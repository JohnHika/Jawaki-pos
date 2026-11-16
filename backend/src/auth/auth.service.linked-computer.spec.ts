import { UnauthorizedException } from '@nestjs/common';
import { createHash } from 'crypto';
import { AuthService } from './auth.service';

/**
 * A computer a phone signed in keeps its identity through every token refresh,
 * and stops working once the phone signs it out.
 */
describe('AuthService linked computers', () => {
  const sha = (text: string) => createHash('sha256').update(text).digest('hex');

  const owner = {
    id: 'owner-1',
    email: 'owner@shop.co',
    role: 'ADMIN',
    tenantId: 'tenant-1',
    firstName: 'Ada',
    lastName: 'Owner',
    isActive: true,
    tenant: { id: 'tenant-1', slug: 'shop', isActive: true },
    branches: [{ branchId: 'b1', isPrimary: true, branch: { id: 'b1', name: 'Main' } }],
  };

  const build = (computer: any) => {
    const sign = jest.fn().mockReturnValue('access');
    const prisma: any = {
      user: {
        findUnique: jest.fn().mockResolvedValue(owner),
        update: jest.fn().mockResolvedValue({}),
      },
      refreshToken: {
        create: jest.fn().mockResolvedValue({}),
        delete: jest.fn().mockResolvedValue({}),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
        findFirst: jest.fn(),
      },
      linkedComputer: {
        create: jest.fn().mockResolvedValue({ id: 'computer-1' }),
        findUnique: jest.fn().mockResolvedValue(computer),
        update: jest.fn().mockResolvedValue({}),
      },
    };
    const service = new AuthService(
      prisma,
      { sign } as any,
      { get: jest.fn((_key: string, def?: string) => def) } as any,
      { del: jest.fn() } as any,
      { record: jest.fn() } as any,
      { getEffectivePermissions: jest.fn().mockResolvedValue([]) } as any,
      { verify: jest.fn() } as any,
      { request: jest.fn(), consume: jest.fn() } as any,
      { createFromVerifiedIdentity: jest.fn() } as any,
    );
    return { service, prisma, sign };
  };

  it('records the approved computer and puts its id on both the token and the session', async () => {
    const { service, prisma, sign } = build(null);

    await service.issueLinkedSession('owner-1', {
      branchId: 'b1',
      deviceId: 'pc-1',
      computer: { desktopName: 'FRONT-DESK', platform: 'windows', place: 'Nairobi, KE', ip: '41.90.10.20' },
    });

    expect(prisma.linkedComputer.create).toHaveBeenCalledWith({
      data: {
        userId: 'owner-1',
        desktopName: 'FRONT-DESK',
        platform: 'windows',
        place: 'Nairobi, KE',
        ip: '41.90.10.20',
        approverDevice: null,
        deviceId: 'pc-1',
      },
      select: { id: true },
    });
    expect(sign).toHaveBeenCalledWith(expect.objectContaining({ sid: 'computer-1' }));
    expect(prisma.refreshToken.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ linkedComputerId: 'computer-1' }),
    });
  });

  it('a normal sign-in carries no computer id', async () => {
    const { service, prisma, sign } = build(null);

    await service.issueLinkedSession('owner-1', { branchId: 'b1' });

    expect(prisma.linkedComputer.create).not.toHaveBeenCalled();
    expect(sign.mock.calls[0][0]).not.toHaveProperty('sid');
  });

  const storedToken = (over: Record<string, any> = {}) => ({
    id: 'token-1',
    userId: 'owner-1',
    deviceId: 'pc-1',
    linkedComputerId: 'computer-1',
    expiresAt: new Date(Date.now() + 60_000),
    user: owner,
    ...over,
  });

  it('refreshing keeps the computer id, so it can still be signed out later', async () => {
    const { service, prisma, sign } = build({ revokedAt: null });
    prisma.refreshToken.findFirst.mockResolvedValue(storedToken());

    await service.refreshToken({ refreshToken: 'old' });

    expect(prisma.refreshToken.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({ where: { tokenHash: sha('old') } }),
    );
    expect(sign).toHaveBeenCalledWith(expect.objectContaining({ sid: 'computer-1' }));
    expect(prisma.refreshToken.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ linkedComputerId: 'computer-1' }),
    });
    expect(prisma.linkedComputer.update).toHaveBeenCalled();
  });

  it('a signed-out computer cannot refresh, and says why', async () => {
    const { service, prisma } = build({ revokedAt: new Date() });
    prisma.refreshToken.findFirst.mockResolvedValue(storedToken());

    const attempt = service.refreshToken({ refreshToken: 'old' });

    await expect(attempt).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(attempt).rejects.toThrow(/signed out from your phone/);
    expect(prisma.refreshToken.create).not.toHaveBeenCalled();
    // The dead token is removed the first time it is tried.
    expect(prisma.refreshToken.deleteMany).toHaveBeenCalledWith({ where: { id: 'token-1' } });
  });

  it('a phone or password session refreshes exactly as before', async () => {
    const { service, prisma, sign } = build(null);
    prisma.refreshToken.findFirst.mockResolvedValue(storedToken({ linkedComputerId: null }));

    await service.refreshToken({ refreshToken: 'old' });

    expect(prisma.linkedComputer.findUnique).not.toHaveBeenCalled();
    expect(sign.mock.calls[0][0]).not.toHaveProperty('sid');
  });
});
