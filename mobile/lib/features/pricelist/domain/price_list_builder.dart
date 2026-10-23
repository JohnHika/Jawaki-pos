// Turns the shop's products into a price list a trader can paste into
// WhatsApp: grouped by category, one line per item, bulk prices underneath.
// Pure so the wording and ordering are tested without a phone.

class PriceTierLine {
  const PriceTierLine({
    required this.unit,
    required this.quantityPerUnit,
    required this.price,
  });

  final String unit;
  final double quantityPerUnit;
  final double price;
}

class PriceListItem {
  const PriceListItem({
    required this.name,
    required this.unit,
    required this.price,
    required this.categoryName,
    this.tiers = const [],
  });

  final String name;
  final String unit;
  final double price;
  final String categoryName;
  final List<PriceTierLine> tiers;
}

String priceKes(double value) {
  final rounded = (value * 100).round() / 100;
  final whole = rounded == rounded.roundToDouble();
  final text = whole ? rounded.round().toString() : rounded.toStringAsFixed(2);
  final parts = text.split('.');
  final digits = parts.first;
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return 'KES $out${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String _qty(double q) => q == q.roundToDouble() ? q.round().toString() : '$q';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Items grouped by category (A to Z, "Other" last), items A to Z within each.
Map<String, List<PriceListItem>> groupPriceList(List<PriceListItem> items) {
  final groups = <String, List<PriceListItem>>{};
  for (final item in items) {
    final category = item.categoryName.trim().isEmpty ? 'Other' : item.categoryName.trim();
    groups.putIfAbsent(category, () => []).add(item);
  }
  final names = groups.keys.toList()
    ..sort((a, b) {
      if (a == 'Other') return 1;
      if (b == 'Other') return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return {
    for (final name in names)
      name: (groups[name]!
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))),
  };
}

/// WhatsApp formatting: *bold* headings, one bullet per item.
String buildPriceListText({
  required String shopName,
  required DateTime date,
  required List<PriceListItem> items,
  String? phone,
  bool showTiers = true,
}) {
  final buffer = StringBuffer()
    ..writeln('*$shopName*')
    ..writeln('Price list · ${_date(date)}');

  final groups = groupPriceList(items);
  for (final entry in groups.entries) {
    buffer
      ..writeln()
      ..writeln('*${entry.key}*');
    for (final item in entry.value) {
      final unit = item.unit.isEmpty || item.unit == 'piece' ? '' : ' per ${item.unit}';
      buffer.writeln('• ${item.name}: ${priceKes(item.price)}$unit');
      if (showTiers) {
        for (final tier in item.tiers) {
          buffer.writeln(
              '    ${tier.unit} (${_qty(tier.quantityPerUnit)}): ${priceKes(tier.price)}');
        }
      }
    }
  }

  if (items.isEmpty) {
    buffer
      ..writeln()
      ..writeln('No items selected.');
  }
  if (phone != null && phone.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Call or WhatsApp ${phone.trim()}');
  }
  return buffer.toString().trimRight();
}
