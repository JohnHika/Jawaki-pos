import {
  PLAN_PRICING,
  UNLIMITED_PLAN_LIMIT,
} from '../subscription/subscription.service';

/**
 * Licensable modules. Each key is a boolean flag on a plan in PLAN_PRICING
 * (subscription.service.ts), so the price list and the gate can never drift
 * apart: adding a flag there and listing it here is all it takes.
 */
export const LICENSE_FEATURES = [
  'analytics',
  'customReports',
  'aiAssistant',
  'multiCurrency',
  'prioritySupport',
] as const;

export type LicenseFeature = (typeof LICENSE_FEATURES)[number];

/** Human wording for the "not included in your plan" message. */
export const FEATURE_LABELS: Record<LicenseFeature, string> = {
  analytics: 'Sales analytics',
  customReports: 'Custom reports and exports',
  aiAssistant: 'Axon AI assistant',
  multiCurrency: 'Multi-currency',
  prioritySupport: 'Priority support',
};

/**
 * off      — nothing is gated; the licence is only reported (the default, so a
 *            deploy never changes what an existing client can do).
 * warn     — nothing is gated, but a would-be block is logged for the operator.
 * enforce  — unlicensed modules, limits and expired licences are refused (402).
 */
export type EnforcementMode = 'off' | 'warn' | 'enforce';
export const ENFORCEMENT_MODES: EnforcementMode[] = ['off', 'warn', 'enforce'];

/** Stored under `tenant.settings.license` (no schema migration needed). */
export interface TenantLicenseSettings {
  enforcement?: EnforcementMode;
  /** Operator grants (true) or revokes (false) a module regardless of plan. */
  overrides?: Partial<Record<LicenseFeature, boolean>>;
  /** Hard stop for a licence that is not tied to a subscription period. */
  validUntil?: string | null;
  /** Explicit seat limits that beat both the plan and the tenant columns. */
  maxBranches?: number | null;
  maxUsers?: number | null;
  licenseKey?: string;
  note?: string;
  updatedAt?: string;
}

export interface TenantForLicense {
  plan: string | null;
  subscriptionStatus?: string | null;
  maxBranches: number | null;
  maxUsers: number | null;
  settings: unknown;
}

export interface ResolvedFeature {
  allowed: boolean;
  source: 'plan' | 'override';
}

export interface ResolvedLicense {
  plan: string;
  enforcement: EnforcementMode;
  /** True only in `enforce` mode: the gate actually refuses requests. */
  enforced: boolean;
  features: Record<LicenseFeature, ResolvedFeature>;
  limits: { maxBranches: number; maxUsers: number };
  validUntil: string | null;
  expired: boolean;
  licenseKey: string | null;
  note: string | null;
  /**
   * The plan name is not in the price list (a legacy or hand-edited row).
   * Such a company is never locked out by a guess: every module stays open
   * and its seat limits come from its own columns, until the operator moves
   * it onto a real plan or sets explicit overrides.
   */
  unknownPlan: boolean;
}

export function readLicenseSettings(settings: unknown): TenantLicenseSettings {
  if (!settings || typeof settings !== 'object') return {};
  const raw = (settings as Record<string, unknown>).license;
  if (!raw || typeof raw !== 'object') return {};
  return raw as TenantLicenseSettings;
}

function parseMode(value: unknown): EnforcementMode | null {
  return typeof value === 'string' &&
    (ENFORCEMENT_MODES as string[]).includes(value)
    ? (value as EnforcementMode)
    : null;
}

/**
 * Pure and deterministic, so the same inputs always give the same verdict on
 * the server, in the signed offline token and in tests.
 *
 * Limits take the LARGEST of the tenant column and the plan's allowance: the
 * schema defaults every tenant to 1 branch / 3 users, so trusting the column
 * alone would lock a paying Business client to a Trial's allowance.
 */
