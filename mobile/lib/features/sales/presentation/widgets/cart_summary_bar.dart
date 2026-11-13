import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/motion_kit.dart';
import '../../../../core/theme/design_system.dart';
import '../providers/cart_provider.dart';
import '../../../../core/utils/format.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// The sale total, kept in thumb reach at the bottom of Sell. One orange bar:
/// how many items and the total on the left, "Review sale" on the right.
class CartSummaryBar extends ConsumerWidget {
  const CartSummaryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartProvider);
    if (cartState.items.isEmpty) return const SizedBox.shrink();

    final count = cartState.itemCount;
    final customer = ref.watch(permissionsProvider).canSeeCustomers
        ? cartState.customerName
        : null;
    const onAccent = DesignColors.textPrimary;

    return FadeSlideIn(
      distance: 28,
      duration: const Duration(milliseconds: 320),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Semantics(
          button: true,
          label: 'Review sale, $count ${count == 1 ? 'item' : 'items'}, '
              '${formatMoney(cartState.total)}',
          child: Material(
            color: DesignColors.accent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => context.push('/cart'),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            customer == null
                                ? '$count ${count == 1 ? 'item' : 'items'}'
                                : '$count ${count == 1 ? 'item' : 'items'} · $customer',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: onAccent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatMoney(cartState.total),
                              maxLines: 1,
                              style: DesignType.display.copyWith(
                                color: onAccent,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Review sale',
                      style: TextStyle(
                        color: onAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: onAccent),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
