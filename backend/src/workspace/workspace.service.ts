import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
import { LegacyUserRole } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';

export interface VerifiedWorkspaceInput {
  email: string;
  provider: 'GOOGLE' | 'EMAIL_OTP';
  firstName: string;
  lastName: string;
  companyName: string;
  companySlug?: string;
  logo?: string;
  logoPublicId?: string;
  settings?: Record<string, unknown>;
  branch: { name: string; code?: string; address?: string; phone?: string; email?: string };
}

const ONBOARDING_STEPS = [
  'confirm_business', 'configure_branch', 'invite_staff', 'add_catalog', 'activate_payment',
] as const;

@Injectable()
export class WorkspaceService {
  constructor(private readonly prisma: PrismaService) {}

  async createFromVerifiedIdentity(input: VerifiedWorkspaceInput) {
    const slug = input.companySlug || this.slugify(input.companyName);
    const existing = await this.prisma.tenant.findUnique({ where: { slug } });
    if (existing) throw new ConflictException('Company with this slug already exists');
    const sameName = await this.prisma.tenant.findFirst({
      where: { name: { equals: input.companyName.trim(), mode: 'insensitive' } }, select: { id: true },
    });
    if (sameName) throw new ConflictException('Company name already exists');

    return this.prisma.$transaction(async (tx) => {
      const tenant = await tx.tenant.create({
        data: {
          name: input.companyName.trim(), slug, logo: input.logo, logoPublicId: input.logoPublicId,
          settings: (input.settings ?? {}) as any, activationStatus: 'PENDING', isActive: true,
        },
      });
      const branch = await tx.branch.create({
        data: {
          tenantId: tenant.id, name: input.branch.name.trim(), code: input.branch.code?.trim() || 'MAIN',
          address: input.branch.address?.trim() || null, phone: input.branch.phone?.trim() || null,
          email: input.branch.email?.trim().toLowerCase() || null,
        },
      });
      const permissions = await tx.permission.findMany({ select: { key: true } });
      if (!permissions.length) throw new BadRequestException('Permission catalog is not initialized; company setup cannot continue safely');

      const user = await tx.user.create({
        data: {
          tenantId: tenant.id, email: input.email.trim().toLowerCase(), passwordHash: null,
          firstName: input.firstName.trim(), lastName: input.lastName.trim(), role: LegacyUserRole.ADMIN,
          identityProvider: input.provider, identityVerifiedAt: new Date(),
          branches: { create: { branchId: branch.id, isPrimary: true } },
        },
        include: { tenant: true, branches: { include: { branch: true } } },
      });

      const rolePermissions = new Map<string, string[]>([
        ['Cashier', permissions.map((p) => p.key).filter((key) => /^(sales|products|customers)\./.test(key))],
        ['Supervisor', permissions.map((p) => p.key).filter((key) => /^(sales|products|customers|inventory)\./.test(key))],
        ['Manager', permissions.map((p) => p.key).filter((key) => !/^(permissions|roles)\./.test(key))],
        ['Admin', permissions.map((p) => p.key)],
      ]);
      let adminRoleId = '';
      for (const [name, keys] of rolePermissions) {
        const role = await tx.role.create({
          data: {
            tenantId: tenant.id, name, isSystem: true,
            description: `${name} default role for this workspace`,
            permissions: { create: keys.map((permissionKey) => ({ permissionKey })) },
          },
        });
        if (name === 'Admin') adminRoleId = role.id;
      }
      await tx.userRole.create({ data: { userId: user.id, roleId: adminRoleId } });
      await tx.tenantOnboarding.create({
        data: {
          tenantId: tenant.id, ownerUserId: user.id,
          steps: { create: ONBOARDING_STEPS.map((key, position) => ({ key, position: position + 1 })) },
        },
      });
      return user;
    });
  }

  private slugify(value: string) {
    const slug = value.toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
    if (slug.length < 2) throw new BadRequestException('Company name cannot be converted to a valid slug');
    return slug.slice(0, 50).replace(/-+$/g, '');
  }
}
