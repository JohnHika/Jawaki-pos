import { ConflictException, ForbiddenException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { PlatformTeamService } from './platform-team.service';

// Real bcrypt (12 rounds) is deliberately slow; allow for a busy CI/dev machine.
jest.setTimeout(30_000);

describe('PlatformTeamService', () => {
  const ctx = { ip: '10.0.0.1' };
  const actor = (role: string, id = 'actor-1'): any => ({
    id,
    email: `${role.toLowerCase()}@archeaxon.com`,
    name: role,
    role,
    permissions: [],
    sessionId: 'sess-actor',
  });
  const staff = (overrides: Record<string, any> = {}) => ({
    id: 'staff-1',
    email: 'staff@archeaxon.com',
    name: 'Staff',
    phone: null,
    role: 'SUPPORT',
    status: 'ACTIVE',
    mustChangePassword: false,
    twoFactorEnabled: false,
    lastLoginAt: null,
    createdAt: new Date('2026-01-01'),
    ...overrides,
  });

  const build = (target: any | null = staff(), extra: Record<string, any> = {}) => {
    const prisma: any = {
      platformAdmin: {
        findUnique: jest.fn().mockResolvedValue(target),
        create: jest.fn().mockImplementation(async ({ data }) => ({ id: 'new-1', createdAt: new Date(), ...data })),
        update: jest.fn().mockImplementation(async ({ data }) => ({ ...(target ?? {}), ...data })),
        count: jest.fn().mockResolvedValue(1),
      },
      platformAdminSession: { updateMany: jest.fn().mockResolvedValue({ count: 3 }) },
      ...extra,
    };
    const audit: any = { log: jest.fn().mockResolvedValue(undefined) };
    return { service: new PlatformTeamService(prisma, audit), prisma, audit };
  };

  describe('create', () => {
    it('lets an admin add support staff and returns a one-time password that is hashed at rest', async () => {
      const { service, prisma, audit } = build(null);
      prisma.platformAdmin.findUnique.mockResolvedValue(null);
      const result = await service.create(
        actor('ADMIN'),
        { email: 'New@Archeaxon.com', name: ' New Hire ', role: 'SUPPORT' },
        ctx,
      );
      const data = prisma.platformAdmin.create.mock.calls[0][0].data;
      expect(data.email).toBe('new@archeaxon.com');
      expect(data.mustChangePassword).toBe(true);
      expect(data.passwordHash).not.toBe(result.temporaryPassword);
      expect(await bcrypt.compare(result.temporaryPassword, data.passwordHash)).toBe(true);
      expect(JSON.stringify(result.staff)).not.toContain('passwordHash');
      expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'TEAM_STAFF_CREATED' }));
    });

    it('stops an admin creating another admin or an owner', async () => {
      const { service } = build(null);
      for (const role of ['ADMIN', 'OWNER']) {
        await expect(
          service.create(actor('ADMIN'), { email: 'x@y.co', name: 'X', role }, ctx),
        ).rejects.toBeInstanceOf(ForbiddenException);
      }
    });

    it('stops non-managers entirely', async () => {
      const { service } = build(null);
      await expect(
        service.create(actor('SECURITY'), { email: 'x@y.co', name: 'X', role: 'VIEWER' }, ctx),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('rejects a duplicate email', async () => {
      const { service } = build(staff());
      await expect(
        service.create(actor('OWNER'), { email: 'staff@archeaxon.com', name: 'Dup', role: 'VIEWER' }, ctx),
      ).rejects.toBeInstanceOf(ConflictException);
    });
  });

  describe('update', () => {
    it('forbids changing your own role or status', async () => {
      const { service } = build(staff({ id: 'actor-1', role: 'OWNER' }));
      await expect(
        service.update(actor('OWNER'), 'actor-1', { role: 'VIEWER' }, ctx),
      ).rejects.toBeInstanceOf(ForbiddenException);
      await expect(
        service.update(actor('OWNER'), 'actor-1', { status: 'DISABLED' }, ctx),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('stops an admin touching another admin or an owner', async () => {
      for (const role of ['ADMIN', 'OWNER']) {
        const { service } = build(staff({ role }));
        await expect(
          service.update(actor('ADMIN'), 'staff-1', { name: 'Hacked' }, ctx),
        ).rejects.toBeInstanceOf(ForbiddenException);
      }
    });

    it('stops an admin promoting someone to admin', async () => {
      const { service } = build(staff({ role: 'SUPPORT' }));
      await expect(
        service.update(actor('ADMIN'), 'staff-1', { role: 'ADMIN' }, ctx),
      ).rejects.toBeInstanceOf(ForbiddenException);
    });

    it('never lets the last active owner be demoted or disabled', async () => {
      const { service, prisma } = build(staff({ role: 'OWNER' }));
      prisma.platformAdmin.count.mockResolvedValue(0);
      await expect(
        service.update(actor('OWNER'), 'staff-1', { role: 'ADMIN' }, ctx),
      ).rejects.toBeInstanceOf(ConflictException);
      await expect(
        service.update(actor('OWNER'), 'staff-1', { status: 'DISABLED' }, ctx),
      ).rejects.toBeInstanceOf(ConflictException);
    });

    it('signs the person out everywhere when disabled or re-roled', async () => {
      const { service, prisma, audit } = build(staff());
      await service.update(actor('ADMIN'), 'staff-1', { status: 'DISABLED' }, ctx);
      expect(prisma.platformAdminSession.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { adminId: 'staff-1', revokedAt: null },
          data: expect.objectContaining({ revokedReason: 'ACCOUNT_DISABLED' }),
        }),
      );
      expect(audit.log).toHaveBeenCalledWith(
        expect.objectContaining({ action: 'TEAM_STAFF_DISABLED', severity: 'WARN' }),
      );
    });

    it('does not revoke sessions for a plain name change', async () => {
      const { service, prisma } = build(staff());
      await service.update(actor('ADMIN'), 'staff-1', { name: 'Renamed' }, ctx);
      expect(prisma.platformAdminSession.updateMany).not.toHaveBeenCalled();
    });
  });

  describe('resetPassword / security actions', () => {
    it('issues a fresh forced-change password, unlocks and ends all sessions', async () => {
      const { service, prisma } = build(staff());
      const result = await service.resetPassword(actor('ADMIN'), 'staff-1', ctx);
      const data = prisma.platformAdmin.update.mock.calls[0][0].data;
      expect(data).toMatchObject({ mustChangePassword: true, lockedUntil: null, failedLoginAttempts: 0 });
      expect(await bcrypt.compare(result.temporaryPassword, data.passwordHash)).toBe(true);
      expect(prisma.platformAdminSession.updateMany).toHaveBeenCalled();
    });

    it('lets SECURITY unlock support staff but not admins', async () => {
      const ok = build(staff({ role: 'SUPPORT' }));
      await expect(ok.service.unlock(actor('SECURITY'), 'staff-1', ctx)).resolves.toEqual({ success: true });
      const blocked = build(staff({ role: 'ADMIN' }));
      await expect(blocked.service.unlock(actor('SECURITY'), 'staff-1', ctx)).rejects.toBeInstanceOf(
        ForbiddenException,
      );
    });

    it('keeps your current session when you revoke your own others', async () => {
      const { service, prisma } = build(staff({ id: 'actor-1', role: 'SECURITY' }));
      await service.revokeSessions(actor('SECURITY'), 'actor-1', ctx);
      expect(prisma.platformAdminSession.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ id: { not: 'sess-actor' } }),
        }),
      );
    });
  });
});
