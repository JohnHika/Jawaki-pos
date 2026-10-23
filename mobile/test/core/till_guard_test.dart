import 'package:axon_pos/core/services/till_guard.dart';
import 'package:axon_pos/core/services/till_rules_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TillRules rules({
  GuardMode priceMode = GuardMode.block,
  GuardMode creditMode = GuardMode.block,
  bool canDiscount = false,
  bool canOverridePrice = false,
  bool canOverrideCredit = false,
  double? defaultCreditLimit,
  int? overdueDays,
  Map<String, ProductFloor>? floors,
}) =>
    TillRules(
      priceMode: priceMode,
      maxCashierDiscountPercent: 5,
      creditMode: creditMode,
      defaultCreditLimit: defaultCreditLimit,
      blockWhenOverdueDays: overdueDays,
      canDiscount: canDiscount,
      canOverridePrice: canOverridePrice,
      canOverrideCredit: canOverrideCredit,
      floors: floors ?? {'p1': const ProductFloor(cost: 300, floor: 330)},
      generatedAt: DateTime.now(),
    );

GuardLine line({double price = 500, double discount = 0, num qty = 2}) =>
    GuardLine(
      productId: 'p1',
      name: 'Sufuria',
      quantity: qty,
      unitPrice: price,
      discount: discount,
    );

