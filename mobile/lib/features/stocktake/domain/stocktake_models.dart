import '../../../core/utils/api_message.dart';

/// One row of the stock-counts list (GET /stocktake).
class StockCountSummary {
  const StockCountSummary({
    required this.id,
    required this.status,
    required this.itemCount,
    required this.createdAt,
    this.title,
    this.createdByName,
    this.totalVarianceValue,
  });

  factory StockCountSummary.fromJson(Map<String, dynamic> json) =>
      StockCountSummary(
        id: '${json['id'] ?? ''}',
        status: '${json['status'] ?? 'IN_PROGRESS'}',
        itemCount: asInt(json['itemCount']),
        createdAt: asDate(json['createdAt']) ?? DateTime.now(),
        title: json['title']?.toString(),
        createdByName: json['createdByName']?.toString(),
        totalVarianceValue: json['totalVarianceValue'] == null
            ? null
            : asDouble(json['totalVarianceValue']),
      );

  final String id;
  final String status;
  final int itemCount;
  final DateTime createdAt;
  final String? title;
  final String? createdByName;
  final double? totalVarianceValue;

  bool get inProgress => status == 'IN_PROGRESS';
  bool get submitted => status == 'SUBMITTED';
  bool get approved => status == 'APPROVED';
  String get displayTitle =>
      (title == null || title!.trim().isEmpty) ? 'Stock count' : title!.trim();
}

class StockCountLine {
  StockCountLine({
    required this.productId,
    required this.productName,
    required this.expectedQty,
    required this.countedQty,
    required this.varianceQty,
    required this.varianceValue,
    this.sku,
    this.unit = 'piece',
    this.reason,
    this.countedByName,
  });

  factory StockCountLine.fromJson(Map<String, dynamic> json) => StockCountLine(
        productId: '${json['productId'] ?? ''}',
        productName: '${json['productName'] ?? ''}',
        sku: json['sku']?.toString(),
        unit: json['unit']?.toString() ?? 'piece',
        expectedQty:
            json['expectedQty'] == null ? null : asDouble(json['expectedQty']),
        countedQty:
            json['countedQty'] == null ? null : asDouble(json['countedQty']),
        varianceQty:
            json['varianceQty'] == null ? null : asDouble(json['varianceQty']),
        varianceValue: json['varianceValue'] == null
            ? null
            : asDouble(json['varianceValue']),
        reason: json['reason']?.toString(),
        countedByName: json['countedByName']?.toString(),
      );

  final String productId;
  final String productName;
  final String? sku;
  final String unit;

  /// Null while a blind count is still open and you may not see it.
  final double? expectedQty;
  final double? countedQty;
  final double? varianceQty;
  final double? varianceValue;
  final String? reason;
  final String? countedByName;

  bool get isCounted => countedQty != null;
}

class StockCountDetail {
  const StockCountDetail({
    required this.id,
    required this.status,
    required this.blind,
    required this.expectedHidden,
    required this.items,
    required this.totalLines,
    required this.countedLines,
    required this.completionPercent,
    this.title,
    this.lossValue = 0,
    this.gainValue = 0,
    this.netValue = 0,
    this.shortLines = 0,
    this.overLines = 0,
    this.createdByName,
    this.submittedByName,
    this.approvedByName,
  });

  factory StockCountDetail.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    return StockCountDetail(
      id: '${json['id'] ?? ''}',
      status: '${json['status'] ?? 'IN_PROGRESS'}',
      blind: json['blind'] != false,
      expectedHidden: json['expectedHidden'] == true,
      title: json['title']?.toString(),
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => StockCountLine.fromJson(e.cast<String, dynamic>()))
          .toList(),
      totalLines: asInt(summary['totalLines']),
      countedLines: asInt(summary['countedLines']),
      completionPercent: asInt(summary['completionPercent']),
      lossValue: asDouble(summary['lossValue']),
      gainValue: asDouble(summary['gainValue']),
      netValue: asDouble(summary['netValue']),
      shortLines: asInt(summary['shortLines']),
      overLines: asInt(summary['overLines']),
      createdByName: json['createdByName']?.toString(),
      submittedByName: json['submittedByName']?.toString(),
      approvedByName: json['approvedByName']?.toString(),
    );
  }

  final String id;
  final String status;
  final bool blind;
  final bool expectedHidden;
  final String? title;
  final List<StockCountLine> items;
  final int totalLines;
  final int countedLines;
  final int completionPercent;
  final double lossValue;
  final double gainValue;
  final double netValue;
  final int shortLines;
  final int overLines;
  final String? createdByName;
  final String? submittedByName;
  final String? approvedByName;

  bool get inProgress => status == 'IN_PROGRESS';
  bool get submitted => status == 'SUBMITTED';
  bool get approved => status == 'APPROVED';
  bool get cancelled => status == 'CANCELLED';
  String get displayTitle =>
      (title == null || title!.trim().isEmpty) ? 'Stock count' : title!.trim();
}
