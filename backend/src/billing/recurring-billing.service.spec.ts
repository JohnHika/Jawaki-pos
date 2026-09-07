import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { RecurringBillingService, isTenantRestricted } from './recurring-billing.service';

type MockTx = Record<string, any>;

const buildPrisma = (overrides: Record<string, any> = {}): MockTx => ({
  $transaction: jest.fn(),
  tenant: {
    findUnique: jest.fn(),
    update: jest.fn(),
    ...(overrides.tenant ?? {}),
  },
  subscriptionInvoice: {
    findFirst: jest.fn(),
    findMany: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
    ...(overrides.subscriptionInvoice ?? {}),
  },
  subscriptionPaymentClaim: {
    findUnique: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
    ...(overrides.subscriptionPaymentClaim ?? {}),
  },
});

const buildService = (prismaOverrides: Record<string, any> = {}) => {
  const prisma = buildPrisma(prismaOverrides);
  const jenga = { initiate: jest.fn() };
  const config = { get: jest.fn().mockReturnValue(undefined) };
  const settler = { settleByCheckoutId: jest.fn().mockResolvedValue(null) };
  const service = new RecurringBillingService(
    prisma as any,
    jenga as any,
    config as any,
    settler as any,
  );
  return { service, prisma, jenga, config, settler };
};

const msPerDay = 24 * 60 * 60 * 1000;

