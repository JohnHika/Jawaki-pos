import '../../../core/utils/api_message.dart';

enum AlertSeverity {
  low,
  medium,
  high;

  static AlertSeverity parse(Object? value) =>
      switch (value?.toString().toUpperCase()) {
        'HIGH' => AlertSeverity.high,
        'MEDIUM' => AlertSeverity.medium,
        _ => AlertSeverity.low,
      };
}

/// One thing that needs the owner's second look (GET /accountability/alerts).
class ShopAlert {
  const ShopAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.acknowledged,
    this.actorName,
    this.branchId,
  });

  factory ShopAlert.fromJson(Map<String, dynamic> json) => ShopAlert(
        id: '${json['id'] ?? ''}',
        type: '${json['type'] ?? ''}',
        severity: AlertSeverity.parse(json['severity']),
        title: '${json['title'] ?? 'Alert'}',
        body: '${json['body'] ?? ''}',
        createdAt: asDate(json['createdAt']) ?? DateTime.now(),
        acknowledged: json['acknowledged'] == true,
        actorName: json['actorName']?.toString(),
        branchId: json['branchId']?.toString(),
      );

  final String id;
  final String type;
  final AlertSeverity severity;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool acknowledged;
  final String? actorName;
  final String? branchId;

  bool get isSummary => type == 'DAILY_SUMMARY';
}

class AlertsPage {
  const AlertsPage({
    this.items = const [],
    this.openCount = 0,
    this.openHigh = 0,
    this.total = 0,
  });

  factory AlertsPage.fromJson(Map<String, dynamic> json) => AlertsPage(
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ShopAlert.fromJson(e.cast<String, dynamic>()))
            .toList(),
        openCount: asInt(json['openCount']),
        openHigh: asInt(json['openHigh']),
        total: asInt(json['total']),
      );

  final List<ShopAlert> items;
  final int openCount;
  final int openHigh;
  final int total;
}

/// The owner's rules (GET/PUT /accountability/settings), kept as nested maps
/// so adding a rule on the server needs no change here.
class AccountabilityRules {
  AccountabilityRules(this.raw);

  final Map<String, dynamic> raw;

  Map<String, dynamic> _section(String name) =>
      (raw[name] as Map?)?.cast<String, dynamic>() ?? const {};

  String get priceMode => '${_section('priceGuard')['mode'] ?? 'FLAG'}';
  double get minMarginPercent =>
      asDouble(_section('priceGuard')['minMarginPercent']);
  double get maxDiscountPercent =>
      asDouble(_section('priceGuard')['maxCashierDiscountPercent'], 5);

  String get creditMode => '${_section('credit')['mode'] ?? 'FLAG'}';
  double? get defaultCreditLimit => _section('credit')['defaultLimit'] == null
      ? null
      : asDouble(_section('credit')['defaultLimit']);
  int? get overdueDays => _section('credit')['blockWhenOverdueDays'] == null
      ? null
      : asInt(_section('credit')['blockWhenOverdueDays']);

  bool get pushHigh => _section('alerts')['pushHigh'] != false;
  double alertThreshold(String key, double fallback) =>
      asDouble(_section('alerts')[key], fallback);

  bool get summaryEnabled => _section('dailySummary')['enabled'] != false;
  int get summaryHour => asInt(_section('dailySummary')['hourLocal'], 19);
}
