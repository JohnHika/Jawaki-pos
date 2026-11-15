import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/alive_feedback.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/widgets/motion_kit_extras.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../coupons/presentation/widgets/coupon_row.dart';
import '../providers/cart_provider.dart';
import '../screens/cart_screen.dart';
import 'cart_item_tile.dart';

/// The sale ticket that sits beside the products on a tablet, a till terminal
/// or an opened-up foldable: what is in the sale, who it is for, the total and
/// the button that takes payment, all without leaving the product browser.
///
/// It follows the shop's business profile: the accent colour, and the words
/// for a product and a customer, come from the chosen layout (a Kamukunji
/// counter, a bakery and food counter, a bookshop and so on).
class SellTicketPane extends ConsumerStatefulWidget {
  const SellTicketPane({
    super.key,
    required this.onHold,
    required this.onOpenHeldSales,
    this.heldSalesCount = 0,
  });

  /// Puts the sale on hold (the screen owns the held-sales storage).
  final Future<void> Function() onHold;

  /// Opens the list of held sales.
  final VoidCallback onOpenHeldSales;

  final int heldSalesCount;

  @override
  ConsumerState<SellTicketPane> createState() => _SellTicketPaneState();
}

class _SellTicketPaneState extends ConsumerState<SellTicketPane> {
  bool _justAdded = false;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  /// The header icon turns into a check for a moment whenever something is
  /// added, so every tap on a product visibly lands in the ticket.
  void _acknowledgeAdd() {
    _flashTimer?.cancel();
    _flashTimer = AliveIcon.flash((value) {
      if (mounted) setState(() => _justAdded = value);
    }, hold: const Duration(milliseconds: 1100));
  }

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear this sale?',
      message: 'Every item is taken out of the cart. Nothing is saved.',
      confirmLabel: 'Clear sale',
      cancelLabel: 'Keep items',
      confirmColor: DesignColors.error,
    );
    if (!confirmed || !context.mounted) return;
    ref.read(cartProvider.notifier).clear();
    Alive.done(context, 'Sale cleared', icon: Icons.delete_sweep_rounded);
  }

  Future<void> _hold() async {
    if (ref.read(cartProvider).items.isEmpty) return;
    await widget.onHold();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final layout = ref.watch(businessLayoutProvider);
    final permissions = ref.watch(permissionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = layout.preset.accent ?? DesignColors.accent;
    final onAccent = ThemeData.estimateBrightnessForColor(accent) ==
            Brightness.dark
        ? Colors.white
        : DesignColors.textPrimary;
    final ink = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final soft =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    ref.listen<CartState>(cartProvider, (previous, next) {
      final before = previous?.itemCount ?? 0;
      if (next.itemCount > before) _acknowledgeAdd();
    });

    final customerName =
        permissions.canSeeCustomers ? cart.customerName : null;
    final customerLabel = customerName ??
        (cart.customerId == null ? 'Walk-in' : 'Selected customer');
    final count = cart.itemCount;
    final isLocal = getIt<AuthService>().isLocalWorkspace;

    return Container(
      key: const ValueKey('sell-ticket-pane'),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurface : Colors.white,
        border: Border(left: BorderSide(color: border)),
      ),
      child: Column(
        children: [
          // A thin band in the shop's own colour ties the ticket to the profile.
          Container(height: 3, color: accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignSpacing.lg,
              DesignSpacing.md,
              DesignSpacing.sm,
              DesignSpacing.xs,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                  child: AliveIcon(
                    done: _justAdded,
                    doneColor: accent,
                    idle: Icon(Icons.receipt_long_rounded,
                        size: 20, color: accent),
                  ),
                ),
                const SizedBox(width: DesignSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current sale',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesignType.display.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      BumpOnChange(
                        trigger: count,
                        scale: 1.08,
                        child: Text(
                          count == 0
                              ? 'No items yet'
                              : '$count ${count == 1 ? 'item' : 'items'}',
                          key: const ValueKey('ticket-count'),
                          style: TextStyle(fontSize: 12.5, color: soft),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Held sales',
                  onPressed: widget.onOpenHeldSales,
                  icon: Badge(
                    isLabelVisible: widget.heldSalesCount > 0,
                    label: Text('${widget.heldSalesCount}'),
                    child: Icon(Icons.inventory_2_outlined, color: soft),
                  ),
                ),
                if (cart.items.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear sale',
                    onPressed: () => _clear(context),
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: DesignColors.error),
                  ),
              ],
            ),
          ),
          if (layout.effectiveShowPosCustomer)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignSpacing.lg,
                DesignSpacing.xs,
                DesignSpacing.lg,
                DesignSpacing.sm,
              ),
              child: _InfoRow(
                key: const ValueKey('ticket-customer'),
                icon: Icons.person_outline_rounded,
                title: layout.customerSingular,
                value: customerLabel,
                onTap: () => ref
                    .read(customerPickerRequestProvider.notifier)
                    .state = true,
              ),
            ),
          Expanded(
            child: cart.items.isEmpty
                ? _EmptyTicket(
                    accent: accent,
                    productSingular: layout.productSingular.toLowerCase(),
                    highlights: layout.preset.highlights,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      DesignSpacing.lg,
                      DesignSpacing.xs,
                      DesignSpacing.lg,
                      DesignSpacing.sm,
                    ),
                    children: [
                      for (var i = 0; i < cart.items.length; i++)
                        StaggeredItem(
                          key: ValueKey('ticket-item-${cart.items[i].productId}'),
                          itemKey: 'ticket-${cart.items[i].productId}',
                          index: i,
                          child: CartItemTile(item: cart.items[i]),
                        ),
                      if (permissions.canApplyDiscount)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _InfoRow(
                            key: const ValueKey('ticket-discount'),
                            icon: Icons.sell_outlined,
                            title: 'Discount',
                            value: cart.manualDiscount > 0
                                ? (cart.discountPercent > 0
                                    ? '${cart.discountPercent.toStringAsFixed(cart.discountPercent % 1 == 0 ? 0 : 1)}% off · ${formatMoney(cart.manualDiscount)}'
                                    : formatMoney(cart.manualDiscount))
                                : 'None',
                            onTap: () =>
                                CartScreen.openDiscountSheet(context, ref, cart),
                          ),
                        ),
                      if (!isLocal) const CouponRow(),
                    ],
                  ),
          ),
          _Footer(
            cart: cart,
            accent: accent,
            onAccent: onAccent,
            heldSalesCount: widget.heldSalesCount,
            onHold: _hold,
            onCharge: () => context.push('/payment'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final soft =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return Material(
      color: isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceSubtle,
      borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 19, color: soft),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: soft,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: soft),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTicket extends StatelessWidget {
  const _EmptyTicket({
    required this.accent,
    required this.productSingular,
    required this.highlights,
  });

  final Color accent;
  final String productSingular;
  final List<String> highlights;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final soft =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return LayoutBuilder(
      builder: (context, constraints) {
        // On a short pane (a foldable half open, a phone on its side) keep
        // only the words so nothing overflows.
        final roomy = constraints.maxHeight >= 190;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DesignSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (roomy)
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add_shopping_cart_rounded,
                        size: 30, color: accent),
                  ),
                if (roomy) const SizedBox(height: DesignSpacing.md),
                Text(
                  'Nothing in this sale yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap a $productSingular to add it here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: soft),
                ),
                if (roomy && highlights.isNotEmpty) ...[
                  const SizedBox(height: DesignSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final text in highlights)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusFull),
                          ),
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.cart,
    required this.accent,
    required this.onAccent,
    required this.heldSalesCount,
    required this.onHold,
    required this.onCharge,
  });

  final CartState cart;
  final Color accent;
  final Color onAccent;
  final int heldSalesCount;
  final Future<void> Function() onHold;
  final VoidCallback onCharge;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final soft =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final auth = getIt<AuthService>();
    final showTax = auth.showTaxOnReceipt && auth.taxRatePercent > 0;
    final hasItems = cart.items.isNotEmpty;

    Widget line(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 13, color: soft)),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color ?? ink,
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: EdgeInsets.fromLTRB(
        DesignSpacing.lg,
        DesignSpacing.md,
        DesignSpacing.lg,
        DesignSpacing.md + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurface : Colors.white,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cart.discount > 0 || showTax) ...[
            line('Subtotal', formatMoney(cart.subtotal)),
            if (cart.discount > 0)
              line('Discount', '- ${formatMoney(cart.discount)}',
                  color: DesignColors.success),
            if (showTax)
              line(
                'Tax (${auth.taxRatePercent.toStringAsFixed(auth.taxRatePercent % 1 == 0 ? 0 : 1)}%)',
                formatMoney(cart.tax),
              ),
            const SizedBox(height: 4),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: soft,
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: RollingNumber(
                    formatMoney(cart.total),
                    key: const ValueKey('ticket-total'),
                    style: DesignType.display.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.md),
          Row(
            children: [
              Expanded(
                flex: 10,
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    key: const ValueKey('ticket-hold'),
                    onPressed: hasItems ? onHold : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ink,
                      side: BorderSide(color: border),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusLg),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Hold'),
                  ),
                ),
              ),
              const SizedBox(width: DesignSpacing.sm),
              Expanded(
                flex: 22,
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    key: const ValueKey('ticket-charge'),
                    onPressed: hasItems ? onCharge : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: onAccent,
                      disabledBackgroundColor: accent.withValues(alpha: 0.35),
                      disabledForegroundColor: onAccent.withValues(alpha: 0.7),
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
        ],
      ),
    );
  }
}
