import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
} from '@nestjs/common';
import { PartnersService, PartnerActor } from './partners.service';

const JAWAKI = { id: 't-jawaki', name: 'Jawaki', slug: 'jawaki', logo: null };
const LEVISA = { id: 't-levisa', name: 'Levisa', slug: 'levisa', logo: null };
const OTHER = { id: 't-other', name: 'Other', slug: 'other', logo: null };

const jawakiAdmin: PartnerActor = { sub: 'u1', role: 'ADMIN', tenantId: JAWAKI.id };
const levisaAdmin: PartnerActor = { sub: 'u2', role: 'MANAGER', tenantId: LEVISA.id };
const outsider: PartnerActor = { sub: 'u3', role: 'ADMIN', tenantId: OTHER.id };

function partnership(over: Record<string, any> = {}) {
  return {
    id: 'p1',
    requesterTenantId: JAWAKI.id,
    addresseeTenantId: LEVISA.id,
    requestedById: 'u1',
    message: null,
    status: 'PENDING',
    respondedAt: null,
    createdAt: new Date('2026-01-01T00:00:00Z'),
    updatedAt: new Date('2026-01-01T00:00:00Z'),
    requesterTenant: JAWAKI,
    addresseeTenant: LEVISA,
    ...over,
  };
}

describe('PartnersService', () => {
  let prisma: any;
  let notifications: { sendToTenantRoles: jest.Mock };
  let service: PartnersService;

  beforeEach(() => {
    prisma = {
      tenant: { findUnique: jest.fn() },
      user: { findUnique: jest.fn() },
      tradePartnership: {
        findUnique: jest.fn(),
        findFirst: jest.fn(),
        findMany: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
      partnerMessage: {
        findFirst: jest.fn(),
        findMany: jest.fn().mockResolvedValue([]),
        count: jest.fn(),
        create: jest.fn(),
        updateMany: jest.fn(),
      },
    };
    notifications = { sendToTenantRoles: jest.fn().mockResolvedValue(undefined) };
    service = new PartnersService(prisma, notifications as any);
  });

  describe('createRequest', () => {
    it('rejects connecting to your own business', async () => {
      prisma.tenant.findUnique.mockResolvedValue({ ...JAWAKI, isActive: true });
      await expect(
        service.createRequest(jawakiAdmin, { companyCode: 'jawaki' }),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.tradePartnership.create).not.toHaveBeenCalled();
    });

    it('returns 404 for an unknown company code', async () => {
      prisma.tenant.findUnique.mockResolvedValue(null);
      const err: HttpException = await service
        .createRequest(jawakiAdmin, { companyCode: '  NOPE ' })
        .catch((e) => e);
      expect(err).toBeInstanceOf(HttpException);
      expect(err.getStatus()).toBe(404);
      expect(prisma.tenant.findUnique).toHaveBeenCalledWith(
        expect.objectContaining({ where: { slug: 'nope' } }),
      );
    });

    it('rejects a duplicate pending request in either direction with 409', async () => {
      prisma.tenant.findUnique.mockResolvedValue({ ...LEVISA, isActive: true });
      // Levisa already asked Jawaki
      prisma.tradePartnership.findFirst.mockResolvedValue(
        partnership({ requesterTenantId: LEVISA.id, addresseeTenantId: JAWAKI.id }),
      );
      await expect(
        service.createRequest(jawakiAdmin, { companyCode: 'levisa' }),
      ).rejects.toBeInstanceOf(ConflictException);

      prisma.tradePartnership.findFirst.mockResolvedValue(partnership({ status: 'ACCEPTED' }));
      await expect(
        service.createRequest(jawakiAdmin, { companyCode: 'levisa' }),
      ).rejects.toBeInstanceOf(ConflictException);
    });

    it('creates a request and notifies the addressee admins and managers', async () => {
      prisma.tenant.findUnique.mockResolvedValue({ ...LEVISA, isActive: true });
      prisma.tradePartnership.findFirst.mockResolvedValue(null);
      prisma.tradePartnership.create.mockResolvedValue(partnership());
      const res = await service.createRequest(jawakiAdmin, {
        companyCode: 'levisa',
        message: 'hi',
      });
      expect(res.direction).toBe('outgoing');
      expect(res.partner.slug).toBe('levisa');
      expect(notifications.sendToTenantRoles).toHaveBeenCalledWith(
        LEVISA.id,
        ['ADMIN', 'MANAGER'],
        expect.objectContaining({
          title: 'New trade partner request',
          body: 'Jawaki wants to connect with you',
          data: { type: 'partner_request', partnershipId: 'p1' },
        }),
      );
    });

    it('re-opens a declined request, flipping requester/addressee to the caller', async () => {
      // Jawaki previously asked Levisa, who declined. Now Levisa asks Jawaki.
      prisma.tenant.findUnique.mockResolvedValue({ ...JAWAKI, isActive: true });
      prisma.tradePartnership.findFirst.mockResolvedValue(partnership({ status: 'DECLINED' }));
      prisma.tradePartnership.update.mockResolvedValue(
        partnership({
          requesterTenantId: LEVISA.id,
          addresseeTenantId: JAWAKI.id,
          requesterTenant: LEVISA,
          addresseeTenant: JAWAKI,
        }),
      );
      const res = await service.createRequest(levisaAdmin, { companyCode: 'jawaki' });
      expect(prisma.tradePartnership.create).not.toHaveBeenCalled();
      expect(prisma.tradePartnership.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'p1' },
          data: expect.objectContaining({
            requesterTenantId: LEVISA.id,
            addresseeTenantId: JAWAKI.id,
            status: 'PENDING',
            respondedAt: null,
          }),
        }),
      );
      expect(res.status).toBe('PENDING');
      expect(res.direction).toBe('outgoing');
    });
  });

  describe('accept / decline', () => {
    it('only the addressee may accept', async () => {
      prisma.tradePartnership.findUnique.mockResolvedValue(partnership());
      await expect(service.accept(jawakiAdmin, 'p1')).rejects.toBeInstanceOf(ForbiddenException);
      expect(prisma.tradePartnership.update).not.toHaveBeenCalled();

      prisma.tradePartnership.update.mockResolvedValue(partnership({ status: 'ACCEPTED' }));
      const res = await service.accept(levisaAdmin, 'p1');
      expect(res.status).toBe('ACCEPTED');
      expect(res.direction).toBe('incoming');
      expect(notifications.sendToTenantRoles).toHaveBeenCalledWith(
        JAWAKI.id,
        ['ADMIN', 'MANAGER'],
        expect.objectContaining({
          body: 'Levisa accepted your request',
          data: { type: 'partner_accepted', partnershipId: 'p1' },
        }),
      );
    });

    it('does not notify on decline and requires PENDING status', async () => {
      prisma.tradePartnership.findUnique.mockResolvedValue(partnership());
      prisma.tradePartnership.update.mockResolvedValue(partnership({ status: 'DECLINED' }));
      await service.decline(levisaAdmin, 'p1');
      expect(notifications.sendToTenantRoles).not.toHaveBeenCalled();

      prisma.tradePartnership.findUnique.mockResolvedValue(partnership({ status: 'ACCEPTED' }));
      await expect(service.decline(levisaAdmin, 'p1')).rejects.toBeInstanceOf(ConflictException);
    });
  });

  describe('messaging', () => {
    it('is blocked unless the partnership is ACCEPTED', async () => {
      prisma.tradePartnership.findUnique.mockResolvedValue(partnership({ status: 'PENDING' }));
      await expect(
        service.sendMessage(jawakiAdmin, 'p1', { body: 'hello' }),
      ).rejects.toBeInstanceOf(ForbiddenException);
      await expect(service.getMessages(jawakiAdmin, 'p1')).rejects.toBeInstanceOf(
        ForbiddenException,
      );
      expect(prisma.partnerMessage.create).not.toHaveBeenCalled();
    });

    it('sends a message, uses the sender full name and notifies the other business', async () => {
      prisma.tradePartnership.findUnique.mockResolvedValue(partnership({ status: 'ACCEPTED' }));
      prisma.user.findUnique.mockResolvedValue({
        firstName: 'Jane',
        lastName: 'Doe',
        email: 'j@x.com',
      });
      prisma.partnerMessage.create.mockImplementation(async ({ data }: any) => ({
        id: 'm1',
        createdAt: new Date('2026-01-02T00:00:00Z'),
        ...data,
      }));
      const long = 'x'.repeat(300);
      const res = await service.sendMessage(jawakiAdmin, 'p1', { body: long });
      expect(res).toMatchObject({ id: 'm1', fromMe: true, senderName: 'Jane Doe' });
      expect(notifications.sendToTenantRoles).toHaveBeenCalledWith(
        LEVISA.id,
        ['ADMIN', 'MANAGER'],
        expect.objectContaining({
          title: 'Jawaki',
          body: 'x'.repeat(120),
          data: { type: 'partner_message', partnershipId: 'p1' },
        }),
      );
    });

    it('marks the other business messages as read when fetching', async () => {
      prisma.tradePartnership.findUnique.mockResolvedValue(partnership({ status: 'ACCEPTED' }));
      prisma.partnerMessage.findMany.mockResolvedValue([
        { id: 'm2', body: 'b', createdAt: new Date('2026-01-02'), senderTenantId: JAWAKI.id, senderName: 'A' },
        { id: 'm1', body: 'a', createdAt: new Date('2026-01-01'), senderTenantId: LEVISA.id, senderName: 'B' },
      ]);
      const res = await service.getMessages(jawakiAdmin, 'p1');
      // latest-N query is desc; response must be ascending
      expect(res.messages.map((m) => m.id)).toEqual(['m1', 'm2']);
      expect(res.messages.map((m) => m.fromMe)).toEqual([false, true]);
      expect(prisma.partnerMessage.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { partnershipId: 'p1', senderTenantId: LEVISA.id, readAt: null },
        }),
      );
    });
  });

  describe('access control', () => {
    it('blocks cross-tenant access with a 404 on every partnership route', async () => {
      prisma.tradePartnership.findUnique.mockResolvedValue(partnership({ status: 'ACCEPTED' }));
      const calls = [
        () => service.accept(outsider, 'p1'),
        () => service.decline(outsider, 'p1'),
        () => service.remove(outsider, 'p1'),
        () => service.getMessages(outsider, 'p1'),
        () => service.sendMessage(outsider, 'p1', { body: 'hi' }),
      ];
      for (const call of calls) {
        const err: HttpException = await call().catch((e) => e);
        expect(err).toBeInstanceOf(HttpException);
        expect(err.getStatus()).toBe(404);
      }
      expect(prisma.tradePartnership.update).not.toHaveBeenCalled();
      expect(prisma.partnerMessage.create).not.toHaveBeenCalled();
    });

    it('rejects cashiers and supervisors with 403', async () => {
      const cashier: PartnerActor = { sub: 'c', role: 'CASHIER', tenantId: JAWAKI.id };
      const supervisor: PartnerActor = { sub: 's', role: 'SUPERVISOR', tenantId: JAWAKI.id };
      for (const u of [cashier, supervisor]) {
        await expect(service.list(u)).rejects.toBeInstanceOf(ForbiddenException);
        await expect(
          service.createRequest(u, { companyCode: 'levisa' }),
        ).rejects.toBeInstanceOf(ForbiddenException);
        await expect(service.getMessages(u, 'p1')).rejects.toBeInstanceOf(ForbiddenException);
      }
    });

    it('either side may remove a partnership', async () => {
      prisma.tradePartnership.findUnique.mockResolvedValue(partnership());
      prisma.tradePartnership.update.mockResolvedValue({});
      // requester withdrawing own pending request
      await expect(service.remove(jawakiAdmin, 'p1')).resolves.toEqual({
        id: 'p1',
        status: 'REMOVED',
      });
      await expect(service.remove(levisaAdmin, 'p1')).resolves.toBeDefined();
    });
  });

  describe('list', () => {
    it('puts incoming pending first, then accepted by last activity', async () => {
      prisma.tradePartnership.findMany.mockResolvedValue([
        partnership({ id: 'a-old', status: 'ACCEPTED', addresseeTenant: LEVISA }),
        partnership({
          id: 'incoming',
          requesterTenantId: OTHER.id,
          requesterTenant: OTHER,
          addresseeTenantId: JAWAKI.id,
          addresseeTenant: JAWAKI,
        }),
        partnership({
          id: 'a-new',
          status: 'ACCEPTED',
          createdAt: new Date('2026-02-01'),
        }),
      ]);
      prisma.partnerMessage.findFirst.mockResolvedValue(null);
      prisma.partnerMessage.count.mockResolvedValue(2);
      const { partners } = await service.list(jawakiAdmin);
      expect(partners.map((p) => p.id)).toEqual(['incoming', 'a-new', 'a-old']);
      expect(partners[0].direction).toBe('incoming');
      expect(partners[1].unreadCount).toBe(2);
    });
  });
});
