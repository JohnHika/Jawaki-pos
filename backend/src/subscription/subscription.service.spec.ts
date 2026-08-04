import { NotFoundException } from '@nestjs/common';
import { SubscriptionService } from './subscription.service';

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
    it('switches a tenant from CORE to ENTERPRISE and updates limits and billing period', async () => {
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
              maxBranches: 10,
              maxUsers: 50,
            }),
          },
        },
      });

      const result = await service.changePlan('tenant-1', 'ENTERPRISE');

      expect(prisma.tenant.findUnique).toHaveBeenCalledWith({
        where: { id: 'tenant-1' },
        select: { id: true },
      });
      expect(prisma.tenant.update).toHaveBeenCalledWith({
        where: { id: 'tenant-1' },
        data: {
          plan: 'ENTERPRISE',
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
        plan: 'ENTERPRISE',
        subscriptionStatus: 'ACTIVE',
        maxBranches: 10,
        maxUsers: 50,
      });

      const updateArgs = prisma.tenant.update.mock.calls[0][0];
      expect(updateArgs.data.currentPeriodEnd.getTime()).toBeGreaterThan(updateArgs.data.currentPeriodStart.getTime());
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
        { id: 'inv-1', plan: 'CORE', amount: 1500 },
        { id: 'inv-2', plan: 'ENTERPRISE', amount: 5000 },
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
});
