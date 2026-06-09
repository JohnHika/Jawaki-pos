import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;
import '../../../database/app_database.dart';
import '../middleware.dart';
import '../sql_helper.dart';

/// Inventory routes for phone server mode.
class InventoryRoutes {
  final AppDatabase _db;

  InventoryRoutes(this._db);

  void addRoutes(Router r) {
    r.get('/api/v1/inventory/stock', _handleGetStock);
    r.get('/api/v1/inventory/low-stock', _handleGetLowStock);
    r.post('/api/v1/inventory/batches/receive', _handleReceiveBatches);

    // Stock requests
    r.get('/api/v1/inventory/stock-requests/stats/summary',
        _handleStockRequestStats);
    r.get('/api/v1/inventory/stock-requests', _handleGetStockRequests);
    r.get('/api/v1/inventory/stock-requests/<id>', _handleGetStockRequest);
    r.post('/api/v1/inventory/stock-requests', _handleCreateStockRequest);
    r.put('/api/v1/inventory/stock-requests/<id>', _handleUpdateStockRequest);
    r.put('/api/v1/inventory/stock-requests/<id>/resolve',
        _handleResolveStockRequest);
    r.put('/api/v1/inventory/stock-requests/<id>/cancel',
        _handleCancelStockRequest);
  }

