import { ConflictException, UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { AuthService } from './auth.service';

describe('AuthService PIN uniqueness and collision handling', () => {
  const buildService = (prismaOverrides: Record<string, any> = {}) => {
    const prisma: any = {
      user: {
        findUnique: jest.fn(),
        findMany: jest.fn().mockResolvedValue([]),
        update: jest.fn(),
        ...(prismaOverrides.user ?? {}),
      },
      userBranch: {
        findMany: jest.fn(),
        ...(prismaOverrides.userBranch ?? {}),
      },
      device: { findFirst: jest.fn() },
      refreshToken: { create: jest.fn().mockResolvedValue({}) },
    };
    const audit = { record: jest.fn() };
    const service = new AuthService(
      prisma,
      { sign: jest.fn().mockReturnValue('token') } as any,
      { get: jest.fn((_key: string, def?: string) => def) } as any,
      { del: jest.fn() } as any,
      audit as any,
      { getEffectivePermissions: jest.fn().mockResolvedValue([]) } as any,
      { verify: jest.fn() } as any,
      { request: jest.fn(), consume: jest.fn() } as any,
      { createFromVerifiedIdentity: jest.fn() } as any,
    );
    return { service, prisma, audit };
  };

  describe('setPin', () => {
    it('rejects a PIN already used by another active user in the same tenant', async () => {
      const { service, prisma } = buildService();
      prisma.user.findUnique.mockResolvedValue({ tenantId: 'tenant-1' });
      const existingHash = await bcrypt.hash('4321', 12);
      prisma.user.findMany.mockResolvedValue([
        { id: 'other-user', pin: existingHash },
      ]);

      await expect(
        service.setPin('user-1', { pin: '4321' }),
      ).rejects.toBeInstanceOf(ConflictException);

      expect(prisma.user.update).not.toHaveBeenCalled();
    });

    it('allows setting a PIN that no other active user in the tenant has', async () => {
      const { service, prisma } = buildService();
      prisma.user.findUnique.mockResolvedValue({ tenantId: 'tenant-1' });
      const otherHash = await bcrypt.hash('9999', 12);
      prisma.user.findMany.mockResolvedValue([
        { id: 'other-user', pin: otherHash },
      ]);
      prisma.user.update.mockResolvedValue({});

      await service.setPin('user-1', { pin: '4321' });

      expect(prisma.user.update).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: 'user-1' } }),
      );
    });

    it('only checks other active users, not the caller themself', async () => {
      const { service, prisma } = buildService();
      prisma.user.findUnique.mockResolvedValue({ tenantId: 'tenant-1' });
      prisma.user.update.mockResolvedValue({});

      await service.setPin('user-1', { pin: '4321' });

      expect(prisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            tenantId: 'tenant-1',
            isActive: true,
            id: { not: 'user-1' },
          }),
        }),
      );
    });
  });

  describe('loginWithPin', () => {
    it('refuses login and logs a collision when two accounts share a PIN', async () => {
      const { service, prisma } = buildService();
      const sharedHash = await bcrypt.hash('1234', 12);
      const baseUser = (id: string) => ({
        id,
        pin: sharedHash,
        isActive: true,
        tenant: { isActive: true },
        branches: [],
      });
      prisma.userBranch.findMany.mockResolvedValue([
        { user: baseUser('user-a') },
        { user: baseUser('user-b') },
      ]);

      await expect(
        service.loginWithPin({ pin: '1234', deviceId: 'device-1', branchId: 'branch-1' }),
      ).rejects.toBeInstanceOf(UnauthorizedException);

      expect(prisma.user.update).not.toHaveBeenCalled();
    });

    it('logs in the single matching user when only one PIN matches', async () => {
      const { service, prisma, audit } = buildService();
      const hash = await bcrypt.hash('1234', 12);
      prisma.userBranch.findMany.mockResolvedValue([
        {
          user: {
            id: 'user-a',
            pin: hash,
            isActive: true,
            tenant: { isActive: true },
            branches: [{ branchId: 'branch-1', isPrimary: true }],
          },
        },
      ]);
      prisma.user.update.mockResolvedValue({});

      const result = await service.loginWithPin({
        pin: '1234',
        deviceId: 'device-1',
        branchId: 'branch-1',
      });

      expect(result.accessToken).toBe('token');
      expect(prisma.user.update).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: 'user-a' } }),
      );
      expect(audit.record).toHaveBeenCalledWith(
        expect.objectContaining({ userId: 'user-a', action: 'LOGIN' }),
      );
    });

    it('rejects when no PIN matches', async () => {
      const { service, prisma } = buildService();
      prisma.userBranch.findMany.mockResolvedValue([]);

      await expect(
        service.loginWithPin({ pin: '0000', deviceId: 'device-1', branchId: 'branch-1' }),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });
  });
});
