/// How strictly a rule is applied. FLAG records it for the owner and lets the
/// sale through; BLOCK refuses it unless the user may override.
enum GuardMode {
  off,
  flag,
  block;

  static GuardMode parse(Object? value, GuardMode fallback) =>
      switch (value?.toString().toUpperCase()) {
        'OFF' => GuardMode.off,
        'FLAG' => GuardMode.flag,
        'BLOCK' => GuardMode.block,
        _ => fallback,
      };
}

enum GuardSeverity { low, medium, high }

/// One thing wrong with a sale, in words a cashier can act on.
class GuardIssue {
  const GuardIssue({
    required this.code,
    required this.severity,
    required this.message,
    required this.blocking,
  });

  final String code;
  final GuardSeverity severity;
  final String message;

  /// True when this user cannot proceed without a manager.
  final bool blocking;
}

class ProductFloor {
  const ProductFloor({required this.cost, required this.floor});

  final double cost;
  final double floor;
}

/// What a till needs to apply the shop's price, discount and credit rules
/// with no signal. Fetched from `GET /accountability/till-rules` and cached.
class TillRules {
  const TillRules({
    required this.priceMode,
    required this.maxCashierDiscountPercent,
    required this.creditMode,
    required this.defaultCreditLimit,
    required this.blockWhenOverdueDays,
    required this.canDiscount,
    required this.canOverridePrice,
    required this.canOverrideCredit,
    required this.floors,
    required this.generatedAt,
  });

  final GuardMode priceMode;
  final double maxCashierDiscountPercent;
  final GuardMode creditMode;
  final double? defaultCreditLimit;
  final int? blockWhenOverdueDays;
  final bool canDiscount;
  final bool canOverridePrice;
  final bool canOverrideCredit;
  final Map<String, ProductFloor> floors;
  final DateTime generatedAt;

  static double _d(Object? v, [double fallback = 0]) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? fallback;

  factory TillRules.fromJson(Map<String, dynamic> json) {
    final price = (json['priceGuard'] as Map?)?.cast<String, dynamic>() ?? {};
    final credit = (json['credit'] as Map?)?.cast<String, dynamic>() ?? {};
    final can = (json['can'] as Map?)?.cast<String, dynamic>() ?? {};
    final floors = <String, ProductFloor>{};
    for (final raw in (json['floors'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final id = raw['productId']?.toString();
      if (id == null || id.isEmpty) continue;
      floors[id] = ProductFloor(cost: _d(raw['cost']), floor: _d(raw['floor']));
    }
    return TillRules(
      priceMode: GuardMode.parse(price['mode'], GuardMode.flag),
      maxCashierDiscountPercent: _d(price['maxCashierDiscountPercent'], 5),
      creditMode: GuardMode.parse(credit['mode'], GuardMode.flag),
      defaultCreditLimit:
          credit['defaultLimit'] == null ? null : _d(credit['defaultLimit']),
      blockWhenOverdueDays: (credit['blockWhenOverdueDays'] as num?)?.toInt(),
      canDiscount: can['discount'] == true,
      canOverridePrice: can['overridePrice'] == true,
      canOverrideCredit: can['overrideCredit'] == true,
      floors: floors,
      generatedAt:
          DateTime.tryParse('${json['generatedAt'] ?? ''}')?.toLocal() ??
              DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'priceGuard': {
          'mode': priceMode.name.toUpperCase(),
          'maxCashierDiscountPercent': maxCashierDiscountPercent,
        },
        'credit': {
          'mode': creditMode.name.toUpperCase(),
          'defaultLimit': defaultCreditLimit,
          'blockWhenOverdueDays': blockWhenOverdueDays,
        },
        'can': {
          'discount': canDiscount,
          'overridePrice': canOverridePrice,
          'overrideCredit': canOverrideCredit,
        },
        'floors': [
          for (final e in floors.entries)
            {'productId': e.key, 'cost': e.value.cost, 'floor': e.value.floor},
        ],
        'generatedAt': generatedAt.toUtc().toIso8601String(),
      };
}

/// A cart line as the rules see it. Price is per base unit, like the server.
class GuardLine {
  const GuardLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
  });

  final String productId;
  final String name;
  final num quantity;
  final double unitPrice;
  final double discount;
}

String _kes(num n) {
  final whole = n.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    final fromEnd = whole.length - i;
    buffer.write(whole[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1 && whole[i] != '-') buffer.write(',');
  }
  return 'KES $buffer';
}

/// Mirrors the server's `assessSalePricing`. Keep the two in step: the till
/// uses this to stop or warn about a sale; the server uses its copy to record
/// anything that still gets through (e.g. a sale queued while offline).
List<GuardIssue> assessPricing(
  TillRules rules,
  List<GuardLine> lines, {
  double cartDiscount = 0,
}) {
  if (rules.priceMode == GuardMode.off) return const [];
  final blocks = rules.priceMode == GuardMode.block;
  final issues = <GuardIssue>[];
  var gross = 0.0;
  var lineDiscounts = 0.0;

  for (final line in lines) {
    gross += line.unitPrice * line.quantity;
    lineDiscounts += line.discount;
    if (line.quantity <= 0) continue;

    final floor = rules.floors[line.productId];
    if (floor == null) continue;
    final netUnit =
        (line.unitPrice * line.quantity - line.discount) / line.quantity;

    if (floor.cost > 0 && netUnit < floor.cost) {
      issues.add(GuardIssue(
        code: 'BELOW_COST',
        severity: GuardSeverity.high,
        blocking: blocks && !rules.canOverridePrice,
        message:
            '${line.name} is at ${_kes(netUnit)} each, below its cost of ${_kes(floor.cost)}',
      ));
    } else if (floor.floor > 0 && netUnit < floor.floor) {
      issues.add(GuardIssue(
        code: 'BELOW_FLOOR',
        severity: GuardSeverity.medium,
        blocking: blocks && !rules.canOverridePrice,
        message:
            '${line.name} is at ${_kes(netUnit)} each, below its minimum price of ${_kes(floor.floor)}',
      ));
    }
  }

  final totalDiscount = lineDiscounts + (cartDiscount > 0 ? cartDiscount : 0);
  if (gross > 0 && totalDiscount > 0 && !rules.canDiscount) {
    final percent = totalDiscount / gross * 100;
    if (percent > rules.maxCashierDiscountPercent) {
      issues.add(GuardIssue(
        code: 'DISCOUNT_LIMIT',
        severity: percent >= 25 ? GuardSeverity.high : GuardSeverity.medium,
        blocking: blocks,
        message:
            'A discount of ${_kes(totalDiscount)} (${percent.toStringAsFixed(1)}%) is over the ${rules.maxCashierDiscountPercent.toStringAsFixed(0)}% limit',
      ));
    }
  }
  return issues;
}

/// What a customer owes against their limit (from `GET /customers/:id/credit`).
class CreditStanding {
  const CreditStanding({
    required this.limit,
    required this.outstanding,
    required this.oldestOverdueDays,
  });

