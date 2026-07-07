import {
  Injectable,
  NotFoundException,
  ConflictException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { AuditService } from '../audit/audit.service';
import {
  CreateTenantDto,
  UpdateTenantDto,
  CreateBranchDto,
  UpdateBranchDto,
  RegisterDeviceDto,
  UpdateDeviceDto,
} from './dto/branch.dto';

@Injectable()
export class BranchesService {
  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
    private auditService: AuditService,
  ) {}

  // ==================== TENANT OPERATIONS ====================

  async createTenant(dto: CreateTenantDto) {
    const existing = await this.prisma.tenant.findUnique({
      where: { slug: dto.slug },
    });

    if (existing) {
      throw new ConflictException('Tenant with this slug already exists');
    }

    const { taxRatePercent, showTaxOnReceipt, settings, ...rest } = dto;
    return this.prisma.tenant.create({
      data: {
        ...rest,
        settings: this.mergeTaxSettingsFields(settings, {
          taxRatePercent,
          showTaxOnReceipt,
        }),
      },
    });
  }

  async getTenant(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      include: {
        branches: {
          where: { isActive: true },
          select: {
            id: true,
            name: true,
            code: true,
          },
        },
        _count: {
          select: {
            branches: true,
            users: true,
            products: true,
          },
        },
      },
    });

    if (!tenant) {
      throw new NotFoundException('Tenant not found');
    }

    return tenant;
  }

  async updateTenant(tenantId: string, dto: UpdateTenantDto) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
    });

    if (!tenant) {
      throw new NotFoundException('Tenant not found');
    }

    const { taxRatePercent, showTaxOnReceipt, settings, ...rest } = dto;
    const hasSettingsUpdate =
      taxRatePercent !== undefined ||
      showTaxOnReceipt !== undefined ||
      settings !== undefined;

    return this.prisma.tenant.update({
      where: { id: tenantId },
      data: {
        ...rest,
        ...(hasSettingsUpdate
          ? {
              settings: this.mergeTaxSettingsFields(
                { ...(tenant.settings as Record<string, any>), ...settings },
                { taxRatePercent, showTaxOnReceipt },
              ),
            }
          : {}),
      },
    });
  }

  /** Merges tax-related fields into a settings JSON blob without
   * clobbering other keys already stored there. */
  private mergeTaxSettingsFields(
    settings: Record<string, any> | undefined,
    fields: { taxRatePercent?: number; showTaxOnReceipt?: boolean },
  ): Record<string, any> {
    const base = settings ?? {};
    return {
      ...base,
      ...(fields.taxRatePercent !== undefined
        ? { taxRatePercent: fields.taxRatePercent }
        : {}),
      ...(fields.showTaxOnReceipt !== undefined
        ? { showTaxOnReceipt: fields.showTaxOnReceipt }
        : {}),
    };
  }

  // ==================== BRANCH OPERATIONS ====================

  async createBranch(tenantId: string, dto: CreateBranchDto, userId?: string) {
    const existing = await this.prisma.branch.findFirst({
      where: { tenantId, code: dto.code },
    });

    if (existing) {
      throw new ConflictException('Branch with this code already exists');
    }

    const branch = await this.prisma.branch.create({
      data: {
        tenantId,
        ...dto,
      },
    });

    await this.redisService.del(`branches:${tenantId}`);
    await this.auditService.record({
      userId,
      action: 'CREATE',
      entityType: 'branch',
      entityId: branch.id,
      newValues: { name: branch.name, code: branch.code },
    });
    return branch;
  }

  async getBranches(tenantId: string) {
    const cacheKey = `branches:${tenantId}`;
    const cached = await this.redisService.getJson<any[]>(cacheKey);
    if (cached) return cached;

    const branches = await this.prisma.branch.findMany({
      where: { tenantId },
      include: {
        _count: {
          select: {
            devices: true,
            users: true,
          },
        },
      },
      orderBy: { name: 'asc' },
    });

    const result = branches.map((b) => ({
      ...b,
      deviceCount: b._count.devices,
      userCount: b._count.users,
      _count: undefined,
    }));

    await this.redisService.setJson(cacheKey, result, 300);
    return result;
  }

  async getBranch(branchId: string, tenantId: string) {
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
      include: {
        devices: {
          where: { isActive: true },
        },
        _count: {
          select: {
            users: true,
            sales: true,
            stock: true,
          },
        },
      },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    return {
      ...branch,
      userCount: branch._count.users,
      salesCount: branch._count.sales,
      productCount: branch._count.stock,
      _count: undefined,
    };
  }

  async updateBranch(
    branchId: string,
    tenantId: string,
    dto: UpdateBranchDto,
    userId?: string,
  ) {
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    const updated = await this.prisma.branch.update({
      where: { id: branchId },
      data: dto,
    });

    await this.redisService.del(`branches:${tenantId}`);
    await this.auditService.record({
      userId,
      action: 'UPDATE',
      entityType: 'branch',
      entityId: branchId,
      oldValues: { name: branch.name, code: branch.code, isActive: branch.isActive },
      newValues: dto as Record<string, unknown>,
    });
    return updated;
  }

  async deleteBranch(branchId: string, tenantId: string, userId?: string) {
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
      include: {
        _count: {
          select: { sales: true },
        },
      },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    if (branch._count.sales > 0) {
      throw new ForbiddenException(
        'Cannot delete branch with sales history. Deactivate instead.',
      );
    }

    await this.prisma.branch.delete({
      where: { id: branchId },
    });

    await this.redisService.del(`branches:${tenantId}`);
    await this.auditService.record({
      userId,
      action: 'DELETE',
      entityType: 'branch',
      entityId: branchId,
      oldValues: { name: branch.name, code: branch.code },
    });
  }

  // ==================== BULK BRANCH OPERATIONS ====================

  async bulkCreateBranches(tenantId: string, branches: any[]) {
    const results = await this.prisma.$transaction(
      branches.map((dto) =>
        this.prisma.branch.create({
          data: {
            tenantId,
            ...dto,
          },
        }),
      ),
    );

    await this.redisService.del(`branches:${tenantId}`);
    return results;
  }

  async bulkUpdateBranches(tenantId: string, branches: { id: string; [key: string]: any }[]) {
    const results = await this.prisma.$transaction(async (tx) => {
      const updated: any[] = [];
      for (const item of branches) {
        const { id, ...updateData } = item;

        const existing = await tx.branch.findFirst({
          where: { id, tenantId },
        });
        if (!existing) {
          throw new NotFoundException(`Branch ${id} not found`);
        }

        const result = await tx.branch.update({
          where: { id },
          data: updateData,
        });
        updated.push(result);
      }
      return updated;
    });

    await this.redisService.del(`branches:${tenantId}`);
    return results;
  }

  async bulkDeleteBranches(tenantId: string, ids: string[]) {
    const branches = await this.prisma.branch.findMany({
      where: { id: { in: ids }, tenantId },
      include: { _count: { select: { sales: true } } },
    });

    if (branches.length !== ids.length) {
      const foundIds = branches.map((b) => b.id);
      const missing = ids.filter((id) => !foundIds.includes(id));
      throw new NotFoundException(`Branches not found: ${missing.join(', ')}`);
    }

    const withSales = branches.filter((b) => b._count.sales > 0);
    if (withSales.length > 0) {
      throw new ForbiddenException(
        `Cannot delete branches with sales history: ${withSales.map((b) => b.code).join(', ')}. Deactivate instead.`,
      );
    }

    await this.prisma.$transaction([
      this.prisma.device.deleteMany({ where: { branchId: { in: ids } } }),
      this.prisma.branch.deleteMany({ where: { id: { in: ids } } }),
    ]);

    await this.redisService.del(`branches:${tenantId}`);
  }

  // ==================== DEVICE OPERATIONS ====================

  async registerDevice(tenantId: string, dto: RegisterDeviceDto) {
    // Verify branch belongs to tenant
    const branch = await this.prisma.branch.findFirst({
      where: { id: dto.branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    // Check if device already registered
    const existing = await this.prisma.device.findUnique({
      where: { deviceUuid: dto.deviceUuid },
    });

    if (existing) {
      // Update existing device
      return this.prisma.device.update({
        where: { id: existing.id },
        data: {
          branchId: dto.branchId,
          name: dto.name,
          model: dto.model,
          osVersion: dto.osVersion,
          appVersion: dto.appVersion,
          isActive: true,
        },
      });
    }

    return this.prisma.device.create({
      data: {
        branchId: dto.branchId,
        deviceUuid: dto.deviceUuid,
        name: dto.name,
        model: dto.model,
        osVersion: dto.osVersion,
        appVersion: dto.appVersion,
      },
    });
  }

  async getDevices(branchId: string, tenantId: string) {
    // Verify branch belongs to tenant
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    return this.prisma.device.findMany({
      where: { branchId },
      orderBy: { name: 'asc' },
    });
  }

  async getDevice(deviceId: string) {
    const device = await this.prisma.device.findUnique({
      where: { id: deviceId },
      include: {
        branch: {
          select: {
            id: true,
            name: true,
            code: true,
            tenantId: true,
          },
        },
      },
    });

    if (!device) {
      throw new NotFoundException('Device not found');
    }

    return {
      ...device,
      branchName: device.branch.name,
    };
  }

  async updateDevice(deviceId: string, tenantId: string, dto: UpdateDeviceDto) {
    const device = await this.prisma.device.findUnique({
      where: { id: deviceId },
      include: { branch: true },
    });

    if (!device || device.branch.tenantId !== tenantId) {
      throw new NotFoundException('Device not found');
    }

    return this.prisma.device.update({
      where: { id: deviceId },
      data: dto,
    });
  }

  async updateDeviceLastSync(deviceId: string) {
    return this.prisma.device.update({
      where: { id: deviceId },
      data: { lastSyncAt: new Date() },
    });
  }

  async deactivateDevice(deviceId: string, tenantId: string) {
    const device = await this.prisma.device.findUnique({
      where: { id: deviceId },
      include: { branch: true },
    });

    if (!device || device.branch.tenantId !== tenantId) {
      throw new NotFoundException('Device not found');
    }

    return this.prisma.device.update({
      where: { id: deviceId },
      data: { isActive: false },
    });
  }

  async getOutdatedDevices(
    branchId: string,
    tenantId: string,
    minVersion: string,
  ) {
    // Verify branch belongs to tenant
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    return this.prisma.device.findMany({
      where: {
        branchId,
        appVersion: {
          not: minVersion,
        },
      },
      orderBy: { lastActiveAt: 'desc' },
      select: {
        id: true,
        deviceUuid: true,
        name: true,
        model: true,
        osVersion: true,
        appVersion: true,
        lastActiveAt: true,
        lastSyncAt: true,
        isActive: true,
      },
    });
  }

}
