import { AiBillingService } from './ai-billing.service';

/**
 * AI access is plan-based: every Axon POS plan (CORE, BUSINESS,
 * ENTERPRISE) includes the AI assistant. TRIAL tenants do not.
 * AI_BILLING_DISABLED (anything other than the literal string 'false')
 * short-circuits everything to free access for local/dev environments.
 */
describe('AiBillingService', () => {
  const ORIGINAL_BILLING_DISABLED = process.env.AI_BILLING_DISABLED;

  afterEach(() => {
    if (ORIGINAL_BILLING_DISABLED === undefined) {
      delete process.env.AI_BILLING_DISABLED;
    } else {
      process.env.AI_BILLING_DISABLED = ORIGINAL_BILLING_DISABLED;
    }
  });

  const buildPrisma = (overrides: Record<string, any> = {}) => ({
    branch: {
      findUnique: jest.fn(),
      ...overrides.branch,
    },
    tenant: {
      findUnique: jest.fn(),
      ...overrides.tenant,
    },
    aiSubscription: {
      findUnique: jest.fn(),
      ...overrides.aiSubscription,
    },
  });

  const buildService = (overrides: Record<string, any> = {}) => {
    const prisma = buildPrisma(overrides.prisma ?? {});
    const paystack = {
      initializeTransaction: jest.fn(),
      chargeAuthorization: jest.fn(),
    };
    return {
      service: new AiBillingService(prisma as any, paystack as any),
      prisma,
    };
  };

  const buildForPlan = (plan: unknown) =>
    buildService({
      prisma: {
        branch: {
          findUnique: jest.fn().mockResolvedValue({ tenantId: 'tenant-1' }),
        },
        tenant: {
          findUnique: jest.fn().mockResolvedValue({ plan }),
        },
      },
    });

  describe('canUseAi', () => {
    beforeEach(() => {
      process.env.AI_BILLING_DISABLED = 'false';
    });

    it('ENTERPRISE includes AI', async () => {
      const { service } = buildForPlan('ENTERPRISE');

      await expect(service.canUseAi('branch-1')).resolves.toBe(true);
    });

    it('BUSINESS includes AI', async () => {
      const { service } = buildForPlan('BUSINESS');

      await expect(service.canUseAi('branch-1')).resolves.toBe(true);
    });

    it('CORE includes AI (no taste window)', async () => {
      const { service } = buildForPlan('CORE');

      await expect(service.canUseAi('branch-1')).resolves.toBe(true);
    });

    it('normalizes the plan name before matching (lowercase/whitespace)', async () => {
      const { service } = buildForPlan('business');

      await expect(service.canUseAi('branch-1')).resolves.toBe(true);
    });

    it('TRIAL does not include AI', async () => {
      const { service } = buildForPlan('TRIAL');

      await expect(service.canUseAi('branch-1')).resolves.toBe(false);
    });

    it('treats a missing plan as TRIAL', async () => {
      const { service } = buildForPlan(null);

      await expect(service.canUseAi('branch-1')).resolves.toBe(false);
    });

    it('returns false for an unknown/missing branch', async () => {
      const { service, prisma } = buildService({
        prisma: { branch: { findUnique: jest.fn().mockResolvedValue(null) } },
      });

      await expect(service.canUseAi('missing-branch')).resolves.toBe(false);
      expect(prisma.tenant.findUnique).not.toHaveBeenCalled();
    });

    it('returns false when the branch tenant no longer exists', async () => {
      const { service } = buildService({
        prisma: {
          branch: {
            findUnique: jest.fn().mockResolvedValue({ tenantId: 'tenant-1' }),
          },
          tenant: { findUnique: jest.fn().mockResolvedValue(null) },
        },
      });

      await expect(service.canUseAi('branch-1')).resolves.toBe(false);
    });

    it('looks the branch up by id and reads its tenant plan', async () => {
      const { service, prisma } = buildForPlan('CORE');

      await service.canUseAi('branch-1');

      expect(prisma.branch.findUnique).toHaveBeenCalledWith({
        where: { id: 'branch-1' },
        select: { tenantId: true },
      });
      expect(prisma.tenant.findUnique).toHaveBeenCalledWith({
        where: { id: 'tenant-1' },
        select: { plan: true },
      });
    });

    it('AI_BILLING_DISABLED short-circuits to true without touching the database', async () => {
      process.env.AI_BILLING_DISABLED = 'true';
      const { service, prisma } = buildService();

      await expect(service.canUseAi('branch-1')).resolves.toBe(true);
      expect(prisma.branch.findUnique).not.toHaveBeenCalled();
      expect(prisma.tenant.findUnique).not.toHaveBeenCalled();
    });
  });

  describe('getStatus', () => {
    beforeEach(() => {
      process.env.AI_BILLING_DISABLED = 'false';
    });

    it('explains plan inclusion when there is no legacy subscription record', async () => {
      const { service } = buildService({
        prisma: {
          aiSubscription: { findUnique: jest.fn().mockResolvedValue(null) },
        },
      });

      const status = await service.getStatus('branch-1');

      expect(status).toMatchObject({
        hasSubscription: false,
        status: null,
        message: 'The AI assistant is included in every Axon POS plan.',
      });
    });
  });
});
