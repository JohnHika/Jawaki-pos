import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../providers/cart_provider.dart';

class CartSummaryBar extends ConsumerWidget {
  const CartSummaryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartProvider);
    if (cartState.items.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      margin: EdgeInsets.zero,
      borderRadius: 0,
      blur: 20,
      tint: isDark
          ? DesignColors.darkSurfaceElevated.withValues(alpha:0.95)
          : Colors.white.withValues(alpha:0.95),
      borderColor: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha:isDark ? 0.4 : 0.08),
          blurRadius: 16,
          offset: const Offset(0, -4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha:isDark ? 0.2 : 0.04),
          blurRadius: 32,
          offset: const Offset(0, -8),
        ),
      ],
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Cart Icon with Badge (Pulse Animation)
            PulseAnimation(
              active: cartState.itemCount > 0,
              scale: 1.08,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: DesignColors.accent.withValues(alpha:0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: DesignColors.accent.withValues(alpha:0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.shopping_cart_rounded,
                      color: DesignColors.accent,
                      size: 22,
                    ),
                  ),
                  Positioned(
                    top: -4,
                    right: -4,
                    child: TweenAnimationBuilder<int>(
                      duration: DesignAnimation.fast,
                      tween: IntTween(
                        begin: 0,
                        end: cartState.itemCount,
                      ),
                      builder: (context, value, child) {
                        return Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: DesignColors.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: DesignColors.accent.withValues(alpha:0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          constraints:
                              const BoxConstraints(minWidth: 20, minHeight: 20),
                          child: Text(
                            '$value',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Cart Summary
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cartState.customerName != null)
                    Row(
                      children: [
                        const Icon(Icons.person_rounded,
                            size: 12, color: DesignColors.accent),
                        const SizedBox(width: 4),
                        Text(
                          cartState.customerName!,
                          style: const TextStyle(
                            color: DesignColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '${cartState.itemCount} item${cartState.itemCount > 1 ? 's' : ''}',
                    style: TextStyle(
                      color: isDark
                          ? DesignColors.darkTextSecondary
                          : DesignColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'KES ${cartState.total.toStringAsFixed(0)}',
                      style: DesignType.numeric(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),

            // View Cart Button
            GradientButton(
              label: 'View Cart',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => context.push('/cart'),
              height: 44,
              borderRadius: 12,
            ),
          ],
        ),
      ),
    );
  }
}

