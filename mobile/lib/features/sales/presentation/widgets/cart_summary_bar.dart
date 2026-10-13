import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/motion_kit.dart';
import '../../../../core/theme/design_system.dart';
import '../providers/cart_provider.dart';
import '../../../../core/utils/format.dart';

class CartSummaryBar extends ConsumerWidget {
  const CartSummaryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartProvider);
    if (cartState.items.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Floating rounded bar (slides up when the first item is added).
    return FadeSlideIn(
      distance: 28,
      duration: const Duration(milliseconds: 420),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      margin: EdgeInsets.zero,
      borderRadius: 24,
      blur: 20,
      tint: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
      borderColor:
          isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight,
      boxShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.45)
              : const Color(0xFF8A6B45).withValues(alpha: 0.18),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
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
                    child: BadgeBounce(
                      value: cartState.itemCount,
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
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    )),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: CountUpText(
                      formatMoney(cartState.total),
                      duration: const Duration(milliseconds: 450),
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
              borderRadius: 16,
              expanded: false,
            ),
          ],
        ),
      ),
    ));
  }
}

