import { Injectable, NotFoundException, Optional } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AccountabilityService } from '../accountability/accountability.service';
import { AuditService } from '../audit/audit.service';
import { getDayBoundsInTimezone, todayInTimezone } from '../common/operating-hours';
import { CashFlowService } from './cash-flow.service';
import { CashEntryType } from './dto/cash-flow.dto';
import { CreateReconciliationDto, ReconciliationQueryDto } from './dto/cash-reconciliation.dto';

@Injectable()
export class CashReconciliationService {
  constructor(
    private prisma: PrismaService,
    private auditService: AuditService,
    private cashFlowService: CashFlowService,
    @Optional() private accountability?: AccountabilityService,
  ) {}

  /**
   * Counts physical cash against what the system expects, and books the
   * difference as a MANUAL_ADJUSTMENT ledger entry so the discrepancy
   * doesn't just sit in a report — it's reflected going forward, which
   * matters most in RUNNING_BALANCE mode where an uncorrected shortfall
   * would otherwise silently overstate available cash forever.
   */
  async createReconciliation(userId: string, tenantId: string, branchId: string, dto: CreateReconciliationDto) {
    const result = await this.prisma.$transaction(async (tx) => {
      // Use the same branch lock as every cash-ledger append. This serializes
      // the expected-cash read against simultaneous sales, payouts, and other
      // reconciliations, so a stale read cannot double-book a discrepancy.
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${branchId}))`;

      const branch = await tx.branch.findFirst({
        where: { id: branchId, tenantId },
      });
      if (!branch) throw new NotFoundException('Branch not found');

      const { mode, expectedPhysicalCash } = await this.cashFlowService.getAvailableCash(branchId, tx);
      const expectedCash = expectedPhysicalCash;
      const discrepancy = dto.countedCash - expectedCash;

      const lastReconciliation = await tx.cashReconciliation.findFirst({
        where: { branchId },
        orderBy: { periodEnd: 'desc' },
      });
      const periodStart = lastReconciliation?.periodEnd ?? this.startOfToday(branch.timezone);

      const reconciliation = await tx.cashReconciliation.create({
        data: {
          branchId,
          expectedCash,
          countedCash: dto.countedCash,
          discrepancy,
          cashMode: mode,
          periodStart,
          notes: dto.notes,
          countedById: userId,
        },
      });

      // Keep the observation and any forward correction atomic. A failed
      // ledger append must not leave a reconciliation that was never applied.
      if (Math.abs(discrepancy) > 0.01) {
        await this.cashFlowService.recordEntry({
          branchId,
          type: CashEntryType.MANUAL_ADJUSTMENT,
          amount: discrepancy,
          referenceType: 'cash_reconciliation',
          referenceId: reconciliation.id,
          note:
            discrepancy > 0
              ? `Reconciliation overage of ${discrepancy.toFixed(2)}`
              : `Reconciliation shortfall of ${Math.abs(discrepancy).toFixed(2)}`,
          createdById: userId,
          tx,
        });
      }

      return { reconciliation, expectedCash, discrepancy };
    });
    const { reconciliation, expectedCash, discrepancy } = result;

    await this.auditService.record({
      userId,
      action: 'CREATE',
      entityType: 'cash_reconciliation',
      entityId: reconciliation.id,
      newValues: { expectedCash, countedCash: dto.countedCash, discrepancy },
    });

    await this.alertOnDiscrepancy(tenantId, branchId, userId, discrepancy, reconciliation.id);

    return this.formatReconciliation(reconciliation);
  }

  /** A till that does not balance is the most direct sign of missing money. */
  private async alertOnDiscrepancy(
    tenantId: string,
    branchId: string,
    userId: string,
    discrepancy: number,
    reconciliationId: string,
  ) {
    if (!this.accountability || Math.abs(discrepancy) < 1) return;
    try {
      const settings = await this.accountability.getSettings(tenantId);
      const actor = await this.accountability.actorName(userId);
      const short = discrepancy < 0;
      const amount = Math.abs(discrepancy);
      const threshold = settings.alerts.cashShortAmount;
      await this.accountability.raise({
        tenantId,
        branchId,
        type: short ? 'CASH_SHORT' : 'CASH_OVER',
        severity: short ? (threshold > 0 && amount >= threshold ? 'HIGH' : 'MEDIUM') : 'LOW',
        title: short ? 'Till is short' : 'Till is over',
        body: `${actor} counted the till ${short ? 'SHORT' : 'OVER'} by KES ${Math.round(amount).toLocaleString('en-KE')}`,
        actorUserId: userId,
        entityType: 'CashReconciliation',
        entityId: reconciliationId,
        data: { discrepancy },
      });
    } catch (error) {
      // Recording must never undo a reconciliation that has already committed.
    }
  }

  async getReconciliations(tenantId: string, branchId: string, query: ReconciliationQueryDto) {
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
    });
    if (!branch) throw new NotFoundException('Branch not found');

    const { page = 1, limit = 20 } = query;
    const skip = (page - 1) * limit;

    const [items, total] = await Promise.all([
      this.prisma.cashReconciliation.findMany({
        where: { branchId },
        include: { countedBy: { select: { firstName: true, lastName: true } } },
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
      }),
      this.prisma.cashReconciliation.count({ where: { branchId } }),
    ]);

    return {
      items: items.map((r) => this.formatReconciliation(r)),
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  private startOfToday(timezone?: string): Date {
    const branchTimezone = timezone ?? 'Africa/Nairobi';
    return getDayBoundsInTimezone(todayInTimezone(branchTimezone), branchTimezone).start;
  }

  private formatReconciliation(r: any) {
    return {
      id: r.id,
      branchId: r.branchId,
      expectedCash: Number(r.expectedCash),
      countedCash: Number(r.countedCash),
      discrepancy: Number(r.discrepancy),
      cashMode: r.cashMode,
      periodStart: r.periodStart,
      periodEnd: r.periodEnd,
      notes: r.notes,
      countedById: r.countedById,
      countedByName: r.countedBy ? `${r.countedBy.firstName} ${r.countedBy.lastName}` : undefined,
      createdAt: r.createdAt,
    };
  }
}
