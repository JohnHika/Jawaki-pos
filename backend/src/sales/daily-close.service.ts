import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { SalesService } from './sales.service';
import { CashReconciliationService } from '../cash-flow/cash-reconciliation.service';
import { CloseDayDto } from './dto/daily-close.dto';

/**
 * End-of-day "Z-report" close. Finalizes one branch-day into a permanent
 * DailyClose snapshot: the day's sales/transactions/payment split plus a
 * cash count. It also books a CashReconciliation for the counted-vs-expected
 * difference (reusing the existing cash flow), so closing the day is a single
 * unified action rather than two separate steps.
 *
 * It does NOT lock sales — the next day starts fresh by date. Closing is
 * idempotent: re-closing the same branch-day updates the existing record
 * (e.g. a re-count after a correction).
 */
@Injectable()
export class DailyCloseService {
  constructor(
    private prisma: PrismaService,
    private auditService: AuditService,
    private salesService: SalesService,
    private reconciliationService: CashReconciliationService,
  ) {}

  /** UTC midnight for the given (or today's) date — the stable key for a
   * business day, matching how DailyBrief normalizes its date. */
  private normalizeDate(date?: string): Date {
    const base = date ? new Date(date) : new Date();
    return new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth(), base.getUTCDate()));
  }

  async closeDay(userId: string, tenantId: string, branchId: string, dto: CloseDayDto) {
    const branch = await this.prisma.branch.findFirst({ where: { id: branchId, tenantId } });
    if (!branch) throw new NotFoundException('Branch not found');

    const date = this.normalizeDate(dto.date);
    const dateStr = date.toISOString().split('T')[0];

    // Full sales + payment-method picture for the day.
    const summary = await this.salesService.getDailySummary(branchId, dateStr, tenantId);

    // Book the cash count as a reconciliation (also corrects the ledger for
    // any discrepancy in RUNNING_BALANCE mode). This is the source of the
    // expected-vs-counted figures we snapshot into the close.
    const reconciliation = await this.reconciliationService.createReconciliation(
      userId,
      branchId,
      { countedCash: dto.countedCash, notes: dto.notes },
    );

    const data = {
      branchId,
      date,
      totalSales: summary.totalSales,
      totalTransactions: summary.totalTransactions,
      cashSales: summary.cashSales,
      mpesaSales: summary.mpesaSales,
      cardSales: summary.cardSales,
      creditSales: summary.creditSales,
      outstandingBalance: summary.outstandingBalance,
      totalTax: summary.totalTax,
      totalDiscount: summary.totalDiscount,
      expectedCash: reconciliation.expectedCash,
      countedCash: reconciliation.countedCash,
      cashDiscrepancy: reconciliation.discrepancy,
      reconciliationId: reconciliation.id,
      notes: dto.notes,
      closedById: userId,
      closedAt: new Date(),
    };

    // Idempotent per branch-day: re-closing updates the snapshot.
    const close = await this.prisma.dailyClose.upsert({
      where: { branchId_date: { branchId, date } },
      create: data,
      update: data,
    });

    await this.auditService.record({
      userId,
      action: 'CREATE',
      entityType: 'daily_close',
      entityId: close.id,
      newValues: {
        date: dateStr,
        totalSales: summary.totalSales,
        countedCash: dto.countedCash,
        discrepancy: reconciliation.discrepancy,
      },
    });

    return this.format(close);
  }

  /** The close for a specific day (or today) — null if not yet closed. Lets
   * the app show "closed at 7:12pm by Jane" vs an open day. */
  async getClose(tenantId: string, branchId: string, date?: string) {
    const branch = await this.prisma.branch.findFirst({ where: { id: branchId, tenantId } });
    if (!branch) throw new NotFoundException('Branch not found');

    const normalized = this.normalizeDate(date);
    const close = await this.prisma.dailyClose.findUnique({
      where: { branchId_date: { branchId, date: normalized } },
      include: { closedBy: { select: { firstName: true, lastName: true } } },
    });
    return close ? this.format(close) : null;
  }

  async getHistory(tenantId: string, branchId: string, limit = 30) {
    const branch = await this.prisma.branch.findFirst({ where: { id: branchId, tenantId } });
    if (!branch) throw new NotFoundException('Branch not found');

    const items = await this.prisma.dailyClose.findMany({
      where: { branchId },
      include: { closedBy: { select: { firstName: true, lastName: true } } },
      orderBy: { date: 'desc' },
      take: Math.min(limit, 90),
    });
    return items.map((c) => this.format(c));
  }

  private format(c: any) {
    return {
      id: c.id,
      branchId: c.branchId,
      date: c.date,
      totalSales: Number(c.totalSales),
      totalTransactions: c.totalTransactions,
      cashSales: Number(c.cashSales),
      mpesaSales: Number(c.mpesaSales),
      cardSales: Number(c.cardSales),
      creditSales: Number(c.creditSales),
      outstandingBalance: Number(c.outstandingBalance),
      totalTax: Number(c.totalTax),
      totalDiscount: Number(c.totalDiscount),
      expectedCash: Number(c.expectedCash),
      countedCash: Number(c.countedCash),
      cashDiscrepancy: Number(c.cashDiscrepancy),
      reconciliationId: c.reconciliationId,
      notes: c.notes,
      closedById: c.closedById,
      closedByName: c.closedBy ? `${c.closedBy.firstName} ${c.closedBy.lastName}` : undefined,
      closedAt: c.closedAt,
    };
  }
}
