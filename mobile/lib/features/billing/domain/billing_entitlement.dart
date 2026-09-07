import 'package:flutter/foundation.dart';

/// Entitlement state as seen from the mobile client.
enum EntitlementState { active, grace, restricted, unknown }

/// Signed, tenant-wide subscription entitlement snapshot.
///
/// Mirrors the shape returned by `GET /billing/entitlement` and the payload
/// embedded in the signed offline token from `GET /billing/entitlement/offline`
/// (`base64url(payload).base64url(hmac-sha256(payload))`).
@immutable
class BillingEntitlement {
  const BillingEntitlement({
    required this.plan,
    required this.status,
    this.paidUntil,
    this.daysRemaining,
    this.graceUntil,
    this.maxBranches,
    this.maxUsers,
    this.restrictedMode = false,
    this.restrictedReason,
    this.source = EntitlementSource.live,
  });

  factory BillingEntitlement.fromMap(
    Map<String, dynamic> map, {
    EntitlementSource source = EntitlementSource.live,
  }) {
    final features = map['features'];
    final featuresMap = features is Map<String, dynamic> ? features : null;
    return BillingEntitlement(
      plan: map['plan']?.toString() ?? 'CORE',
      status: map['status']?.toString() ?? 'ACTIVE',
      paidUntil: map['paidUntil']?.toString(),
      daysRemaining: (map['daysRemaining'] as num?)?.toInt(),
      graceUntil: map['graceUntil']?.toString(),
      maxBranches: (featuresMap?['maxBranches'] as num?)?.toInt(),
      maxUsers: (featuresMap?['maxUsers'] as num?)?.toInt(),
      restrictedMode: map['restrictedMode'] == true,
      restrictedReason: map['restrictedReason']?.toString(),
      source: source,
    );
  }

  final String plan;
  final String status;
  final String? paidUntil;
  final int? daysRemaining;
  final String? graceUntil;
  final int? maxBranches;
  final int? maxUsers;
  final bool restrictedMode;
  final String? restrictedReason;
  final EntitlementSource source;

  bool get isActive => status.toUpperCase() == 'ACTIVE' && !restrictedMode;
  bool get isInGrace =>
      status.toUpperCase() == 'GRACE_PERIOD' ||
      status.toUpperCase() == 'PAST_DUE' ||
      (restrictedMode && status.toUpperCase() != 'RESTRICTED');

  /// Coarse client-side state used for banner copy and colors.
  EntitlementState get state {
    if (restrictedMode) return EntitlementState.restricted;
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return EntitlementState.active;
      case 'GRACE_PERIOD':
      case 'PAST_DUE':
        return EntitlementState.grace;
      case 'RESTRICTED':
        return EntitlementState.restricted;
      default:
        return EntitlementState.unknown;
    }
  }

  BillingEntitlement copyWith({EntitlementSource? source}) =>
      BillingEntitlement(
        plan: plan,
        status: status,
        paidUntil: paidUntil,
        daysRemaining: daysRemaining,
        graceUntil: graceUntil,
        maxBranches: maxBranches,
        maxUsers: maxUsers,
        restrictedMode: restrictedMode,
        restrictedReason: restrictedReason,
        source: source ?? this.source,
      );
}

/// Where an entitlement snapshot came from.
enum EntitlementSource { live, offlineCache }