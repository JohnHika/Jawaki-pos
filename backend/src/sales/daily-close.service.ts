import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { SalesService } from './sales.service';
import { CashReconciliationService } from '../cash-flow/cash-reconciliation.service';
import { CloseDayDto } from './dto/daily-close.dto';
import { todayInTimezone } from '../common/operating-hours';

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

  /** UTC midnight for the given date, or the branch's current business day. */
  private normalizeDate(date: string | undefined, timezone: string): Date {
    const base = date
      ? new Date(date)
      : new Date(`${todayInTimezone(timezone)}T00:00:00.000Z`);
    return new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth(), base.getUTCDate()));
  }

  async closeDay(userId: string, tenantId: string, branchId: string, dto: CloseDayDto) {
    const branch = await this.prisma.branch.findFirst({ where: { id: branchId, tenantId } });
    if (!branch) throw new NotFoundException('Branch not found');

    const timezone = branch.timezone ?? 'Africa/Nairobi';
    const businessDay = todayInTimezone(timezone);
    const date = this.normalizeDate(dto.date ?? businessDay, timezone);
    const dateStr = date.toISOString().split('T')[0];
    if (dateStr !== businessDay) {
      throw new BadRequestException(
        'End of day can only be closed for the current business day. Historical cash counts cannot be reconciled against today’s till balance.',
      );
    }

    // Full sales + payment-method picture for the day.
    const summary = await this.salesService.getDailySummary(branchId, dateStr, tenantId);

    // Commit the till adjustment and the Z-report as one operation. The
    // branch lock also serializes concurrent close taps so retries can reuse
    // the first reconciliation instead of creating duplicate ledger history.
    const result = await this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${branchId}))`;

      const existingClose = await tx.dailyClose.findUnique({
        where: { branchId_date: { branchId, date } },
      });

      let reconciliationResult:
        | Awaited<ReturnType<CashReconciliationService['createReconciliationInTransaction']>>
        | null = null;
      let reconciliationCreated = false;

      // A network retry or an unchanged re-close should be idempotent across
      // both the Z-report and the cash ledger, not just the upsert below.
      if (
        existingClose?.reconciliationId &&
        Number(existingClose.countedCash) === dto.countedCash
      ) {
        const previous = await tx.cashReconciliation.findFirst({
          where: {
            id: existingClose.reconciliationId,
            branchId,
          },
        });
        if (previous) {
          const laterCashMovement = await tx.cashLedgerEntry.findFirst({
            where: { branchId, createdAt: { gt: previous.createdAt } },
            select: { id: true },
          });
          if (!laterCashMovement) {
            reconciliationResult = {
              reconciliation: previous,
              expectedCash: Number(previous.expectedCash),
              discrepancy: Number(previous.discrepancy),
            };
          }
        }
      }

      if (!reconciliationResult) {
        reconciliationResult = await this.reconciliationService
          .createReconciliationInTransaction(tx, userId, tenantId, branchId, {
            countedCash: dto.countedCash,
            notes: dto.notes,
          });
        reconciliationCreated = true;
      }

      const reconciliation = reconciliationResult.reconciliation;
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

      const close = await tx.dailyClose.upsert({
        where: { branchId_date: { branchId, date } },
        create: data,
        update: data,
      });

      return {
        close,
        reconciliationResult,
        reconciliationCreated,
        wasReclosed: existingClose != null,
      };
    });

    if (result.reconciliationCreated) {
      await this.reconciliationService.recordReconciliationEffects(
        userId,
        tenantId,
        branchId,
        result.reconciliationResult,
      );
    }

    await this.auditService.record({
      userId,
      action: result.wasReclosed ? 'UPDATE' : 'CREATE',
      entityType: 'daily_close',
      entityId: result.close.id,
      newValues: {
        date: dateStr,
        totalSales: summary.totalSales,
        countedCash: dto.countedCash,
        discrepancy: result.reconciliationResult.discrepancy,
      },
    });

    return this.format(result.close);
  }

  /** The close for a specific day (or today) — null if not yet closed. Lets
   * the app show "closed at 7:12pm by Jane" vs an open day. */
  async getClose(tenantId: string, branchId: string, date?: string) {
    const branch = await this.prisma.branch.findFirst({ where: { id: branchId, tenantId } });
    if (!branch) throw new NotFoundException('Branch not found');

    const normalized = this.normalizeDate(date, branch.timezone ?? 'Africa/Nairobi');
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
