export interface CountLine {
  productId: string;
  productName: string;
  expectedQty: number;
  countedQty: number | null;
  unitCost: number;
  countedById?: string | null;
}

export interface VarianceLine extends CountLine {
  /** counted - expected; positive = more than the system said (overage). */
  varianceQty: number;
  /** varianceQty valued at cost; negative = money lost. */
  varianceValue: number;
}

const round2 = (n: number) => Math.round(n * 100) / 100;
const round3 = (n: number) => Math.round(n * 1000) / 1000;

/** Variance for lines that were actually counted; uncounted lines are left out. */
export function computeVariances(lines: CountLine[]): VarianceLine[] {
  return lines
    .filter((l) => l.countedQty !== null)
    .map((l) => {
      const varianceQty = round3((l.countedQty as number) - l.expectedQty);
      return { ...l, varianceQty, varianceValue: round2(varianceQty * l.unitCost) };
    });
}

export interface CountSummary {
  totalLines: number;
  countedLines: number;
  matchedLines: number;
  shortLines: number;
  overLines: number;
  /** Value of all shortages (a positive number). */
  lossValue: number;
  /** Value of all overages (a positive number). */
  gainValue: number;
  /** gain - loss; negative means the shop is poorer than its books said. */
  netValue: number;
  /** Counted lines as a share of all lines, 0-100. */
  completionPercent: number;
}

export function summarizeCount(lines: CountLine[]): CountSummary {
  const variances = computeVariances(lines);
  let loss = 0;
  let gain = 0;
  let matched = 0;
  let short = 0;
  let over = 0;
  for (const v of variances) {
    if (v.varianceQty === 0) matched++;
    else if (v.varianceQty < 0) {
      short++;
      loss += -v.varianceValue;
    } else {
      over++;
      gain += v.varianceValue;
    }
  }
  return {
    totalLines: lines.length,
    countedLines: variances.length,
    matchedLines: matched,
    shortLines: short,
    overLines: over,
    lossValue: round2(loss),
    gainValue: round2(gain),
    netValue: round2(gain - loss),
    completionPercent: lines.length === 0 ? 0 : Math.round((variances.length / lines.length) * 100),
  };
}

export interface CounterBreakdown {
  countedById: string;
  lines: number;
  lossValue: number;
  gainValue: number;
  netValue: number;
}

/** Variance per person who did the counting - a pattern of one person's counts always coming up short is worth a conversation. */
export function breakdownByCounter(lines: CountLine[]): CounterBreakdown[] {
  const map = new Map<string, CounterBreakdown>();
  for (const v of computeVariances(lines)) {
    const key = v.countedById ?? 'unknown';
    const row = map.get(key) ?? { countedById: key, lines: 0, lossValue: 0, gainValue: 0, netValue: 0 };
    row.lines++;
    if (v.varianceValue < 0) row.lossValue = round2(row.lossValue + -v.varianceValue);
    else row.gainValue = round2(row.gainValue + v.varianceValue);
    row.netValue = round2(row.gainValue - row.lossValue);
    map.set(key, row);
  }
  return [...map.values()].sort((a, b) => a.netValue - b.netValue);
}
