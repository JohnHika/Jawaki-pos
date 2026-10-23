import { applyPurchaseCost, weightedAverageCost } from './product-cost';
import { InventoryService } from '../inventory/inventory.service';

describe('weightedAverageCost', () => {
  it('blends the stock on hand with the new purchase', () => {
    expect(weightedAverageCost(50, 100, 50, 140)).toBe(120);
  });

  it('uses the new cost when nothing is on hand or no cost is known', () => {
    expect(weightedAverageCost(0, 100, 20, 140)).toBe(140);
    expect(weightedAverageCost(10, null, 20, 140)).toBe(140);
  });

  it('keeps the current cost when nothing is received', () => {
    expect(weightedAverageCost(10, 100, 0, 140)).toBe(100);
  });
});

describe('applyPurchaseCost', () => {
  const tx = (cost: number | null) =>
    ({
      product: {
        findUnique: jest.fn().mockResolvedValue({ costPrice: cost }),
        update: jest.fn(),
      },
    }) as any;

  it('sets the cost on a product that never had one', async () => {
    const t = tx(null);
    await applyPurchaseCost(t, 'p1', 0, 10, 80);
    expect(t.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { costPrice: 80 } });
  });

  it('averages the new purchase into the existing cost', async () => {
    const t = tx(100);
    await applyPurchaseCost(t, 'p1', 10, 10, 120);
    expect(t.product.update).toHaveBeenCalledWith({ where: { id: 'p1' }, data: { costPrice: 110 } });
  });

  it('leaves the cost alone when the price did not change', async () => {
    const t = tx(100);
    await applyPurchaseCost(t, 'p1', 10, 10, 100);
    expect(t.product.update).not.toHaveBeenCalled();
  });

  it('ignores a missing, zero or negative cost so a free sample cannot drag the average down', async () => {
    for (const bad of [null, undefined, 0, -5]) {
      const t = tx(100);
      await applyPurchaseCost(t, 'p1', 10, 10, bad as any);
      expect(t.product.findUnique).not.toHaveBeenCalled();
      expect(t.product.update).not.toHaveBeenCalled();
    }
  });

  it('ignores a receipt of nothing', async () => {
    const t = tx(100);
    await applyPurchaseCost(t, 'p1', 10, 0, 50);
    expect(t.product.update).not.toHaveBeenCalled();
  });
});

describe('receiveBatch keeps the product cost current', () => {
  it('averages a costed batch into Product.costPrice', async () => {
    const productUpdate = jest.fn();
    const tx: any = {
      $executeRaw: jest.fn(async () => 1),
      $queryRaw: jest.fn(async () => [{ id: 'stock-1', quantity: 10 }]),
      stock: {
        findUnique: jest.fn(async () => ({ id: 'stock-1', quantity: 10 })),
        create: jest.fn(),
        update: jest.fn(async () => ({ id: 'stock-1' })),
      },
      stockBatch: {
        findMany: jest.fn(async () => []),
        create: jest.fn(async ({ data }: any) => ({ id: 'batch-1', ...data })),
      },
      stockMovement: {
        findFirst: jest.fn(async () => null),
        create: jest.fn(async ({ data }: any) => ({ id: 'm1', ...data })),
      },
      product: {
        // 10 on hand @ 100
        findUnique: jest.fn(async () => ({ costPrice: 100 })),
        update: productUpdate,
      },
    };
    const prisma: any = {
      branch: { findFirst: jest.fn(async () => ({ id: 'branch-1' })) },
      product: {
        findFirst: jest.fn(async () => ({ id: 'product-1', sku: 'T-1', unit: 'piece', pricingTiers: [] })),
      },
      $transaction: jest.fn(async (cb: any) => cb(tx)),
    };
    const service = new InventoryService(prisma, { invalidatePattern: jest.fn() } as any, {} as any, {} as any, {} as any);

    await service.receiveBatch('u1', 't1', {
      branchId: 'branch-1',
      productId: 'product-1',
      batches: [{ quantity: 10, unit: 'piece', costPrice: 140 }],
    } as any);

    // (10 x 100 + 10 x 140) / 20 = 120
    expect(productUpdate).toHaveBeenCalledWith({ where: { id: 'product-1' }, data: { costPrice: 120 } });
  });
});
