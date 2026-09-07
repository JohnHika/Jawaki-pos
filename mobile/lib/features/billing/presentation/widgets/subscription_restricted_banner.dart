import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';

/// Dismissible global banner shown when the subscription is in restricted
/// mode (`entitlement.restrictedMode == true`).
///
/// Non-blocking by design: the user can keep viewing past sales and
/// exporting reports — the copy says exactly that. [Renew Subscription]
/// pushes the billing screen; dismissal lasts for the session.
///
/// The same widget renders the amber "expiring soon" reminder (task 6) by
/// passing [variant] = reminder — same layout, different color/copy/icon.
class SubscriptionRestrictedBanner extends StatelessWidget {
  const SubscriptionRestrictedBanner({
    super.key,
    this.restrictedReason,
    this.daysRemaining,
    this.expiryDate,
    this.onDismiss,
    this.variant = SubscriptionBannerVariant.restricted,
  });

  /// Amber "expiring soon" convenience constructor (task-6 reminder banner):
  /// same widget, warning color, countdown copy.
  const SubscriptionRestrictedBanner.reminder({
    super.key,
    required this.daysRemaining,
    this.expiryDate,
    this.onDismiss,
  })  : restrictedReason = null,
        variant = SubscriptionBannerVariant.reminder;

  /// Which mode the banner renders in.
  final SubscriptionBannerVariant variant;

  /// Server-provided reason (restricted mode only).
  final String? restrictedReason;

  /// Days left on the paid window (reminder mode only; <= 7 shows banner).
  final int? daysRemaining;

  /// When the current paid period ends (reminder mode copy fallback).
  final DateTime? expiryDate;

  /// Called when the user dismisses the banner (X button). The parent is
  /// responsible for remembering the dismissal for the session.
  final VoidCallback? onDismiss;

  bool get _isReminder => variant == SubscriptionBannerVariant.reminder;

  Color get _color =>
      _isReminder ? DesignColors.warning : DesignColors.error;

  String get _title => _isReminder ? _reminderTitle : 'Subscription paused';

  String get _reminderTitle {
    final days = daysRemaining ?? 0;
    if (days <= 0) return 'Subscription expires today';
    if (days == 1) return 'Subscription expires in 1 day';
    return 'Subscription expires in $days days';
  }

  String get _body => _isReminder
      ? 'Renew now to keep creating sales without interruption.'
      : 'You can still view past sales and export reports. '
          'Creating new sales is paused until payment.';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _color;
    final bodyColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.10 : 0.08),
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            _isReminder
                ? Icons.schedule_rounded
                : Icons.pause_circle_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _body,
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
                if (!_isReminder && restrictedReason != null &&
                    restrictedReason!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    restrictedReason!,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.85),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (onDismiss != null)
                GestureDetector(
                  onTap: onDismiss,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: bodyColor,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              FilledButton(
                onPressed: () => context.push('/billing'),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _isReminder ? 'Renew' : 'Renew Subscription',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
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

/// Which copy/color the banner renders.
enum SubscriptionBannerVariant {
  /// Red — sales creation paused until payment.
  restricted,

  /// Amber — expires within 7 days, still fully usable.
  reminder,
}