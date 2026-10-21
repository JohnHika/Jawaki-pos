import 'package:intl/intl.dart';

/// Formatting helpers. All dates render in the device's local time zone
/// (Nairobi for the team), money is always Kenyan shillings.
class Fmt {
  Fmt._();

  static final NumberFormat _int = NumberFormat.decimalPattern('en_KE');
  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _dateShort = DateFormat('d MMM');
  static final DateFormat _time = DateFormat('HH:mm');
  static final DateFormat _month = DateFormat('MMM');

  /// "KES 12,500" — whole shillings; credits render as "−KES 100".
  static String kes(num? v) {
    if (v == null) return '—';
    final n = v.round();
    return n < 0 ? '−KES ${_int.format(-n)}' : 'KES ${_int.format(n)}';
  }

  /// "KES 1.2M" / "KES 45K" for tight spaces (stat tiles, chart axes).
  static String kesCompact(num? v) {
    if (v == null) return '—';
    final a = v.abs();
    final sign = v < 0 ? '−' : '';
    if (a >= 1000000) return '${sign}KES ${(a / 1000000).toStringAsFixed(a >= 10000000 ? 0 : 1)}M';
    if (a >= 10000) return '${sign}KES ${(a / 1000).toStringAsFixed(0)}K';
    return '${sign}KES ${_int.format(a.round())}';
  }

  static String number(num? v) => v == null ? '—' : _int.format(v);

  static String date(DateTime? d) => d == null ? '—' : _date.format(d.toLocal());
  static String dateShort(DateTime? d) => d == null ? '—' : _dateShort.format(d.toLocal());
  static String time(DateTime? d) => d == null ? '—' : _time.format(d.toLocal());
  static String dateTime(DateTime? d) =>
      d == null ? '—' : '${_date.format(d.toLocal())}, ${_time.format(d.toLocal())}';

  /// "2026-05" -> "May".
  static String monthLabel(String yyyyMm) {
    final parts = yyyyMm.split('-');
    if (parts.length != 2) return yyyyMm;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null) return yyyyMm;
    return _month.format(DateTime(y, m, 1));
  }

  /// "just now", "5 min ago", "3 h ago", "2 d ago", else the date.
  static String ago(DateTime? d, {DateTime? now}) {
    if (d == null) return 'never';
    final diff = (now ?? DateTime.now()).difference(d);
    if (diff.isNegative) return 'in ${_span(-diff)}';
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inDays >= 14) return date(d);
    return '${_span(diff)} ago';
  }

  static String _span(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  /// "5 days left", "ends today", "3 days overdue".
  static String daysUntil(DateTime? end, {DateTime? now}) {
    if (end == null) return 'no end date';
    final n = now ?? DateTime.now();
    final days = DateTime(end.toLocal().year, end.toLocal().month, end.toLocal().day)
        .difference(DateTime(n.year, n.month, n.day))
        .inDays;
    if (days == 0) return 'ends today';
    if (days > 0) return '$days day${days == 1 ? '' : 's'} left';
    return '${-days} day${days == -1 ? '' : 's'} overdue';
  }

  static String initials(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  /// "SUPPORT" -> "Support", "PAST_DUE" -> "Past due".
  static String label(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final s = raw.replaceAll('_', ' ').toLowerCase();
    return s[0].toUpperCase() + s.substring(1);
  }
}
