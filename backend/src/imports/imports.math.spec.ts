import {
  computeLandedCost,
  ItemInput,
  participantLedgers,
  priceToKeepMargin,
  spread,
  weightedAverageCost,
} from './imports.math';

const item = (over: Partial<ItemInput> = {}): ItemInput => ({
  id: 'i1',
  participantId: 'me',
  quantity: 100,
  unitCost: 2, // USD
  cbm: null,
  weightKg: null,
  ...over,
});

describe('spread', () => {
  it('always adds back up to the total, to the cent', () => {
    for (const total of [100, 100.01, 99.99, 1000.07, 0.05]) {
      const parts = spread(total, [1, 1, 1]);
      expect(Math.round(parts.reduce((a, b) => a + b, 0) * 100) / 100).toBe(total);
    }
  });

  it('splits evenly when every weight is zero', () => {
    expect(spread(90, [0, 0, 0])).toEqual([30, 30, 30]);
  });

  it('returns nothing for no lines', () => {
    expect(spread(50, [])).toEqual([]);
  });
});

describe('computeLandedCost', () => {
  it('converts goods to KES and spreads costs by value', () => {
    const r = computeLandedCost({
      fxRate: 130,
      basis: 'VALUE',
      items: [
        item({ id: 'a', quantity: 100, unitCost: 2 }), // 200 USD = 26,000
        item({ id: 'b', quantity: 100, unitCost: 6 }), // 600 USD = 78,000
      ],
      costs: [{ amountKes: 52_000 }], // 50% of goods value
    });
    expect(r.goodsKes).toBe(104_000);
    expect(r.costsKes).toBe(52_000);
    expect(r.landedKes).toBe(156_000);
    expect(r.uplift).toBe(50);
    const a = r.items.find((i) => i.id === 'a')!;
    const b = r.items.find((i) => i.id === 'b')!;
    expect(a.allocatedCostKes).toBe(13_000);
    expect(b.allocatedCostKes).toBe(39_000);
    // 26,000 + 13,000 over 100 pieces
    expect(a.landedUnitCostKes).toBe(390);
    expect(b.landedUnitCostKes).toBe(1170);
  });

  it('spreads by quantity when asked', () => {
    const r = computeLandedCost({
      fxRate: 100,
      basis: 'QUANTITY',
      items: [item({ id: 'a', quantity: 100 }), item({ id: 'b', quantity: 300, unitCost: 1 })],
      costs: [{ amountKes: 4000 }],
    });
    expect(r.items.find((i) => i.id === 'a')!.allocatedCostKes).toBe(1000);
    expect(r.items.find((i) => i.id === 'b')!.allocatedCostKes).toBe(3000);
  });

  it('spreads by CBM when every line has a volume', () => {
    const r = computeLandedCost({
      fxRate: 100,
      basis: 'CBM',
      items: [item({ id: 'a', cbm: 10 }), item({ id: 'b', cbm: 30 })],
      costs: [{ amountKes: 8000 }],
    });
    expect(r.basisUsed).toBe('CBM');
    expect(r.items.find((i) => i.id === 'a')!.allocatedCostKes).toBe(2000);
  });

  it('falls back to value, with a warning, when a line has no volume', () => {
    const r = computeLandedCost({
      fxRate: 100,
      basis: 'CBM',
      items: [item({ id: 'a', cbm: 10 }), item({ id: 'b', cbm: null })],
      costs: [{ amountKes: 1000 }],
    });
    expect(r.basisUsed).toBe('VALUE');
    expect(r.warnings.join(' ')).toMatch(/volume/i);
    const total = r.items.reduce((s, i) => s + i.allocatedCostKes, 0);
    expect(total).toBe(1000);
  });

  it('keeps the books balanced when costs do not divide evenly', () => {
    const r = computeLandedCost({
      fxRate: 130.5,
      basis: 'VALUE',
      items: [item({ id: 'a', unitCost: 1.33 }), item({ id: 'b', unitCost: 2.17 }), item({ id: 'c', unitCost: 0.91 })],
      costs: [{ amountKes: 10_000.01 }],
    });
    const allocated = r.items.reduce((s, i) => s + i.allocatedCostKes, 0);
    expect(Math.round(allocated * 100) / 100).toBe(10_000.01);
    expect(r.landedKes).toBeCloseTo(r.goodsKes + 10_000.01, 2);
  });

  it('handles a shipment with no items or no costs', () => {
    expect(computeLandedCost({ fxRate: 130, basis: 'VALUE', items: [], costs: [] }).landedKes).toBe(0);
    const r = computeLandedCost({ fxRate: 130, basis: 'VALUE', items: [item()], costs: [] });
    expect(r.items[0].allocatedCostKes).toBe(0);
    expect(r.uplift).toBe(0);
  });

  it('gives a zero-quantity line a zero unit cost instead of dividing by zero', () => {
    const r = computeLandedCost({
      fxRate: 130,
      basis: 'VALUE',
      items: [item({ quantity: 0 })],
      costs: [{ amountKes: 100 }],
    });
    expect(r.items[0].landedUnitCostKes).toBe(0);
  });
});

