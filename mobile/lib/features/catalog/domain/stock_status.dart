/// How much of a product is left, in the words and colours used on Products,
/// Sell and Stock.
enum StockLevel { inStock, low, out, notTracked, unknown }

/// Works out the level for one product. A product that is not counted never
/// shows a number. At zero a counted product is out, and Sell does not sell it.
StockLevel stockLevelFor({
  required bool trackInventory,
  required double? quantity,
  required int minStock,
}) {
  if (!trackInventory) return StockLevel.notTracked;
  if (quantity == null) return StockLevel.unknown;
  if (quantity <= 0) return StockLevel.out;
  if (minStock > 0 && quantity <= minStock) return StockLevel.low;
  return StockLevel.inStock;
}

/// "48", "0.5", "2.25": whole numbers have no decimals.
String stockNumber(double quantity) {
  if (quantity % 1 == 0) return quantity.toStringAsFixed(0);
  return quantity
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// The short word shown beside a price: "48 in stock", "3 left", "Out".
String stockWords(StockLevel level, double? quantity) {
  switch (level) {
    case StockLevel.inStock:
      return '${stockNumber(quantity ?? 0)} in stock';
    case StockLevel.low:
      return '${stockNumber(quantity ?? 0)} left';
    case StockLevel.out:
      return 'Out';
    case StockLevel.notTracked:
      return 'Not tracked';
    case StockLevel.unknown:
      return 'No count yet';
  }
}

/// One product's numbers, as needed for the stock summary.
class StockLine {
  const StockLine({
    required this.trackInventory,
    required this.quantity,
    required this.minStock,
    required this.price,
    this.costPrice,
  });

  final bool trackInventory;
  final double? quantity;
  final int minStock;
  final double price;
  final double? costPrice;

  StockLevel get level => stockLevelFor(
        trackInventory: trackInventory,
        quantity: quantity,
        minStock: minStock,
      );
}

class StockSummary {
  const StockSummary({
    required this.products,
    required this.low,
    required this.out,
    required this.worth,
    required this.worthAtCost,
  });

  /// Every product in the shop, counted or not.
  final int products;
  final int low;
  final int out;

  /// Value of the stock on the shelf.
  final double worth;

  /// True when [worth] is at what the shop paid. False means it is at selling
  /// price, because no product has a buying price yet.
  final bool worthAtCost;

  int get needsReorder => low + out;
}

/// Adds up the stock for the Stock view. Worth uses the buying price where one
/// is known. When none is known anywhere it falls back to selling prices, and
/// says so through [StockSummary.worthAtCost].
StockSummary summarizeStock(Iterable<StockLine> lines) {
  var products = 0;
  var low = 0;
  var out = 0;
  var costWorth = 0.0;
  var sellWorth = 0.0;
  var anyCost = false;
  for (final line in lines) {
    products++;
    final level = line.level;
    if (level == StockLevel.low) low++;
    if (level == StockLevel.out) out++;
    final qty = line.quantity;
    if (!line.trackInventory || qty == null || qty <= 0) continue;
    sellWorth += qty * line.price;
    final cost = line.costPrice;
    if (cost != null && cost > 0) {
      anyCost = true;
      costWorth += qty * cost;
    }
  }
  return StockSummary(
    products: products,
    low: low,
    out: out,
    worth: anyCost ? costWorth : sellWorth,
    worthAtCost: anyCost,
  );
}

enum StockMovementKind { sale, delivery, correction }

/// One line in a product's history.
class StockMovement {
  const StockMovement({
    required this.kind,
    required this.at,
    required this.quantity,
    this.note,
    this.unitCost,
  });

  final StockMovementKind kind;
  final DateTime at;

  /// Signed, in the product's own unit: a sale is negative, a delivery is
  /// positive, a correction is whatever moved the count.
  final double quantity;
  final String? note;
  final double? unitCost;

  String get title {
    final amount = stockNumber(quantity.abs());
    switch (kind) {
      case StockMovementKind.sale:
        return 'Sold $amount';
      case StockMovementKind.delivery:
        return 'Received $amount';
      case StockMovementKind.correction:
        return 'Count corrected';
    }
  }

  String get signed =>
      '${quantity >= 0 ? '+' : '−'}${stockNumber(quantity.abs())}';
}
