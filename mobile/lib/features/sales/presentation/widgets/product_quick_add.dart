import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/pricing_service.dart';
import '../providers/cart_provider.dart';

/// "12", "0.5": a count without trailing zeros.
String formatProductCount(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');

/// What the cashier is told when a product cannot be sold for lack of stock.
/// The phone shows it in a snackbar, the desktop till in an inline notice.
String stockBlockedMessage(
  String productName,
  double currentStock, {
  String? unitLabel,
}) {
  final unit = unitLabel?.trim();
  return currentStock <= 0
      ? '$productName is out of stock. Receive inventory before selling.'
      : 'Only ${formatProductCount(currentStock)} ${unit?.isNotEmpty == true ? unit : 'units'} available for $productName.';
}

/// Adds [quantity] of the product's base unit straight to the cart, no sheet.
/// The one place both the phone's product card and the desktop till add an
/// item with a single tap or Enter.
Future<CartMutationResult> quickAddToCart(
  WidgetRef ref,
  Map<String, dynamic> product, {
  num quantity = 1,
}) async {
  final productName = product['name'] as String;
  final stock = (product['stock'] as num?)?.toDouble() ?? 0;
  final trackInventory = product['trackInventory'] as bool? ?? true;
  if (trackInventory && stock <= 0) {
    return CartMutationResult(
      success: false,
      message: stockBlockedMessage(
        productName,
        stock,
        unitLabel: product['unit']?.toString(),
      ),
      currentStock: stock,
      isStockBlocked: true,
    );
  }
  final base = PricingService.getAllPricingTiers(product).first;
  return ref.read(cartProvider.notifier).addItem(
        productId: product['id'] as String,
        productName: productName,
        sku: product['sku'] as String? ?? '',
        unitPrice: base.price,
        catalogUnitPrice: base.price,
        quantity: quantity,
        notes: base.unitTypeLabel,
        saleUnit: base.unit,
        saleQuantity: quantity.toDouble(),
        unitConversionFactor: 1,
        allowFractions: product['allowFractions'] == true,
      );
}
