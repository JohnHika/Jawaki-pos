import 'dart:convert';
import 'package:workmanager/workmanager.dart';
import 'package:drift/drift.dart' hide JsonKey;
import 'package:dio/dio.dart';

import '../database/app_database.dart';
import '../network/api_client.dart';
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
    defaultValue: 'http://10.30.168.100:3000/api/v1',
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
    final database = AppDatabase();
    final connectivityService = ConnectivityService();

    try {
      final connectionStatus = await connectivityService.checkCurrentStatus();
      if (connectionStatus != ConnectionStatus.online) {
        print('[BackgroundSync] Device is offline, skipping sync');
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
      final apiClient = ApiClient(dio);

      final result = await processPendingQueue(
        database: database,
        apiClient: apiClient,
      );

      print(
        '[BackgroundSync] Completed: ${result.successCount} synced, '
        '${result.failureCount} failed, ${result.conflictCount} conflicts',
      );

      final cleaned = await database.cleanupSyncQueue(olderThanDays: 30);
      if (cleaned > 0) {
        print('[BackgroundSync] Cleaned up $cleaned old sync items');
      }

      return !result.hasErrors;
    } catch (e) {
      print('[BackgroundSync] Fatal error: $e');
      return false;
    } finally {
      connectivityService.dispose();
      await database.close();
    }
  }

  static Future<SyncQueueProcessResult> processPendingQueue({
    required AppDatabase database,
    required ApiClient apiClient,
  }) async {
    final pendingItems = await database.getPendingSyncQueue();

    if (pendingItems.isEmpty) {
      return const SyncQueueProcessResult(
        processedCount: 0,
        successCount: 0,
        failureCount: 0,
        conflictCount: 0,
      );
    }

    print('[BackgroundSync] Processing ${pendingItems.length} pending items');

    var successCount = 0;
    var failureCount = 0;
    var conflictCount = 0;

    for (final item in pendingItems) {
      try {
        final response = await apiClient.pushSyncEvents({
          'events': [_buildSyncEventPayload(item)],
        });

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
          final serverId =
              firstResult['serverId']?.toString() ??
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
          await _markRelatedLocalDataAsSynced(database, item);
          successCount++;
          print('[BackgroundSync] ✓ Synced: ${item.entityTable}/${item.action}');
        } else {
          final errorMessage =
              firstResult['error']?.toString() ?? 'Unknown server error';

          if (_isConflictError(errorMessage)) {
            await database.markSyncQueueConflict(item.id, errorMessage);
            conflictCount++;
          } else if (_isRetryableServerError(errorMessage)) {
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

          print(
            '[BackgroundSync] ✗ Failed: ${item.entityTable}/${item.action} - $errorMessage',
          );
        }
      } on DioException catch (e) {
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

        print(
          '[BackgroundSync] ✗ Failed: ${item.entityTable}/${item.action} - $errorMessage',
        );
      } catch (e) {
        final errorMessage = 'Error: $e';
        await database.markSyncQueueFailed(item.id, errorMessage);
        failureCount++;

        print(
          '[BackgroundSync] ✗ Exception: ${item.entityTable}/${item.action} - $errorMessage',
        );
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    return SyncQueueProcessResult(
      processedCount: pendingItems.length,
      successCount: successCount,
      failureCount: failureCount,
      conflictCount: conflictCount,
    );
  }

  static Map<String, dynamic> _buildSyncEventPayload(SyncQueueData item) {
    return {
      'eventId': item.id,
      'eventType': item.eventType,
      'payload': jsonDecode(item.payload),
      'deviceId': item.deviceId,
      'createdAt': item.createdAt.toIso8601String(),
      'sequenceNumber': item.sequenceNumber,
    };
  }

  static Future<void> _markRelatedLocalDataAsSynced(
    AppDatabase database,
    SyncQueueData item,
  ) async {
    if (item.eventType != 'SALE_CREATED') {
      return;
    }

    final payload = Map<String, dynamic>.from(
      jsonDecode(item.payload) as Map<String, dynamic>,
    );
    final offlineId = payload['offlineId']?.toString() ?? item.recordId;

    if (offlineId.isNotEmpty) {
      await database.markSaleAsSynced(offlineId);
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
    final database = AppDatabase();

    try {
      return await database.getSyncQueueStats();
    } finally {
      await database.close();
    }
  }

  /// Retry all failed items
  static Future<void> retryFailedItems() async {
    final database = AppDatabase();

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
      print('[BackgroundSync] Task started: $task');

      switch (task) {
        case BackgroundSyncService.syncTaskName:
        case 'sync-immediate':
          final success = await BackgroundSyncService.processSyncQueue();
          print('[BackgroundSync] Task completed: ${success ? 'SUCCESS' : 'PARTIAL'}');
          return success;

        default:
          print('[BackgroundSync] Unknown task: $task');
          return false;
      }
    } catch (e) {
      print('[BackgroundSync] Task failed: $e');
      return Future.value(false);
    }
  });
}
