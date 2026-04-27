import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../providers/cart_provider.dart';
import '../widgets/cart_item_tile.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: Container(
          margin: const EdgeInsets.only(left: 4),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back_rounded, size: 20),
            ),
            onPressed: () => context.pop(),
          ),
        ),
        title: Row(
          children: [
            Text(
              'Cart',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                letterSpacing: -0.5,
                color: isDark
                    ? DesignColors.darkTextPrimary
                    : DesignColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: DesignColors.brand.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${cart.itemCount}',
                style: const TextStyle(
                  color: DesignColors.brand,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
        backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (cart.items.isNotEmpty)
            TextButton.icon(
              onPressed: () => _showClearCartDialog(context, ref),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text('Clear All'),
              style: TextButton.styleFrom(
                foregroundColor: DesignColors.error,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
      body: cart.items.isEmpty
          ? _buildEmptyCart(context)
          : Column(
              children: [
                // Customer banner (if set)
                if (cart.customerName != null)
                  GlassCard(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    borderRadius: 12,
                    blur: 4,
                    tint: DesignColors.teal.withValues(alpha:0.06),
                    borderColor: DesignColors.teal.withValues(alpha:0.15),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: DesignColors.teal.withValues(alpha:0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.person_rounded,
                              size: 16, color: DesignColors.teal),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          cart.customerName!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: DesignColors.teal,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${cart.itemCount} item${cart.itemCount > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? DesignColors.darkTextSecondary
                                : DesignColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Cart Items List
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      return CartItemTile(item: item);
                    },
                  ),
                ),

                // Order Summary
                _buildOrderSummary(context, cart),
              ],
            ),
      bottomNavigationBar: cart.items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: GradientButton(
                  label:
                      'Proceed to Payment - KES ${cart.total.toStringAsFixed(0)}',
                  icon: Icons.payment_rounded,
                  onPressed: () => context.push('/payment'),
                  height: 56,
                  borderRadius: 16,
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return EmptyState(
      icon: Icons.shopping_cart_outlined,
      title: 'Your cart is empty',
      subtitle: 'Add items from the POS screen',
      actionLabel: 'Start Shopping',
      iconColor: DesignColors.textTertiary,
      onAction: () => context.pop(),
    );
  }

  Widget _buildOrderSummary(BuildContext context, CartState cart) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      borderRadius: 16,
      blur: 12,
      tint: isDark
          ? DesignColors.darkSurfaceElevated.withValues(alpha:0.95)
          : Colors.white.withValues(alpha:0.95),
      borderColor:
          isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
      child: Column(
        children: [
          _buildSummaryRow(
              context, 'Subtotal', 'KES ${cart.subtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 8),
          if (cart.discount > 0) ...[
            _buildSummaryRow(context, 'Discount',
                '- KES ${cart.discount.toStringAsFixed(0)}',
                valueColor: DesignColors.success),
            const SizedBox(height: 8),
          ],
          _buildSummaryRow(
              context, 'Tax (16%)', 'KES ${cart.tax.toStringAsFixed(0)}'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(
              height: 1,
              color: DesignColors.surfaceBorder,
            ),
          ),
          _buildSummaryRow(
            context,
            'Total',
            'KES ${cart.total.toStringAsFixed(0)}',
            isBold: true,
            valueStyle: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: DesignColors.brand,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
    TextStyle? valueStyle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              color: isDark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary,
            )),
        Text(value,
            style: valueStyle ??
                TextStyle(
                  fontSize: isBold ? 18 : 14,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                  color: valueColor ??
                      (isDark
                          ? DesignColors.darkTextPrimary
                          : DesignColors.textPrimary),
                )),
      ],
    );
  }

  void _showClearCartDialog(BuildContext context, WidgetRef ref) {
    showConfirmDialog(
      context,
      title: 'Clear Cart',
      message: 'Are you sure you want to remove all items from the cart?',
      confirmLabel: 'Clear',
      cancelLabel: 'Cancel',
      confirmColor: DesignColors.error,
    ).then((confirmed) {
      if (confirmed) {
        ref.read(cartProvider.notifier).clear();
      }
    });
  }
}
