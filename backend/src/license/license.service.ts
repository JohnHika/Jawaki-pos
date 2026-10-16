import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomBytes } from 'crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  ENFORCEMENT_MODES,
  EnforcementMode,
  FEATURE_LABELS,
  LICENSE_FEATURES,
  LicenseFeature,
  ResolvedLicense,
  TenantLicenseSettings,
  describeLicense,
  generateLicenseKey,
  isFeatureAllowed,
  isWithinLimit,
  readLicenseSettings,
  resolveLicense,
} from './license.catalog';

export interface LicensePatch {
  enforcement?: EnforcementMode;
  overrides?: Partial<Record<LicenseFeature, boolean | null>>;
  validUntil?: string | null;
  maxBranches?: number | null;
  maxUsers?: number | null;
  note?: string | null;
  /** Issue a fresh licence key (also done automatically on first save). */
  reissueKey?: boolean;
}

export interface LicensePreviewRow {
  tenantId: string;
  name: string;
  slug: string;
  plan: string;
  enforcement: EnforcementMode;
  lockedFeatures: LicenseFeature[];
  overLimit: { branches?: number; users?: number };
  expired: boolean;
  /** The plan name is not in the price list: never locked by guesswork. */
  unknownPlan: boolean;
  /** What switching this client to `enforce` would change for them today. */
  wouldBeAffected: boolean;
}

