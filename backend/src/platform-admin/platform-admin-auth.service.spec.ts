import { BadRequestException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import {
  LOCK_MINUTES,
  MAX_FAILED_LOGINS,
  PlatformAdminAuthService,
} from './platform-admin-auth.service';
import { base32Encode, sealSecret, sha256Hex, totpNow } from './security/totp.util';

// Real bcrypt (12 rounds) is deliberately slow; allow for a busy CI/dev machine.
jest.setTimeout(30_000);

describe('PlatformAdminAuthService', () => {
  const PASSWORD = 'Correct-Horse-9!';
  const ctx = { ip: '203.0.113.9', userAgent: 'jest' };
  const TOTP_SECRET = base32Encode(Buffer.from('12345678901234567890'));

  const baseAdmin = (overrides: Record<string, any> = {}) => ({
    id: 'admin-1',
    email: 'owner@arche-axon.xyz',
    name: 'Owner',
    phone: null,
    role: 'OWNER',
    status: 'ACTIVE',
    passwordHash: bcrypt.hashSync(PASSWORD, 4),
    mustChangePassword: false,
    failedLoginAttempts: 0,
    lockedUntil: null,
    twoFactorEnabled: false,
    twoFactorSecretEnc: null,
    twoFactorBackupHashes: null,
    lastLoginAt: null,
    createdAt: new Date('2026-01-01'),
    ...overrides,
  });

  const build = (admin: any | null, extra: Record<string, any> = {}) => {
    const prisma: any = {
      platformAdmin: {
        findUnique: jest.fn().mockResolvedValue(admin),
        update: jest.fn().mockResolvedValue(admin),
      },
      platformAdminSession: {
        create: jest.fn().mockImplementation(async ({ data }) => ({ id: 'sess-new', ...data })),
        findUnique: jest.fn(),
        findFirst: jest.fn(),
        update: jest.fn().mockResolvedValue({}),
        updateMany: jest.fn().mockResolvedValue({ count: 2 }),
      },
      ...extra,
    };
    const config: any = {
      get: jest.fn((key: string, fallback?: any) =>
        ({ JWT_SECRET: 'unit-test-secret', JWT_EXPIRES_IN: '15m' } as any)[key] ?? fallback,
      ),
    };
    const audit: any = { log: jest.fn().mockResolvedValue(undefined) };
    const jwt = new JwtService({});
    const service = new PlatformAdminAuthService(prisma, jwt, config, audit);
    return { service, prisma, audit, jwt };
  };

  describe('login', () => {
    it('signs in, resets failure counters, opens a session and audits it', async () => {
      const { service, prisma, audit, jwt } = build(baseAdmin({ failedLoginAttempts: 3 }));
      const result: any = await service.login(
        { email: '  OWNER@arche-axon.xyz ', password: PASSWORD },
        { ...ctx, device: 'Samsung S25' },
      );

      expect(prisma.platformAdmin.findUnique).toHaveBeenCalledWith({
        where: { email: 'owner@arche-axon.xyz' },
      });
      expect(prisma.platformAdmin.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ failedLoginAttempts: 0, lockedUntil: null }),
        }),
      );
      const created = prisma.platformAdminSession.create.mock.calls[0][0].data;
      expect(created.tokenHash).toBe(sha256Hex(result.refreshToken));
      expect(created.deviceLabel).toBe('Samsung S25');

      const claims: any = jwt.verify(result.accessToken, { secret: 'unit-test-secret' });
      expect(claims).toMatchObject({ sub: 'admin-1', type: 'platform', sid: 'sess-new' });
      expect(result.admin.permissions).toContain('team.manage');
      expect(result.admin).not.toHaveProperty('passwordHash');
      expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'AUTH_LOGIN_SUCCESS' }));
    });

    it('rejects an unknown email with the same generic error and audits it', async () => {
      const { service, audit } = build(null);
      await expect(
        service.login({ email: 'nobody@x.co', password: PASSWORD }, ctx),
      ).rejects.toThrow(new UnauthorizedException('Invalid email or password'));
      expect(audit.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'AUTH_LOGIN_FAILED_UNKNOWN', severity: 'WARN' }),
      );
    });

    it('counts a wrong password and locks the account on the fifth failure', async () => {
      const { service, prisma, audit } = build(baseAdmin({ failedLoginAttempts: MAX_FAILED_LOGINS - 1 }));
      await expect(
        service.login({ email: 'owner@arche-axon.xyz', password: 'wrong-password-1A!' }, ctx),
      ).rejects.toBeInstanceOf(UnauthorizedException);

      const data = prisma.platformAdmin.update.mock.calls[0][0].data;
      expect(data.lockedUntil.getTime()).toBeGreaterThan(Date.now() + (LOCK_MINUTES - 1) * 60_000);
      expect(prisma.platformAdminSession.create).not.toHaveBeenCalled();
      expect(audit.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'AUTH_ACCOUNT_LOCKED', severity: 'CRITICAL' }),
      );
    });

    it('refuses a locked account even with the right password', async () => {
      const { service, prisma } = build(
        baseAdmin({ lockedUntil: new Date(Date.now() + 10 * 60_000) }),
      );
      await expect(
        service.login({ email: 'owner@arche-axon.xyz', password: PASSWORD }, ctx),
      ).rejects.toMatchObject({ status: 423 });
      expect(prisma.platformAdminSession.create).not.toHaveBeenCalled();
    });

    it('treats a disabled account like a bad password', async () => {
      const { service, audit } = build(baseAdmin({ status: 'DISABLED' }));
      await expect(
        service.login({ email: 'owner@arche-axon.xyz', password: PASSWORD }, ctx),
      ).rejects.toBeInstanceOf(UnauthorizedException);
      expect(audit.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'AUTH_LOGIN_DISABLED_ACCOUNT' }),
      );
    });

    describe('with two-factor enabled', () => {
      const withTotp = () =>
        baseAdmin({
          twoFactorEnabled: true,
          twoFactorSecretEnc: sealSecret(TOTP_SECRET, 'unit-test-secret'),
        });

      it('asks for a code instead of issuing a session', async () => {
        const { service, prisma } = build(withTotp());
        const result = await service.login({ email: 'owner@arche-axon.xyz', password: PASSWORD }, ctx);
        expect(result).toEqual({ requiresTwoFactor: true });
        expect(prisma.platformAdminSession.create).not.toHaveBeenCalled();
      });

      it('accepts a valid authenticator code', async () => {
        const { service } = build(withTotp());
        const result: any = await service.login(
          { email: 'owner@arche-axon.xyz', password: PASSWORD, otp: totpNow(TOTP_SECRET) },
          ctx,
        );
        expect(result.accessToken).toBeDefined();
      });

      it('counts a wrong code as a failed attempt', async () => {
        const { service, prisma, audit } = build(withTotp());
        await expect(
          service.login({ email: 'owner@arche-axon.xyz', password: PASSWORD, otp: '000000' }, ctx),
        ).rejects.toThrow('Invalid verification code');
        expect(prisma.platformAdmin.update.mock.calls[0][0].data.failedLoginAttempts).toBe(1);
        expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'AUTH_2FA_FAILED' }));
      });

      it('accepts a backup code once and burns it', async () => {
        const hash = sha256Hex('K7QD9MXA');
        const { service, prisma } = build({ ...withTotp(), twoFactorBackupHashes: [hash, 'other'] });
        const result: any = await service.login(
          { email: 'owner@arche-axon.xyz', password: PASSWORD, otp: 'k7qd-9mxa' },
          ctx,
        );
        expect(result.accessToken).toBeDefined();
        expect(prisma.platformAdmin.update).toHaveBeenCalledWith(
          expect.objectContaining({ data: { twoFactorBackupHashes: ['other'] } }),
        );
      });
    });
  });

  describe('refresh', () => {
    const session = (overrides: Record<string, any> = {}) => ({
      id: 'sess-1',
      adminId: 'admin-1',
      tokenHash: sha256Hex('current-token'),
      prevTokenHash: null,
      revokedAt: null,
      expiresAt: new Date(Date.now() + 86_400_000),
      lastUsedAt: new Date(),
      ipAddress: '1.1.1.1',
      admin: baseAdmin(),
      ...overrides,
    });

    it('rotates the refresh token and remembers the retired one', async () => {
      const { service, prisma } = build(null);
      prisma.platformAdminSession.findUnique.mockResolvedValue(session());
      const result: any = await service.refresh('current-token', ctx);

      expect(result.refreshToken).not.toBe('current-token');
      const update = prisma.platformAdminSession.update.mock.calls[0][0];
      expect(update.data.prevTokenHash).toBe(sha256Hex('current-token'));
      expect(update.data.tokenHash).toBe(sha256Hex(result.refreshToken));
    });

    it('revokes the whole session when a retired token is replayed long after rotation', async () => {
      const { service, prisma, audit } = build(null);
      prisma.platformAdminSession.findUnique.mockResolvedValue(null);
      prisma.platformAdminSession.findFirst.mockResolvedValue(
        session({ prevTokenHash: sha256Hex('stolen'), lastUsedAt: new Date(Date.now() - 120_000) }),
      );
      await expect(service.refresh('stolen', ctx)).rejects.toBeInstanceOf(UnauthorizedException);
      expect(prisma.platformAdminSession.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ revokedReason: 'REFRESH_TOKEN_REUSE' }),
        }),
      );
      expect(audit.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'AUTH_REFRESH_TOKEN_REUSE', severity: 'CRITICAL' }),
      );
    });

    it('does not kill the session when the replay is just a near-simultaneous client retry', async () => {
      const { service, prisma } = build(null);
      prisma.platformAdminSession.findUnique.mockResolvedValue(null);
      prisma.platformAdminSession.findFirst.mockResolvedValue(
        session({ prevTokenHash: sha256Hex('racy'), lastUsedAt: new Date(Date.now() - 2_000) }),
      );
      await expect(service.refresh('racy', ctx)).rejects.toBeInstanceOf(UnauthorizedException);
      expect(prisma.platformAdminSession.update).not.toHaveBeenCalled();
    });

    it.each([
      ['revoked', { revokedAt: new Date() }],
      ['expired', { expiresAt: new Date(Date.now() - 1000) }],
      ['for a disabled admin', { admin: baseAdmin({ status: 'DISABLED' }) }],
    ])('refuses a %s session', async (_l, overrides) => {
      const { service, prisma } = build(null);
      prisma.platformAdminSession.findUnique.mockResolvedValue(session(overrides));
      await expect(service.refresh('current-token', ctx)).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
    });
  });

  describe('changePassword', () => {
    const actor: any = {
      id: 'admin-1',
      email: 'owner@arche-axon.xyz',
      role: 'OWNER',
      permissions: [],
      sessionId: 'sess-keep',
      name: 'Owner',
    };

    it('rejects a wrong current password', async () => {
      const { service } = build(baseAdmin());
      await expect(
        service.changePassword(actor, { currentPassword: 'nope', newPassword: 'New-Passw0rd-xyz!' }),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('rejects a weak new password', async () => {
      const { service } = build(baseAdmin());
      await expect(
        service.changePassword(actor, { currentPassword: PASSWORD, newPassword: 'weakpassword' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects reusing the current password', async () => {
      const { service } = build(baseAdmin());
      await expect(
        service.changePassword(actor, { currentPassword: PASSWORD, newPassword: PASSWORD }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('updates the hash, clears the forced-change flag and signs out other devices', async () => {
      const { service, prisma } = build(baseAdmin({ mustChangePassword: true }));
      const result = await service.changePassword(actor, {
        currentPassword: PASSWORD,
        newPassword: 'New-Passw0rd-xyz!',
      });
      const data = prisma.platformAdmin.update.mock.calls[0][0].data;
      expect(data.mustChangePassword).toBe(false);
      expect(await bcrypt.compare('New-Passw0rd-xyz!', data.passwordHash)).toBe(true);
      expect(prisma.platformAdminSession.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ id: { not: 'sess-keep' } }),
        }),
      );
      expect(result.otherSessionsRevoked).toBe(2);
    });
  });
});
