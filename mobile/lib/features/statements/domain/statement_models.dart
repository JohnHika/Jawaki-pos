import '../../../core/utils/api_message.dart';

/// What a customer or shop owes right now (from `GET /statements/preview`).
class StatementPreview {
  const StatementPreview({
    required this.debtorName,
    required this.outstanding,
    required this.overdue,
    required this.oldestOverdueDays,
    required this.openItems,
    required this.payInstructions,
  });

  final String debtorName;
  final double outstanding;
  final double overdue;
  final int oldestOverdueDays;
  final int openItems;
  final String? payInstructions;

  factory StatementPreview.fromJson(Map<String, dynamic> json) {
    final debtor = (json['debtor'] as Map?)?.cast<String, dynamic>() ?? {};
    final business = (json['business'] as Map?)?.cast<String, dynamic>() ?? {};
    final pay = business['payInstructions']?.toString();
    return StatementPreview(
      debtorName: '${debtor['name'] ?? ''}',
      outstanding: asDouble(json['outstanding']),
      overdue: asDouble(json['overdue']),
      oldestOverdueDays: asInt(json['oldestOverdueDays']),
      openItems: ((json['items'] as List?) ?? const []).length,
      payInstructions: pay == null || pay.trim().isEmpty ? null : pay,
    );
  }
}

/// A link already sent: whether it was opened and whether it still works.
class SentStatementLink {
  const SentStatementLink({
    required this.id,
    required this.path,
    required this.url,
    required this.createdAt,
    required this.expiresAt,
    required this.revoked,
    required this.expired,
    required this.viewCount,
    required this.lastViewedAt,
    required this.claims,
  });

  final String id;
  final String path;
  final String? url;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final bool revoked;
  final bool expired;
  final int viewCount;
  final DateTime? lastViewedAt;
  final int claims;

  bool get isLive => !revoked && !expired;

  factory SentStatementLink.fromJson(Map<String, dynamic> json) =>
      SentStatementLink(
        id: '${json['id']}',
        path: '${json['path'] ?? ''}',
        url: json['url']?.toString(),
        createdAt: asDate(json['createdAt']),
        expiresAt: asDate(json['expiresAt']),
        revoked: json['revoked'] == true,
        expired: json['expired'] == true,
        viewCount: asInt(json['viewCount']),
        lastViewedAt: asDate(json['lastViewedAt']),
        claims: asInt(json['claims']),
      );
}

/// A customer's reply from the statement page.
class StatementClaim {
  const StatementClaim({
    required this.id,
    required this.kind,
    required this.status,
    required this.amount,
    required this.mpesaCode,
    required this.promisedFor,
    required this.payerName,
    required this.createdAt,
    required this.debtorName,
    required this.debtorPhone,
    required this.outstanding,
  });

  final String id;

  /// PAID | PROMISE
  final String kind;

  /// PENDING | CONFIRMED | REJECTED
  final String status;
  final double? amount;
  final String? mpesaCode;
  final DateTime? promisedFor;
  final String? payerName;
  final DateTime? createdAt;
  final String debtorName;
  final String? debtorPhone;
  final double outstanding;

  bool get isPaid => kind == 'PAID';
  bool get isPending => status == 'PENDING';

  factory StatementClaim.fromJson(Map<String, dynamic> json) => StatementClaim(
        id: '${json['id']}',
        kind: '${json['kind']}',
        status: '${json['status']}',
        amount: json['amount'] == null ? null : asDouble(json['amount']),
        mpesaCode: json['mpesaCode']?.toString(),
        promisedFor: asDate(json['promisedFor']),
        payerName: json['payerName']?.toString(),
        createdAt: asDate(json['createdAt']),
        debtorName: '${json['debtorName'] ?? 'Unknown'}',
        debtorPhone: json['debtorPhone']?.toString(),
        outstanding: asDouble(json['outstanding']),
      );
}

/// Kenyan numbers for wa.me links: 07xx / 01xx / +254 / 254 all become 254xxxxxxxxx.
String? whatsappNumber(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.startsWith('254') && digits.length == 12) return digits;
  if (digits.startsWith('0') && digits.length == 10) {
    return '254${digits.substring(1)}';
  }
  if (digits.length == 9 && (digits.startsWith('7') || digits.startsWith('1'))) {
    return '254$digits';
  }
  return null;
}
