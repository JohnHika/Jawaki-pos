// Plain-words age of the prices on the price list: "Updated just now",
// "Updated 5 min ago". Pure so the wording is tested without a phone.

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// When a price moved: "today", "yesterday", "3 days ago".
String priceChangeWhen(DateTime at, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}

/// How long ago the prices were last confirmed against the shop's server.
String priceFreshnessLabel(DateTime? at, DateTime now) {
  if (at == null) return 'Not updated yet';
  final diff = now.difference(at);
  if (diff.isNegative || diff.inSeconds < 45) return 'Updated just now';
  if (diff.inMinutes < 60) {
    final minutes = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    return 'Updated $minutes min ago';
  }
  if (diff.inHours < 24) return 'Updated ${diff.inHours} h ago';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 1) return 'Updated yesterday';
  if (days < 7) return 'Updated $days days ago';
  return 'Updated ${at.day} ${_months[at.month - 1]}';
}
