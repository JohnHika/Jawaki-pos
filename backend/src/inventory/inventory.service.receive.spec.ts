import { InventoryService } from './inventory.service';
import { StockMovementType } from '@prisma/client';

describe('InventoryService receiveBatch', () => {
  it('derives movements and response from the locked stock quantity', async () => {
    const stockMovement = {
      findFirst: jest.fn(async () => null),
      create: jest.fn(async ({ data }) => ({ id: 'movement-1', ...data })),
    };
    const tx = {
      $executeRaw: jest.fn(async () => 1),
      $queryRaw: jest.fn(async () => [{ id: 'stock-1', quantity: 15 }]),
      stock: {
        findUnique: jest.fn(async () => ({ id: 'stock-1', quantity: 10 })),
        create: jest.fn(),
        update: jest.fn(async () => ({ id: 'stock-1', quantity: 20 })),
      },
      stockBatch: {
        findMany: jest.fn(async () => []),
        create: jest.fn(async ({ data }) => ({ id: 'batch-1', ...data })),
      },
      stockMovement,
    };
    const prisma = {
      branch: { findFirst: jest.fn(async () => ({ id: 'branch-1' })) },
      product: {
        findFirst: jest.fn(async () => ({
          id: 'product-1',
          sku: 'TEST-1',
          unit: 'piece',
          pricingTiers: [],
        })),
      },
      $transaction: jest.fn(async (callback) => callback(tx)),
    } as any;
    const redis = { invalidatePattern: jest.fn(async () => undefined) } as any;
    const service = new InventoryService(
      prisma,
      redis,
      {} as any,
      {} as any,
      {} as any,
    );

    const result = await service.receiveBatch('user-1', 'tenant-1', {
      branchId: 'branch-1',
      productId: 'product-1',
      batches: [{ quantity: 5, unit: 'piece' }],
    });

    expect(tx.$executeRaw).toHaveBeenCalledTimes(1);
    expect(tx.$queryRaw).toHaveBeenCalledTimes(1);
    expect(stockMovement.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ previousQty: 15, newQty: 20 }),
      }),
    );
    expect(result.currentQuantity).toBe(20);
    expect(result.receiptMetadata).toEqual({
      quantity: 5,
      unit: 'piece',
      unitsPerQuantity: 1,
      baseQuantity: 5,
    });
  });
});

describe('InventoryService stock writer locking', () => {
  it('uses the locked stock row for adjustment movement arithmetic', async () => {
    const calls: string[] = [];
    const stockUpdate = jest.fn(async ({ data }) => {
      calls.push('update');
      return { id: 'stock-1', quantity: data.quantity };
    });
    const movementCreate = jest.fn(async ({ data }) => data);
    const tx = {
      $executeRaw: jest.fn(async () => {
        calls.push('advisory');
        return 1;
      }),
      $queryRaw: jest.fn(async () => {
        calls.push('row-lock');
        return [{ id: 'stock-1', quantity: 15 }];
      }),
      stock: {
        findUnique: jest.fn(async () => ({ id: 'stock-1' })),
        create: jest.fn(),
        update: stockUpdate,
      },
      stockMovement: { create: movementCreate },
    };
    const prisma = {
      branch: { findFirst: jest.fn(async () => ({ id: 'branch-1' })) },
      product: { findMany: jest.fn(async () => [{ id: 'product-1' }]) },
      $transaction: jest.fn(async (callback) => callback(tx)),
    };
    const redis = { invalidatePattern: jest.fn(async () => undefined) };
    const service = new InventoryService(
      prisma as any,
      redis as any,
      {} as any,
      {} as any,
      {} as any,
    );

    await service.adjustStock('user-1', 'tenant-1', {
      branchId: 'branch-1',
      type: StockMovementType.ADJUSTMENT,
      items: [{ productId: 'product-1', quantity: 20 }],
    });

    expect(calls).toEqual(['advisory', 'row-lock', 'update']);
    expect(stockUpdate).toHaveBeenCalledWith({
      where: { id: 'stock-1' },
      data: { quantity: 20 },
    });
    expect(movementCreate).toHaveBeenCalledWith({
      data: expect.objectContaining({
        quantity: 5,
        previousQty: 15,
        newQty: 20,
      }),
    });
  });
});
