import '../../../core/utils/api_message.dart';

/// A coupon as the owner manages it (the till uses the lighter `Coupon` in
/// core/services/coupon_rules.dart).
class ShopCoupon {
  const ShopCoupon({
    required this.id,
    required this.code,
    required this.name,
    required this.isPercent,
    required this.value,
    required this.maxDiscount,
    required this.minSpend,
    required this.startsAt,
    required this.expiresAt,
    required this.usageLimit,
    required this.usedCount,
    required this.perCustomerLimit,
    required this.isActive,
    required this.status,
    required this.description,
  });

  final String id;
  final String code;
  final String? name;
  final bool isPercent;
  final double value;
  final double? maxDiscount;
  final double? minSpend;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? usageLimit;
  final int usedCount;
  final int? perCustomerLimit;
  final bool isActive;

  /// ACTIVE | SCHEDULED | EXPIRED | USED_UP | OFF
  final String status;
  final String description;

  factory ShopCoupon.fromJson(Map<String, dynamic> json) => ShopCoupon(
        id: '${json['id']}',
        code: '${json['code']}',
        name: json['name']?.toString(),
        isPercent: '${json['kind']}'.toUpperCase() != 'FIXED',
        value: asDouble(json['value']),
        maxDiscount:
            json['maxDiscount'] == null ? null : asDouble(json['maxDiscount']),
        minSpend: json['minSpend'] == null ? null : asDouble(json['minSpend']),
        startsAt: asDate(json['startsAt']),
        expiresAt: asDate(json['expiresAt']),
        usageLimit: json['usageLimit'] == null ? null : asInt(json['usageLimit']),
        usedCount: asInt(json['usedCount']),
        perCustomerLimit: json['perCustomerLimit'] == null
            ? null
            : asInt(json['perCustomerLimit']),
        isActive: json['isActive'] != false,
        status: '${json['status'] ?? 'ACTIVE'}',
        description: '${json['description'] ?? ''}',
      );

  /// "3 of 20 used" / "3 used".
  String get usageLabel =>
      usageLimit == null ? '$usedCount used' : '$usedCount of $usageLimit used';

  /// The words to send a customer along with the code.
  String shareText(String shopName) {
    final until = expiresAt == null
        ? ''
        : ' Valid until ${expiresAt!.day} ${_months[expiresAt!.month - 1]} ${expiresAt!.year}.';
    final spend = minSpend == null
        ? ''
        : ' Spend KES ${minSpend!.round()} or more.';
    return 'Use code $code at $shopName to get $description.$spend$until';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class CouponUse {
  const CouponUse(
      {required this.label, required this.uses, required this.given});

  final String label;
  final int uses;
  final double given;
}

class CouponReport {
  const CouponReport({
    this.days = 30,
    this.uses = 0,
    this.totalGiven = 0,
    this.byCode = const [],
    this.byCashier = const [],
  });

  final int days;
  final int uses;
  final double totalGiven;
  final List<CouponUse> byCode;
  final List<CouponUse> byCashier;

  factory CouponReport.fromJson(Map<String, dynamic> json) {
    List<CouponUse> read(String key, String labelKey) => [
          for (final raw in (json[key] as List?) ?? const [])
            if (raw is Map)
              CouponUse(
                label: '${raw[labelKey] ?? ''}',
                uses: asInt(raw['uses']),
                given: asDouble(raw['given']),
              ),
        ];
    return CouponReport(
      days: asInt(json['days'], 30),
      uses: asInt(json['uses']),
      totalGiven: asDouble(json['totalGiven']),
      byCode: read('byCode', 'code'),
      byCashier: read('byCashier', 'name'),
    );
  }
}
