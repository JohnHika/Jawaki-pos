import '../../../core/utils/api_message.dart';

/// One row of the containers list (GET /imports).
class ImportSummary {
  const ImportSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.currency,
    required this.goodsKes,
    required this.costsKes,
    required this.landedKes,
    required this.outstandingKes,
    required this.participantCount,
    this.reference,
    this.origin,
    this.expectedArrival,
  });

  factory ImportSummary.fromJson(Map<String, dynamic> json) => ImportSummary(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? 'Container'}',
        status: '${json['status'] ?? 'PLANNED'}',
        currency: '${json['currency'] ?? 'USD'}',
        reference: json['reference']?.toString(),
        origin: json['origin']?.toString(),
        expectedArrival: asDate(json['expectedArrival']),
        goodsKes: asDouble(json['goodsKes']),
        costsKes: asDouble(json['costsKes']),
        landedKes: asDouble(json['landedKes']),
        outstandingKes: asDouble(json['outstandingKes']),
        participantCount: asInt(json['participantCount']),
      );

  final String id;
  final String title;
  final String status;
  final String currency;
  final String? reference;
  final String? origin;
  final DateTime? expectedArrival;
  final double goodsKes;
  final double costsKes;
  final double landedKes;
  final double outstandingKes;
  final int participantCount;
}

class ImportCostRow {
  const ImportCostRow({
    required this.id,
    required this.type,
    required this.amount,
    required this.currency,
    required this.amountKes,
    this.label,
    this.reference,
  });

  factory ImportCostRow.fromJson(Map<String, dynamic> json) => ImportCostRow(
        id: '${json['id'] ?? ''}',
        type: '${json['type'] ?? 'OTHER'}',
        label: json['label']?.toString(),
        amount: asDouble(json['amount']),
        currency: '${json['currency'] ?? 'KES'}',
        amountKes: asDouble(json['amountKes']),
        reference: json['reference']?.toString(),
      );

  final String id;
  final String type;
  final String? label;
  final double amount;
  final String currency;
  final double amountKes;
  final String? reference;

  String get title => (label != null && label!.trim().isNotEmpty)
      ? label!.trim()
      : importCostTypeLabel(type);
}

class ImportItemRow {
  const ImportItemRow({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitCost,
    required this.landedUnitCostKes,
    required this.landedTotalKes,
    required this.goodsValueKes,
    required this.allocatedCostKes,
    this.participantId,
    this.productId,
    this.receivedQty,
  });

  factory ImportItemRow.fromJson(Map<String, dynamic> json) => ImportItemRow(
        id: '${json['id'] ?? ''}',
        participantId: json['participantId']?.toString(),
        productId: json['productId']?.toString(),
        description: '${json['description'] ?? ''}',
        quantity: asDouble(json['quantity']),
        unit: '${json['unit'] ?? 'piece'}',
        unitCost: asDouble(json['unitCost']),
        landedUnitCostKes: asDouble(json['landedUnitCostKes']),
        landedTotalKes: asDouble(json['landedTotalKes']),
        goodsValueKes: asDouble(json['goodsValueKes']),
        allocatedCostKes: asDouble(json['allocatedCostKes']),
        receivedQty:
            json['receivedQty'] == null ? null : asDouble(json['receivedQty']),
      );

  final String id;
  final String? participantId;
  final String? productId;
  final String description;
  final double quantity;
  final String unit;
  final double unitCost;
  final double landedUnitCostKes;
  final double landedTotalKes;
  final double goodsValueKes;
  final double allocatedCostKes;
  final double? receivedQty;
}

class ImportParticipantRow {
  const ImportParticipantRow({
    required this.id,
    required this.name,
    required this.isSelf,
    required this.owesKes,
    required this.paidKes,
    required this.balanceKes,
    required this.status,
    this.phone,
  });

  factory ImportParticipantRow.fromJson(Map<String, dynamic> json) =>
      ImportParticipantRow(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        phone: json['phone']?.toString(),
        isSelf: json['isSelf'] == true,
        owesKes: asDouble(json['owesKes']),
        paidKes: asDouble(json['paidKes']),
        balanceKes: asDouble(json['balanceKes']),
        status: '${json['status'] ?? 'SETTLED'}',
      );

