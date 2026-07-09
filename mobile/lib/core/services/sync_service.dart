import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../network/api_client.dart';
import 'connectivity_service.dart';
import 'background_sync_service.dart';
import 'storage_service.dart';

enum SyncEventType {
  saleCreated,
  saleVoided,
  refundCreated,
  stockAdjusted,
  supplierInvoiceCreated,
  supplierPaymentRecorded,
}

/// Sync action types for SyncQueue
enum SyncAction {
  create,
  update,
  delete,
}

enum SyncConflictResolution {
  serverWins,
  clientWins,
  merge,
}

extension SyncEventTypeWireFormat on SyncEventType {
  String get wireName {
    switch (this) {
      case SyncEventType.saleCreated:
        return 'SALE_CREATED';
      case SyncEventType.saleVoided:
        return 'SALE_VOIDED';
      case SyncEventType.refundCreated:
        return 'REFUND_CREATED';
      case SyncEventType.stockAdjusted:
        return 'STOCK_ADJUSTED';
      case SyncEventType.supplierInvoiceCreated:
        return 'SUPPLIER_INVOICE_CREATED';
      case SyncEventType.supplierPaymentRecorded:
        return 'SUPPLIER_PAYMENT_RECORDED';
    }
  }
}

extension SyncConflictResolutionWireFormat on SyncConflictResolution {
  String get wireName {
    switch (this) {
      case SyncConflictResolution.serverWins:
        return 'SERVER_WINS';
      case SyncConflictResolution.clientWins:
        return 'CLIENT_WINS';
      case SyncConflictResolution.merge:
        return 'MERGE';
    }
  }
}

String _tableNameForEventType(SyncEventType eventType) {
  switch (eventType) {
    case SyncEventType.saleCreated:
    case SyncEventType.saleVoided:
    case SyncEventType.refundCreated:
      return 'sales';
    case SyncEventType.stockAdjusted:
      return 'inventory';
    case SyncEventType.supplierInvoiceCreated:
    case SyncEventType.supplierPaymentRecorded:
      return 'suppliers';
  }
}

SyncAction _actionForEventType(SyncEventType eventType) {
  switch (eventType) {
    case SyncEventType.saleCreated:
    case SyncEventType.refundCreated:
    case SyncEventType.supplierInvoiceCreated:
    case SyncEventType.supplierPaymentRecorded:
      return SyncAction.create;
    case SyncEventType.saleVoided:
    case SyncEventType.stockAdjusted:
      return SyncAction.update;
  }
}

String _recordIdForEvent(
  SyncEventType eventType,
  Map<String, dynamic> payload,
  String fallbackRecordId,
) {
  switch (eventType) {
    case SyncEventType.saleCreated:
      return payload['offlineId']?.toString() ?? fallbackRecordId;
    case SyncEventType.saleVoided:
    case SyncEventType.refundCreated:
      return payload['saleId']?.toString() ?? payload['id']?.toString() ?? fallbackRecordId;
    case SyncEventType.stockAdjusted:
      return payload['productId']?.toString() ?? payload['id']?.toString() ?? fallbackRecordId;
    case SyncEventType.supplierInvoiceCreated:
      return payload['offlineId']?.toString() ?? fallbackRecordId;
    case SyncEventType.supplierPaymentRecorded:
      return payload['invoiceId']?.toString() ?? fallbackRecordId;
  }
}

