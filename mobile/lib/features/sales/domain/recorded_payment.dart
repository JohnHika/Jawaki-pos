import 'dart:convert';

/// Payments the shop receives itself (customer pays the shop's own till, paybill
/// or bank account) and records in Counterbase. They are never verified by
/// Counterbase, so they are stored under their own method names and labelled
/// "recorded" everywhere they appear.
class RecordedPaymentMethod {
  const RecordedPaymentMethod._();

  static const String mpesa = 'MPESA_RECORDED';
  static const String bank = 'BANK_RECORDED';

  static bool isRecorded(String? method) {
    final value = method?.trim().toUpperCase();
    return value == mpesa || value == bank;
  }

  static String label(String? method) {
    switch (method?.trim().toUpperCase()) {
      case mpesa:
        return 'M-Pesa (recorded)';
      case bank:
        return 'Bank transfer (recorded)';
    }
    return 'Recorded payment';
  }
}

/// What could be read from a pasted M-Pesa confirmation message.
class ParsedMpesaMessage {
  const ParsedMpesaMessage({this.code, this.amount, this.receivedAt});

  final String? code;
  final double? amount;
  final DateTime? receivedAt;

  bool get isEmpty => code == null && amount == null;
}

/// M-Pesa transaction codes are ten upper-case letters and digits, such as
/// SKL4X9Q2TB.
final RegExp _mpesaCodePattern = RegExp(r'^[A-Z][A-Z0-9]{9}$');

bool looksLikeMpesaCode(String value) =>
    _mpesaCodePattern.hasMatch(value.trim().toUpperCase());

/// A bank reference is looser: letters, digits and a few separators.
bool looksLikeBankReference(String value) =>
    RegExp(r'^[A-Za-z0-9\-/]{6,30}$').hasMatch(value.trim());

/// Reads the code, amount and time from a message such as
/// "SKL4X9Q2TB Confirmed. Ksh4,200.00 received from NAME 0712 on 4/11/26 at
/// 11:19 AM." Returns whatever it can find; a missing part is left null so the
/// person can correct it.
ParsedMpesaMessage parseMpesaMessage(String message) {
  final text = message.trim();
  if (text.isEmpty) return const ParsedMpesaMessage();

  String? code;
  for (final match in RegExp(r'\b[A-Z][A-Z0-9]{9}\b').allMatches(text)) {
    final candidate = match.group(0)!;
    // Skip a word that has no digit (for example "CONFIRMED"): real codes
    // always mix in at least one digit.
    if (RegExp(r'\d').hasMatch(candidate)) {
      code = candidate;
      break;
    }
  }

  double? amount;
  final amountMatch = RegExp(
    r'(?:Ksh|KES|Kshs)\.?\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  ).firstMatch(text);
  if (amountMatch != null) {
    amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
  }

  DateTime? receivedAt;
  final timeMatch = RegExp(
    r'(\d{1,2})/(\d{1,2})/(\d{2,4})\s+at\s+(\d{1,2}):(\d{2})\s*(AM|PM)',
    caseSensitive: false,
  ).firstMatch(text);
  if (timeMatch != null) {
    final day = int.parse(timeMatch.group(1)!);
    final month = int.parse(timeMatch.group(2)!);
    var year = int.parse(timeMatch.group(3)!);
    if (year < 100) year += 2000;
    var hour = int.parse(timeMatch.group(4)!) % 12;
    if (timeMatch.group(6)!.toUpperCase() == 'PM') hour += 12;
    final minute = int.parse(timeMatch.group(5)!);
    try {
      receivedAt = DateTime(year, month, day, hour, minute);
    } catch (_) {
      receivedAt = null;
    }
  }

  return ParsedMpesaMessage(
    code: code,
    amount: amount,
    receivedAt: receivedAt,
  );
}

/// How old a message may be before the person is warned. It is a warning, not
/// a block, because a customer can pay a little before reaching the counter.
const Duration kRecordedPaymentFreshness = Duration(hours: 6);

/// The shop's rules for recorded payments. Defaults are the safe ones.
class RecordedPaymentRules {
  const RecordedPaymentRules({
    this.enabled = true,
    this.approvalLimit = 5000,
    this.requireMessage = true,
    this.tillNumber = '',
  });

  /// Whether staff may record payments at all.
  final bool enabled;

  /// Recorded payments above this amount need a manager or owner PIN. Zero
  /// means every recorded payment needs one.
  final double approvalLimit;

  /// Whether an M-Pesa payment must come with the pasted message.
  final bool requireMessage;

  /// The shop's own till, paybill or phone number, shown at checkout so
  /// customers pay the right place.
  final String tillNumber;

  bool needsApproval(double amount) =>
      amount > approvalLimit + 0.005 || approvalLimit <= 0;

  RecordedPaymentRules copyWith({
    bool? enabled,
    double? approvalLimit,
    bool? requireMessage,
    String? tillNumber,
  }) =>
      RecordedPaymentRules(
        enabled: enabled ?? this.enabled,
        approvalLimit: approvalLimit ?? this.approvalLimit,
        requireMessage: requireMessage ?? this.requireMessage,
        tillNumber: tillNumber ?? this.tillNumber,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'approvalLimit': approvalLimit,
        'requireMessage': requireMessage,
        'tillNumber': tillNumber,
      };

  factory RecordedPaymentRules.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RecordedPaymentRules();
    final limit = json['approvalLimit'];
    return RecordedPaymentRules(
      enabled: json['enabled'] != false,
      approvalLimit: limit is num && limit.isFinite && limit >= 0
          ? limit.toDouble()
          : 5000,
      requireMessage: json['requireMessage'] != false,
      tillNumber: (json['tillNumber'] ?? '').toString().trim(),
    );
  }
}

