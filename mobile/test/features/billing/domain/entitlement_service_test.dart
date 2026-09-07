import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:axon_pos/features/billing/domain/billing_entitlement.dart';
import 'package:axon_pos/features/billing/domain/entitlement_service.dart';

/// Builds a signed token the same way the backend does:
/// base64url(payloadJson).base64url(hmac-sha256(payloadSegment, secret)).
String _sign(Map<String, dynamic> payload, {String? key}) {
  final payloadJson = jsonEncode(payload);
  final segment = base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');
  final secret = key ?? EntitlementService.secretKey;
  final mac = Hmac(sha256, utf8.encode(secret))
      .convert(utf8.encode(segment))
      .bytes;
  final sig = base64Url.encode(mac).replaceAll('=', '');
  return '$segment.$sig';
}

/// Takes a valid token, decodes its payload, edits it, re-encodes — but
/// keeps the original signature (the classic tamper attempt the verifier
/// must reject).
String _reSignWithDifferentPayload(String validToken) {
  final parts = validToken.split('.');
  final payloadBytes = base64Url.decode(
      base64Url.normalize(parts[0]));
  final payloadJson = utf8.decode(payloadBytes)
      .replaceFirst('"daysRemaining":30', '"daysRemaining":999');
  final tamperedSegment =
      base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');
  return '$tamperedSegment.${parts[1]}';
}

Map<String, dynamic> _payload({
  int? validUntilMs,
  int? graceUntilMs,
  bool restricted = false,
}) {
  final now = DateTime.now();
  return {
    'plan': 'CORE',
    'status': 'ACTIVE',
    'paidUntil': now.add(const Duration(days: 30)).toIso8601String(),
    'daysRemaining': 30,
    if (validUntilMs != null) 'validUntil': validUntilMs,
    if (graceUntilMs != null) 'graceUntil': graceUntilMs,
    'features': {'maxBranches': 3, 'maxUsers': 10},
    'restrictedMode': restricted,
  };
}