class SyncService {
  final AppDatabase _database;
  final ApiClient _apiClient;
  final ConnectivityService _connectivity;
  final StorageService _storage;

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
    required StorageService storage,
  }) : _database = database,
       _apiClient = apiClient,
       _connectivity = connectivity,
       _storage = storage {
    _initializeSync();
  }

  void _initializeSync() {
    // Listen for connectivity changes
    _connectivity.statusStream.listen((status) {
      if (status == ConnectionStatus.online) {
        // Trigger sync when coming online
        syncPendingEvents();
        migrateLocalSupplierDataIfNeeded();
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
    final fallbackRecordId =
        payload['offlineId']?.toString() ??
        payload['saleId']?.toString() ??
        payload['id']?.toString() ??
        _uuid.v4();

    await queueSyncItem(
      tableName: _tableNameForEventType(eventType),
      recordId: _recordIdForEvent(eventType, payload, fallbackRecordId),
      action: _actionForEventType(eventType),
      eventType: eventType,
      data: payload,
      deviceId: deviceId,
      userId: payload['cashierId']?.toString() ?? payload['userId']?.toString() ?? '',
    );
  }

  /// Queue a sync item to SyncQueue (New method)
  Future<void> queueSyncItem({
    required String tableName,
    required String recordId,
    required SyncAction action,
    required SyncEventType eventType,
    required Map<String, dynamic> data,
    required String deviceId,
    required String userId,
    int maxRetries = 5,
  }) async {
    final itemId = _uuid.v4();
    final sequenceNumber = await _database.getNextSyncSequenceNumber();
    
    await _database.addToSyncQueue(SyncQueueCompanion(
      id: Value(itemId),
      entityTable: Value(tableName),
      recordId: Value(recordId),
      action: Value(action.name),
      eventType: Value(eventType.wireName),
      payload: Value(jsonEncode(data)),
      deviceId: Value(deviceId),
      userId: Value(userId),
      sequenceNumber: Value(sequenceNumber),
      createdAt: Value(DateTime.now()),
      retryCount: const Value(0),
      maxRetries: Value(maxRetries),
    ));
    
    // Try to sync immediately if online
    if (_connectivity.isOnline) {
      await syncPendingEvents();
    }
  }

  /// Get sync queue statistics
  Future<Map<String, int>> getSyncStats() async {
    return await _database.getSyncQueueStats();
  }

  Future<List<SyncQueueData>> getConflictItems() {
    return _database.getConflictSyncQueue();
  }

  /// Retry all failed sync items
  Future<void> retryFailedItems() async {
    final failedItems = await _database.getFailedSyncQueue();
    for (final item in failedItems) {
      await _database.resetSyncQueueItem(item.id);
    }

    if (_connectivity.isOnline ||
        await _connectivity.checkCurrentStatus() == ConnectionStatus.online) {
      await syncPendingEvents();
    }
  }

  Future<void> resolveConflictItem({
    required String itemId,
    required SyncConflictResolution resolution,
    Map<String, dynamic>? mergedPayload,
  }) async {
    final results = await _apiClient.resolveSyncConflicts([
      {
        'eventId': itemId,
        'resolution': resolution.wireName,
        if (mergedPayload != null) 'mergedPayload': mergedPayload,
      },
    ]);

    final firstResult = results.isNotEmpty
        ? Map<String, dynamic>.from(results.first as Map)
        : null;

    if (firstResult == null || firstResult['success'] != true) {
      throw Exception(
        firstResult?['error']?.toString() ?? 'Failed to resolve sync conflict',
      );
    }

    if (resolution == SyncConflictResolution.serverWins) {
      await _database.markSyncQueueResolved(
        itemId,
        resolution: resolution.wireName,
      );
      await _markLocalSyncItemResolved(itemId);
      return;
    }

    await _database.resetSyncQueueItem(itemId);

    if (_connectivity.isOnline ||
        await _connectivity.checkCurrentStatus() == ConnectionStatus.online) {
      await syncPendingEvents();
    }
  }
  
  /// Sync pending events to server
  Future<void> syncPendingEvents() async {
    if (_isSyncing) return;

    final connectionStatus = _connectivity.isOnline
        ? ConnectionStatus.online
        : await _connectivity.checkCurrentStatus();

    if (connectionStatus != ConnectionStatus.online) {
      return;
    }
    
    _isSyncing = true;
    _statusController.add(SyncStatus.syncing);
    
    try {
      final result = await BackgroundSyncService.processPendingQueue(
        database: _database,
        apiClient: _apiClient,
      );

      if (result.hasErrors) {
        _statusController.add(SyncStatus.error);
      } else {
        _statusController.add(SyncStatus.synced);
      }
    } catch (e) {
      _statusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }
  }

  /// One-time push of this device's pre-existing local supplier
  /// invoices/payments (recorded by the old device-local Finance screen)
  /// to the backend, so switching that screen to read/write through the
  /// API doesn't silently orphan debt records already on the phone.
  /// Safe to call repeatedly — it no-ops once the flag is set, and each
  /// invoice carries its original local id as offlineId so a retry after
  /// a partial failure won't create duplicates server-side.
  Future<void> migrateLocalSupplierDataIfNeeded() async {
    if (_storage.isSupplierDataMigrated()) return;
    if (!_connectivity.isOnline) return;

    final branchId = _storage.getBranchId();
    if (branchId == null || branchId.isEmpty) return;

    try {
      final localData = await _database.getAllLocalSupplierData();

      for (final supplier in localData) {
        // Each supplier migrates independently — one supplier's data quirk
        // (e.g. a payment total that doesn't reconcile cleanly) shouldn't
        // block every other supplier's records from migrating.
        try {
          await _migrateOneLocalSupplier(supplier, branchId);
        } catch (_) {
          continue;
        }
      }

      await _storage.setSupplierDataMigrated(true);
    } catch (e) {
      // Leave the flag unset so the next time the device comes online it
      // retries — a partial migration is safer than silently giving up.
    }
  }

  Future<void> _migrateOneLocalSupplier(
    Map<String, dynamic> supplier,
    String branchId,
  ) async {
    final invoices = supplier['invoices'] as List<dynamic>;
    String? firstMigratedInvoiceId;
    double firstInvoiceDue = 0;
    double paidAmountAlreadyCounted = 0;

    for (final invoice in invoices) {
      final items = (invoice['items'] as List<dynamic>)
          .map((item) => {
                'productName': item['productName'],
                'quantity': item['quantity'],
                'unit': item['unit'],
                'unitCost': item['unitCost'],
              })
          .toList();

      if (items.isEmpty) continue;

      final paidAmount = (invoice['paidAmount'] as num?)?.toDouble() ?? 0;
      final created = await _apiClient.createSupplierInvoice({
        'branchId': branchId,
        'supplierName': supplier['supplierName'],
        'supplierPhone': supplier['supplierPhone'],
        'invoiceNumber': invoice['invoiceNumber'],
        'items': items,
        'paidAmount': paidAmount,
        'dueDate': invoice['dueDate'],
        'offlineId': 'legacy-${invoice['id']}',
      });

      if (firstMigratedInvoiceId == null) {
        firstMigratedInvoiceId = created['id']?.toString();
        firstInvoiceDue = (created['dueAmount'] as num?)?.toDouble() ?? 0;
      }
      paidAmountAlreadyCounted += paidAmount;
    }

    // Locally, recordSupplierInvoice() already writes a supplier_payments
    // row for any paidAmount given at invoice creation time, so
    // supplier_payments totals include that — only the amount beyond what's
    // already been passed as paidAmount above is a genuinely separate later
    // payment. Local rows also don't record which invoice they were
    // against, so any excess is applied as one lump-sum payment against the
    // first migrated invoice, clamped to what that invoice can actually
    // absorb — this keeps the total amount owed roughly correct even if not
    // broken down exactly as it was originally.
    final payments = supplier['payments'] as List<dynamic>;
    final totalPaid = payments.fold<double>(
      0,
      (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0),
    );
    final excessPayment = totalPaid - paidAmountAlreadyCounted;
    if (excessPayment > 0 && firstMigratedInvoiceId != null) {
      final amountToApply = excessPayment > firstInvoiceDue ? firstInvoiceDue : excessPayment;
      if (amountToApply > 0) {
        await _apiClient.recordSupplierPayment(firstMigratedInvoiceId, {
          'amount': amountToApply,
          'notes': 'Migrated from device-local payment history',
        });
      }
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
  
  /// Parse timestamp from various formats (ISO string or milliseconds since epoch)
  DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    
    // If it's already a DateTime, return it
    if (value is DateTime) return value;
    
    // If it's a number (Unix timestamp in milliseconds)
    if (value is int || value is double) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    
    // If it's a string
    if (value is String) {
      // Try to parse as ISO string first
      try {
        return DateTime.parse(value);
      } catch (_) {
        // If that fails, try parsing as milliseconds since epoch
        try {
          final milliseconds = int.tryParse(value);
          if (milliseconds != null) {
            return DateTime.fromMillisecondsSinceEpoch(milliseconds);
          }
          return DateTime.now();
        } catch (_) {
          return DateTime.now();
        }
      }
    }
    
    return DateTime.now();
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
    final createdAt = _parseTimestamp(data['createdAt']);
    final updatedAt = _parseTimestamp(data['updatedAt']);
    
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
        minStock: Value((data['minStock'] as num?)?.toInt() ?? 0),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
      ),
    ]);
  }
  
  Future<void> _updateLocalCategory(Map<String, dynamic> data) async {
    final createdAt = _parseTimestamp(data['createdAt']);
    final updatedAt = _parseTimestamp(data['updatedAt']);
    
    await _database.insertCategories([
      CategoriesCompanion(
        id: Value(data['id']),
        name: Value(data['name']),
        description: Value(data['description']),
        parentId: Value(data['parentId']),
        imageUrl: Value(data['imageUrl']),
        sortOrder: Value(data['sortOrder'] ?? 0),
        isActive: Value(data['isActive'] ?? true),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
      ),
    ]);
  }
  
  Future<void> _updateLocalPrice(Map<String, dynamic> data) async {
    // Update branch price override
  }
  
  /// Applies a STOCK_ADJUSTED pull event to the on-device stock cache.
  /// The payload is a backend StockMovement row; `newQty` is the absolute
  /// quantity after the movement, so applying events in their pulled
  /// (createdAt-ascending) order converges the local value to the server's
  /// latest — no need to replay deltas. This was previously an empty stub,
  /// which meant server-side stock changes (receiving batches on another
  /// device, admin corrections, bulk initializations) never reached this
  /// device's POS/inventory screens at all.
  Future<void> _updateLocalStock(Map<String, dynamic> data) async {
    final productId = data['productId'] as String?;
    final branchId = data['branchId'] as String?;
    final rawNewQty = data['newQty'];
    if (productId == null || branchId == null || rawNewQty == null) return;

    // Prisma Decimal fields serialize as strings over JSON; plain ints
    // arrive as numbers. Accept both.
    final newQty =
        rawNewQty is num ? rawNewQty : num.tryParse(rawNewQty.toString());
    if (newQty == null) return;

    final now = DateTime.now();
    final existing = await _database.getProductStock(productId, branchId);
    if (existing != null) {
      await (_database.update(_database.localStock)..where(
            (s) => s.productId.equals(productId) & s.branchId.equals(branchId),
          ))
          .write(
            LocalStockCompanion(
              quantity: Value(newQty.round()),
              updatedAt: Value(now),
            ),
          );
    } else {
      await _database.into(_database.localStock).insert(
            LocalStockCompanion.insert(
              id: 'stock-$branchId-$productId',
              productId: productId,
              branchId: branchId,
              quantity: newQty.round(),
              updatedAt: now,
            ),
          );
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
    final queueStats = await _database.getSyncQueueStats();
    final unsyncedSales = await _database.getUnsyncedSales();
    
    return SyncStats(
      pendingEvents:
          (queueStats['pending'] ?? 0) +
          (queueStats['failed'] ?? 0) +
          (queueStats['conflict'] ?? 0),
      unsyncedSales: unsyncedSales.length,
      failedEvents: queueStats['failed'] ?? 0,
      conflictEvents: queueStats['conflict'] ?? 0,
      isOnline: _connectivity.isOnline,
    );
  }

  Future<void> _markLocalSyncItemResolved(String itemId) async {
    final item = await _database.getSyncQueueItem(itemId);
    if (item == null || item.eventType != SyncEventType.saleCreated.wireName) {
      return;
    }

    final payload = Map<String, dynamic>.from(
      jsonDecode(item.payload) as Map<String, dynamic>,
    );
    final offlineId = payload['offlineId']?.toString() ?? item.recordId;

    if (offlineId.isNotEmpty) {
      await _database.markSaleAsSynced(offlineId);
    }
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
  final int failedEvents;
  final int conflictEvents;
  final bool isOnline;
  
  SyncStats({
    required this.pendingEvents,
    required this.unsyncedSales,
    this.failedEvents = 0,
    this.conflictEvents = 0,
    required this.isOnline,
  });
  
  bool get hasPendingSync =>
      pendingEvents > 0 ||
      unsyncedSales > 0 ||
      failedEvents > 0 ||
      conflictEvents > 0;
}
