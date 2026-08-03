import { ForbiddenException } from '@nestjs/common';
import { LegacyUserRole } from '@prisma/client';
import { AuthService } from './auth.service';

describe('AuthService legacy staff registration authorization', () => {
  const actor = {
    sub: 'actor-1',
    tenantId: 'tenant-a',
    role: LegacyUserRole.ADMIN,
    permissions: ['users.create'],
  };

  const dto = {
    email: 'new.staff@example.test',
    password: 'ValidPass1',
    firstName: 'New',
    lastName: 'Staff',
    tenantId: 'tenant-b',
  };

  const buildService = () => {
    const prisma = {
      user: { findFirst: jest.fn() },
      branch: { findMany: jest.fn() },
      refreshToken: { create: jest.fn() },
    };
    const service = new AuthService(
      prisma as any,
      { sign: jest.fn() } as any,
      { get: jest.fn() } as any,
      { del: jest.fn() } as any,
      { record: jest.fn() } as any,
      { getEffectivePermissions: jest.fn() } as any,
      { verify: jest.fn() } as any,
      { request: jest.fn(), consume: jest.fn() } as any,
      { createFromVerifiedIdentity: jest.fn() } as any,
    );
    return { service, prisma };
  };

  it('rejects a supplied tenantId that differs from the authenticated tenant', async () => {
    const { service, prisma } = buildService();

    await expect((service.register as any)(dto, actor)).rejects.toBeInstanceOf(ForbiddenException);

    expect(prisma.user.findFirst).not.toHaveBeenCalled();
    expect(prisma.branch.findMany).not.toHaveBeenCalled();
  });

  it('rejects an assigned branch that belongs to another tenant', async () => {
    const { service, prisma } = buildService();
    prisma.branch.findMany.mockResolvedValue([]);

    await expect((service.register as any)({
      ...dto,
      tenantId: actor.tenantId,
      branchIds: ['branch-from-tenant-b'],
    }, actor)).rejects.toBeInstanceOf(ForbiddenException);

    expect(prisma.branch.findMany).toHaveBeenCalledWith({
      where: {
        id: { in: ['branch-from-tenant-b'] },
        tenantId: actor.tenantId,
        isActive: true,
      },
      select: { id: true },
    });
    expect(prisma.user.findFirst).not.toHaveBeenCalled();
  });

  it('rejects a legacy role equal to or higher than the caller role', async () => {
    const { service, prisma } = buildService();

    await expect((service.register as any)({
      ...dto,
      tenantId: actor.tenantId,
      role: LegacyUserRole.ADMIN,
    }, { ...actor, role: LegacyUserRole.MANAGER })).rejects.toBeInstanceOf(ForbiddenException);

    expect(prisma.user.findFirst).not.toHaveBeenCalled();
    expect(prisma.branch.findMany).not.toHaveBeenCalled();
  });
});
