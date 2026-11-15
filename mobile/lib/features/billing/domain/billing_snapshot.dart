import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Everything the Plan & Billing page shows, as of the last time the server
/// answered, so the page can paint at once and refresh behind it instead of
/// waiting on the network every time it opens.
///
/// Stale-while-revalidate: a snapshot younger than [softTtl] needs no refresh;
/// one between [softTtl] and [hardTtl] is shown straight away and refreshed in
/// the background; an older one, or one written by a different schema, is
/// ignored. A failed refresh never replaces a snapshot.
class BillingSnapshot {
  const BillingSnapshot({
    required this.savedAt,
    this.entitlement,
    this.plan,
    this.invoices = const [],
    this.settings,
  });

  /// Bump when the stored shape changes; older copies are then ignored.
  static const schemaVersion = 1;
  static const softTtl = Duration(minutes: 5);
  static const hardTtl = Duration(days: 7);

  final DateTime savedAt;

  /// `GET /billing/entitlement`
  final Map<String, dynamic>? entitlement;

  /// `GET /subscription/plan` (current plan, scheduled change, plan prices)
  final Map<String, dynamic>? plan;

  /// `GET /billing/invoices`
  final List<dynamic> invoices;

  /// `GET /billing/settings` (owner only)
  final Map<String, dynamic>? settings;

  bool isFresh([DateTime? now]) =>
      (now ?? DateTime.now()).difference(savedAt) < softTtl;

  bool isUsable([DateTime? now]) =>
      (now ?? DateTime.now()).difference(savedAt) < hardTtl;

  bool get isEmpty => entitlement == null && plan == null && invoices.isEmpty;

  BillingSnapshot copyWith({
    Map<String, dynamic>? entitlement,
    Map<String, dynamic>? plan,
    List<dynamic>? invoices,
    Map<String, dynamic>? settings,
    DateTime? savedAt,
  }) =>
      BillingSnapshot(
        savedAt: savedAt ?? this.savedAt,
        entitlement: entitlement ?? this.entitlement,
        plan: plan ?? this.plan,
        invoices: invoices ?? this.invoices,
        settings: settings ?? this.settings,
      );

  Map<String, dynamic> toJson() => {
        'v': schemaVersion,
        'savedAt': savedAt.millisecondsSinceEpoch,
        'entitlement': entitlement,
        'plan': plan,
        'invoices': invoices,
        'settings': settings,
      };

  static BillingSnapshot? fromJson(Object? raw) {
    if (raw is! Map || raw['v'] != schemaVersion) return null;
    final savedAt = raw['savedAt'];
    if (savedAt is! num) return null;
    Map<String, dynamic>? asMap(Object? v) =>
        v is Map ? Map<String, dynamic>.from(v) : null;
    return BillingSnapshot(
      savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt.toInt()),
      entitlement: asMap(raw['entitlement']),
      plan: asMap(raw['plan']),
      invoices: raw['invoices'] is List
          ? List<dynamic>.from(raw['invoices'] as List)
          : const [],
      settings: asMap(raw['settings']),
    );
  }
}

/// Reads and writes the [BillingSnapshot] in SharedPreferences, one copy per
/// shop so signing in to another shop never shows the first one's plan.
class BillingSnapshotStore {
  const BillingSnapshotStore();

  static String _key(String? tenantId) =>
      'billing_snapshot_v${BillingSnapshot.schemaVersion}_${tenantId ?? 'shop'}';

  Future<BillingSnapshot?> load(String? tenantId, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(tenantId));
      if (raw == null || raw.isEmpty) return null;
      final snapshot = BillingSnapshot.fromJson(jsonDecode(raw));
      if (snapshot == null || !snapshot.isUsable(now) || snapshot.isEmpty) {
        return null;
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String? tenantId, BillingSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(tenantId), jsonEncode(snapshot.toJson()));
    } catch (_) {
      // A full disk must never break the page; the snapshot is only a speed-up.
    }
  }

  Future<void> clear(String? tenantId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(tenantId));
    } catch (_) {}
  }
}
