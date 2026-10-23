/**
 * Coupon rules as pure functions, so the server and the phone's offline till
 * apply exactly the same maths (the Dart port lives in mobile
 * `core/services/coupon_rules.dart`).
 */

export type CouponKindValue = 'PERCENT' | 'FIXED';

export interface CouponDef {
  code: string;
  kind: CouponKindValue;
  /** Percent (0-100) or a flat KES amount, depending on `kind`. */
  value: number;
  maxDiscount: number | null;
  minSpend: number | null;
  startsAt: Date | null;
  expiresAt: Date | null;
  usageLimit: number | null;
  usedCount: number;
  perCustomerLimit: number | null;
  customerId: string | null;
  /** Empty = the whole sale. */
  productIds: string[];
  isActive: boolean;
}

export interface CouponLine {
  productId: string;
  /** Line value before the coupon: unitPrice x quantity - line discount. */
  amount: number;
}

export interface CouponContext {
  now: Date;
  customerId?: string | null;
  /** How many times this customer has already used the code. */
  customerUses: number;
  lines: CouponLine[];
}

export type CouponRefusalReason =
  | 'NOT_FOUND'
  | 'INACTIVE'
  | 'NOT_STARTED'
  | 'EXPIRED'
  | 'USED_UP'
  | 'WRONG_CUSTOMER'
  | 'NEEDS_CUSTOMER'
  | 'CUSTOMER_LIMIT'
  | 'MIN_SPEND'
  | 'NOTHING_ELIGIBLE';

/**
 * Flat on purpose: this project does not compile with strictNullChecks, where
 * TypeScript cannot narrow a union on a boolean flag.
 */
export interface CouponVerdict {
  ok: boolean;
  discount: number;
  eligibleAmount: number;
  reason: CouponRefusalReason | null;
  message: string | null;
}

export const round2 = (value: number): number => Math.round((value + Number.EPSILON) * 100) / 100;

export const normaliseCouponCode = (value: string): string =>
  value.trim().toUpperCase().replace(/\s+/g, '');

const refuse = (reason: CouponRefusalReason, message: string): CouponVerdict => ({
  ok: false,
  discount: 0,
  eligibleAmount: 0,
  reason,
  message,
});

export function evaluateCoupon(def: CouponDef, ctx: CouponContext): CouponVerdict {
  if (!def.isActive) return refuse('INACTIVE', 'This coupon is switched off.');
  if (def.startsAt && ctx.now < def.startsAt) {
    return refuse('NOT_STARTED', 'This coupon is not active yet.');
  }
  if (def.expiresAt && ctx.now > def.expiresAt) {
    return refuse('EXPIRED', 'This coupon has expired.');
  }
  if (def.usageLimit != null && def.usedCount >= def.usageLimit) {
    return refuse('USED_UP', 'This coupon has been used up.');
  }
  if (def.customerId) {
    if (!ctx.customerId) {
      return refuse('NEEDS_CUSTOMER', 'This coupon is for one customer. Pick the customer first.');
    }
    if (ctx.customerId !== def.customerId) {
      return refuse('WRONG_CUSTOMER', 'This coupon belongs to a different customer.');
    }
  }
  if (def.perCustomerLimit != null) {
    if (!ctx.customerId) {
      return refuse('NEEDS_CUSTOMER', 'Pick the customer first. This coupon is limited per customer.');
    }
    if (ctx.customerUses >= def.perCustomerLimit) {
      return refuse('CUSTOMER_LIMIT', 'This customer has already used this coupon the most times allowed.');
    }
  }

  const saleAmount = ctx.lines.reduce((sum, line) => sum + Math.max(line.amount, 0), 0);
  if (def.minSpend != null && saleAmount < def.minSpend) {
    return refuse('MIN_SPEND', `Spend at least KES ${Math.ceil(def.minSpend)} to use this coupon.`);
  }

  const eligibleAmount =
    def.productIds.length === 0
      ? saleAmount
      : ctx.lines
          .filter((line) => def.productIds.includes(line.productId))
          .reduce((sum, line) => sum + Math.max(line.amount, 0), 0);
  if (eligibleAmount <= 0) {
    return refuse('NOTHING_ELIGIBLE', 'None of the items in this sale qualify for the coupon.');
  }

  let discount =
    def.kind === 'PERCENT' ? (eligibleAmount * Math.min(Math.max(def.value, 0), 100)) / 100 : def.value;
  if (def.maxDiscount != null) discount = Math.min(discount, def.maxDiscount);
  discount = round2(Math.min(discount, eligibleAmount));
  if (discount <= 0) return refuse('NOTHING_ELIGIBLE', 'This coupon gives no discount on this sale.');

  return { ok: true, discount, eligibleAmount: round2(eligibleAmount), reason: null, message: null };
}

/**
 * Shares a coupon's discount across the lines it applies to, in proportion to
 * their value, so the price guard can see the real price each item sold at.
 * Returns one share per line (zero for lines the coupon does not touch); the
 * shares add up to exactly `discount`.
 */
export function spreadCouponDiscount(
  lines: CouponLine[],
  productIds: string[],
  discount: number,
): number[] {
  const eligible = lines.map((line) => (productIds.length === 0 || productIds.includes(line.productId) ? Math.max(line.amount, 0) : 0));
  const base = eligible.reduce((sum, amount) => sum + amount, 0);
  const shares = lines.map(() => 0);
  if (base <= 0 || discount <= 0) return shares;
  let given = 0;
  let last = -1;
  eligible.forEach((amount, i) => {
    if (amount <= 0) return;
    shares[i] = round2((discount * amount) / base);
    given += shares[i];
    last = i;
  });
  // Whatever rounding left over goes on the last eligible line.
  if (last >= 0) shares[last] = round2(shares[last] + (discount - given));
  return shares;
}

/** Short description for lists: "10% off", "KES 200 off". */
export function describeCoupon(def: Pick<CouponDef, 'kind' | 'value' | 'maxDiscount'>): string {
  const value = Number.isInteger(def.value) ? String(def.value) : def.value.toFixed(2);
  const base = def.kind === 'PERCENT' ? `${value}% off` : `KES ${value} off`;
  return def.kind === 'PERCENT' && def.maxDiscount != null
    ? `${base} (max KES ${Math.round(def.maxDiscount)})`
    : base;
}
