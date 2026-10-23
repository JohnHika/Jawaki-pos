import {
  assessCredit,
  assessSalePricing,
  percentChange,
  severityForAmount,
  SaleLineInput,
} from './accountability.rules';
import {
  DEFAULT_ACCOUNTABILITY_SETTINGS,
  resolveAccountabilitySettings,
} from './accountability.settings';

const settings = DEFAULT_ACCOUNTABILITY_SETTINGS;

const line = (over: Partial<SaleLineInput> = {}): SaleLineInput => ({
  productId: 'p1',
  name: 'Sufuria',
  quantity: 2,
  unitPrice: 500,
  discount: 0,
  costPrice: 300,
  minPrice: null,
  ...over,
});

const pricing = (lines: SaleLineInput[], extra: Partial<Parameters<typeof assessSalePricing>[0]> = {}) =>
  assessSalePricing({
    lines,
    overallDiscount: 0,
    settings,
    canDiscount: false,
    canOverridePrice: false,
    ...extra,
  });

describe('assessSalePricing', () => {
  it('passes a normal sale', () => {
    expect(pricing([line()])).toEqual([]);
  });

  it('flags a sale below cost as HIGH and blockable for a cashier', () => {
    const [v] = pricing([line({ unitPrice: 250 })]);
    expect(v.code).toBe('BELOW_COST');
    expect(v.severity).toBe('HIGH');
    expect(v.blockable).toBe(true);
  });

  it('does not make a below-cost sale blockable for someone who can override price', () => {
    const [v] = pricing([line({ unitPrice: 250 })], { canOverridePrice: true });
    expect(v.code).toBe('BELOW_COST');
    expect(v.blockable).toBe(false);
  });

  it('counts the line discount when deciding if the price is below cost', () => {
    // 2 x 500 less a 450 discount = 275 each, under the 300 cost.
    const [v] = pricing([line({ discount: 450 })], { canDiscount: true });
    expect(v.code).toBe('BELOW_COST');
  });

  it('flags a sale under the explicit minimum price but above cost as MEDIUM', () => {
    const [v] = pricing([line({ unitPrice: 380, minPrice: 400 })]);
    expect(v.code).toBe('BELOW_FLOOR');
    expect(v.severity).toBe('MEDIUM');
  });

  it('applies the required margin on top of cost', () => {
    const strict = resolveAccountabilitySettings({ priceGuard: { minMarginPercent: 20 } });
    // cost 300 + 20% = 360 floor; 340 is above cost but under the floor.
    const [v] = pricing([line({ unitPrice: 340 })], { settings: strict });
    expect(v.code).toBe('BELOW_FLOOR');
    expect(pricing([line({ unitPrice: 360 })], { settings: strict })).toEqual([]);
  });

  it('ignores cost when none is known', () => {
    expect(pricing([line({ costPrice: null, unitPrice: 1 })])).toEqual([]);
  });

  it('flags a cashier discount over the limit, but not for someone with sales.discount', () => {
    // gross 1000, 150 off = 15% > 5% limit
    const [v] = pricing([line({ discount: 150 })]);
    expect(v.code).toBe('DISCOUNT_LIMIT');
    expect(v.blockable).toBe(true);
    expect(pricing([line({ discount: 150 })], { canDiscount: true })).toEqual([]);
  });

  it('adds the sale-level discount to line discounts', () => {
    // 30 line + 40 overall = 70 of 1000 = 7% > 5%
    const out = pricing([line({ discount: 30 })], { overallDiscount: 40 });
    expect(out.map((v) => v.code)).toEqual(['DISCOUNT_LIMIT']);
  });

  it('treats a discount of 25% or more as HIGH', () => {
    const [v] = pricing([line({ discount: 300 })]);
    expect(v.severity).toBe('HIGH');
  });

  it('does nothing when the guard is OFF', () => {
    const off = resolveAccountabilitySettings({ priceGuard: { mode: 'OFF' } });
    expect(pricing([line({ unitPrice: 1 })], { settings: off })).toEqual([]);
  });
});

