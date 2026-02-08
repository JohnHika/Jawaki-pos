import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../network/api_client.dart';
import 'connectivity_service.dart';
import 'background_sync_service.dart';

enum SyncEventType {
  saleCreated,
  saleVoided,
  refundCreated,
  stockAdjusted,
}

/// Sync action types for SyncQueue
enum SyncAction {
  create,
  update,
  delete,
}

class SyncService {
  final AppDatabase _database;
  final ApiClient _apiClient;
  final ConnectivityService _connectivity;
  
  final _uuid = const Uuid();
  Timer? _syncTimer;
  Timer? _heartbeatTimer;
  bool _isSyncing = false;
  
  final StreamController<SyncStatus> _statusController = 
      StreamController<SyncStatus>.broadcast();
  
  Stream<SyncStatus> get statusStream => _statusController.stream;
  
  SyncService({
    required AppDatabase database,
    required ApiClient apiClient,
    required ConnectivityService connectivity,
  }) : _database = database, 
       _apiClient = apiClient, 
       _connectivity = connectivity {
    _initializeSync();
  }
  
  void _initializeSync() {
    // Listen for connectivity changes
    _connectivity.statusStream.listen((status) {
      if (status == ConnectionStatus.online) {
        // Trigger sync when coming online
        syncPendingEvents();
      }
    });
    
    // Start periodic sync (every 30 seconds when online)
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connectivity.isOnline) {
        syncPendingEvents();
      }
    });
    
    // Start heartbeat (every 2 minutes when online)
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_connectivity.isOnline) {
        _sendHeartbeat();
      }
    });
  }
  
  /// Queue an event for sync (Legacy - backwards compatibility)
  @Deprecated('Use queueSyncItem instead')
  Future<void> queueEvent({
    required SyncEventType eventType,
    required Map<String, dynamic> payload,
    required String deviceId,
  }) async {
    final eventId = _uuid.v4();
    final sequenceNumber = await _database.getNextSequenceNumber();
    
    await _database.addSyncEvent(SyncQueueCompanion(
      id: Value(eventId),
      eventType: Value(eventType.name),
      payload: Value(jsonEncode(payload)),
      deviceId: Value(deviceId),
      entityTable: const Value(''),
      recordId: const Value(''),
      action: const Value('create'),
      sequenceNumber: Value(sequenceNumber),
      createdAt: Value(DateTime.now()),
    ));
    
    // Try to sync immediately if online
    if (_connectivity.isOnline) {
      syncPendingEvents();
    }
  }

  /// Queue a sync item to SyncQueue (New method)
  Future<void> queueSyncItem({
    required String tableName,
    required String recordId,
    required SyncAction action,
    required Map<String, dynamic> data,
    required String deviceId,
    required String userId,
  }) async {
    final itemId = _uuid.v4();
    final sequenceNumber = await _database.getNextSyncSequenceNumber();
    
    await _database.addToSyncQueue(SyncQueueCompanion(
      id: Value(itemId),
      entityTable: Value(tableName),
      recordId: Value(recordId),
      action: Value(action.name),
      eventType: Value('${tableName.toUpperCase()}_${action.name.toUpperCase()}'),
      payload: Value(jsonEncode(data)),
      deviceId: Value(deviceId),
      userId: Value(userId),
      sequenceNumber: Value(sequenceNumber),
      createdAt: Value(DateTime.now()),
      retryCount: const Value(0),
      maxRetries: const Value(3),
    ));
    
    // Try to sync immediately if online
    if (_connectivity.isOnline) {
      await BackgroundSyncService.triggerImmediateSync();
    }
  }

  /// Get sync queue statistics
  Future<Map<String, int>> getSyncStats() async {
    return await _database.getSyncQueueStats();
  }

  /// Retry all failed sync items
  Future<void> retryFailedItems() async {
    await BackgroundSyncService.retryFailedItems();
  }
  
  /// Sync pending events to server
  Future<void> syncPendingEvents() async {
    if (_isSyncing || !_connectivity.isOnline) return;
    
    _isSyncing = true;
    _statusController.add(SyncStatus.syncing);
    
    try {
      final pendingEvents = await _database.getPendingSyncEvents();
      
      if (pendingEvents.isEmpty) {
        _statusController.add(SyncStatus.synced);
        _isSyncing = false;
        return;
      }
      
      // Convert to API format
      final events = pendingEvents.map((e) => {
        'eventId': e.id,
        'eventType': e.eventType.toUpperCase(),
        'payload': jsonDecode(e.payload),
        'deviceId': e.deviceId,
        'createdAt': e.createdAt.toIso8601String(),
        'sequenceNumber': e.sequenceNumber,
      }).toList();
      
      final response = await _apiClient.pushSyncEvents({
        'events': events,
      });
      
      // Process results
      final results = response['results'] as List;
      for (final result in results) {
        final eventId = result['eventId'] as String;
        final success = result['success'] as bool;
        
        if (success) {
          await _database.markSyncEventProcessed(eventId);
        } else {
          await _database.markSyncEventFailed(
            eventId, 
            result['error'] ?? 'Unknown error',
          );
        }
      }
      
      // Update pending sales sync status
      await _syncPendingSales();
      
      _statusController.add(SyncStatus.synced);
    } catch (e) {
      _statusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }
  }
  
  /// Pull changes from server
  Future<void> pullChanges({String? since}) async {
    if (!_connectivity.isOnline) return;
    
    try {
      final response = await _apiClient.pullSyncEvents(since: since);
      final events = response['events'] as List;
      
      for (final event in events) {
        await _processServerEvent(event);
      }
    } catch (e) {
      // Log error but don't throw
    }
  }
  
  Future<void> _processServerEvent(Map<String, dynamic> event) async {
    final eventType = event['eventType'] as String;
    final payload = event['payload'] as Map<String, dynamic>;
    
    switch (eventType) {
      case 'PRODUCT_UPDATED':
        await _updateLocalProduct(payload);
        break;
      case 'CATEGORY_UPDATED':
        await _updateLocalCategory(payload);
        break;
      case 'PRICE_OVERRIDE_UPDATED':
        await _updateLocalPrice(payload);
        break;
      case 'STOCK_ADJUSTED':
        await _updateLocalStock(payload);
        break;
    }
  }
  
  Future<void> _updateLocalProduct(Map<String, dynamic> data) async {
    await _database.insertProducts([
      ProductsCompanion(
        id: Value(data['id']),
        sku: Value(data['sku']),
        name: Value(data['name']),
        description: Value(data['description']),
        categoryId: Value(data['categoryId']),
        price: Value((data['price'] as num).toDouble()),
        costPrice: Value(data['costPrice'] != null 
            ? (data['costPrice'] as num).toDouble() 
            : null),
        unit: Value(data['unit'] ?? 'piece'),
        imageUrl: Value(data['imageUrl']),
        isActive: Value(data['isActive'] ?? true),
        trackInventory: Value(data['trackInventory'] ?? true),
        createdAt: Value(DateTime.parse(data['createdAt'])),
        updatedAt: Value(DateTime.parse(data['updatedAt'])),
      ),
    ]);
  }
  
  Future<void> _updateLocalCategory(Map<String, dynamic> data) async {
    await _database.insertCategories([
      CategoriesCompanion(
        id: Value(data['id']),
        name: Value(data['name']),
        description: Value(data['description']),
        parentId: Value(data['parentId']),
        imageUrl: Value(data['imageUrl']),
        sortOrder: Value(data['sortOrder'] ?? 0),
        isActive: Value(data['isActive'] ?? true),
        createdAt: Value(DateTime.parse(data['createdAt'])),
        updatedAt: Value(DateTime.parse(data['updatedAt'])),
      ),
    ]);
  }
  
  Future<void> _updateLocalPrice(Map<String, dynamic> data) async {
    // Update branch price override
  }
  
  Future<void> _updateLocalStock(Map<String, dynamic> data) async {
    // Update local stock from server event
  }
  
  Future<void> _syncPendingSales() async {
    // Mark synced sales in the pending sales table
    final events = await _database.customSelect(
      '''
      SELECT DISTINCT payload FROM sync_queue 
      WHERE event_type = 'saleCreated' AND status = 'PROCESSED'
      ''',
    ).get();
    
    for (final event in events) {
      final payload = jsonDecode(event.read<String>('payload'));
      final offlineId = payload['offlineId'];
      if (offlineId != null) {
        await _database.markSaleAsSynced(offlineId);
      }
    }
  }
  
  Future<void> _sendHeartbeat() async {
    try {
      await _apiClient.sendHeartbeat();
    } catch (e) {
      // Ignore heartbeat errors
    }
  }
  
  /// Get sync statistics
  Future<SyncStats> getStats() async {
    final pending = await _database.getPendingSyncEvents();
    final unsyncedSales = await _database.getUnsyncedSales();
    
    return SyncStats(
      pendingEvents: pending.length,
      unsyncedSales: unsyncedSales.length,
      isOnline: _connectivity.isOnline,
    );
  }
  
  void dispose() {
    _syncTimer?.cancel();
    _heartbeatTimer?.cancel();
    _statusController.close();
  }
}

enum SyncStatus {
  idle,
  syncing,
  synced,
  error,
}

class SyncStats {
  final int pendingEvents;
  final int unsyncedSales;
  final bool isOnline;
  
  SyncStats({
    required this.pendingEvents,
    required this.unsyncedSales,
    required this.isOnline,
  });
  
  bool get hasPendingSync => pendingEvents > 0 || unsyncedSales > 0;
}
