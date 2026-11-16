import 'dart:convert';

/// How the day's money came in: sales paid now plus money collected from
/// customers who owed, grouped by how it was paid.
class MoneyInToday {
  const MoneyInToday({
    required this.byMethod,
    required this.fromSalesCents,
    required this.fromCollectionsCents,
  });

  /// Cents per method label, in display order, zero rows left out.
  final Map<String, int> byMethod;
  final int fromSalesCents;
  final int fromCollectionsCents;

  int get totalCents => fromSalesCents + fromCollectionsCents;
  double get total => totalCents / 100;
  double get fromSales => fromSalesCents / 100;
  double get fromCollections => fromCollectionsCents / 100;
  bool get isEmpty => totalCents == 0;
}

const _order = ['Cash', 'M-Pesa', 'Bank', 'Card', 'Other'];

/// Groups a payment method name ("MPESA_RECORDED", "Cash", "bank transfer").
String moneyMethodLabel(String method) {
  final u = method.trim().toUpperCase();
  if (u.contains('CASH')) return 'Cash';
  if (u.contains('MPESA') || u.contains('M-PESA')) return 'M-Pesa';
  if (u.contains('BANK')) return 'Bank';
  if (u.contains('CARD') || u == 'PESAPAL' || u == 'TOURISTTAP') return 'Card';
  return 'Other';
}

bool _isCredit(String method) {
  final u = method.trim().toUpperCase();
  return u == 'CREDIT' || u == 'DEBT';
}

int _cents(num amount) => (amount * 100).round();

/// [sales] are today's completed sales as (method, total, reference) triples,
/// where a SPLIT sale's reference holds its tenders as JSON. Credit is money
/// still owed, so it is left out. [collections] are today's payments from
/// customers and shops as (method, amount).
MoneyInToday moneyInToday({
  required Iterable<({String method, double total, String? reference})> sales,
  required Iterable<({String method, double amount})> collections,
}) {
  final buckets = <String, int>{};
  var salesCents = 0;
  var collectionsCents = 0;

  void add(String label, int cents) {
    if (cents <= 0) return;
    buckets.update(label, (v) => v + cents, ifAbsent: () => cents);
  }

  for (final sale in sales) {
    final method = sale.method.trim().toUpperCase();
    if (method == 'SPLIT') {
      var counted = false;
      try {
        final decoded = jsonDecode(sale.reference ?? '');
        if (decoded is List) {
          for (final tender in decoded.whereType<Map>()) {
            final m = tender['method']?.toString() ?? '';
            final amount = tender['amount'];
            if (amount is! num || _isCredit(m)) continue;
            final cents = _cents(amount);
            add(moneyMethodLabel(m), cents);
            salesCents += cents;
            counted = true;
          }
        }
      } catch (_) {}
      if (!counted) continue;
    } else if (!_isCredit(method)) {
      final cents = _cents(sale.total);
      add(moneyMethodLabel(method), cents);
      salesCents += cents;
    }
  }
  for (final c in collections) {
    final cents = _cents(c.amount);
    if (cents <= 0) continue;
    add(moneyMethodLabel(c.method), cents);
    collectionsCents += cents;
  }

  return MoneyInToday(
    byMethod: {
      for (final label in _order)
        if ((buckets[label] ?? 0) > 0) label: buckets[label]!,
    },
    fromSalesCents: salesCents,
    fromCollectionsCents: collectionsCents,
  );
}
