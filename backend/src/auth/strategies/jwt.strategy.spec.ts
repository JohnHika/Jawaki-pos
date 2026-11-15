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

  describe('a computer signed in from the phone', () => {
    const build = (computer: any) => {
      const prisma = {
        user: {
          findUnique: jest.fn().mockResolvedValue({
            id: 'owner-1',
            isActive: true,
            role: LegacyUserRole.ADMIN,
            tenantId: 'tenant-a',
            tenant: { activationStatus: 'ACTIVE' },
          }),
        },
        linkedComputer: {
          findUnique: jest.fn().mockResolvedValue(computer),
          updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        },
      };
      const strategy = new JwtStrategy(
        { get: jest.fn().mockReturnValue('test-secret') } as any,
        prisma as any,
        { getEffectivePermissions: jest.fn().mockResolvedValue([]) } as any,
      );
      return { strategy, prisma };
    };
    const payload = {
      sub: 'owner-1',
      email: 'owner@example.test',
      role: LegacyUserRole.ADMIN,
      tenantId: 'tenant-a',
      sid: 'computer-1',
    };

    it('is refused as soon as the phone signs that computer out', async () => {
      const { strategy } = build({
        userId: 'owner-1',
        revokedAt: new Date(),
        lastActiveAt: new Date(),
      });
      await expect(strategy.validate(payload)).rejects.toThrow(/signed out from your phone/);
    });

    it('is refused when the computer record is gone or belongs to someone else', async () => {
      await expect(build(null).strategy.validate(payload)).rejects.toThrow();
      await expect(
        build({ userId: 'other', revokedAt: null, lastActiveAt: new Date() }).strategy.validate(
          payload,
        ),
      ).rejects.toThrow();
    });

    it('works while linked, and passes the computer id on', async () => {
      const { strategy, prisma } = build({
        userId: 'owner-1',
        revokedAt: null,
        lastActiveAt: new Date(),
      });
      await expect(strategy.validate(payload)).resolves.toMatchObject({ sid: 'computer-1' });
      // Active a moment ago: no write on every request.
      expect(prisma.linkedComputer.updateMany).not.toHaveBeenCalled();
    });

    it('refreshes "last active" when it is stale', async () => {
      const { strategy, prisma } = build({
        userId: 'owner-1',
        revokedAt: null,
        lastActiveAt: new Date(Date.now() - 10 * 60 * 1000),
      });
      await strategy.validate(payload);
      expect(prisma.linkedComputer.updateMany).toHaveBeenCalledTimes(1);
    });

    it('a normal sign-in does not look anything up', async () => {
      const { strategy, prisma } = build(null);
      await strategy.validate({ ...payload, sid: undefined });
      expect(prisma.linkedComputer.findUnique).not.toHaveBeenCalled();
    });
  });
});
