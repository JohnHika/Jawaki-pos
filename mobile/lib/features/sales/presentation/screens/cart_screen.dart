import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
import '../../../coupons/presentation/widgets/coupon_row.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../providers/cart_provider.dart';
import '../widgets/cart_item_tile.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/motion_kit_extras.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final heldSalesCount = ref.watch(
      parkedSalesProvider.select((sales) => sales.length),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 68,
        leading: AppBackButton(
          color:
              isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
          isDark: isDark,
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Review sale',
          style: DesignType.display.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 19,
            color: isDark
                ? DesignColors.darkTextPrimary
                : DesignColors.textPrimary,
          ),
        ),
        centerTitle: false,
        backgroundColor:
            isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (cart.items.isNotEmpty)
            TextButton(
              onPressed: () => _showClearCartDialog(context, ref),
              style: TextButton.styleFrom(
                foregroundColor: DesignColors.error,
                minimumSize: const Size(56, 44),
              ),
              child: const Text('Clear',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          const SizedBox(width: DesignSpacing.xs),
        ],
      ),
      backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
      body: cart.items.isEmpty
          ? _buildEmptyCart(context)
          : Column(
              children: [
                // Customer row: opens the picker back on Sell.
                if (ref.watch(businessLayoutProvider).effectiveShowPosCustomer)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                        DesignSpacing.md, DesignSpacing.lg, 0),
                    child: Material(
                      color: isDark ? DesignColors.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusLg),
                        onTap: () {
                          ref.read(customerPickerRequestProvider.notifier).state =
                              true;
                          context.pop();
                        },
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 56),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusLg),
                            border: Border.all(
                              color: isDark
                                  ? DesignColors.darkBorder
                                  : DesignColors.surfaceBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.person_outline_rounded,
                                  size: 20,
                                  color: isDark
                                      ? DesignColors.darkTextSecondary
                                      : DesignColors.textSecondary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      ref
                                          .watch(businessLayoutProvider)
                                          .customerSingular,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? DesignColors.darkTextPrimary
                                            : DesignColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      cart.customerName ?? 'Walk-in',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
                              Icon(Icons.chevron_right_rounded,
                                  color: isDark
                                      ? DesignColors.darkTextTertiary
                                      : DesignColors.textTertiary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Discount row: the shop's discount limit is checked at payment.
                Padding(
                  padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                      DesignSpacing.sm, DesignSpacing.lg, 0),
                  child: Material(
                    color: isDark ? DesignColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                      onTap: () => _showDiscountSheet(context, ref, cart),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusLg),
                          border: Border.all(
                            color: isDark
                                ? DesignColors.darkBorder
                                : DesignColors.surfaceBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.sell_outlined,
                                size: 20,
                                color: isDark
                                    ? DesignColors.darkTextSecondary
                                    : DesignColors.textSecondary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Discount',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? DesignColors.darkTextPrimary
                                          : DesignColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    cart.manualDiscount > 0
                                        ? (cart.discountPercent > 0
                                            ? '${cart.discountPercent.toStringAsFixed(cart.discountPercent % 1 == 0 ? 0 : 1)}% off · ${formatMoney(cart.manualDiscount)}'
                                            : formatMoney(cart.manualDiscount))
                                        : 'None',
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
                            Icon(Icons.chevron_right_rounded,
                                color: isDark
                                    ? DesignColors.darkTextTertiary
                                    : DesignColors.textTertiary),
                          ],
                        ),
                      ),
                    ),
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
                        child: index == 0
                            ? SwipeNudge(child: CartItemTile(item: item))
                            : CartItemTile(item: item),
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
                child: Row(
                  children: [
                    Expanded(
                      flex: 10,
                      child: SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          onPressed: () => _holdSale(context, ref, cart),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? DesignColors.darkTextPrimary
                                : DesignColors.textPrimary,
                            side: BorderSide(
                              color: isDark
                                  ? DesignColors.darkBorder
                                  : DesignColors.surfaceBorder,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(DesignSpacing.radiusLg),
                            ),
                            textStyle: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          child: Badge(
                            isLabelVisible: heldSalesCount > 0,
                            label: Text('$heldSalesCount'),
                            offset: const Offset(10, -8),
                            child: const Text('Hold'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignSpacing.md),
                    Expanded(
                      flex: 22,
                      child: SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed: () => context.push('/payment'),
                          style: FilledButton.styleFrom(
                            backgroundColor: DesignColors.accent,
                            foregroundColor: DesignColors.textPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(DesignSpacing.radiusLg),
                            ),
                            textStyle: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          child: const Text('Take payment'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return EmptyState(
      icon: Icons.shopping_cart_outlined,
      title: 'Nothing in this sale yet',
      subtitle: 'Add items from the Sell screen',
      actionLabel: 'Back to Sell',
      actionIcon: Icons.add_shopping_cart_rounded,
      onAction: () => context.pop(),
    );
  }

  Widget _buildOrderSummary(BuildContext context, CartState cart) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.lg),
      margin:
          const EdgeInsets.fromLTRB(DesignSpacing.lg, 0, DesignSpacing.lg, 0),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(
          color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
        ),
      ),
      child: Column(
        children: [
          if (!getIt<AuthService>().isLocalWorkspace) ...[
            const CouponRow(),
            const SizedBox(height: DesignSpacing.sm),
          ],
          // Subtotal only earns its own line when something actually moves
          // it away from the final total (a discount or tax applied). When
          // there's neither, "Subtotal" and "Total" are the same number —
          // showing both is redundant and reads like an unfinished screen.
          if (cart.discount > 0 ||
              (getIt<AuthService>().showTaxOnReceipt &&
                  getIt<AuthService>().taxRatePercent > 0)) ...[
            _buildSummaryRow(context, 'Subtotal', formatMoney(cart.subtotal)),
            const SizedBox(height: DesignSpacing.sm),
            if (cart.discount > 0) ...[
              _buildSummaryRow(
                  context, 'Discount', '- ${formatMoney(cart.discount)}',
                  valueColor: DesignColors.success),
              const SizedBox(height: DesignSpacing.sm),
            ],
            if (getIt<AuthService>().showTaxOnReceipt &&
                getIt<AuthService>().taxRatePercent > 0) ...[
              _buildSummaryRow(
                context,
                'Tax (${getIt<AuthService>().taxRatePercent.toStringAsFixed(getIt<AuthService>().taxRatePercent % 1 == 0 ? 0 : 1)}%)',
                formatMoney(cart.tax),
              ),
              const SizedBox(height: DesignSpacing.sm),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DesignSpacing.md),
              child: Divider(
                height: 1,
                color: isDark
                    ? DesignColors.darkBorder
                    : DesignColors.surfaceBorder,
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total',
                    style: TextStyle(
                      fontSize: DesignType.chatBody,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? DesignColors.darkTextSecondary
                          : DesignColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: DesignType.chatSecondary,
                      color: isDark
                          ? DesignColors.darkTextTertiary
                          : DesignColors.textTertiary,
                    ),
                  ),
                ],
              ),
              RollingNumber(
                formatMoney(cart.total),
                style: DesignType.display.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? DesignColors.darkTextPrimary
                      : DesignColors.textPrimary,
                ),
              ),
            ],
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
              fontSize: isBold ? DesignType.chatBody + 2 : DesignType.chatBody,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              color: isDark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary,
            )),
        Text(value,
            style: valueStyle ??
                TextStyle(
                  fontSize:
                      isBold ? DesignType.chatBody + 4 : DesignType.chatBody,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                  color: valueColor ??
                      (isDark
                          ? DesignColors.darkTextPrimary
                          : DesignColors.textPrimary),
                )),
      ],
    );
  }

  Future<void> _showDiscountSheet(
      BuildContext context, WidgetRef ref, CartState cart) async {
    final controller = TextEditingController(
      text: cart.discountPercent > 0
          ? cart.discountPercent.toStringAsFixed(cart.discountPercent % 1 == 0 ? 0 : 1)
          : cart.discountAmount > 0
              ? cart.discountAmount.toStringAsFixed(cart.discountAmount % 1 == 0 ? 0 : 2)
              : '',
    );
    var percent = cart.discountAmount <= 0;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final ink =
            isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
        final soft = isDark
            ? DesignColors.darkTextSecondary
            : DesignColors.textSecondary;
        return StatefulBuilder(builder: (ctx, setSheet) {
          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: BoxDecoration(
                  color: isDark ? DesignColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? DesignColors.darkBorder
                        : DesignColors.surfaceBorder,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Discount',
                        style: DesignType.display.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: ink)),
                    const SizedBox(height: 6),
                    Text(
                      'Your shop sets the biggest discount a cashier can give. It is checked when you take payment.',
                      style: TextStyle(fontSize: 13, color: soft, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Percent')),
                        ButtonSegment(value: false, label: Text('Amount')),
                      ],
                      selected: {percent},
                      onSelectionChanged: (value) =>
                          setSheet(() => percent = value.first),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        prefixText: percent ? null : 'KES ',
                        suffixText: percent ? '%' : null,
                        errorText: error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: () {
                          final value = double.tryParse(controller.text.trim());
                          if (value == null || value <= 0) {
                            setSheet(() => error = 'Enter a number above 0.');
                            return;
                          }
                          if (percent && value > 100) {
                            setSheet(() => error = 'A percent cannot be over 100.');
                            return;
                          }
                          final notifier = ref.read(cartProvider.notifier);
                          if (percent) {
                            notifier.setDiscountPercent(value);
                          } else {
                            notifier.setDiscountAmount(value);
                          }
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: DesignColors.accent,
                          foregroundColor: DesignColors.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        child: const Text('Apply discount'),
                      ),
                    ),
                    if (cart.manualDiscount > 0) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          ref.read(cartProvider.notifier)
                            ..setDiscountPercent(0)
                            ..setDiscountAmount(0);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Remove discount'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
    controller.dispose();
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

  Future<void> _holdSale(
      BuildContext context, WidgetRef ref, CartState cart) async {
    if (cart.items.isEmpty) return;
    try {
      await ref.read(parkedSalesProvider.notifier).park(cart);
    } catch (_) {
      if (context.mounted) {
        showGlassSnackBar(
          context,
          'Could not save the held sale. Your cart is still here.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
      return;
    }
    if (!context.mounted) return;
    final currentCart = ref.read(cartProvider);
    if (!identical(currentCart, cart)) {
      if (currentCart.items.isEmpty) return;
      showGlassSnackBar(
        context,
        'Sale saved. Your updated cart is still open.',
        icon: Icons.info_outline_rounded,
        color: DesignColors.warning,
      );
      return;
    }
    ref.read(cartProvider.notifier).clear();
    showGlassSnackBar(
      context,
      'Sale held and ready to resume',
      icon: Icons.pause_circle_filled_rounded,
      color: DesignColors.warning,
    );
    context.pop();
  }
}
