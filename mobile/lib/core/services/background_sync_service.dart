import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:dio/dio.dart';

import '../database/app_database.dart';
import '../network/api_client.dart';
import '../services/storage_service.dart';
import 'connectivity_service.dart';

class SyncQueueProcessResult {
  final int processedCount;
  final int successCount;
  final int failureCount;
  final int conflictCount;

  const SyncQueueProcessResult({
    required this.processedCount,
    required this.successCount,
    required this.failureCount,
    required this.conflictCount,
  });

  bool get hasErrors => failureCount > 0 || conflictCount > 0;
}

/// Background Sync Service using Workmanager
/// Runs every 15 minutes to sync pending changes to the server
class BackgroundSyncService {
  static const String syncTaskName = 'sync-queue-processor';
  static const String syncTaskTag = 'background-sync';
  static const String _immediateSyncTag = 'immediate-sync';
  static const String _defaultApiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.archeaxon.com/api/v1',
  );

  // Run every 15 minutes
  static const Duration syncInterval = Duration(minutes: 15);

  // Exponential backoff delays (in seconds)
  static const List<int> retryDelays = [5, 15, 60, 300, 900];

  /// Initialize the background sync worker
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
    );

    await registerSyncTask();
  }

  /// Register the periodic sync task
  static Future<void> registerSyncTask() async {
    await Workmanager().registerPeriodicTask(
      syncTaskName,
      syncTaskName,
      frequency: syncInterval,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: Duration(seconds: retryDelays.first),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      tag: syncTaskTag,
    );
  }

  /// Trigger an immediate sync (useful for manual triggers)
  static Future<void> triggerImmediateSync() async {
    await Workmanager().registerOneOffTask(
      'sync-immediate',
      syncTaskName,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      tag: _immediateSyncTag,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  /// Cancel all sync tasks
  static Future<void> cancelAllSyncTasks() async {
    await Workmanager().cancelByTag(syncTaskTag);
    await Workmanager().cancelByTag(_immediateSyncTag);
  }

  /// Process the sync queue (called by workmanager callback)
  static Future<bool> processSyncQueue() async {
    // Create isolated instances for background work (runs in isolate,
    // separate from the app's main-isolate AuthService/AuthInterceptor —
    // this must source and refresh its own access token from secure
    // storage, or every request here 401s even with a perfectly valid
    // session (see the auth token bootstrap below).
    final storageService = StorageService();
    await storageService.initialize();
    final database = AppDatabase(storageService);
    final connectivityService = ConnectivityService();
    final expectedTenantId = storageService.getTenantId();

    try {
      if (expectedTenantId == null || expectedTenantId.isEmpty) {
        debugPrint('[BackgroundSync] No active workspace, skipping sync');
        return false;
      }
      final connectionStatus = await connectivityService.checkCurrentStatus();
      if (connectionStatus != ConnectionStatus.online) {
        debugPrint('[BackgroundSync] Device is offline, skipping sync');
        return false;
      }

      final dio = Dio(
        BaseOptions(
          baseUrl: _defaultApiBaseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

      final accessToken = await storageService.getAccessToken();
      if (accessToken == null) {
        debugPrint('[BackgroundSync] No stored session, skipping sync');
        return false;
      }
      dio.options.headers['Authorization'] = 'Bearer $accessToken';
      dio.interceptors.add(_BackgroundAuthInterceptor(storageService, dio));

      final apiClient = ApiClient(dio);

      final result = await processPendingQueue(
        database: database,
        apiClient: apiClient,
        expectedTenantId: expectedTenantId,
      );

      debugPrint(
        '[BackgroundSync] Completed: ${result.successCount} synced, '
        '${result.failureCount} failed, ${result.conflictCount} conflicts',
      );

      final cleaned = await database.cleanupSyncQueue(olderThanDays: 30);
      if (cleaned > 0) {
        debugPrint('[BackgroundSync] Cleaned up $cleaned old sync items');
      }

      return !result.hasErrors;
    } catch (e) {
      debugPrint('[BackgroundSync] Fatal error: $e');
      return false;
    } finally {
      try {
        connectivityService.dispose();
      } catch (_) {}
      try {
        await database.close();
      } catch (_) {}
    }
  }

  static Future<SyncQueueProcessResult> processPendingQueue({
    required AppDatabase database,
    required ApiClient apiClient,
    required String expectedTenantId,
  }) async {
    if (database.activeTenantId != expectedTenantId) {
      return const SyncQueueProcessResult(
        processedCount: 0,
        successCount: 0,
        failureCount: 0,
        conflictCount: 0,
      );
    }
    final pendingItems = await database.getPendingSyncQueue();

    if (pendingItems.isEmpty) {
      return const SyncQueueProcessResult(
        processedCount: 0,
        successCount: 0,
        failureCount: 0,
        conflictCount: 0,
      );
    }

    // Customers referenced by offline sales must exist on the server first.
    // Recovered customer events can have a newer queue sequence than an older
    // sale, so process customer creates ahead of other events and hold their
    // dependent sales until the create is confirmed.
    pendingItems.sort((a, b) {
      final aPriority = a.eventType == 'CUSTOMER_CREATED' ? 0 : 1;
      final bPriority = b.eventType == 'CUSTOMER_CREATED' ? 0 : 1;
      final priorityOrder = aPriority.compareTo(bPriority);
      return priorityOrder != 0
          ? priorityOrder
          : a.sequenceNumber.compareTo(b.sequenceNumber);
    });
    final customersAwaitingCreate =
        await database.getUnresolvedCustomerCreateSyncRecordIds();

    debugPrint(
        '[BackgroundSync] Processing ${pendingItems.length} pending items');

    var successCount = 0;
    var failureCount = 0;
    var conflictCount = 0;

    for (final item in pendingItems) {
      if (database.activeTenantId != expectedTenantId) break;

      if (item.eventType == 'SALE_CREATED') {
        try {
          final payload = jsonDecode(item.payload) as Map<String, dynamic>;
          final customerId = payload['customerId']?.toString();
          if (customerId != null &&
              customerId.isNotEmpty &&
              customersAwaitingCreate.contains(customerId)) {
            debugPrint(
              '[BackgroundSync] Waiting to sync sale ${item.recordId} until customer $customerId is available',
            );
            continue;
          }
        } catch (_) {
          // The event will reach the normal payload validation path below.
        }
      }

      try {
        final response = await apiClient.pushSyncEvents({
          'events': [_buildSyncEventPayload(item)],
        }, expectedTenantId: expectedTenantId);
        if (database.activeTenantId != expectedTenantId) break;

        final results = response['results'] as List<dynamic>?;
        final firstResult = results != null && results.isNotEmpty
            ? Map<String, dynamic>.from(results.first as Map)
            : null;

        if (firstResult == null) {
          await database.scheduleSyncQueueRetry(
            item.id,
            'Server returned no sync result',
            _retryDelayFor(item.retryCount),
          );
          failureCount++;
        } else if (firstResult['success'] == true) {
          final serverId = firstResult['serverId']?.toString() ??
              firstResult['eventId']?.toString() ??
              item.recordId;
          final serverTimestamp = DateTime.tryParse(
                firstResult['serverTimestamp']?.toString() ?? '',
              ) ??
              DateTime.now();

          await database.markSyncQueueSynced(
            item.id,
            serverId,
            serverTimestamp,
          );
          await _markRelatedLocalDataAsSynced(
            database,
            item,
            receiptNumber: firstResult['receiptNumber']?.toString(),
          );
          if (item.eventType == 'CUSTOMER_CREATED') {
            customersAwaitingCreate.remove(item.recordId);
          }
          successCount++;
          debugPrint(
              '[BackgroundSync] ✓ Synced: ${item.entityTable}/${item.action}');
        } else {
          final errorMessage =
              firstResult['error']?.toString() ?? 'Unknown server error';

          if (_isConflictError(errorMessage)) {
            await database.markSyncQueueConflict(item.id, errorMessage);
            conflictCount++;
          } else if (firstResult['retryable'] == true ||
              _isRetryableServerError(errorMessage)) {
            await database.scheduleSyncQueueRetry(
              item.id,
              errorMessage,
              _retryDelayFor(item.retryCount),
            );
            failureCount++;
          } else {
            await database.markSyncQueueFailed(item.id, errorMessage);
            failureCount++;
          }

          debugPrint(
            '[BackgroundSync] ✗ Failed: ${item.entityTable}/${item.action} - $errorMessage',
          );
        }
      } on DioException catch (e) {
        if (database.activeTenantId != expectedTenantId) break;
        final errorMessage = _describeDioException(e);

        if (_isConflictException(e)) {
          await database.markSyncQueueConflict(item.id, errorMessage);
          conflictCount++;
        } else if (_isRetryableDioException(e)) {
          await database.scheduleSyncQueueRetry(
            item.id,
            errorMessage,
            _retryDelayFor(item.retryCount),
          );
          failureCount++;
        } else {
          await database.markSyncQueueFailed(item.id, errorMessage);
          failureCount++;
        }

        debugPrint(
          '[BackgroundSync] ✗ Failed: ${item.entityTable}/${item.action} - $errorMessage',
        );
      } catch (e) {
        if (database.activeTenantId != expectedTenantId) break;
        final errorMessage = 'Error: $e';
        await database.markSyncQueueFailed(item.id, errorMessage);
        failureCount++;

        debugPrint(
          '[BackgroundSync] ✗ Exception: ${item.entityTable}/${item.action} - $errorMessage',
        );
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    return SyncQueueProcessResult(
      // A tenant switch can stop the loop before every row was attempted.
      // Report only outcomes that were actually handled in this session.
      processedCount: successCount + failureCount + conflictCount,
      successCount: successCount,
      failureCount: failureCount,
      conflictCount: conflictCount,
    );
  }

  static Map<String, dynamic> _buildSyncEventPayload(SyncQueueData item) {
    final payload = Map<String, dynamic>.from(
      jsonDecode(item.payload) as Map,
    )..remove('_localTenantId');
    return {
      'eventId': item.id,
      'eventType': item.eventType,
      'payload': payload,
      'deviceId': item.deviceId,
      'createdAt': item.createdAt.toIso8601String(),
      'sequenceNumber': item.sequenceNumber,
    };
  }

  static Future<void> _markRelatedLocalDataAsSynced(
    AppDatabase database,
    SyncQueueData item, {
    String? receiptNumber,
  }) async {
    if (item.eventType != 'SALE_CREATED') {
      return;
    }

    final payload = Map<String, dynamic>.from(
      jsonDecode(item.payload) as Map<String, dynamic>,
    );
    final offlineId = payload['offlineId']?.toString() ?? item.recordId;

    if (offlineId.isNotEmpty) {
      await database.markSaleAsSynced(offlineId);
      // Replace the phone's temporary RCP- number with the server's, so the
      // receipt, dashboard and reports all quote the same one.
      if (receiptNumber != null && receiptNumber.isNotEmpty) {
        await database.updateSaleReceiptNumber(offlineId, receiptNumber);
      }
    }
  }

  static Duration _retryDelayFor(int retryCount) {
    final index = retryCount.clamp(0, retryDelays.length - 1);
    return Duration(seconds: retryDelays[index]);
  }

  static bool _isConflictError(String errorMessage) {
    final normalized = errorMessage.toLowerCase();
    return normalized.contains('conflict') ||
        normalized.contains('concurrent update') ||
        normalized.contains('deleted on server') ||
        normalized.contains('manual resolution');
  }

  static bool _isRetryableServerError(String errorMessage) {
    final normalized = errorMessage.toLowerCase();
    return normalized.contains('timeout') ||
        normalized.contains('temporar') ||
        normalized.contains('rate limit') ||
        normalized.contains('server error') ||
        normalized.contains('network');
  }

  static bool _isConflictException(DioException error) {
    return error.response?.statusCode == 409 ||
        _isConflictError(
          error.response?.data?.toString() ?? error.message ?? 'Conflict',
        );
  }

  static bool _isRetryableDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.unknown ||
        statusCode == 429 ||
        // 401 here means this isolate's own refresh-and-retry (see
        // _BackgroundAuthInterceptor) already failed once for this request —
        // could still be a transient token race, not proof the sale itself
        // is invalid. Treat as retryable so a queued sale isn't permanently
        // lost to an auth hiccup with no user-visible recovery.
        statusCode == 401 ||
        (statusCode != null && statusCode >= 500);
  }

  static String _describeDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    final responseData = error.response?.data;

    if (statusCode != null && responseData != null) {
      return 'HTTP $statusCode: $responseData';
    }

    if (statusCode != null) {
      return 'HTTP $statusCode: ${error.message ?? 'Request failed'}';
    }

    return 'Network error: ${error.message ?? 'Unknown network error'}';
  }

  /// Get sync queue statistics
  static Future<Map<String, int>> getSyncStats() async {
    final storageService = StorageService();
    final database = AppDatabase(storageService);

    try {
      return await database.getSyncQueueStats();
    } finally {
      await database.close();
    }
  }

  /// Retry all failed items
  static Future<void> retryFailedItems() async {
    final storageService = StorageService();
    final database = AppDatabase(storageService);

    try {
      final failedItems = await database.getFailedSyncQueue();
      for (final item in failedItems) {
        await database.resetSyncQueueItem(item.id);
      }
    } finally {
      await database.close();
    }

    await triggerImmediateSync();
  }
}

/// Workmanager callback dispatcher (runs in isolate)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('[BackgroundSync] Task started: $task');

      switch (task) {
        case BackgroundSyncService.syncTaskName:
        case 'sync-immediate':
          final success = await BackgroundSyncService.processSyncQueue();
          debugPrint(
              '[BackgroundSync] Task completed: ${success ? 'SUCCESS' : 'PARTIAL'}');
          return success;

        default:
          debugPrint('[BackgroundSync] Unknown task: $task');
          return false;
      }
    } catch (e) {
      debugPrint('[BackgroundSync] Task failed: $e');
      return Future.value(false);
    }
  });
}

