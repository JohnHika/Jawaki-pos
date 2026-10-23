import {
  CouponDef,
  CouponContext,
  describeCoupon,
  evaluateCoupon,
  normaliseCouponCode,
  spreadCouponDiscount,
} from './coupons.rules';

const NOW = new Date('2026-10-24T09:00:00Z');

const base = (over: Partial<CouponDef> = {}): CouponDef => ({
  code: 'SAVE10',
  kind: 'PERCENT',
  value: 10,
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
  ...over,
});

const ctx = (over: Partial<CouponContext> = {}): CouponContext => ({
  now: NOW,
  customerId: null,
  customerUses: 0,
  lines: [
    { productId: 'a', amount: 600 },
    { productId: 'b', amount: 400 },
  ],
  ...over,
});

describe('evaluateCoupon', () => {
  it('takes a percentage off the whole sale', () => {
    const v = evaluateCoupon(base(), ctx());
    expect(v).toMatchObject({ ok: true, discount: 100, eligibleAmount: 1000 });
  });

  it('caps a percent coupon at maxDiscount', () => {
    const v = evaluateCoupon(base({ value: 50, maxDiscount: 120 }), ctx());
    expect(v).toMatchObject({ ok: true, discount: 120 });
  });

  it('gives a fixed amount, never more than the sale', () => {
    expect(evaluateCoupon(base({ kind: 'FIXED', value: 200 }), ctx())).toMatchObject({ ok: true, discount: 200 });
    expect(
      evaluateCoupon(base({ kind: 'FIXED', value: 5000 }), ctx({ lines: [{ productId: 'a', amount: 300 }] })),
    ).toMatchObject({ ok: true, discount: 300 });
  });

  it('only discounts the listed products', () => {
    const v = evaluateCoupon(base({ productIds: ['b'] }), ctx());
    expect(v).toMatchObject({ ok: true, discount: 40, eligibleAmount: 400 });
  });

  it('refuses when none of the products qualify', () => {
    const v = evaluateCoupon(base({ productIds: ['z'] }), ctx());
    expect(v).toMatchObject({ ok: false, reason: 'NOTHING_ELIGIBLE' });
  });

  it('measures minimum spend on the whole sale, not just eligible items', () => {
    expect(evaluateCoupon(base({ minSpend: 900, productIds: ['b'] }), ctx())).toMatchObject({ ok: true });
    expect(evaluateCoupon(base({ minSpend: 1500 }), ctx())).toMatchObject({ ok: false, reason: 'MIN_SPEND' });
  });

  it('respects the start and end dates', () => {
    expect(evaluateCoupon(base({ startsAt: new Date('2026-11-01') }), ctx())).toMatchObject({
      ok: false,
      reason: 'NOT_STARTED',
    });
    expect(evaluateCoupon(base({ expiresAt: new Date('2026-10-01') }), ctx())).toMatchObject({
      ok: false,
      reason: 'EXPIRED',
    });
  });

  it('refuses a switched-off or used-up coupon', () => {
    expect(evaluateCoupon(base({ isActive: false }), ctx())).toMatchObject({ ok: false, reason: 'INACTIVE' });
    expect(evaluateCoupon(base({ usageLimit: 5, usedCount: 5 }), ctx())).toMatchObject({
      ok: false,
      reason: 'USED_UP',
    });
    expect(evaluateCoupon(base({ usageLimit: 5, usedCount: 4 }), ctx())).toMatchObject({ ok: true });
  });

  it('locks a coupon to one customer', () => {
    const def = base({ customerId: 'c1' });
    expect(evaluateCoupon(def, ctx())).toMatchObject({ ok: false, reason: 'NEEDS_CUSTOMER' });
    expect(evaluateCoupon(def, ctx({ customerId: 'c2' }))).toMatchObject({ ok: false, reason: 'WRONG_CUSTOMER' });
    expect(evaluateCoupon(def, ctx({ customerId: 'c1' }))).toMatchObject({ ok: true });
  });

  it('limits uses per customer and needs a customer to count them', () => {
    const def = base({ perCustomerLimit: 2 });
    expect(evaluateCoupon(def, ctx())).toMatchObject({ ok: false, reason: 'NEEDS_CUSTOMER' });
    expect(evaluateCoupon(def, ctx({ customerId: 'c1', customerUses: 2 }))).toMatchObject({
      ok: false,
      reason: 'CUSTOMER_LIMIT',
    });
    expect(evaluateCoupon(def, ctx({ customerId: 'c1', customerUses: 1 }))).toMatchObject({ ok: true });
  });

  it('rounds to cents', () => {
    const v = evaluateCoupon(base({ value: 7.5 }), ctx({ lines: [{ productId: 'a', amount: 333.33 }] }));
    expect(v).toMatchObject({ ok: true, discount: 25 });
  });

  it('ignores negative line amounts', () => {
    const v = evaluateCoupon(base(), ctx({ lines: [{ productId: 'a', amount: -50 }, { productId: 'b', amount: 200 }] }));
    expect(v).toMatchObject({ ok: true, discount: 20 });
  });
});

describe('spreadCouponDiscount', () => {
  const lines = [
    { productId: 'a', amount: 600 },
    { productId: 'b', amount: 300 },
    { productId: 'c', amount: 100 },
  ];

  it('shares the discount in proportion to value and adds up exactly', () => {
    const shares = spreadCouponDiscount(lines, [], 100);
    expect(shares).toEqual([60, 30, 10]);
    expect(shares.reduce((s, x) => s + x, 0)).toBe(100);
  });

  it('only touches the lines the coupon applies to', () => {
    expect(spreadCouponDiscount(lines, ['b', 'c'], 40)).toEqual([0, 30, 10]);
  });

  it('puts rounding leftovers on the last line so cents are never lost', () => {
    const shares = spreadCouponDiscount(
      [
        { productId: 'a', amount: 100 },
        { productId: 'b', amount: 100 },
        { productId: 'c', amount: 100 },
      ],
      [],
      100,
    );
    expect(shares.reduce((s, x) => Math.round((s + x) * 100) / 100, 0)).toBe(100);
  });

  it('gives nothing when there is nothing to spread', () => {
    expect(spreadCouponDiscount(lines, [], 0)).toEqual([0, 0, 0]);
    expect(spreadCouponDiscount(lines, ['zzz'], 50)).toEqual([0, 0, 0]);
  });
});

describe('helpers', () => {
  it('normalises codes', () => {
    expect(normaliseCouponCode('  save 10 ')).toBe('SAVE10');
  });

  it('describes coupons', () => {
    expect(describeCoupon({ kind: 'PERCENT', value: 10, maxDiscount: null })).toBe('10% off');
    expect(describeCoupon({ kind: 'PERCENT', value: 10, maxDiscount: 500 })).toBe('10% off (max KES 500)');
    expect(describeCoupon({ kind: 'FIXED', value: 200, maxDiscount: null })).toBe('KES 200 off');
  });
});
