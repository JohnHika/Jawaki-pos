import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;
import '../../../database/app_database.dart';
import '../middleware.dart';
import '../sql_helper.dart';

/// Sync routes for phone server mode.
///
/// Client phones push their offline events here, and pull changes.
class SyncRoutes {
  final AppDatabase _db;

  SyncRoutes(this._db);

  void addRoutes(Router r) {
    r.post('/api/v1/sync/push', _handlePush);
    r.post('/api/v1/sync/pull', _handlePull);
    r.post('/api/v1/sync/heartbeat', _handleHeartbeat);
    r.post('/api/v1/sync/conflicts/resolve', _handleConflicts);
    r.get('/api/v1/sync/failed', _handleGetFailed);
    r.post('/api/v1/sync/retry', _handleRetry);
  }

  /// POST /api/v1/sync/push — receive events from client phones
  Future<shelf.Response> _handlePush(shelf.Request request) async {
    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');

    final events =
        (body['events'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final results = <Map<String, dynamic>>[];
    await _ensureProcessedEventsTable();

    for (final event in events) {
      final suppliedEventId = event['eventId']?.toString().trim();
      final eventId = suppliedEventId == null || suppliedEventId.isEmpty
          ? _uuid()
          : suppliedEventId;
      try {
        final deviceId = event['deviceId'] as String? ?? '';
        final eventType = event['eventType'] as String? ?? '';
        final payload = event['payload'] as Map<String, dynamic>? ?? {};

        // Apply each event and record its id atomically. A crash between a
        // stock/sale update and the dedupe insert must never replay the
        // side effect when the client retries this event.
        final isDuplicate = await _db.transaction(() async {
          final alreadyProcessed = await _db
              .customSelect(
                'SELECT event_id FROM server_processed_events WHERE event_id = ${Sql.str(eventId)}',
              )
              .get();
          if (alreadyProcessed.isNotEmpty) return true;

          switch (eventType) {
            case 'SALE_CREATED':
              await _processSaleCreated(payload);
              break;
            case 'SALE_VOIDED':
              await _processSaleVoided(payload);
              break;
            case 'STOCK_ADJUSTED':
              await _processStockAdjusted(payload);
              break;
            case 'CUSTOMER_CREATED':
            case 'CUSTOMER_UPDATED':
              await _processCustomer(payload);
              break;
            case 'SUPPLIER_INVOICE_CREATED':
              await _processSupplierInvoice(payload, eventId);
              break;
            default:
              throw UnsupportedError('Unsupported sync event: $eventType');
          }
          await _db.customStatement(
            'INSERT INTO server_processed_events (event_id, processed_at) '
            'VALUES (${Sql.vals([eventId, DateTime.now().toIso8601String()])})',
          );
          return false;
        });

        results.add({
          'success': true,
          'eventId': eventId,
          'deviceId': deviceId,
          'serverId': 'srv-$eventId',
          'serverTimestamp': DateTime.now().toIso8601String(),
          'duplicate': isDuplicate,
        });
      } catch (e, stack) {
        debugPrint('[PhoneServer Sync] Failed event $eventId: $e');
        debugPrint(stack.toString());
        final unsupportedEvent = e is UnsupportedError;
        results.add({
          'success': false,
          'eventId': eventId,
          'error': unsupportedEvent
              ? 'This update is not supported by the shop phone. Update it, then retry Sync.'
              : 'This update could not be saved. We’ll retry shortly; check Sync status if the problem continues.',
          'retryable': !unsupportedEvent,
        });
      }
    }

    return shelf.Response.ok(
      jsonEncode({'results': results}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST /api/v1/sync/pull — return recent changes since timestamp
  Future<shelf.Response> _handlePull(shelf.Request request) async {
    final body = getRequestBody(request);
    final rawSince = body?['since'];
    if (rawSince != null && rawSince is! String) {
      return _error(400, 'Sync timestamp must be a valid date');
    }
    final since = rawSince as String?;
    final sinceDate = since != null
        ? DateTime.tryParse(since)
        : DateTime.now().subtract(const Duration(days: 7));
    if (sinceDate == null)
      return _error(400, 'Sync timestamp must be a valid date');

    // Return a list of events that happened since the given timestamp
    // For now, we return product/category updates from the sync_queue
    final events = <Map<String, dynamic>>[];

    try {
      final result = await _db
          .customSelect(
            'SELECT * FROM sync_queue WHERE created_at > ${Sql.str(sinceDate.toIso8601String())} AND status = \'synced\' ORDER BY created_at ASC LIMIT 100',
          )
          .get();

      for (final row in result) {
        events.add({
          'id': row.read<String>('id'),
          'eventType': row.read<String>('event_type'),
          'entityTable': row.read<String>('entity_table'),
          'recordId': row.read<String>('record_id'),
          'action': row.read<String>('action'),
          'payload': row.read<String>('payload'),
          'createdAt': row.read<String>('created_at'),
        });
      }
    } catch (_) {
      return _error(500, 'Could not load sync updates');
    }

    return shelf.Response.ok(
      jsonEncode({'events': events}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST /api/v1/sync/heartbeat — client phone pings to say "I'm alive"
  Future<shelf.Response> _handleHeartbeat(shelf.Request request) async {
    return shelf.Response.ok(
      jsonEncode(
          {'message': 'alive', 'serverTime': DateTime.now().toIso8601String()}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST /api/v1/sync/conflicts/resolve
  ///
  /// Phone-server mode has no authoritative conflict resolution — the
  /// "server" is just another phone. Return 501 instead of a fake
  /// success so clients keep their conflict state instead of silently
  /// dropping it.
  Future<shelf.Response> _handleConflicts(shelf.Request request) async {
    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');

    final conflicts =
        (body['conflicts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
            [];

    return _error(
      501,
      'conflict resolution not supported in phone-server mode '
      '(${conflicts.length} conflict(s) rejected)',
    );
  }

  /// GET /api/v1/sync/failed
  Future<shelf.Response> _handleGetFailed(shelf.Request request) async {
    try {
      final failed = await _db.getFailedSyncQueue();
      return shelf.Response.ok(
        jsonEncode(failed
            .map((f) => {
                  'id': f.id,
                  'eventType': f.eventType,
                  'errorMessage': f.errorMessage,
                  'retryCount': f.retryCount,
                })
            .toList()),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(500, 'Could not load failed sync items');
    }
  }

  /// POST /api/v1/sync/retry
  Future<shelf.Response> _handleRetry(shelf.Request request) async {
    try {
      final failed = await _db.transaction(() async {
        final items = await _db.getFailedSyncQueue();
        for (final item in items) {
          await _db.resetSyncQueueItem(item.id);
        }
        return items;
      });
      return shelf.Response.ok(
        jsonEncode({'message': 'Retry initiated', 'count': failed.length}),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(500, 'Could not restart failed sync items');
    }
  }

  // ─── Event processors ───

  Future<void> _processSaleCreated(Map<String, dynamic> payload) async {
    // The pushing client usually already stored the sale locally, but a
    // client can push a sale this server phone never received (e.g. its
    // own queue drained the event while the sale row write never landed,
    // or the sale was created on the client after its last pull). Insert
    // it from the payload if missing so success:true never means a
    // silently lost sale.
    final saleId = payload['offlineId']?.toString() ??
        payload['id']?.toString() ??
        payload['saleId']?.toString();
    if (saleId == null || saleId.trim().isEmpty) {
      throw const FormatException('Sale sync event is missing its id');
    }

    final existing = await _db.getPendingSaleById(saleId);
    if (existing != null) {
      await _db.markSaleAsSynced(saleId);
      return;
    }

    final createdAt = _parseTimestamp(payload['createdAt']) ?? DateTime.now();
    final items = payload['items'] as List<dynamic>? ?? [];
    final saleItems = items.whereType<Map>().toList();
    final branchId = payload['branchId']?.toString().trim() ?? '';
    if (branchId.isEmpty ||
        saleItems.isEmpty ||
        saleItems.length != items.length) {
      throw const FormatException(
          'Sale sync event is missing its branch or valid items');
    }

    await _db.into(_db.pendingSales).insert(
          PendingSalesCompanion(
            id: Value(saleId),
            receiptNumber: Value(payload['receiptNumber']?.toString() ?? ''),
            subtotal: Value(_parseNumber(payload['subtotal']) ?? 0),
            discount: Value(_parseNumber(payload['discountAmount']) ?? 0),
            tax: Value(_parseNumber(payload['taxAmount']) ?? 0),
            total: Value(
                _parseNumber(payload['totalAmount'] ?? payload['paidAmount']) ??
                    0),
            paymentMethod:
                Value(payload['paymentMethod']?.toString() ?? 'CASH'),
            paymentReference: Value(payload['paymentReference']?.toString()),
            customerId: Value(payload['customerId']?.toString()),
            cashierId: Value(payload['cashierId']?.toString() ??
                payload['userId']?.toString() ??
                ''),
            branchId: Value(branchId),
            notes: Value(payload['notes']?.toString()),
            status: Value(payload['status']?.toString() ?? 'COMPLETED'),
            createdAt: Value(createdAt),
            isSynced: const Value(true),
            syncedAt: Value(createdAt),
          ),
        );

    for (final item in saleItems) {
      final productId = item['productId']?.toString().trim() ?? '';
      final quantity = _parseNumber(item['quantity']) ?? 0;
      if (productId.isEmpty || quantity <= 0) {
        throw const FormatException(
            'Sale sync item is missing its product or quantity');
      }
      await _db.into(_db.pendingSaleItems).insert(
            PendingSaleItemsCompanion.insert(
              saleId: saleId,
              productId: productId,
              productName: item['productName']?.toString() ?? '',
              sku: item['sku']?.toString() ??
                  (item['product'] is Map
                      ? (item['product'] as Map)['sku']?.toString() ?? ''
                      : ''),
              quantity: quantity,
              unitPrice: _parseNumber(item['unitPrice']) ?? 0,
              discount: Value(_parseNumber(item['discount']) ?? 0),
              total: _parseNumber(
                    item['total'] ?? item['totalAmount'],
                  ) ??
                  0,
              unit: Value(item['unit']?.toString()),
              quantityPerUnit: Value(_parseNumber(item['quantityPerUnit'])),
            ),
          );
      // A queued sale can arrive from another phone without an existing sale
      // row. Keep its stock movement in the same transaction as the sale and
      // event ledger so retries never deduct stock twice.
      await _db.decrementStock(productId, branchId, quantity);
    }
  }

  Future<void> _processSaleVoided(Map<String, dynamic> payload) async {
    final saleId = payload['saleId']?.toString().trim() ??
        payload['id']?.toString().trim() ??
        '';
    final reason = payload['reason']?.toString().trim() ?? '';
    if (saleId.isEmpty || reason.isEmpty) {
      throw const FormatException(
          'Sale void event is missing its sale id or reason');
    }
    final sale = await _db.getPendingSaleById(saleId);
    if (sale == null) {
      throw const FormatException('Voided sale was not found on this device');
    }
    if (sale.status != 'VOIDED') {
      await _db.voidPendingSale(
        saleId,
        reason: reason,
        voidedBy: payload['voidedById']?.toString(),
      );
    }
  }

  Future<void> _processStockAdjusted(Map<String, dynamic> payload) async {
    final productId = payload['productId'] as String?;
    final branchId = payload['branchId'] as String?;
    final quantity = (payload['quantity'] as num?)?.toDouble();
    if (productId != null && branchId != null && quantity != null) {
      await _db.decrementStock(productId, branchId, quantity);
    }
  }

  Future<void> _processCustomer(Map<String, dynamic> payload) async {
    final customerId = payload['id']?.toString().trim() ?? '';
    final name = payload['name']?.toString().trim() ?? '';
    if (customerId.isEmpty || name.isEmpty) {
      throw const FormatException(
          'Customer sync event is missing its id or name');
    }
    await _db.upsertCustomerById(
      customerId,
      name,
      phone: payload['phone']?.toString(),
      email: payload['email']?.toString(),
      location: (payload['location'] ?? payload['address'])?.toString(),
    );
  }

  Future<void> _processSupplierInvoice(
    Map<String, dynamic> payload,
    String eventId,
  ) async {
    final supplierName = payload['supplierName']?.toString().trim() ?? '';
    if (supplierName.isEmpty) {
      throw const FormatException(
          'Supplier invoice is missing the supplier name');
    }

    final invoiceItems = (payload['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) {
          final quantity = _parseNumber(item['quantity']) ?? 1;
          final unitCost = _parseNumber(item['unitCost']) ?? 0;
          return <String, dynamic>{
            'name': (item['name'] ?? item['productName'])?.toString() ?? '',
            'sku': item['sku']?.toString(),
            'quantity': quantity,
            'unit': item['unit']?.toString() ?? 'piece',
            'unitCost': unitCost,
            'lineTotal': _parseNumber(item['lineTotal'] ?? item['total']) ??
                quantity * unitCost,
            'confidence': _parseNumber(item['confidence']) ?? 0,
            'rawText': item['rawText']?.toString(),
          };
        })
        .where((item) => (item['name'] as String).trim().isNotEmpty)
        .toList();
    if (invoiceItems.isEmpty) {
      throw const FormatException('Supplier invoice has no valid items');
    }

    await _db.recordSupplierInvoice(
      invoiceId: payload['offlineId']?.toString() ?? eventId,
      supplierName: supplierName,
      phone: payload['phone']?.toString(),
      email: payload['email']?.toString(),
      invoiceNumber: payload['invoiceNumber']?.toString(),
      terms: payload['fundingSource']?.toString() == 'CREDIT_SUPPLIER'
          ? 'pay_later'
          : 'paid',
      paidAmount: _parseNumber(payload['paidAmount']) ?? 0,
      dueDate: _parseTimestamp(payload['dueDate']),
      items: invoiceItems,
    );
  }

  String _uuid() => 'sync-${DateTime.now().microsecondsSinceEpoch}';

  DateTime? _parseTimestamp(dynamic value) {
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        value < 100000000000 ? value * 1000 : value,
      );
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  double? _parseNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return value == null ? null : double.tryParse(value.toString());
  }

  /// Idempotent CREATE TABLE for the event-dedupe ledger, following the
  /// same `_ensure*Table` pattern as the other phone-server route files.
  Future<void> _ensureProcessedEventsTable() async {
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS server_processed_events ('
      '  event_id TEXT PRIMARY KEY NOT NULL, '
      '  processed_at TEXT NOT NULL'
      ')',
    );
  }

  shelf.Response _error(int statusCode, String message) {
    return shelf.Response(
      statusCode,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );
  }
}
