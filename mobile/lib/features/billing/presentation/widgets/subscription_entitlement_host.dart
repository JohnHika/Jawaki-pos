import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/billing_entitlement.dart';
import '../providers/entitlement_provider.dart';
import 'subscription_expiry_toast.dart';
import 'subscription_restricted_banner.dart';

/// Global subscription notice host, mounted in the home shell scaffold
/// (directly under the offline banner, above the routed child).
///
/// Watches [entitlementProvider] (fetched on login/app-resume) and renders:
///  - a RED, layout-pushing BANNER when `restrictedMode` is true — sales
///    creation is actually blocked, so this deserves permanent visibility
///    (Stripe's own guidance: banners are for things needing action that
///    block the user; https://docs.stripe.com/stripe-apps/patterns/communicating-state).
///  - an AMBER, floating, dismissible TOAST when the plan is merely
///    expiring soon (1–7 days) — informational only, nothing is blocked,
///    so it must never resize every screen under it. It anchors above the
///    bottom nav like a standard mobile toast instead.
///  - nothing when ACTIVE with comfortable runway.
///
/// Dismissal is per-session (a Set of dismissed variant keys) — the notice
/// reappears after a fresh fetch flips the state. Never blocks navigation
/// to data screens: both are passive, not gates.
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

    // 1. Restricted mode — red, layout-pushing banner. Sales are actually
    //    blocked, so this earns permanent space above the content.
    if (_isRestricted(entitlement) &&
        !_dismissed.contains(SubscriptionBannerVariant.restricted)) {
      return Column(
        children: [
          SubscriptionRestrictedBanner(
            key: const ValueKey('billing-banner-restricted'),
            restrictedReason: entitlement.restrictedReason,
            onDismiss: () => setState(
                () => _dismissed.add(SubscriptionBannerVariant.restricted)),
          ),
          Expanded(child: widget.child),
        ],
      );
    }

    // 2. Expiry reminder — amber, floating toast anchored above the bottom
    //    nav. Nothing is blocked, so the child keeps its full layout;
    //    the toast overlays on top instead of pushing content down.
    if (isExpiringSoon(entitlement) &&
        !_dismissed.contains(SubscriptionBannerVariant.reminder)) {
      return Stack(
        children: [
          widget.child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: SubscriptionExpiryToast(
                key: const ValueKey('billing-toast-reminder'),
                daysRemaining: entitlement.daysRemaining ?? 0,
                onDismiss: () => setState(
                    () => _dismissed.add(SubscriptionBannerVariant.reminder)),
              ),
            ),
          ),
        ],
      );
    }

    return widget.child;
  }

  bool _isRestricted(BillingEntitlement entitlement) =>
      entitlement.restrictedMode ||
      entitlement.state == EntitlementState.restricted;
}

/// True when the entitlement says the paid window closes within 7 days.
bool isExpiringSoon(BillingEntitlement entitlement) {
  if (entitlement.restrictedMode) return false;
  if (entitlement.state != EntitlementState.active) return false;
  final days = entitlement.daysRemaining;
  return days != null && days >= 0 && days <= 7;
}
