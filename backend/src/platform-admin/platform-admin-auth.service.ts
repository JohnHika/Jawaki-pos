import {
  BadRequestException,
  ConflictException,
  HttpException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Prisma } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { randomBytes } from 'crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { PlatformAuditService, RequestContext } from './audit/platform-audit.service';
import { PlatformAdminActor, PlatformAdminJwtPayload } from './guards/platform-admin.guard';
import { permissionsForRole } from './rbac/platform-permissions';
import {
  PASSWORD_POLICY_MESSAGE,
  generateBackupCodes,
  generateTotpSecret,
  normalizeBackupCode,
  openSecret,
  otpauthUri,
  passwordMeetsPolicy,
  sealSecret,
  sha256Hex,
  verifyTotp,
} from './security/totp.util';

const BCRYPT_ROUNDS = 12;
export const MAX_FAILED_LOGINS = 5;
export const LOCK_MINUTES = 15;
export const REFRESH_TOKEN_DAYS = 14;
/** A replay of the previous refresh token this soon after rotation is a client race, not theft. */
const REFRESH_RACE_GRACE_MS = 15_000;

let dummyHash: string | undefined;
function getDummyHash(): string {
  // Compared against when the email is unknown so response time doesn't leak which emails exist.
  dummyHash ??= bcrypt.hashSync('not-a-real-account-password', BCRYPT_ROUNDS);
  return dummyHash;
}

/**
 * Seeds the first platform owner from PLATFORM_ADMIN_EMAIL /
 * PLATFORM_ADMIN_PASSWORD on boot when the table is empty. The password is
 * read from env, hashed, and never logged or returned.
 */
