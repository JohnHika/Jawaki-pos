import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { LayoutRequestsService } from './layout-requests.service';

describe('LayoutRequestsService', () => {
  const build = (opts: { settings?: any; pending?: any; request?: any } = {}) => {
    const prisma: any = {
      tenant: {
        findUnique: jest.fn().mockResolvedValue({
          id: 't1',
          settings: opts.settings ?? { businessLayout: { profileId: 'bookshop' } },
        }),
        update: jest.fn().mockResolvedValue({}),
      },
      layoutChangeRequest: {
        findFirst: jest.fn().mockResolvedValue(opts.pending ?? null),
        findUnique: jest.fn().mockResolvedValue(opts.request ?? null),
        findMany: jest.fn().mockResolvedValue([]),
        create: jest.fn().mockImplementation(({ data }) => Promise.resolve({ id: 'r1', ...data })),
        update: jest.fn().mockImplementation(({ data, where }) =>
          Promise.resolve({ id: where.id, tenantId: 't1', toProfileId: 'cafe_takeaway', requestedByUserId: 'u1', ...data }),
        ),
      },
    };
    const notifications = { sendToUser: jest.fn().mockResolvedValue(undefined) };
    return { service: new LayoutRequestsService(prisma, notifications as any), prisma, notifications };
  };

  const dto = { toProfileId: 'cafe_takeaway', reason: 'Opening a food counter' };

  it('records the request with the current and the wanted type', async () => {
    const { service, prisma } = build();
    await service.create('t1', 'u1', dto);
    expect(prisma.layoutChangeRequest.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ fromProfileId: 'bookshop', toProfileId: 'cafe_takeaway', requestedByUserId: 'u1' }),
      }),
    );
  });

  it('allows only one waiting request per shop', async () => {
    const { service } = build({ pending: { id: 'p1' } });
    await expect(service.create('t1', 'u1', dto)).rejects.toBeInstanceOf(ConflictException);
  });

  it('refuses a request for the type the shop already has', async () => {
    const { service } = build();
    await expect(service.create('t1', 'u1', { ...dto, toProfileId: 'bookshop' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('cancels only a waiting request of the same shop', async () => {
    const { service, prisma } = build();
    prisma.layoutChangeRequest.findFirst.mockResolvedValue({ id: 'r1', status: 'APPROVED' });
    await expect(service.cancel('t1', 'r1')).rejects.toBeInstanceOf(ConflictException);
    prisma.layoutChangeRequest.findFirst.mockResolvedValue(null);
    await expect(service.cancel('t1', 'r1')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('approving leaves a marker in the shop settings and notifies the owner', async () => {
    const pending = { id: 'r1', tenantId: 't1', status: 'PENDING', toProfileId: 'cafe_takeaway', additionalProfileIds: [], requestedByUserId: 'u1' };
    const { service, prisma, notifications } = build({ request: pending });
    await service.decide({ id: 'a1', email: 'staff@axon.test' }, 'r1', true, 'Welcome');
    expect(prisma.tenant.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { settings: expect.objectContaining({ approvedProfileChange: expect.objectContaining({ profileId: 'cafe_takeaway', requestId: 'r1' }) }) },
      }),
    );
    expect(notifications.sendToUser).toHaveBeenCalledWith(
      'u1',
      expect.objectContaining({ data: expect.objectContaining({ type: 'layout_request_decision' }) }),
      { tenantId: 't1' },
    );
  });

  it('declining writes nothing to the shop and shows the note', async () => {
    const pending = { id: 'r1', tenantId: 't1', status: 'PENDING', toProfileId: 'cafe_takeaway', requestedByUserId: 'u1' };
    const { service, prisma } = build({ request: pending });
    const out: any = await service.decide({ id: 'a1', email: 'staff@axon.test' }, 'r1', false, 'Add a store instead');
    expect(prisma.tenant.update).not.toHaveBeenCalled();
    expect(out.status).toBe('REJECTED');
    expect(out.decisionNote).toBe('Add a store instead');
  });

  it('cannot decide a request twice', async () => {
    const { service } = build({ request: { id: 'r1', status: 'APPROVED' } });
    await expect(service.decide({ id: 'a1', email: 'x@y.z' }, 'r1', true)).rejects.toBeInstanceOf(ConflictException);
  });
});
