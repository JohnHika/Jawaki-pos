import 'package:aca/core/theme.dart';
import 'package:aca/data/models.dart';
import 'package:aca/features/overview/overview_logic.dart';
import 'package:aca/features/tenants/tenants_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('greeting', () {
    test('changes with the hour', () {
      expect(greetingFor(DateTime(2026, 10, 21, 5)), 'Good morning');
      expect(greetingFor(DateTime(2026, 10, 21, 11, 59)), 'Good morning');
      expect(greetingFor(DateTime(2026, 10, 21, 12)), 'Good afternoon');
      expect(greetingFor(DateTime(2026, 10, 21, 16, 59)), 'Good afternoon');
      expect(greetingFor(DateTime(2026, 10, 21, 17)), 'Good evening');
      expect(greetingFor(DateTime(2026, 10, 21, 23, 30)), 'Good evening');
      expect(greetingFor(DateTime(2026, 10, 21, 2)), 'Good evening');
    });

    test('uses the first name only, and copes with a missing name', () {
      expect(firstNameOf('Amina Wanjiku'), 'Amina');
      expect(firstNameOf('  Otieno  '), 'Otieno');
      expect(firstNameOf(''), isNull);
      expect(firstNameOf(null), isNull);
      expect(greetingLine('Amina Wanjiku', DateTime(2026, 1, 1, 9)), 'Good morning, Amina');
      expect(greetingLine(null, DateTime(2026, 1, 1, 9)), 'Good morning');
    });
  });

  group('revenue delta', () {
    test('formats sign and precision', () {
      expect(formatDelta(12.4), '+12%');
      expect(formatDelta(-91.623), '−92%');
      expect(formatDelta(3.46), '+3.5%');
      expect(formatDelta(-0.5), '−0.5%');
      expect(formatDelta(0), '0%');
      expect(formatDelta(0.01), '0%');
      expect(formatDelta(25000), '+999%+');
    });

    test('is green up, red down, neutral flat', () {
      expect(deltaTone(5), Tone.success);
      expect(deltaTone(-5), Tone.danger);
      expect(deltaTone(0), Tone.neutral);
    });

    test('Overview.collectedChangePct is null without a baseline (chip hidden)', () {
      Overview ov(num now, num prev) => Overview.fromJson({
            'revenue': {'collectedLast30DaysKes': now, 'collectedPrevious30DaysKes': prev},
          });
      expect(ov(5000, 0).collectedChangePct, isNull);
      expect(ov(0, 0).collectedChangePct, isNull);
      expect(ov(3200, 38200).collectedChangePct, closeTo(-91.62, 0.01));
      expect(ov(6000, 3000).collectedChangePct, closeTo(100, 0.001));
    });
  });

  group('status tiles', () {
    test('every tile maps to a status the Clients filter accepts', () {
      for (final t in kOverviewStatusTiles) {
        expect(normalizeStatus(t.status), t.status, reason: t.label);
        expect(statusFilterLabel(t.status), t.label);
      }
    });
  });

  group('chart scale', () {
    test('rounds the ceiling to a nice number', () {
      final a = niceAxis(38200);
      expect(a.max, 40000);
      expect(a.interval, 10000);
      final b = niceAxis(3200);
      expect(b.max, 4000);
      expect(b.interval, 1000);
      final c = niceAxis(1200000);
      expect(c.max, 1500000);
      expect(c.interval, 500000);
    });

    test('always covers the largest value with at most ~5 grid lines', () {
      for (final v in [1, 7, 99, 450, 1234, 9999, 38200, 250000, 4800000]) {
        final a = niceAxis(v);
        expect(a.max, greaterThanOrEqualTo(v), reason: '$v');
        expect(a.max / a.interval, lessThanOrEqualTo(5.0001), reason: '$v');
        expect(a.interval, greaterThan(0));
      }
    });

    test('degenerate input still yields a usable axis', () {
      expect(niceAxis(0).max, 1);
      expect(niceAxis(-5).interval, 1);
      expect(niceAxis(double.nan).max, 1);
    });

    test('compact axis labels', () {
      expect(compactAmount(0), '0');
      expect(compactAmount(500), '500');
      expect(compactAmount(2500), '2.5K');
      expect(compactAmount(40000), '40K');
      expect(compactAmount(1200000), '1.2M');
      expect(compactAmount(-1500), '−1.5K');
    });

    test('hasRevenue is false for an all-zero (or empty) series', () {
      final zero = List.generate(6, (i) => MonthRevenue(month: '2026-0${i + 1}', amountKes: 0));
      expect(hasRevenue(zero), isFalse);
      expect(hasRevenue(const []), isFalse);
      expect(hasRevenue([...zero, MonthRevenue(month: '2026-07', amountKes: 1)]), isTrue);
      expect(revenueTotal([MonthRevenue(month: '2026-07', amountKes: 3200), MonthRevenue(month: '2026-08', amountKes: 38200)]), 41400);
    });
  });

  group('app version breakdown', () {
    test('sorts by devices, flags the latest and counts devices behind it', () {
      final b = versionBreakdown({'1.0.72': 5, '1.0.74': 2, '1.0.9': 1, 'unknown': 1});
      expect(b.latest, '1.0.74');
      expect(b.shown.map((s) => s.version).toList(), ['1.0.72', '1.0.74', '1.0.9', 'unknown']);
      expect(b.shown.first.fraction, 1.0);
      expect(b.shown[1].fraction, closeTo(0.4, 1e-9));
      expect(b.shown.where((s) => s.latest).single.version, '1.0.74');
      // 1.0.72 (5) and 1.0.9 (1) are behind; "unknown" is never counted as behind.
      expect(b.behindLatest, 6);
    });

    test('folds the long tail into one row', () {
      final b = versionBreakdown({for (var i = 1; i <= 9; i++) '1.0.$i': i}, limit: 4);
      expect(b.shown.length, 4);
      expect(b.otherVersions, 5);
      expect(b.otherDevices, 1 + 2 + 3 + 4 + 5);
    });

    test('handles an empty fleet', () {
      final b = versionBreakdown({});
      expect(b.shown, isEmpty);
      expect(b.latest, isNull);
      expect(b.behindLatest, 0);
      expect(activePercent(0, 0), isNull);
      expect(activePercent(3, 4), 75);
      expect(activePercent(9, 4), 100);
    });
  });
}
