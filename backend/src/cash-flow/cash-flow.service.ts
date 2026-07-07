import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { CashFlowMode, CashEntryType } from './dto/cash-flow.dto';
import { CashLedgerQueryDto } from './dto/cash-flow.dto';

interface RecordLedgerEntryParams {
  branchId: string;
  type: CashEntryType;
  amount: number; // positive = inflow, negative = outflow
  referenceType?: string;
  referenceId?: string;
  note?: string;
  createdById?: string;
}

@Injectable()
export class CashFlowService {
  constructor(private prisma: PrismaService) {}

  /**
   * Appends one cash movement row. The running balance is only meaningful
   * for RUNNING_BALANCE mode, but we snapshot it on every write (cheap,
   * always consistent) so switching a branch into that mode later doesn't
   * require a backfill.
   */
  async recordEntry(params: RecordLedgerEntryParams) {
    const last = await this.prisma.cashLedgerEntry.findFirst({
      where: { branchId: params.branchId },
      orderBy: { createdAt: 'desc' },
    });
    const previousBalance = last ? Number(last.balanceAfter) : 0;
    const balanceAfter = previousBalance + params.amount;

    return this.prisma.cashLedgerEntry.create({
      data: {
        branchId: params.branchId,
        type: params.type,
        amount: params.amount,
        balanceAfter,
        referenceType: params.referenceType,
        referenceId: params.referenceId,
        note: params.note,
        createdById: params.createdById,
      },
    });
  }

  async getSettings(branchId: string) {
    const branch = await this.prisma.branch.findUnique({ where: { id: branchId } });
    if (!branch) throw new NotFoundException('Branch not found');

    const settings = await this.prisma.branchCashSettings.findUnique({ where: { branchId } });
    return { branchId, mode: settings?.mode ?? CashFlowMode.CASH_ONLY };
  }

  async updateSettings(branchId: string, mode: CashFlowMode) {
    const branch = await this.prisma.branch.findUnique({ where: { id: branchId } });
    if (!branch) throw new NotFoundException('Branch not found');

    const settings = await this.prisma.branchCashSettings.upsert({
      where: { branchId },
      create: { branchId, mode },
      update: { mode },
    });

    return { branchId, mode: settings.mode };
  }

  /**
   * "Available cash to restock" — the same underlying ledger data read
   * three different ways depending on the branch's chosen mode:
   *
   * - CASH_ONLY: today's cash sales minus today's cash payouts. Resets
   *   every day; matches "what's physically in the till right now."
   * - ALL_REVENUE: today's total revenue (any payment method) minus
   *   today's payouts. A profit-flavored view rather than a physical-cash
   *   one — money isn't literally in hand, but the owner is comfortable
   *   spending against it (e.g. M-Pesa float they can draw from).
   * - RUNNING_BALANCE: the ledger's latest balanceAfter, carried forward
   *   across days rather than resetting at midnight.
   */
  async getAvailableCash(branchId: string) {
    const { mode } = await this.getSettings(branchId);

    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);
    const endOfDay = new Date(startOfDay);
    endOfDay.setDate(endOfDay.getDate() + 1);

    const restockOut = await this.sumToday(branchId, CashEntryType.RESTOCK_OUT, startOfDay, endOfDay);
    const expenseOut = await this.sumToday(branchId, CashEntryType.EXPENSE_OUT, startOfDay, endOfDay);
    // Manual adjustments can be positive (top-up) or negative (removal) — only
    // the negative side counts as a payout; positive ones behave like an
    // OPENING_BALANCE-style inflow and are excluded from todaysCashOut.
    const manualAdjustment = await this.sumNegativeToday(
      branchId,
      CashEntryType.MANUAL_ADJUSTMENT,
      startOfDay,
      endOfDay,
    );
    const todaysCashOut = restockOut + expenseOut + manualAdjustment;

    if (mode === CashFlowMode.RUNNING_BALANCE) {
      const last = await this.prisma.cashLedgerEntry.findFirst({
        where: { branchId },
        orderBy: { createdAt: 'desc' },
      });
      const runningBalance = last ? Number(last.balanceAfter) : 0;
      const salesCashIn = await this.sumToday(branchId, CashEntryType.SALE_CASH_IN, startOfDay, endOfDay);

      return {
        mode,
        availableCash: runningBalance,
        todaysCashIn: salesCashIn,
        todaysCashOut,
        breakdown: {
          runningBalance,
          restockOut,
          expenseOut,
          manualAdjustment,
        },
      };
    }

    if (mode === CashFlowMode.ALL_REVENUE) {
      const revenue = await this.prisma.sale.aggregate({
        where: {
          branchId,
          status: 'COMPLETED',
          createdAt: { gte: startOfDay, lt: endOfDay },
        },
        _sum: { totalAmount: true },
      });
      const allRevenue = Number(revenue._sum.totalAmount) || 0;

      return {
        mode,
        availableCash: allRevenue - todaysCashOut,
        todaysCashIn: allRevenue,
        todaysCashOut,
        breakdown: { allRevenue, restockOut, expenseOut, manualAdjustment },
      };
    }

    // CASH_ONLY (default)
    const salesCashIn = await this.sumToday(branchId, CashEntryType.SALE_CASH_IN, startOfDay, endOfDay);
    return {
      mode,
      availableCash: salesCashIn - todaysCashOut,
      todaysCashIn: salesCashIn,
      todaysCashOut,
      breakdown: { salesCashIn, restockOut, expenseOut, manualAdjustment },
    };
  }

  async getLedger(branchId: string, query: CashLedgerQueryDto) {
    const { page = 1, limit = 50 } = query;
    const skip = (page - 1) * limit;

    const [entries, total] = await Promise.all([
      this.prisma.cashLedgerEntry.findMany({
        where: { branchId },
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
      }),
      this.prisma.cashLedgerEntry.count({ where: { branchId } }),
    ]);

    return {
      items: entries.map((e) => ({
        id: e.id,
        type: e.type,
        amount: Number(e.amount),
        balanceAfter: Number(e.balanceAfter),
        referenceType: e.referenceType,
        referenceId: e.referenceId,
        note: e.note,
        createdAt: e.createdAt,
      })),
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  private async sumToday(branchId: string, type: CashEntryType, start: Date, end: Date): Promise<number> {
    const result = await this.prisma.cashLedgerEntry.aggregate({
      where: { branchId, type, createdAt: { gte: start, lt: end } },
      _sum: { amount: true },
    });
    return Math.abs(Number(result._sum.amount) || 0);
  }

  private async sumNegativeToday(
    branchId: string,
    type: CashEntryType,
    start: Date,
    end: Date,
  ): Promise<number> {
    const result = await this.prisma.cashLedgerEntry.aggregate({
      where: { branchId, type, createdAt: { gte: start, lt: end }, amount: { lt: 0 } },
      _sum: { amount: true },
    });
    return Math.abs(Number(result._sum.amount) || 0);
  }
}