void main() {
  group('EntitlementService.verifySignedToken', () {
    test('verifies and decodes a correctly signed token', () {
      final token = _sign(_payload(
        validUntilMs: DateTime.now()
            .add(const Duration(days: 2))
            .millisecondsSinceEpoch,
      ));

      final entitlement = EntitlementService.verifySignedToken(token);

      expect(entitlement, isNotNull);
      expect(entitlement!.plan, 'CORE');
      expect(entitlement.status, 'ACTIVE');
      expect(entitlement.daysRemaining, 30);
      expect(entitlement.maxBranches, 3);
      expect(entitlement.maxUsers, 10);
      expect(entitlement.restrictedMode, isFalse);
      expect(entitlement.source, EntitlementSource.offlineCache);
    });

    test('rejects a tampered payload', () {
      final token = _sign(_payload(
        validUntilMs: DateTime.now()
            .add(const Duration(days: 2))
            .millisecondsSinceEpoch,
      ));
      // Tamper the *decoded* payload, then re-sign with the wrong key —
      // i.e. someone edits daysRemaining and re-encodes without the secret.
      final tampered = _reSignWithDifferentPayload(token);

      expect(EntitlementService.verifySignedToken(tampered), isNull);
    });

    test('rejects a token signed with the wrong key', () {
      final token = _sign(_payload(
        validUntilMs: DateTime.now()
            .add(const Duration(days: 2))
            .millisecondsSinceEpoch,
      ), key: 'attacker-key');

      expect(EntitlementService.verifySignedToken(token), isNull);
    });

    test('rejects a malformed token (no dot / one segment / bad base64)', () {
      expect(EntitlementService.verifySignedToken('not-a-token'), isNull);
      expect(EntitlementService.verifySignedToken('a.b.c'), isNull);
      expect(EntitlementService.verifySignedToken('!!!.!!!'), isNull);
    });

    test('rejects an expired token (validUntil passed)', () {
      final token = _sign(_payload(
        validUntilMs: DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      ));

      expect(EntitlementService.verifySignedToken(token), isNull);
    });
  });

  group('EntitlementService.resolveCached (offline decision)', () {
    test('returns null when nothing is cached', () async {
      SharedPreferences.setMockInitialValues({});
      final service = EntitlementService();

      expect(await service.resolveCached(), isNull);
    });

    test('valid window → ACTIVE', () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'billing_entitlement_signed_token': _sign(_payload(
          validUntilMs: now.add(const Duration(days: 2)).millisecondsSinceEpoch,
          graceUntilMs: now.add(const Duration(days: 5)).millisecondsSinceEpoch,
        )),
      });
      final service = EntitlementService();

      final result = await service.resolveCached();

      expect(result, isNotNull);
      expect(result!.state, EntitlementState.active);
      expect(result.status, 'ACTIVE');
      expect(result.restrictedMode, isFalse);
    });

    test('within grace → GRACE_PERIOD snapshot (banner, not blocked)',
        () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'billing_entitlement_signed_token': _sign(_payload(
          validUntilMs:
              now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          graceUntilMs:
              now.add(const Duration(days: 2)).millisecondsSinceEpoch,
        )),
      });
      final service = EntitlementService();

      final result = await service.resolveCached();

      expect(result, isNotNull);
      expect(result!.state, EntitlementState.grace);
      expect(result.status, 'GRACE_PERIOD');
      expect(result.restrictedMode, isFalse);
    });

    test('past grace → RESTRICTED snapshot', () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'billing_entitlement_signed_token': _sign(_payload(
          validUntilMs:
              now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
          graceUntilMs:
              now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        )),
      });
      final service = EntitlementService();

      final result = await service.resolveCached();

      expect(result, isNotNull);
      expect(result!.state, EntitlementState.restricted);
      expect(result.status, 'RESTRICTED');
      expect(result.restrictedMode, isTrue);
      expect(result.restrictedReason, isNotNull);
    });

    test('tampered cached token → null (fail closed)', () async {
      final now = DateTime.now();
      final token = _sign(_payload(
        validUntilMs: now.add(const Duration(days: 2)).millisecondsSinceEpoch,
        graceUntilMs: now.add(const Duration(days: 5)).millisecondsSinceEpoch,
      ));
      SharedPreferences.setMockInitialValues({
        'billing_entitlement_signed_token':
            _reSignWithDifferentPayload(token),
      });
      final service = EntitlementService();

      expect(await service.resolveCached(), isNull);
    });

    test('cacheSignedToken stores token and records fetch time', () async {
      SharedPreferences.setMockInitialValues({});
      final service = EntitlementService();
      final token = _sign(_payload(
        validUntilMs:
            DateTime.now().add(const Duration(days: 2)).millisecondsSinceEpoch,
      ));

      await service.cacheSignedToken(token);

      expect(await service.cachedSignedToken(), token);
      expect(await service.lastFetchedAt(), isNotNull);
      expect(await service.isRefreshDue(), isFalse);
    });

    test('isRefreshDue is true when never fetched or stale', () async {
      SharedPreferences.setMockInitialValues({});
      final service = EntitlementService();
      expect(await service.isRefreshDue(), isTrue);

      // Simulate a fetch an hour ago (past the 30-minute refresh interval).
      SharedPreferences.setMockInitialValues({
        'billing_entitlement_fetched_at_ms': DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      });
      expect(await service.isRefreshDue(), isTrue);

      // And a fetch just now (fresh) → not due. Cache the token through
      // the service so its in-memory prefs singleton stays consistent.
      await service.cacheSignedToken(_sign(_payload()));
      expect(await service.isRefreshDue(), isFalse);
    });
  });

  group('BillingEntitlement', () {
    test('state mapping', () {
      expect(
        const BillingEntitlement(plan: 'CORE', status: 'ACTIVE').state,
        EntitlementState.active,
      );
      expect(
        const BillingEntitlement(plan: 'CORE', status: 'GRACE_PERIOD').state,
        EntitlementState.grace,
      );
      expect(
        const BillingEntitlement(plan: 'CORE', status: 'PAST_DUE').state,
        EntitlementState.grace,
      );
      expect(
        const BillingEntitlement(plan: 'CORE', status: 'ACTIVE', restrictedMode: true)
            .state,
        EntitlementState.restricted,
      );
    });

    test('fromMap tolerates missing fields', () {
      final e = BillingEntitlement.fromMap(const {});
      expect(e.plan, 'CORE');
      expect(e.daysRemaining, isNull);
      expect(e.restrictedMode, isFalse);
      expect(e.state, EntitlementState.active);
    });
  });
}