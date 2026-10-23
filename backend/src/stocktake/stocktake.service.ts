import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { LegacyUserRole, Prisma, StockMovementType } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { lockStockForUpdate } from '../common/stock-lock';
import { AccountabilityService } from '../accountability/accountability.service';
import {
  breakdownByCounter,
  computeVariances,
  CountLine,
  summarizeCount,
} from './stocktake.math';
import { RecordCountsDto, StartStockCountDto, StockCountQueryDto } from './dto/stocktake.dto';

const APPROVE_PERMISSION = 'inventory.stocktake.approve';

@Injectable()
export class StocktakeService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly accountability: AccountabilityService,
  ) {}

  // -------------------------------------------------------------------- start

  async start(userId: string, tenantId: string, dto: StartStockCountDto) {
    const branch = await this.prisma.branch.findFirst({
      where: { id: dto.branchId, tenantId },
      select: { id: true, name: true },
    });
    if (!branch) throw new NotFoundException('Branch not found');

    const open = await this.prisma.stockCount.findFirst({
      where: { tenantId, branchId: dto.branchId, status: { in: ['IN_PROGRESS', 'SUBMITTED'] } },
      select: { id: true, status: true },
    });
    if (open) {
      throw new ConflictException(
        open.status === 'IN_PROGRESS'
          ? 'A count is already in progress at this branch. Finish or cancel it first.'
          : 'A submitted count is waiting for approval at this branch.',
      );
    }

    const where: Prisma.ProductWhereInput = { tenantId, isActive: true, trackInventory: true };
    if (dto.productIds?.length) where.id = { in: dto.productIds };
    if (dto.categoryId) where.categories = { some: { categoryId: dto.categoryId } };

    const products = await this.prisma.product.findMany({
      where,
      select: {
        id: true,
        name: true,
        sku: true,
        costPrice: true,
        basePrice: true,
        stock: { where: { branchId: dto.branchId }, select: { quantity: true } },
      },
      orderBy: { name: 'asc' },
    });
    if (products.length === 0) {
      throw new BadRequestException('No products to count with those filters');
    }

    const count = await this.prisma.stockCount.create({
      data: {
        tenantId,
        branchId: dto.branchId,
        title: dto.title?.trim() || null,
        blind: dto.blind ?? true,
        notes: dto.notes ?? null,
        createdById: userId,
        items: {
          create: products.map((p) => ({
            productId: p.id,
            productName: p.name,
            sku: p.sku,
            expectedQty: p.stock[0]?.quantity ?? 0,
            // Valued at cost so a loss is a money figure; falls back to the
            // selling price only when no cost was ever entered.
            unitCost: p.costPrice ?? p.basePrice,
          })),
        },
      },
    });

    await this.accountability.record({
      userId,
      action: 'STOCKTAKE_STARTED',
      entityType: 'StockCount',
      entityId: count.id,
      newValues: { branchId: dto.branchId, products: products.length, blind: count.blind },
    });

    return this.get(userId, tenantId, count.id);
  }

  // --------------------------------------------------------------------- read

  async list(tenantId: string, query: StockCountQueryDto) {
    const counts = await this.prisma.stockCount.findMany({
      where: {
        tenantId,
        ...(query.branchId ? { branchId: query.branchId } : {}),
        ...(query.status ? { status: query.status } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: 50,
      include: { _count: { select: { items: true } } },
    });

    const userIds = [
      ...new Set(counts.flatMap((c) => [c.createdById, c.approvedById]).filter(Boolean) as string[]),
    ];
    const names = await this.userNames(tenantId, userIds);

    return counts.map((c) => ({
      id: c.id,
      branchId: c.branchId,
      title: c.title,
      status: c.status,
      blind: c.blind,
      itemCount: c._count.items,
      totalVarianceValue: c.totalVarianceValue === null ? null : Number(c.totalVarianceValue),
      createdAt: c.createdAt,
      createdByName: names.get(c.createdById) ?? null,
      submittedAt: c.submittedAt,
      approvedAt: c.approvedAt,
      approvedByName: c.approvedById ? names.get(c.approvedById) ?? null : null,
    }));
  }

  /**
   * One count with its lines. While a blind count is still being counted the
   * system quantity is withheld from anyone who can't approve it, so the
   * counter reports what is on the shelf instead of what they expect to see.
   */
  async get(userId: string, tenantId: string, id: string) {
    const count = await this.prisma.stockCount.findFirst({
      where: { id, tenantId },
      include: { items: { orderBy: { productName: 'asc' } } },
    });
    if (!count) throw new NotFoundException('Stock count not found');

    const canSee = await this.accountability.userHas(userId, APPROVE_PERMISSION);
    const hideExpected = count.blind && count.status === 'IN_PROGRESS' && !canSee;

    const lines: CountLine[] = count.items.map((i) => ({
      productId: i.productId,
      productName: i.productName,
      expectedQty: Number(i.expectedQty),
      countedQty: i.countedQty === null ? null : Number(i.countedQty),
      unitCost: Number(i.unitCost),
      countedById: i.countedById,
    }));
    const summary = summarizeCount(lines);
    const names = await this.userNames(
      tenantId,
      [
        count.createdById,
        count.submittedById,
        count.approvedById,
        ...count.items.map((i) => i.countedById),
      ].filter(Boolean) as string[],
    );

    return {
      id: count.id,
      branchId: count.branchId,
      title: count.title,
      status: count.status,
      blind: count.blind,
      notes: count.notes,
      createdAt: count.createdAt,
      createdByName: names.get(count.createdById) ?? null,
      submittedAt: count.submittedAt,
      submittedByName: count.submittedById ? names.get(count.submittedById) ?? null : null,
      approvedAt: count.approvedAt,
      approvedByName: count.approvedById ? names.get(count.approvedById) ?? null : null,
      expectedHidden: hideExpected,
      summary: hideExpected
        ? {
            totalLines: summary.totalLines,
            countedLines: summary.countedLines,
            completionPercent: summary.completionPercent,
          }
        : summary,
      items: count.items.map((i) => {
        const expected = Number(i.expectedQty);
        const counted = i.countedQty === null ? null : Number(i.countedQty);
        const variance = counted === null ? null : Math.round((counted - expected) * 1000) / 1000;
        return {
          productId: i.productId,
          productName: i.productName,
          sku: i.sku,
          expectedQty: hideExpected ? null : expected,
          countedQty: counted,
          varianceQty: hideExpected ? null : variance,
          varianceValue:
            hideExpected || variance === null
              ? null
              : Math.round(variance * Number(i.unitCost) * 100) / 100,
          unitCost: hideExpected ? null : Number(i.unitCost),
          reason: i.reason,
          countedByName: i.countedById ? names.get(i.countedById) ?? null : null,
          countedAt: i.countedAt,
        };
      }),
    };
  }

  /** Who counted what, and whose counts keep coming up short. Approvers only. */
  async report(tenantId: string, id: string) {
    const count = await this.prisma.stockCount.findFirst({
      where: { id, tenantId },
      include: { items: true },
    });
    if (!count) throw new NotFoundException('Stock count not found');

    const lines: CountLine[] = count.items.map((i) => ({
      productId: i.productId,
      productName: i.productName,
      expectedQty: Number(i.expectedQty),
      countedQty: i.countedQty === null ? null : Number(i.countedQty),
      unitCost: Number(i.unitCost),
      countedById: i.countedById,
    }));
    const names = await this.userNames(
      tenantId,
      count.items.map((i) => i.countedById).filter(Boolean) as string[],
    );
    const variances = computeVariances(lines).filter((v) => v.varianceQty !== 0);

    return {
      id: count.id,
      status: count.status,
      summary: summarizeCount(lines),
      biggestLosses: variances
        .filter((v) => v.varianceValue < 0)
        .sort((a, b) => a.varianceValue - b.varianceValue)
        .slice(0, 20)
        .map((v) => ({
          productId: v.productId,
          productName: v.productName,
          expectedQty: v.expectedQty,
          countedQty: v.countedQty,
          varianceQty: v.varianceQty,
          varianceValue: v.varianceValue,
        })),
      byCounter: breakdownByCounter(lines).map((c) => ({
        ...c,
        countedByName: names.get(c.countedById) ?? 'Unknown',
      })),
    };
  }

  // ------------------------------------------------------------------- counting

  async recordCounts(userId: string, tenantId: string, id: string, dto: RecordCountsDto) {
    const count = await this.requireCount(tenantId, id);
    if (count.status !== 'IN_PROGRESS') {
      throw new ConflictException('This count is no longer open for counting');
    }

    const ids = dto.entries.map((e) => e.productId);
    const items = await this.prisma.stockCountItem.findMany({
      where: { countId: id, productId: { in: ids } },
      select: { productId: true },
    });
    const known = new Set(items.map((i) => i.productId));
    const unknown = ids.filter((p) => !known.has(p));
    if (unknown.length > 0) {
      throw new BadRequestException(`${unknown.length} product(s) are not part of this count`);
    }

    const now = new Date();
    await this.prisma.$transaction(
      dto.entries.map((e) =>
        this.prisma.stockCountItem.update({
          where: { countId_productId: { countId: id, productId: e.productId } },
          data: {
            countedQty: e.countedQty,
            reason: e.reason?.trim() || null,
            countedById: userId,
            countedAt: now,
          },
        }),
      ),
    );
    return { recorded: dto.entries.length };
  }

  async submit(userId: string, tenantId: string, id: string) {
    const count = await this.prisma.stockCount.findFirst({
      where: { id, tenantId },
      include: { items: true },
    });
    if (!count) throw new NotFoundException('Stock count not found');
    if (count.status !== 'IN_PROGRESS') {
      throw new ConflictException('Only a count in progress can be submitted');
    }

    const lines = this.toLines(count.items);
    const summary = summarizeCount(lines);
    if (summary.countedLines === 0) {
      throw new BadRequestException('Count at least one product before submitting');
    }

    await this.prisma.stockCount.update({
      where: { id },
      data: {
        status: 'SUBMITTED',
        submittedById: userId,
        submittedAt: new Date(),
        totalVarianceValue: summary.netValue,
      },
    });

    await this.accountability.record({
      userId,
      action: 'STOCKTAKE_SUBMITTED',
      entityType: 'StockCount',
      entityId: id,
      newValues: { ...summary },
    });

    // The owner hears about a loss when the count is handed in, not weeks
    // later when somebody finally gets round to approving it.
    const settings = await this.accountability.getSettings(tenantId);
    if (summary.lossValue > 0) {
      const actor = await this.accountability.actorName(userId);
      const threshold = settings.alerts.stocktakeVarianceValue;
      await this.accountability.raise({
        tenantId,
        branchId: count.branchId,
        type: 'STOCKTAKE_VARIANCE',
        severity: threshold > 0 && summary.lossValue >= threshold ? 'HIGH' : 'MEDIUM',
        title: 'Stocktake shows missing stock',
        body: `${actor} counted ${summary.countedLines} items: ${summary.shortLines} short (KES ${Math.round(summary.lossValue).toLocaleString('en-KE')} at cost), ${summary.overLines} over.`,
        actorUserId: userId,
        entityType: 'StockCount',
        entityId: id,
        data: { ...summary },
      });
    }

    return this.get(userId, tenantId, id);
  }

  // ------------------------------------------------------------------- approval

  /**
   * Turns a submitted count into real stock changes. Each product moves by
   * (counted - expected-at-start), not to the counted figure, so anything
   * sold or received while the count was running is preserved.
   */
  async approve(userId: string, tenantId: string, id: string, notes?: string) {
    const count = await this.prisma.stockCount.findFirst({
      where: { id, tenantId },
      include: { items: true },
    });
    if (!count) throw new NotFoundException('Stock count not found');
    if (count.status !== 'SUBMITTED') {
      throw new ConflictException('Only a submitted count can be approved');
    }

    const settings = await this.accountability.getSettings(tenantId);
    if (settings.stocktake.separateApprover && count.submittedById === userId) {
      const approver = await this.prisma.user.findUnique({
        where: { id: userId },
        select: { role: true },
      });
      // The owner may approve their own count (a one-person shop has no one
      // else); everyone else needs a second pair of eyes.
      if (approver?.role !== LegacyUserRole.ADMIN) {
        throw new ForbiddenException(
          'The person who submitted a count cannot also approve it. Ask a manager or the owner.',
        );
      }
    }

    const lines = this.toLines(count.items);
    const summary = summarizeCount(lines);
    const toApply = count.items.filter(
      (i) => i.countedQty !== null && !i.countedQty.equals(i.expectedQty),
    );
    const stamp = new Date().toISOString().slice(2, 10).replace(/-/g, '');

    await this.prisma.$transaction(
      async (tx) => {
        // Locked in a stable order so two approvals can't deadlock each other.
        for (const item of [...toApply].sort((a, b) => a.productId.localeCompare(b.productId))) {
          const delta = Number(item.countedQty) - Number(item.expectedQty);
          const stock = await lockStockForUpdate(tx, count.branchId, item.productId, true);
          if (!stock) throw new ConflictException('Could not lock stock for the count');

          const previousQty = Number(stock.quantity);
          // Never below zero: if the shelf was already sold down further than
          // the count assumed, clamp instead of failing the whole approval.
          const newQty = Math.max(previousQty + delta, 0);
          const applied = newQty - previousQty;
          if (applied === 0) continue;

          await tx.stock.update({ where: { id: stock.id }, data: { quantity: newQty } });
          await this.applyToBatches(tx, stock.id, applied, Number(item.unitCost), `CNT-${stamp}-${id.slice(0, 4)}`);

          await tx.stockMovement.create({
            data: {
              branchId: count.branchId,
              productId: item.productId,
              type: applied < 0 ? StockMovementType.ADJUSTMENT_OUT : StockMovementType.ADJUSTMENT_IN,
              quantity: applied,
              previousQty,
              newQty,
              reference: `stocktake:${id}`,
              notes: `Stocktake${count.title ? ` "${count.title}"` : ''}${item.reason ? `: ${item.reason}` : ''}`,
              createdById: userId,
            },
          });
        }

        await tx.stockCount.update({
          where: { id },
          data: {
            status: 'APPROVED',
            approvedById: userId,
            approvedAt: new Date(),
            notes: notes ? `${count.notes ? count.notes + '\n' : ''}${notes}` : count.notes,
          },
        });
      },
      { timeout: 60_000, maxWait: 10_000 },
    );

    await this.redis.invalidatePattern(`products:${tenantId}:*`);
    await this.accountability.record({
      userId,
      action: 'STOCKTAKE_APPROVED',
      entityType: 'StockCount',
      entityId: id,
      newValues: { adjusted: toApply.length, ...summary },
    });

    return this.get(userId, tenantId, id);
  }

  async cancel(userId: string, tenantId: string, id: string) {
    const count = await this.requireCount(tenantId, id);
    if (count.status !== 'IN_PROGRESS' && count.status !== 'SUBMITTED') {
      throw new ConflictException('This count is already finished');
    }
    await this.prisma.stockCount.update({ where: { id }, data: { status: 'CANCELLED' } });
    await this.accountability.record({
      userId,
      action: 'STOCKTAKE_CANCELLED',
      entityType: 'StockCount',
      entityId: id,
    });
    return { id, status: 'CANCELLED' };
  }

  // -------------------------------------------------------------------- helpers

  /**
   * Keeps stock_batches adding up to the stock figure. A shortage comes off
   * the earliest-expiring batches first (matching how sales allocate); extra
   * stock found becomes its own batch so FEFO selling can find it.
   */
  private async applyToBatches(
    tx: Prisma.TransactionClient,
    stockId: string,
    change: number,
    unitCost: number,
    batchNumber: string,
  ) {
    const hasBatches = (await tx.stockBatch.count({ where: { stockId } })) > 0;
    if (!hasBatches) return;

    if (change < 0) {
      let remaining = -change;
      const batches = await tx.stockBatch.findMany({
        where: { stockId, isBlocked: false, quantity: { gt: 0 } },
        orderBy: [{ expiryDate: 'asc' }, { id: 'asc' }],
      });
      for (const batch of batches) {
        if (remaining <= 0) break;
        const take = Math.min(Number(batch.quantity), remaining);
        await tx.stockBatch.update({ where: { id: batch.id }, data: { quantity: { decrement: take } } });
        remaining -= take;
      }
      return;
    }

    await tx.stockBatch.upsert({
      where: { stockId_batchNumber: { stockId, batchNumber } },
      create: { stockId, batchNumber, quantity: change, costPrice: unitCost, notes: 'Found in stocktake' },
      update: { quantity: { increment: change } },
    });
  }

  private toLines(
    items: Array<{
      productId: string;
      productName: string;
      expectedQty: Prisma.Decimal;
      countedQty: Prisma.Decimal | null;
      unitCost: Prisma.Decimal;
      countedById: string | null;
    }>,
  ): CountLine[] {
    return items.map((i) => ({
      productId: i.productId,
      productName: i.productName,
      expectedQty: Number(i.expectedQty),
      countedQty: i.countedQty === null ? null : Number(i.countedQty),
      unitCost: Number(i.unitCost),
      countedById: i.countedById,
    }));
  }

  private async requireCount(tenantId: string, id: string) {
    const count = await this.prisma.stockCount.findFirst({ where: { id, tenantId } });
    if (!count) throw new NotFoundException('Stock count not found');
    return count;
  }

  private async userNames(tenantId: string, ids: string[]) {
    const unique = [...new Set(ids)];
    if (unique.length === 0) return new Map<string, string>();
    const users = await this.prisma.user.findMany({
      where: { id: { in: unique }, tenantId },
      select: { id: true, firstName: true, lastName: true },
    });
    return new Map(
      users.map((u) => [u.id, [u.firstName, u.lastName].filter(Boolean).join(' ').trim() || 'Staff']),
    );
  }
}
