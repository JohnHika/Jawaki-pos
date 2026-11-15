import { ConflictException, Injectable, NotFoundException, Optional } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { LegalPolicyService } from '../legal/legal-policy.service';

export interface PlanPricing {
  planId: string;
  name: string;
  monthlyAmountKes: number;
  trialDays: number;
  features: {
    maxBranches: number;
    maxUsers: number;
    analytics: boolean;
    prioritySupport: boolean;
    aiAssistant: boolean;
    customReports: boolean;
    multiCurrency: boolean;
  };
}

/**
 * Sentinel for "unlimited" on numeric plan limits. Consumers do arithmetic
 * and comparisons on these values (e.g. a mobile formatter renders >= 1000
 * as 'Unlimited'), so unlimited is a large finite number, never 0 or -1.
 */
export const UNLIMITED_PLAN_LIMIT = 999999;

export const PLAN_PRICING: Record<string, PlanPricing> = {
  TRIAL: {
    planId: 'TRIAL',
    name: 'Trial',
    monthlyAmountKes: 0,
    trialDays: 7,
    features: {
      maxBranches: 1,
      maxUsers: 3,
      analytics: false,
      prioritySupport: false,
      aiAssistant: false,
      customReports: false,
      multiCurrency: false,
    },
  },
  CORE: {
    planId: 'CORE',
    name: 'Core',
    monthlyAmountKes: 3000,
    trialDays: 7,
    features: {
      maxBranches: 3,
      maxUsers: 10,
      analytics: true,
      prioritySupport: false,
      aiAssistant: false,
      customReports: false,
      multiCurrency: false,
    },
  },
  BUSINESS: {
    planId: 'BUSINESS',
    name: 'Business',
    monthlyAmountKes: 5000,
    trialDays: 7,
    features: {
      maxBranches: 10,
      maxUsers: 50,
      analytics: true,
      prioritySupport: false,
      aiAssistant: true,
      customReports: true,
      multiCurrency: false,
    },
  },
  ENTERPRISE: {
    planId: 'ENTERPRISE',
    name: 'Enterprise',
    monthlyAmountKes: 9999,
    trialDays: 7,
    features: {
      maxBranches: UNLIMITED_PLAN_LIMIT,
      maxUsers: UNLIMITED_PLAN_LIMIT,
      analytics: true,
      prioritySupport: true,
      aiAssistant: true,
      customReports: true,
      multiCurrency: true,
    },
  },
};

export const VALID_PLANS = Object.keys(PLAN_PRICING);

@Injectable()
export class SubscriptionService {
  constructor(
    private readonly prisma: PrismaService,
    @Optional() private readonly legalPolicies?: LegalPolicyService,
  ) {}

