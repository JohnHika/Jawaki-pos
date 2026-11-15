import { ConfigService } from '@nestjs/config';
import { TenantActivationService } from './tenant-activation.service';

describe('TenantActivationService durable attempts', () => {
  it('returns a prior attempt for the same idempotency key instead of initializing another checkout', async () => {
    const existingAttempt = {
      id: 'attempt-1', reference: 'AXON-ONE', authorizationUrl: 'https://pay.example/one',
      status: 'PENDING', amount: 125000, provider: 'PAYSTACK', verifiedAt: null,
    };
    const prisma: any = {
      user: { findFirst: jest.fn().mockResolvedValue({ identityVerifiedAt: new Date() }) },
      tenant: { findUnique: jest.fn().mockResolvedValue({ id: 'tenant-1', name: 'Acme', activationStatus: 'PENDING' }), update: jest.fn() },
      tenantActivationAttempt: {
        findUnique: jest.fn().mockResolvedValue(existingAttempt),
        create: jest.fn(), update: jest.fn(),
      },
    };
    const paystack = { initializeTransaction: jest.fn() };
    const service = new TenantActivationService(prisma, paystack as any, {} as ConfigService);

    await expect(service.initialize('tenant-1', 'user-1', 'owner@example.test', 'client-key-1'))
      .resolves.toEqual(expect.objectContaining({ attemptId: 'attempt-1', reference: 'AXON-ONE' }));
    expect(paystack.initializeTransaction).not.toHaveBeenCalled();
    expect(prisma.tenant.update).not.toHaveBeenCalled();
  });

  describe('confirming the activation payment', () => {
    const build = (attemptStatus: string, quoted = 125000, paidAmountKes = 125000) => {
      const attempt: any = { id: 'attempt-1', tenantId: 'tenant-1', reference: 'AXON-ONE', status: attemptStatus, provider: 'PAYSTACK', amount: quoted };
      const prisma: any = {
        tenant: {
          findUnique: jest.fn().mockResolvedValue({ activationStatus: 'ACTIVE', activationAmount: 35000, activationPaidAt: new Date() }),
          update: jest.fn().mockResolvedValue({ activationStatus: 'ACTIVE', activationAmount: 35000, activationPaidAt: new Date() }),
        },
        tenantActivationAttempt: {
          findFirst: jest.fn().mockResolvedValue(attempt),
          findUnique: jest.fn().mockResolvedValue(attempt),
          update: jest.fn().mockResolvedValue({ ...attempt, status: 'PAID' }),
        },
      };
      const paystack = { verifyTransaction: jest.fn().mockResolvedValue({ status: 'success', amount: paidAmountKes * 100 }) };
      const referrals = { onActivated: jest.fn().mockResolvedValue(undefined) };
      const service = new TenantActivationService(prisma, paystack as any, {} as ConfigService, referrals as any);
      return { service, prisma, referrals };
    };

    it('starts the trial and then pays out any referral or promo days', async () => {
      const { service, prisma, referrals } = build('INITIALIZED');
      await service.verify('tenant-1', 'AXON-ONE');
      expect(prisma.tenant.update).toHaveBeenCalledTimes(1);
      expect(referrals.onActivated).toHaveBeenCalledWith('tenant-1');
    });

    it('does not restart the trial when the same payment is confirmed twice', async () => {
      // The webhook and the app both confirm. A second pass must not reset the
      // period end, which would wipe the bonus days added after the first.
      const { service, prisma, referrals } = build('PAID');
      await service.verify('tenant-1', 'AXON-ONE');
      expect(prisma.tenant.update).not.toHaveBeenCalled();
      expect(referrals.onActivated).not.toHaveBeenCalled();
    });

    it('holds a checkout opened at the old KES 35,000 price instead of activating', async () => {
      const { service, prisma, referrals } = build('PENDING', 35000, 35000);
      const result: any = await service.verify('tenant-1', 'AXON-ONE');
      expect(prisma.tenantActivationAttempt.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ status: 'NEEDS_REVIEW', authorizationUrl: null }) }),
      );
      expect(prisma.tenant.update).not.toHaveBeenCalled();
      expect(referrals.onActivated).not.toHaveBeenCalled();
      expect(result.attemptStatus).toBe('NEEDS_REVIEW');
      expect(result.status).toBe('PENDING');
    });

    it('holds a payment whose amount is not what the checkout was opened for', async () => {
      const { service, prisma } = build('PENDING', 125000, 80000);
      const result: any = await service.verify('tenant-1', 'AXON-ONE');
      expect(prisma.tenant.update).not.toHaveBeenCalled();
      expect(result.attemptStatus).toBe('NEEDS_REVIEW');
    });

    it('does not re-check a payment that is already on hold', async () => {
      const { service, prisma } = build('NEEDS_REVIEW');
      const result: any = await service.verify('tenant-1', 'AXON-ONE');
      expect(prisma.tenantActivationAttempt.update).not.toHaveBeenCalled();
      expect(prisma.tenant.update).not.toHaveBeenCalled();
      expect(result.attemptStatus).toBe('NEEDS_REVIEW');
    });

    it('activates at KES 125,000 and records that amount', async () => {
      const { service, prisma } = build('PENDING');
      await service.verify('tenant-1', 'AXON-ONE');
      expect(prisma.tenant.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ activationAmount: 125000 }) }),
      );
    });
  });

  describe('quoting the setup fee', () => {
    const buildInit = (priorAmount: number | null) => {
      const prior = priorAmount == null ? null : {
        id: 'old-attempt', reference: 'AXON-OLD', authorizationUrl: 'https://pay.example/old',
        status: 'PENDING', amount: priorAmount, provider: 'PAYSTACK', verifiedAt: null,
      };
      const prisma: any = {
        user: { findFirst: jest.fn().mockResolvedValue({ id: 'user-1' }) },
        tenant: {
          findUnique: jest.fn().mockResolvedValue({
            id: 'tenant-1', name: 'Acme', activationStatus: 'PENDING', activationAmount: 35000,
          }),
        },
        tenantActivationAttempt: {
          findUnique: jest.fn()
            .mockResolvedValueOnce(prior)
            .mockResolvedValue(null),
          create: jest.fn().mockResolvedValue({ id: 'new-attempt' }),
          update: jest.fn().mockResolvedValue({
            id: 'new-attempt', reference: 'AXON-NEW', status: 'PENDING', amount: 125000,
            provider: 'PAYSTACK', authorizationUrl: 'https://pay.example/new',
          }),
        },
      };
      const paystack = {
        initializeTransaction: jest.fn().mockResolvedValue({ authorizationUrl: 'https://pay.example/new' }),
      };
      const config = { get: jest.fn().mockReturnValue(undefined) } as unknown as ConfigService;
      return { service: new TenantActivationService(prisma, paystack as any, config), prisma, paystack };
    };

    it('quotes a shop that has not paid KES 125,000 even if its row still holds the old default', async () => {
      const { service, paystack } = buildInit(null);
      const result: any = await service.initialize('tenant-1', 'user-1', 'o@x.test', 'k1');
      expect(paystack.initializeTransaction).toHaveBeenCalledWith(expect.objectContaining({ amountKes: 125000 }));
      expect(result.amountKes).toBe(125000);
    });

    it('closes an unpaid checkout opened at 35,000 and opens a new one at 125,000', async () => {
      const { service, prisma, paystack } = buildInit(35000);
      await service.initialize('tenant-1', 'user-1', 'o@x.test', 'k1');
      expect(prisma.tenantActivationAttempt.update).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: 'old-attempt' }, data: expect.objectContaining({ status: 'SUPERSEDED' }) }),
      );
      expect(prisma.tenantActivationAttempt.create).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ amount: 125000, idempotencyKey: 'k1:125000' }) }),
      );
      expect(paystack.initializeTransaction).toHaveBeenCalledWith(expect.objectContaining({ amountKes: 125000 }));
    });
  });
});
