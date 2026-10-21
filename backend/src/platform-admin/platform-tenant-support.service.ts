import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { PlatformAuditService, RequestContext } from './audit/platform-audit.service';
import { PlatformAdminActor } from './guards/platform-admin.guard';

/**
 * Support/security tools that reach into a client company: its staff
 * accounts, devices, internal notes and the emergency lock-out switch.
 * Every mutation is attributed to the acting platform staff member.
 */
@Injectable()
export class PlatformTenantSupportService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: PlatformAuditService,
  ) {}

  private async requireTenant(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true, name: true, isActive: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');
    return tenant;
  }

  async listUsers(tenantId: string) {
    await this.requireTenant(tenantId);
    const now = new Date();
    const users = await this.prisma.user.findMany({
      where: { tenantId },
      orderBy: [{ isActive: 'desc' }, { createdAt: 'asc' }],
      select: {
        id: true,
        email: true,
        phone: true,
        firstName: true,
        lastName: true,
        role: true,
        isActive: true,
        lastLoginAt: true,
        createdAt: true,
        _count: { select: { refreshTokens: { where: { expiresAt: { gt: now } } } } },
      },
    });
    return {
      items: users.map((u) => ({
        id: u.id,
        email: u.email,
        phone: u.phone,
        firstName: u.firstName,
        lastName: u.lastName,
        role: u.role,
        isActive: u.isActive,
        lastLoginAt: u.lastLoginAt,
        createdAt: u.createdAt,
        activeSessions: u._count.refreshTokens,
      })),
      total: users.length,
    };
  }

  async setUserActive(
    actor: PlatformAdminActor,
    tenantId: string,
    userId: string,
    active: boolean,
    ctx: RequestContext,
  ) {
    const tenant = await this.requireTenant(tenantId);
    const user = await this.prisma.user.findFirst({
      where: { id: userId, tenantId },
      select: { id: true, email: true, isActive: true },
    });
    if (!user) throw new NotFoundException('User not found in this company');

    await this.prisma.user.update({ where: { id: userId }, data: { isActive: active } });
    let sessionsEnded = 0;
    if (!active) {
      sessionsEnded = (await this.prisma.refreshToken.deleteMany({ where: { userId } })).count;
    }
    await this.audit.log({
      action: active ? 'TENANT_USER_ACTIVATED' : 'TENANT_USER_DEACTIVATED',
      category: 'SECURITY',
      severity: active ? 'INFO' : 'WARN',
      actor,
      targetType: 'User',
      targetId: userId,
      tenantId,
      summary: `${actor.email} ${active ? 'reactivated' : 'deactivated'} ${user.email} at ${tenant.name}`,
      metadata: { sessionsEnded },
      ctx,
    });
    return { success: true, isActive: active, sessionsEnded };
  }

  async revokeUserSessions(
    actor: PlatformAdminActor,
    tenantId: string,
    userId: string,
    ctx: RequestContext,
  ) {
    const tenant = await this.requireTenant(tenantId);
    const user = await this.prisma.user.findFirst({
      where: { id: userId, tenantId },
      select: { id: true, email: true },
    });
    if (!user) throw new NotFoundException('User not found in this company');
    const result = await this.prisma.refreshToken.deleteMany({ where: { userId } });
    await this.audit.log({
      action: 'TENANT_USER_SESSIONS_REVOKED',
      category: 'SECURITY',
      severity: 'WARN',
      actor,
      targetType: 'User',
      targetId: userId,
      tenantId,
      summary: `${actor.email} signed ${user.email} out of ${result.count} device(s) at ${tenant.name}`,
      ctx,
    });
    return { success: true, revoked: result.count };
  }

  async forceLogout(actor: PlatformAdminActor, tenantId: string, ctx: RequestContext) {
    const tenant = await this.requireTenant(tenantId);
    const result = await this.prisma.refreshToken.deleteMany({ where: { user: { tenantId } } });
    await this.audit.log({
      action: 'TENANT_FORCE_LOGOUT',
      category: 'SECURITY',
      severity: 'CRITICAL',
      actor,
      targetType: 'Tenant',
      targetId: tenantId,
      tenantId,
      summary: `${actor.email} forced every user at ${tenant.name} to sign in again (${result.count} session(s))`,
      ctx,
    });
    return { success: true, revoked: result.count };
  }

  /** Emergency kill switch: blocks sign-in for the whole company and ends its sessions. */
  async setLockout(
    actor: PlatformAdminActor,
    tenantId: string,
    locked: boolean,
    reason: string | undefined,
    ctx: RequestContext,
  ) {
    const tenant = await this.requireTenant(tenantId);
    await this.prisma.tenant.update({ where: { id: tenantId }, data: { isActive: !locked } });
    let revoked = 0;
    if (locked) {
      revoked = (await this.prisma.refreshToken.deleteMany({ where: { user: { tenantId } } })).count;
    }
    await this.audit.log({
      action: locked ? 'TENANT_LOCKED_OUT' : 'TENANT_LOCKOUT_LIFTED',
      category: 'SECURITY',
      severity: locked ? 'CRITICAL' : 'WARN',
      actor,
      targetType: 'Tenant',
      targetId: tenantId,
      tenantId,
      summary: `${actor.email} ${locked ? 'locked out' : 'restored access for'} ${tenant.name}${
        reason ? ` — ${reason}` : ''
      }`,
      metadata: { reason: reason ?? null, sessionsEnded: revoked },
      ctx,
    });
    return { success: true, isActive: !locked, sessionsEnded: revoked };
  }

  async listDevices(tenantId: string) {
    await this.requireTenant(tenantId);
    const devices = await this.prisma.device.findMany({
      where: { branch: { tenantId } },
      orderBy: { lastActiveAt: { sort: 'desc', nulls: 'last' } },
      select: {
        id: true,
        name: true,
        model: true,
        osVersion: true,
        appVersion: true,
        lastSyncAt: true,
        lastActiveAt: true,
        isActive: true,
        registeredAt: true,
        branch: { select: { id: true, name: true } },
      },
    });
    return {
      items: devices.map((d) => ({
        id: d.id,
        name: d.name,
        model: d.model,
        osVersion: d.osVersion,
        appVersion: d.appVersion,
        lastSyncAt: d.lastSyncAt,
        lastActiveAt: d.lastActiveAt,
        isActive: d.isActive,
        registeredAt: d.registeredAt,
        branchId: d.branch.id,
        branchName: d.branch.name,
      })),
      total: devices.length,
    };
  }

  async listNotes(tenantId: string) {
    await this.requireTenant(tenantId);
    const notes = await this.prisma.platformTenantNote.findMany({
      where: { tenantId },
      orderBy: [{ pinned: 'desc' }, { createdAt: 'desc' }],
      take: 100,
    });
    return { items: notes };
  }

  async addNote(
    actor: PlatformAdminActor,
    tenantId: string,
    body: string,
    pinned: boolean,
    ctx: RequestContext,
  ) {
    const tenant = await this.requireTenant(tenantId);
    const note = await this.prisma.platformTenantNote.create({
      data: { tenantId, authorId: actor.id, authorEmail: actor.email, body: body.trim(), pinned },
    });
    await this.audit.log({
      action: 'TENANT_NOTE_ADDED',
      category: 'TENANT',
      actor,
      targetType: 'PlatformTenantNote',
      targetId: note.id,
      tenantId,
      summary: `${actor.email} added a note on ${tenant.name}`,
      ctx,
    });
    return note;
  }

  async deleteNote(actor: PlatformAdminActor, tenantId: string, noteId: string, ctx: RequestContext) {
    const note = await this.prisma.platformTenantNote.findFirst({ where: { id: noteId, tenantId } });
    if (!note) throw new NotFoundException('Note not found');
    await this.prisma.platformTenantNote.delete({ where: { id: noteId } });
    await this.audit.log({
      action: 'TENANT_NOTE_DELETED',
      category: 'TENANT',
      actor,
      targetType: 'PlatformTenantNote',
      targetId: noteId,
      tenantId,
      summary: `${actor.email} deleted a note`,
      ctx,
    });
    return { success: true };
  }
}
