import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CashFlowService } from './cash-flow.service';
import { CashEntryType } from './dto/cash-flow.dto';
import { CreateReconciliationDto, ReconciliationQueryDto } from './dto/cash-reconciliation.dto';

@Injectable()
export class CashReconciliationService {
  constructor(
    private prisma: PrismaService,
    private auditService: AuditService,
    private cashFlowService: CashFlowService,
  ) {}

  /**
   * Counts physical cash against what the system expects, and books the
   * difference as a MANUAL_ADJUSTMENT ledger entry so the discrepancy
   * doesn't just sit in a report — it's reflected going forward, which
   * matters most in RUNNING_BALANCE mode where an uncorrected shortfall
   * would otherwise silently overstate available cash forever.
   */
  async createReconciliation(userId: string, branchId: string, dto: CreateReconciliationDto) {
    const branch = await this.prisma.branch.findUnique({ where: { id: branchId } });
    if (!branch) throw new NotFoundException('Branch not found');

    const { mode, availableCash } = await this.cashFlowService.getAvailableCash(branchId);
    const expectedCash = availableCash;
    const discrepancy = dto.countedCash - expectedCash;

    const lastReconciliation = await this.prisma.cashReconciliation.findFirst({
      where: { branchId },
      orderBy: { periodEnd: 'desc' },
    });
    const periodStart = lastReconciliation?.periodEnd ?? this.startOfToday();

    const reconciliation = await this.prisma.cashReconciliation.create({
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

    // A discrepancy is corrected going forward via a ledger adjustment —
    // not retroactively rewriting past entries, which would misrepresent
    // what actually happened at the time.
    if (Math.abs(discrepancy) > 0.01) {
      await this.cashFlowService.recordEntry({
        branchId,
        type: CashEntryType.MANUAL_ADJUSTMENT,
        amount: discrepancy,
        referenceType: 'cash_reconciliation',
        referenceId: reconciliation.id,
        note: discrepancy > 0
          ? `Reconciliation overage of ${discrepancy.toFixed(2)}`
          : `Reconciliation shortfall of ${Math.abs(discrepancy).toFixed(2)}`,
        createdById: userId,
      });
    }

    await this.auditService.record({
      userId,
      action: 'CREATE',
      entityType: 'cash_reconciliation',
      entityId: reconciliation.id,
      newValues: { expectedCash, countedCash: dto.countedCash, discrepancy },
    });

    return this.formatReconciliation(reconciliation);
  }

  async getReconciliations(branchId: string, query: ReconciliationQueryDto) {
    const branch = await this.prisma.branch.findUnique({ where: { id: branchId } });
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

  private startOfToday(): Date {
    const now = new Date();
    now.setHours(0, 0, 0, 0);
    return now;
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
      countedByName: r.countedBy
        ? `${r.countedBy.firstName} ${r.countedBy.lastName}`
        : undefined,
      createdAt: r.createdAt,
    };
  }
}
