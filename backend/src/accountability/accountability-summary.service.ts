import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PaymentMethod, SaleStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { getDayBoundsInTimezone, todayInTimezone } from '../common/operating-hours';
import { AccountabilityService, MANAGER_ROLES } from './accountability.service';

export interface BranchDaySummary {
  branchId: string;
  branchName: string;
  date: string;
  salesCount: number;
  totalSales: number;
  cash: number;
  mpesa: number;
  card: number;
  credit: number;
  split: number;
  voidCount: number;
  voidAmount: number;
  refundCount: number;
  refundAmount: number;
  creditGiven: number;
  creditOutstanding: number;
  cashDiscrepancy: number | null;
  couponUses: number;
  couponGiven: number;
  /** Supplier invoices past their due date, and those falling due within a week. */
  supplierOverdue: number;
  supplierDueSoon: number;
  /** Customer "I have paid" / "I will pay" replies waiting for the owner. */
  pendingClaims: number;
  dayClosed: boolean;
  flags: Record<string, number>;
}

const kes = (n: number) => `KES ${Math.round(n).toLocaleString('en-KE')}`;

/** Local hour (0-23) right now in `timezone`. */
export function localHour(timezone: string, at: Date = new Date()): number {
  const hour = new Intl.DateTimeFormat('en-GB', {
    timeZone: timezone || 'Africa/Nairobi',
    hour: '2-digit',
    hour12: false,
  }).format(at);
  return Number(hour) % 24;
}

@Injectable()
export class AccountabilitySummaryService {
  private readonly logger = new Logger(AccountabilitySummaryService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly accountability: AccountabilityService,
  ) {}