  final double? limit;
  final double outstanding;
  final int oldestOverdueDays;

  factory CreditStanding.fromJson(Map<String, dynamic> json) => CreditStanding(
        limit: json['limit'] is num ? (json['limit'] as num).toDouble() : null,
        outstanding: (json['outstanding'] as num?)?.toDouble() ?? 0,
        oldestOverdueDays: (json['oldestOverdueDays'] as num?)?.toInt() ?? 0,
      );
}

/// Mirrors the server's `assessCredit`.
List<GuardIssue> assessCreditSale(
  TillRules rules, {
  required double creditAmount,
  required bool hasCustomer,
  String? customerName,
  CreditStanding? standing,
}) {
  if (rules.creditMode == GuardMode.off || creditAmount <= 0) return const [];
  final blocks = rules.creditMode == GuardMode.block && !rules.canOverrideCredit;

  if (!hasCustomer) {
    return [
      GuardIssue(
        code: 'CREDIT_NO_CUSTOMER',
        severity: GuardSeverity.high,
        blocking: blocks,
        message:
            '${_kes(creditAmount)} on credit with no customer attached — nobody is on record as owing it',
      ),
    ];
  }
  if (standing == null) return const []; // offline: the server records it later

  final issues = <GuardIssue>[];
  final who = customerName ?? 'This customer';
  final limit = standing.limit ?? rules.defaultCreditLimit;
  if (limit != null && standing.outstanding + creditAmount > limit) {
    issues.add(GuardIssue(
      code: 'CREDIT_LIMIT_EXCEEDED',
      severity: GuardSeverity.high,
      blocking: blocks,
      message:
          '$who would owe ${_kes(standing.outstanding + creditAmount)}, over their ${_kes(limit)} credit limit',
    ));
  }
  final overdueAfter = rules.blockWhenOverdueDays;
  if (overdueAfter != null && standing.oldestOverdueDays >= overdueAfter) {
    issues.add(GuardIssue(
      code: 'CREDIT_OVERDUE',
      severity: GuardSeverity.high,
      blocking: blocks,
      message:
          '$who has a balance ${standing.oldestOverdueDays} days overdue and is still being given credit',
    ));
  }
  return issues;
}
