import 'finance_models.dart';

/// One money-in event against a customer credit or a shop debt.
class CollectionEntry {
  const CollectionEntry({
    required this.paymentId,
    required this.receivableId,
    required this.who,
    required this.what,
    required this.amount,
    required this.method,
    required this.paidAt,
    required this.isShop,
    this.reference,
    this.notes,
  });

  final String paymentId;
  final String receivableId;

  /// Customer or shop name.
  final String who;

  /// The sale receipt or the debt description the money was applied to.
  final String what;
  final double amount;
  final String method;
  final DateTime paidAt;
  final bool isShop;
  final String? reference;
  final String? notes;
}

DateTime _when(ReceivablePayment p) =>
    (p.paidAt ?? p.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
        .toLocal();

CollectionEntry _entry(
  ReceivablePayment p, {
  required String who,
  required String what,
  required bool isShop,
}) =>
    CollectionEntry(
      paymentId: p.id,
      receivableId: p.receivableId,
      who: who,
      what: what,
      amount: p.amount,
      method: p.method,
      paidAt: _when(p),
      isShop: isShop,
      reference: p.reference,
      notes: p.notes,
    );

/// Every collection in [snapshot] (customers and shops), newest first.
List<CollectionEntry> allCollections(FinanceSnapshot snapshot) {
  final entries = <CollectionEntry>[
    for (final r in snapshot.retailReceivables)
      for (final p in r.payments)
        _entry(
          p,
          who: r.customerName ?? 'Walk-in customer',
          what: r.receiptNumber == null ? 'Credit sale' : 'Receipt ${r.receiptNumber}',
          isShop: false,
        ),
    for (final r in snapshot.peerReceivables)
      for (final p in r.payments)
        _entry(p, who: r.debtor.name, what: r.description, isShop: true),
  ]..sort((a, b) => b.paidAt.compareTo(a.paidAt));
  return entries;
}

/// Sum of [entries] that fall on or after [from] and before [to] (exclusive).
double collectedBetween(
  Iterable<CollectionEntry> entries,
  DateTime from, [
  DateTime? to,
]) {
  var cents = 0;
  for (final e in entries) {
    if (e.paidAt.isBefore(from)) continue;
    if (to != null && !e.paidAt.isBefore(to)) continue;
    cents += (e.amount * 100).round();
  }
  return cents / 100;
}

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Everything one shop owes and has paid, in one place.
class ShopStatement {
  const ShopStatement({
    required this.shop,
    required this.debts,
    required this.collections,
    required this.originalTotal,
    required this.outstanding,
  });

  final PeerDebtor shop;

  /// Open debts first (oldest due first), then settled ones.
  final List<PeerReceivable> debts;

  /// Instalments received from this shop, newest first.
  final List<CollectionEntry> collections;
  final double originalTotal;
  final double outstanding;

  double get paid => ((originalTotal - outstanding) * 100).round() / 100;

  /// 0..1 share of the original total already recovered.
  double get progress =>
      originalTotal <= 0 ? 0 : (paid / originalTotal).clamp(0.0, 1.0);

  List<PeerReceivable> get openDebts =>
      debts.where((d) => d.outstandingAmount > 0).toList();

  bool get isSettled => outstanding <= 0 && originalTotal > 0;
}

ShopStatement shopStatement(FinanceSnapshot snapshot, PeerDebtor shop) {
  final mine =
      snapshot.peerReceivables.where((r) => r.debtor.id == shop.id).toList();
  var original = 0;
  var outstanding = 0;
  for (final r in mine) {
    original += (r.originalAmount * 100).round();
    outstanding += (r.outstandingAmount * 100).round();
  }
  mine.sort((a, b) {
    final aOpen = a.outstandingAmount > 0;
    final bOpen = b.outstandingAmount > 0;
    if (aOpen != bOpen) return aOpen ? -1 : 1;
    final aDue = a.dueDate;
    final bDue = b.dueDate;
    if (aDue != null && bDue != null) {
      final byDue = aDue.compareTo(bDue);
      if (byDue != 0) return byDue;
    } else if (aDue != null) {
      return -1;
    } else if (bDue != null) {
      return 1;
    }
    return (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));
  });
  final entries = <CollectionEntry>[
    for (final r in mine)
      for (final p in r.payments)
        _entry(p, who: shop.name, what: r.description, isShop: true),
  ]..sort((a, b) => b.paidAt.compareTo(a.paidAt));
  return ShopStatement(
    shop: shop,
    debts: mine,
    collections: entries,
    originalTotal: original / 100,
    outstanding: outstanding / 100,
  );
}

/// What a shop owes right now, for ranking and summaries.
double shopOutstanding(FinanceSnapshot snapshot, PeerDebtor shop) {
  var cents = 0;
  for (final r in snapshot.peerReceivables) {
    if (r.debtor.id == shop.id) cents += (r.outstandingAmount * 100).round();
  }
  return cents / 100;
}

/// Folds the per-debt rows of a single instalment back into one entry.
///
/// A payment spread across several debts is stored as one row per debt, all
/// written together. Rows from the same payer, method and reference a few
/// seconds apart are one instalment to the owner, so show them as one.
List<CollectionEntry> mergeInstalments(List<CollectionEntry> entries) {
  final sorted = [...entries]..sort((a, b) => b.paidAt.compareTo(a.paidAt));
  final merged = <CollectionEntry>[];
  final names = <List<String>>[];
  for (final e in sorted) {
    if (merged.isNotEmpty) {
      final last = merged.last;
      final sameBatch = last.who == e.who &&
          last.method == e.method &&
          last.reference == e.reference &&
          last.isShop == e.isShop &&
          last.paidAt.difference(e.paidAt).inSeconds.abs() <= 5;
      if (sameBatch) {
        names.last.add(e.what);
        merged[merged.length - 1] = CollectionEntry(
          paymentId: last.paymentId,
          receivableId: last.receivableId,
          who: last.who,
          what: last.what,
          amount: ((last.amount + e.amount) * 100).round() / 100,
          method: last.method,
          paidAt: last.paidAt,
          isShop: last.isShop,
          reference: last.reference,
          notes: last.notes,
        );
        continue;
      }
    }
    merged.add(e);
    names.add([e.what]);
  }
  return [
    for (var i = 0; i < merged.length; i++)
      names[i].length == 1
          ? merged[i]
          : CollectionEntry(
              paymentId: merged[i].paymentId,
              receivableId: merged[i].receivableId,
              who: merged[i].who,
              what: '${names[i].length} debts',
              amount: merged[i].amount,
              method: merged[i].method,
              paidAt: merged[i].paidAt,
              isShop: merged[i].isShop,
              reference: merged[i].reference,
              notes: merged[i].notes,
            ),
  ];
}
