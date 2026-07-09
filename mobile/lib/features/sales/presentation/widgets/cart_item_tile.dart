import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_system.dart';
import '../providers/cart_provider.dart';
import 'price_adjustment_widget.dart';

class CartItemTile extends ConsumerWidget {
  final CartItem item;

  const CartItemTile({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(item.productId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: DesignColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) => showConfirmDialog(
        context,
        title: 'Remove Item',
        message: 'Remove ${item.productName} from cart?',
        confirmLabel: 'Remove',
        confirmColor: DesignColors.error,
      ),
      onDismissed: (_) {
        ref.read(cartProvider.notifier).removeItem(item.productId);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            // Product Image Placeholder
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                color: Theme.of(context).disabledColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),

            // Product Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  _buildDetailBlock(context),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Quantity Controls
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _showPriceAdjustment(context, item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      'KES ${item.total.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: DesignColors.brand,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _QuantityControls(item: item),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPriceAdjustment(BuildContext context, CartItem item) {
    showDialog(
      context: context,
      builder: (dialogContext) => PriceAdjustmentWidget(
        productId: item.productId,
        originalPrice: item.unitPrice * item.quantity,
      ),
    );
  }

  /// Detailed breakdown shown under the product name: what unit it's
  /// being sold as, the qty × unit price arithmetic behind the line
  /// subtotal, the pre-discount amount when a discount is applied, and
  /// the base-stock impact when the sale unit differs from the stock unit
  /// (e.g. selling by the pack while stock is tracked in pieces).
  Widget _buildDetailBlock(BuildContext context) {
    final disabledColor = Theme.of(context).disabledColor;
    final soldByTier = item.saleUnit != null && item.saleQuantity != null;
    final displayQty = soldByTier ? item.saleQuantity! : item.quantity.toDouble();
    final displayUnit = soldByTier ? item.saleUnit! : 'unit';
    final perUnitPrice = soldByTier
        ? item.unitPrice * (item.unitConversionFactor ?? 1)
        : item.unitPrice;
    final subtotal = item.unitPrice * item.quantity;
    final conversion = item.unitConversionFactor ?? 1;
    final showsStockImpact = soldByTier && conversion != 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_formatQty(displayQty)} $displayUnit × KES ${perUnitPrice.toStringAsFixed(0)} '
          '= KES ${subtotal.toStringAsFixed(0)}',
          style: TextStyle(color: disabledColor, fontSize: 12),
        ),
        if (showsStockImpact) ...[
          const SizedBox(height: 2),
          Text(
            '= ${item.quantity} from stock',
            style: TextStyle(color: disabledColor, fontSize: 11),
          ),
        ],
        if (item.discount > 0) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'KES ${subtotal.toStringAsFixed(0)}',
                style: TextStyle(
                  color: disabledColor,
                  fontSize: 11,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: DesignColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '-KES ${item.discount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: DesignColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _formatQty(double qty) {
    return qty.truncateToDouble() == qty
        ? qty.toStringAsFixed(0)
        : qty.toStringAsFixed(1);
  }
}

class _QuantityControls extends ConsumerWidget {
  final CartItem item;

  const _QuantityControls({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignColors.darkSurfaceElevated
            : DesignColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QuantityButton(
            icon: Icons.remove,
            onPressed: item.quantity > 1
                ? () => ref
                      .read(cartProvider.notifier)
                      .updateQuantity(item.productId, item.quantity - 1)
                : null,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              item.saleUnit != null && item.saleQuantity != null
                  ? item.saleQuantity!.toStringAsFixed(
                      item.saleQuantity!.truncateToDouble() == item.saleQuantity
                          ? 0
                          : 1,
                    )
                  : '${item.quantity}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          _QuantityButton(
            icon: Icons.add,
            onPressed: () => ref
                .read(cartProvider.notifier)
                .updateQuantity(item.productId, item.quantity + 1),
          ),
        ],
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _QuantityButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 18,
            color: onPressed != null ? null : Theme.of(context).disabledColor,
          ),
        ),
      ),
    );
  }
}