  /// GET /api/v1/inventory/stock?branchId=
  Future<shelf.Response> _handleGetStock(shelf.Request request) async {
    final params = request.url.queryParameters;
    final branchId = params['branchId'] ?? '';

    final report = await _db.getInventoryReport();
    final filtered = branchId.isNotEmpty
        ? report.where((r) => r['branchId'] == branchId).toList()
        : report;

    return shelf.Response.ok(
      jsonEncode(filtered),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/v1/inventory/low-stock
  Future<shelf.Response> _handleGetLowStock(shelf.Request request) async {
    final lowStock = await _db.getLowStockProducts();
    return shelf.Response.ok(
      jsonEncode(lowStock),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST /api/v1/inventory/batches/receive
  Future<shelf.Response> _handleReceiveBatches(shelf.Request request) async {
    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');

    final productId = body['productId'] as String?;
    final branchId = body['branchId'] as String?;
    final batches = body['batches'];
    final quantity = batches is List
        ? batches.fold<int>(0, (sum, item) {
            if (item is! Map) return sum;
            final batchQty = (item['quantity'] as num?)?.toDouble() ?? 0;
            final unitsPerQuantity =
                (item['unitsPerQuantity'] as num?)?.toDouble() ?? 1;
            return sum + (batchQty * unitsPerQuantity).round();
          })
        : ((body['quantity'] as num?)?.toInt() ?? 0);
    final batchNumber = body['batchNumber'] as String? ??
        'BATCH-${DateTime.now().millisecondsSinceEpoch}';

    if (productId == null || branchId == null || quantity <= 0) {
      return _error(400, 'productId, branchId, and quantity > 0 are required');
    }

    // Upsert local stock
    final existing = await _db.getProductStock(productId, branchId);
    if (existing != null) {
      await (_db.update(_db.localStock)
            ..where((s) =>
                s.productId.equals(productId) & s.branchId.equals(branchId)))
          .write(LocalStockCompanion(
        quantity: Value(existing.quantity + quantity),
        updatedAt: Value(DateTime.now()),
      ));
    } else {
      await _db.into(_db.localStock).insert(LocalStockCompanion(
            id: Value('stock-$branchId-$productId'),
            productId: Value(productId),
            branchId: Value(branchId),
            quantity: Value(quantity),
            updatedAt: Value(DateTime.now()),
          ));
    }

    return shelf.Response(
      201,
      body: jsonEncode({
        'message': 'Stock received',
        'productId': productId,
        'quantity': quantity,
        'batchNumber': batchNumber,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Stock requests
  Future<shelf.Response> _handleGetStockRequests(shelf.Request request) async {
    final params = request.url.queryParameters;
    final branchId = params['branchId'];
    final status = params['status'];

    final conditions = <String>[];
    if (branchId != null && branchId.isNotEmpty) {
      conditions.add('branch_id = ${Sql.str(branchId)}');
    }
    if (status != null && status.isNotEmpty) {
      conditions.add('status = ${Sql.str(status)}');
    }
    final where =
        conditions.isNotEmpty ? ' WHERE ${conditions.join(' AND ')}' : '';
    final sql = 'SELECT * FROM stock_requests$where ORDER BY created_at DESC';

    try {
      final result = await _db.customSelect(sql).get();
      return shelf.Response.ok(
        jsonEncode(result.map((r) => _stockRequestToMap(r)).toList()),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return shelf.Response.ok(
        jsonEncode([]),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<shelf.Response> _handleGetStockRequest(
      shelf.Request request, String id) async {
    try {
      final result = await _db
          .customSelect(
            'SELECT * FROM stock_requests WHERE id = ${Sql.str(id)}',
          )
          .get();
      if (result.isEmpty) return _error(404, 'Stock request not found');
      return shelf.Response.ok(
        jsonEncode(_stockRequestToMap(result.first)),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(404, 'Stock request not found');
    }
  }

  Future<shelf.Response> _handleCreateStockRequest(
      shelf.Request request) async {
    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');

    await _ensureStockRequestsTable();
    final id = _uuid();
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      'INSERT INTO stock_requests '
      '(id, branch_id, product_id, quantity, unit, reason, priority, status, requested_by_id, created_at, updated_at) '
      'VALUES (${Sql.str(id)}, ${Sql.str(body['branchId'] as String? ?? '')}, '
      '${Sql.str(body['productId'] as String? ?? '')}, '
      '${(body['quantity'] as num?)?.toInt() ?? 1}, '
      '${Sql.str(body['unit'] as String? ?? 'piece')}, '
      '${Sql.str(body['reason'] as String? ?? '')}, '
      '${Sql.str(body['priority'] as String? ?? 'normal')}, '
      "'PENDING', "
      '${Sql.str(body['requestedById'] as String? ?? '')}, '
      '${Sql.str(now)}, ${Sql.str(now)})',
    );

    return shelf.Response(
      201,
      body: jsonEncode({'message': 'Stock request created', 'id': id}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<shelf.Response> _handleUpdateStockRequest(
      shelf.Request request, String id) async {
    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');

    try {
      await _db.customStatement(
        'UPDATE stock_requests SET '
        'quantity = ${(body['quantity'] as num?)?.toInt() ?? 1}, '
        'priority = ${Sql.str(body['priority'] as String? ?? 'normal')}, '
        'reason = ${Sql.str(body['reason'] as String? ?? '')}, '
        'updated_at = ${Sql.str(DateTime.now().toIso8601String())} '
        'WHERE id = ${Sql.str(id)}',
      );
      return shelf.Response.ok(
        jsonEncode({'message': 'Stock request updated'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(404, 'Stock request not found');
    }
  }

  Future<shelf.Response> _handleResolveStockRequest(
      shelf.Request request, String id) async {
    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');

    final status = body['status'] as String? ?? 'APPROVED';
    final resolution = body['resolution'] as String?;
    final now = Sql.str(DateTime.now().toIso8601String());

    try {
      await _db.customStatement(
        'UPDATE stock_requests SET status = ${Sql.str(status)}, '
        'resolution = ${Sql.str(resolution ?? '')}, '
        'resolved_at = $now, updated_at = $now WHERE id = ${Sql.str(id)}',
      );
      return shelf.Response.ok(
        jsonEncode({'message': 'Stock request resolved'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(404, 'Stock request not found');
    }
  }

  Future<shelf.Response> _handleCancelStockRequest(
      shelf.Request request, String id) async {
    final now = Sql.str(DateTime.now().toIso8601String());
    try {
      await _db.customStatement(
        'UPDATE stock_requests SET status = \'CANCELLED\', updated_at = $now WHERE id = ${Sql.str(id)}',
      );
      return shelf.Response.ok(
        jsonEncode({'message': 'Stock request cancelled'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(404, 'Stock request not found');
    }
  }

  Future<shelf.Response> _handleStockRequestStats(shelf.Request request) async {
    try {
      final result = await _db
          .customSelect(
            'SELECT status, COUNT(*) as count FROM stock_requests GROUP BY status',
          )
          .get();
      final stats = <String, int>{};
      for (final row in result) {
        stats[row.read<String>('status')] = row.read<int>('count');
      }
      return shelf.Response.ok(
        jsonEncode(stats),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return shelf.Response.ok(
        jsonEncode({
          'PENDING': 0,
          'APPROVED': 0,
          'REJECTED': 0,
          'FULFILLED': 0,
          'CANCELLED': 0
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<void> _ensureStockRequestsTable() async {
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS stock_requests ('
      '  id TEXT PRIMARY KEY NOT NULL, '
      '  branch_id TEXT NOT NULL, '
      '  product_id TEXT NOT NULL, '
      '  quantity INTEGER NOT NULL DEFAULT 1, '
      '  unit TEXT NOT NULL DEFAULT \'piece\', '
      '  reason TEXT, '
      '  priority TEXT NOT NULL DEFAULT \'normal\', '
      '  status TEXT NOT NULL DEFAULT \'PENDING\', '
      '  resolution TEXT, '
      '  requested_by_id TEXT, '
      '  resolved_by_id TEXT, '
      '  resolved_at TEXT, '
      '  created_at TEXT NOT NULL, '
      '  updated_at TEXT NOT NULL'
      ')',
    );
  }

  Map<String, dynamic> _stockRequestToMap(QueryRow r) {
    return {
      'id': r.read<String>('id'),
      'branchId': r.read<String>('branch_id'),
      'productId': r.read<String>('product_id'),
      'quantity': r.read<int>('quantity'),
      'unit': r.read<String>('unit'),
      'reason': r.readNullable<String>('reason'),
      'priority': r.read<String>('priority'),
      'status': r.read<String>('status'),
      'resolution': r.readNullable<String>('resolution'),
      'requestedById': r.readNullable<String>('requested_by_id'),
      'createdAt': r.read<String>('created_at'),
    };
  }

  String _uuid() => 'inv-${DateTime.now().microsecondsSinceEpoch}';

  shelf.Response _error(int statusCode, String message) {
    return shelf.Response(
      statusCode,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );
  }
}
