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
