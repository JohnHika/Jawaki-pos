import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { PLAN_PRICING } from '../subscription/subscription.service';

/**
 * Credit convention: a goodwill credit is stored as a SubscriptionInvoice
 * with a NEGATIVE amount, status PAID, provider='CREDIT', and the reason in
 * the `reference` field (prefix `CREDIT:`). This keeps ledger arithmetic
 * simple: net owed for a tenant = sum(amount) across invoices, so a credit
 * automatically offsets the next renewal invoice. paidAt is set at creation
 * because a credit is instantly "settled" — no payment is expected.
 */
export const CREDIT_PROVIDER = 'CREDIT';

export const SUBSCRIPTION_STATUSES = [
  'ACTIVE',
  'TRIAL',
  'PAST_DUE',
  'SUSPENDED',
  'CANCELLED',
] as const;

const FAILED_PAYMENT_GRACE_DAYS = 7;

@Injectable()
export class PlatformAdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditService: AuditService,
  ) {}

  async getDashboard() {
    const statusRows = await this.prisma.tenant.groupBy({
      by: ['subscriptionStatus'],
      _count: true,
    });

    const counts = {
      ACTIVE: 0,
      TRIAL: 0,
      PAST_DUE: 0,
      SUSPENDED: 0,
      CANCELLED: 0,
    };
    let unmapped = 0;
    for (const row of statusRows) {
      const key = row.subscriptionStatus as keyof typeof counts | null;
      if (key && key in counts) {
        counts[key] += row._count;
      } else {
        unmapped += row._count;
      }
    }

    const activeNonTrial = await this.prisma.tenant.findMany({
      where: { subscriptionStatus: 'ACTIVE', plan: { not: 'TRIAL' } },
      select: { plan: true },
    });
    const mrr = activeNonTrial.reduce(
      (sum, t) => sum + (PLAN_PRICING[t.plan]?.monthlyAmountKes ?? 0),
      0,
    );

    const failedPaymentsCutoff = new Date(Date.now() - FAILED_PAYMENT_GRACE_DAYS * 86_400_000);
    const [failedPayments, recentPayments] = await Promise.all([
      this.prisma.subscriptionInvoice.count({
        where: { status: 'PENDING', createdAt: { lt: failedPaymentsCutoff } },
      }),
      this.prisma.subscriptionInvoice.findMany({
        where: { status: 'PAID' },
        orderBy: { paidAt: 'desc' },
        take: 10,
        select: {
          id: true,
          tenantId: true,
          plan: true,
          amount: true,
          paidAt: true,
          provider: true,
          reference: true,
          tenant: { select: { name: true } },
        },
      }),
    ]);

    return {
      tenants: counts,
      tenantsUnmappedStatus: unmapped,
      mrrKes: mrr,
      arrKes: mrr * 12,
      failedPayments,
      recentPayments: recentPayments.map((invoice) => ({
        id: invoice.id,
        tenantId: invoice.tenantId,
        tenantName: invoice.tenant.name,
        plan: invoice.plan,
        amount: invoice.amount,
        paidAt: invoice.paidAt,
        provider: invoice.provider,
        reference: invoice.reference,
      })),
    };
  }

  async listTenants(query: { status?: string; search?: string; page?: number; pageSize?: number }) {
    const page = query.page ?? 1;
    const pageSize = Math.min(query.pageSize ?? 20, 100);
    const where: any = {};
    if (query.status) where.subscriptionStatus = query.status;
    if (query.search) where.name = { contains: query.search, mode: 'insensitive' };

    const [tenants, total] = await Promise.all([
      this.prisma.tenant.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
        select: {
          id: true,
          name: true,
          slug: true,
          plan: true,
          subscriptionStatus: true,
          currentPeriodStart: true,
          currentPeriodEnd: true,
          createdAt: true,
          _count: { select: { subscriptionInvoices: true } },
        },
      }),
      this.prisma.tenant.count({ where }),
    ]);

    return {
      items: tenants.map((tenant) => ({
        id: tenant.id,
        name: tenant.name,
        slug: tenant.slug,
        plan: tenant.plan,
        subscriptionStatus: tenant.subscriptionStatus,
        currentPeriodStart: tenant.currentPeriodStart,
        currentPeriodEnd: tenant.currentPeriodEnd,
        createdAt: tenant.createdAt,
        invoiceCount: tenant._count.subscriptionInvoices,
      })),
      total,
      page,
      pageSize,
      totalPages: Math.ceil(total / pageSize),
    };
  }

  async getTenantDetail(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      include: {
        users: {
          where: { role: 'ADMIN' },
          select: { id: true, email: true, firstName: true, lastName: true },
          take: 1,
        },
        _count: { select: { branches: true, users: true, subscriptionInvoices: true } },
      },
    });
    if (!tenant) throw new NotFoundException('Tenant not found');

    const [invoices, claims] = await Promise.all([
      this.prisma.subscriptionInvoice.findMany({
        where: { tenantId },
        orderBy: { createdAt: 'desc' },
        take: 5,
      }),
      this.prisma.subscriptionPaymentClaim.findMany({
        where: { tenantId },
        orderBy: { createdAt: 'desc' },
        take: 10,
      }),
    ]);

    const owner = tenant.users[0] ?? null;
    return {
      id: tenant.id,
      name: tenant.name,
      slug: tenant.slug,
      plan: tenant.plan,
      subscriptionStatus: tenant.subscriptionStatus,
      currentPeriodStart: tenant.currentPeriodStart,
      currentPeriodEnd: tenant.currentPeriodEnd,
      maxBranches: tenant.maxBranches,
      maxUsers: tenant.maxUsers,
      autoRenewEnabled: tenant.autoRenewEnabled,
      billingPhone: tenant.billingPhone,
      activationStatus: tenant.activationStatus,
      createdAt: tenant.createdAt,
      owner,
      counts: {
        branches: tenant._count.branches,
        users: tenant._count.users,
        invoices: tenant._count.subscriptionInvoices,
      },
      last5Invoices: invoices,
      claims,
    };
  }

  async extendTenant(tenantId: string, days: number, actor: { id: string; email: string }) {
    const tenant = await this.getTenantOrThrow(tenantId);
    const currentEnd = tenant.currentPeriodEnd ?? new Date();
    const base = currentEnd > new Date() ? currentEnd : new Date();
    const newPeriodEnd = new Date(base.getTime() + days * 86_400_000);

    const updated = await this.prisma.tenant.update({
      where: { id: tenantId },
      data: { currentPeriodEnd: newPeriodEnd },
      select: { id: true, currentPeriodEnd: true },
    });

    await this.auditService.record({
      userId: null,
      action: 'PLATFORM_ADMIN_TENANT_EXTENDED',
      entityType: 'Tenant',
      entityId: tenantId,
      oldValues: { currentPeriodEnd: tenant.currentPeriodEnd },
      newValues: { currentPeriodEnd: newPeriodEnd, days },
    });
    void actor;

    return updated;
  }

  async setSuspended(tenantId: string, actor: { id: string; email: string }) {
    return this.setStatus(tenantId, 'SUSPENDED', actor);
  }

  async setReactivated(tenantId: string, actor: { id: string; email: string }) {
    return this.setStatus(tenantId, 'ACTIVE', actor);
  }

  private async setStatus(
    tenantId: string,
    status: string,
    actor: { id: string; email: string },
  ) {
    const tenant = await this.getTenantOrThrow(tenantId);
    const updated = await this.prisma.tenant.update({
      where: { id: tenantId },
      data: { subscriptionStatus: status },
      select: { id: true, subscriptionStatus: true },
    });

    await this.auditService.record({
      userId: null,
      action: status === 'SUSPENDED' ? 'PLATFORM_ADMIN_TENANT_SUSPENDED' : 'PLATFORM_ADMIN_TENANT_REACTIVATED',
      entityType: 'Tenant',
      entityId: tenantId,
      oldValues: { subscriptionStatus: tenant.subscriptionStatus },
      newValues: { subscriptionStatus: status },
    });
    void actor;

    return updated;
  }

  async creditTenant(
    tenantId: string,
    amountKes: number,
    reason: string,
    actor: { id: string; email: string },
  ) {
    await this.getTenantOrThrow(tenantId);
    const now = new Date();
    const periodEnd = new Date(now);
    periodEnd.setMonth(periodEnd.getMonth() + 1);
    const reference = `CREDIT:${reason}`.slice(0, 180);

    const invoice = await this.prisma.subscriptionInvoice.create({
      data: {
        tenantId,
        plan: 'CREDIT',
        amount: -amountKes,
        status: 'PAID',
        provider: CREDIT_PROVIDER,
        reference,
        periodStart: now,
        periodEnd,
        paidAt: now,
        renewalSequence: 0,
      },
    });

    await this.auditService.record({
      userId: null,
      action: 'PLATFORM_ADMIN_TENANT_CREDITED',
      entityType: 'SubscriptionInvoice',
      entityId: invoice.id,
      oldValues: null,
      newValues: { tenantId, amountKes: -amountKes, reason, provider: CREDIT_PROVIDER },
    });
    void actor;

    return invoice;
  }

  async listInvoices(query: { status?: string; tenantId?: string; page?: number; pageSize?: number }) {
    const page = query.page ?? 1;
    const pageSize = Math.min(query.pageSize ?? 20, 100);
    const where: any = {};
    if (query.status) where.status = query.status;
    if (query.tenantId) where.tenantId = query.tenantId;

    const [invoices, total] = await Promise.all([
      this.prisma.subscriptionInvoice.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
        include: { tenant: { select: { id: true, name: true } } },
      }),
      this.prisma.subscriptionInvoice.count({ where }),
    ]);

    return {
      items: invoices.map((invoice) => ({
        ...invoice,
        tenantName: invoice.tenant.name,
        tenant: undefined,
      })),
      total,
      page,
      pageSize,
      totalPages: Math.ceil(total / pageSize),
    };
  }

  async markInvoicePaid(invoiceId: string, mpesaCode: string | undefined, actor: { id: string; email: string }) {
    const invoice = await this.prisma.subscriptionInvoice.findUnique({ where: { id: invoiceId } });
    if (!invoice) throw new NotFoundException('Invoice not found');
    if (invoice.status === 'PAID') {
      throw new ConflictException('Invoice is already marked PAID');
    }

    const paidAt = new Date();
    const updated = await this.prisma.subscriptionInvoice.update({
      where: { id: invoiceId },
      data: {
        status: 'PAID',
        paidAt,
        provider: mpesaCode ? 'MPESA_MANUAL' : invoice.provider,
        reference: mpesaCode ?? invoice.reference,
      },
    });

    // When John reconciles a tenant's payment manually, reactivate the
    // tenant if it was suspended/past-due for non-payment (matching the
    // renewal flow: PAID => ACTIVE).
    if (mpesaCode) {
      await this.prisma.tenant.updateMany({
        where: { id: invoice.tenantId, subscriptionStatus: { in: ['PAST_DUE', 'SUSPENDED'] } },
        data: { subscriptionStatus: 'ACTIVE' },
      });
    }

    await this.auditService.record({
      userId: null,
      action: 'PLATFORM_ADMIN_INVOICE_MARKED_PAID',
      entityType: 'SubscriptionInvoice',
      entityId: invoiceId,
      oldValues: { status: invoice.status, paidAt: invoice.paidAt },
      newValues: { status: 'PAID', paidAt, mpesaCode: mpesaCode ?? null },
    });
    void actor;

    return updated;
  }

  private async getTenantOrThrow(tenantId: string) {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true, subscriptionStatus: true, currentPeriodEnd: true },
    });
    if (!tenant) throw new NotFoundException('Tenant not found');
    return tenant;
  }
}