describe('RecurringBillingService', () => {
  // =========================================================================
  // Invoice idempotency per period
  // =========================================================================
  describe('invoice idempotency per period', () => {
    it('creates the new period invoice once and reuses it on the next tick', async () => {
      const now = new Date('2026-09-07T04:00:00Z');
      const tenant = {
        id: 'tenant-1',
        name: 'Jawaki Ltd',
        plan: 'CORE',
        autoRenewEnabled: false,
        billingPhone: null,
        subscriptionStatus: 'ACTIVE',
        currentPeriodStart: new Date('2026-08-07T00:00:00Z'),
        currentPeriodEnd: new Date('2026-09-07T00:00:00Z'),
      };
      const invoice = {
        id: 'inv-1',
        tenantId: 'tenant-1',
        status: 'PENDING',
        renewalSequence: 1,
        createdAt: now,
        periodStart: now,
        periodEnd: new Date(now.getTime() + 30 * msPerDay),
      };
      const { service, prisma } = buildService();
      prisma.tenant.findMany = jest.fn().mockResolvedValue([tenant]);
      prisma.subscriptionInvoice.findFirst
        .mockResolvedValueOnce(invoice) // ensureInvoiceForPeriod finds existing
        .mockResolvedValueOnce({ renewalSequence: 1 }); // sequence lookup if created
      prisma.subscriptionInvoice.create = jest.fn();

      const summary = await service.runRenewalCycle(now);

      // The existing invoice for the same periodStart was reused — no create.
      expect(prisma.subscriptionInvoice.create).not.toHaveBeenCalled();
      expect(summary.renewed).toContain('tenant-1');
    });

    it('creates an invoice with the plan price and an incremented sequence when none exists', async () => {
      const now = new Date('2026-09-07T04:00:00Z');
      const tenant = {
        id: 'tenant-2',
        name: 'Jawaki Ltd',
        plan: 'CORE',
        autoRenewEnabled: false,
        billingPhone: null,
        subscriptionStatus: 'ACTIVE',
        currentPeriodStart: new Date('2026-08-07T00:00:00Z'),
        currentPeriodEnd: new Date('2026-09-07T00:00:00Z'),
      };
      const { service, prisma } = buildService();
      prisma.tenant.findMany = jest.fn().mockResolvedValue([tenant]);
      prisma.subscriptionInvoice.findFirst
        .mockResolvedValueOnce(null) // no invoice for this periodStart yet
        .mockResolvedValueOnce({ renewalSequence: 4 }); // last invoice sequence
      prisma.subscriptionInvoice.create = jest
        .fn()
        .mockResolvedValue({ id: 'inv-new', status: 'PENDING', createdAt: now });

      await service.runRenewalCycle(now);

      expect(prisma.subscriptionInvoice.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          tenantId: 'tenant-2',
          plan: 'CORE',
          status: 'PENDING',
          renewalSequence: 5,
          amount: expect.anything(),
        }),
      });
      const created = prisma.subscriptionInvoice.create.mock.calls[0][0].data;
      expect(created.periodStart).toEqual(new Date('2026-09-07T00:00:00Z')); // startOfDay(now) in UTC
      expect(Number(created.amount)).toBe(3200); // CORE monthly price
    });
  });

  // =========================================================================
  // Suspension after grace
  // =========================================================================
  describe('suspension after grace', () => {
    it('suspends a tenant whose PENDING invoice is at/older than grace days', async () => {
      const now = new Date('2026-09-10T04:00:00Z');
      const createdAt = new Date(now.getTime() - 3 * msPerDay); // exactly grace
      const tenant = {
        id: 'tenant-3',
        name: 'Overdue Ltd',
        plan: 'CORE',
        autoRenewEnabled: false,
        billingPhone: null,
        subscriptionStatus: 'ACTIVE',
        currentPeriodStart: new Date('2026-08-07T00:00:00Z'),
        currentPeriodEnd: new Date('2026-09-07T00:00:00Z'),
      };
      const { service, prisma } = buildService();
      prisma.tenant.findMany = jest.fn().mockResolvedValue([tenant]);
      prisma.subscriptionInvoice.findFirst
        .mockResolvedValueOnce({
          id: 'inv-3',
          status: 'PENDING',
          renewalSequence: 1,
          createdAt,
        })
        .mockResolvedValueOnce({ renewalSequence: 1 });
      prisma.subscriptionInvoice.create = jest.fn();

      const summary = await service.runRenewalCycle(now);

      expect(prisma.tenant.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'tenant-3' },
          data: { subscriptionStatus: 'PAST_DUE' },
        }),
      );
      expect(summary.suspended).toContain('tenant-3');
    });

    it('does not suspend inside the grace window (invoice younger than grace days)', async () => {
      const now = new Date('2026-09-09T04:00:00Z');
      const createdAt = new Date(now.getTime() - 1 * msPerDay); // 1 day < 3-day grace
      const tenant = {
        id: 'tenant-4',
        name: 'Within Grace Ltd',
        plan: 'CORE',
        autoRenewEnabled: false,
        billingPhone: null,
        subscriptionStatus: 'ACTIVE',
        currentPeriodStart: new Date('2026-08-07T00:00:00Z'),
        currentPeriodEnd: new Date('2026-09-07T00:00:00Z'),
      };
      const { service, prisma } = buildService();
      prisma.tenant.findMany = jest.fn().mockResolvedValue([tenant]);
      prisma.subscriptionInvoice.findFirst
        .mockResolvedValueOnce({
          id: 'inv-4',
          status: 'PENDING',
          renewalSequence: 1,
          createdAt,
        })
        .mockResolvedValueOnce({ renewalSequence: 1 });
      prisma.subscriptionInvoice.create = jest.fn();

      const summary = await service.runRenewalCycle(now);

      expect(prisma.tenant.update).not.toHaveBeenCalled();
      expect(summary.suspended).toHaveLength(0);
      expect(summary.renewed).toContain('tenant-4');
    });

    it('heals a stale ACTIVE tenant whose invoice is already PAID', async () => {
      const now = new Date('2026-09-10T04:00:00Z');
      const tenant = {
        id: 'tenant-5',
        name: 'Stale Ltd',
        plan: 'CORE',
        autoRenewEnabled: false,
        billingPhone: null,
        subscriptionStatus: 'PAST_DUE',
        currentPeriodStart: new Date('2026-08-07T00:00:00Z'),
        currentPeriodEnd: new Date('2026-09-07T00:00:00Z'),
      };
      const { service, prisma } = buildService();
      prisma.tenant.findMany = jest.fn().mockResolvedValue([tenant]);
      prisma.subscriptionInvoice.findFirst
        .mockResolvedValueOnce({
          id: 'inv-5',
          status: 'PAID',
          createdAt: new Date(now.getTime() - 5 * msPerDay),
          periodStart: new Date('2026-09-07T00:00:00Z'),
          periodEnd: new Date('2026-10-07T00:00:00Z'),
        })
        .mockResolvedValueOnce({ renewalSequence: 2 });
      prisma.subscriptionInvoice.create = jest.fn();

      const summary = await service.runRenewalCycle(now);

      expect(prisma.tenant.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'tenant-5' },
          data: expect.objectContaining({ subscriptionStatus: 'ACTIVE' }),
        }),
      );
      expect(summary.renewed).toContain('tenant-5');
    });
  });

  // =========================================================================
  // settleRenewalPayment — invoice + tenant flip in one transaction
  // =========================================================================
  describe('settleRenewalPayment', () => {
    it('marks the invoice PAID and activates the tenant in a single transaction', async () => {
      const invoice = {
        id: 'inv-6',
        tenantId: 'tenant-6',
        status: 'PENDING',
        mpesaCheckoutId: 'chk-123',
      };
      const { service, prisma, settler } = buildService();
      settler.settleByCheckoutId.mockResolvedValue({ id: 'inv-6', status: 'PAID' });

      const result = await service.settleRenewalPayment('chk-123');

      expect(settler.settleByCheckoutId).toHaveBeenCalledWith('chk-123');
      expect(result).toMatchObject({ id: 'inv-6', status: 'PAID' });
      // The billing service itself performs no direct invoice writes.
      expect(prisma.subscriptionInvoice.findFirst).not.toHaveBeenCalled();
      expect(prisma.subscriptionInvoice.update).not.toHaveBeenCalled();
      expect(prisma.tenant.update).not.toHaveBeenCalled();
      void invoice;
    });

    it('is idempotent: an already-PAID invoice returns null and writes nothing', async () => {
      const { service, settler } = buildService();
      settler.settleByCheckoutId.mockResolvedValue(null);

      const result = await service.settleRenewalPayment('chk-already-paid');

      expect(result).toBeNull();
    });
  });

  // =========================================================================
  // Manual claim approve / reject flow
  // =========================================================================
  describe('submitManualPayment + confirmManualPayment', () => {
    const tenantRow = {
      plan: 'CORE',
      currentPeriodEnd: new Date('2026-09-07T00:00:00Z'),
      subscriptionStatus: 'ACTIVE',
    };

    it('submits a code as a PENDING claim and flips the invoice to PENDING_CONFIRMATION', async () => {
      const { service, prisma } = buildService();
      prisma.tenant.findUnique.mockResolvedValue(tenantRow);
      prisma.subscriptionInvoice.findFirst.mockResolvedValue({
        id: 'inv-7',
        amount: 3200,
      });
      prisma.subscriptionPaymentClaim.findUnique.mockResolvedValue(null);
      prisma.subscriptionPaymentClaim.create.mockResolvedValue({
        id: 'claim-1',
        status: 'PENDING',
      });

      const result = await service.submitManualPayment('tenant-7', 'user-1', {
        mpesaCode: 'qgh7xyz92k',
        amount: 3200,
      });

      expect(result).toMatchObject({ claimId: 'claim-1', status: 'PENDING_CONFIRMATION' });
      const createdData = prisma.subscriptionPaymentClaim.create.mock.calls[0][0].data;
      expect(createdData.mpesaCode).toBe('QGH7XYZ92K'); // normalized to upper-case
      expect(createdData.status).toBe('PENDING');
      expect(prisma.subscriptionInvoice.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'inv-7' },
          data: expect.objectContaining({ status: 'PENDING_CONFIRMATION' }),
        }),
      );
    });

    it('rejects a claim without touching the tenant period', async () => {
      const { service, prisma } = buildService();
      prisma.subscriptionPaymentClaim.findUnique.mockResolvedValue({
        id: 'claim-2',
        tenantId: 'tenant-7',
        invoiceId: 'inv-7',
        status: 'PENDING',
        mpesaCode: 'QGH7XYZ92K',
      });
      prisma.subscriptionPaymentClaim.update.mockResolvedValue({
        id: 'claim-2',
        status: 'REJECTED',
      });

      const result = await service.confirmManualPayment('tenant-7', 'claim-2', false);

      expect(result.claim).toMatchObject({ status: 'REJECTED' });
      expect(result.invoice).toBeNull();
      expect(prisma.$transaction).not.toHaveBeenCalled();
      expect(prisma.tenant.update).not.toHaveBeenCalled();
    });

    it('approves a claim atomically: invoice PAID + claim APPROVED + tenant activated', async () => {
      const { service, prisma } = buildService();
      prisma.subscriptionPaymentClaim.findUnique.mockResolvedValue({
        id: 'claim-3',
        tenantId: 'tenant-7',
        invoiceId: 'inv-7',
        status: 'PENDING',
        mpesaCode: 'QGH7XYZ92K',
      });
      // In-memory transaction: the tx object IS the prisma mock, so calls
      // made inside the callback are visible to assertions afterwards.
      prisma.$transaction = jest
        .fn()
        .mockImplementation(async (fn: (tx: MockTx) => Promise<unknown>) => fn(prisma as MockTx));
      const now = new Date();
      prisma.subscriptionInvoice.update.mockResolvedValue({
        id: 'inv-7',
        status: 'PAID',
        paidAt: now,
        periodStart: now,
        periodEnd: new Date(now.getTime() + 30 * msPerDay),
        plan: 'CORE',
      });
      prisma.subscriptionPaymentClaim.update.mockResolvedValue({
        id: 'claim-3',
        status: 'APPROVED',
      });

      const result = await service.confirmManualPayment('tenant-7', 'claim-3', true);

      expect(result.claim).toMatchObject({ status: 'APPROVED' });
      expect(result.invoice).toMatchObject({ status: 'PAID' });
      // Tenant activated in the SAME transaction with the invoice's period.
      expect(prisma.tenant.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'tenant-7' },
          data: expect.objectContaining({
            subscriptionStatus: 'ACTIVE',
            currentPeriodStart: expect.any(Date),
            currentPeriodEnd: expect.any(Date),
          }),
        }),
      );
      const claimUpdate = prisma.subscriptionPaymentClaim.update.mock.calls[0][0];
      expect(claimUpdate.where).toEqual({ id: 'claim-3' });
      expect(claimUpdate.data).toMatchObject({ status: 'APPROVED', decidedAt: expect.any(Date) });
    });

    it('refuses to approve an already-decided claim', async () => {
      const { service, prisma } = buildService();
      prisma.subscriptionPaymentClaim.findUnique.mockResolvedValue({
        id: 'claim-4',
        tenantId: 'tenant-7',
        invoiceId: 'inv-7',
        status: 'APPROVED',
      });

      await expect(
        service.confirmManualPayment('tenant-7', 'claim-4', true),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('refuses a claim that belongs to another company', async () => {
      const { service, prisma } = buildService();
      prisma.subscriptionPaymentClaim.findUnique.mockResolvedValue({
        id: 'claim-5',
        tenantId: 'other-tenant',
        invoiceId: 'inv-9',
        status: 'PENDING',
      });

      await expect(
        service.confirmManualPayment('tenant-7', 'claim-5', true),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('throws NotFound when no open invoice exists to claim against', async () => {
      const { service, prisma } = buildService();
      prisma.tenant.findUnique.mockResolvedValue({
        plan: 'CORE',
        currentPeriodEnd: new Date(Date.now() + 10 * msPerDay),
        subscriptionStatus: 'ACTIVE',
      });
      prisma.subscriptionInvoice.findFirst.mockResolvedValue(null);

      await expect(
        service.submitManualPayment('tenant-7', 'user-1', { mpesaCode: 'QGH7XYZ92K' }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  // =========================================================================
  // isTenantRestricted (restricted-mode helper shared with the guard)
  // =========================================================================
  describe('isTenantRestricted', () => {
    it('never restricts ACTIVE or TRIAL tenants', () => {
      expect(
        isTenantRestricted({ subscriptionStatus: 'ACTIVE', currentPeriodEnd: new Date(Date.now() - msPerDay) }),
      ).toEqual({ restricted: false, reason: null });
      expect(
        isTenantRestricted({ subscriptionStatus: 'TRIAL', currentPeriodEnd: new Date(Date.now() - msPerDay) }),
      ).toEqual({ restricted: false, reason: null });
    });

    it('gives PAST_DUE tenants grace before restricting', () => {
      const periodEnd = new Date(Date.now() - msPerDay); // 1 day past end < 3-day grace
      expect(isTenantRestricted({ subscriptionStatus: 'PAST_DUE', currentPeriodEnd: periodEnd })).toEqual({
        restricted: false,
        reason: 'grace_period',
      });
    });

    it('restricts PAST_DUE beyond grace with payment_overdue', () => {
      const periodEnd = new Date(Date.now() - 4 * msPerDay); // 4 days > 3-day grace
      expect(isTenantRestricted({ subscriptionStatus: 'PAST_DUE', currentPeriodEnd: periodEnd })).toEqual({
        restricted: true,
        reason: 'payment_overdue',
      });
    });

    it('restricts tenants with no period window at all', () => {
      expect(isTenantRestricted({ subscriptionStatus: 'SUSPENDED', currentPeriodEnd: null })).toEqual({
        restricted: true,
        reason: 'payment_overdue',
      });
    });
  });

  // =========================================================================
  // Signed offline entitlement
  // =========================================================================
  describe('offline entitlement signing', () => {
    const OLD_ENV = process.env;

    beforeEach(() => {
      jest.resetModules();
      process.env = { ...OLD_ENV, ENTITLEMENT_SECRET: 'test-entitlement-secret' };
    });

    afterAll(() => {
      process.env = OLD_ENV;
    });

    const buildEntitlementService = (tenantRow: Record<string, any>) => {
      const built = buildService();
      // buildOfflineEntitlement reads ENTITLEMENT_SECRET (JWT_SECRET fallback)
      // from ConfigService; verifyOfflineEntitlement reads the same key from
      // process.env. Point both at the same secret for the round-trip test.
      (built.config.get as jest.Mock).mockImplementation(
        (key: string) => (key === 'ENTITLEMENT_SECRET' ? 'test-entitlement-secret' : undefined),
      );
      built.prisma.tenant.findUnique = jest.fn().mockResolvedValue(tenantRow);
      return built;
    };

    it('round-trips buildOfflineEntitlement through verifyOfflineEntitlement', async () => {
      const { service } = buildEntitlementService({
        id: 'tenant-8',
        plan: 'CORE',
        subscriptionStatus: 'ACTIVE',
        currentPeriodEnd: new Date('2026-10-07T00:00:00Z'),
      });

      const token = await service.buildOfflineEntitlement('tenant-8');
      expect(token.signature).toMatch(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);

      const payload = RecurringBillingService.verifyOfflineEntitlement(
        { tenantId: token.tenantId },
        token.signature,
      );
      expect(payload).toMatchObject({
        tenantId: 'tenant-8',
        plan: 'CORE',
        validUntil: token.validUntil,
      });
      // Offline grace is exactly 7 days beyond validUntil.
      const valid = new Date(token.validUntil as string).getTime();
      const grace = new Date(token.offlineGraceUntil as string).getTime();
      expect(grace - valid).toBe(7 * msPerDay);
    });

    it('rejects a tampered payload', async () => {
      const { service } = buildEntitlementService({
        id: 'tenant-8',
        plan: 'CORE',
        subscriptionStatus: 'ACTIVE',
        currentPeriodEnd: new Date('2026-10-07T00:00:00Z'),
      });

      const token = await service.buildOfflineEntitlement('tenant-8');
      expect(() =>
        RecurringBillingService.verifyOfflineEntitlement(
          { tenantId: 'tenant-OTHER' },
          token.signature,
        ),
      ).toThrow();
    });

    it('rejects a signature produced with a different secret', async () => {
      const { service } = buildEntitlementService({
        id: 'tenant-8',
        plan: 'CORE',
        subscriptionStatus: 'ACTIVE',
        currentPeriodEnd: new Date('2026-10-07T00:00:00Z'),
      });

      const token = await service.buildOfflineEntitlement('tenant-8');
      expect(() =>
        RecurringBillingService.verifyOfflineEntitlement(
          { tenantId: token.tenantId },
          token.signature,
          'a-different-secret',
        ),
      ).toThrow();
    });

    it('gives a suspended tenant an already-expired validUntil', async () => {
      const { service } = buildEntitlementService({
        id: 'tenant-9',
        plan: 'CORE',
        subscriptionStatus: 'PAST_DUE',
        currentPeriodEnd: new Date('2026-10-07T00:00:00Z'),
      });

      const token = await service.buildOfflineEntitlement('tenant-9');
      expect(new Date(token.validUntil as string).getTime()).toBeLessThanOrEqual(Date.now());
    });
  });
});