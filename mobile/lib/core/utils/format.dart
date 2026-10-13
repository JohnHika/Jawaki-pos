import 'package:intl/intl.dart';

/// Shared money formatting so figures across the app read consistently with
/// thousands separators (e.g. 7335500 → "KES 7,335,500") instead of a long
/// unbroken run of digits that's hard to eyeball at a glance.
final NumberFormat _moneyGrouped = NumberFormat('#,##0', 'en_US');
final NumberFormat _moneyGrouped2 = NumberFormat('#,##0.00', 'en_US');

/// Formats [value] with thousands separators. No decimals by default (most
/// POS figures are whole shillings); pass [decimals] `true` for the 2-dp
/// form. Prefixes [symbol] ("KES " by default; pass '' for a bare number).
String formatMoney(
  num? value, {
  String symbol = 'KES ',
  bool decimals = false,
}) {
  final v = value ?? 0;
  final formatted = decimals ? _moneyGrouped2.format(v) : _moneyGrouped.format(v);
  return '$symbol$formatted';
}

/// "1 transaction" / "3 transactions". [count] may be a num or numeric string.
/// Pass [plural] for irregular words ("batch" -> "batches").
String countLabel(Object? count, String singular, {String? plural}) {
  final n = count is num ? count : num.tryParse(count?.toString() ?? '') ?? 0;
  final word = n == 1 ? singular : (plural ?? '${singular}s');
  return '${n == n.roundToDouble() ? n.toInt() : n} $word';
}

/// Customer-facing name for a payment method code from the server or database.
/// "MPESA" -> "M-Pesa", "TOURISTTAP" -> "TouristTap", "BANK_TRANSFER" -> "Bank transfer".
String paymentMethodLabel(String? code) {
  final raw = (code ?? '').trim();
  if (raw.isEmpty) return 'Unknown';
  switch (raw.toUpperCase().replaceAll(' ', '_')) {
    case 'MPESA':
    case 'M_PESA':
      return 'M-Pesa';
    case 'TOURISTTAP':
    case 'TOURIST_TAP':
      return 'TouristTap';
    case 'PESAPAL':
      return 'Pesapal';
    case 'CASH':
      return 'Cash';
    case 'CARD':
      return 'Card';
    case 'CREDIT':
      return 'Credit';
    case 'SPLIT':
      return 'Split';
    case 'MANUAL':
      return 'Manual';
  }
  final words = raw.replaceAll('_', ' ').toLowerCase();
  return words[0].toUpperCase() + words.substring(1);
}
