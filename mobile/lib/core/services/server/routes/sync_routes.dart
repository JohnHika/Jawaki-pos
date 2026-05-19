import 'dart:convert';
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
        final eventType = event['eventType'] as String? ?? '';
        final payload = event['payload'] as Map<String, dynamic>? ?? {};
        // Process based on event type
        switch (eventType) {
          case 'SALE_CREATED':
            _processSaleCreated(payload);
            break;
          case 'SALE_VOIDED':
            _processSaleVoided(payload);
            break;
          case 'STOCK_ADJUSTED':
            _processStockAdjusted(payload);
            break;
          default:
            break;
        }

        results.add({
          'success': true,
          'eventId': eventId,
          'serverId': 'srv-$eventId',
          'serverTimestamp': DateTime.now().toIso8601String(),
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
  Future<shelf.Response> _handleConflicts(shelf.Request request) async {
    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');

    final conflicts =
        (body['conflicts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
            [];
    final results = <Map<String, dynamic>>[];

    for (final conflict in conflicts) {
      results.add({
        'eventId': conflict['eventId'],
        'success': true,
        'resolution': conflict['resolution'] ?? 'SERVER_WINS',
      });
    }

    return shelf.Response.ok(
      jsonEncode(results),
      headers: {'content-type': 'application/json'},
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

  void _processSaleCreated(Map<String, dynamic> payload) async {
    // Sales should already be in the local DB (PendingSales)
    // This handles sync from client phones that went offline
    final saleId = payload['id'] as String?;
    if (saleId != null) {
      await _db.markSaleAsSynced(saleId);
    }
  }

  void _processSaleVoided(Map<String, dynamic> payload) async {
    final saleId = payload['id'] as String?;
    if (saleId != null) {
      await _db.customStatement(
        'UPDATE pending_sales SET status = \'VOIDED\' WHERE id = ${Sql.str(saleId)}',
      );
    }
  }

  void _processStockAdjusted(Map<String, dynamic> payload) async {
    final productId = payload['productId'] as String?;
    final branchId = payload['branchId'] as String?;
    final quantity = (payload['quantity'] as num?)?.toInt();
    if (productId != null && branchId != null && quantity != null) {
      await _db.decrementStock(productId, branchId, quantity);
    }
  }

  String _uuid() => 'sync-${DateTime.now().microsecondsSinceEpoch}';

  shelf.Response _error(int statusCode, String message) {
    return shelf.Response(
      statusCode,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );
  }
}