  final String id;
  final String name;
  final String? phone;
  final bool isSelf;
  final double owesKes;
  final double paidKes;
  final double balanceKes;
  final String status;
}

class ImportPaymentRow {
  const ImportPaymentRow({
    required this.id,
    required this.participantId,
    required this.amountKes,
    required this.paidAt,
    this.method,
    this.reference,
  });

  factory ImportPaymentRow.fromJson(Map<String, dynamic> json) =>
      ImportPaymentRow(
        id: '${json['id'] ?? ''}',
        participantId: '${json['participantId'] ?? ''}',
        amountKes: asDouble(json['amountKes']),
        method: json['method']?.toString(),
        reference: json['reference']?.toString(),
        paidAt: asDate(json['paidAt']) ?? DateTime.now(),
      );

  final String id;
  final String participantId;
  final double amountKes;
  final String? method;
  final String? reference;
  final DateTime paidAt;
}

class ImportDetail {
  const ImportDetail({
    required this.id,
    required this.title,
    required this.status,
    required this.currency,
    required this.fxRate,
    required this.basisUsed,
    required this.goodsKes,
    required this.costsKes,
    required this.landedKes,
    required this.upliftPercent,
    required this.warnings,
    required this.costs,
    required this.items,
    required this.participants,
    required this.payments,
    this.reference,
    this.origin,
  });

  factory ImportDetail.fromJson(Map<String, dynamic> json) {
    final totals = (json['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    List<T> rows<T>(String key, T Function(Map<String, dynamic>) make) =>
        ((json[key] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => make(e.cast<String, dynamic>()))
            .toList();
    return ImportDetail(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? 'Container'}',
      status: '${json['status'] ?? 'PLANNED'}',
      currency: '${json['currency'] ?? 'USD'}',
      fxRate: asDouble(json['fxRate'], 1),
      basisUsed: '${json['basisUsed'] ?? 'VALUE'}',
      reference: json['reference']?.toString(),
      origin: json['origin']?.toString(),
      goodsKes: asDouble(totals['goodsKes']),
      costsKes: asDouble(totals['costsKes']),
      landedKes: asDouble(totals['landedKes']),
      upliftPercent: asDouble(totals['upliftPercent']),
      warnings: ((json['warnings'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      costs: rows('costs', ImportCostRow.fromJson),
      items: rows('items', ImportItemRow.fromJson),
      participants: rows('participants', ImportParticipantRow.fromJson),
      payments: rows('payments', ImportPaymentRow.fromJson),
    );
  }

  final String id;
  final String title;
  final String status;
  final String currency;
  final double fxRate;
  final String basisUsed;
  final String? reference;
  final String? origin;
  final double goodsKes;
  final double costsKes;
  final double landedKes;
  final double upliftPercent;
  final List<String> warnings;
  final List<ImportCostRow> costs;
  final List<ImportItemRow> items;
  final List<ImportParticipantRow> participants;
  final List<ImportPaymentRow> payments;

  bool get isReceived => status == 'RECEIVED';
  bool get isCancelled => status == 'CANCELLED';
  bool get isOpen => !isReceived && !isCancelled;
  ImportParticipantRow? get self {
    for (final p in participants) {
      if (p.isSelf) return p;
    }
    return null;
  }

  String participantName(String? id) {
    for (final p in participants) {
      if (p.id == id) return p.isSelf ? 'You' : p.name;
    }
    return 'You';
  }
}

const importCostTypes = <String, String>{
  'FREIGHT': 'Freight',
  'DUTY': 'Import duty',
  'VAT': 'VAT',
  'IDF': 'IDF',
  'RDL': 'RDL',
  'CLEARING': 'Clearing agent',
  'PORT_HANDLING': 'Port & storage',
  'TRANSPORT': 'Trucking',
  'INSURANCE': 'Insurance',
  'AGENT_FEE': 'Sourcing agent',
  'OTHER': 'Other',
};

String importCostTypeLabel(String type) => importCostTypes[type] ?? type;

String importStatusLabel(String status) => switch (status) {
      'PLANNED' => 'Planned',
      'IN_TRANSIT' => 'On the way',
      'ARRIVED' => 'Arrived',
      'RECEIVED' => 'In stock',
      'CANCELLED' => 'Cancelled',
      _ => status,
    };
