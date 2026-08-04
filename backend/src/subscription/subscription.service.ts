import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

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
    return tenant;
  }

  async changePlan(tenantId: string, newPlan: string) {
    const validPlans = ['TRIAL', 'CORE', 'ENTERPRISE'];
    if (!validPlans.includes(newPlan)) {
      throw new NotFoundException(`Invalid plan. Must be one of: ${validPlans.join(', ')}`);
    }

    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true },
    });
    if (!tenant) throw new NotFoundException('Company not found');

    const limits = this.getPlanLimits(newPlan);
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
        maxBranches: limits.maxBranches,
        maxUsers: limits.maxUsers,
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

  private getPlanLimits(plan: string): { maxBranches: number; maxUsers: number } {
    switch (plan) {
      case 'ENTERPRISE':
        return { maxBranches: 10, maxUsers: 50 };
      case 'CORE':
        return { maxBranches: 3, maxUsers: 10 };
      case 'TRIAL':
      default:
        return { maxBranches: 1, maxUsers: 3 };
    }
  }
}
