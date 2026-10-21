import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../common/prisma/prisma.service';
import { PlatformAuditService, RequestContext } from './audit/platform-audit.service';
import { PlatformAdminActor } from './guards/platform-admin.guard';
import {
  PLATFORM_ROLES,
  PlatformRole,
  ROLE_DESCRIPTIONS,
  ROLE_PERMISSIONS,
  ROLE_RANK,
  assignableRoles,
  canManageRole,
  isPlatformRole,
  permissionsForRole,
} from './rbac/platform-permissions';
import { generateTempPassword } from './security/totp.util';
import { toStaffProfile } from './platform-admin-auth.service';

/** OWNER may act on anyone; everyone else only on strictly lower-ranked staff. */
export function canSecureTarget(actorRole: string, targetRole: string): boolean {
  if (actorRole === 'OWNER') return true;
  const a = ROLE_RANK[actorRole as PlatformRole] ?? 0;
  const t = ROLE_RANK[targetRole as PlatformRole] ?? 0;
  return a > t;
}

@Injectable()
export class PlatformTeamService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: PlatformAuditService,
  ) {}

  roleCatalog(actorRole: string) {
    const assignable = assignableRoles(actorRole);
    return {
      roles: PLATFORM_ROLES.map((role) => ({
        role,
        rank: ROLE_RANK[role],
        description: ROLE_DESCRIPTIONS[role],
        permissions: ROLE_PERMISSIONS[role],
        assignable: assignable.includes(role),
      })),
    };
  }

  async list() {
    const now = new Date();
    const [admins, sessionCounts] = await Promise.all([
      this.prisma.platformAdmin.findMany({ orderBy: [{ createdAt: 'asc' }] }),
      this.prisma.platformAdminSession.groupBy({
        by: ['adminId'],
        where: { revokedAt: null, expiresAt: { gt: now } },
        _count: true,
      }),
    ]);
    const counts = new Map(sessionCounts.map((r) => [r.adminId, r._count]));
    return {
      items: admins.map((a) => ({
        ...toStaffProfile(a),
        locked: !!a.lockedUntil && a.lockedUntil > now,
        lockedUntil: a.lockedUntil && a.lockedUntil > now ? a.lockedUntil : null,
        failedLoginAttempts: a.failedLoginAttempts,
        lastLoginIp: a.lastLoginIp,
        activeSessions: counts.get(a.id) ?? 0,
      })),
      total: admins.length,
    };
  }

  async get(id: string) {
    const admin = await this.prisma.platformAdmin.findUnique({ where: { id } });
    if (!admin) throw new NotFoundException('Staff member not found');
    const now = new Date();
    const [activeSessions, recent] = await Promise.all([
      this.prisma.platformAdminSession.count({
        where: { adminId: id, revokedAt: null, expiresAt: { gt: now } },
      }),
      this.prisma.platformAuditLog.findMany({
        where: { actorId: id },
        orderBy: { createdAt: 'desc' },
        take: 15,
      }),
    ]);
    return {
      ...toStaffProfile(admin),
      locked: !!admin.lockedUntil && admin.lockedUntil > now,
      lockedUntil: admin.lockedUntil && admin.lockedUntil > now ? admin.lockedUntil : null,
      failedLoginAttempts: admin.failedLoginAttempts,
      lastLoginIp: admin.lastLoginIp,
      passwordChangedAt: admin.passwordChangedAt,
      activeSessions,
      recentActivity: recent,
    };
  }

  async create(
    actor: PlatformAdminActor,
    dto: { email: string; name: string; role: string; phone?: string },
    ctx: RequestContext,
  ) {
    if (!isPlatformRole(dto.role) || !canManageRole(actor.role, dto.role)) {
      throw new ForbiddenException(`Your role cannot create ${dto.role} accounts.`);
    }
    const email = dto.email.trim().toLowerCase();
    if (await this.prisma.platformAdmin.findUnique({ where: { email } })) {
      throw new ConflictException('A staff member with that email already exists.');
    }

    const temporaryPassword = generateTempPassword();
    const created = await this.prisma.platformAdmin.create({
      data: {
        email,
        name: dto.name.trim(),
        role: dto.role,
        phone: dto.phone?.trim() || null,
        passwordHash: await bcrypt.hash(temporaryPassword, 12),
        mustChangePassword: true,
        createdById: actor.id,
      },
    });

    await this.audit.log({
      action: 'TEAM_STAFF_CREATED',
      category: 'TEAM',
      severity: dto.role === 'OWNER' || dto.role === 'ADMIN' ? 'WARN' : 'INFO',
      actor,
      targetType: 'PlatformAdmin',
      targetId: created.id,
      summary: `${actor.email} added ${email} as ${dto.role}`,
      metadata: { role: dto.role },
      ctx,
    });

    return { staff: toStaffProfile(created), temporaryPassword };
  }

  async update(
    actor: PlatformAdminActor,
    id: string,
    dto: { name?: string; role?: string; status?: string; phone?: string },
    ctx: RequestContext,
  ) {
    const target = await this.requireTarget(id);

    if (id === actor.id && (dto.role !== undefined || dto.status !== undefined)) {
      throw new ForbiddenException('You cannot change your own role or status.');
    }
    if (!canManageRole(actor.role, target.role)) {
      throw new ForbiddenException('Your role cannot manage this staff member.');
    }
    if (dto.role !== undefined) {
      if (!isPlatformRole(dto.role) || !canManageRole(actor.role, dto.role)) {
        throw new ForbiddenException(`Your role cannot assign ${dto.role}.`);
      }
    }

    const losesOwnership =
      target.role === 'OWNER' &&
      ((dto.role !== undefined && dto.role !== 'OWNER') || dto.status === 'DISABLED');
    if (losesOwnership) {
      await this.assertAnotherActiveOwner(id);
    }

    const data: Record<string, unknown> = {};
    if (dto.name !== undefined) data.name = dto.name.trim();
    if (dto.phone !== undefined) data.phone = dto.phone.trim() || null;
    if (dto.role !== undefined) data.role = dto.role;
    if (dto.status !== undefined) data.status = dto.status;
    if (Object.keys(data).length === 0) {
      throw new BadRequestException('Nothing to update.');
    }

    const updated = await this.prisma.platformAdmin.update({ where: { id }, data });

    const security = dto.role !== undefined || dto.status !== undefined;
    if (security) {
      // A role/status change must take effect now, not at next token refresh.
      await this.prisma.platformAdminSession.updateMany({
        where: { adminId: id, revokedAt: null },
        data: {
          revokedAt: new Date(),
          revokedReason: dto.status === 'DISABLED' ? 'ACCOUNT_DISABLED' : 'ROLE_CHANGED',
        },
      });
    }

    await this.audit.log({
      action:
        dto.status === 'DISABLED'
          ? 'TEAM_STAFF_DISABLED'
          : dto.status === 'ACTIVE' && target.status !== 'ACTIVE'
            ? 'TEAM_STAFF_ENABLED'
            : dto.role !== undefined && dto.role !== target.role
              ? 'TEAM_ROLE_CHANGED'
              : 'TEAM_STAFF_UPDATED',
      category: 'TEAM',
      severity: security ? 'WARN' : 'INFO',
      actor,
      targetType: 'PlatformAdmin',
      targetId: id,
      summary: `${actor.email} updated ${target.email}`,
      metadata: {
        before: { role: target.role, status: target.status, name: target.name },
        after: data,
      },
      ctx,
    });

    return toStaffProfile(updated);
  }

  async resetPassword(actor: PlatformAdminActor, id: string, ctx: RequestContext) {
    const target = await this.requireTarget(id);
    if (id === actor.id) {
      throw new ForbiddenException('Use Change password for your own account.');
    }
    if (!canManageRole(actor.role, target.role)) {
      throw new ForbiddenException('Your role cannot manage this staff member.');
    }
    const temporaryPassword = generateTempPassword();
    await this.prisma.platformAdmin.update({
      where: { id },
      data: {
        passwordHash: await bcrypt.hash(temporaryPassword, 12),
        mustChangePassword: true,
        failedLoginAttempts: 0,
        lockedUntil: null,
      },
    });
    await this.prisma.platformAdminSession.updateMany({
      where: { adminId: id, revokedAt: null },
      data: { revokedAt: new Date(), revokedReason: 'PASSWORD_RESET' },
    });
    await this.audit.log({
      action: 'TEAM_PASSWORD_RESET',
      category: 'TEAM',
      severity: 'WARN',
      actor,
      targetType: 'PlatformAdmin',
      targetId: id,
      summary: `${actor.email} reset the password for ${target.email}`,
      ctx,
    });
    return { temporaryPassword };
  }

  async unlock(actor: PlatformAdminActor, id: string, ctx: RequestContext) {
    const target = await this.requireTarget(id);
    if (id !== actor.id && !canSecureTarget(actor.role, target.role)) {
      throw new ForbiddenException('Your role cannot act on this staff member.');
    }
    await this.prisma.platformAdmin.update({
      where: { id },
      data: { lockedUntil: null, failedLoginAttempts: 0 },
    });
    await this.audit.log({
      action: 'SECURITY_ACCOUNT_UNLOCKED',
      category: 'SECURITY',
      severity: 'WARN',
      actor,
      targetType: 'PlatformAdmin',
      targetId: id,
      summary: `${actor.email} unlocked ${target.email}`,
      ctx,
    });
    return { success: true };
  }

  async sessions(id: string) {
    await this.requireTarget(id);
    const rows = await this.prisma.platformAdminSession.findMany({
      where: { adminId: id, revokedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { lastUsedAt: 'desc' },
    });
    return {
      items: rows.map((s) => ({
        id: s.id,
        deviceLabel: s.deviceLabel,
        ipAddress: s.ipAddress,
        createdAt: s.createdAt,
        lastUsedAt: s.lastUsedAt,
      })),
    };
  }

  async revokeSessions(actor: PlatformAdminActor, id: string, ctx: RequestContext) {
    const target = await this.requireTarget(id);
    if (id !== actor.id && !canSecureTarget(actor.role, target.role)) {
      throw new ForbiddenException('Your role cannot act on this staff member.');
    }
    const result = await this.prisma.platformAdminSession.updateMany({
      where: {
        adminId: id,
        revokedAt: null,
        ...(id === actor.id ? { id: { not: actor.sessionId } } : {}),
      },
      data: { revokedAt: new Date(), revokedReason: 'SECURITY_REVOKE' },
    });
    await this.audit.log({
      action: 'SECURITY_STAFF_SESSIONS_REVOKED',
      category: 'SECURITY',
      severity: 'WARN',
      actor,
      targetType: 'PlatformAdmin',
      targetId: id,
      summary: `${actor.email} signed out ${result.count} session(s) for ${target.email}`,
      ctx,
    });
    return { success: true, revoked: result.count };
  }

  private async requireTarget(id: string) {
    const target = await this.prisma.platformAdmin.findUnique({ where: { id } });
    if (!target) throw new NotFoundException('Staff member not found');
    return target;
  }

  private async assertAnotherActiveOwner(excludeId: string) {
    const others = await this.prisma.platformAdmin.count({
      where: { role: 'OWNER', status: 'ACTIVE', id: { not: excludeId } },
    });
    if (others === 0) {
      throw new ConflictException('Counterbase must always keep at least one active owner.');
    }
  }
}

// Re-exported so controllers don't need to reach into rbac for the catalog.
export { permissionsForRole };
