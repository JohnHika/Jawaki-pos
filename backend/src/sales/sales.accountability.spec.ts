import { ForbiddenException } from '@nestjs/common';
import { PaymentMethod } from '@prisma/client';
import { SalesService } from './sales.service';
import { AccountabilityService } from '../accountability/accountability.service';

/**
 * End-to-end through SalesService with the real AccountabilityService, so the
 * wiring (what is passed in, when a sale is refused, what gets recorded) is
 * tested and not just the rules in isolation.
 */
describe('SalesService + accountability', () => {
  const tenantId = 'tenant-a';
  const branchId = 'branch-a';
  const userId = 'user-a';
  const productId = 'product-a';
  let prisma: any;
  let alerts: any;
  let service: SalesService;
  let settings: Record<string, unknown>;
  let permissions: string[];

  beforeEach(() => {
    settings = {};
    permissions = [];
    alerts = { create: jest.fn().mockResolvedValue({}) };

    prisma = {
      branch: {
        findFirst: jest.fn().mockResolvedValue({ id: branchId, tenantId }),
        findUnique: jest.fn().mockResolvedValue({ code: 'A', timezone: 'Africa/Nairobi' }),
      },
      tenant: { findUnique: jest.fn(async () => ({ settings: { accountability: settings } })) },
      sale: {
        findUnique: jest.fn().mockResolvedValue(null),
        count: jest.fn().mockResolvedValue(0),
      },
      customer: { findFirst: jest.fn().mockResolvedValue(null) },
      retailReceivable: { findMany: jest.fn().mockResolvedValue([]) },
      user: { findUnique: jest.fn().mockResolvedValue({ firstName: 'Faith', lastName: 'Atieno' }) },
      accountabilityAlert: alerts,
      product: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: productId,
            tenantId,
            name: 'Sufuria',
            basePrice: 500,
            costPrice: 300,
            minPrice: null,
            taxRate: 0,
            trackInventory: false,
            priceOverrides: [],
            stock: [],
          },
        ]),
      },
      $transaction: jest.fn(async (work: any) =>
        work({
          ...prisma,
          sale: {
            ...prisma.sale,
            create: jest.fn(async ({ data }: any) => ({
              id: 'sale-1',
              ...data,
              items: [{ id: 'line-1', productId }],
              branch: { name: 'Branch A' },
              user: { firstName: 'Faith', lastName: 'Atieno' },
              customer: null,
            })),
          },
          payment: { createMany: jest.fn(), findMany: jest.fn().mockResolvedValue([]) },
        }),
      ),
    };

    const accountability = new AccountabilityService(
      prisma,
      { record: jest.fn() } as any,
      { sendToTenantRoles: jest.fn() } as any,
      { getEffectivePermissions: jest.fn(async () => permissions) } as any,
    );
    const finance = { createRetailReceivableForSale: jest.fn().mockResolvedValue({ id: 'r1' }) };
    service = new SalesService(
      prisma,
      { get: jest.fn(), set: jest.fn() } as any,
      { recordEntry: jest.fn() } as any,
      finance as any,
      accountability,
    );
  });

  const cheapSale = (extra: Record<string, unknown> = {}) =>
    ({
      branchId,
      // 250 each is below the 300 cost.
      items: [{ productId, quantity: 1, unitPrice: 250 }],
      paymentMethod: PaymentMethod.CASH,
      paidAmount: 250,
      ...extra,
    }) as any;

  it('records a below-cost sale for the owner without stopping it (default FLAG mode)', async () => {
    permissions = ['sales.price_override'];
    const sale = await service.createSale(userId, tenantId, cheapSale());
    expect(sale).toBeDefined();

    const types = alerts.create.mock.calls.map((c: any) => c[0].data.type);
    expect(types).toContain('BELOW_COST');
    const data = alerts.create.mock.calls[0][0].data;
    expect(data.severity).toBe('HIGH');
    expect(data.entityId).toBe('sale-1');
    expect(data.body).toContain('Faith Atieno');
  });

  it('refuses an online idempotent sale once the owner switches to BLOCK', async () => {
    settings = { priceGuard: { mode: 'BLOCK' } };
    await expect(
      service.createSale(userId, tenantId, cheapSale({ offlineId: 'client-sale-id' })),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(alerts.create).not.toHaveBeenCalled();
  });

  it('still records an offline-queue sale in BLOCK mode — it already happened at the counter', async () => {
    settings = { priceGuard: { mode: 'BLOCK' } };
    await expect(
      service.createSale(
        userId,
        tenantId,
        cheapSale({ offlineId: 'dev-sale-1' }),
        { offlineReconciliation: true },
      ),
    ).resolves.toBeDefined();
    expect(alerts.create).toHaveBeenCalled();
  });

  it('lets a manager with sales.price_override through in BLOCK mode', async () => {
    settings = { priceGuard: { mode: 'BLOCK' } };
    permissions = ['sales.price_override'];
    await expect(service.createSale(userId, tenantId, cheapSale())).resolves.toBeDefined();
  });

  it('is silent for an ordinary profitable sale', async () => {
    await service.createSale(userId, tenantId, {
      branchId,
      items: [{ productId, quantity: 1, unitPrice: 500 }],
      paymentMethod: PaymentMethod.CASH,
      paidAmount: 500,
    } as any);
    expect(alerts.create).not.toHaveBeenCalled();
  });

  it('refuses credit with no customer attached in BLOCK mode', async () => {
    settings = { credit: { mode: 'BLOCK' } };
    await expect(
      service.createSale(userId, tenantId, {
        branchId,
        items: [{ productId, quantity: 1, unitPrice: 500 }],
        paymentMethod: PaymentMethod.CREDIT,
      } as any),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('accepts catalog-priced sales when no accountability layer is supplied', async () => {
    const bare = new SalesService(
      prisma,
      { get: jest.fn(), set: jest.fn() } as any,
      { recordEntry: jest.fn() } as any,
      { createRetailReceivableForSale: jest.fn() } as any,
    );
    await expect(
      bare.createSale(userId, tenantId, {
        ...cheapSale(),
        items: [{ productId, quantity: 1, unitPrice: 500 }],
        paidAmount: 500,
      }),
    ).resolves.toBeDefined();
  });
});
