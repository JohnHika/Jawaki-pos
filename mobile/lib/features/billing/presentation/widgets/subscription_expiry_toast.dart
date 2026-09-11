import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';

/// Floating, dismissible expiry reminder — NOT a layout-pushing banner.
///
/// Design rationale (matches Stripe's own banner-vs-toast distinction and
/// the general SaaS convention: https://docs.stripe.com/stripe-apps/patterns/communicating-state):
/// a banner is for things that block the user and need permanent visibility
/// (see [SubscriptionRestrictedBanner] for that case — red, blocking sales,
/// stays pinned above the shell). An "expires in N days" reminder is
/// informational and never blocks anything, so it doesn't earn permanent
/// space that resizes every screen underneath it. It floats above the
/// bottom nav instead — thumb-reachable, dismissible, doesn't reflow the
/// app, and disappears at the next re-fetch that confirms it's no longer
/// relevant (same dismissal-persists-for-session contract as the banner).
class SubscriptionExpiryToast extends StatelessWidget {
  const SubscriptionExpiryToast({
    super.key,
    required this.daysRemaining,
    this.onDismiss,
  });

  final int daysRemaining;
  final VoidCallback? onDismiss;

  String get _title {
    if (daysRemaining <= 0) return 'Subscription expires today';
    if (daysRemaining == 1) return 'Subscription expires in 1 day';
    return 'Subscription expires in $daysRemaining days';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bodyColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    final card = Container(
      margin: const EdgeInsets.fromLTRB(
        DesignSpacing.md,
        0,
        DesignSpacing.md,
        DesignSpacing.md,
      ),
      padding: const EdgeInsets.fromLTRB(
        DesignSpacing.md,
        DesignSpacing.sm + 2,
        DesignSpacing.sm,
        DesignSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(
          color: DesignColors.warning.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.schedule_rounded,
              color: DesignColors.warning, size: 20),
          const SizedBox(width: DesignSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    color: DesignColors.warning,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Renew now to keep creating sales without interruption.',
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DesignSpacing.sm),
          TextButton(
            onPressed: () => context.push('/billing'),
            style: TextButton.styleFrom(
              backgroundColor: DesignColors.warning,
              foregroundColor: DesignColors.warning.computeLuminance() > 0.5
                  ? Colors.black
                  : Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: DesignSpacing.sm + 4,
                vertical: DesignSpacing.xs + 2,
              ),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
              ),
            ),
            child: const Text(
              'Renew',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
          if (onDismiss != null)
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, size: 16),
                color: bodyColor,
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );

    return AnimatedSlide(
      duration: DesignAnimation.fast,
      curve: DesignAnimation.smooth,
      offset: Offset.zero,
      child: AnimatedOpacity(
        duration: DesignAnimation.fast,
        opacity: 1,
        child: card,
      ),
    );
  }
}