const credit = (over: Partial<Parameters<typeof assessCredit>[0]> = {}) =>
  assessCredit({
    creditAmount: 1000,
    hasCustomer: true,
    customerName: 'Mama Njeri',
    customerLimit: 5000,
    outstanding: 0,
    oldestOverdueDays: 0,
    settings,
    ...over,
  });

describe('assessCredit', () => {
  it('is silent for a cash sale', () => {
    expect(credit({ creditAmount: 0, hasCustomer: false })).toEqual([]);
  });

  it('flags credit with no customer — nobody is on record as owing it', () => {
    const [v] = credit({ hasCustomer: false });
    expect(v.code).toBe('CREDIT_NO_CUSTOMER');
    expect(v.severity).toBe('HIGH');
  });

  it('allows credit within the limit', () => {
    expect(credit({ outstanding: 3000 })).toEqual([]);
  });

  it('flags credit that would push the balance over the limit', () => {
    const [v] = credit({ outstanding: 4500 });
    expect(v.code).toBe('CREDIT_LIMIT_EXCEEDED');
  });

  it('uses the company default when the customer has no limit of their own', () => {
    const withDefault = resolveAccountabilitySettings({ credit: { defaultLimit: 2000 } });
    const [v] = credit({ customerLimit: null, outstanding: 1500, settings: withDefault });
    expect(v.code).toBe('CREDIT_LIMIT_EXCEEDED');
  });

  it('has no limit at all when neither is set', () => {
    expect(credit({ customerLimit: null, outstanding: 9_999_999 })).toEqual([]);
  });

  it('flags new credit to a customer who is long overdue', () => {
    const strict = resolveAccountabilitySettings({ credit: { blockWhenOverdueDays: 30 } });
    const [v] = credit({ oldestOverdueDays: 45, settings: strict });
    expect(v.code).toBe('CREDIT_OVERDUE');
    expect(credit({ oldestOverdueDays: 10, settings: strict })).toEqual([]);
  });

  it('does nothing when credit checking is OFF', () => {
    const off = resolveAccountabilitySettings({ credit: { mode: 'OFF' } });
    expect(credit({ hasCustomer: false, settings: off })).toEqual([]);
  });
});

describe('severityForAmount / percentChange', () => {
  it('grades a void by how big it is', () => {
    expect(severityForAmount(1500, 1000)).toBe('HIGH');
    expect(severityForAmount(600, 1000)).toBe('MEDIUM');
    expect(severityForAmount(100, 1000)).toBe('LOW');
  });

  it('computes percent change and refuses a zero base', () => {
    expect(percentChange(100, 150)).toBe(50);
    expect(percentChange(200, 100)).toBe(-50);
    expect(percentChange(0, 100)).toBeNull();
  });
});

describe('resolveAccountabilitySettings', () => {
  it('returns the gentle defaults for empty or junk input', () => {
    expect(resolveAccountabilitySettings(undefined)).toEqual(DEFAULT_ACCOUNTABILITY_SETTINGS);
    expect(resolveAccountabilitySettings('nonsense')).toEqual(DEFAULT_ACCOUNTABILITY_SETTINGS);
  });

  it('never blocks by default — FLAG only', () => {
    expect(DEFAULT_ACCOUNTABILITY_SETTINGS.priceGuard.mode).toBe('FLAG');
    expect(DEFAULT_ACCOUNTABILITY_SETTINGS.credit.mode).toBe('FLAG');
  });

  it('clamps out-of-range numbers and rejects unknown modes', () => {
    const s = resolveAccountabilitySettings({
      priceGuard: { mode: 'EXPLODE', maxCashierDiscountPercent: 900, minMarginPercent: -5 },
      dailySummary: { hourLocal: 99 },
    });
    expect(s.priceGuard.mode).toBe('FLAG');
    expect(s.priceGuard.maxCashierDiscountPercent).toBe(100);
    expect(s.priceGuard.minMarginPercent).toBe(0);
    expect(s.dailySummary.hourLocal).toBe(23);
  });

  it('keeps an explicit null credit limit as "no limit"', () => {
    const s = resolveAccountabilitySettings({ credit: { defaultLimit: null } });
    expect(s.credit.defaultLimit).toBeNull();
  });
});