/// Standalone 401-refresh-and-retry for the background-sync isolate, which
/// has no [AuthService]/main-isolate [AuthInterceptor] to share. Mirrors
/// their single-flight refresh + rotate-on-use handling so a 15-minute
/// access token expiring mid-background-sync doesn't fail every queued item.
class _BackgroundAuthInterceptor extends Interceptor {
  final StorageService _storage;
  final Dio _dio;
  Future<String?>? _refreshFuture;

  _BackgroundAuthInterceptor(this._storage, this._dio);

  bool _matchesExpectedTenant(RequestOptions options) {
    final expectedTenantId = options.extra['expectedTenantId']?.toString();
    return expectedTenantId == null ||
        expectedTenantId == _storage.getTenantId();
  }

  DioException _sessionChanged(RequestOptions options) => DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        message: 'The signed-in workspace changed during sync.',
      );

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_matchesExpectedTenant(options)) {
      return handler.reject(_sessionChanged(options));
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_matchesExpectedTenant(err.requestOptions)) {
      return handler.next(err);
    }
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    try {
      final expectedTenantId =
          err.requestOptions.extra['expectedTenantId']?.toString();
      _refreshFuture ??= _refresh(expectedTenantId);
      final newAccessToken = await _refreshFuture;
      _refreshFuture = null;
      if (newAccessToken == null ||
          !_matchesExpectedTenant(err.requestOptions)) {
        return handler.next(err);
      }

      final opts = err.requestOptions;
      if (!_matchesExpectedTenant(opts)) return handler.next(err);
      opts.headers['Authorization'] = 'Bearer $newAccessToken';
      final response = await _dio.fetch(opts);
      return handler.resolve(response);
    } catch (_) {
      _refreshFuture = null;
      return handler.next(err);
    }
  }

  Future<String?> _refresh(String? expectedTenantId) async {
    if (expectedTenantId != null &&
        _storage.getTenantId() != expectedTenantId) {
      return null;
    }
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) return null;
    if (expectedTenantId != null &&
        _storage.getTenantId() != expectedTenantId) {
      return null;
    }

    // A fresh Dio() (unlike _dio) inherits no timeouts at all — without
    // setting them explicitly here, a stalled connection would leave this
    // await (and every queued request behind the shared _refreshFuture)
    // hanging forever instead of failing after 30s.
    final refreshDio = Dio(BaseOptions(
      baseUrl: _dio.options.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
    final response = await refreshDio.post('/auth/refresh', data: {
      'refreshToken': refreshToken,
    });

    if (expectedTenantId != null &&
        _storage.getTenantId() != expectedTenantId) {
      return null;
    }

    final newAccessToken = response.data['accessToken'] as String?;
    if (newAccessToken == null) return null;

    await _storage.saveAccessToken(newAccessToken);
    if (expectedTenantId != null &&
        _storage.getTenantId() != expectedTenantId) {
      return null;
    }
    _dio.options.headers['Authorization'] = 'Bearer $newAccessToken';

    final newRefreshToken = response.data['refreshToken'] as String?;
    if (newRefreshToken != null) {
      await _storage.saveRefreshToken(newRefreshToken);
    }

    return newAccessToken;
  }
}
