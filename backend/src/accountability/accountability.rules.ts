import { AccountabilitySettings } from './accountability.settings';

export type Severity = 'LOW' | 'MEDIUM' | 'HIGH';

export interface Violation {
  code:
    | 'BELOW_COST'
    | 'BELOW_FLOOR'
    | 'DISCOUNT_LIMIT'
    | 'CREDIT_NO_CUSTOMER'
    | 'CREDIT_LIMIT_EXCEEDED'
    | 'CREDIT_OVERDUE';
  severity: Severity;
  message: string;
  productId?: string;
  /** True when a user without the matching override permission may be refused. */
  blockable: boolean;
  data?: Record<string, unknown>;
}

export interface SaleLineInput {
  productId: string;
  name: string;
  quantity: number;
  /** Price per base unit as sent by the till. */
  unitPrice: number;
  /** Discount taken off this whole line (KES). */
  discount: number;
  /**
   * Discount the owner has already approved for this line, e.g. its share of a
   * coupon. It lowers the price the item really sold at (so selling below cost
   * is still caught) but does not count against the cashier's discount limit.
   */
  approvedDiscount?: number;
  costPrice: number | null;
  minPrice: number | null;
}

export interface SaleAssessmentInput {
  lines: SaleLineInput[];
  /** Sale-level discount on top of line discounts (KES). */
  overallDiscount: number;
  settings: AccountabilitySettings;
  /** Holds `sales.discount` (supervisor and above by default). */
  canDiscount: boolean;
  /** Holds `sales.price_override`. */
  canOverridePrice: boolean;
}

const money = (n: number) => `KES ${Math.round(n).toLocaleString('en-KE')}`;
const round2 = (n: number) => Math.round(n * 100) / 100;

/**
 * Checks a sale's prices and discounts against the company's rules.
 * Pure: no database, so it is trivially testable and cheap to run on every sale.
 */
export function assessSalePricing(input: SaleAssessmentInput): Violation[] {
  const { settings } = input;
  if (settings.priceGuard.mode === 'OFF') return [];

  const violations: Violation[] = [];
  let gross = 0;
  let lineDiscounts = 0;

  for (const line of input.lines) {
    gross += line.unitPrice * line.quantity;
    lineDiscounts += line.discount;

    if (line.quantity <= 0) continue;
    const netUnit =
      (line.unitPrice * line.quantity - line.discount - (line.approvedDiscount ?? 0)) / line.quantity;
    const cost = line.costPrice && line.costPrice > 0 ? line.costPrice : 0;
    const marginFloor = cost > 0 ? cost * (1 + settings.priceGuard.minMarginPercent / 100) : 0;
    const floor = Math.max(line.minPrice ?? 0, marginFloor);

    if (cost > 0 && netUnit < cost) {
      violations.push({
        code: 'BELOW_COST',
        severity: 'HIGH',
        productId: line.productId,
        blockable: !input.canOverridePrice,
        message: `${line.name} sold at ${money(netUnit)} each, below its cost of ${money(cost)}`,
        data: { netUnitPrice: round2(netUnit), costPrice: cost, quantity: line.quantity },
      });
    } else if (floor > 0 && netUnit < floor) {
      violations.push({
        code: 'BELOW_FLOOR',
        severity: 'MEDIUM',
        productId: line.productId,
        blockable: !input.canOverridePrice,
        message: `${line.name} sold at ${money(netUnit)} each, below its minimum price of ${money(floor)}`,
        data: { netUnitPrice: round2(netUnit), floorPrice: round2(floor), quantity: line.quantity },
      });
    }
  }

  const totalDiscount = lineDiscounts + Math.max(input.overallDiscount, 0);
  if (gross > 0 && totalDiscount > 0) {
    const percent = (totalDiscount / gross) * 100;
    if (!input.canDiscount && percent > settings.priceGuard.maxCashierDiscountPercent) {
      violations.push({
        code: 'DISCOUNT_LIMIT',
        severity: percent >= 25 ? 'HIGH' : 'MEDIUM',
        blockable: true,
        message: `Discount of ${money(totalDiscount)} (${percent.toFixed(1)}%) is over the ${settings.priceGuard.maxCashierDiscountPercent}% limit`,
        data: { discountAmount: round2(totalDiscount), discountPercent: round2(percent) },
      });
    }
  }

  return violations;
}

export interface CreditAssessmentInput {
  /** The part of the sale that goes on credit (KES). 0 = not a credit sale. */
  creditAmount: number;
  hasCustomer: boolean;
  customerName?: string;
  /** The customer's own limit; null falls back to the company default. */
  customerLimit: number | null;
  /** What the customer already owes. */
  outstanding: number;
  /** Days the oldest unpaid balance is past due (0 = nothing overdue). */
  oldestOverdueDays: number;
  settings: AccountabilitySettings;
}

export function assessCredit(input: CreditAssessmentInput): Violation[] {
  const { settings } = input;
  if (settings.credit.mode === 'OFF' || input.creditAmount <= 0) return [];

  if (!input.hasCustomer) {
    return [
      {
        code: 'CREDIT_NO_CUSTOMER',
        severity: 'HIGH',
        blockable: true,
        message: `${money(input.creditAmount)} given on credit with no customer attached — nobody is on record as owing it`,
        data: { creditAmount: round2(input.creditAmount) },
      },
    ];
  }

  const violations: Violation[] = [];
  const who = input.customerName ?? 'Customer';
  const limit = input.customerLimit ?? settings.credit.defaultLimit;

  if (limit !== null && limit !== undefined) {
    const after = input.outstanding + input.creditAmount;
    if (after > limit) {
      violations.push({
        code: 'CREDIT_LIMIT_EXCEEDED',
        severity: 'HIGH',
        blockable: true,
        message: `${who} would owe ${money(after)}, over their ${money(limit)} credit limit`,
        data: {
          creditAmount: round2(input.creditAmount),
          outstanding: round2(input.outstanding),
          limit: round2(limit),
        },
      });
    }
  }

  const overdueAfter = settings.credit.blockWhenOverdueDays;
  if (overdueAfter !== null && input.oldestOverdueDays >= overdueAfter) {
    violations.push({
      code: 'CREDIT_OVERDUE',
      severity: 'HIGH',
      blockable: true,
      message: `${who} has a balance ${input.oldestOverdueDays} days overdue and is still being given credit`,
      data: { overdueDays: input.oldestOverdueDays },
    });
  }

  return violations;
}

/** Severity of a void/refund of `amount` given the company thresholds. */
export function severityForAmount(amount: number, threshold: number): Severity {
  if (threshold > 0 && amount >= threshold) return 'HIGH';
  return amount >= threshold / 2 && threshold > 0 ? 'MEDIUM' : 'LOW';
}

/** Percentage change from `before` to `after`; null when there is no base. */
export function percentChange(before: number, after: number): number | null {
  if (!Number.isFinite(before) || before <= 0 || !Number.isFinite(after)) return null;
  return ((after - before) / before) * 100;
}