  async buildBranchSummary(
    tenantId: string,
    branchId: string,
    date?: string,
  ): Promise<BranchDaySummary> {
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
      select: { id: true, name: true, timezone: true },
    });
    if (!branch) throw new NotFoundException('Branch not found');

    const tz = branch.timezone || 'Africa/Nairobi';
    const day = date ?? todayInTimezone(tz);
    const { start, end } = getDayBoundsInTimezone(day, tz);
    const range = { gte: start, lte: end };

    const weekAhead = new Date(Date.now() + 7 * 86_400_000);
    const [byMethod, voided, refunds, creditGiven, creditOpen, close, alerts, coupons, overdue, dueSoon, claims] =
      await Promise.all([
      this.prisma.sale.groupBy({
        by: ['paymentMethod'],
        where: {
          branchId,
          createdAt: range,
          status: { in: [SaleStatus.COMPLETED, SaleStatus.PARTIAL_REFUND, SaleStatus.REFUNDED] },
        },
        _sum: { totalAmount: true },
        _count: { _all: true },
      }),
      this.prisma.sale.aggregate({
        where: { branchId, status: SaleStatus.VOIDED, updatedAt: range },
        _sum: { totalAmount: true },
        _count: { _all: true },
      }),
      this.prisma.refund.aggregate({
        where: { sale: { branchId }, createdAt: range },
        _sum: { amount: true },
        _count: { _all: true },
      }),
      this.prisma.retailReceivable.aggregate({
        where: { tenantId, branchId, createdAt: range },
        _sum: { originalAmount: true },
      }),
      this.prisma.retailReceivable.aggregate({
        where: { tenantId, branchId, status: { in: ['OPEN', 'PARTIAL'] } },
        _sum: { outstandingAmount: true },
      }),
      this.prisma.dailyClose.findFirst({
        where: { branchId, date: new Date(`${day}T00:00:00.000Z`) },
        select: { cashDiscrepancy: true },
      }),
      this.prisma.accountabilityAlert.groupBy({
        by: ['type'],
        where: {
          tenantId,
          OR: [{ branchId }, { branchId: null }],
          createdAt: range,
          type: { not: 'DAILY_SUMMARY' },
        },
        _count: { _all: true },
      }),
      this.prisma.couponRedemption.aggregate({
        where: { tenantId, branchId, createdAt: range },
        _sum: { amount: true },
        _count: { _all: true },
      }),
      this.prisma.supplierInvoice.aggregate({
        where: { tenantId, branchId, status: { not: 'PAID' }, dueDate: { lt: new Date() } },
        _sum: { dueAmount: true },
      }),
      this.prisma.supplierInvoice.aggregate({
        where: { tenantId, branchId, status: { not: 'PAID' }, dueDate: { gte: new Date(), lte: weekAhead } },
        _sum: { dueAmount: true },
      }),
      this.prisma.statementClaim.count({ where: { tenantId, status: 'PENDING' } }),
    ]);

    const amount = (m: PaymentMethod) =>
      Number(byMethod.find((r) => r.paymentMethod === m)?._sum.totalAmount ?? 0);
    const totalSales = byMethod.reduce((s, r) => s + Number(r._sum.totalAmount ?? 0), 0);
    const salesCount = byMethod.reduce((s, r) => s + r._count._all, 0);

    return {
      branchId,
      branchName: branch.name,
      date: day,
      salesCount,
      totalSales,
      cash: amount(PaymentMethod.CASH),
      mpesa: amount(PaymentMethod.MPESA),
      card: amount(PaymentMethod.PESAPAL) + amount(PaymentMethod.TOURISTTAP),
      credit: amount(PaymentMethod.CREDIT),
      split: amount(PaymentMethod.SPLIT),
      voidCount: voided._count._all,
      voidAmount: Number(voided._sum.totalAmount ?? 0),
      refundCount: refunds._count._all,
      refundAmount: Number(refunds._sum.amount ?? 0),
      creditGiven: Number(creditGiven._sum.originalAmount ?? 0),
      creditOutstanding: Number(creditOpen._sum.outstandingAmount ?? 0),
      cashDiscrepancy: close ? Number(close.cashDiscrepancy) : null,
      couponUses: coupons._count._all,
      couponGiven: Number(coupons._sum.amount ?? 0),
      supplierOverdue: Number(overdue._sum.dueAmount ?? 0),
      supplierDueSoon: Number(dueSoon._sum.dueAmount ?? 0),
      pendingClaims: claims,
      dayClosed: !!close,
      flags: Object.fromEntries(alerts.map((a) => [a.type, a._count._all])),
    };
  }

  /** Short, phone-friendly text for the push and the in-app feed. */
  formatSummary(s: BranchDaySummary): { title: string; body: string } {
    const lines: string[] = [];
    lines.push(`Sales ${kes(s.totalSales)} from ${s.salesCount} sale${s.salesCount === 1 ? '' : 's'}.`);

    const methods = [
      s.cash > 0 && `Cash ${kes(s.cash)}`,
      s.mpesa > 0 && `M-Pesa ${kes(s.mpesa)}`,
      s.card > 0 && `Card ${kes(s.card)}`,
      s.credit > 0 && `Credit ${kes(s.credit)}`,
      s.split > 0 && `Split ${kes(s.split)}`,
    ].filter(Boolean);
    if (methods.length) lines.push(methods.join(' · '));

    const watch: string[] = [];
    if (s.voidCount > 0) watch.push(`${s.voidCount} void${s.voidCount === 1 ? '' : 's'} (${kes(s.voidAmount)})`);
    if (s.refundCount > 0) watch.push(`${s.refundCount} refund${s.refundCount === 1 ? '' : 's'} (${kes(s.refundAmount)})`);
    const belowCost = (s.flags.BELOW_COST ?? 0) + (s.flags.BELOW_FLOOR ?? 0);
    if (belowCost > 0) watch.push(`${belowCost} below-price sale${belowCost === 1 ? '' : 's'}`);
    if ((s.flags.DISCOUNT_LIMIT ?? 0) > 0) watch.push(`${s.flags.DISCOUNT_LIMIT} over-limit discount${s.flags.DISCOUNT_LIMIT === 1 ? '' : 's'}`);
    if ((s.flags.STOCK_WRITE_OFF ?? 0) > 0) watch.push(`${s.flags.STOCK_WRITE_OFF} stock write-off${s.flags.STOCK_WRITE_OFF === 1 ? '' : 's'}`);
    if (s.creditGiven > 0) watch.push(`${kes(s.creditGiven)} given on credit`);
    if (s.couponUses > 0) watch.push(`${s.couponUses} coupon${s.couponUses === 1 ? "" : "s"} used (${kes(s.couponGiven)} given away)`);
    if (watch.length) lines.push(`Check: ${watch.join(', ')}.`);

    if (!s.dayClosed) lines.push('The day has not been closed yet.');
    else if (s.cashDiscrepancy !== null && Math.abs(s.cashDiscrepancy) >= 1) {
      lines.push(
        s.cashDiscrepancy < 0
          ? `Till SHORT by ${kes(Math.abs(s.cashDiscrepancy))}.`
          : `Till OVER by ${kes(s.cashDiscrepancy)}.`,
      );
    } else lines.push('Till balanced.');

    if (s.creditOutstanding > 0) lines.push(`Customers owe you ${kes(s.creditOutstanding)} in total.`);
    if (s.pendingClaims > 0) {
      lines.push(
        `${s.pendingClaims} customer${s.pendingClaims === 1 ? " says" : "s say"} they have paid or will pay. Open Statements to confirm.`,
      );
    }
    if (s.supplierOverdue > 0) lines.push(`You owe suppliers ${kes(s.supplierOverdue)} that is past due.`);
    if (s.supplierDueSoon > 0) lines.push(`${kes(s.supplierDueSoon)} to suppliers falls due this week.`);

    return { title: `${s.branchName} — today`, body: lines.join('\n') };
  }

  /**
   * Hourly sweep: for each branch whose local clock has reached the owner's
   * chosen summary hour and which hasn't had today's summary yet, build it,
   * store it in the alert feed and push it. `>=` rather than `==` so a missed
   * or late cron slot still delivers that evening.
   */
  @Cron('5 * * * *')
  async sendDueSummaries(): Promise<{ sent: number }> {
    const branches = await this.prisma.branch.findMany({
      where: { isActive: true },
      select: { id: true, tenantId: true, timezone: true },
    });

    const settingsByTenant = new Map<string, Awaited<ReturnType<AccountabilityService['getSettings']>>>();
    let sent = 0;

    for (const branch of branches) {
      try {
        const tz = branch.timezone || 'Africa/Nairobi';
        let settings = settingsByTenant.get(branch.tenantId);
        if (!settings) {
          settings = await this.accountability.getSettings(branch.tenantId);
          settingsByTenant.set(branch.tenantId, settings);
        }
        if (!settings.dailySummary.enabled) continue;
        if (localHour(tz) < settings.dailySummary.hourLocal) continue;

        const day = todayInTimezone(tz);
        const key = `${branch.id}:${day}`;
        const already = await this.prisma.accountabilityAlert.findFirst({
          where: { tenantId: branch.tenantId, type: 'DAILY_SUMMARY', entityId: key },
          select: { id: true },
        });
        if (already) continue;

        const summary = await this.buildBranchSummary(branch.tenantId, branch.id, day);
        // A branch that traded nothing and opened nothing needn't wake anyone.
        if (summary.salesCount === 0 && summary.voidCount === 0 && !summary.dayClosed) continue;

        const text = this.formatSummary(summary);
        await this.accountability.raise({
          tenantId: branch.tenantId,
          branchId: branch.id,
          type: 'DAILY_SUMMARY',
          severity: 'LOW',
          title: text.title,
          body: text.body,
          entityType: 'BranchDay',
          entityId: key,
          data: summary as unknown as Record<string, unknown>,
        });
        await this.notifications.sendToTenantRoles(branch.tenantId, MANAGER_ROLES, {
          title: text.title,
          body: text.body,
          data: { type: 'daily_summary', branchId: branch.id, date: day },
        });
        sent++;
      } catch (error) {
        this.logger.error(`Daily summary failed for branch ${branch.id}: ${error}`);
      }
    }

    if (sent > 0) this.logger.log(`Daily summaries sent: ${sent}`);
    return { sent };
  }
}
