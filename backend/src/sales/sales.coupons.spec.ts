import { BadRequestException } from '@nestjs/common';
import { PaymentMethod } from '@prisma/client';
import { SalesService } from './sales.service';
import { AccountabilityService } from '../accountability/accountability.service';
import { CouponsService } from '../coupons/coupons.service';

/**
 * A coupon is an approved discount: it must not trip the cashier's own
 * discount limit, must be counted, and must never turn a sale that already
 * happened at the counter into a refusal.
 */
describe('SalesService + coupons', () => {
  const tenantId = 'tenant-a';
  const branchId = 'branch-a';
  const userId = 'user-a';
  const productId = 'product-a';
  let prisma: any;
  let alerts: any;
  let redemptionCreate: jest.Mock;
  let couponUpdate: jest.Mock;
  let saleCreate: jest.Mock;
  let coupon: any;
  let service: SalesService;

  beforeEach(() => {
    alerts = { create: jest.fn().mockResolvedValue({}) };
    redemptionCreate = jest.fn().mockResolvedValue({});
    couponUpdate = jest.fn().mockResolvedValue({ usedCount: 1, usageLimit: null });
    saleCreate = jest.fn(async ({ data }: any) => ({
      id: 'sale-1',
      ...data,
      items: [{ id: 'line-1', productId }],
      branch: { name: 'Branch A' },
      user: { firstName: 'Faith', lastName: 'Atieno' },
      customer: null,
    }));
    coupon = {
      id: 'coupon-1',
      tenantId,
      code: 'SAVE20',
      kind: 'PERCENT',
      value: 20,
      maxDiscount: null,
      minSpend: null,
      startsAt: null,
      expiresAt: null,
      usageLimit: null,
      usedCount: 0,
      perCustomerLimit: null,
      customerId: null,
      productIds: [],
      isActive: true,
    };

    prisma = {
      branch: {
        findFirst: jest.fn().mockResolvedValue({ id: branchId, tenantId }),
        findUnique: jest.fn().mockResolvedValue({ code: 'A', timezone: 'Africa/Nairobi' }),
      },
      tenant: {
        findUnique: jest.fn(async () => ({
          settings: { accountability: { priceGuard: { maxCashierDiscountPercent: 5 } } },
        })),
      },
      sale: { findUnique: jest.fn().mockResolvedValue(null), count: jest.fn().mockResolvedValue(0) },
      customer: { findFirst: jest.fn().mockResolvedValue(null) },
      retailReceivable: { findMany: jest.fn().mockResolvedValue([]) },
      user: { findUnique: jest.fn().mockResolvedValue({ firstName: 'Faith', lastName: 'Atieno' }) },
      accountabilityAlert: alerts,
      coupon: {
        findUnique: jest.fn(async () => coupon),
      },
      couponRedemption: { count: jest.fn().mockResolvedValue(0) },
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
            create: saleCreate,
          },
          couponRedemption: {
            findUnique: jest.fn().mockResolvedValue(null),
            create: redemptionCreate,
          },
          coupon: { update: couponUpdate },
          payment: { createMany: jest.fn(), findMany: jest.fn().mockResolvedValue([]) },
        }),
      ),
    };

    const accountability = new AccountabilityService(
      prisma,
      { record: jest.fn() } as any,
      { sendToTenantRoles: jest.fn() } as any,
      { getEffectivePermissions: jest.fn(async () => []) } as any,
    );
    const coupons = new CouponsService(prisma, { record: jest.fn() } as any, accountability);
    const finance = { createRetailReceivableForSale: jest.fn().mockResolvedValue({ id: 'r1' }) };
    service = new SalesService(
      prisma,
      { get: jest.fn(), set: jest.fn() } as any,
      { recordEntry: jest.fn() } as any,
      finance as any,
      accountability,
      coupons,
    );
  });

  const sale = (extra: Record<string, unknown> = {}) =>
    ({
      branchId,
      items: [{ productId, quantity: 1, unitPrice: 500 }],
      discountAmount: 100,
      paymentMethod: PaymentMethod.CASH,
      paidAmount: 400,
      ...extra,
    }) as any;

  const alertTypes = () => alerts.create.mock.calls.map((c: any) => c[0].data.type);

  it('counts a valid coupon and keeps it out of the cashier discount limit', async () => {
    const created = await service.createSale(userId, tenantId, sale({ couponCode: 'save20' }));

    expect(created).toBeDefined();
    expect(redemptionCreate).toHaveBeenCalledTimes(1);
    expect(redemptionCreate.mock.calls[0][0].data).toMatchObject({
      couponId: 'coupon-1',
      saleId: 'sale-1',
      code: 'SAVE20',
      amount: 100,
      userId,
    });
    expect(couponUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ data: { usedCount: { increment: 1 } } }),
    );
    expect(alertTypes()).not.toContain('DISCOUNT_LIMIT');
    expect(alertTypes()).not.toContain('COUPON_REJECTED');
  });

  it('records the coupon on the receipt metadata', async () => {
    await service.createSale(userId, tenantId, sale({ couponCode: 'SAVE20' }));
    expect(saleCreate.mock.calls[0][0].data.metadata).toEqual({
      coupon: { code: 'SAVE20', amount: 100 },
    });
    expect(saleCreate.mock.calls[0][0].data.discountAmount).toBe(100);
  });

  it('flags the same discount as over-limit when no coupon backs it', async () => {
    await service.createSale(userId, tenantId, sale());
    expect(alertTypes()).toContain('DISCOUNT_LIMIT');
    expect(redemptionCreate).not.toHaveBeenCalled();
  });

  it('only credits the coupon for the discount it actually allows', async () => {
    // 20% of 500 is 100, but the cashier took 150 off.
    await service.createSale(userId, tenantId, sale({ couponCode: 'SAVE20', discountAmount: 150, paidAmount: 350 }));
    expect(redemptionCreate.mock.calls[0][0].data.amount).toBe(100);
    // The extra 50 (10%) is the cashier's own discount, over the 5% limit.
    expect(alertTypes()).toContain('DISCOUNT_LIMIT');
  });

  it('still flags a sale the coupon pushed below cost', async () => {
    // 60% off 500 is 300 off, leaving 200 against a cost of 300.
    coupon.value = 60;
    await service.createSale(userId, tenantId, sale({ couponCode: 'SAVE20', discountAmount: 300, paidAmount: 200 }));
    expect(alertTypes()).toContain('BELOW_COST');
    // It is the coupon's discount, so it is not also an over-limit cashier discount.
    expect(alertTypes()).not.toContain('DISCOUNT_LIMIT');
  });

  it('keeps an offline sale with a bad coupon, and tells the owner', async () => {
    coupon.expiresAt = new Date('2020-01-01');
    const created = await service.createSale(
      userId,
      tenantId,
      sale({ couponCode: 'SAVE20', offlineId: 'dev-1' }),
      { offlineReconciliation: true },
    );
    expect(created).toBeDefined();
    expect(redemptionCreate).not.toHaveBeenCalled();
    expect(alertTypes()).toContain('COUPON_REJECTED');
    // The discount was never backed by a valid coupon, so it counts as the cashier's own.
    expect(alertTypes()).toContain('DISCOUNT_LIMIT');
  });

  it('refuses an online idempotent sale with a coupon that does not exist', async () => {
    coupon = null;
    await expect(
      service.createSale(
        userId,
        tenantId,
        sale({ couponCode: 'NOPE', offlineId: 'client-sale-id' }),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('never refuses a sale whose payment was already taken', async () => {
    coupon = null;
    await expect(
      service.createSale(userId, tenantId, sale({ couponCode: 'NOPE', paymentMethod: PaymentMethod.MPESA }), {
        verifiedMerchantMpesa: true,
      }),
    ).resolves.toBeDefined();
    expect(alertTypes()).toContain('COUPON_REJECTED');
  });

  it('flags a coupon that went past its limit in a race', async () => {
    couponUpdate.mockResolvedValue({ usedCount: 6, usageLimit: 5 });
    await service.createSale(userId, tenantId, sale({ couponCode: 'SAVE20', offlineId: 'dev-2' }));
    expect(alertTypes()).toContain('COUPON_OVERUSE');
  });
});
