import { Injectable, NotFoundException, ConflictException, BadRequestException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CreateRoleDto, UpdateRoleDto } from './dto/role.dto';

@Injectable()
export class RolesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditService: AuditService,
  ) {}

  async findAll(tenantId: string) {
    const roles = await this.prisma.role.findMany({
      where: { tenantId },
      include: {
        permissions: { select: { permissionKey: true } },
        _count: { select: { userRoles: true } },
      },
      orderBy: { name: 'asc' },
    });

    return roles.map((role) => ({
      id: role.id,
      name: role.name,
      description: role.description,
      isSystem: role.isSystem,
      permissionKeys: role.permissions.map((p) => p.permissionKey),
      userCount: role._count.userRoles,
      createdAt: role.createdAt,
      updatedAt: role.updatedAt,
    }));
  }

  async findOne(tenantId: string, roleId: string) {
    const role = await this.prisma.role.findFirst({
      where: { id: roleId, tenantId },
      include: { permissions: { select: { permissionKey: true } } },
    });

    if (!role) {
      throw new NotFoundException('Role not found');
    }

    return {
      id: role.id,
      name: role.name,
      description: role.description,
      isSystem: role.isSystem,
      permissionKeys: role.permissions.map((p) => p.permissionKey),
      createdAt: role.createdAt,
      updatedAt: role.updatedAt,
    };
  }

  async create(tenantId: string, dto: CreateRoleDto, actorUserId: string) {
    await this.assertPermissionKeysExist(dto.permissionKeys ?? []);

    const existing = await this.prisma.role.findUnique({
      where: { tenantId_name: { tenantId, name: dto.name } },
    });
    if (existing) {
      throw new ConflictException('A role with this name already exists');
    }

    const role = await this.prisma.role.create({
      data: {
        tenantId,
        name: dto.name,
        description: dto.description,
        permissions: dto.permissionKeys?.length
          ? { create: dto.permissionKeys.map((permissionKey) => ({ permissionKey })) }
          : undefined,
      },
      include: { permissions: { select: { permissionKey: true } } },
    });

    await this.auditService.record({
      userId: actorUserId,
      action: 'ROLE_CREATED',
      entityType: 'Role',
      entityId: role.id,
      newValues: { name: role.name, permissionKeys: dto.permissionKeys ?? [] },
    });

    return {
      id: role.id,
      name: role.name,
      description: role.description,
      isSystem: role.isSystem,
      permissionKeys: role.permissions.map((p) => p.permissionKey),
    };
  }

  /** Replaces a role's full permission set in one call when permissionKeys is provided. */
  async update(tenantId: string, roleId: string, dto: UpdateRoleDto, actorUserId: string) {
    const role = await this.prisma.role.findFirst({
      where: { id: roleId, tenantId },
      include: { permissions: { select: { permissionKey: true } } },
    });
    if (!role) {
      throw new NotFoundException('Role not found');
    }

    if (dto.permissionKeys) {
      await this.assertPermissionKeysExist(dto.permissionKeys);
    }

    const oldPermissionKeys = role.permissions.map((p) => p.permissionKey);

    const updated = await this.prisma.$transaction(async (tx) => {
      if (dto.permissionKeys) {
        await tx.rolePermission.deleteMany({ where: { roleId } });
        if (dto.permissionKeys.length) {
          await tx.rolePermission.createMany({
            data: dto.permissionKeys.map((permissionKey) => ({ roleId, permissionKey })),
          });
        }
      }

      return tx.role.update({
        where: { id: roleId },
        data: {
          name: dto.name ?? undefined,
          description: dto.description ?? undefined,
        },
        include: { permissions: { select: { permissionKey: true } } },
      });
    });

    await this.auditService.record({
      userId: actorUserId,
      action: 'ROLE_UPDATED',
      entityType: 'Role',
      entityId: roleId,
      oldValues: { name: role.name, permissionKeys: oldPermissionKeys },
      newValues: {
        name: updated.name,
        permissionKeys: updated.permissions.map((p) => p.permissionKey),
      },
    });

    return {
      id: updated.id,
      name: updated.name,
      description: updated.description,
      isSystem: updated.isSystem,
      permissionKeys: updated.permissions.map((p) => p.permissionKey),
    };
  }

  async remove(tenantId: string, roleId: string, actorUserId: string) {
    const role = await this.prisma.role.findFirst({
      where: { id: roleId, tenantId },
      include: { _count: { select: { userRoles: true } } },
    });
    if (!role) {
      throw new NotFoundException('Role not found');
    }
    if (role.isSystem) {
      throw new BadRequestException('System-seeded default roles cannot be deleted');
    }
    if (role._count.userRoles > 0) {
      throw new BadRequestException(
        `Cannot delete role "${role.name}": ${role._count.userRoles} user(s) still assigned. Remove the assignment first.`,
      );
    }

    await this.prisma.role.delete({ where: { id: roleId } });

    await this.auditService.record({
      userId: actorUserId,
      action: 'ROLE_DELETED',
      entityType: 'Role',
      entityId: roleId,
      oldValues: { name: role.name },
    });

    return { success: true };
  }

  private async assertPermissionKeysExist(keys: string[]) {
    if (!keys.length) return;
    const found = await this.prisma.permission.findMany({
      where: { key: { in: keys } },
      select: { key: true },
    });
    const foundKeys = new Set(found.map((p) => p.key));
    const unknown = keys.filter((k) => !foundKeys.has(k));
    if (unknown.length) {
      throw new BadRequestException(`Unknown permission key(s): ${unknown.join(', ')}`);
    }
  }
}
