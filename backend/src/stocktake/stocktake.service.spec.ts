import { ConflictException, ForbiddenException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { StocktakeService } from './stocktake.service';

jest.mock('../common/stock-lock', () => ({
  lockStockForUpdate: jest.fn(),
}));
import { lockStockForUpdate } from '../common/stock-lock';

const D = (n: number) => new Prisma.Decimal(n);

function item(over: Record<string, unknown> = {}) {
  return {
    id: 'i',
    countId: 'c1',
    productId: 'p1',
    productName: 'Sufuria',
    sku: 'S1',
    expectedQty: D(10),
    countedQty: D(7),
    unitCost: D(100),
    reason: null,
    countedById: 'counter',
    countedAt: new Date(),
    ...over,
  };
}

function build(count: Record<string, unknown> | null, opts: { approverRole?: string; separate?: boolean } = {}) {
  const tx: any = {
    stock: { update: jest.fn() },
    stockMovement: { create: jest.fn() },
    stockBatch: { count: jest.fn().mockResolvedValue(0), findMany: jest.fn(), update: jest.fn(), upsert: jest.fn() },
    stockCount: { update: jest.fn() },
  };
  const prisma: any = {
    stockCount: {
      findFirst: jest.fn().mockResolvedValue(count),
      update: jest.fn(),
    },
    user: { findUnique: jest.fn().mockResolvedValue({ role: opts.approverRole ?? 'MANAGER' }) },
    $transaction: jest.fn(async (fn: any) => fn(tx)),
  };
  const redis: any = { invalidatePattern: jest.fn() };
  const accountability: any = {
    record: jest.fn(),
    raise: jest.fn(),
    actorName: jest.fn().mockResolvedValue('Faith'),
    userHas: jest.fn().mockResolvedValue(true),
    getSettings: jest.fn().mockResolvedValue({
      stocktake: { separateApprover: opts.separate ?? true },
      alerts: { stocktakeVarianceValue: 2000 },
    }),
  };
  // get() is called at the end of approve/submit; stub it so these tests stay about the write path.
  const service = new StocktakeService(prisma, redis, accountability);
  jest.spyOn(service, 'get').mockResolvedValue({ id: 'c1' } as any);
  return { service, prisma, tx, accountability };
}

describe('StocktakeService.approve', () => {
  beforeEach(() => {
    (lockStockForUpdate as jest.Mock).mockReset();
  });

  it('adjusts by counted minus expected, so sales made during the count are kept', async () => {
    // Snapshot said 10, the shelf has 7 (-3). Meanwhile 2 were sold, so the
    // live quantity is now 8. The result must be 5, not 7.
    (lockStockForUpdate as jest.Mock).mockResolvedValue({ id: 'stock1', quantity: 8 });
    const { service, tx } = build({
      id: 'c1', tenantId: 't1', branchId: 'b1', status: 'SUBMITTED', title: null, notes: null,
      submittedById: 'counter', items: [item()],
    });

    await service.approve('manager', 't1', 'c1');

    expect(tx.stock.update).toHaveBeenCalledWith({ where: { id: 'stock1' }, data: { quantity: 5 } });
    const movement = tx.stockMovement.create.mock.calls[0][0].data;
    expect(movement.type).toBe('ADJUSTMENT_OUT');
    expect(movement.quantity).toBe(-3);
    expect(movement.previousQty).toBe(8);
    expect(movement.newQty).toBe(5);
    expect(movement.reference).toBe('stocktake:c1');
    expect(tx.stockCount.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ status: 'APPROVED', approvedById: 'manager' }) }),
    );
  });

  it('never drives stock below zero', async () => {
    (lockStockForUpdate as jest.Mock).mockResolvedValue({ id: 'stock1', quantity: 1 });
    const { service, tx } = build({
      id: 'c1', tenantId: 't1', branchId: 'b1', status: 'SUBMITTED', title: null, notes: null,
      submittedById: 'counter', items: [item({ expectedQty: D(10), countedQty: D(2) })],
    });
    await service.approve('manager', 't1', 'c1');
    expect(tx.stock.update).toHaveBeenCalledWith({ where: { id: 'stock1' }, data: { quantity: 0 } });
    expect(tx.stockMovement.create.mock.calls[0][0].data.quantity).toBe(-1);
  });

  it('records stock found as an increase, and leaves matching and uncounted lines alone', async () => {
    (lockStockForUpdate as jest.Mock).mockResolvedValue({ id: 'stock1', quantity: 10 });
    const { service, tx } = build({
      id: 'c1', tenantId: 't1', branchId: 'b1', status: 'SUBMITTED', title: null, notes: null,
      submittedById: 'counter',
      items: [
        item({ productId: 'a', expectedQty: D(10), countedQty: D(12) }),
        item({ productId: 'b', expectedQty: D(5), countedQty: D(5) }),
        item({ productId: 'c', expectedQty: D(5), countedQty: null }),
      ],
    });
    await service.approve('manager', 't1', 'c1');
    expect(tx.stockMovement.create).toHaveBeenCalledTimes(1);
    expect(tx.stockMovement.create.mock.calls[0][0].data.type).toBe('ADJUSTMENT_IN');
    expect(tx.stock.update).toHaveBeenCalledWith({ where: { id: 'stock1' }, data: { quantity: 12 } });
  });

  it('refuses to approve a count that was never submitted', async () => {
    const { service } = build({
      id: 'c1', tenantId: 't1', branchId: 'b1', status: 'IN_PROGRESS', items: [],
    });
    await expect(service.approve('manager', 't1', 'c1')).rejects.toBeInstanceOf(ConflictException);
  });

  it('will not let the person who submitted a count also approve it', async () => {
    const { service, tx } = build(
      { id: 'c1', tenantId: 't1', branchId: 'b1', status: 'SUBMITTED', submittedById: 'same', items: [item()] },
      { approverRole: 'MANAGER' },
    );
    await expect(service.approve('same', 't1', 'c1')).rejects.toBeInstanceOf(ForbiddenException);
    expect(tx.stock.update).not.toHaveBeenCalled();
  });

  it('lets the owner approve their own count — a one-person shop has no one else', async () => {
    (lockStockForUpdate as jest.Mock).mockResolvedValue({ id: 'stock1', quantity: 10 });
    const { service } = build(
      { id: 'c1', tenantId: 't1', branchId: 'b1', status: 'SUBMITTED', submittedById: 'owner', items: [item()] },
      { approverRole: 'ADMIN' },
    );
    await expect(service.approve('owner', 't1', 'c1')).resolves.toBeDefined();
  });

  it('shrinks the earliest-expiring batches first when stock goes missing', async () => {
    (lockStockForUpdate as jest.Mock).mockResolvedValue({ id: 'stock1', quantity: 10 });
    const { service, tx } = build({
      id: 'c1', tenantId: 't1', branchId: 'b1', status: 'SUBMITTED', title: null, notes: null,
      submittedById: 'counter', items: [item({ expectedQty: D(10), countedQty: D(6) })],
    });
    tx.stockBatch.count.mockResolvedValue(2);
    tx.stockBatch.findMany.mockResolvedValue([
      { id: 'early', quantity: D(3) },
      { id: 'late', quantity: D(7) },
    ]);

    await service.approve('manager', 't1', 'c1');

    // 4 missing: 3 from the early batch, 1 from the next.
    expect(tx.stockBatch.update).toHaveBeenNthCalledWith(1, {
      where: { id: 'early' },
      data: { quantity: { decrement: 3 } },
    });
    expect(tx.stockBatch.update).toHaveBeenNthCalledWith(2, {
      where: { id: 'late' },
      data: { quantity: { decrement: 1 } },
    });
  });

  it('puts found stock into its own batch so FEFO selling can reach it', async () => {
    (lockStockForUpdate as jest.Mock).mockResolvedValue({ id: 'stock1', quantity: 10 });
    const { service, tx } = build({
      id: 'c1', tenantId: 't1', branchId: 'b1', status: 'SUBMITTED', title: null, notes: null,
      submittedById: 'counter', items: [item({ expectedQty: D(10), countedQty: D(13) })],
    });
    tx.stockBatch.count.mockResolvedValue(1);

    await service.approve('manager', 't1', 'c1');

    const upsert = tx.stockBatch.upsert.mock.calls[0][0];
    expect(upsert.create.quantity).toBe(3);
    expect(upsert.create.batchNumber).toMatch(/^CNT-/);
  });
});

describe('StocktakeService.submit', () => {
  it('alerts the owner when the count shows missing stock', async () => {
    const { service, prisma, accountability } = build({
      id: 'c1', tenantId: 't1', branchId: 'b1', status: 'IN_PROGRESS',
      items: [item({ expectedQty: D(100), countedQty: D(70), unitCost: D(100) })], // -3000 at cost
    });
    prisma.stockCount.update.mockResolvedValue({});

    await service.submit('counter', 't1', 'c1');

    expect(accountability.raise).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'STOCKTAKE_VARIANCE', severity: 'HIGH' }),
    );
  });

  it('refuses to submit a count with nothing counted', async () => {
    const { service } = build({
      id: 'c1', tenantId: 't1', branchId: 'b1', status: 'IN_PROGRESS',
      items: [item({ countedQty: null })],
    });
    await expect(service.submit('counter', 't1', 'c1')).rejects.toThrow(/at least one/i);
  });
});