@Injectable()
export class LicenseService {
  private readonly logger = new Logger(LicenseService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  /** Platform-wide default; a tenant's own setting beats it. Defaults to off. */
  defaultMode(): EnforcementMode {
    const raw = this.config.get<string>('LICENSE_ENFORCEMENT');
    return (ENFORCEMENT_MODES as string[]).includes(raw ?? '')
      ? (raw as EnforcementMode)
      : 'off';
  }

  async getForTenant(tenantId: string): Promise<ResolvedLicense> {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { plan: true, maxBranches: true, maxUsers: true, settings: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');
    return resolveLicense(tenant, { defaultMode: this.defaultMode() });
  }

  /** Throws 402 FEATURE_NOT_LICENSED when the module is not paid for. */
  async assertFeature(tenantId: string, feature: LicenseFeature): Promise<void> {
    const license = await this.getForTenant(tenantId);
    if (isFeatureAllowed(license, feature)) {
      if (license.enforcement === 'warn' && !license.features[feature].allowed) {
        this.logger.warn(
          `[licence/warn] tenant ${tenantId} used "${feature}" which its ${license.plan} plan does not include`,
        );
      }
      return;
    }
    throw new HttpException(
      {
        message: license.expired
          ? 'Your licence has expired. Contact support to renew it.'
          : `${FEATURE_LABELS[feature]} is not included in your plan. Upgrade to unlock it.`,
        code: license.expired ? 'LICENSE_EXPIRED' : 'FEATURE_NOT_LICENSED',
        feature,
        plan: license.plan,
      },
      HttpStatus.PAYMENT_REQUIRED,
    );
  }

  /** Throws 402 LICENSE_LIMIT_REACHED when adding one more would exceed the plan. */
  async assertWithinLimit(
    tenantId: string,
    kind: 'branches' | 'users',
  ): Promise<void> {
    const license = await this.getForTenant(tenantId);
    if (!license.enforced) return;
    const current =
      kind === 'branches'
        ? await this.prisma.branch.count({ where: { tenantId } })
        : await this.prisma.user.count({ where: { tenantId } });
    if (isWithinLimit(license, kind, current)) return;
    const max =
      kind === 'branches' ? license.limits.maxBranches : license.limits.maxUsers;
    throw new HttpException(
      {
        message: `Your ${license.plan} plan allows ${max} ${kind === 'branches' ? 'branch(es)' : 'user(s)'}. Upgrade to add more.`,
        code: 'LICENSE_LIMIT_REACHED',
        limit: kind,
        max,
        plan: license.plan,
      },
      HttpStatus.PAYMENT_REQUIRED,
    );
  }

  /** The client-facing licence: what to show and what to lock. */
  async describeForClient(tenantId: string) {
    return describeLicense(await this.getForTenant(tenantId));
  }

  /**
   * Dry run for the operator: for every client, what turning on `enforce`
   * would lock today. Read-only.
   */
  async preview(): Promise<LicensePreviewRow[]> {
    const tenants = await this.prisma.tenant.findMany({
      select: {
        id: true,
        name: true,
        slug: true,
        plan: true,
        maxBranches: true,
        maxUsers: true,
        settings: true,
        _count: { select: { branches: true, users: true } },
      },
      orderBy: { createdAt: 'asc' },
    });
    return tenants.map((t) => {
      const asEnforced = resolveLicense(t, { defaultMode: 'enforce' });
      const current = resolveLicense(t, { defaultMode: this.defaultMode() });
      const lockedFeatures = LICENSE_FEATURES.filter(
        (k) => !asEnforced.features[k].allowed,
      );
      const overLimit: { branches?: number; users?: number } = {};
      if (t._count.branches > asEnforced.limits.maxBranches) {
        overLimit.branches = t._count.branches - asEnforced.limits.maxBranches;
      }
      if (t._count.users > asEnforced.limits.maxUsers) {
        overLimit.users = t._count.users - asEnforced.limits.maxUsers;
      }
      return {
        tenantId: t.id,
        name: t.name,
        slug: t.slug,
        plan: asEnforced.plan,
        enforcement: current.enforcement,
        lockedFeatures,
        overLimit,
        expired: asEnforced.expired,
        unknownPlan: asEnforced.unknownPlan,
        wouldBeAffected:
          lockedFeatures.length > 0 ||
          asEnforced.expired ||
          Object.keys(overLimit).length > 0,
      };
    });
  }

  /** Validates and merges an operator change; returns old and new settings. */
  async update(
    tenantId: string,
    patch: LicensePatch,
  ): Promise<{ before: TenantLicenseSettings; after: TenantLicenseSettings }> {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true, settings: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    const before = readLicenseSettings(tenant.settings);
    const after: TenantLicenseSettings = {
      ...before,
      overrides: { ...(before.overrides ?? {}) },
    };

    if (patch.enforcement !== undefined) {
      if (!ENFORCEMENT_MODES.includes(patch.enforcement)) {
        throw new BadRequestException(
          `enforcement must be one of ${ENFORCEMENT_MODES.join(', ')}`,
        );
      }
      after.enforcement = patch.enforcement;
    }
    if (patch.overrides) {
      for (const [key, value] of Object.entries(patch.overrides)) {
        if (!(LICENSE_FEATURES as readonly string[]).includes(key)) {
          throw new BadRequestException(`Unknown feature "${key}"`);
        }
        if (value === null) delete after.overrides![key as LicenseFeature];
        else if (typeof value === 'boolean') {
          after.overrides![key as LicenseFeature] = value;
        } else {
          throw new BadRequestException(`Override "${key}" must be true, false or null`);
        }
      }
    }
    if (patch.validUntil !== undefined) {
      if (patch.validUntil !== null && Number.isNaN(Date.parse(patch.validUntil))) {
        throw new BadRequestException('validUntil must be an ISO date or null');
      }
      after.validUntil = patch.validUntil
        ? new Date(patch.validUntil).toISOString()
        : null;
    }
    for (const field of ['maxBranches', 'maxUsers'] as const) {
      const value = patch[field];
      if (value === undefined) continue;
      if (value !== null && (!Number.isInteger(value) || value < 1)) {
        throw new BadRequestException(`${field} must be a whole number of at least 1`);
      }
      after[field] = value;
    }
    if (patch.note !== undefined) after.note = patch.note ?? undefined;
    if (patch.reissueKey || !after.licenseKey) {
      after.licenseKey = generateLicenseKey((n) => randomBytes(n));
    }
    after.updatedAt = new Date().toISOString();

    const settings = {
      ...((tenant.settings as Record<string, unknown>) ?? {}),
      license: after,
    };
    await this.prisma.tenant.update({
      where: { id: tenantId },
      data: { settings: settings as any },
    });
    return { before, after };
  }
}
