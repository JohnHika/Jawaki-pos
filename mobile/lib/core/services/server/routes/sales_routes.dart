import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;
import '../../../database/app_database.dart';
import '../middleware.dart';
import '../sql_helper.dart';

/// Sales routes for phone server mode.
class SalesRoutes {
  final AppDatabase _db;

  SalesRoutes(this._db);

  void addRoutes(Router r) {
    r.post('/api/v1/sales', _handleCreateSale);
    r.get('/api/v1/sales', _handleGetSales);
    r.get('/api/v1/sales/daily-summary', _handleDailySummary);
    r.get('/api/v1/sales/<id>', _handleGetSale);
    r.get('/api/v1/sales/<saleId>/receipt', _handleGetReceipt);
    r.post('/api/v1/sales/<id>/void', _handleVoidSale);
  }

  /// POST /api/v1/sales — create a new sale
  Future<shelf.Response> _handleCreateSale(shelf.Request request) async {
    final body = getRequestBody(request);
    if (body == null) {
      return _error(400, 'Request body is required');
    }

    final items = (body['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final saleCompanion = PendingSalesCompanion(
      id: Value(body['id'] as String? ?? _uuid()),
      receiptNumber: Value(body['receiptNumber'] as String? ?? _generateReceiptNo()),
      subtotal: Value((body['subtotal'] as num?)?.toDouble() ?? 0),
      discount: Value((body['discount'] as num?)?.toDouble() ?? 0),
      tax: Value((body['tax'] as num?)?.toDouble() ?? 0),
      total: Value((body['total'] as num?)?.toDouble() ?? 0),
      paymentMethod: Value(body['paymentMethod'] as String? ?? 'CASH'),
      paymentReference: Value(body['paymentReference'] as String?),
      customerId: Value(body['customerId'] as String?),
      cashierId: Value(body['cashierId'] as String? ?? ''),
      branchId: Value(body['branchId'] as String? ?? ''),
      notes: Value(body['notes'] as String?),
      status: const Value('COMPLETED'),
      createdAt: Value(DateTime.now()),
      isSynced: const Value(false),
    );

    final itemCompanions = items.map((i) => PendingSaleItemsCompanion(
      saleId: Value(body['id'] as String? ?? _uuid()),
      productId: Value(i['productId'] as String? ?? ''),
      productName: Value(i['productName'] as String? ?? ''),
      sku: Value(i['sku'] as String? ?? ''),
      quantity: Value((i['quantity'] as num?)?.toInt() ?? 1),
      unitPrice: Value((i['unitPrice'] as num?)?.toDouble() ?? 0),
      discount: Value((i['discount'] as num?)?.toDouble() ?? 0),
      total: Value((i['total'] as num?)?.toDouble() ?? 0),
    )).toList();

    await _db.createPendingSale(saleCompanion, itemCompanions);

    return shelf.Response(
      201,
      body: jsonEncode({'message': 'Sale created', 'id': saleCompanion.id.value}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/v1/sales?startDate=&endDate=&page=&limit=
  Future<shelf.Response> _handleGetSales(shelf.Request request) async {
    final params = request.url.queryParameters;
    final startDate = params['startDate'] != null ? DateTime.parse(params['startDate']!) : DateTime.now().subtract(const Duration(days: 30));
    final endDate = params['endDate'] != null ? DateTime.parse(params['endDate']!) : DateTime.now();
    final page = int.tryParse(params['page'] ?? '1') ?? 1;
    final limit = int.tryParse(params['limit'] ?? '50') ?? 50;

    final sales = await _db.getSalesByDateRange(startDate, endDate);
    final total = sales.length;
    final start = (page - 1) * limit;
    final paged = sales.skip(start).take(limit).toList();

    return shelf.Response.ok(
      jsonEncode({
        'items': paged.map((s) => _saleToMap(s)).toList(),
        'total': total,
        'page': page,
        'limit': limit,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/v1/sales/<id>
  Future<shelf.Response> _handleGetSale(shelf.Request request, String id) async {
    final sales = await _db.getSalesByDateRange(
      DateTime.now().subtract(const Duration(days: 365)),
      DateTime.now().add(const Duration(days: 1)),
    );
    final sale = sales.where((s) => s.id == id).firstOrNull;
    if (sale == null) {
      return _error(404, 'Sale not found');
    }

    final items = await _db.getSaleItems(id);
    return shelf.Response.ok(
      jsonEncode({
        ..._saleToMap(sale),
        'items': items.map((i) => {
          'id': i.id,
          'productId': i.productId,
          'productName': i.productName,
          'sku': i.sku,
          'quantity': i.quantity,
          'unitPrice': i.unitPrice,
          'discount': i.discount,
          'total': i.total,
        }).toList(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/v1/sales/<saleId>/receipt
  Future<shelf.Response> _handleGetReceipt(shelf.Request request, String saleId) async {
    return _handleGetSale(request, saleId);
  }

  /// GET /api/v1/sales/daily-summary
  Future<shelf.Response> _handleDailySummary(shelf.Request request) async {
    final summary = await _db.getDashboardSummary();
    return shelf.Response.ok(
      jsonEncode(summary),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST /api/v1/sales/<id>/void
  Future<shelf.Response> _handleVoidSale(shelf.Request request, String id) async {
    await _db.customStatement(
      'UPDATE pending_sales SET status = \'VOIDED\' WHERE id = ${Sql.str(id)}',
    );
    return shelf.Response.ok(
      jsonEncode({'message': 'Sale voided'}),
      headers: {'content-type': 'application/json'},
    );
  }

  Map<String, dynamic> _saleToMap(PendingSale s) {
    return {
      'id': s.id,
      'receiptNumber': s.receiptNumber,
      'subtotal': s.subtotal,
      'discount': s.discount,
      'tax': s.tax,
      'total': s.total,
      'paymentMethod': s.paymentMethod,
      'paymentReference': s.paymentReference,
      'customerId': s.customerId,
      'cashierId': s.cashierId,
      'branchId': s.branchId,
      'notes': s.notes,
      'status': s.status,
      'createdAt': s.createdAt.toIso8601String(),
      'isSynced': s.isSynced,
    };
  }

  String _generateReceiptNo() {
    final now = DateTime.now();
    final seq = now.millisecondsSinceEpoch % 100000;
    return 'RCP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-$seq';
  }

  String _uuid() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'sale-$now-${now % 10000}';
  }

  shelf.Response _error(int statusCode, String message) {
    return shelf.Response(
      statusCode,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );
  }
}
