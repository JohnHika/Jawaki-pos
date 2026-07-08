import { Injectable, NotFoundException, ConflictException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { PermissionsService } from '../permissions/permissions.service';
import { AssignRoleDto, CreatePermissionOverrideDto } from './dto/user-management.dto';

@Injectable()
export class UsersManagementService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditService: AuditService,
    private readonly permissionsService: PermissionsService,
  ) {}

  async findAll(tenantId: string) {
    const users = await this.prisma.user.findMany({
      where: { tenantId },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        phone: true,
        role: true,
        isActive: true,
        lastLoginAt: true,
        roles: { select: { role: { select: { id: true, name: true } } } },
        branches: {
          select: { isPrimary: true, branch: { select: { id: true, name: true, code: true } } },
        },
      },
      orderBy: [{ firstName: 'asc' }, { lastName: 'asc' }],
    });

    return users.map((user) => ({
      id: user.id,
      email: user.email,
      firstName: user.firstName,
      lastName: user.lastName,
      phone: user.phone,
      legacyRole: user.role,
      isActive: user.isActive,
      lastLoginAt: user.lastLoginAt,
      roles: user.roles.map((ur) => ur.role),
      branches: user.branches.map((ub) => ({ ...ub.branch, isPrimary: ub.isPrimary })),
    }));
  }

  // Directory a phone-server pulls once (while online) to authorize local
  // logins entirely offline afterward. Never includes `pin`/`passwordHash`
  // — only `offlineAccessPinHash`, a credential distinct from the online
  // login PIN that a user must have explicitly set for this to work.
  async getOfflineDirectory(tenantId: string) {
    const users = await this.prisma.user.findMany({
      where: { tenantId, isActive: true, offlineAccessPinHash: { not: null } },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        role: true,
        isActive: true,
        offlineAccessPinHash: true,
        branches: { where: { isPrimary: true }, select: { branchId: true } },
      },
    });

    return Promise.all(
      users.map(async (user) => ({
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: user.role,
        tenantId,
        branchId: user.branches[0]?.branchId ?? null,
        isActive: user.isActive,
        offlineAccessPinHash: user.offlineAccessPinHash,
        permissions: await this.permissionsService.getEffectivePermissions(user.id),
      })),
    );
  }

  private async assertUserInTenant(tenantId: string, userId: string) {
    const user = await this.prisma.user.findFirst({ where: { id: userId, tenantId } });
    if (!user) {
      throw new NotFoundException('User not found');
    }
    return user;
  }

  async getPermissionBreakdown(tenantId: string, userId: string) {
    await this.assertUserInTenant(tenantId, userId);
    return this.permissionsService.getUserPermissionBreakdown(userId);
  }

  async assignRole(tenantId: string, userId: string, dto: AssignRoleDto, actorUserId: string) {
    await this.assertUserInTenant(tenantId, userId);

    const role = await this.prisma.role.findFirst({ where: { id: dto.roleId, tenantId } });
    if (!role) {
      throw new NotFoundException('Role not found');
    }

    const existing = await this.prisma.userRole.findUnique({
      where: { userId_roleId: { userId, roleId: dto.roleId } },
    });
    if (existing) {
      throw new ConflictException('User already has this role');
    }

    await this.prisma.userRole.create({ data: { userId, roleId: dto.roleId } });

    await this.auditService.record({
      userId: actorUserId,
      action: 'USER_ROLE_ASSIGNED',
      entityType: 'User',
      entityId: userId,
      newValues: { roleId: dto.roleId, roleName: role.name },
    });

    return this.permissionsService.getUserPermissionBreakdown(userId);
  }

  async removeRole(tenantId: string, userId: string, roleId: string, actorUserId: string) {
    await this.assertUserInTenant(tenantId, userId);

    const userRole = await this.prisma.userRole.findUnique({
      where: { userId_roleId: { userId, roleId } },
      include: { role: true },
    });
    if (!userRole) {
      throw new NotFoundException('User does not have this role');
    }

    await this.prisma.userRole.delete({ where: { userId_roleId: { userId, roleId } } });

    await this.auditService.record({
      userId: actorUserId,
      action: 'USER_ROLE_REMOVED',
      entityType: 'User',
      entityId: userId,
      oldValues: { roleId, roleName: userRole.role.name },
    });

    return this.permissionsService.getUserPermissionBreakdown(userId);
  }

  async setPermissionOverride(
    tenantId: string,
    userId: string,
    dto: CreatePermissionOverrideDto,
    actorUserId: string,
  ) {
    await this.assertUserInTenant(tenantId, userId);

    const permission = await this.prisma.permission.findUnique({ where: { key: dto.permissionKey } });
    if (!permission) {
      throw new NotFoundException(`Unknown permission key: ${dto.permissionKey}`);
    }

    const override = await this.prisma.userPermissionOverride.upsert({
      where: { userId_permissionKey: { userId, permissionKey: dto.permissionKey } },
      update: { grant: dto.grant, reason: dto.reason, createdById: actorUserId },
      create: {
        userId,
        permissionKey: dto.permissionKey,
        grant: dto.grant,
        reason: dto.reason,
        createdById: actorUserId,
      },
    });

    await this.auditService.record({
      userId: actorUserId,
      action: dto.grant ? 'USER_PERMISSION_GRANTED' : 'USER_PERMISSION_REVOKED',
      entityType: 'User',
      entityId: userId,
      newValues: { permissionKey: dto.permissionKey, grant: dto.grant, reason: dto.reason },
    });

    return { override, breakdown: await this.permissionsService.getUserPermissionBreakdown(userId) };
  }

  async clearPermissionOverride(
    tenantId: string,
    userId: string,
    permissionKey: string,
    actorUserId: string,
  ) {
    await this.assertUserInTenant(tenantId, userId);

    const existing = await this.prisma.userPermissionOverride.findUnique({
      where: { userId_permissionKey: { userId, permissionKey } },
    });
    if (!existing) {
      throw new NotFoundException('No override exists for this permission key');
    }

    await this.prisma.userPermissionOverride.delete({
      where: { userId_permissionKey: { userId, permissionKey } },
    });

    await this.auditService.record({
      userId: actorUserId,
      action: 'USER_PERMISSION_OVERRIDE_CLEARED',
      entityType: 'User',
      entityId: userId,
      oldValues: { permissionKey, grant: existing.grant },
    });

    return this.permissionsService.getUserPermissionBreakdown(userId);
  }
}
