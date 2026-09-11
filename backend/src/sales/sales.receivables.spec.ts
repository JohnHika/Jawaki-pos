import { PaymentMethod } from '@prisma/client';
import { SalesService } from './sales.service';

describe('SalesService receivable creation', () => {
  const tenantId = 'tenant-a';
  const branchId = 'branch-a';
  const userId = 'user-a';
  const productId = 'product-a';
  let prisma: any;
  let finance: any;
  let service: SalesService;

  beforeEach(() => {
    prisma = {
      branch: {
        findFirst: jest.fn().mockResolvedValue({ id: branchId, tenantId }),
        findUnique: jest.fn().mockResolvedValue({ code: 'A', timezone: 'Africa/Nairobi' }),
      },
      sale: {
        findUnique: jest.fn().mockResolvedValue(null),
        count: jest.fn().mockResolvedValue(0),
      },
      product: {
        findMany: jest.fn().mockResolvedValue([{
          id: productId,
          tenantId,
          name: 'Item',
          basePrice: 100,
          taxRate: 0,
          trackInventory: false,
          priceOverrides: [],
          stock: [],
        }]),
      },
      $transaction: jest.fn(async (work: any) => work({
        ...prisma,
        sale: {
          ...prisma.sale,
          create: jest.fn(async ({ data }: any) => ({
            id: 'sale-1',
            ...data,
            items: [{ id: 'line-1', productId }],
            branch: { name: 'Branch A' },
            user: { firstName: 'User', lastName: 'A' },
            customer: null,
          })),
        },
        payment: { createMany: jest.fn(), findMany: jest.fn().mockResolvedValue([]) },
      })),
    };
    finance = { createRetailReceivableForSale: jest.fn().mockResolvedValue({ id: 'receivable-1' }) };
    service = new SalesService(prisma, { get: jest.fn(), set: jest.fn() } as any, { recordEntry: jest.fn() } as any, finance);
  });

  const baseSale = {
    branchId,
    items: [{ productId, quantity: 1 }],
  } as any;

  it('creates an obligation for the whole unpaid pure CREDIT receipt inside the sale transaction', async () => {
    await service.createSale(userId, tenantId, { ...baseSale, paymentMethod: PaymentMethod.CREDIT, offlineId: 'sale-offline-1' });

    expect(finance.createRetailReceivableForSale).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      tenantId,
      branchId,
      saleId: 'sale-1',
      originalAmount: 100,
      offlineId: 'sale-offline-1',
      createdById: userId,
    }));
  });

  it('creates an obligation only for the CREDIT tender portion of a SPLIT receipt', async () => {
    await service.createSale(userId, tenantId, {
      ...baseSale,
      paymentMethod: PaymentMethod.SPLIT,
      tenders: [
        { method: PaymentMethod.CASH, amount: 60 },
        { method: PaymentMethod.CREDIT, amount: 40 },
      ],
    });

    expect(finance.createRetailReceivableForSale).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      saleId: 'sale-1',
      originalAmount: 40,
    }));
  });
});
