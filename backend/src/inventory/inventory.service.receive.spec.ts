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

describe('InventoryService stock transfers', () => {
  const transfer = {
    id: 'transfer-1',
    fromBranchId: 'branch-source',
    toBranchId: 'branch-destination',
    status: 'in_transit',
    notes: null,
    createdAt: new Date('2026-10-25T10:00:00.000Z'),
    createdById: 'user-1',
    items: [
      {
        id: 'transfer-item-1',
        productId: 'product-1',
        requestedQty: 5,
        sentQty: 5,
        receivedQty: null,
      },
    ],
  };

  function createTransferService() {
    const prisma = {
      branch: {
        findMany: jest.fn(async () => [
          { id: 'branch-source', name: 'Source' },
          { id: 'branch-destination', name: 'Destination' },
        ]),
      },
      product: { findMany: jest.fn() },
      stockTransfer: {
        findUnique: jest.fn(async () => transfer),
        findMany: jest.fn(),
        count: jest.fn(),
      },
      $transaction: jest.fn(),
    } as any;
    const service = new InventoryService(
      prisma,
      { invalidatePattern: jest.fn() } as any,
      {} as any,
      {} as any,
      {} as any,
    );
    return { prisma, service };
  }

  it('rejects duplicate received products before opening a transaction', async () => {
    const { prisma, service } = createTransferService();
    await expect(
      service.receiveTransfer('transfer-1', 'user-1', 'tenant-1', {
        receivedItems: [
          { productId: 'product-1', quantity: 2 },
          { productId: 'product-1', quantity: 2 },
        ],
      }),
    ).rejects.toThrow('Each transferred product must be listed once');
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects quantities above what was dispatched', async () => {
    const { prisma, service } = createTransferService();
    await expect(
      service.receiveTransfer('transfer-1', 'user-1', 'tenant-1', {
        receivedItems: [{ productId: 'product-1', quantity: 6 }],
      }),
    ).rejects.toThrow('Received quantity cannot exceed the amount dispatched');
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('requires a note when a received quantity differs from the dispatched quantity', async () => {
    const { prisma, service } = createTransferService();
    await expect(
      service.receiveTransfer('transfer-1', 'user-1', 'tenant-1', {
        receivedItems: [{ productId: 'product-1', quantity: 4 }],
      }),
    ).rejects.toThrow('Add a note explaining the quantity difference');
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('records a fully missing shipment as zero received when the discrepancy is documented', async () => {
    const { prisma, service } = createTransferService();
    const transferUpdate = jest.fn(async ({ data }) => ({ ...transfer, ...data }));
    const itemUpdate = jest.fn(async () => ({ id: 'transfer-item-1' }));
    const stockUpdate = jest.fn();
    const movementCreate = jest.fn();
    const tx = {
      $queryRaw: jest.fn(async () => [{ id: 'transfer-1' }]),
      stockTransfer: {
        findUnique: jest.fn(async () => transfer),
        update: transferUpdate,
      },
      stockTransferItem: { update: itemUpdate },
      stock: { update: stockUpdate },
      stockMovement: { create: movementCreate },
    };
    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await service.receiveTransfer('transfer-1', 'user-1', 'tenant-1', {
      receivedItems: [{ productId: 'product-1', quantity: 0 }],
      notes: 'Shipment was lost before arrival',
    }, 'branch-destination');

    expect(result.status).toBe('completed');
    expect(itemUpdate).toHaveBeenCalledWith({
      where: { id: 'transfer-item-1' },
      data: { receivedQty: 0 },
    });
    expect(stockUpdate).not.toHaveBeenCalled();
    expect(movementCreate).not.toHaveBeenCalled();
    expect(transferUpdate).toHaveBeenCalledWith({
      where: { id: 'transfer-1' },
      data: expect.objectContaining({
        notes: 'Received: Shipment was lost before arrival',
      }),
    });
  });

  it('rejects products that are not part of the dispatched transfer', async () => {
    const { prisma, service } = createTransferService();
    await expect(
      service.receiveTransfer('transfer-1', 'user-1', 'tenant-1', {
        receivedItems: [{ productId: 'product-other', quantity: 1 }],
      }),
    ).rejects.toThrow('Received items must match the dispatched transfer');
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('returns readable branch and product names and includes incoming transfers', async () => {
    const incomingTransfer = {
      ...transfer,
      items: [
        {
          productId: 'product-1',
          requestedQty: 5,
          sentQty: 5,
          receivedQty: null,
        },
      ],
    };
    const { prisma, service } = createTransferService();
    prisma.stockTransfer.findUnique.mockClear();
    prisma.stockTransfer.findMany.mockResolvedValue([incomingTransfer]);
    prisma.stockTransfer.count.mockResolvedValue(1);
    prisma.product.findMany.mockResolvedValue([{ id: 'product-1', name: 'Tea' }]);

    const result = await service.getTransfers('tenant-1', 'branch-destination');

    expect(prisma.stockTransfer.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          AND: expect.arrayContaining([
            { fromBranchId: { in: ['branch-source', 'branch-destination'] } },
            { toBranchId: { in: ['branch-source', 'branch-destination'] } },
            { OR: [{ fromBranchId: 'branch-destination' }, { toBranchId: 'branch-destination' }] },
          ]),
        }),
      }),
    );
    expect(result.items[0]).toMatchObject({
      fromBranchName: 'Source',
      toBranchName: 'Destination',
      items: [{ productName: 'Tea', requestedQty: 5, sentQty: 5 }],
    });
  });

  it('does not expose another branch transfer by its ID', async () => {
    const { prisma, service } = createTransferService();

    await expect(
      service.getTransfer('transfer-1', 'tenant-1', 'branch-unrelated'),
    ).rejects.toThrow('Access denied');
    expect(prisma.product.findMany).not.toHaveBeenCalled();
  });
});
