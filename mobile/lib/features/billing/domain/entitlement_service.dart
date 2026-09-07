import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'billing_entitlement.dart';

/// How long a fetched live entitlement is considered fresh before we try
/// to refresh it again from the network.
const Duration entitlementRefreshInterval = Duration(minutes: 30);

/// Offline signed-entitlement cache.
///
/// The backend issues `GET /billing/entitlement/offline` as
/// `base64url(payloadJson).base64url(hmac-sha256(payloadSegment, secret))`
/// — JWT-style two unpadded base64url segments, HMAC keyed with
/// ENTITLEMENT_SECRET (or the JWT secret). The token is stored in
/// SharedPreferences: it is not a secret, only its *integrity* is
/// protected, and the client re-verifies the HMAC on load so a tampered
/// or hand-edited token can never unlock features.
///
/// Offline resolution rules:
///  - signature invalid / payload unreadable → RESTRICTED (fail closed)
///  - now < payload.validUntil               → ACTIVE
///  - validUntil <= now < graceUntil         → GRACE (banner shows)
///  - now >= graceUntil                      → RESTRICTED
class EntitlementService {
  EntitlementService({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const _cacheKey = 'billing_entitlement_signed_token';
  static const _fetchedAtKey = 'billing_entitlement_fetched_at_ms';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _prefsFuture async =>
      _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();

  /// Verify + decode a signed token without touching storage. Static and
  /// pure so it is directly unit-testable.
  ///
  /// Returns the embedded entitlement (with [EntitlementSource.offlineCache])
  /// or null when the token is malformed, signed with the wrong key, or its
  /// `validUntil` has passed. Grace is NOT folded in here — callers that
  /// need the full offline decision use [resolveCached].
  static BillingEntitlement? verifySignedToken(String token) {
    final parts = token.split('.');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    final payloadSegment = parts[0];

    Uint8List payloadBytes;
    try {
      payloadBytes = _base64UrlDecode(payloadSegment);
    } on FormatException {
      return null;
    }

    // HMAC is computed over the raw base64url payload segment (ASCII bytes),
    // exactly like a JWT signature covers the encoded header/payload — so
    // any re-encoded-but-equivalent payload fails verification.
    final expected = Hmac(sha256, utf8.encode(secretKey))
        .convert(utf8.encode(payloadSegment))
        .bytes;
    final Uint8List providedBytes;
    try {
      providedBytes = _base64UrlDecode(parts[1]);
    } on FormatException {
      return null;
    }
    if (!_constantTimeEquals(providedBytes, expected)) return null;

    Map<String, dynamic> payload;
    try {
      final decoded = utf8.decode(payloadBytes);
      final jsonValue = jsonDecode(decoded);
      if (jsonValue is! Map<String, dynamic>) return null;
      payload = jsonValue;
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }

    // Expired payload (validUntil passed)? Fail closed; grace is handled by
    // [resolveCached] which needs the graceUntil timestamp.
    final validUntilMs = (payload['validUntil'] as num?)?.toInt();
    if (validUntilMs != null) {
      final validUntil =
          DateTime.fromMillisecondsSinceEpoch(validUntilMs);
      if (DateTime.now().isAfter(validUntil)) return null;
    }

    return BillingEntitlement.fromMap(
      payload,
      source: EntitlementSource.offlineCache,
    );
  }

  /// The shared signing secret. Configurable via --dart-define so a real
  /// deployment can inject the backend's ENTITLEMENT_SECRET without a code
  /// change; default matches local dev. Verification is a cache-integrity
  /// check on-device, not a security boundary.
  static const String secretKey = String.fromEnvironment(
    'ENTITLEMENT_SECRET',
    defaultValue: 'axon-dev-entitlement-secret',
  );

  /// Store the signed token after a successful live fetch. Also records
  /// when it was fetched so [shouldRefresh] can throttle network calls.
  Future<void> cacheSignedToken(String token) async {
    final prefs = await _prefsFuture;
    await prefs.setString(_cacheKey, token);
    await prefs.setInt(_fetchedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// The cached signed token, if any. (Exposed for tests/diagnostics.)
  Future<String?> cachedSignedToken() async {
    final prefs = await _prefsFuture;
    return prefs.getString(_cacheKey);
  }

  /// Resolve the offline entitlement decision from the cached token.
  ///
  /// Returns null when nothing valid is cached — callers treat that as
  /// RESTRICTED/offline-unknown. Otherwise:
  ///  - signature valid and now < validUntil → ACTIVE
  ///  - now within [validUntil, graceUntil)  → GRACE snapshot (banner)
  ///  - now >= graceUntil                    → RESTRICTED snapshot
  Future<BillingEntitlement?> resolveCached({DateTime? now}) async {
    final prefs = await _prefsFuture;
    final token = prefs.getString(_cacheKey);
    if (token == null || token.isEmpty) return null;

    final at = now ?? DateTime.now();
    final parts = token.split('.');
    if (parts.length != 2) return null;

    Uint8List payloadBytes;
    try {
      payloadBytes = _base64UrlDecode(parts[0]);
    } on FormatException {
      return null;
    }

    final expected = Hmac(sha256, utf8.encode(secretKey))
        .convert(utf8.encode(parts[0]))
        .bytes;
    final Uint8List providedBytes;
    try {
      providedBytes = _base64UrlDecode(parts[1]);
    } on FormatException {
      return null;
    }
    if (!_constantTimeEquals(providedBytes, expected)) return null;

    Map<String, dynamic> payload;
    try {
      final jsonValue = jsonDecode(utf8.decode(payloadBytes));
      if (jsonValue is! Map<String, dynamic>) return null;
      payload = jsonValue;
    } catch (_) {
      return null;
    }

    final validUntilMs = (payload['validUntil'] as num?)?.toInt();
    final graceUntilMs = (payload['graceUntil'] as num?)?.toInt();
    final validUntil = validUntilMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(validUntilMs);
    final graceUntil = graceUntilMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(graceUntilMs);

    final base = BillingEntitlement.fromMap(
      payload,
      source: EntitlementSource.offlineCache,
    );

    if (validUntil == null || at.isBefore(validUntil)) {
      // Signed snapshot still inside its paid window.
      return base;
    }
    if (graceUntil != null && at.isBefore(graceUntil)) {
      // Offline and the paid window lapsed, but still inside grace —
      // surface GRACE_PERIOD so the reminder banner (not the red
      // restricted banner) shows and navigation stays open.
      return BillingEntitlement(
        plan: base.plan,
        status: 'GRACE_PERIOD',
        paidUntil: base.paidUntil,
        daysRemaining: 0,
        graceUntil: base.graceUntil,
        maxBranches: base.maxBranches,
        maxUsers: base.maxUsers,
        restrictedMode: false,
        source: EntitlementSource.offlineCache,
      );
    }
    // Past grace while offline → restricted.
    return BillingEntitlement(
      plan: base.plan,
      status: 'RESTRICTED',
      paidUntil: base.paidUntil,
      daysRemaining: 0,
      graceUntil: base.graceUntil,
      maxBranches: base.maxBranches,
      maxUsers: base.maxUsers,
      restrictedMode: true,
      restrictedReason: base.restrictedReason ?? 'Subscription payment overdue',
      source: EntitlementSource.offlineCache,
    );
  }

  /// When the cache was last refreshed (null = never).
  Future<DateTime?> lastFetchedAt() async {
    final prefs = await _prefsFuture;
    final ms = prefs.getInt(_fetchedAtKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// True when a live refresh is due (stale or never fetched).
  Future<bool> isRefreshDue({
    DateTime? now,
    Duration interval = entitlementRefreshInterval,
  }) async {
    final last = await lastFetchedAt();
    if (last == null) return true;
    final at = now ?? DateTime.now();
    return at.difference(last) >= interval;
  }

  /// Clear the cache (logout, tenant switch).
  Future<void> clear() async {
    final prefs = await _prefsFuture;
    await prefs.remove(_cacheKey);
    await prefs.remove(_fetchedAtKey);
  }

  static Uint8List _base64UrlDecode(String input) =>
      base64Url.decode(base64Url.normalize(input));

  /// Constant-time comparison so a tamperer can't time the cache check.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}