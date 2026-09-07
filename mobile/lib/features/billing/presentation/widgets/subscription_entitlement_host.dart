import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/billing_entitlement.dart';
import '../providers/entitlement_provider.dart';
import 'subscription_restricted_banner.dart';

/// Global subscription banner host, mounted in the home shell scaffold
/// (directly under the offline banner, above the routed child).
///
/// Watches [entitlementProvider] (fetched on login/app-resume) and renders:
///  - red restricted banner when `restrictedMode` is true
///  - amber expiry reminder when `daysRemaining` is 1..7
///  - nothing when ACTIVE with comfortable runway
///
/// Dismissal is per-session (a Set of dismissed variant keys) — the banner
/// reappears after a fresh fetch flips the state. Never blocks navigation
/// to data screens: it's a passive strip in the shell, not a gate.
class SubscriptionEntitlementHost extends ConsumerStatefulWidget {
  const SubscriptionEntitlementHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SubscriptionEntitlementHost> createState() =>
      _SubscriptionEntitlementHostState();
}

class _SubscriptionEntitlementHostState
    extends ConsumerState<SubscriptionEntitlementHost> {
  final Set<SubscriptionBannerVariant> _dismissed = {};

  @override
  Widget build(BuildContext context) {
    final entitlementAsync = ref.watch(entitlementProvider);
    final entitlement = entitlementAsync.valueOrNull;

    // Nothing resolved yet (still loading / logged out / fetch failed with
    // no cache): show nothing rather than guessing.
    if (entitlement == null) return widget.child;

    final banner = _buildBanner(entitlement);
    if (banner == null) return widget.child;

    return Column(
      children: [
        banner,
        Expanded(child: widget.child),
      ],
    );
  }

  Widget? _buildBanner(BillingEntitlement entitlement) {
    // 1. Restricted mode — red, non-blocking.
    if (entitlement.restrictedMode ||
        entitlement.state == EntitlementState.restricted) {
      if (_dismissed.contains(SubscriptionBannerVariant.restricted)) {
        return null;
      }
      return SubscriptionRestrictedBanner(
        key: const ValueKey('billing-banner-restricted'),
        restrictedReason: entitlement.restrictedReason,
        onDismiss: () => setState(
            () => _dismissed.add(SubscriptionBannerVariant.restricted)),
      );
    }

    // 2. Expiry reminder — amber, daysRemaining <= 7 (per John's spec).
    //    day -3 and beyond (grace) is covered by the restricted banner
    //    via PAST_DUE/GRACE_PERIOD + restrictedMode from the server.
    final days = entitlement.daysRemaining;
    if (isExpiringSoon(entitlement)) {
      if (_dismissed.contains(SubscriptionBannerVariant.reminder)) {
        return null;
      }
      return SubscriptionRestrictedBanner.reminder(
        key: const ValueKey('billing-banner-reminder'),
        daysRemaining: days ?? 0,
        expiryDate:
            entitlement.paidUntil == null ? null : DateTime.tryParse(entitlement.paidUntil!),
        onDismiss: () =>
            setState(() => _dismissed.add(SubscriptionBannerVariant.reminder)),
      );
    }
    return null;
  }
}

/// True when the entitlement says the paid window closes within 7 days.
bool isExpiringSoon(BillingEntitlement entitlement) {
  if (entitlement.restrictedMode) return false;
  if (entitlement.state != EntitlementState.active) return false;
  final days = entitlement.daysRemaining;
  return days != null && days >= 0 && days <= 7;
}