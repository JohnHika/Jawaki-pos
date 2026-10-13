/// Maths for the "cash received" step at the till.
///
/// Money is handled in whole cents so 0.1 + 0.2 style float error can never show
/// a cashier a change figure that is off by a fraction.
int _cents(double value) => (value * 100).round();

/// Change to hand back; 0 when the customer gave exactly the total or less.
double cashChange({required double total, required double tendered}) {
  final diff = _cents(tendered) - _cents(total);
  return diff <= 0 ? 0 : diff / 100;
}

/// How much is still missing; 0 when the customer gave enough.
double cashShortfall({required double total, required double tendered}) {
  final diff = _cents(total) - _cents(tendered);
  return diff <= 0 ? 0 : diff / 100;
}

/// True when [tendered] covers [total] and there is something to charge.
bool coversTotal({required double total, required double tendered}) =>
    _cents(total) > 0 && _cents(tendered) >= _cents(total);

/// One-tap amounts shown above the keypad: the exact total first, then the
/// total rounded up to the next 50, 100, 500 and 1,000 — the notes a customer
/// is most likely to hand over. Duplicates collapse, so a total of 500 offers
/// just 500 and 1,000.
List<double> suggestedTenders(double total, {int maxCount = 4}) {
  final whole = total.ceil();
  if (whole <= 0) return const [];

  final amounts = <double>{};
  if (_cents(total) % 100 == 0) amounts.add(total);
  for (final step in const [50, 100, 500, 1000]) {
    final rounded = ((whole + step - 1) ~/ step) * step;
    amounts.add(rounded.toDouble());
  }
  // A total with cents has no exact-note chip; the smallest chip is the next
  // rounded amount, which still covers the sale.
  final sorted = amounts.toList()..sort();
  return sorted.take(maxCount).toList();
}
