import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion_kit.dart';
import '../providers/cart_provider.dart';
import 'price_adjustment_widget.dart';
import '../../../../core/utils/format.dart';

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
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? DesignColors.darkBorder
                : DesignColors.surfaceBorder,
          ),
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
                borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.productName,
                          style: Theme.of(context).textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Explicit remove control — swipe-to-dismiss removes
                      // this single item too (see the Dismissible wrapper
                      // above), but many users never discover a swipe
                      // gesture. This icon is the same removeItem() call,
                      // just a second, always-visible entry point.
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusSm),
                            onTap: () => _confirmRemove(context, ref, item),
                            child: Icon(
                              Icons.close_rounded,
                              semanticLabel: 'Remove item',
                              size: 20,
                              color: Theme.of(context).disabledColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildDetailBlock(context),
                  const SizedBox(height: 8),
                  // Line total and stepper share their own row so the name
                  // above keeps the full width of the card.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      InkWell(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusSm),
                        onTap: () => _showPriceAdjustment(context, item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            formatMoney(item.total),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: DesignColors.brand,
                                ),
                          ),
                        ),
                      ),
                      _QuantityControls(item: item),
                    ],
                  ),
                ],
              ),
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
        currentPrice: item.total,
        quantityLabel: item.saleUnit != null && item.saleQuantity != null
            ? '${_quantityText(item.saleQuantity!)} ${item.saleUnit}'
            : '${item.quantity} ${item.quantity == 1 ? 'unit' : 'units'}',
      ),
    );
  }

  String _quantityText(double quantity) => quantity == quantity.roundToDouble()
      ? quantity.toStringAsFixed(0)
      : quantity.toString();

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, CartItem item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove Item',
      message: 'Remove ${item.productName} from cart?',
      confirmLabel: 'Remove',
      confirmColor: DesignColors.error,
    );
    if (confirmed) {
      ref.read(cartProvider.notifier).removeItem(item.productId);
    }
  }

  /// Detailed breakdown shown under the product name: what unit it's
  /// being sold as, the qty × unit price arithmetic behind the line
  /// subtotal, the pre-discount amount when a discount is applied, and
  /// the base-stock impact when the sale unit differs from the stock unit
  /// (e.g. selling by the pack while stock is tracked in pieces).
  Widget _buildDetailBlock(BuildContext context) {
    final disabledColor = Theme.of(context).disabledColor;
    final soldByTier = item.saleUnit != null && item.saleQuantity != null;
    final displayQty =
        soldByTier ? item.saleQuantity! : item.quantity.toDouble();
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
          '${_formatQty(displayQty)} $displayUnit × ${formatMoney(perUnitPrice)} '
          '= ${formatMoney(subtotal)}',
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
                formatMoney(subtotal),
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
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
                ),
                child: Text(
                  '-${formatMoney(item.discount)}',
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
    final rawConversion = item.unitConversionFactor;
    final conversion =
        rawConversion != null && rawConversion.isFinite && rawConversion > 0
            ? rawConversion.round().clamp(1, 0x7fffffff).toInt()
            : 1;
    final step = item.saleUnit == null ? 1 : conversion;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? DesignColors.darkSurfaceElevated
            : DesignColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QuantityButton(
            icon: Icons.remove,
            onPressed: item.quantity > step
                ? () => ref
                    .read(cartProvider.notifier)
                    .changeQuantityBy(item.productId, -step)
                : null,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Builder(builder: (_) {
              final label = item.saleUnit != null && item.saleQuantity != null
                  ? item.saleQuantity!.toStringAsFixed(
                      item.saleQuantity!.truncateToDouble() == item.saleQuantity
                          ? 0
                          : 1,
                    )
                  : '${item.quantity}';
              // The number slides up/fades whenever it changes.
              return SlideSwitcher(
                child: Text(
                  label,
                  key: ValueKey(label),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              );
            }),
          ),
          _QuantityButton(
            icon: Icons.add,
            onPressed: () => ref
                .read(cartProvider.notifier)
                .changeQuantityBy(item.productId, step),
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
        borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
        child: Padding(
          // 18dp icon + 13dp padding = 44dp: a comfortable thumb target for
          // a control used constantly at the till.
          padding: const EdgeInsets.all(13),
          child: Icon(
            icon,
            semanticLabel:
                icon == Icons.add ? 'Increase quantity' : 'Decrease quantity',
            size: 18,
            color: onPressed != null ? null : Theme.of(context).disabledColor,
          ),
        ),
      ),
    );
  }
}
