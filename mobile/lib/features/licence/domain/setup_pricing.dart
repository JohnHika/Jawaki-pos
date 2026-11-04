/// What a shop pays Arche Axon for Counterbase: a one-time setup price, then a
/// monthly plan. Pure rules with no network and no payment provider, so they
/// can be tested and shown to the owner before any collection exists.
///
/// Whole shillings only. The owner set the setup price on 2026-11-04 (first
/// KES 80,000, then raised to KES 125,000).
library;

const int kSetupFeeKes = 125000;

/// The smallest first payment when the setup price is paid in parts.
const double kMinimumFirstPaymentShare = 0.25;

/// Days of free use before the first monthly invoice.
const int kTrialDays = 7;

/// Days after a due date before new sales pause.
const int kGraceDays = 3;

/// A month on the plan, for scheduling invoices.
const int kPlanMonthDays = 30;

/// Plan months included when the setup price is paid in full.
const int kFreeMonthsWhenPaidInFull = 2;

/// Monthly plan prices in KES, set by the owner on 2026-11-04.
const Map<String, int> kMonthlyPlanKes = {
  'CORE': 3000,
  'BUSINESS': 5000,
  'ENTERPRISE': 9999,
};

/// How the setup price is paid.
enum SetupPayment {
  /// All at once. The first [kFreeMonthsWhenPaidInFull] plan months are free.
  full(1),

  /// Two equal parts.
  twoParts(2),

  /// Four equal parts, the smallest allowed (a quarter each).
  fourParts(4);

  const SetupPayment(this.parts);

  final int parts;
}

/// One invoice in the schedule: what falls due on a day, split into the part of
/// the setup price and the plan month it carries.
class ScheduledInvoice {
  const ScheduledInvoice({
    required this.number,
    required this.dayOffset,
    required this.setupKes,
    required this.planKes,
  });

  /// 1 for the first invoice.
  final int number;

  /// Days after the shop started. 0 is the start day.
  final int dayOffset;
  final int setupKes;
  final int planKes;

  int get totalKes => setupKes + planKes;
}

/// The plan price for one month, or null for an unknown plan.
int? monthlyPriceFor(String plan) => kMonthlyPlanKes[plan.toUpperCase()];

/// The yearly price: pay for ten months, get twelve.
int yearlyPriceFor(int monthlyKes) => monthlyKes * 10;

/// The smallest first payment for a setup price.
int minimumFirstPaymentKes([int setupKes = kSetupFeeKes]) =>
    (setupKes * kMinimumFirstPaymentShare).ceil();

/// True when [option] keeps the first payment at or above the minimum share.
bool isAllowed(SetupPayment option, [int setupKes = kSetupFeeKes]) =>
    firstPartKes(option, setupKes) >= minimumFirstPaymentKes(setupKes);

/// The first part of the setup price for [option]. Any odd shilling from the
/// split goes here, so the parts add up exactly.
int firstPartKes(SetupPayment option, [int setupKes = kSetupFeeKes]) {
  final base = setupKes ~/ option.parts;
  return base + (setupKes - base * option.parts);
}

/// The invoices for the first [invoiceCount] billing points of a new shop.
///
/// Invoice 1 is on the start day and carries only the first part of the setup
/// price. The monthly plan starts after the trial: invoice 2 is on day
/// [kTrialDays], then every [kPlanMonthDays] days. Remaining parts of the setup
/// price ride on the invoices that follow, so a shop receives one bill at a
/// time.
List<ScheduledInvoice> buildSchedule({
  required String plan,
  required SetupPayment option,
  int setupKes = kSetupFeeKes,
  int invoiceCount = 6,
}) {
  final monthly = monthlyPriceFor(plan);
  if (monthly == null) {
    throw ArgumentError.value(plan, 'plan', 'Unknown plan.');
  }
  if (!isAllowed(option, setupKes)) {
    throw ArgumentError.value(
        option, 'option', 'The first payment would be too small.');
  }
  if (invoiceCount < 1) {
    throw ArgumentError.value(invoiceCount, 'invoiceCount', 'Must be 1 or more.');
  }

  // Split the setup price into parts that add up exactly. Any odd shilling
  // goes on the first part.
  final base = setupKes ~/ option.parts;
  final parts = List<int>.filled(option.parts, base);
  parts[0] += setupKes - base * option.parts;

  final invoices = <ScheduledInvoice>[];
  for (var i = 0; i < invoiceCount; i++) {
    final number = i + 1;
    final day = i == 0 ? 0 : kTrialDays + (i - 1) * kPlanMonthDays;

    final setupPart = i < parts.length ? parts[i] : 0;
    var planPart = 0;
    if (i >= 1) {
      final planMonth = i; // 1 for the first plan month, on day 7
      final free = option == SetupPayment.full &&
          planMonth <= kFreeMonthsWhenPaidInFull;
      planPart = free ? 0 : monthly;
    }
    invoices.add(ScheduledInvoice(
      number: number,
      dayOffset: day,
      setupKes: setupPart,
      planKes: planPart,
    ));
  }
  return invoices;
}

/// Total paid across the first [invoiceCount] invoices.
int totalOf(Iterable<ScheduledInvoice> invoices) =>
    invoices.fold(0, (sum, invoice) => sum + invoice.totalKes);

/// The first year for a plan: the setup price plus twelve plan months, or ten
/// when paid yearly.
int firstYearKes(String plan, {bool yearly = false}) {
  final monthly = monthlyPriceFor(plan);
  if (monthly == null) {
    throw ArgumentError.value(plan, 'plan', 'Unknown plan.');
  }
  return kSetupFeeKes + (yearly ? yearlyPriceFor(monthly) : monthly * 12);
}