export function resolveLicense(
  tenant: TenantForLicense,
  opts: { now?: Date; defaultMode?: EnforcementMode } = {},
): ResolvedLicense {
  const now = opts.now ?? new Date();
  const stored = readLicenseSettings(tenant.settings);
  // A selected paid plan is not a paid entitlement while the tenant is still
  // in the free trial (including rows created by older plan-selection code).
  const isTrial = tenant.subscriptionStatus === 'TRIAL';
  const planId = isTrial ? 'TRIAL' : tenant.plan ?? 'TRIAL';
  const knownPlan = PLAN_PRICING[planId];
  const unknownPlan = !knownPlan;
  const planMeta = knownPlan ?? PLAN_PRICING.TRIAL;
  const enforcement = parseMode(stored.enforcement) ?? opts.defaultMode ?? 'off';

  const features = {} as Record<LicenseFeature, ResolvedFeature>;
  for (const key of LICENSE_FEATURES) {
    const override = stored.overrides?.[key];
    features[key] =
      typeof override === 'boolean'
        ? { allowed: override, source: 'override' }
        : { allowed: unknownPlan || planMeta.features[key] === true, source: 'plan' };
  }

  const positive = (n: unknown): n is number =>
    typeof n === 'number' && Number.isFinite(n) && n > 0;
  // A plan that is not in the price list keeps whatever its own columns say,
  // or is unlimited when they are empty, rather than being read as a trial.
  const seats = (explicit: unknown, column: number | null, planMax: number) => {
    if (positive(explicit)) return explicit;
    if (unknownPlan) return column && column > 0 ? column : UNLIMITED_PLAN_LIMIT;
    return isTrial ? planMax : Math.max(column ?? 0, planMax);
  };
  const limits = {
    maxBranches: seats(stored.maxBranches, tenant.maxBranches, planMeta.features.maxBranches),
    maxUsers: seats(stored.maxUsers, tenant.maxUsers, planMeta.features.maxUsers),
  };

  const validUntil = stored.validUntil ?? null;
  const expired =
    validUntil !== null && new Date(validUntil).getTime() <= now.getTime();

  return {
    plan: planId,
    enforcement,
    enforced: enforcement === 'enforce',
    features,
    limits,
    validUntil,
    expired,
    licenseKey: stored.licenseKey ?? null,
    note: stored.note ?? null,
    unknownPlan,
  };
}

/** Whether `feature` may be used right now. Always true unless enforced. */
export function isFeatureAllowed(
  license: ResolvedLicense,
  feature: LicenseFeature,
): boolean {
  if (!license.enforced) return true;
  if (license.expired) return false;
  return license.features[feature].allowed;
}

/** Whether the tenant may add one more of `kind` given the current count. */
export function isWithinLimit(
  license: ResolvedLicense,
  kind: 'branches' | 'users',
  currentCount: number,
): boolean {
  if (!license.enforced) return true;
  const max =
    kind === 'branches' ? license.limits.maxBranches : license.limits.maxUsers;
  return currentCount < max;
}

/** `AXON-XXXX-XXXX-XXXX` without look-alike characters (0/O, 1/I). */
export function generateLicenseKey(randomBytes: (n: number) => Uint8Array): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = randomBytes(12);
  const groups: string[] = [];
  for (let g = 0; g < 3; g++) {
    let part = '';
    for (let i = 0; i < 4; i++) {
      part += alphabet[bytes[g * 4 + i] % alphabet.length];
    }
    groups.push(part);
  }
  return `AXON-${groups.join('-')}`;
}

export interface ClientLicenseView {
  plan: string;
  enforced: boolean;
  expired: boolean;
  validUntil: string | null;
  licenseKey: string | null;
  limits: { maxBranches: number; maxUsers: number };
  /** What this company may use right now (everything, while not enforced). */
  features: Record<LicenseFeature, boolean>;
  /** What the plan itself includes, so the UI can show what an upgrade adds. */
  planFeatures: Record<LicenseFeature, boolean>;
}

/** The licence as the app sees it; shared by /license and /billing/entitlement. */
export function describeLicense(license: ResolvedLicense): ClientLicenseView {
  const features = {} as Record<LicenseFeature, boolean>;
  const planFeatures = {} as Record<LicenseFeature, boolean>;
  for (const key of LICENSE_FEATURES) {
    features[key] = isFeatureAllowed(license, key);
    planFeatures[key] = license.features[key].allowed;
  }
  return {
    plan: license.plan,
    enforced: license.enforced,
    expired: license.expired,
    validUntil: license.validUntil,
    licenseKey: license.licenseKey,
    limits: license.limits,
    features,
    planFeatures,
  };
}