/// Everything saved with a recorded sale, so the receipt, the reports and a
/// later dispute can show who recorded it, who approved it and what evidence
/// was seen. Stored as JSON in the sale's payment reference.
class RecordedPaymentDetails {
  const RecordedPaymentDetails({
    required this.method,
    required this.code,
    required this.amount,
    required this.recordedById,
    required this.recordedByName,
    this.approvedById,
    this.approvedByName,
    this.message,
    this.recordedAt,
  });

  final String method;
  final String code;
  final double amount;
  final String recordedById;
  final String recordedByName;
  final String? approvedById;
  final String? approvedByName;
  final String? message;
  final DateTime? recordedAt;

  String toReference() => jsonEncode({
        'kind': 'recorded',
        'method': method,
        'code': code.trim().toUpperCase(),
        'amount': amount,
        'recordedById': recordedById,
        'recordedBy': recordedByName,
        if (approvedById != null) 'approvedById': approvedById,
        if (approvedByName != null) 'approvedBy': approvedByName,
        if (message != null && message!.trim().isNotEmpty)
          'message': message!.trim(),
        'recordedAt': (recordedAt ?? DateTime.now()).toUtc().toIso8601String(),
      });

  /// Reads a payment reference back. Returns null when it is not a recorded
  /// payment, for example a cash or split reference.
  static RecordedPaymentDetails? tryParse(String? reference) {
    if (reference == null || reference.isEmpty) return null;
    try {
      final decoded = jsonDecode(reference);
      if (decoded is! Map || decoded['kind'] != 'recorded') return null;
      return RecordedPaymentDetails(
        method: decoded['method']?.toString() ?? RecordedPaymentMethod.mpesa,
        code: decoded['code']?.toString() ?? '',
        amount: (decoded['amount'] as num?)?.toDouble() ?? 0,
        recordedById: decoded['recordedById']?.toString() ?? '',
        recordedByName: decoded['recordedBy']?.toString() ?? '',
        approvedById: decoded['approvedById']?.toString(),
        approvedByName: decoded['approvedBy']?.toString(),
        message: decoded['message']?.toString(),
        recordedAt: DateTime.tryParse(decoded['recordedAt']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}

/// The pattern used to find a code that was already used. The JSON encoder
/// writes `"code":"X"` with no spaces, so this matches exactly that.
String recordedCodeSearchPattern(String code) =>
    '%"code":${jsonEncode(code.trim().toUpperCase())}%';
