import { ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { AuthService } from './auth.service';

describe('AuthService verified-identity safeguards', () => {
  const buildService = (overrides: Record<string, any> = {}) => {
    const prisma = overrides.prisma ?? {
      tenant: { findUnique: jest.fn().mockResolvedValue({ id: 'tenant-1', isActive: true }) },
      user: { findFirst: jest.fn().mockResolvedValue(null) },
      refreshToken: { findFirst: jest.fn(), delete: jest.fn() },
    };
    const googleIdentity = overrides.googleIdentity ?? { verify: jest.fn().mockResolvedValue({ email: 'owner@example.test' }) };
    const workspace = overrides.workspace ?? { createFromVerifiedIdentity: jest.fn() };
    const service = new AuthService(
      prisma,
      { sign: jest.fn() } as any,
      { get: jest.fn() } as any,
      { del: jest.fn() } as any,
      { record: jest.fn() } as any,
      { getEffectivePermissions: jest.fn() } as any,
      googleIdentity,
      { request: jest.fn(), consume: jest.fn() } as any,
      workspace,
    );
    return { service, prisma, workspace };
  };

  it('keeps Google login existing-user-only and does not create a workspace', async () => {
    const { service, workspace } = buildService();

    await expect(service.loginWithGoogle({ idToken: 'valid-token', tenantSlug: 'acme' } as any))
      .rejects.toBeInstanceOf(UnauthorizedException);

    expect(workspace.createFromVerifiedIdentity).not.toHaveBeenCalled();
  });

  it('rejects legacy password-based company registration', async () => {
    const { service } = buildService();

    await expect(service.registerCompany({} as any)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('rejects refreshes for users whose tenant is disabled', async () => {
    const prisma = {
      refreshToken: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'refresh-1',
          expiresAt: new Date(Date.now() + 60_000),
          user: { isActive: true, tenant: { isActive: false }, branches: [] },
        }),
        delete: jest.fn(),
      },
    };
    const { service } = buildService({ prisma });

    await expect(service.refreshToken({ refreshToken: 'x'.repeat(36) })).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.refreshToken.delete).not.toHaveBeenCalled();
  });
});
