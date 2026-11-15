import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cache/swr_cache.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../sales/presentation/providers/catalog_provider.dart';

/// What the price list knows about its link to the shop's server.
class PriceSyncState {
  const PriceSyncState({
    this.syncing = false,
    this.lastSyncedAt,
    this.lastFailed = false,
    this.deviceOnly = false,
  });

  /// A refresh from the server is running right now.
  final bool syncing;

  /// When the prices were last confirmed against the server.
  final DateTime? lastSyncedAt;

  /// The last attempt could not reach the server: the list shows saved prices.
  final bool lastFailed;

  /// This shop keeps its prices on the phone only, so there is no server to ask.
  final bool deviceOnly;

  PriceSyncState copyWith({
    bool? syncing,
    DateTime? lastSyncedAt,
    bool? lastFailed,
  }) =>
      PriceSyncState(
        syncing: syncing ?? this.syncing,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastFailed: lastFailed ?? this.lastFailed,
        deviceOnly: deviceOnly,
      );
}

/// Pulls the shop's current catalogue from the server into the phone, for the
/// price list. It reuses the catalogue sync the Products and Inventory screens
/// already use, so there is one way prices reach the phone.
///
/// - A shop that keeps everything on the phone (or a build with no server
///   configured) has nothing to pull: [refresh] succeeds at once and the screen
///   only re-reads the local list.
/// - A failed refresh never clears anything. The screen keeps the saved prices
///   and says so calmly.
class PriceListSync extends StateNotifier<PriceSyncState> {
  PriceListSync({
    required Future<void> Function() sync,
    required bool deviceOnly,
    required String scopeKey,
    SwrCache? cache,
    DateTime Function()? clock,
    this.autoSyncAfter = const Duration(minutes: 5),
  })  : _sync = sync,
        _scopeKey = scopeKey,
        _clock = clock ?? DateTime.now,
        _cache = cache ?? _defaultCache,
        super(PriceSyncState(deviceOnly: deviceOnly)) {
    _ready = _restore();
  }

  static final _defaultCache = SwrCache(
    namespace: 'pricelist_sync',
    schemaVersion: 1,
    softTtl: Duration.zero,
    hardTtl: const Duration(days: 60),
  );

  final Future<void> Function() _sync;
  final String _scopeKey;
  final DateTime Function() _clock;
  final SwrCache _cache;

  /// How old the last sync may be before opening the page starts a quiet one.
  final Duration autoSyncAfter;

  late final Future<void> _ready;
  Future<bool>? _running;

  Future<void> _restore() async {
    try {
      final entry = await _cache.read(_scopeKey);
      if (entry != null && mounted && state.lastSyncedAt == null) {
        state = state.copyWith(lastSyncedAt: entry.savedAt);
      }
    } catch (_) {
      // Nothing saved: the page simply shows "Not updated yet".
    }
  }

  /// Opening the page: refresh quietly when the prices are older than
  /// [autoSyncAfter]. Never complains; the page just shows the saved prices.
  Future<void> syncIfStale() async {
    if (state.deviceOnly) return;
    await _ready;
    if (!mounted) return;
    final at = state.lastSyncedAt;
    if (at != null && _clock().difference(at) < autoSyncAfter) return;
    await refresh();
  }

  /// Pulls the catalogue now. Returns whether the prices are confirmed.
  /// Calls made while one is running share it.
  Future<bool> refresh() {
    final running = _running;
    if (running != null) return running;
    final run = _refresh();
    _running = run;
    run.whenComplete(() {
      if (identical(_running, run)) _running = null;
    }).ignore();
    return run;
  }

  Future<bool> _refresh() async {
    if (state.deviceOnly) return true;
    await _ready;
    if (!mounted) return false;
    state = state.copyWith(syncing: true);
    try {
      await _sync();
    } catch (_) {
      if (mounted) state = state.copyWith(syncing: false, lastFailed: true);
      return false;
    }
    final now = _clock();
    try {
      await _cache.write(_scopeKey, {'ok': true});
    } catch (_) {}
    if (mounted) {
      state = state.copyWith(
        syncing: false,
        lastSyncedAt: now,
        lastFailed: false,
      );
    }
    return true;
  }
}

String _scopeFromStorage() {
  if (!getIt.isRegistered<StorageService>()) return 'unknown';
  final user = getIt<StorageService>().getUser() ?? {};
  return '${user['tenantId'] ?? ''}:${user['branchId'] ?? ''}';
}

bool _hasServer() =>
    getIt.isRegistered<AuthService>() && !getIt<AuthService>().isLocalWorkspace;

final priceListSyncProvider =
    StateNotifierProvider.autoDispose<PriceListSync, PriceSyncState>((ref) {
  return PriceListSync(
    sync: syncCatalogCacheFromApi,
    deviceOnly: !_hasServer(),
    scopeKey: _scopeFromStorage(),
  );
});
