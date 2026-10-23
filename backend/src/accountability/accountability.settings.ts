/**
 * Per-company accountability rules. Stored under `tenant.settings.accountability`
 * (JSON, no migration) the same way the licence settings are.
 *
 * Defaults are deliberately gentle: every check starts in FLAG mode, which
 * records an alert and an audit entry but never refuses a sale. A company
 * switches a check to BLOCK once its staff are used to the rules.
 */
export type GuardMode = 'OFF' | 'FLAG' | 'BLOCK';

export interface AccountabilitySettings {
  priceGuard: {
    mode: GuardMode;
    /** Extra margin required on top of cost, e.g. 5 = never sell under cost + 5%. */
    minMarginPercent: number;
    /** Largest discount (% of the sale) a user without `sales.discount` may give. */
    maxCashierDiscountPercent: number;
  };
  credit: {
    mode: GuardMode;
    /** Limit applied to customers with no limit of their own. null = unlimited. */
    defaultLimit: number | null;
    /** Refuse new credit to a customer with a balance overdue by this many days. null = off. */
    blockWhenOverdueDays: number | null;
  };
  alerts: {
    /** Push HIGH alerts to the owner straight away. */
    pushHigh: boolean;
    /** Void / refund at or above this amount (KES) is HIGH severity. */
    voidAlertAmount: number;
    refundAlertAmount: number;
    /** Stock written off (at cost) at or above this value is HIGH severity. */
    stockWriteOffValue: number;
    /** Till short by this much or more at close is HIGH severity. */
    cashShortAmount: number;
    /** Product price / cost moved by this % or more is flagged. */
    priceChangePercent: number;
    /** Stocktake loss (at cost) at or above this value is HIGH severity. */
    stocktakeVarianceValue: number;
  };
  dailySummary: {
    enabled: boolean;
    /** Local hour (0-23, branch timezone) the owner's summary is sent. */
    hourLocal: number;
  };
  stocktake: {
    /** The person who submitted a count may not also approve it. */
    separateApprover: boolean;
  };
}

export const DEFAULT_ACCOUNTABILITY_SETTINGS: AccountabilitySettings = {
  priceGuard: { mode: 'FLAG', minMarginPercent: 0, maxCashierDiscountPercent: 5 },
  credit: { mode: 'FLAG', defaultLimit: null, blockWhenOverdueDays: null },
  alerts: {
    pushHigh: true,
    voidAlertAmount: 1000,
    refundAlertAmount: 1000,
    stockWriteOffValue: 1000,
    cashShortAmount: 200,
    priceChangePercent: 10,
    stocktakeVarianceValue: 2000,
  },
  dailySummary: { enabled: true, hourLocal: 19 },
  stocktake: { separateApprover: true },
};

const MODES: GuardMode[] = ['OFF', 'FLAG', 'BLOCK'];

function num(value: unknown, fallback: number, min: number, max: number): number {
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(Math.max(n, min), max);
}

function nullableNum(value: unknown, fallback: number | null, min: number, max: number) {
  if (value === null) return null;
  if (value === undefined) return fallback;
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(Math.max(n, min), max);
}

function mode(value: unknown, fallback: GuardMode): GuardMode {
  return MODES.includes(value as GuardMode) ? (value as GuardMode) : fallback;
}

/**
 * Merges stored (or patched) settings over the defaults, clamping every
 * number so a bad value in the JSON can never switch a rule into nonsense.
 */
export function resolveAccountabilitySettings(raw: unknown): AccountabilitySettings {
  const d = DEFAULT_ACCOUNTABILITY_SETTINGS;
  const r = (raw && typeof raw === 'object' ? raw : {}) as Record<string, any>;
  const pg = r.priceGuard ?? {};
  const cr = r.credit ?? {};
  const al = r.alerts ?? {};
  const ds = r.dailySummary ?? {};
  const st = r.stocktake ?? {};

  return {
    priceGuard: {
      mode: mode(pg.mode, d.priceGuard.mode),
      minMarginPercent: num(pg.minMarginPercent, d.priceGuard.minMarginPercent, 0, 500),
      maxCashierDiscountPercent: num(
        pg.maxCashierDiscountPercent,
        d.priceGuard.maxCashierDiscountPercent,
        0,
        100,
      ),
    },
    credit: {
      mode: mode(cr.mode, d.credit.mode),
      defaultLimit: nullableNum(cr.defaultLimit, d.credit.defaultLimit, 0, 100_000_000),
      blockWhenOverdueDays: nullableNum(cr.blockWhenOverdueDays, d.credit.blockWhenOverdueDays, 1, 3650),
    },
    alerts: {
      pushHigh: typeof al.pushHigh === 'boolean' ? al.pushHigh : d.alerts.pushHigh,
      voidAlertAmount: num(al.voidAlertAmount, d.alerts.voidAlertAmount, 0, 100_000_000),
      refundAlertAmount: num(al.refundAlertAmount, d.alerts.refundAlertAmount, 0, 100_000_000),
      stockWriteOffValue: num(al.stockWriteOffValue, d.alerts.stockWriteOffValue, 0, 100_000_000),
      cashShortAmount: num(al.cashShortAmount, d.alerts.cashShortAmount, 0, 100_000_000),
      priceChangePercent: num(al.priceChangePercent, d.alerts.priceChangePercent, 0, 1000),
      stocktakeVarianceValue: num(
        al.stocktakeVarianceValue,
        d.alerts.stocktakeVarianceValue,
        0,
        100_000_000,
      ),
    },
    dailySummary: {
      enabled: typeof ds.enabled === 'boolean' ? ds.enabled : d.dailySummary.enabled,
      hourLocal: Math.trunc(num(ds.hourLocal, d.dailySummary.hourLocal, 0, 23)),
    },
    stocktake: {
      separateApprover:
        typeof st.separateApprover === 'boolean' ? st.separateApprover : d.stocktake.separateApprover,
    },
  };
}
