export type AllocationBasis = 'VALUE' | 'QUANTITY' | 'CBM' | 'WEIGHT';

export interface CostInput {
  amountKes: number;
}

export interface ItemInput {
  id: string;
  participantId: string | null;
  quantity: number;
  /** Supplier price per unit in the shipment currency. */
  unitCost: number;
  cbm: number | null;
  weightKg: number | null;
}

export interface ItemResult {
  id: string;
  participantId: string | null;
  goodsValueKes: number;
  allocatedCostKes: number;
  /** (goods + allocated costs) / quantity, in KES. */
  landedUnitCostKes: number;
  landedTotalKes: number;
}

export interface LandedCostResult {
  basisUsed: AllocationBasis;
  warnings: string[];
  items: ItemResult[];
  goodsKes: number;
  costsKes: number;
  landedKes: number;
  /** How much dearer each item became than the supplier price, in %. */
  uplift: number;
}

const round2 = (n: number) => Math.round(n * 100) / 100;
const round4 = (n: number) => Math.round(n * 10_000) / 10_000;

/**
 * Spreads `total` across `weights` so the parts add up to exactly `total` to
 * the cent. Naive rounding loses or invents cents; the leftover goes to the
 * largest share so the books always balance.
 */
export function spread(total: number, weights: number[]): number[] {
  const sum = weights.reduce((a, b) => a + b, 0);
  if (weights.length === 0) return [];
  if (sum <= 0) {
    const even = round2(total / weights.length);
    const parts = weights.map(() => even);
    parts[0] = round2(parts[0] + (total - even * weights.length));
    return parts;
  }
  const parts = weights.map((w) => round2((total * w) / sum));
  const drift = round2(total - parts.reduce((a, b) => a + b, 0));
  if (drift !== 0) {
    let biggest = 0;
    for (let i = 1; i < weights.length; i++) if (weights[i] > weights[biggest]) biggest = i;
    parts[biggest] = round2(parts[biggest] + drift);
  }
  return parts;
}

/**
 * True landed cost of every line in a shipment.
 *
 * Goods are converted to KES at the shipment's rate. All shipment costs
 * (freight, duty, clearing...) are then spread across the lines by the
 * chosen basis. If the basis needs data some lines lack (e.g. CBM with a
 * line that has no volume) it falls back to VALUE and says so, rather than
 * silently charging those lines nothing.
 */
export function computeLandedCost(input: {
  fxRate: number;
  basis: AllocationBasis;
  items: ItemInput[];
  costs: CostInput[];
}): LandedCostResult {
  const warnings: string[] = [];
  const goods = input.items.map((i) => round2(i.quantity * i.unitCost * input.fxRate));
  const goodsKes = round2(goods.reduce((a, b) => a + b, 0));
  const costsKes = round2(input.costs.reduce((a, c) => a + c.amountKes, 0));

  let basisUsed: AllocationBasis = input.basis;
  let weights: number[];

  const complete = (pick: (i: ItemInput) => number | null) =>
    input.items.length > 0 && input.items.every((i) => (pick(i) ?? 0) > 0);

  if (basisUsed === 'CBM' && !complete((i) => i.cbm)) {
    warnings.push('Some lines have no volume (CBM), so costs were spread by value instead.');
    basisUsed = 'VALUE';
  } else if (basisUsed === 'WEIGHT' && !complete((i) => i.weightKg)) {
    warnings.push('Some lines have no weight, so costs were spread by value instead.');
    basisUsed = 'VALUE';
  }

  switch (basisUsed) {
    case 'QUANTITY':
      weights = input.items.map((i) => i.quantity);
      break;
    case 'CBM':
      weights = input.items.map((i) => i.cbm ?? 0);
      break;
    case 'WEIGHT':
      weights = input.items.map((i) => i.weightKg ?? 0);
      break;
    default:
      weights = goods;
  }

  if (costsKes > 0 && goodsKes === 0 && basisUsed === 'VALUE') {
    warnings.push('Costs were entered but the goods have no value yet, so they were split evenly.');
  }

  const allocated = spread(costsKes, weights);
  const items: ItemResult[] = input.items.map((item, idx) => {
    const landedTotal = round2(goods[idx] + allocated[idx]);
    return {
      id: item.id,
      participantId: item.participantId,
      goodsValueKes: goods[idx],
      allocatedCostKes: allocated[idx],
      landedUnitCostKes: item.quantity > 0 ? round4(landedTotal / item.quantity) : 0,
      landedTotalKes: landedTotal,
    };
  });

  return {
    basisUsed,
    warnings,
    items,
    goodsKes,
    costsKes,
    landedKes: round2(goodsKes + costsKes),
    uplift: goodsKes > 0 ? round2((costsKes / goodsKes) * 100) : 0,
  };
}

export interface ParticipantLedger {
  participantId: string;
  goodsKes: number;
  costShareKes: number;
  owesKes: number;
  paidKes: number;
  balanceKes: number;
  status: 'SETTLED' | 'PART_PAID' | 'UNPAID' | 'OVERPAID';
}

/**
 * What each trader in a shared container owes: their goods plus their share
 * of the costs, less what they've already handed over.
 */
export function participantLedgers(
  items: ItemResult[],
  participantIds: string[],
  payments: Array<{ participantId: string; amountKes: number }>,
): ParticipantLedger[] {
  return participantIds.map((participantId) => {
    const mine = items.filter((i) => i.participantId === participantId);
    const goodsKes = round2(mine.reduce((a, i) => a + i.goodsValueKes, 0));
    const costShareKes = round2(mine.reduce((a, i) => a + i.allocatedCostKes, 0));
    const owesKes = round2(goodsKes + costShareKes);
    const paidKes = round2(
      payments.filter((p) => p.participantId === participantId).reduce((a, p) => a + p.amountKes, 0),
    );
    const balanceKes = round2(owesKes - paidKes);
    const status =
      balanceKes < -0.005
        ? 'OVERPAID'
        : Math.abs(balanceKes) <= 0.005 && owesKes > 0
          ? 'SETTLED'
          : paidKes > 0
            ? 'PART_PAID'
            : owesKes > 0
              ? 'UNPAID'
              : 'SETTLED';
    return { participantId, goodsKes, costShareKes, owesKes, paidKes, balanceKes, status };
  });
}

export { weightedAverageCost } from '../common/product-cost';

/** Price that keeps the margin the shop was already earning after a cost rise. */
export function priceToKeepMargin(
  oldCost: number | null,
  oldPrice: number,
  newCost: number,
): number | null {
  if (!oldCost || oldCost <= 0 || oldPrice <= oldCost) return null;
  const markup = oldPrice / oldCost;
  return Math.ceil(newCost * markup);
}
