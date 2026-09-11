import { NotFoundException } from '@nestjs/common';
import { SubscriptionService, UNLIMITED_PLAN_LIMIT } from './subscription.service';

describe('SubscriptionService', () => {
  const buildPrisma = (overrides: Record<string, any> = {}) => ({
    tenant: {
      findUnique: jest.fn(),
      update: jest.fn(),
      ...overrides.tenant,
    },
    subscriptionInvoice: {
      findMany: jest.fn(),
      ...overrides.subscriptionInvoice,
    },
  });

  const buildService = (overrides: Record<string, any> = {}) => {
    const prisma = buildPrisma(overrides.prisma ?? {});
    return { service: new SubscriptionService(prisma as any), prisma };
  };

  describe('getCurrentPlan', () => {
    it('returns the current subscription plan details for a tenant', async () => {
      const plan = {
        plan: 'CORE',
        subscriptionStatus: 'ACTIVE',
        subscriptionProvider: 'MANUAL',
        subscriptionReference: 'ref-1',
        currentPeriodStart: new Date('2026-08-01T00:00:00Z'),
        currentPeriodEnd: new Date('2026-09-01T00:00:00Z'),
        setupFeePaidAt: new Date('2026-08-01T00:00:00Z'),
        maxBranches: 3,
        maxUsers: 10,
        activationStatus: 'ACTIVE',
        activationPaidAt: new Date('2026-08-01T00:00:00Z'),
      };
      const { service, prisma } = buildService({
        prisma: { tenant: { findUnique: jest.fn().mockResolvedValue(plan) } },
      });

      const result = await service.getCurrentPlan('tenant-1');

      expect(result).toMatchObject({
        ...plan,
        planMeta: expect.objectContaining({ planId: 'CORE' }),
        availablePlans: expect.arrayContaining([
          expect.objectContaining({ planId: 'TRIAL' }),
          expect.objectContaining({ planId: 'CORE' }),
          expect.objectContaining({ planId: 'BUSINESS' }),
          expect.objectContaining({ planId: 'ENTERPRISE' }),
        ]),
      });

      expect(prisma.tenant.findUnique).toHaveBeenCalledWith({
        where: { id: 'tenant-1' },
        select: {
          plan: true,
          subscriptionStatus: true,
          subscriptionProvider: true,
          subscriptionReference: true,
          currentPeriodStart: true,
          currentPeriodEnd: true,
          setupFeePaidAt: true,
          maxBranches: true,
          maxUsers: true,
          activationStatus: true,
          activationPaidAt: true,
        },
      });
    });

    it('throws NotFoundException when the tenant does not exist', async () => {
      const { service, prisma } = buildService({
        prisma: { tenant: { findUnique: jest.fn().mockResolvedValue(null) } },
      });

      await expect(service.getCurrentPlan('missing-tenant')).rejects.toBeInstanceOf(NotFoundException);
      expect(prisma.tenant.findUnique).toHaveBeenCalledWith({
        where: { id: 'missing-tenant' },
        select: expect.any(Object),
      });
    });
  });

  describe('changePlan', () => {
    it('switches a tenant from CORE to BUSINESS and updates limits and billing period', async () => {
      const { service, prisma } = buildService({
        prisma: {
          tenant: {
            findUnique: jest.fn().mockResolvedValue({ id: 'tenant-1' }),
            update: jest.fn().mockResolvedValue({
              id: 'tenant-1',
              plan: 'BUSINESS',
              subscriptionStatus: 'ACTIVE',
              currentPeriodStart: expect.any(Date),
              currentPeriodEnd: expect.any(Date),
              maxBranches: 10,
              maxUsers: 50,
            }),
          },
        },
      });

      const result = await service.changePlan('tenant-1', 'BUSINESS');

      expect(prisma.tenant.findUnique).toHaveBeenCalledWith({
        where: { id: 'tenant-1' },
        select: { id: true },
      });
      expect(prisma.tenant.update).toHaveBeenCalledWith({
        where: { id: 'tenant-1' },
        data: {
          plan: 'BUSINESS',
          subscriptionStatus: 'ACTIVE',
          currentPeriodStart: expect.any(Date),
          currentPeriodEnd: expect.any(Date),
          maxBranches: 10,
          maxUsers: 50,
        },
        select: {
          plan: true,
          subscriptionStatus: true,
          currentPeriodStart: true,
          currentPeriodEnd: true,
          maxBranches: true,
          maxUsers: true,
        },
      });
      expect(result).toMatchObject({
        plan: 'BUSINESS',
        subscriptionStatus: 'ACTIVE',
        maxBranches: 10,
        maxUsers: 50,
      });

      const updateArgs = prisma.tenant.update.mock.calls[0][0];
      expect(updateArgs.data.currentPeriodEnd.getTime()).toBeGreaterThan(updateArgs.data.currentPeriodStart.getTime());
    });

    it('switches a tenant to ENTERPRISE with unlimited branch and user limits', async () => {
      const { service, prisma } = buildService({
        prisma: {
          tenant: {
            findUnique: jest.fn().mockResolvedValue({ id: 'tenant-1' }),
            update: jest.fn().mockResolvedValue({
              id: 'tenant-1',
              plan: 'ENTERPRISE',
              subscriptionStatus: 'ACTIVE',
              currentPeriodStart: expect.any(Date),
              currentPeriodEnd: expect.any(Date),
              maxBranches: UNLIMITED_PLAN_LIMIT,
              maxUsers: UNLIMITED_PLAN_LIMIT,
            }),
          },
        },
      });

      const result = await service.changePlan('tenant-1', 'ENTERPRISE');

      expect(prisma.tenant.update).toHaveBeenCalledWith({
        where: { id: 'tenant-1' },
        data: {
          plan: 'ENTERPRISE',
          subscriptionStatus: 'ACTIVE',
          currentPeriodStart: expect.any(Date),
          currentPeriodEnd: expect.any(Date),
          maxBranches: UNLIMITED_PLAN_LIMIT,
          maxUsers: UNLIMITED_PLAN_LIMIT,
        },
        select: {
          plan: true,
          subscriptionStatus: true,
          currentPeriodStart: true,
          currentPeriodEnd: true,
          maxBranches: true,
          maxUsers: true,
        },
      });
      expect(result).toMatchObject({
        plan: 'ENTERPRISE',
        subscriptionStatus: 'ACTIVE',
        maxBranches: UNLIMITED_PLAN_LIMIT,
        maxUsers: UNLIMITED_PLAN_LIMIT,
      });
      // Unlimited must be a large positive finite sentinel: consumers do
      // arithmetic/comparison on these values and a mobile formatter treats
      // >= 1000 as 'Unlimited'.
      expect(UNLIMITED_PLAN_LIMIT).toBeGreaterThanOrEqual(1000);
    });

    it('throws NotFoundException for an invalid plan name', async () => {
      const { service, prisma } = buildService();

      await expect(service.changePlan('tenant-1', 'INVALID')).rejects.toBeInstanceOf(NotFoundException);
      expect(prisma.tenant.findUnique).not.toHaveBeenCalled();
      expect(prisma.tenant.update).not.toHaveBeenCalled();
    });

    it('throws NotFoundException when the tenant does not exist', async () => {
      const { service, prisma } = buildService({
        prisma: { tenant: { findUnique: jest.fn().mockResolvedValue(null) } },
      });

      await expect(service.changePlan('missing-tenant', 'ENTERPRISE')).rejects.toBeInstanceOf(NotFoundException);
      expect(prisma.tenant.update).not.toHaveBeenCalled();
    });
  });

  describe('listInvoices', () => {
    it('returns subscription invoices for a tenant ordered by newest first', async () => {
      const invoices = [
        { id: 'inv-1', plan: 'CORE', amount: 3200 },
        { id: 'inv-2', plan: 'BUSINESS', amount: 6500 },
        { id: 'inv-3', plan: 'ENTERPRISE', amount: 10000 },
      ];
      const { service, prisma } = buildService({
        prisma: {
          tenant: { findUnique: jest.fn().mockResolvedValue({ id: 'tenant-1' }) },
          subscriptionInvoice: { findMany: jest.fn().mockResolvedValue(invoices) },
        },
      });

      await expect(service.listInvoices('tenant-1')).resolves.toEqual(invoices);
      expect(prisma.subscriptionInvoice.findMany).toHaveBeenCalledWith({
        where: { tenantId: 'tenant-1' },
        orderBy: { createdAt: 'desc' },
      });
    });
  });

  describe('getFeatureAccess', () => {
    const buildForPlan = (plan: string, currentPeriodStart = new Date()) =>
      buildService({
        prisma: {
          tenant: {
            findUnique: jest.fn().mockResolvedValue({
              plan,
              currentPeriodStart,
              createdAt: currentPeriodStart,
            }),
          },
        },
      }).service;

    it('BUSINESS includes its feature set outright (no taste window)', async () => {
      const service = buildForPlan('BUSINESS', new Date(Date.now() - 30 * 86_400_000));

      for (const feature of [
        'multi_branch_dashboard',
        'multi_branch_transfers',
        'advanced_reports',
        'ai_insights',
        'supplier_management',
        'whatsapp_bot',
        'whatsapp_promotions',
        'staff_performance',
        'customer_360',
      ] as const) {
        await expect(service.getFeatureAccess('tenant-1', feature)).resolves.toMatchObject({
          allowed: true,
        });
      }
    });

    it('BUSINESS still denies the strictly ENTERPRISE-only features', async () => {
      const service = buildForPlan('BUSINESS');

      for (const feature of [
        'ai_fraud_detection',
        'ai_supply_chain',
        'priority_support',
      ] as const) {
        await expect(service.getFeatureAccess('tenant-1', feature)).resolves.toEqual({
          allowed: false,
          reason: 'enterprise_only',
        });
      }
    });

    it('ENTERPRISE allows every feature', async () => {
      const service = buildForPlan('ENTERPRISE');

      for (const feature of ['ai_fraud_detection', 'ai_supply_chain', 'priority_support'] as const) {
        await expect(service.getFeatureAccess('tenant-1', feature)).resolves.toMatchObject({
          allowed: true,
        });
      }
    });

    it('CORE keeps the 7-day taste window for taste features', async () => {
      const tasteFeature = 'ai_insights';

      const freshCore = buildForPlan('CORE', new Date(Date.now() - 1 * 86_400_000));
      await expect(freshCore.getFeatureAccess('tenant-1', tasteFeature)).resolves.toMatchObject({
        allowed: true,
        reason: 'taste_active',
      });

      const spentCore = buildForPlan('CORE', new Date(Date.now() - 10 * 86_400_000));
      await expect(spentCore.getFeatureAccess('tenant-1', tasteFeature)).resolves.toMatchObject({
        allowed: false,
        reason: 'taste_used',
      });
    });
  });
});
