import { breakdownByCounter, computeVariances, CountLine, summarizeCount } from './stocktake.math';

const line = (over: Partial<CountLine>): CountLine => ({
  productId: 'p',
  productName: 'Item',
  expectedQty: 10,
  countedQty: 10,
  unitCost: 100,
  countedById: 'u1',
  ...over,
});

describe('stocktake math', () => {
  it('values a shortage as negative money at cost', () => {
    const [v] = computeVariances([line({ expectedQty: 10, countedQty: 7, unitCost: 120 })]);
    expect(v.varianceQty).toBe(-3);
    expect(v.varianceValue).toBe(-360);
  });

  it('leaves uncounted lines out of the variance', () => {
    expect(computeVariances([line({ countedQty: null })])).toEqual([]);
  });

  it('summarises losses, gains and completion', () => {
    const s = summarizeCount([
      line({ productId: 'a', expectedQty: 10, countedQty: 8, unitCost: 100 }), // -200
      line({ productId: 'b', expectedQty: 5, countedQty: 6, unitCost: 50 }), // +50
      line({ productId: 'c', expectedQty: 4, countedQty: 4 }), // match
      line({ productId: 'd', expectedQty: 4, countedQty: null }), // not counted
    ]);
    expect(s).toMatchObject({
      totalLines: 4,
      countedLines: 3,
      matchedLines: 1,
      shortLines: 1,
      overLines: 1,
      lossValue: 200,
      gainValue: 50,
      netValue: -150,
      completionPercent: 75,
    });
  });

  it('handles fractional quantities without float drift', () => {
    const [v] = computeVariances([line({ expectedQty: 0.3, countedQty: 0.1, unitCost: 10 })]);
    expect(v.varianceQty).toBe(-0.2);
    expect(v.varianceValue).toBe(-2);
  });

  it('ranks counters by how much their counts come up short', () => {
    const rows = breakdownByCounter([
      line({ productId: 'a', countedQty: 5, countedById: 'honest' }), // -500
      line({ productId: 'b', countedQty: 10, countedById: 'honest' }), // 0
      line({ productId: 'c', countedQty: 0, countedById: 'short' }), // -1000
    ]);
    expect(rows[0].countedById).toBe('short');
    expect(rows[0].netValue).toBe(-1000);
    expect(rows[1].netValue).toBe(-500);
  });

  it('reports an empty count as 0% complete, not NaN', () => {
    expect(summarizeCount([]).completionPercent).toBe(0);
  });
});
