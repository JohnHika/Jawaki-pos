import 'price_list_builder.dart';

/// Whether a product can be sold right now, in the words the list uses.
enum PriceStock { available, low, out, untracked }

/// One product line on the phone / tablet price list.
class PriceListRowData {
  const PriceListRowData({
    required this.item,
    this.sku,
    this.stock = PriceStock.untracked,
  });

  final PriceListItem item;
  final String? sku;
  final PriceStock stock;

  /// Stable key for this row: the till's product id, else category and name.
  String get key =>
      item.id.isNotEmpty ? item.id : '${item.categoryName}:${item.name}';
}
