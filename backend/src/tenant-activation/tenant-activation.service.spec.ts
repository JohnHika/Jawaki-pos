import { ConfigService } from '@nestjs/config';
import { TenantActivationService } from './tenant-activation.service';

describe('TenantActivationService durable attempts', () => {
  it('returns a prior attempt for the same idempotency key instead of initializing another checkout', async () => {
    const existingAttempt = {
      id: 'attempt-1', reference: 'AXON-ONE', authorizationUrl: 'https://pay.example/one',
      status: 'PENDING', amount: 50000, provider: 'PAYSTACK', verifiedAt: null,
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
    const build = (attemptStatus: string) => {
      const attempt: any = { id: 'attempt-1', tenantId: 'tenant-1', reference: 'AXON-ONE', status: attemptStatus, provider: 'PAYSTACK' };
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
      const paystack = { verifyTransaction: jest.fn().mockResolvedValue({ status: 'success', amount: 3_500_000 }) };
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
  });
});
