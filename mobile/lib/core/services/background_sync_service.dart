import 'dart:convert';
import 'package:workmanager/workmanager.dart';
import 'package:drift/drift.dart' hide JsonKey;
import 'package:dio/dio.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import 'connectivity_service.dart';

/// Background Sync Service using Workmanager
/// Runs every 15 minutes to sync pending changes to the server
class BackgroundSyncService {
  static const String syncTaskName = 'sync-queue-processor';
  static const String syncTaskTag = 'background-sync';
  
  // Run every 15 minutes
  static const Duration syncInterval = Duration(minutes: 15);
  
  // Exponential backoff delays (in seconds)
  static const List<int> retryDelays = [5, 15, 60]; // 5s, 15s, 1min
  
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
        networkType: NetworkType.connected, // Only run when online
        requiresBatteryNotLow: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: Duration(seconds: retryDelays[0]),
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
      tag: 'immediate-sync',
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
  
  /// Cancel all sync tasks
  static Future<void> cancelAllSyncTasks() async {
    await Workmanager().cancelByTag(syncTaskTag);
  }
  
  /// Process the sync queue (called by workmanager callback)
  static Future<bool> processSyncQueue() async {
    try {
      // Initialize database
      final database = AppDatabase();
      
      // Check connectivity
      final connectivityService = ConnectivityService();
      final isOnline = connectivityService.isOnline;
      
      if (!isOnline) {
        print('[BackgroundSync] Device is offline, skipping sync');
        await database.close();
        return false;
      }
      
      // Get pending items
      final pendingItems = await database.getPendingSyncQueue();
      
      if (pendingItems.isEmpty) {
        print('[BackgroundSync] No pending items to sync');
        await database.close();
        return true;
      }
      
      print('[BackgroundSync] Processing ${pendingItems.length} pending items');
      
      // Initialize API client
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000/api'));
      final apiClient = ApiClient(dio);
      
      int successCount = 0;
      int failureCount = 0;
      
      // Process each item
      // Add exponential backoff for failed items
      int retryCount = 0;
      for (final item in pendingItems) {
        try {
          // Prepare payload
          final payload = {
            'id': item.id,
            'tableName': item.entityTable,
            'recordId': item.recordId,
            'action': item.action,
            'eventType': item.eventType,
            'payload': jsonDecode(item.payload),
            'timestamp': item.createdAt.toIso8601String(),
            'deviceId': item.deviceId,
          };

          // Send to server
          try {
            final response = await apiClient.pushSyncEvents({
              'events': [payload],
            });

            final results = response['results'] as List?;
            if (results != null && results.isNotEmpty) {
              final result = results.first;
              final serverId = result['serverId'] ?? result['eventId'] ?? item.id;
              final serverTimestamp = DateTime.tryParse(
                result['serverTimestamp']?.toString() ?? ''
              ) ?? DateTime.now();

              if (result['success'] == true) {
                await database.markSyncQueueSynced(
                  item.id,
                  serverId.toString(),
                  serverTimestamp,
                );
                successCount++;
                print('[BackgroundSync] ✓ Synced: ${item.entityTable}/${item.action}');
              } else {
                final errorMessage = result['error'] ?? 'Unknown server error';
                await database.markSyncQueueFailed(item.id, errorMessage);
                failureCount++;
                print('[BackgroundSync] ✗ Failed: ${item.entityTable}/${item.action} - $errorMessage');
              }
            }
          } on DioException catch (e) {
            final errorMessage = 'Network error: ${e.message}';
            await database.markSyncQueueFailed(item.id, errorMessage);
            failureCount++;
            print('[BackgroundSync] ✗ Failed: ${item.entityTable}/${item.action} - $errorMessage');
          }
        } catch (e) {
          // Network or processing error - mark as failed
          final errorMessage = 'Error: ${e.toString()}';
          await database.markSyncQueueFailed(item.id, errorMessage);

          failureCount++;
          print('[BackgroundSync] ✗ Exception: ${item.entityTable}/${item.action} - $errorMessage');
        }

        // Small delay between requests to avoid overwhelming server
        await Future.delayed(const Duration(milliseconds: 100));
      }
      for (final item in pendingItems) {
        try {
          // Prepare payload
          final payload = {
            'id': item.id,
            'tableName': item.entityTable,
            'recordId': item.recordId,
            'action': item.action,
            'eventType': item.eventType,
            'payload': jsonDecode(item.payload),
            'timestamp': item.createdAt.toIso8601String(),
            'deviceId': item.deviceId,
          };
          
          // Send to server
          try {
            final response = await apiClient.pushSyncEvents({
              'events': [payload],
            });
            
            final results = response['results'] as List?;
            if (results != null && results.isNotEmpty) {
              final result = results.first;
              final serverId = result['serverId'] ?? result['eventId'] ?? item.id;
              final serverTimestamp = DateTime.tryParse(
                result['serverTimestamp']?.toString() ?? ''
              ) ?? DateTime.now();
              
              if (result['success'] == true) {
                await database.markSyncQueueSynced(
                  item.id,
                  serverId.toString(),
                  serverTimestamp,
                );
                successCount++;
                print('[BackgroundSync] ✓ Synced: ${item.entityTable}/${item.action}');
              } else {
                final errorMessage = result['error'] ?? 'Unknown server error';
                await database.markSyncQueueFailed(item.id, errorMessage);
                failureCount++;
                print('[BackgroundSync] ✗ Failed: ${item.entityTable}/${item.action} - $errorMessage');
              }
            }
          } on DioException catch (e) {
            final errorMessage = 'Network error: ${e.message}';
            await database.markSyncQueueFailed(item.id, errorMessage);
            failureCount++;
            print('[BackgroundSync] ✗ Failed: ${item.entityTable}/${item.action} - $errorMessage');
          }
        } catch (e) {
          // Network or processing error - mark as failed
          final errorMessage = 'Error: ${e.toString()}';
          await database.markSyncQueueFailed(item.id, errorMessage);
          
          failureCount++;
          print('[BackgroundSync] ✗ Exception: ${item.entityTable}/${item.action} - $errorMessage');
        }
        
        // Small delay between requests to avoid overwhelming server
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      print('[BackgroundSync] Completed: $successCount synced, $failureCount failed');
      
      // Cleanup old synced items (older than 30 days)
      final cleaned = await database.cleanupSyncQueue(olderThanDays: 30);
      if (cleaned > 0) {
        print('[BackgroundSync] Cleaned up $cleaned old synced items');
      }
      
      await database.close();
      
      return failureCount == 0;
    } catch (e) {
      print('[BackgroundSync] Fatal error: $e');
      return false;
    }
  }
  
  /// Get sync queue statistics
  static Future<Map<String, int>> getSyncStats() async {
    final database = AppDatabase();
    final stats = await database.getSyncQueueStats();
    await database.close();
    return stats;
  }
  
  /// Retry all failed items
  static Future<void> retryFailedItems() async {
    final database = AppDatabase();
    final failedItems = await database.getFailedSyncQueue();
    
    for (final item in failedItems) {
      await database.resetSyncQueueItem(item.id);
    }
    
    await database.close();
    
    // Trigger immediate sync
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
