import 'package:flutter/foundation.dart';

/// Entitlement state as seen from the mobile client.
enum EntitlementState { active, grace, restricted, unknown }

/// The modules a company can be licensed for. Keys match the backend's
/// `LICENSE_FEATURES` (backend/src/license/license.catalog.ts).
class LicensedFeature {
  const LicensedFeature._();
  static const analytics = 'analytics';
  static const customReports = 'customReports';
  static const aiAssistant = 'aiAssistant';
  static const multiCurrency = 'multiCurrency';
  static const prioritySupport = 'prioritySupport';

  static const labels = <String, String>{
    analytics: 'Sales analytics',
    customReports: 'Custom reports and exports',
    aiAssistant: 'Axon AI assistant',
    multiCurrency: 'Multi-currency',
    prioritySupport: 'Priority support',
  };

  static const blurbs = <String, String>{
    analytics: 'Trends, top products, cashier and payment breakdowns.',
    customReports: 'Build and export your own reports.',
    aiAssistant: 'Ask questions about your shop and get daily briefs.',
    multiCurrency: 'Sell and report in more than one currency.',
    prioritySupport: 'Jump the queue when you need help.',
  };
}

/// Which modules this company has paid for, as reported by the server.
///
/// The server is the gate (it answers 402 for an unlicensed module); this only
/// lets the app show a lock instead of a failing screen. It fails open: with
/// no licence information, or while the operator has enforcement switched
/// off, every module reads as available.
@immutable
class ClientLicense {
  const ClientLicense({
    this.enforced = false,
    this.expired = false,
    this.features = const {},
    this.planFeatures = const {},
    this.maxBranches,
    this.maxUsers,
    this.validUntil,
    this.licenseKey,
  });

  factory ClientLicense.fromMap(Map<String, dynamic> map) {
    Map<String, bool> flags(Object? raw) => raw is Map
        ? {
            for (final e in raw.entries)
              if (e.value is bool) e.key.toString(): e.value as bool,
          }
        : const {};
    final limits = map['limits'];
    return ClientLicense(
      enforced: map['enforced'] == true,
      expired: map['expired'] == true,
      features: flags(map['features']),
      planFeatures: flags(map['planFeatures']),
      maxBranches: limits is Map ? (limits['maxBranches'] as num?)?.toInt() : null,
      maxUsers: limits is Map ? (limits['maxUsers'] as num?)?.toInt() : null,
      validUntil: map['validUntil']?.toString(),
      licenseKey: map['licenseKey']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'enforced': enforced,
        'expired': expired,
        'features': features,
        'planFeatures': planFeatures,
        'limits': {'maxBranches': maxBranches, 'maxUsers': maxUsers},
        'validUntil': validUntil,
        'licenseKey': licenseKey,
      };

  final bool enforced;
  final bool expired;
  final Map<String, bool> features;
  final Map<String, bool> planFeatures;
  final int? maxBranches;
  final int? maxUsers;
  final String? validUntil;
  final String? licenseKey;

  /// Whether [feature] may be used right now. Unknown keys are allowed.
  bool allows(String feature) {
    if (!enforced) return true;
    if (expired) return false;
    return features[feature] ?? true;
  }

  /// Modules the current plan does not include (for the upgrade list).
  List<String> get lockedFeatures => [
        for (final e in planFeatures.entries)
          if (!e.value) e.key,
      ];
}

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
    this.daysOverdue = 0,
    this.graceUntil,
    this.maxBranches,
    this.maxUsers,
    this.restrictedMode = false,
    this.restrictedReason,
    this.license,
    this.source = EntitlementSource.live,
  });

  factory BillingEntitlement.fromMap(
    Map<String, dynamic> map, {
    EntitlementSource source = EntitlementSource.live,
  }) {
    final features = map['features'];
    final featuresMap = features is Map<String, dynamic> ? features : null;
    // An older server counted past the end of the paid period as negative
    // days. Never show or compare a negative: fold it into "days overdue".
    final rawDays = (map['daysRemaining'] as num?)?.toInt();
    final overdue = (map['daysOverdue'] as num?)?.toInt() ??
        ((rawDays != null && rawDays < 0) ? -rawDays : 0);
    return BillingEntitlement(
      plan: map['plan']?.toString() ?? 'CORE',
      status: map['status']?.toString() ?? 'ACTIVE',
      paidUntil: map['paidUntil']?.toString(),
      daysRemaining: rawDays == null ? null : (rawDays < 0 ? 0 : rawDays),
      daysOverdue: overdue,
      graceUntil: map['graceUntil']?.toString(),
      maxBranches: (featuresMap?['maxBranches'] as num?)?.toInt(),
      maxUsers: (featuresMap?['maxUsers'] as num?)?.toInt(),
      restrictedMode: map['restrictedMode'] == true,
      restrictedReason: map['restrictedReason']?.toString(),
      license: map['license'] is Map
          ? ClientLicense.fromMap(Map<String, dynamic>.from(map['license'] as Map))
          : null,
      source: source,
    );
  }

  final String plan;
  final String status;
  final String? paidUntil;
  final int? daysRemaining;

  /// Whole days past the end of the paid period (0 while it is still running).
  final int daysOverdue;
  final String? graceUntil;
  final int? maxBranches;
  final int? maxUsers;
  final bool restrictedMode;
  final String? restrictedReason;

  /// Null when the server sent none (older backend) or we are offline with no
  /// cached copy — treated as "everything available".
  final ClientLicense? license;
  final EntitlementSource source;

  /// Whether [feature] may be used right now (see [ClientLicense.allows]).
  bool allows(String feature) => license?.allows(feature) ?? true;

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

  BillingEntitlement copyWith({
    EntitlementSource? source,
    ClientLicense? license,
  }) =>
      BillingEntitlement(
        plan: plan,
        status: status,
        paidUntil: paidUntil,
        daysRemaining: daysRemaining,
        daysOverdue: daysOverdue,
        graceUntil: graceUntil,
        maxBranches: maxBranches,
        maxUsers: maxUsers,
        restrictedMode: restrictedMode,
        restrictedReason: restrictedReason,
        license: license ?? this.license,
        source: source ?? this.source,
      );
}

/// The server serialises money (Prisma Decimal) as a string such as
/// "3200.00". A hard `as num` cast on it throws while the page builds, which
/// in a release build paints the whole screen grey. Accept either form.
num parseBillingAmount(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

/// Where an entitlement snapshot came from.
enum EntitlementSource { live, offlineCache }