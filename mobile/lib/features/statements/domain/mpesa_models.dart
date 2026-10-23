import '../../../core/utils/api_message.dart';

/// Who a pasted M-Pesa payment probably belongs to.
class MpesaSuggestion {
  const MpesaSuggestion({
    required this.kind,
    required this.id,
    required this.name,
    required this.outstanding,
    required this.confidence,
    required this.reasons,
  });

  /// CUSTOMER | SHOP
  final String kind;
  final String id;
  final String name;
  final double outstanding;

  /// HIGH | MEDIUM | LOW
  final String confidence;
  final List<String> reasons;

  bool get isShop => kind == 'SHOP';

  factory MpesaSuggestion.fromJson(Map<String, dynamic> json) => MpesaSuggestion(
        kind: '${json['kind']}',
        id: '${json['id']}',
        name: '${json['name']}',
        outstanding: asDouble(json['outstanding']),
        confidence: '${json['confidence']}',
        reasons: [
          for (final r in (json['reasons'] as List?) ?? const []) '$r',
        ],
      );
}

class MpesaPayment {
  const MpesaPayment({
    required this.code,
    required this.amount,
    required this.senderName,
    required this.senderPhone,
    required this.paidAt,
    required this.state,
    required this.suggestions,
  });

  final String code;
  final double amount;
  final String? senderName;
  final String? senderPhone;
  final DateTime? paidAt;

  /// NEW | RECORDED | IGNORED
  final String state;
  final List<MpesaSuggestion> suggestions;

  bool get isNew => state == 'NEW';

  factory MpesaPayment.fromJson(Map<String, dynamic> json) => MpesaPayment(
        code: '${json['code']}',
        amount: asDouble(json['amount']),
        senderName: json['senderName']?.toString(),
        senderPhone: json['senderPhone']?.toString(),
        paidAt: asDate(json['paidAt']),
        state: '${json['state'] ?? 'NEW'}',
        suggestions: [
          for (final s in (json['suggestions'] as List?) ?? const [])
            if (s is Map) MpesaSuggestion.fromJson(s.cast<String, dynamic>()),
        ],
      );

  Map<String, dynamic> toItemJson() => {
        'code': code,
        'amount': amount,
        if (senderName != null) 'senderName': senderName,
        if (senderPhone != null) 'senderPhone': senderPhone,
        if (paidAt != null) 'paidAt': paidAt!.toUtc().toIso8601String(),
      };
}