void main() {
  group('assessPricing', () {
    test('lets an ordinary sale through', () {
      expect(assessPricing(rules(), [line()]), isEmpty);
    });

    test('blocks a sale below cost for a cashier', () {
      final issues = assessPricing(rules(), [line(price: 250)]);
      expect(issues.single.code, 'BELOW_COST');
      expect(issues.single.blocking, isTrue);
      expect(issues.single.severity, GuardSeverity.high);
    });

    test('does not block below-cost for someone who may override the price',
        () {
      final issues =
          assessPricing(rules(canOverridePrice: true), [line(price: 250)]);
      expect(issues.single.code, 'BELOW_COST');
      expect(issues.single.blocking, isFalse);
    });

    test('warns without blocking in FLAG mode', () {
      final issues =
          assessPricing(rules(priceMode: GuardMode.flag), [line(price: 250)]);
      expect(issues.single.blocking, isFalse);
    });

    test('treats a price between cost and the floor as a lesser issue', () {
      final issues = assessPricing(rules(), [line(price: 320)]);
      expect(issues.single.code, 'BELOW_FLOOR');
      expect(issues.single.severity, GuardSeverity.medium);
    });

    test('counts the line discount when judging the price', () {
      // 2 x 500 less a 450 discount is 275 each: under the 300 cost.
      final issues = assessPricing(
          rules(canDiscount: true), [line(discount: 450)]);
      expect(issues.single.code, 'BELOW_COST');
    });

    test('flags a cashier discount over the limit but not a manager one', () {
      // 150 off 1000 is 15%.
      expect(assessPricing(rules(), [line(discount: 150)]).single.code,
          'DISCOUNT_LIMIT');
      expect(
          assessPricing(rules(canDiscount: true), [line(discount: 150)]),
          isEmpty);
    });

    test('adds the cart-level discount to the line discounts', () {
      final issues =
          assessPricing(rules(), [line(discount: 30)], cartDiscount: 40);
      expect(issues.single.code, 'DISCOUNT_LIMIT');
    });

    test('a coupon share can push a sale below cost without tripping the discount limit',
        () {
      // 2 x 500 = 1000. A 450 coupon share leaves 275 each, under the 300 cost.
      const l = GuardLine(
        productId: 'p1',
        name: 'Sufuria',
        quantity: 2,
        unitPrice: 500,
        discount: 0,
        approvedDiscount: 450,
      );
      final issues = assessPricing(rules(), [l]);
      expect(issues.map((i) => i.code).toList(), ['BELOW_COST']);
    });

    test('a coupon share that keeps the price above cost raises nothing', () {
      const l = GuardLine(
        productId: 'p1',
        name: 'Sufuria',
        quantity: 2,
        unitPrice: 500,
        discount: 0,
        approvedDiscount: 100,
      );
      expect(assessPricing(rules(), [l]), isEmpty);
    });

    test('does nothing when the guard is off or the product has no floor', () {
      expect(
          assessPricing(rules(priceMode: GuardMode.off), [line(price: 1)]),
          isEmpty);
      expect(assessPricing(rules(floors: {}), [line(price: 1)]), isEmpty);
    });
  });

  group('assessCreditSale', () {
    test('is silent for a sale that is not on credit', () {
      expect(
          assessCreditSale(rules(),
              creditAmount: 0, hasCustomer: false),
          isEmpty);
    });

    test('flags credit with no customer', () {
      final issues = assessCreditSale(rules(),
          creditAmount: 1000, hasCustomer: false);
      expect(issues.single.code, 'CREDIT_NO_CUSTOMER');
      expect(issues.single.blocking, isTrue);
    });

    test('flags credit over the customer limit', () {
      final issues = assessCreditSale(
        rules(),
        creditAmount: 1000,
        hasCustomer: true,
        customerName: 'Mama Njeri',
        standing: const CreditStanding(
            limit: 5000, outstanding: 4500, oldestOverdueDays: 0),
      );
      expect(issues.single.code, 'CREDIT_LIMIT_EXCEEDED');
      expect(issues.single.message, contains('Mama Njeri'));
    });

    test('falls back to the company default limit', () {
      final issues = assessCreditSale(
        rules(defaultCreditLimit: 2000),
        creditAmount: 1000,
        hasCustomer: true,
        standing: const CreditStanding(
            limit: null, outstanding: 1500, oldestOverdueDays: 0),
      );
      expect(issues.single.code, 'CREDIT_LIMIT_EXCEEDED');
    });

    test('lets credit through when offline (no standing known)', () {
      expect(
          assessCreditSale(rules(),
              creditAmount: 1000, hasCustomer: true),
          isEmpty);
    });

    test('flags credit to a customer long overdue', () {
      final issues = assessCreditSale(
        rules(overdueDays: 30),
        creditAmount: 100,
        hasCustomer: true,
        standing: const CreditStanding(
            limit: null, outstanding: 0, oldestOverdueDays: 45),
      );
      expect(issues.single.code, 'CREDIT_OVERDUE');
    });

    test('a credit override lifts the block but keeps the flag', () {
      final issues = assessCreditSale(
        rules(canOverrideCredit: true),
        creditAmount: 1000,
        hasCustomer: false,
      );
      expect(issues.single.blocking, isFalse);
    });
  });

  group('TillRules', () {
    test('round-trips through JSON, including floors', () {
      final original = rules(defaultCreditLimit: 2500, overdueDays: 21);
      final copy = TillRules.fromJson(original.toJson());
      expect(copy.priceMode, GuardMode.block);
      expect(copy.defaultCreditLimit, 2500);
      expect(copy.blockWhenOverdueDays, 21);
      expect(copy.floors['p1']!.floor, 330);
    });

    test('reads the server shape and tolerates missing sections', () {
      final r = TillRules.fromJson({
        'priceGuard': {'mode': 'BLOCK', 'maxCashierDiscountPercent': 10},
        'can': {'overridePrice': true},
        'floors': [
          {'productId': 'a', 'cost': 100, 'floor': 110},
          {'cost': 1}, // no id: ignored
        ],
      });
      expect(r.priceMode, GuardMode.block);
      expect(r.maxCashierDiscountPercent, 10);
      expect(r.canOverridePrice, isTrue);
      expect(r.creditMode, GuardMode.flag); // default
      expect(r.floors.keys, ['a']);
    });
  });

  group('TillRulesCache', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('keeps rules across a restart', () async {
      final first = TillRulesCache();
      await first.save(rules(overdueDays: 14));
      final second = TillRulesCache(); // fresh instance = app restart
      final loaded = await second.load();
      expect(loaded?.blockWhenOverdueDays, 14);
      expect(second.isStale, isFalse);
    });

    test('is stale when empty, and after clear', () async {
      final cache = TillRulesCache();
      expect(cache.isStale, isTrue);
      await cache.save(rules());
      await cache.clear();
      expect(cache.isStale, isTrue);
      expect(await TillRulesCache().load(), isNull);
    });
  });
}
