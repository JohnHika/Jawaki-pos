import { BadRequestException, Injectable } from '@nestjs/common';
import { ReceivablePaymentMethod } from '@prisma/client';
import { createHash } from 'crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { FinanceService } from '../finance/finance.service';

export interface DebtTarget {
  customerId?: string | null;
  debtorId?: string | null;
}

export interface PlannedAllocation {
  receivableId: string;
  branchId: string;
  amount: number;
}

const cents = (value: number) => Math.round(value * 100) / 100;

/**
 * Spreads a payment over a debtor's open debts, oldest first, and never more
 * than is owed on each. Pure so the maths is tested on its own.
 */
export function planAllocations(
  open: { id: string; branchId: string; outstanding: number }[],
  amount: number,
): { allocations: PlannedAllocation[]; applied: number; unallocated: number } {
  let remaining = cents(amount);
  const allocations: PlannedAllocation[] = [];
  for (const debt of open) {
    if (remaining <= 0) break;
    const take = cents(Math.min(remaining, debt.outstanding));
    if (take <= 0) continue;
    allocations.push({ receivableId: debt.id, branchId: debt.branchId, amount: take });
    remaining = cents(remaining - take);
  }
  const applied = cents(allocations.reduce((sum, a) => sum + a.amount, 0));
  return { allocations, applied, unallocated: cents(amount - applied) };
}

/**
 * Records a payment against a customer's or shop's open debts through the
 * existing finance code, so balances, cash ledgers and audit all behave as if
 * the owner had recorded it by hand.
 */
@Injectable()
export class DebtCollectionService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly finance: FinanceService,
  ) {}

  async openDebts(tenantId: string, target: DebtTarget) {
    if (target.customerId) {
      const rows = await this.prisma.retailReceivable.findMany({
        where: { tenantId, customerId: target.customerId, status: { in: ['OPEN', 'PARTIAL'] } },
        orderBy: { createdAt: 'asc' },
        select: { id: true, branchId: true, outstandingAmount: true },
      });
      return rows.map((r) => ({ id: r.id, branchId: r.branchId, outstanding: Number(r.outstandingAmount) }));
    }
    if (target.debtorId) {
      const rows = await this.prisma.peerReceivable.findMany({
        where: { tenantId, debtorId: target.debtorId, status: { in: ['OPEN', 'PARTIAL'] } },
        orderBy: { createdAt: 'asc' },
        select: { id: true, branchId: true, outstandingAmount: true },
      });
      return rows.map((r) => ({ id: r.id, branchId: r.branchId, outstanding: Number(r.outstandingAmount) }));
    }
    return [];
  }

  async outstandingFor(tenantId: string, target: DebtTarget): Promise<number> {
    const open = await this.openDebts(tenantId, target);
    return cents(open.reduce((sum, d) => sum + d.outstanding, 0));
  }

  async applyPayment(params: {
    tenantId: string;
    userId: string;
    target: DebtTarget;
    amount: number;
    method: ReceivablePaymentMethod;
    reference?: string | null;
    notes?: string | null;
    /** Makes a retry safe: the same key never records the payment twice. */
    idempotencyKey: string;
  }): Promise<{ applied: number; unallocated: number; debtsTouched: number }> {
    if (!params.target.customerId === !params.target.debtorId) {
      throw new BadRequestException('Name a customer or a shop to credit');
    }
    if (!(params.amount > 0)) throw new BadRequestException('Amount must be greater than zero');

    const open = await this.openDebts(params.tenantId, params.target);
    const plan = planAllocations(open, params.amount);
    if (plan.allocations.length === 0) {
      return { applied: 0, unallocated: cents(params.amount), debtsTouched: 0 };
    }

    // The finance code works one branch at a time, so group the plan by branch.
    const byBranch = new Map<string, PlannedAllocation[]>();
    for (const allocation of plan.allocations) {
      byBranch.set(allocation.branchId, [...(byBranch.get(allocation.branchId) ?? []), allocation]);
    }

    for (const [branchId, allocations] of byBranch) {
      const dto = {
        branchId,
        method: params.method,
        allocations: allocations.map((a) => ({ receivableId: a.receivableId, amount: a.amount })),
        reference: params.reference ?? undefined,
        notes: params.notes ?? undefined,
        // Hashed so the key stays short enough for the finance DTO and unique per branch.
        offlineId: `dc-${createHash('sha1').update(`${params.idempotencyKey}:${branchId}`).digest('hex').slice(0, 40)}`,
      };
      if (params.target.customerId) {
        await this.finance.recordRetailBulkPayment(params.userId, params.tenantId, dto);
      } else {
        await this.finance.recordPeerBulkPayment(params.userId, params.tenantId, dto);
      }
    }

    return { applied: plan.applied, unallocated: plan.unallocated, debtsTouched: plan.allocations.length };
  }
}
