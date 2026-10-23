import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/accountability_provider.dart';

/// A line on the dashboard that says whether anything in the shop needs the
/// owner's eye right now, and takes them straight to it. Silent for people
/// who cannot see alerts, and quiet (no card) while the feed is loading.
class ShopAttentionCard extends ConsumerWidget {
  const ShopAttentionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(permissionsProvider).has('accountability.view')) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(alertsProvider);
    if (!state.loadedOnce) return const SizedBox.shrink();

    final open = state.page.openCount;
    final high = state.page.openHigh;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // All clear is worth showing too: "nothing to check" is the reassurance
    // an owner who is away from the shop is actually looking for.
    final clear = open == 0;
    final color = clear
        ? DesignColors.success
        : (high > 0 ? DesignColors.error : DesignColors.warning);
    final title = clear
        ? 'Nothing needs your attention'
        : high > 0
            ? '$high serious ${high == 1 ? 'alert' : 'alerts'} to check'
            : '$open ${open == 1 ? 'thing' : 'things'} to look at';
    final subtitle = clear
        ? 'No odd sales, voids, stock losses or credit issues.'
        : 'Sales below cost, voids, stock written off, credit and more.';

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.xl),
      child: Material(
        color: color.withValues(alpha: isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          onTap: () => context.push('/shop-alerts'),
          child: Container(
            padding: const EdgeInsets.all(DesignSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Icon(clear ? Icons.verified_user_rounded : Icons.shield_rounded,
                    color: color),
                const SizedBox(width: DesignSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
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
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
