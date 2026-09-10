import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
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
          margin: const EdgeInsets.only(left: DesignSpacing.xs),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(DesignSpacing.sm),
              decoration: BoxDecoration(
                color: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(DesignSpacing.md - 2),
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
                fontSize: DesignSpacing.xl,
                letterSpacing: -0.5,
                color: isDark
                    ? DesignColors.darkTextPrimary
                    : DesignColors.textPrimary,
              ),
            ),
            const SizedBox(width: DesignSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: DesignSpacing.md - 2, vertical: DesignSpacing.xs),
              decoration: BoxDecoration(
                color: DesignColors.accent.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(DesignSpacing.sm),
              ),
              child: Text(
                '${cart.itemCount}',
                style: const TextStyle(
                  color: DesignColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: DesignType.chatBody - 1,
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
                padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.md),
              ),
            ),
          const SizedBox(width: DesignSpacing.xs),
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
                    margin: const EdgeInsets.fromLTRB(
                        DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, 0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.md + 2,
                        vertical: DesignSpacing.md - 2),
                    borderRadius: DesignSpacing.radiusMd,
                    blur: 4,
                    tint: DesignColors.accent.withValues(alpha:0.06),
                    borderColor: DesignColors.accent.withValues(alpha:0.15),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(DesignSpacing.sm - 2),
                          decoration: BoxDecoration(
                            color: DesignColors.accent.withValues(alpha:0.12),
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.sm),
                          ),
                          child: const Icon(Icons.person_rounded,
                              size: 16, color: DesignColors.accent),
                        ),
                        const SizedBox(width: DesignSpacing.md - 2),
                        Text(
                          cart.customerName!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: DesignColors.accent,
                            fontSize: DesignType.chatBody,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${cart.itemCount} item${cart.itemCount > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: DesignType.chatSecondary,
                            color: isDark
                                ? DesignColors.darkTextSecondary
                                : DesignColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Cart Items List — first-mount entrance stagger with stable
                // per-item keys (item identity, not index) so quantity edits
                // and removals never replay the choreography.
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                        DesignSpacing.lg, DesignSpacing.lg, DesignSpacing.lg),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: DesignSpacing.sm),
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      return StaggeredItem(
                        key: ValueKey('cart-item-${item.productId}'),
                        itemKey: 'cart-${item.productId}',
                        index: index,
                        child: CartItemTile(item: item),
                      );
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
                padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                    DesignSpacing.sm, DesignSpacing.lg, DesignSpacing.lg),
                child: GradientButton(
                  label:
                      'Proceed to Payment - KES ${cart.total.toStringAsFixed(0)}',
                  icon: Icons.payment_rounded,
                  onPressed: () => context.push('/payment'),
                  height: 56,
                  borderRadius: DesignSpacing.radiusLg,
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
      onAction: () => context.pop(),
    );
  }

  Widget _buildOrderSummary(BuildContext context, CartState cart) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.all(DesignSpacing.lg),
      margin: const EdgeInsets.fromLTRB(
          DesignSpacing.lg, 0, DesignSpacing.lg, 0),
      borderRadius: DesignSpacing.radiusLg,
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
          const SizedBox(height: DesignSpacing.sm),
          if (cart.discount > 0) ...[
            _buildSummaryRow(context, 'Discount',
                '- KES ${cart.discount.toStringAsFixed(0)}',
                valueColor: DesignColors.success),
            const SizedBox(height: DesignSpacing.sm),
          ],
          if (getIt<AuthService>().showTaxOnReceipt &&
              getIt<AuthService>().taxRatePercent > 0) ...[
            _buildSummaryRow(
              context,
              'Tax (${getIt<AuthService>().taxRatePercent.toStringAsFixed(getIt<AuthService>().taxRatePercent % 1 == 0 ? 0 : 1)}%)',
              'KES ${cart.tax.toStringAsFixed(0)}',
            ),
            const SizedBox(height: DesignSpacing.sm),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DesignSpacing.md),
            child: Divider(
              height: 1,
              color:
                  isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
            ),
          ),
          _buildSummaryRow(
            context,
            'Total',
            'KES ${cart.total.toStringAsFixed(0)}',
            isBold: true,
            valueStyle: DesignType.numeric(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: DesignColors.accent,
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
              fontSize: isBold
                  ? DesignType.chatBody + 2
                  : DesignType.chatBody,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              color: isDark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary,
            )),
        Text(value,
            style: valueStyle ??
                TextStyle(
                  fontSize: isBold
                      ? DesignType.chatBody + 4
                      : DesignType.chatBody,
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
