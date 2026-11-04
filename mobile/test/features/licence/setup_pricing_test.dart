import 'package:axon_pos/features/licence/domain/licence_standing.dart';
import 'package:axon_pos/features/licence/domain/setup_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('setup price', () {
    test('is KES 125,000 and the smallest first payment is a quarter', () {
      expect(kSetupFeeKes, 125000);
      expect(minimumFirstPaymentKes(), 31250);
    });

    test('every option keeps the first payment at or above the minimum', () {
      for (final option in SetupPayment.values) {
        expect(isAllowed(option), isTrue, reason: option.name);
      }
    });

    test('a first payment below a quarter is not allowed', () {
      // A fifth of the price would start under the 25 percent minimum.
      expect(kSetupFeeKes / 5 < minimumFirstPaymentKes(), isTrue);
    });
  });

  group('schedule', () {
    test('paying in full takes everything on day 0 and gives two months free',
        () {
      final invoices = buildSchedule(
          plan: 'CORE', option: SetupPayment.full, invoiceCount: 4);
      expect(invoices[0].setupKes, 125000);
      expect(invoices[0].totalKes, 125000);
      // Plan months 1 and 2 are free, month 3 is charged.
      expect(invoices[1].planKes, 0);
      expect(invoices[2].planKes, 0);
      expect(invoices[3].planKes, 3200);
      expect(invoices.map((i) => i.dayOffset), [0, 7, 37, 67]);
    });

    test('two parts split the price in half', () {
      final invoices = buildSchedule(
          plan: 'CORE', option: SetupPayment.twoParts, invoiceCount: 4);
      expect(invoices[0].setupKes, 62500);
      expect(invoices[1].setupKes, 62500);
      expect(invoices[1].planKes, 3200);
      expect(invoices[2].setupKes, 0);
      expect(invoices[2].planKes, 3200);
    });

    test('four parts: a quarter each, with the plan month riding along', () {
      final invoices = buildSchedule(
          plan: 'CORE', option: SetupPayment.fourParts, invoiceCount: 5);
      expect(invoices.map((i) => i.setupKes), [31250, 31250, 31250, 31250, 0]);
      expect(invoices.map((i) => i.planKes), [0, 3200, 3200, 3200, 3200]);
      // First four invoices: the setup price plus three plan months.
      expect(totalOf(invoices.take(4)), 134600);
    });

    test('parts always add up to the setup price exactly', () {
      for (final option in SetupPayment.values) {
        final invoices =
            buildSchedule(plan: 'BUSINESS', option: option, invoiceCount: 6);
        expect(invoices.fold<int>(0, (s, i) => s + i.setupKes), 125000,
            reason: option.name);
      }
    });

    test('an odd price puts the spare shilling on the first part', () {
      final invoices = buildSchedule(
        plan: 'CORE',
        option: SetupPayment.fourParts,
        setupKes: 100003,
        invoiceCount: 4,
      );
      expect(invoices.fold<int>(0, (s, i) => s + i.setupKes), 100003);
      expect(invoices[0].setupKes, 25003);
    });

    test('an unknown plan is refused', () {
      expect(
        () => buildSchedule(plan: 'GOLD', option: SetupPayment.full),
        throwsArgumentError,
      );
    });
  });

  group('prices', () {
    test('yearly means pay for ten months', () {
      expect(yearlyPriceFor(3200), 32000);
      expect(yearlyPriceFor(6500), 65000);
      expect(yearlyPriceFor(10000), 100000);
    });

    test('first year with setup', () {
      expect(firstYearKes('CORE'), 125000 + 38400);
      expect(firstYearKes('CORE', yearly: true), 157000);
      expect(firstYearKes('BUSINESS'), 203000);
      expect(firstYearKes('ENTERPRISE', yearly: true), 225000);
    });
  });

  group('standing', () {
    final start = DateTime(2026, 11, 4, 9);

    test('before the first payment and inside the trial', () {
      final due = start.add(const Duration(days: kTrialDays));
      final s = standingFor(
          everPaid: false, dueAt: due, now: start.add(const Duration(days: 2)));
      expect(s.status, LicenceStatus.trial);
      expect(s.daysLeft, 5);
      expect(s.canSell, isTrue);
    });

    test('paid up is active', () {
      final due = start.add(const Duration(days: 30));
      final s = standingFor(everPaid: true, dueAt: due, now: start);
      expect(s.status, LicenceStatus.active);
      expect(s.canSell, isTrue);
    });

    test('a late payment gets three days of grace and everything still works',
        () {
      final due = start;
      final s = standingFor(
          everPaid: true, dueAt: due, now: due.add(const Duration(days: 1)));
      expect(s.status, LicenceStatus.grace);
      expect(s.daysLeft, 2);
      expect(s.canSell, isTrue);
    });

    test('after grace new sales pause, but records stay open', () {
      final due = start;
      final s = standingFor(
          everPaid: true, dueAt: due, now: due.add(const Duration(days: 3)));
      expect(s.status, LicenceStatus.salesPaused);
      expect(s.canSell, isFalse);
      expect(s.canViewAndExport, isTrue);
    });

    test('an unpaid trial that ran out follows the same grace', () {
      final due = start.add(const Duration(days: kTrialDays));
      final late = standingFor(
          everPaid: false, dueAt: due, now: due.add(const Duration(days: 10)));
      expect(late.status, LicenceStatus.salesPaused);
      expect(late.canViewAndExport, isTrue);
    });
  });
}
