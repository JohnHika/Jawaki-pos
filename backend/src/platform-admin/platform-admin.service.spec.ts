import { ConflictException, NotFoundException } from '@nestjs/common';
import { AuditService } from '../audit/audit.service';
import { PlatformAdminService } from './platform-admin.service';

describe('PlatformAdminService', () => {
  const buildPrisma = (overrides: Record<string, any> = {}) => ({
    tenant: {
      groupBy: jest.fn(),
      findMany: jest.fn(),
      findUnique: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
      count: jest.fn(),
      ...(overrides.tenant ?? {}),
    },
    subscriptionInvoice: {
      count: jest.fn(),
      findMany: jest.fn(),
      findUnique: jest.fn(),
      update: jest.fn(),
      create: jest.fn(),
      ...(overrides.subscriptionInvoice ?? {}),
    },
    subscriptionPaymentClaim: {
      findMany: jest.fn(),
    },
  });

  const buildService = (overrides: Record<string, any> = {}) => {
    const prisma = buildPrisma(overrides.prisma ?? {});
    const auditService = {
      record: jest.fn().mockResolvedValue(undefined),
    } as unknown as AuditService;
    const service = new PlatformAdminService(prisma as any, auditService);
    return { service, prisma, auditService };
  };

  const actor = { id: 'admin-1', email: 'admin@jawaki.co' };

  describe('getDashboard', () => {
    it('computes counts by status, MRR and ARR from PLAN_PRICING for non-trial ACTIVE tenants', async () => {
      const { service, prisma } = buildService({
        prisma: {
          tenant: {
            groupBy: jest.fn().mockResolvedValue([
              { subscriptionStatus: 'ACTIVE', _count: 2 },
              { subscriptionStatus: 'TRIAL', _count: 3 },
              { subscriptionStatus: 'PAST_DUE', _count: 1 },
            ]),
            // 2 CORE (3200 each) + 1 ENTERPRISE (5000) => MRR 11400
            findMany: jest.fn().mockResolvedValue([
              { plan: 'CORE' },
              { plan: 'CORE' },
              { plan: 'ENTERPRISE' },
            ]),
          },
        },
      });
      prisma.subscriptionInvoice.count.mockResolvedValue(4);
      prisma.subscriptionInvoice.findMany.mockResolvedValue([
        {
          id: 'inv-1',
          tenantId: 't1',
          plan: 'CORE',
          amount: 3200,
          paidAt: new Date('2026-09-01T10:00:00Z'),
          provider: 'MPESA_MANUAL',
          reference: 'SBX123',
          tenant: { name: 'Kams Shop' },
        },
      ]);

      const result = await service.getDashboard();

      expect(result.mrrKes).toBe(11400);
      expect(result.arrKes).toBe(11400 * 12);
      expect(result.tenants).toEqual({
        ACTIVE: 2,
        TRIAL: 3,
        PAST_DUE: 1,
        SUSPENDED: 0,
        CANCELLED: 0,
      });
      expect(result.failedPayments).toBe(4);
      expect(result.recentPayments).toHaveLength(1);
      expect(result.recentPayments[0]).toMatchObject({
        tenantName: 'Kams Shop',
        amount: 3200,
      });
      // failedPayments = PENDING invoices older than 7 days
      expect(prisma.subscriptionInvoice.count).toHaveBeenCalledWith({
        where: { status: 'PENDING', createdAt: { lt: expect.any(Date) } },
      });
    });

    it('treats TRIAL tenants as zero MRR and maps unknown statuses to tenantsUnmappedStatus', async () => {
      const { service, prisma } = buildService({
        prisma: {
          tenant: {
            groupBy: jest.fn().mockResolvedValue([
              { subscriptionStatus: 'ACTIVE', _count: 1 },
              { subscriptionStatus: 'WEIRD_STATUS', _count: 5 },
            ]),
            findMany: jest.fn().mockResolvedValue([{ plan: 'TRIAL' }]),
          },
          subscriptionInvoice: {
            findMany: jest.fn().mockResolvedValue([]),
          },
        },
      });

      const result = await service.getDashboard();

      expect(result.mrrKes).toBe(0); // TRIAL pricing is 0
      expect(result.tenants.ACTIVE).toBe(1);
      expect(result.tenantsUnmappedStatus).toBe(5);
    });
  });

  describe('extendTenant', () => {
    it('pushes currentPeriodEnd forward from the current end and writes an audit record', async () => {
      const currentEnd = new Date('2026-09-10T00:00:00Z');
      const { service, prisma, auditService } = buildService({
        prisma: {
          tenant: {
            findUnique: jest.fn().mockResolvedValue({
              id: 't1',
              subscriptionStatus: 'ACTIVE',
              currentPeriodEnd: currentEnd,
            }),
            update: jest.fn().mockResolvedValue({ id: 't1' }),
          },
        },
      });

      await service.extendTenant('t1', 7, actor);

      const call = prisma.tenant.update.mock.calls[0][0];
      const expected = new Date(currentEnd.getTime() + 7 * 86_400_000);
      expect((call.data.currentPeriodEnd as Date).getTime()).toBe(expected.getTime());
      expect(auditService.record).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'PLATFORM_ADMIN_TENANT_EXTENDED',
          entityType: 'Tenant',
          entityId: 't1',
          userId: null,
        }),
      );
    });

    it('extends from now when the current period already expired', async () => {
      const { service, prisma } = buildService({
        prisma: {
          tenant: {
            findUnique: jest.fn().mockResolvedValue({
              id: 't1',
              subscriptionStatus: 'ACTIVE',
              currentPeriodEnd: new Date('2020-01-01T00:00:00Z'),
            }),
            update: jest.fn().mockResolvedValue({ id: 't1' }),
          },
        },
      });

      await service.extendTenant('t1', 5, actor);

      const call = prisma.tenant.update.mock.calls[0][0];
      const expected = new Date(Date.now() + 5 * 86_400_000);
      // Allow a small clock skew between the two Date.now() reads.
      expect((call.data.currentPeriodEnd as Date).getTime()).toBeGreaterThanOrEqual(
        expected.getTime() - 1000,
      );
      expect((call.data.currentPeriodEnd as Date).getTime()).toBeLessThanOrEqual(
        expected.getTime() + 1000,
      );
    });

    it('throws NotFoundException for an unknown tenant', async () => {
      const { service } = buildService({
        prisma: { tenant: { findUnique: jest.fn().mockResolvedValue(null) } },
      });

      await expect(service.extendTenant('missing', 7, actor)).rejects.toBeInstanceOf(
        NotFoundException,
      );
    });
  });

  describe('creditTenant', () => {
    // Convention: negative amount, status PAID, provider CREDIT.
    it('creates a negative-amount PAID invoice with provider CREDIT and audits it', async () => {
      const { service, prisma, auditService } = buildService({
        prisma: {
          tenant: {
            findUnique: jest.fn().mockResolvedValue({
              id: 't1',
              subscriptionStatus: 'ACTIVE',
              currentPeriodEnd: null,
            }),
          },
          subscriptionInvoice: {
            create: jest.fn().mockResolvedValue({
              id: 'inv-credit-1',
              tenantId: 't1',
              plan: 'CREDIT',
              amount: -1500,
              status: 'PAID',
              provider: 'CREDIT',
            }),
          },
        },
      });

      const invoice = await service.creditTenant('t1', 1500, 'Goodwill', actor);

      expect(invoice).toMatchObject({ amount: -1500, status: 'PAID', provider: 'CREDIT' });
      expect(prisma.subscriptionInvoice.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          tenantId: 't1',
          plan: 'CREDIT',
          amount: -1500,
          status: 'PAID',
          provider: 'CREDIT',
          reference: 'CREDIT:Goodwill',
        }),
      });
      expect(auditService.record).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'PLATFORM_ADMIN_TENANT_CREDITED',
          entityType: 'SubscriptionInvoice',
        }),
      );
    });
  });

  describe('setSuspended / setReactivated', () => {
    it('sets SUSPENDED and audits', async () => {
      const { service, prisma, auditService } = buildService({
        prisma: {
          tenant: {
            findUnique: jest.fn().mockResolvedValue({
              id: 't1',
              subscriptionStatus: 'ACTIVE',
              currentPeriodEnd: null,
            }),
            update: jest.fn().mockResolvedValue({ id: 't1', subscriptionStatus: 'SUSPENDED' }),
          },
        },
      });

      const result = await service.setSuspended('t1', actor);

      expect(result).toEqual({ id: 't1', subscriptionStatus: 'SUSPENDED' });
      expect(prisma.tenant.update).toHaveBeenCalledWith({
        where: { id: 't1' },
        data: { subscriptionStatus: 'SUSPENDED' },
        select: expect.any(Object),
      });
      expect(auditService.record).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'PLATFORM_ADMIN_TENANT_SUSPENDED' }),
      );
    });

    it('sets ACTIVE on reactivate and audits', async () => {
      const { service, prisma, auditService } = buildService({
        prisma: {
          tenant: {
            findUnique: jest.fn().mockResolvedValue({
              id: 't1',
              subscriptionStatus: 'SUSPENDED',
              currentPeriodEnd: null,
            }),
            update: jest.fn().mockResolvedValue({ id: 't1', subscriptionStatus: 'ACTIVE' }),
          },
        },
      });

      const result = await service.setReactivated('t1', actor);

      expect(result.subscriptionStatus).toBe('ACTIVE');
      expect(auditService.record).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'PLATFORM_ADMIN_TENANT_REACTIVATED' }),
      );
    });
  });

  describe('markInvoicePaid', () => {
    it('marks paid, records the mpesa reference, and reactivates a PAST_DUE tenant', async () => {
      const { service, prisma, auditService } = buildService({
        prisma: {
          subscriptionInvoice: {
            findUnique: jest.fn().mockResolvedValue({
              id: 'inv-1',
              tenantId: 't1',
              status: 'PENDING',
              provider: 'MPESA_MANUAL',
              reference: null,
            }),
            update: jest.fn().mockResolvedValue({ id: 'inv-1', status: 'PAID' }),
          },
          tenant: {
            updateMany: jest.fn().mockResolvedValue({ count: 1 }),
          },
        },
      });

      await service.markInvoicePaid('inv-1', 'SBX12AB34CD', actor);

      expect(prisma.subscriptionInvoice.update).toHaveBeenCalledWith({
        where: { id: 'inv-1' },
        data: expect.objectContaining({ status: 'PAID', reference: 'SBX12AB34CD' }),
      });
      expect(prisma.tenant.updateMany).toHaveBeenCalledWith({
        where: { id: 't1', subscriptionStatus: { in: ['PAST_DUE', 'SUSPENDED'] } },
        data: { subscriptionStatus: 'ACTIVE' },
      });
      expect(auditService.record).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'PLATFORM_ADMIN_INVOICE_MARKED_PAID' }),
      );
    });

    it('rejects marking an already-PAID invoice', async () => {
      const { service } = buildService({
        prisma: {
          subscriptionInvoice: {
            findUnique: jest.fn().mockResolvedValue({
              id: 'inv-1',
              tenantId: 't1',
              status: 'PAID',
            }),
          },
        },
      });

      await expect(service.markInvoicePaid('inv-1', undefined, actor)).rejects.toBeInstanceOf(
        ConflictException,
      );
    });
  });
});