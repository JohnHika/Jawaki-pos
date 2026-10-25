import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;
import '../../../database/app_database.dart';
import '../middleware.dart';
import '../server_user_access.dart';
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
    r.get(
      '/api/v1/inventory/stock-requests/stats/summary',
      _handleStockRequestStats,
    );
    r.get('/api/v1/inventory/stock-requests', _handleGetStockRequests);
    r.get('/api/v1/inventory/stock-requests/<id>', _handleGetStockRequest);
    r.post('/api/v1/inventory/stock-requests', _handleCreateStockRequest);
    r.put('/api/v1/inventory/stock-requests/<id>', _handleUpdateStockRequest);
    r.put(
      '/api/v1/inventory/stock-requests/<id>/resolve',
      _handleResolveStockRequest,
    );
    r.put(
      '/api/v1/inventory/stock-requests/<id>/cancel',
      _handleCancelStockRequest,
    );
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
    final access = await ServerUserAccess.load(_db, request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!access.has('inventory.batches.receive')) {
      return _error(403, 'You do not have permission to receive stock');
    }

    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');

    final productId = body['productId'] as String?;
    final branchId = body['branchId']?.toString().trim();
    final batches = body['batches'];
    var quantity = 0.0;
    if (batches is List) {
      if (batches.isEmpty) {
        return _error(400, 'At least one valid stock batch is required');
      }
      for (final item in batches) {
        if (item is! Map || item['quantity'] is! num) {
          return _error(400, 'Each stock batch needs a valid quantity');
        }
        final batchQuantity = (item['quantity'] as num).toDouble();
        final unitsPerQuantity = item['unitsPerQuantity'] == null
            ? 1.0
            : item['unitsPerQuantity'] is num
                ? (item['unitsPerQuantity'] as num).toDouble()
                : double.nan;
        if (!batchQuantity.isFinite ||
            batchQuantity <= 0 ||
            batchQuantity > 10000000 ||
            !unitsPerQuantity.isFinite ||
            unitsPerQuantity <= 0 ||
            unitsPerQuantity > 10000000) {
          return _error(
              400, 'Stock batch quantity and unit size must be positive');
        }
        quantity += batchQuantity * unitsPerQuantity;
      }
    } else if (body['quantity'] is num) {
      quantity = (body['quantity'] as num).toDouble();
    }
    final batchNumber = body['batchNumber'] as String? ??
        'BATCH-${DateTime.now().millisecondsSinceEpoch}';

    if (productId == null ||
        productId.trim().isEmpty ||
        branchId == null ||
        branchId.isEmpty ||
        !quantity.isFinite ||
        quantity <= 0 ||
        quantity > 10000000) {
      return _error(400, 'productId, branchId, and quantity > 0 are required');
    }
    if (access.branchId != null && access.branchId != branchId) {
      return _error(403, 'You can only receive stock for your assigned branch');
    }
    if (access.branchId == null && !access.has('branches.update')) {
      return _error(
          403, 'Your account needs an assigned branch to receive stock');
    }

    final currentQuantity = await _db.incrementLocalStock(
      productId: productId,
      branchId: branchId,
      quantity: quantity,
    );

    return shelf.Response(
      201,
      body: jsonEncode({
        'message': 'Stock received',
        'productId': productId,
        'quantity': quantity,
        'currentQuantity': currentQuantity,
        'batchNumber': batchNumber,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Stock requests
  Future<shelf.Response> _handleGetStockRequests(shelf.Request request) async {
    final params = request.url.queryParameters;
    final user = getAuthUser(request);
    final tokenBranchId = user?['branchId']?.toString();
    final requestedBranchId = params['branchId'];
    if (tokenBranchId != null &&
        tokenBranchId.isNotEmpty &&
        requestedBranchId != null &&
        requestedBranchId != tokenBranchId) {
      return _error(403, 'You cannot view requests from another branch');
    }
    final branchId = requestedBranchId ?? tokenBranchId;
    final status = params['status'];
    final priority = params['priority'];
    final productId = params['productId'];
    final requestedById = params['requestedById'];
    final page = _positiveInt(params['page'], fallback: 1);
    final limit = _positiveInt(params['limit'], fallback: 20);

    if (page == null || page > 10000) {
      return _error(400, 'Page must be between 1 and 10,000');
    }
    if (limit == null || limit > 500) {
      return _error(400, 'Limit must be between 1 and 500');
    }
    if (status != null &&
        status.isNotEmpty &&
        !_stockStatuses.contains(status)) {
      return _error(400, 'Unsupported stock request status');
    }
    if (priority != null &&
        priority.isNotEmpty &&
        !_stockPriorities.contains(priority)) {
      return _error(400, 'Unsupported stock request priority');
    }

    final conditions = <String>[];
    if (branchId != null && branchId.isNotEmpty) {
      conditions.add('branch_id = ${Sql.str(branchId)}');
    }
    if (status != null && status.isNotEmpty) {
      conditions.add('status = ${Sql.str(status)}');
    }
    if (priority != null && priority.isNotEmpty) {
      conditions.add('priority = ${Sql.str(priority)}');
    }
    if (productId != null && productId.isNotEmpty) {
      conditions.add('product_id = ${Sql.str(productId)}');
    }
    if (requestedById != null && requestedById.isNotEmpty) {
      conditions.add('requested_by_id = ${Sql.str(requestedById)}');
    }
    final where =
        conditions.isNotEmpty ? ' WHERE ${conditions.join(' AND ')}' : '';

    try {
      await _ensureStockRequestsTable();
      final countRows = await _db
          .customSelect('SELECT COUNT(*) AS count FROM stock_requests$where')
          .get();
      final total = countRows.first.read<int>('count');
      final offset = (page - 1) * limit;
      final result = await _db
          .customSelect(
            'SELECT * FROM stock_requests$where '
            "ORDER BY CASE WHEN status = 'PENDING' THEN 0 ELSE 1 END, created_at DESC "
            'LIMIT $limit OFFSET $offset',
          )
          .get();
      return shelf.Response.ok(
        jsonEncode({
          'items': result.map(_stockRequestToMap).toList(),
          'total': total,
          'page': page,
          'limit': limit,
          'totalPages': (total / limit).ceil(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(500, 'Could not load stock requests');
    }
  }

  Future<shelf.Response> _handleGetStockRequest(
    shelf.Request request,
    String id,
  ) async {
    try {
      final user = getAuthUser(request);
      final branchId = user?['branchId']?.toString();
      final branchFilter = branchId == null || branchId.isEmpty
          ? ''
          : ' AND branch_id = ${Sql.str(branchId)}';
      await _ensureStockRequestsTable();
      final result = await _db
          .customSelect(
            'SELECT * FROM stock_requests WHERE id = ${Sql.str(id)}$branchFilter',
          )
          .get();
      if (result.isEmpty) return _error(404, 'Stock request not found');
      return shelf.Response.ok(
        jsonEncode(_stockRequestToMap(result.first)),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(500, 'Could not load this stock request');
    }
  }

  Future<shelf.Response> _handleCreateStockRequest(
    shelf.Request request,
  ) async {
    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');

    final user = getAuthUser(request);
    final requesterId = user?['sub']?.toString();
    final branchId = body['branchId']?.toString().trim() ?? '';
    final productId = body['productId']?.toString().trim() ?? '';
    final quantity = body['quantity'];
    final unit = body['unit']?.toString().trim() ?? 'piece';
    final reason = body['reason']?.toString().trim() ?? '';
    final priority = body['priority']?.toString() ?? 'normal';
    final quantityError = _quantityError(quantity);
    if (requesterId == null || requesterId.isEmpty) {
      return _error(401, 'Sign in again to create a stock request');
    }
    if (branchId.isEmpty || productId.isEmpty) {
      return _error(400, 'Branch and product are required');
    }
    if (user?['branchId'] != null && user!['branchId'].toString() != branchId) {
      return _error(403, 'You cannot request stock for another branch');
    }
    if (quantityError != null) return _error(400, quantityError);
    if (unit.isEmpty || unit.length > 20) {
      return _error(400, 'Unit must contain 1 to 20 characters');
    }
    if (reason.isNotEmpty && (reason.length < 10 || reason.length > 500)) {
      return _error(400, 'Reason must contain 10 to 500 characters');
    }
    if (!_stockPriorities.contains(priority)) {
      return _error(400, 'Unsupported stock request priority');
    }

    try {
      await _ensureStockRequestsTable();
      final id = _uuid();
      final now = DateTime.now().toIso8601String();
      await _db.customStatement(
        'INSERT INTO stock_requests '
        '(id, branch_id, product_id, quantity, unit, reason, priority, status, requested_by_id, created_at, updated_at) '
        'VALUES (${Sql.str(id)}, ${Sql.str(branchId)}, '
        '${Sql.str(productId)}, ${(quantity as num).toDouble()}, '
        '${Sql.str(unit)}, ${Sql.opt(reason.isEmpty ? null : reason)}, '
        '${Sql.str(priority)}, '
        "'PENDING', "
        '${Sql.str(requesterId)}, '
        '${Sql.str(now)}, ${Sql.str(now)})',
      );

      return shelf.Response(
        201,
        body: jsonEncode({'message': 'Stock request created', 'id': id}),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(500, 'Could not create the stock request');
    }
  }

  Future<shelf.Response> _handleUpdateStockRequest(
    shelf.Request request,
    String id,
  ) async {
    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');
    final user = getAuthUser(request);
    final requesterId = user?['sub']?.toString();
    if (requesterId == null || requesterId.isEmpty) {
      return _error(401, 'Sign in again to update this request');
    }

    final assignments = <String>[];
    if (body.containsKey('quantity')) {
      final error = _quantityError(body['quantity']);
      if (error != null) return _error(400, error);
      assignments.add('quantity = ${(body['quantity'] as num).toDouble()}');
    }
    if (body.containsKey('unit')) {
      final unit = body['unit']?.toString().trim() ?? '';
      if (unit.isEmpty || unit.length > 20) {
        return _error(400, 'Unit must contain 1 to 20 characters');
      }
      assignments.add('unit = ${Sql.str(unit)}');
    }
    if (body.containsKey('reason')) {
      final reason = body['reason']?.toString().trim() ?? '';
      if (reason.isNotEmpty && (reason.length < 10 || reason.length > 500)) {
        return _error(400, 'Reason must contain 10 to 500 characters');
      }
      assignments.add('reason = ${Sql.opt(reason.isEmpty ? null : reason)}');
    }
    if (body.containsKey('priority')) {
      final priority = body['priority']?.toString() ?? '';
      if (!_stockPriorities.contains(priority)) {
        return _error(400, 'Unsupported stock request priority');
      }
      assignments.add('priority = ${Sql.str(priority)}');
    }
    if (assignments.isEmpty) return _error(400, 'No changes were provided');
    assignments
        .add('updated_at = ${Sql.str(DateTime.now().toIso8601String())}');
    final branchId = user?['branchId']?.toString();
    final branchFilter = branchId == null || branchId.isEmpty
        ? ''
        : ' AND branch_id = ${Sql.str(branchId)}';

    try {
      await _ensureStockRequestsTable();
      final changed = await _db.customUpdate(
        'UPDATE stock_requests SET ${assignments.join(', ')} '
        'WHERE id = ${Sql.str(id)} '
        'AND requested_by_id = ${Sql.str(requesterId)} '
        "AND status = 'PENDING'$branchFilter",
      );
      if (changed == 0) {
        return _error(404, 'Stock request not found or no longer editable');
      }
      return shelf.Response.ok(
        jsonEncode({'message': 'Stock request updated'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(500, 'Could not update the stock request');
    }
  }

  Future<shelf.Response> _handleResolveStockRequest(
    shelf.Request request,
    String id,
  ) async {
    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');

    final user = getAuthUser(request);
    final role = user?['role']?.toString().toUpperCase();
    if (!const {'OWNER', 'ADMIN', 'MANAGER', 'SUPERVISOR'}.contains(role)) {
      return _error(403, 'A manager or supervisor must resolve stock requests');
    }
    final status = body['status']?.toString() ?? '';
    if (!_resolvableStockStatuses.contains(status)) {
      return _error(400, 'Status must be APPROVED, REJECTED, or FULFILLED');
    }
    final resolution = body['resolution']?.toString().trim() ?? '';
    if (resolution.isNotEmpty &&
        (resolution.length < 10 || resolution.length > 1000)) {
      return _error(400, 'Resolution must contain 10 to 1,000 characters');
    }
    final branchId = user?['branchId']?.toString();
    final branchFilter = branchId == null || branchId.isEmpty
        ? ''
        : ' AND branch_id = ${Sql.str(branchId)}';
    final now = Sql.str(DateTime.now().toIso8601String());

    try {
      await _ensureStockRequestsTable();
      final changed = await _db.customUpdate(
        'UPDATE stock_requests SET status = ${Sql.str(status)}, '
        'resolution = ${Sql.opt(resolution.isEmpty ? null : resolution)}, '
        'resolved_by_id = ${Sql.opt(user?['sub']?.toString())}, '
        'resolved_at = $now, updated_at = $now '
        "WHERE id = ${Sql.str(id)} AND status IN ('PENDING', 'APPROVED')$branchFilter",
      );
      if (changed == 0) {
        final existing = await _db
            .customSelect(
              'SELECT id FROM stock_requests WHERE id = ${Sql.str(id)}$branchFilter',
            )
            .get();
        return existing.isEmpty
            ? _error(404, 'Stock request not found')
            : _error(409, 'This stock request has already been resolved');
      }
      return shelf.Response.ok(
        jsonEncode({'message': 'Stock request resolved'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(500, 'Could not resolve the stock request');
    }
  }

  Future<shelf.Response> _handleCancelStockRequest(
    shelf.Request request,
    String id,
  ) async {
    final user = getAuthUser(request);
    final requesterId = user?['sub']?.toString();
    if (requesterId == null || requesterId.isEmpty) {
      return _error(401, 'Sign in again to cancel this request');
    }
    final branchId = user?['branchId']?.toString();
    final branchFilter = branchId == null || branchId.isEmpty
        ? ''
        : ' AND branch_id = ${Sql.str(branchId)}';
    final now = Sql.str(DateTime.now().toIso8601String());
    try {
      await _ensureStockRequestsTable();
      final changed = await _db.customUpdate(
        "UPDATE stock_requests SET status = 'CANCELLED', updated_at = $now "
        'WHERE id = ${Sql.str(id)} '
        'AND requested_by_id = ${Sql.str(requesterId)} '
        "AND status = 'PENDING'$branchFilter",
      );
      if (changed == 0) {
        return _error(404, 'Stock request not found or no longer cancellable');
      }
      return shelf.Response.ok(
        jsonEncode({'message': 'Stock request cancelled'}),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(500, 'Could not cancel the stock request');
    }
  }

  Future<shelf.Response> _handleStockRequestStats(shelf.Request request) async {
    try {
      final user = getAuthUser(request);
      final tokenBranchId = user?['branchId']?.toString();
      final requestedBranchId = request.url.queryParameters['branchId'];
      if (tokenBranchId != null &&
          tokenBranchId.isNotEmpty &&
          requestedBranchId != null &&
          requestedBranchId != tokenBranchId) {
        return _error(403, 'You cannot view another branch’s stock requests');
      }
      final branchId = requestedBranchId ?? tokenBranchId;
      final branchFilter = branchId == null || branchId.isEmpty
          ? ''
          : ' WHERE branch_id = ${Sql.str(branchId)}';
      await _ensureStockRequestsTable();
      final result = await _db
          .customSelect(
            'SELECT status, COUNT(*) as count FROM stock_requests$branchFilter GROUP BY status',
          )
          .get();
      final stats = <String, int>{
        'pending': 0,
        'approved': 0,
        'rejected': 0,
        'fulfilled': 0,
        'cancelled': 0,
        'urgent': 0,
        'total': 0,
      };
      for (final row in result) {
        final status = row.read<String>('status').toLowerCase();
        final count = row.read<int>('count');
        if (stats.containsKey(status)) {
          stats[status] = count;
          stats['total'] = stats['total']! + count;
        }
      }
      final urgentRows = await _db
          .customSelect(
            "SELECT COUNT(*) AS count FROM stock_requests$branchFilter${branchFilter.isEmpty ? ' WHERE' : ' AND'} priority = 'urgent' AND status = 'PENDING'",
          )
          .get();
      stats['urgent'] = urgentRows.first.read<int>('count');
      return shelf.Response.ok(
        jsonEncode(stats),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return _error(500, 'Could not load stock request statistics');
    }
  }

  Future<void> _ensureStockRequestsTable() async {
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS stock_requests ('
      '  id TEXT PRIMARY KEY NOT NULL, '
      '  branch_id TEXT NOT NULL, '
      '  product_id TEXT NOT NULL, '
      '  quantity REAL NOT NULL DEFAULT 1, '
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
      'quantity': r.read<double>('quantity'),
      'unit': r.read<String>('unit'),
      'reason': r.readNullable<String>('reason'),
      'priority': r.read<String>('priority'),
      'status': r.read<String>('status'),
      'resolution': r.readNullable<String>('resolution'),
      'requestedById': r.readNullable<String>('requested_by_id'),
      'resolvedById': r.readNullable<String>('resolved_by_id'),
      'resolvedAt': r.readNullable<String>('resolved_at'),
      'createdAt': r.read<String>('created_at'),
      'updatedAt': r.read<String>('updated_at'),
    };
  }

  static const Set<String> _stockStatuses = {
    'PENDING',
    'APPROVED',
    'REJECTED',
    'FULFILLED',
    'CANCELLED',
  };
  static const Set<String> _stockPriorities = {
    'low',
    'normal',
    'high',
    'urgent',
  };
  static const Set<String> _resolvableStockStatuses = {
    'APPROVED',
    'REJECTED',
    'FULFILLED',
  };

  int? _positiveInt(String? value, {required int fallback}) {
    if (value == null) return fallback;
    final parsed = int.tryParse(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  String? _quantityError(Object? value) {
    if (value is! num || !value.isFinite || value < 0.001 || value > 10000000) {
      return 'Quantity must be between 0.001 and 10,000,000';
    }
    final scaled = value * 1000;
    if ((scaled - scaled.round()).abs() > 0.000001) {
      return 'Quantity can have at most 3 decimal places';
    }
    return null;
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
