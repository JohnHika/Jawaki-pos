import { Injectable } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

@Injectable()
export class PermissionsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Effective permissions = union of every assigned role's permissions,
   * plus personal grants, minus personal revokes. A revoke always wins
   * over a role grant for the same key, so it's applied last.
   */
  async getEffectivePermissions(userId: string): Promise<string[]> {
    const [userRoles, overrides] = await Promise.all([
      this.prisma.userRole.findMany({
        where: { userId },
        select: { role: { select: { permissions: { select: { permissionKey: true } } } } },
      }),
      this.prisma.userPermissionOverride.findMany({
        where: { userId },
        select: { permissionKey: true, grant: true },
      }),
    ]);

    const effective = new Set<string>();
    for (const userRole of userRoles) {
      for (const rp of userRole.role.permissions) {
        effective.add(rp.permissionKey);
      }
    }

    for (const override of overrides) {
      if (override.grant) {
        effective.add(override.permissionKey);
      } else {
        effective.delete(override.permissionKey);
      }
    }

    return Array.from(effective);
  }

  /** Full catalog grouped by feature, for UI rendering (role editor, override screen). */
  async getCatalog() {
    const permissions = await this.prisma.permission.findMany({
      orderBy: [{ feature: 'asc' }, { action: 'asc' }],
    });

    const grouped = new Map<string, typeof permissions>();
    for (const perm of permissions) {
      const list = grouped.get(perm.feature) ?? [];
      list.push(perm);
      grouped.set(perm.feature, list);
    }

    return Array.from(grouped.entries()).map(([feature, perms]) => ({
      feature,
      permissions: perms,
    }));
  }

  /** Breakdown of a user's permissions: what comes from roles vs personal overrides. */
  async getUserPermissionBreakdown(userId: string) {
    const [userRoles, overrides] = await Promise.all([
      this.prisma.userRole.findMany({
        where: { userId },
        select: {
          role: {
            select: {
              id: true,
              name: true,
              permissions: { select: { permissionKey: true } },
            },
          },
        },
      }),
      this.prisma.userPermissionOverride.findMany({
        where: { userId },
        select: { permissionKey: true, grant: true, reason: true },
      }),
    ]);

    const fromRoles = new Set<string>();
    for (const userRole of userRoles) {
      for (const rp of userRole.role.permissions) {
        fromRoles.add(rp.permissionKey);
      }
    }

    const granted = overrides.filter((o) => o.grant).map((o) => o.permissionKey);
    const revoked = overrides.filter((o) => !o.grant).map((o) => o.permissionKey);

    const effective = new Set(fromRoles);
    for (const key of granted) effective.add(key);
    for (const key of revoked) effective.delete(key);

    return {
      roles: userRoles.map((ur) => ({ id: ur.role.id, name: ur.role.name })),
      fromRoles: Array.from(fromRoles),
      granted,
      revoked,
      effective: Array.from(effective),
    };
  }
}
