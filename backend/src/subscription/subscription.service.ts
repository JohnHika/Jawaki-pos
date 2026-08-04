import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

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
    monthlyAmountKes: 3200,
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
  ENTERPRISE: {
    planId: 'ENTERPRISE',
    name: 'Enterprise',
    monthlyAmountKes: 5000,
    trialDays: 7,
    features: {
      maxBranches: 10,
      maxUsers: 50,
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
  constructor(private readonly prisma: PrismaService) {}

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
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');
    const planMeta = PLAN_PRICING[tenant.plan ?? 'TRIAL'] ?? PLAN_PRICING.TRIAL;
    return {
      ...tenant,
      planMeta,
      availablePlans: Object.values(PLAN_PRICING),
    };
  }

  async changePlan(tenantId: string, newPlan: string) {
    if (!VALID_PLANS.includes(newPlan)) {
      throw new NotFoundException(`Invalid plan. Must be one of: ${VALID_PLANS.join(', ')}`);
    }

    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    const plan = PLAN_PRICING[newPlan];
    const now = new Date();
    const periodEnd = new Date(now);
    periodEnd.setMonth(periodEnd.getMonth() + 1);

    return this.prisma.tenant.update({
      where: { id: tenantId },
      data: {
        plan: newPlan,
        subscriptionStatus: 'ACTIVE',
        currentPeriodStart: now,
        currentPeriodEnd: periodEnd,
        maxBranches: plan.features.maxBranches,
        maxUsers: plan.features.maxUsers,
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
        currentPeriodStart: true,
        createdAt: true,
      },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    const plan = (tenant.plan ?? 'TRIAL').toUpperCase();

    // Enterprise plan always has everything.
    if (plan === 'ENTERPRISE') {
      return { allowed: true, reason: 'enterprise' };
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
