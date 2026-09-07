import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/billing_entitlement.dart';

/// Live fetch + offline fallback, invoked on login/resume and pull-to-refresh.
///
/// Flow: try GET /billing/entitlement; on success cache the signed offline
/// token for next time. On network failure fall back to the offline cache
/// (signature re-verified with a small staleness allowance for clock skew).
/// Never throws — errors are surfaced as a RESTRICTED-unknown state and the
/// UI keeps working.
Future<BillingEntitlement?> refreshEntitlement() async {
  final service = getIt<EntitlementService>();
  try {
    final map = await getIt<ApiClient>().getBillingEntitlement();
    final entitlement = BillingEntitlement.fromMap(map);
    // Best-effort: cache the signed offline token so a future offline
    // session can still resolve its own status. Failures here are silent.
    try {
      final token = await getIt<ApiClient>().getBillingEntitlementOffline();
      if (token.isNotEmpty) await service.cacheSignedToken(token);
    } catch (_) {
      // Offline token is optional; the live snapshot above still applies.
    }
    return entitlement;
  } on DioException catch (e) {
    debugPrint('[Entitlement] live fetch failed (${e.type}), using cache');
    return _fallbackToCache(service);
  } catch (e) {
    debugPrint('[Entitlement] live fetch failed: $e');
    return _fallbackToCache(service);
  }
}

Future<BillingEntitlement?> _fallbackToCache(EntitlementService service) async {
  try {
    // Small allowance: if the token is a few minutes past validUntil but
    // still within graceUntil, resolveCached already returns the GRACE
    // snapshot — no extra handling needed here.
    return await service.resolveCached();
  } catch (e) {
    debugPrint('[Entitlement] offline cache resolve failed: $e');
    return null;
  }
}

/// FutureProvider — watched by the banner host on the home shell.
///
/// Fires when the provider is first read after login (or app resume with a
/// logged-in session) and re-executes on [entitlementRefreshTickProvider].
/// Auto-disposes when the last listener goes away so a re-login refetches.
final entitlementProvider =
    FutureProvider.autoDispose<BillingEntitlement?>((ref) async {
  ref.watch(entitlementRefreshTickProvider);
  return refreshEntitlement();
});

/// Bump to force a refetch (login, app resume, pull-to-refresh, payment).
final entitlementRefreshTickProvider = StateProvider<int>((ref) => 0);