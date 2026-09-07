import 'dart:convert';
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

    for (final event in events) {
      try {
        final eventId = event['eventId'] as String? ?? _uuid();
        final deviceId = event['deviceId'] as String? ?? '';
        final eventType = event['eventType'] as String? ?? '';
        final payload = event['payload'] as Map<String, dynamic>? ?? {};

        // Dedupe retried events: a client retrying the same eventId must
        // not re-run side effects (e.g. STOCK_ADJUSTED would decrement
        // stock twice and corrupt it). Check-before-process, then insert
        // into the ledger after processing succeeds — so a processing
        // failure leaves the event un-recorded and a client retry can
        // still land it.
        await _ensureProcessedEventsTable();
        final alreadyProcessed = await _db
            .customSelect(
              'SELECT event_id FROM server_processed_events WHERE event_id = ${Sql.str(eventId)}',
            )
            .get();
        final isDuplicate = alreadyProcessed.isNotEmpty;
        if (!isDuplicate) {
          // Process based on event type
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
            default:
              break;
          }
          await _db.customStatement(
            'INSERT OR IGNORE INTO server_processed_events (event_id, processed_at) '
            'VALUES (${Sql.vals([eventId, DateTime.now().toIso8601String()])})',
          );
        }

        results.add({
          'success': true,
          'eventId': eventId,
          'deviceId': deviceId,
          'serverId': 'srv-$eventId',
          'serverTimestamp': DateTime.now().toIso8601String(),
          'duplicate': isDuplicate,
        });
      } catch (e) {
        results.add({
          'success': false,
          'eventId': event['eventId'],
          'error': e.toString(),
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
    final since = body?['since'] as String?;
    final sinceDate = since != null
        ? DateTime.tryParse(since)
        : DateTime.now().subtract(const Duration(days: 7));

    // Return a list of events that happened since the given timestamp
    // For now, we return product/category updates from the sync_queue
    final events = <Map<String, dynamic>>[];

    if (sinceDate != null) {
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
        // Table might be empty, that's fine
      }
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
      return shelf.Response.ok(
        jsonEncode([]),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/v1/sync/retry
  Future<shelf.Response> _handleRetry(shelf.Request request) async {
    try {
      final failed = await _db.getFailedSyncQueue();
      for (final item in failed) {
        await _db.resetSyncQueueItem(item.id);
      }
      return shelf.Response.ok(
        jsonEncode({'message': 'Retry initiated', 'count': failed.length}),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return shelf.Response.ok(
        jsonEncode({'message': 'Nothing to retry', 'count': 0}),
        headers: {'content-type': 'application/json'},
      );
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
    if (saleId == null) return;

    final existing = await _db.getPendingSaleById(saleId);
    if (existing != null) {
      await _db.markSaleAsSynced(saleId);
      return;
    }

    final createdAt = _parseTimestamp(payload['createdAt']) ?? DateTime.now();
    final items = payload['items'] as List<dynamic>? ?? [];

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
            cashierId: Value(
                payload['cashierId']?.toString() ??
                    payload['userId']?.toString() ??
                    ''),
            branchId: Value(payload['branchId']?.toString() ?? ''),
            notes: Value(payload['notes']?.toString()),
            status: Value(payload['status']?.toString() ?? 'COMPLETED'),
            createdAt: Value(createdAt),
            isSynced: const Value(true),
            syncedAt: Value(createdAt),
          ),
        );

    for (final item in items.whereType<Map>()) {
      await _db.into(_db.pendingSaleItems).insert(
            PendingSaleItemsCompanion.insert(
              saleId: saleId,
              productId: item['productId']?.toString() ?? '',
              productName: item['productName']?.toString() ?? '',
              sku: item['sku']?.toString() ??
                  (item['product'] is Map
                      ? (item['product'] as Map)['sku']?.toString() ?? ''
                      : ''),
              quantity: _parseNumber(item['quantity'])?.round() ?? 0,
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
    }
  }

  Future<void> _processSaleVoided(Map<String, dynamic> payload) async {
    final saleId = payload['id'] as String?;
    if (saleId != null) {
      await _db.customStatement(
        'UPDATE pending_sales SET status = \'VOIDED\' WHERE id = ${Sql.str(saleId)}',
      );
    }
  }

  Future<void> _processStockAdjusted(Map<String, dynamic> payload) async {
    final productId = payload['productId'] as String?;
    final branchId = payload['branchId'] as String?;
    final quantity = (payload['quantity'] as num?)?.toInt();
    if (productId != null && branchId != null && quantity != null) {
      await _db.decrementStock(productId, branchId, quantity);
    }
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
