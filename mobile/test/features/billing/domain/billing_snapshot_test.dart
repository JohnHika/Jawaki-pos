import 'package:axon_pos/features/billing/domain/billing_snapshot.dart';
import 'package:axon_pos/features/subscription/domain/subscription_plans.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const store = BillingSnapshotStore();

  BillingSnapshot snap(DateTime at) => BillingSnapshot(
        savedAt: at,
        entitlement: const {'plan': 'CORE', 'status': 'ACTIVE'},
        plan: const {'plan': 'CORE'},
        invoices: const [
          {'id': 'inv-1'}
        ],
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('BillingSnapshot freshness', () {
    final now = DateTime(2026, 11, 15, 12);

    test('is fresh under five minutes and stale after', () {
      expect(snap(now.subtract(const Duration(minutes: 4))).isFresh(now), isTrue);
      expect(snap(now.subtract(const Duration(minutes: 6))).isFresh(now), isFalse);
    });

    test('is usable for a week and no longer', () {
      expect(snap(now.subtract(const Duration(days: 6))).isUsable(now), isTrue);
      expect(snap(now.subtract(const Duration(days: 8))).isUsable(now), isFalse);
    });
  });

  group('BillingSnapshotStore', () {
    test('round-trips what was saved', () async {
      await store.save('t1', snap(DateTime.now()));
      final loaded = await store.load('t1');
      expect(loaded, isNotNull);
      expect(loaded!.entitlement!['plan'], 'CORE');
      expect(loaded.invoices, hasLength(1));
    });

    test('keeps one copy per shop', () async {
      await store.save('t1', snap(DateTime.now()));
      expect(await store.load('t2'), isNull);
    });

    test('ignores a copy older than the hard limit', () async {
      await store.save('t1', snap(DateTime.now().subtract(const Duration(days: 9))));
      expect(await store.load('t1'), isNull);
    });

    test('ignores a copy written by another schema version', () async {
      SharedPreferences.setMockInitialValues({
        'billing_snapshot_v${BillingSnapshot.schemaVersion}_t1':
            '{"v":0,"savedAt":${DateTime.now().millisecondsSinceEpoch}}',
      });
      expect(await store.load('t1'), isNull);
    });

    test('survives a corrupt copy', () async {
      SharedPreferences.setMockInitialValues({
        'billing_snapshot_v${BillingSnapshot.schemaVersion}_t1': '{not json',
      });
      expect(await store.load('t1'), isNull);
    });
  });

  group('PlanPrices', () {
    setUp(PlanPrices.reset);

    test('shows the bundled prices, equal to the invoice prices, offline', () {
      expect(planPriceKes('core'), 3000);
      expect(planPriceKes('business'), 5000);
      expect(planPriceKes('enterprise'), 9999);
      expect(PlanPrices.isLastKnown, isTrue);
    });

    test('takes the server table and marks it live', () async {
      await PlanPrices.apply([
        {'planId': 'TRIAL', 'monthlyAmountKes': 0},
        {'planId': 'CORE', 'monthlyAmountKes': 3500},
        {'planId': 'BUSINESS', 'monthlyAmountKes': 7000},
      ]);
      expect(planPriceKes('CORE'), 3500);
      expect(kAvailablePlans.first.priceKes, 3500);
      // A plan the server did not list keeps its bundled price.
      expect(planPriceKes('enterprise'), 9999);
      expect(PlanPrices.source, PlanPriceSource.live);
    });

    test('remembers the last table and marks it saved on the next start', () async {
      await PlanPrices.apply([
        {'planId': 'CORE', 'monthlyAmountKes': 3500},
      ]);
      PlanPrices.reset();
      expect(planPriceKes('core'), 3000);

      await PlanPrices.restore();

      expect(planPriceKes('core'), 3500);
      expect(PlanPrices.source, PlanPriceSource.saved);
      expect(PlanPrices.isLastKnown, isTrue);
    });
  });
}