@Injectable()
export class PlatformAdminBootstrapService implements OnModuleInit {
  private readonly logger = new Logger(PlatformAdminBootstrapService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {}

  async onModuleInit(): Promise<void> {
    try {
      const email = this.configService.get<string>('PLATFORM_ADMIN_EMAIL');
      const password = this.configService.get<string>('PLATFORM_ADMIN_PASSWORD');

      if (!email || !password) {
        this.logger.warn(
          'PLATFORM_ADMIN_EMAIL/PLATFORM_ADMIN_PASSWORD not set — no platform admin seeded',
        );
        return;
      }

      const existing = await this.prisma.platformAdmin.findFirst({ select: { id: true } });
      if (existing) {
        return; // Table already has staff; nothing to do.
      }

      const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);
      await this.prisma.platformAdmin.create({
        data: {
          email: email.trim().toLowerCase(),
          passwordHash,
          name: 'Platform Owner',
          role: 'OWNER',
          passwordChangedAt: new Date(),
        },
        select: { id: true },
      });
      this.logger.log(`Seeded platform owner account ${email}`);
    } catch (error) {
      // Never block app boot on seeding; log and continue.
      this.logger.error(
        `Platform admin bootstrap failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
}

export interface StaffProfile {
  id: string;
  email: string;
  name: string;
  phone: string | null;
  role: string;
  status: string;
  permissions: string[];
  mustChangePassword: boolean;
  twoFactorEnabled: boolean;
  lastLoginAt: Date | null;
  createdAt: Date;
}

export function toStaffProfile(admin: any): StaffProfile {
  return {
    id: admin.id,
    email: admin.email,
    name: admin.name,
    phone: admin.phone ?? null,
    role: admin.role,
    status: admin.status,
    permissions: permissionsForRole(admin.role),
    mustChangePassword: !!admin.mustChangePassword,
    twoFactorEnabled: !!admin.twoFactorEnabled,
    lastLoginAt: admin.lastLoginAt ?? null,
    createdAt: admin.createdAt,
  };
}

@Injectable()
export class PlatformAdminAuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    private readonly audit: PlatformAuditService,
  ) {}

  // ---------------------------------------------------------------- login

  async login(
    input: { email: string; password: string; otp?: string },
    ctx: RequestContext & { device?: string } = {},
  ) {
    const email = input.email.trim().toLowerCase();
    const admin = await this.prisma.platformAdmin.findUnique({ where: { email } });
    const now = new Date();

    if (admin?.lockedUntil && admin.lockedUntil > now) {
      const retryAfterSeconds = Math.ceil((admin.lockedUntil.getTime() - now.getTime()) / 1000);
      await this.audit.log({
        action: 'AUTH_LOGIN_BLOCKED_LOCKED',
        category: 'AUTH',
        severity: 'WARN',
        actor: { id: admin.id, email: admin.email, role: admin.role },
        summary: `Sign-in attempt blocked: ${admin.email} is locked`,
        ctx,
      });
      throw new HttpException(
        {
          statusCode: 423,
          error: 'Locked',
          code: 'ACCOUNT_LOCKED',
          message: `Too many failed attempts. Try again in ${Math.ceil(retryAfterSeconds / 60)} minute(s).`,
          retryAfterSeconds,
        },
        423,
      );
    }

    const passwordOk = admin
      ? await bcrypt.compare(input.password, admin.passwordHash)
      : (await bcrypt.compare(input.password, getDummyHash()), false);

    if (!admin || !passwordOk || admin.status !== 'ACTIVE') {
      await this.registerFailure(admin, email, ctx, admin && admin.status !== 'ACTIVE' ? 'disabled' : 'password');
      throw new UnauthorizedException('Invalid email or password');
    }

    if (admin.twoFactorEnabled) {
      if (!input.otp) {
        return { requiresTwoFactor: true as const };
      }
      const otpOk = await this.verifySecondFactor(admin, input.otp);
      if (!otpOk) {
        await this.registerFailure(admin, email, ctx, '2fa');
        throw new UnauthorizedException('Invalid verification code');
      }
    }

    await this.prisma.platformAdmin.update({
      where: { id: admin.id },
      data: {
        failedLoginAttempts: 0,
        lockedUntil: null,
        lastLoginAt: now,
        lastLoginIp: ctx.ip ?? null,
      },
    });

    const tokens = await this.issueSession(admin, ctx);
    await this.audit.log({
      action: 'AUTH_LOGIN_SUCCESS',
      category: 'AUTH',
      actor: { id: admin.id, email: admin.email, role: admin.role },
      summary: `${admin.email} signed in`,
      metadata: { device: ctx.device ?? null, twoFactor: admin.twoFactorEnabled },
      ctx,
    });

    return {
      ...tokens,
      admin: toStaffProfile({ ...admin, lastLoginAt: now }),
    };
  }

  private async registerFailure(
    admin: any | null,
    email: string,
    ctx: RequestContext,
    reason: 'password' | '2fa' | 'disabled',
  ) {
    if (!admin) {
      await this.audit.log({
        action: 'AUTH_LOGIN_FAILED_UNKNOWN',
        category: 'AUTH',
        severity: 'WARN',
        actor: { email },
        summary: `Failed sign-in for unknown account ${email}`,
        ctx,
      });
      return;
    }

    const attempts = (admin.failedLoginAttempts ?? 0) + 1;
    const lock = attempts >= MAX_FAILED_LOGINS;
    await this.prisma.platformAdmin.update({
      where: { id: admin.id },
      data: lock
        ? {
            failedLoginAttempts: 0,
            lockedUntil: new Date(Date.now() + LOCK_MINUTES * 60_000),
          }
        : { failedLoginAttempts: attempts },
    });

    await this.audit.log({
      action:
        reason === '2fa'
          ? 'AUTH_2FA_FAILED'
          : reason === 'disabled'
            ? 'AUTH_LOGIN_DISABLED_ACCOUNT'
            : 'AUTH_LOGIN_FAILED',
      category: 'AUTH',
      severity: 'WARN',
      actor: { id: admin.id, email: admin.email, role: admin.role },
      summary: `Failed sign-in (${reason}) for ${admin.email} — attempt ${attempts}/${MAX_FAILED_LOGINS}`,
      ctx,
    });

    if (lock) {
      await this.audit.log({
        action: 'AUTH_ACCOUNT_LOCKED',
        category: 'SECURITY',
        severity: 'CRITICAL',
        actor: { id: admin.id, email: admin.email, role: admin.role },
        targetType: 'PlatformAdmin',
        targetId: admin.id,
        summary: `${admin.email} locked for ${LOCK_MINUTES} minutes after ${MAX_FAILED_LOGINS} failed attempts`,
        ctx,
      });
    }
  }

  // --------------------------------------------------------------- tokens

  private async issueSession(admin: any, ctx: RequestContext & { device?: string }) {
    const refreshToken = randomBytes(48).toString('base64url');
    const session = await this.prisma.platformAdminSession.create({
      data: {
        adminId: admin.id,
        tokenHash: sha256Hex(refreshToken),
        userAgent: ctx.userAgent ?? null,
        ipAddress: ctx.ip ?? null,
        deviceLabel: ctx.device?.slice(0, 80) ?? null,
        expiresAt: new Date(Date.now() + REFRESH_TOKEN_DAYS * 86_400_000),
      },
    });
    return { ...this.signAccessToken(admin, session.id), refreshToken, sessionId: session.id };
  }

  private signAccessToken(admin: { id: string; email: string }, sessionId: string) {
    const payload: PlatformAdminJwtPayload = {
      sub: admin.id,
      email: admin.email,
      role: 'PLATFORM_ADMIN',
      type: 'platform',
      sid: sessionId,
    };
    const expiresIn = this.configService.get<string>('JWT_EXPIRES_IN', '15m');
    const accessToken = this.jwtService.sign(payload, {
      secret: this.configService.get<string>('JWT_SECRET'),
      expiresIn,
    });
    const decoded: any = this.jwtService.decode(accessToken);
    return {
      accessToken,
      accessTokenExpiresAt: decoded?.exp ? new Date(decoded.exp * 1000).toISOString() : null,
    };
  }

  async refresh(refreshToken: string, ctx: RequestContext = {}) {
    const hash = sha256Hex(refreshToken);
    const session = await this.prisma.platformAdminSession.findUnique({
      where: { tokenHash: hash },
      include: { admin: true },
    });
    const now = new Date();

    if (!session) {
      const replayed = await this.prisma.platformAdminSession.findFirst({
        where: { prevTokenHash: hash },
        include: { admin: true },
      });
      if (replayed && !replayed.revokedAt) {
        const sinceRotation = now.getTime() - replayed.lastUsedAt.getTime();
        if (sinceRotation > REFRESH_RACE_GRACE_MS) {
          await this.prisma.platformAdminSession.update({
            where: { id: replayed.id },
            data: { revokedAt: now, revokedReason: 'REFRESH_TOKEN_REUSE' },
          });
          await this.audit.log({
            action: 'AUTH_REFRESH_TOKEN_REUSE',
            category: 'SECURITY',
            severity: 'CRITICAL',
            actor: { id: replayed.admin.id, email: replayed.admin.email, role: replayed.admin.role },
            targetType: 'PlatformAdminSession',
            targetId: replayed.id,
            summary: `A retired refresh token for ${replayed.admin.email} was replayed; the session was revoked`,
            ctx,
          });
        }
      }
      throw new UnauthorizedException('Session expired. Please sign in again.');
    }

    if (session.revokedAt || session.expiresAt <= now || session.admin.status !== 'ACTIVE') {
      throw new UnauthorizedException('Session expired. Please sign in again.');
    }

    const nextToken = randomBytes(48).toString('base64url');
    await this.prisma.platformAdminSession.update({
      where: { id: session.id },
      data: {
        tokenHash: sha256Hex(nextToken),
        prevTokenHash: hash,
        lastUsedAt: now,
        ipAddress: ctx.ip ?? session.ipAddress,
        expiresAt: new Date(now.getTime() + REFRESH_TOKEN_DAYS * 86_400_000),
      },
    });

    return {
      ...this.signAccessToken(session.admin, session.id),
      refreshToken: nextToken,
      admin: toStaffProfile(session.admin),
    };
  }

  async logout(actor: PlatformAdminActor, ctx: RequestContext = {}) {
    await this.prisma.platformAdminSession.updateMany({
      where: { id: actor.sessionId, revokedAt: null },
      data: { revokedAt: new Date(), revokedReason: 'LOGOUT' },
    });
    await this.audit.log({
      action: 'AUTH_LOGOUT',
      category: 'AUTH',
      actor,
      summary: `${actor.email} signed out`,
      ctx,
    });
    return { success: true };
  }

  // -------------------------------------------------------------- profile

  async findById(id: string) {
    const admin = await this.prisma.platformAdmin.findUnique({ where: { id } });
    return admin ? toStaffProfile(admin) : null;
  }

  async changePassword(
    actor: PlatformAdminActor,
    input: { currentPassword: string; newPassword: string },
    ctx: RequestContext = {},
  ) {
    const admin = await this.prisma.platformAdmin.findUnique({ where: { id: actor.id } });
    if (!admin) throw new NotFoundException('Account no longer exists');
    if (!(await bcrypt.compare(input.currentPassword, admin.passwordHash))) {
      await this.audit.log({
        action: 'AUTH_PASSWORD_CHANGE_FAILED',
        category: 'AUTH',
        severity: 'WARN',
        actor,
        summary: `${actor.email} entered the wrong current password`,
        ctx,
      });
      throw new UnauthorizedException('Current password is incorrect');
    }
    if (!passwordMeetsPolicy(input.newPassword)) {
      throw new BadRequestException(PASSWORD_POLICY_MESSAGE);
    }
    if (input.currentPassword === input.newPassword) {
      throw new BadRequestException('Choose a password different from the current one.');
    }

    const now = new Date();
    await this.prisma.platformAdmin.update({
      where: { id: admin.id },
      data: {
        passwordHash: await bcrypt.hash(input.newPassword, BCRYPT_ROUNDS),
        mustChangePassword: false,
        passwordChangedAt: now,
      },
    });
    const revoked = await this.prisma.platformAdminSession.updateMany({
      where: { adminId: admin.id, revokedAt: null, id: { not: actor.sessionId } },
      data: { revokedAt: now, revokedReason: 'PASSWORD_CHANGED' },
    });
    await this.audit.log({
      action: 'AUTH_PASSWORD_CHANGED',
      category: 'AUTH',
      actor,
      summary: `${actor.email} changed their password (${revoked.count} other session(s) signed out)`,
      ctx,
    });
    return { success: true, otherSessionsRevoked: revoked.count };
  }

  // ------------------------------------------------------------- sessions

  async listSessions(adminId: string, currentSessionId: string) {
    const rows = await this.prisma.platformAdminSession.findMany({
      where: { adminId, revokedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { lastUsedAt: 'desc' },
    });
    return rows.map((s) => ({
      id: s.id,
      deviceLabel: s.deviceLabel,
      userAgent: s.userAgent,
      ipAddress: s.ipAddress,
      createdAt: s.createdAt,
      lastUsedAt: s.lastUsedAt,
      expiresAt: s.expiresAt,
      current: s.id === currentSessionId,
    }));
  }

  async revokeSession(actor: PlatformAdminActor, sessionId: string, ctx: RequestContext = {}) {
    const result = await this.prisma.platformAdminSession.updateMany({
      where: { id: sessionId, adminId: actor.id, revokedAt: null },
      data: { revokedAt: new Date(), revokedReason: 'USER_REVOKED' },
    });
    if (result.count === 0) throw new NotFoundException('Session not found');
    await this.audit.log({
      action: 'AUTH_SESSION_REVOKED',
      category: 'AUTH',
      actor,
      targetType: 'PlatformAdminSession',
      targetId: sessionId,
      summary: `${actor.email} signed out a device`,
      ctx,
    });
    return { success: true };
  }

  async revokeOtherSessions(actor: PlatformAdminActor, ctx: RequestContext = {}) {
    const result = await this.prisma.platformAdminSession.updateMany({
      where: { adminId: actor.id, revokedAt: null, id: { not: actor.sessionId } },
      data: { revokedAt: new Date(), revokedReason: 'USER_REVOKED_OTHERS' },
    });
    await this.audit.log({
      action: 'AUTH_OTHER_SESSIONS_REVOKED',
      category: 'AUTH',
      actor,
      summary: `${actor.email} signed out ${result.count} other device(s)`,
      ctx,
    });
    return { success: true, revoked: result.count };
  }

  // ------------------------------------------------------------------ 2FA

  private sealingKey(): string {
    return (
      this.configService.get<string>('PLATFORM_2FA_KEY') ||
      this.configService.get<string>('JWT_REFRESH_SECRET') ||
      this.configService.get<string>('JWT_SECRET') ||
      ''
    );
  }

  private async verifySecondFactor(admin: any, code: string): Promise<boolean> {
    if (admin.twoFactorSecretEnc) {
      try {
        const secret = openSecret(admin.twoFactorSecretEnc, this.sealingKey());
        if (verifyTotp(secret, code)) return true;
      } catch {
        // fall through to backup codes
      }
    }
    const hashes: string[] = Array.isArray(admin.twoFactorBackupHashes)
      ? (admin.twoFactorBackupHashes as string[])
      : [];
    const candidate = sha256Hex(normalizeBackupCode(code));
    if (hashes.includes(candidate)) {
      await this.prisma.platformAdmin.update({
        where: { id: admin.id },
        data: { twoFactorBackupHashes: hashes.filter((h) => h !== candidate) },
      });
      await this.audit.log({
        action: 'AUTH_BACKUP_CODE_USED',
        category: 'SECURITY',
        severity: 'WARN',
        actor: { id: admin.id, email: admin.email, role: admin.role },
        summary: `${admin.email} signed in with a backup code (${hashes.length - 1} left)`,
      });
      return true;
    }
    return false;
  }

  async startTwoFactorSetup(actor: PlatformAdminActor) {
    const admin = await this.prisma.platformAdmin.findUnique({ where: { id: actor.id } });
    if (!admin) throw new NotFoundException('Account no longer exists');
    if (admin.twoFactorEnabled) {
      throw new ConflictException('Two-factor authentication is already on.');
    }
    const secret = generateTotpSecret();
    await this.prisma.platformAdmin.update({
      where: { id: admin.id },
      data: { twoFactorSecretEnc: sealSecret(secret, this.sealingKey()) },
    });
    return { secret, otpauthUri: otpauthUri(secret, admin.email) };
  }

  async enableTwoFactor(actor: PlatformAdminActor, code: string, ctx: RequestContext = {}) {
    const admin = await this.prisma.platformAdmin.findUnique({ where: { id: actor.id } });
    if (!admin?.twoFactorSecretEnc) {
      throw new BadRequestException('Start two-factor setup first.');
    }
    if (admin.twoFactorEnabled) {
      throw new ConflictException('Two-factor authentication is already on.');
    }
    const secret = openSecret(admin.twoFactorSecretEnc, this.sealingKey());
    if (!verifyTotp(secret, code)) {
      throw new BadRequestException('That code is not valid. Check the time on your phone and try again.');
    }
    const backupCodes = generateBackupCodes();
    await this.prisma.platformAdmin.update({
      where: { id: admin.id },
      data: {
        twoFactorEnabled: true,
        twoFactorBackupHashes: backupCodes.map((c) => sha256Hex(normalizeBackupCode(c))),
      },
    });
    await this.audit.log({
      action: 'AUTH_2FA_ENABLED',
      category: 'SECURITY',
      actor,
      summary: `${actor.email} turned on two-factor authentication`,
      ctx,
    });
    return { success: true, backupCodes };
  }

  async disableTwoFactor(
    actor: PlatformAdminActor,
    input: { password: string; code: string },
    ctx: RequestContext = {},
  ) {
    const admin = await this.prisma.platformAdmin.findUnique({ where: { id: actor.id } });
    if (!admin) throw new NotFoundException('Account no longer exists');
    if (!admin.twoFactorEnabled) {
      throw new BadRequestException('Two-factor authentication is not on.');
    }
    if (!(await bcrypt.compare(input.password, admin.passwordHash))) {
      throw new UnauthorizedException('Password is incorrect');
    }
    if (!(await this.verifySecondFactor(admin, input.code))) {
      throw new UnauthorizedException('Invalid verification code');
    }
    await this.prisma.platformAdmin.update({
      where: { id: admin.id },
      data: { twoFactorEnabled: false, twoFactorSecretEnc: null, twoFactorBackupHashes: Prisma.DbNull },
    });
    await this.audit.log({
      action: 'AUTH_2FA_DISABLED',
      category: 'SECURITY',
      severity: 'WARN',
      actor,
      summary: `${actor.email} turned off two-factor authentication`,
      ctx,
    });
    return { success: true };
  }
}
