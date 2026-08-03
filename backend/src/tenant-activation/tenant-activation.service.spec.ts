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
});
