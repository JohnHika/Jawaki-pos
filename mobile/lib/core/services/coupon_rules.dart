// Coupon rules as pure functions. A port of the server's `coupons.rules.ts`:
// the till applies a coupon with no signal using this, and the server runs the
// same maths again when the sale syncs. Keep the two in step.

enum CouponKind { percent, fixed }

class Coupon {
  const Coupon({
    required this.code,
    required this.kind,
    required this.value,
    this.maxDiscount,
    this.minSpend,
    this.startsAt,
    this.expiresAt,
    this.usageLimit,
    this.usedCount = 0,
    this.perCustomerLimit,
    this.customerId,
    this.productIds = const [],
    this.description = '',
  });

  final String code;
  final CouponKind kind;
  final double value;
  final double? maxDiscount;
  final double? minSpend;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? usageLimit;
  final int usedCount;
  final int? perCustomerLimit;
  final String? customerId;

  /// Empty means the whole sale.
  final List<String> productIds;
  final String description;

  static double? _num(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  factory Coupon.fromJson(Map<String, dynamic> json) => Coupon(
        code: '${json['code'] ?? ''}'.toUpperCase(),
        kind: '${json['kind']}'.toUpperCase() == 'FIXED'
            ? CouponKind.fixed
            : CouponKind.percent,
        value: _num(json['value']) ?? 0,
        maxDiscount: _num(json['maxDiscount']),
        minSpend: _num(json['minSpend']),
        startsAt: DateTime.tryParse('${json['startsAt'] ?? ''}')?.toLocal(),
        expiresAt: DateTime.tryParse('${json['expiresAt'] ?? ''}')?.toLocal(),
        usageLimit: (json['usageLimit'] as num?)?.toInt(),
        usedCount: (json['usedCount'] as num?)?.toInt() ?? 0,
        perCustomerLimit: (json['perCustomerLimit'] as num?)?.toInt(),
        customerId: json['customerId']?.toString(),
        productIds: [
          for (final id in (json['productIds'] as List?) ?? const [])
            id.toString(),
        ],
        description: '${json['description'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'kind': kind == CouponKind.fixed ? 'FIXED' : 'PERCENT',
        'value': value,
        'maxDiscount': maxDiscount,
        'minSpend': minSpend,
        'startsAt': startsAt?.toUtc().toIso8601String(),
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'usageLimit': usageLimit,
        'usedCount': usedCount,
        'perCustomerLimit': perCustomerLimit,
        'customerId': customerId,
        'productIds': productIds,
        'description': description,
      };
}

/// One cart line: its value before the coupon (price x quantity - line discount).
class CouponLine {
  const CouponLine({required this.productId, required this.amount});

  final String productId;
  final double amount;
}

class CouponVerdict {
  const CouponVerdict._(this.ok, this.discount, this.message);

  const CouponVerdict.accepted(double discount) : this._(true, discount, null);

  const CouponVerdict.refused(String message) : this._(false, 0, message);

  final bool ok;
  final double discount;
  final String? message;
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

String normaliseCouponCode(String value) =>
    value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

/// Does this coupon work on this cart, and how much does it take off?
///
/// [customerUses] is how often this customer already used it; the phone can't
/// know that offline, so it is left at 0 there and the server enforces it.
CouponVerdict evaluateCoupon(
  Coupon coupon,
  List<CouponLine> lines, {
  DateTime? now,
  String? customerId,
  int customerUses = 0,
}) {
  final at = now ?? DateTime.now();
  if (coupon.startsAt != null && at.isBefore(coupon.startsAt!)) {
    return const CouponVerdict.refused('This coupon is not active yet.');
  }
  if (coupon.expiresAt != null && at.isAfter(coupon.expiresAt!)) {
    return const CouponVerdict.refused('This coupon has expired.');
  }
  if (coupon.usageLimit != null && coupon.usedCount >= coupon.usageLimit!) {
    return const CouponVerdict.refused('This coupon has been used up.');
  }
  if (coupon.customerId != null) {
    if (customerId == null) {
      return const CouponVerdict.refused(
          'This coupon is for one customer. Pick the customer first.');
    }
    if (customerId != coupon.customerId) {
      return const CouponVerdict.refused(
          'This coupon belongs to a different customer.');
    }
  }
  if (coupon.perCustomerLimit != null) {
    if (customerId == null) {
      return const CouponVerdict.refused(
          'Pick the customer first. This coupon is limited per customer.');
    }
    if (customerUses >= coupon.perCustomerLimit!) {
      return const CouponVerdict.refused(
          'This customer has already used this coupon the most times allowed.');
    }
  }

  double positive(double v) => v > 0 ? v : 0;
  final saleAmount = lines.fold<double>(0, (s, l) => s + positive(l.amount));
  if (coupon.minSpend != null && saleAmount < coupon.minSpend!) {
    return CouponVerdict.refused(
        'Spend at least KES ${coupon.minSpend!.ceil()} to use this coupon.');
  }

  final eligible = coupon.productIds.isEmpty
      ? saleAmount
      : lines
          .where((l) => coupon.productIds.contains(l.productId))
          .fold<double>(0, (s, l) => s + positive(l.amount));
  if (eligible <= 0) {
    return const CouponVerdict.refused(
        'None of the items in this sale qualify for the coupon.');
  }

  double discount = coupon.kind == CouponKind.percent
      ? eligible * coupon.value.clamp(0.0, 100.0).toDouble() / 100
      : coupon.value;
  if (coupon.maxDiscount != null && discount > coupon.maxDiscount!) {
    discount = coupon.maxDiscount!;
  }
  if (discount > eligible) discount = eligible;
  discount = _round2(discount);
  if (discount <= 0) {
    return const CouponVerdict.refused(
        'This coupon gives no discount on this sale.');
  }
  return CouponVerdict.accepted(discount);
}

/// Shares a coupon's discount across the lines it applies to in proportion to
/// their value, so the price guard sees the real price each item sold at.
/// One share per line, adding up to exactly [discount].
List<double> spreadCouponDiscount(
  List<CouponLine> lines,
  List<String> productIds,
  double discount,
) {
  final eligible = [
    for (final l in lines)
      productIds.isEmpty || productIds.contains(l.productId)
          ? (l.amount > 0 ? l.amount : 0.0)
          : 0.0,
  ];
  final base = eligible.fold<double>(0, (s, a) => s + a);
  final shares = List<double>.filled(lines.length, 0);
  if (base <= 0 || discount <= 0) return shares;
  var given = 0.0;
  var last = -1;
  for (var i = 0; i < eligible.length; i++) {
    if (eligible[i] <= 0) continue;
    shares[i] = _round2(discount * eligible[i] / base);
    given += shares[i];
    last = i;
  }
  if (last >= 0) shares[last] = _round2(shares[last] + (discount - given));
  return shares;
}