  async getCurrentPlan(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: {
        plan: true,
        subscriptionStatus: true,
        subscriptionProvider: true,
        subscriptionReference: true,
        currentPeriodStart: true,
        currentPeriodEnd: true,
        setupFeePaidAt: true,
        maxBranches: true,
        maxUsers: true,
        activationStatus: true,
        activationPaidAt: true,
        settings: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');
    const isTrial = tenant.subscriptionStatus === 'TRIAL';
    const planMeta = PLAN_PRICING[isTrial ? 'TRIAL' : tenant.plan ?? 'TRIAL'] ?? PLAN_PRICING.TRIAL;
    const { settings, ...currentPlan } = tenant;
    return {
      ...currentPlan,
      plan: isTrial ? 'TRIAL' : currentPlan.plan,
      maxBranches: isTrial ? PLAN_PRICING.TRIAL.features.maxBranches : currentPlan.maxBranches,
      maxUsers: isTrial ? PLAN_PRICING.TRIAL.features.maxUsers : currentPlan.maxUsers,
      pendingPlan: selectedTrialPlan(settings) ?? (isTrial && currentPlan.plan !== 'TRIAL' ? currentPlan.plan : null),
      // A change scheduled for the next renewal on a paid plan.
      pendingChange: isTrial ? null : scheduledPlanChange(settings, currentPlan.plan),
      planMeta,
      availablePlans: Object.values(PLAN_PRICING),
    };
  }

  async changePlan(tenantId: string, newPlan: string) {
    await this.legalPolicies?.assertCurrentAcceptance(tenantId, 'BILLING_TERMS');
    if (!VALID_PLANS.includes(newPlan)) {
      throw new NotFoundException(`Invalid plan. Must be one of: ${VALID_PLANS.join(', ')}`);
    }

    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: {
        id: true,
        subscriptionStatus: true,
        currentPeriodStart: true,
        currentPeriodEnd: true,
        settings: true,
        plan: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    if (newPlan === 'TRIAL') {
      throw new ConflictException('Select a paid plan to continue after your free trial.');
    }
    if (PAID_STATUSES.includes(tenant.subscriptionStatus ?? '')) {
      return this.changePaidPlan(tenant, newPlan);
    }
    const now = new Date();
    const isActiveTrial =
      tenant.subscriptionStatus === 'TRIAL' &&
      tenant.currentPeriodEnd != null &&
      tenant.currentPeriodEnd.getTime() > now.getTime();
    if (!isActiveTrial) {
      throw new ConflictException(
        'Your trial has ended. Pay the open subscription invoice before changing your plan.',
      );
    }

    const currentSettings =
      tenant.settings && typeof tenant.settings === 'object' && !Array.isArray(tenant.settings)
        ? tenant.settings as Record<string, unknown>
        : {};
    const updated = await this.prisma.tenant.update({
      where: { id: tenantId },
      data: {
        // Selecting a future plan is not payment. Keep the trial's feature
        // access and seat limits until a verified provider charge settles.
        settings: { ...currentSettings, pendingSubscriptionPlan: newPlan } as Prisma.InputJsonValue,
      },
      select: {
        plan: true,
        subscriptionStatus: true,
        currentPeriodStart: true,
        currentPeriodEnd: true,
        maxBranches: true,
        maxUsers: true,
      },
    });
    return { ...updated, pendingPlan: newPlan };
  }

  /**
   * A paying company switches plans. Nothing is charged or downgraded on the
   * spot: the choice is recorded and the next invoice is issued for it, so the
   * plan the company already paid for stays in force until the period ends.
   * The exception is a company that is overdue with an unpaid invoice that no
   * checkout has started on: that invoice is re-priced, because nothing has
   * been paid yet and the next payment should be for the plan they want.
   */
  private async changePaidPlan(
    tenant: {
      id: string;
      plan: string | null;
      subscriptionStatus: string | null;
      currentPeriodEnd: Date | null;
      settings: unknown;
    },
    newPlan: string,
  ) {
    const currentPlan = tenant.plan ?? 'CORE';
    if (newPlan === currentPlan) {
      return this.cancelPlanChange(tenant.id);
    }
    const now = new Date();
    const periodEnded = tenant.currentPeriodEnd != null && tenant.currentPeriodEnd.getTime() <= now.getTime();
    const overdue = tenant.subscriptionStatus === 'PAST_DUE' || periodEnded;
    const openInvoice = await this.findOpenInvoice(tenant.id);

    if (overdue && openInvoice) {
      if (invoiceHasCheckoutInFlight(openInvoice)) {
        throw new ConflictException(
          'A payment for this month is already in progress. Finish it, or wait a few minutes, before changing your plan.',
        );
      }
      const plan = PLAN_PRICING[newPlan];
      await this.prisma.subscriptionInvoice.update({
        where: { id: openInvoice.id },
        data: {
          plan: newPlan,
          amount: new Prisma.Decimal(plan.monthlyAmountKes),
          provider: null,
          reference: null,
          authorizationUrl: null,
          authorizationIssuedAt: null,
          mpesaCheckoutId: null,
        },
      });
      await this.writeSettings(tenant.id, tenant.settings, {
        pendingSubscriptionPlan: undefined,
        pendingSubscriptionPlanEffectiveAt: undefined,
        pendingSubscriptionPlanRequestedAt: undefined,
      });
      return {
        plan: currentPlan,
        subscriptionStatus: tenant.subscriptionStatus,
        currentPeriodEnd: tenant.currentPeriodEnd,
        pendingPlan: newPlan,
        pendingChange: null,
        effective: 'on_payment' as const,
        invoicePlan: newPlan,
      };
    }

    const effectiveAt = tenant.currentPeriodEnd ? tenant.currentPeriodEnd.toISOString() : null;
    await this.writeSettings(tenant.id, tenant.settings, {
      pendingSubscriptionPlan: newPlan,
      pendingSubscriptionPlanEffectiveAt: effectiveAt ?? now.toISOString(),
      pendingSubscriptionPlanRequestedAt: now.toISOString(),
    });
    return {
      plan: currentPlan,
      subscriptionStatus: tenant.subscriptionStatus,
      currentPeriodEnd: tenant.currentPeriodEnd,
      pendingPlan: newPlan,
      pendingChange: {
        plan: newPlan,
        effectiveAt: effectiveAt ?? now.toISOString(),
        direction: planDirection(currentPlan, newPlan),
      },
      effective: 'at_renewal' as const,
    };
  }

  /** Drops a scheduled plan change; an unpaid, unstarted invoice goes back to the current plan. */
  async cancelPlanChange(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: {
        id: true,
        plan: true,
        subscriptionStatus: true,
        currentPeriodEnd: true,
        settings: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');
    const currentPlan = tenant.plan ?? 'CORE';

    if (PAID_STATUSES.includes(tenant.subscriptionStatus ?? '')) {
      const openInvoice = await this.findOpenInvoice(tenantId);
      if (
        openInvoice &&
        openInvoice.plan !== currentPlan &&
        PLAN_PRICING[currentPlan] &&
        !invoiceHasCheckoutInFlight(openInvoice)
      ) {
        await this.prisma.subscriptionInvoice.update({
          where: { id: openInvoice.id },
          data: {
            plan: currentPlan,
            amount: new Prisma.Decimal(PLAN_PRICING[currentPlan].monthlyAmountKes),
            provider: null,
            reference: null,
            authorizationUrl: null,
            authorizationIssuedAt: null,
            mpesaCheckoutId: null,
          },
        });
      }
    }
    await this.writeSettings(tenantId, tenant.settings, {
      pendingSubscriptionPlan: undefined,
      pendingSubscriptionPlanEffectiveAt: undefined,
      pendingSubscriptionPlanRequestedAt: undefined,
    });
    return {
      plan: currentPlan,
      subscriptionStatus: tenant.subscriptionStatus,
      currentPeriodEnd: tenant.currentPeriodEnd,
      pendingPlan: null,
      pendingChange: null,
      effective: 'none' as const,
    };
  }

  private findOpenInvoice(tenantId: string) {
    return this.prisma.subscriptionInvoice.findFirst({
      where: { tenantId, status: { in: ['PENDING', 'PENDING_CONFIRMATION'] } },
      orderBy: { createdAt: 'desc' },
    });
  }

  /** Merges keys into tenant.settings; a key set to undefined is removed. */
  private async writeSettings(
    tenantId: string,
    current: unknown,
    changes: Record<string, string | undefined>,
  ) {
    const next: Record<string, unknown> =
      current && typeof current === 'object' && !Array.isArray(current)
        ? { ...(current as Record<string, unknown>) }
        : {};
    for (const [key, value] of Object.entries(changes)) {
      if (value === undefined) delete next[key];
      else next[key] = value;
    }
    await this.prisma.tenant.update({
      where: { id: tenantId },
      data: { settings: next as Prisma.InputJsonValue },
    });
  }

  /** The plans on offer, straight from the price table the invoices use. */
  listPlans() {
    return {
      currency: 'KES',
      plans: Object.values(PLAN_PRICING).filter((p) => p.planId !== 'TRIAL'),
    };
  }

  async listInvoices(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    return this.prisma.subscriptionInvoice.findMany({
      where: { tenantId },
      orderBy: { createdAt: 'desc' },
    });
  }

  async getFeatureAccess(tenantId: string, feature: FeatureKey) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: {
        plan: true,
        subscriptionStatus: true,
        currentPeriodStart: true,
        createdAt: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    const plan = (tenant.subscriptionStatus === 'TRIAL' ? 'TRIAL' : tenant.plan ?? 'TRIAL').toUpperCase();

    // Enterprise plan always has everything.
    if (plan === 'ENTERPRISE') {
      return { allowed: true, reason: 'enterprise' };
    }

    // Business plan includes its feature set outright — no taste window.
    if (INCLUDED_FEATURES_BY_PLAN[plan]?.has(feature)) {
      return { allowed: true, reason: 'plan_included' };
    }

    // Some features are strictly Enterprise-only, no taste window.
    if (ENTERPRISE_ONLY_FEATURES.has(feature)) {
      return { allowed: false, reason: 'enterprise_only' };
    }

    // Everything else can be tasted by Core users for 7 days per billing period.
    if (plan === 'CORE') {
      const periodStart = tenant.currentPeriodStart ?? tenant.createdAt ?? new Date();
      const now = new Date();
      const daysSincePeriodStart = Math.floor(
        (now.getTime() - periodStart.getTime()) / (1000 * 60 * 60 * 24),
      );
      const allowed = daysSincePeriodStart < 7;
      return {
        allowed,
        reason: allowed ? 'taste_active' : 'taste_used',
        tasteDaysRemaining: Math.max(0, 7 - daysSincePeriodStart),
        tasteDaysUsed: Math.min(7, daysSincePeriodStart),
      };
    }

    // Trial plan is limited to free features only.
    return { allowed: false, reason: 'trial' };
  }
}

export function selectedTrialPlan(settings: unknown): string | null {
  if (!settings || typeof settings !== 'object' || Array.isArray(settings)) return null;
  const selected = (settings as Record<string, unknown>).pendingSubscriptionPlan;
  return typeof selected === 'string' && selected !== 'TRIAL' && VALID_PLANS.includes(selected)
    ? selected
    : null;
}

/** Statuses of a company that is paying (or owes a payment) rather than on trial. */
const PAID_STATUSES = ['ACTIVE', 'PAST_DUE'];

export type PlanDirection = 'UPGRADE' | 'DOWNGRADE';

export function planDirection(from: string, to: string): PlanDirection {
  const a = PLAN_PRICING[from]?.monthlyAmountKes ?? 0;
  const b = PLAN_PRICING[to]?.monthlyAmountKes ?? 0;
  return b >= a ? 'UPGRADE' : 'DOWNGRADE';
}

/**
 * A plan change a paying company scheduled for its next renewal. Only the new
 * flow writes `pendingSubscriptionPlanEffectiveAt`, so a trial-time selection
 * left in settings is never mistaken for a downgrade or an upgrade.
 */
export function scheduledPlanChange(
  settings: unknown,
  currentPlan: string | null | undefined,
): { plan: string; effectiveAt: string | null; direction: PlanDirection } | null {
  if (!settings || typeof settings !== 'object' || Array.isArray(settings)) return null;
  const s = settings as Record<string, unknown>;
  const plan = s.pendingSubscriptionPlan;
  const effectiveAt = s.pendingSubscriptionPlanEffectiveAt;
  if (typeof plan !== 'string' || typeof effectiveAt !== 'string') return null;
  if (!VALID_PLANS.includes(plan) || plan === 'TRIAL' || plan === currentPlan) return null;
  return { plan, effectiveAt, direction: planDirection(currentPlan ?? 'CORE', plan) };
}

/** The plan the next invoice is issued for. */
export function nextInvoicePlan(tenant: {
  plan?: string | null;
  settings?: unknown;
}): string {
  if (tenant.plan === 'TRIAL') return selectedTrialPlan(tenant.settings) ?? 'CORE';
  return scheduledPlanChange(tenant.settings, tenant.plan)?.plan ?? tenant.plan ?? 'CORE';
}

/** A checkout or M-Pesa prompt has already been started on this invoice. */
export function invoiceHasCheckoutInFlight(invoice: {
  provider?: string | null;
  authorizationIssuedAt?: Date | null;
}): boolean {
  const provider = invoice.provider;
  if (!provider || provider === 'PAYSTACK_FAILED') return false;
  if (provider === 'PAYSTACK') {
    // A hosted link nobody paid within a day is dead; do not let it block a
    // plan change forever. Rows from before the issue time was recorded too.
    const issued = invoice.authorizationIssuedAt;
    return !!issued && Date.now() - new Date(issued).getTime() < 24 * 60 * 60 * 1000;
  }
  return true;
}

export type FeatureKey =
  | 'multi_branch_dashboard'
  | 'multi_branch_transfers'
  | 'advanced_reports'
  | 'ai_insights'
  | 'ai_fraud_detection'
  | 'ai_supply_chain'
  | 'supplier_management'
  | 'whatsapp_bot'
  | 'whatsapp_promotions'
  | 'staff_performance'
  | 'priority_support'
  | 'customer_360';

/**
 * Features a paid plan includes outright, with no 7-day taste window.
 * ENTERPRISE is handled separately (it includes everything).
 */
const INCLUDED_FEATURES_BY_PLAN: Record<string, ReadonlySet<FeatureKey>> = {
  BUSINESS: new Set<FeatureKey>([
    'multi_branch_dashboard',
    'multi_branch_transfers',
    'advanced_reports',
    'ai_insights',
    'supplier_management',
    'whatsapp_bot',
    'whatsapp_promotions',
    'staff_performance',
    'customer_360',
  ]),
};

/**
 * Features with no taste window on CORE/TRIAL: ai_fraud_detection,
 * ai_supply_chain and priority_support are strictly ENTERPRISE-only; the
 * rest are unlocked by BUSINESS (see INCLUDED_FEATURES_BY_PLAN) but never
 * tasted by CORE.
 */
const ENTERPRISE_ONLY_FEATURES = new Set<FeatureKey>([
  'multi_branch_transfers',
  'ai_fraud_detection',
  'ai_supply_chain',
  'supplier_management',
  'whatsapp_bot',
  'whatsapp_promotions',
  'staff_performance',
  'priority_support',
]);

export const TASTE_FEATURES = new Set<FeatureKey>([
  'multi_branch_dashboard',
  'advanced_reports',
  'ai_insights',
  'customer_360',
]);
