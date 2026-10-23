import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/services/coupon_rules.dart';

// Mirrors backend/src/coupons/coupons.rules.spec.ts. The till and the server
// must agree on what a coupon is worth.

Coupon coupon({
  CouponKind kind = CouponKind.percent,
  double value = 10,
  double? maxDiscount,
  double? minSpend,
  DateTime? startsAt,
  DateTime? expiresAt,
  int? usageLimit,
  int usedCount = 0,
  int? perCustomerLimit,
  String? customerId,
  List<String> productIds = const [],
}) =>
    Coupon(
      code: 'SAVE10',
      kind: kind,
      value: value,
      maxDiscount: maxDiscount,
      minSpend: minSpend,
      startsAt: startsAt,
      expiresAt: expiresAt,
      usageLimit: usageLimit,
      usedCount: usedCount,
      perCustomerLimit: perCustomerLimit,
      customerId: customerId,
      productIds: productIds,
    );

const lines = [
  CouponLine(productId: 'a', amount: 600),
  CouponLine(productId: 'b', amount: 400),
];

void main() {
  final now = DateTime(2026, 10, 24, 9);

  group('evaluateCoupon', () {
    test('takes a percentage off the whole sale', () {
      final v = evaluateCoupon(coupon(), lines, now: now);
      expect(v.ok, isTrue);
      expect(v.discount, 100.0);
    });

    test('caps a percent coupon at maxDiscount', () {
      final v = evaluateCoupon(coupon(value: 50, maxDiscount: 120), lines,
          now: now);
      expect(v.discount, 120.0);
    });

    test('gives a fixed amount but never more than the sale', () {
      expect(
          evaluateCoupon(coupon(kind: CouponKind.fixed, value: 200), lines,
                  now: now)
              .discount,
          200.0);
      expect(
          evaluateCoupon(
                  coupon(kind: CouponKind.fixed, value: 5000),
                  const [CouponLine(productId: 'a', amount: 300)],
                  now: now)
              .discount,
          300.0);
    });

    test('only discounts the listed products', () {
      final v = evaluateCoupon(coupon(productIds: ['b']), lines, now: now);
      expect(v.discount, 40.0);
      final none = evaluateCoupon(coupon(productIds: ['z']), lines, now: now);
      expect(none.ok, isFalse);
    });

    test('measures minimum spend on the whole sale', () {
      expect(
          evaluateCoupon(coupon(minSpend: 900, productIds: ['b']), lines,
                  now: now)
              .ok,
          isTrue);
      final low = evaluateCoupon(coupon(minSpend: 1500), lines, now: now);
      expect(low.ok, isFalse);
      expect(low.message, contains('1500'));
    });

    test('respects the start and end dates', () {
      expect(
          evaluateCoupon(coupon(startsAt: DateTime(2026, 11, 1)), lines,
                  now: now)
              .ok,
          isFalse);
      expect(
          evaluateCoupon(coupon(expiresAt: DateTime(2026, 10, 1)), lines,
                  now: now)
              .ok,
          isFalse);
    });

    test('refuses a used-up coupon', () {
      expect(
          evaluateCoupon(coupon(usageLimit: 5, usedCount: 5), lines, now: now)
              .ok,
          isFalse);
      expect(
          evaluateCoupon(coupon(usageLimit: 5, usedCount: 4), lines, now: now)
              .ok,
          isTrue);
    });

    test('locks a coupon to one customer', () {
      final c = coupon(customerId: 'c1');
      expect(evaluateCoupon(c, lines, now: now).ok, isFalse);
      expect(evaluateCoupon(c, lines, now: now, customerId: 'c2').ok, isFalse);
      expect(evaluateCoupon(c, lines, now: now, customerId: 'c1').ok, isTrue);
    });

    test('limits uses per customer and needs a customer to count them', () {
      final c = coupon(perCustomerLimit: 2);
      expect(evaluateCoupon(c, lines, now: now).ok, isFalse);
      expect(
          evaluateCoupon(c, lines,
                  now: now, customerId: 'c1', customerUses: 2)
              .ok,
          isFalse);
      expect(
          evaluateCoupon(c, lines,
                  now: now, customerId: 'c1', customerUses: 1)
              .ok,
          isTrue);
    });

    test('rounds to cents and ignores negative lines', () {
      final v = evaluateCoupon(coupon(value: 7.5),
          const [CouponLine(productId: 'a', amount: 333.33)],
          now: now);
      expect(v.discount, 25.0);
      final neg = evaluateCoupon(coupon(), const [
        CouponLine(productId: 'a', amount: -50),
        CouponLine(productId: 'b', amount: 200),
      ], now: now);
      expect(neg.discount, 20.0);
    });
  });

  group('spreadCouponDiscount', () {
    const three = [
      CouponLine(productId: 'a', amount: 600),
      CouponLine(productId: 'b', amount: 300),
      CouponLine(productId: 'c', amount: 100),
    ];

    test('shares in proportion and adds up exactly', () {
      expect(spreadCouponDiscount(three, const [], 100), [60.0, 30.0, 10.0]);
    });

    test('only touches the lines the coupon applies to', () {
      expect(spreadCouponDiscount(three, const ['b', 'c'], 40),
          [0.0, 30.0, 10.0]);
    });

    test('never loses a cent to rounding', () {
      final shares = spreadCouponDiscount(const [
        CouponLine(productId: 'a', amount: 100),
        CouponLine(productId: 'b', amount: 100),
        CouponLine(productId: 'c', amount: 100),
      ], const [], 100);
      final total = shares.fold<double>(0, (s, x) => s + x);
      expect((total * 100).round(), 10000);
    });

    test('gives nothing when there is nothing to spread', () {
      expect(spreadCouponDiscount(three, const [], 0), [0.0, 0.0, 0.0]);
      expect(spreadCouponDiscount(three, const ['zzz'], 50), [0.0, 0.0, 0.0]);
    });
  });

  test('normalises a typed code', () {
    expect(normaliseCouponCode('  save 10 '), 'SAVE10');
  });
}