describe('participantLedgers', () => {
  const calc = computeLandedCost({
    fxRate: 100,
    basis: 'VALUE',
    items: [
      item({ id: 'a', participantId: 'me', quantity: 100, unitCost: 3 }), // 30,000
      item({ id: 'b', participantId: 'wanjiru', quantity: 100, unitCost: 1 }), // 10,000
    ],
    costs: [{ amountKes: 20_000 }], // 50% uplift
  });

  it('adds each trader\'s goods and their share of costs', () => {
    const [me, wanjiru] = participantLedgers(calc.items, ['me', 'wanjiru'], []);
    expect(me.goodsKes).toBe(30_000);
    expect(me.costShareKes).toBe(15_000);
    expect(me.owesKes).toBe(45_000);
    expect(wanjiru.owesKes).toBe(15_000);
    expect(wanjiru.status).toBe('UNPAID');
  });

  it('tracks part payment, settlement and overpayment', () => {
    const [part] = participantLedgers(calc.items, ['wanjiru'], [{ participantId: 'wanjiru', amountKes: 5_000 }]);
    expect(part.balanceKes).toBe(10_000);
    expect(part.status).toBe('PART_PAID');

    const [done] = participantLedgers(calc.items, ['wanjiru'], [
      { participantId: 'wanjiru', amountKes: 10_000 },
      { participantId: 'wanjiru', amountKes: 5_000 },
    ]);
    expect(done.status).toBe('SETTLED');

    const [over] = participantLedgers(calc.items, ['wanjiru'], [{ participantId: 'wanjiru', amountKes: 16_000 }]);
    expect(over.status).toBe('OVERPAID');
    expect(over.balanceKes).toBe(-1_000);
  });

  it('ignores other people\'s payments', () => {
    const [me] = participantLedgers(calc.items, ['me'], [{ participantId: 'wanjiru', amountKes: 15_000 }]);
    expect(me.paidKes).toBe(0);
  });
});

describe('weightedAverageCost / priceToKeepMargin', () => {
  it('blends existing stock with new landed stock', () => {
    // 50 on hand @ 100, 50 arriving @ 140 => 120
    expect(weightedAverageCost(50, 100, 50, 140)).toBe(120);
  });

  it('uses the landed cost when nothing is on hand or no cost is known', () => {
    expect(weightedAverageCost(0, 100, 20, 140)).toBe(140);
    expect(weightedAverageCost(10, null, 20, 140)).toBe(140);
  });

  it('keeps the usual markup after a cost rise', () => {
    // cost 100 sells at 130 (1.3x); cost goes to 150 => 195
    expect(priceToKeepMargin(100, 130, 150)).toBe(195);
  });

  it('gives no suggestion when the old price had no margin to preserve', () => {
    expect(priceToKeepMargin(100, 90, 150)).toBeNull();
    expect(priceToKeepMargin(null, 130, 150)).toBeNull();
  });
});
