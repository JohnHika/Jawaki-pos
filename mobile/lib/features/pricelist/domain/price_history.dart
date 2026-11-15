// Remembers the last price seen for each product so the list can say "up KES 5"
// or "down KES 10" after a refresh. Pure and JSON-safe: the price list screen
// keeps it on the phone with the stale-while-revalidate cache.

enum PriceDirection { up, down }

/// A recent move in one product's price.
class PriceChange {
  const PriceChange({
    required this.previous,
    required this.current,
    required this.changedAt,
  });

  final double previous;
  final double current;
  final DateTime changedAt;

  double get delta => current - previous;
  PriceDirection get direction =>
      delta > 0 ? PriceDirection.up : PriceDirection.down;
}

class PriceHistoryEntry {
  const PriceHistoryEntry({required this.price, this.previous, this.changedAt});

  final double price;
  final double? previous;
  final DateTime? changedAt;

  Map<String, dynamic> toJson() => {
        'p': price,
        if (previous != null) 'o': previous,
        if (changedAt != null) 't': changedAt!.millisecondsSinceEpoch,
      };

  static PriceHistoryEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final price = json['p'];
    if (price is! num) return null;
    final previous = json['o'];
    final at = json['t'];
    return PriceHistoryEntry(
      price: price.toDouble(),
      previous: previous is num ? previous.toDouble() : null,
      changedAt:
          at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
    );
  }
}

class PriceHistory {
  const PriceHistory([this.entries = const {}]);

  static const empty = PriceHistory();

  /// How long a move stays highlighted on the list.
  static const window = Duration(days: 7);

  /// Product id to the price last seen and the move before it.
  final Map<String, PriceHistoryEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// Folds in the prices just seen. A product seen for the first time sets its
  /// starting price and shows no move. Returns this same object when nothing
  /// changed, so callers can cheaply tell whether to save.
  ///
  /// Products missing from [current] keep their entry: the list is read a page
  /// at a time, so a short list is not proof that a product is gone.
  PriceHistory update(Map<String, double> current, DateTime now) {
    if (current.isEmpty) return this;
    var changed = false;
    final next = Map<String, PriceHistoryEntry>.of(entries);
    current.forEach((id, price) {
      final old = entries[id];
      if (old == null) {
        next[id] = PriceHistoryEntry(price: price);
        changed = true;
      } else if ((old.price - price).abs() > 0.004) {
        next[id] = PriceHistoryEntry(
          price: price,
          previous: old.price,
          changedAt: now,
        );
        changed = true;
      }
    });
    return changed ? PriceHistory(next) : this;
  }

  /// The move to show for [id], if it happened inside [window] and the price
  /// on the list is still the price it moved to.
  PriceChange? changeFor(String id, double currentPrice, DateTime now) {
    final entry = entries[id];
    final previous = entry?.previous;
    final at = entry?.changedAt;
    if (entry == null || previous == null || at == null) return null;
    if ((entry.price - currentPrice).abs() > 0.004) return null;
    if (now.difference(at) > window) return null;
    if ((previous - entry.price).abs() <= 0.004) return null;
    return PriceChange(previous: previous, current: entry.price, changedAt: at);
  }

  Map<String, dynamic> toJson() => {
        for (final e in entries.entries) e.key: e.value.toJson(),
      };

  static PriceHistory fromJson(Object? json) {
    if (json is! Map) return empty;
    final entries = <String, PriceHistoryEntry>{};
    json.forEach((key, value) {
      final entry = PriceHistoryEntry.fromJson(value);
      if (entry != null) entries['$key'] = entry;
    });
    return PriceHistory(entries);
  }
}

/// "Up KES 5" / "Down KES 10.50": the size of a move, in plain words.
String priceChangeLabel(PriceChange change, String Function(double) money) {
  final size = money(change.delta.abs());
  return change.direction == PriceDirection.up ? 'Up $size' : 'Down $size';
}
