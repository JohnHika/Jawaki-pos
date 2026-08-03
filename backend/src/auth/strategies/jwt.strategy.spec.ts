import { LegacyUserRole } from '@prisma/client';
import { JwtStrategy } from './jwt.strategy';

describe('JwtStrategy current-user claims', () => {
  it('uses the current database tenant and role instead of stale JWT claims', async () => {
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({
          id: 'actor-1',
          isActive: true,
          role: LegacyUserRole.MANAGER,
          tenantId: 'tenant-a',
          tenant: { activationStatus: 'ACTIVE' },
        }),
      },
    };
    const strategy = new JwtStrategy(
      { get: jest.fn().mockReturnValue('test-secret') } as any,
      prisma as any,
      { getEffectivePermissions: jest.fn().mockResolvedValue(['users.create']) } as any,
    );

    const currentUser = await strategy.validate({
      sub: 'actor-1',
      email: 'manager@example.test',
      role: LegacyUserRole.ADMIN,
      tenantId: 'tenant-b',
    });

    expect(currentUser).toMatchObject({
      role: LegacyUserRole.MANAGER,
      tenantId: 'tenant-a',
      permissions: ['users.create'],
    });
  });
});
