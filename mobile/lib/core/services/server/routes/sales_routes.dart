import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;
import '../../../database/app_database.dart';
import '../middleware.dart';

/// Sales routes for phone server mode.
class SalesRoutes {
  final AppDatabase _db;
  final double _taxRatePercent;

  SalesRoutes(this._db, {double taxRatePercent = 0})
      : _taxRatePercent = taxRatePercent;

  void addRoutes(Router r) {
    r.post('/api/v1/sales', _handleCreateSale);
    r.get('/api/v1/sales', _handleGetSales);
    r.get('/api/v1/sales/daily-summary', _handleDailySummary);
    r.get('/api/v1/sales/summary/<branchId>/<date>', _handleBranchDailySummary);
    r.get('/api/v1/sales/<id>', _handleGetSale);
    r.get('/api/v1/sales/<saleId>/receipt', _handleGetReceipt);
    r.post('/api/v1/sales/<id>/void', _handleVoidSale);
  }

  /// POST /api/v1/sales — create a new sale
  Future<shelf.Response> _handleCreateSale(shelf.Request request) async {
    final access = await _loadSalesAccess(request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!access.has('sales.create')) {
      return _error(403, 'You do not have permission to create sales');
    }

    final body = getRequestBody(request);
    if (body == null) {
      return _error(400, 'Request body is required');
    }

    final saleId = body['offlineId']?.toString().trim().isNotEmpty == true
        ? body['offlineId'].toString().trim()
        : body['id']?.toString().trim().isNotEmpty == true
            ? body['id'].toString().trim()
            : _uuid();
    final branchId = body['branchId']?.toString().trim() ?? '';
    final rawItems = body['items'];
    if (branchId.isEmpty || rawItems is! List || rawItems.isEmpty) {
      return _error(400, 'A branch and at least one sale item are required');
    }
    if (access.branchId != null && access.branchId != branchId) {
      return _error(403, 'You can only create sales for your assigned branch');
    }
    if (access.branchId == null && !access.has('sales.view_all')) {
      return _error(403, 'Your account needs an assigned branch to create sales');
    }

    // The cashier commits a local receipt before asking the server to sync.
    // Reuse that id and acknowledge the saved receipt instead of creating a
    // duplicate with a generated id when the phone server is this device.
    final existing = await _db.getPendingSaleById(saleId);
    if (existing != null) {
      if (existing.branchId != branchId) {
        return _error(409, 'The sale id is already used by another branch');
      }
      if (existing.cashierId != access.userId &&
          !access.has('sales.view_all')) {
        return _error(403, 'You cannot access this sale');
      }
      return _saleCreatedResponse(
        id: existing.id,
        receiptNumber: existing.receiptNumber,
        created: false,
      );
    }

    final itemCompanions = <PendingSaleItemsCompanion>[];
    var subtotal = 0.0;
    for (final rawItem in rawItems) {
      if (rawItem is! Map) {
        return _error(400, 'Sale items must be valid objects');
      }
      final item = Map<String, dynamic>.from(rawItem);
      final productId = item['productId']?.toString().trim() ?? '';
      final quantity = _number(item['quantity']) ?? 0;
      final unitPrice = _number(item['unitPrice']) ?? 0;
      final lineDiscount = _number(item['discount']) ?? 0;
      if (productId.isEmpty ||
          !quantity.isFinite ||
          quantity <= 0 ||
          !unitPrice.isFinite ||
          unitPrice < 0 ||
          !lineDiscount.isFinite ||
          lineDiscount < 0 ||
          lineDiscount > unitPrice * quantity) {
        return _error(
            400, 'Each sale item needs a product, price, and quantity');
      }

      final product = await _db.getProduct(productId);
      final productName =
          item['productName']?.toString().trim().isNotEmpty == true
              ? item['productName'].toString().trim()
              : product?.name ?? '';
      if (productName.isEmpty) {
        return _error(400, 'A sale item could not be matched to a product');
      }
      final expectedLineTotal =
          (unitPrice * quantity - lineDiscount).clamp(0, double.infinity);
      final reportedLineTotal = _number(item['total']);
      if (reportedLineTotal != null &&
          (!reportedLineTotal.isFinite ||
              reportedLineTotal < 0 ||
              (reportedLineTotal - expectedLineTotal).abs() > 0.01)) {
        return _error(400, 'A sale item total does not match its price');
      }
      final lineTotal = expectedLineTotal.toDouble();
      if (!lineTotal.isFinite || lineTotal < 0) {
        return _error(400, 'Sale item totals must be valid amounts');
      }
      subtotal += lineTotal;
      itemCompanions.add(
        PendingSaleItemsCompanion.insert(
          saleId: saleId,
          productId: productId,
          productName: productName,
          sku: item['sku']?.toString() ?? product?.sku ?? '',
          quantity: quantity,
          unitPrice: unitPrice,
          discount: Value(lineDiscount),
          total: lineTotal,
          unit: Value(item['unit']?.toString() ?? item['saleUnit']?.toString()),
          quantityPerUnit: Value(
            _number(item['quantityPerUnit'] ?? item['unitConversionFactor']),
          ),
        ),
      );
    }

    final paymentMethod =
        (body['paymentMethod']?.toString() ?? 'CASH').toUpperCase();
    if (!const {'CASH', 'CREDIT', 'SPLIT'}.contains(paymentMethod)) {
      return _error(
        400,
        paymentMethod == 'MPESA'
            ? 'M-Pesa sales must be confirmed by the payment provider'
            : 'The selected payment method is not supported',
      );
    }
    final discount = _number(body['discountAmount']) ?? 0;
    if (!discount.isFinite ||
        discount < 0 ||
        discount > subtotal ||
        !_taxRatePercent.isFinite ||
        _taxRatePercent < 0) {
      return _error(400, 'The sale discount or tax settings are invalid');
    }
    final tax = ((subtotal - discount).clamp(0, double.infinity) *
            (_taxRatePercent / 100))
        .toDouble();
    final computedTotal =
        (subtotal + tax - discount).clamp(0, double.infinity).toDouble();
    final reportedTotal = _number(body['totalAmount']);
    if (reportedTotal != null &&
        (!reportedTotal.isFinite ||
            reportedTotal < 0 ||
            (reportedTotal - computedTotal).abs() > 0.01)) {
      return _error(400, 'The sale total does not match its items and tax');
    }
    final total = computedTotal;
    if (!total.isFinite || total <= 0 || total > 10000000) {
      return _error(400, 'The sale total must be between 0 and 10,000,000');
    }
    final customerId = body['customerId']?.toString();
    final tenders = body['tenders'];
    final paidAmount = (_number(body['paidAmount']) ?? total).toDouble();
    if (!paidAmount.isFinite || paidAmount < 0) {
      return _error(400, 'The amount paid must be a valid amount');
    }
    if (!{'CREDIT', 'SPLIT'}.contains(paymentMethod) && paidAmount < total) {
      return _error(400, 'The amount paid is less than the sale total');
    }
    var debtAmount = paymentMethod == 'CREDIT'
        ? (total - paidAmount).clamp(0, double.infinity).toDouble()
        : 0.0;
    String? paymentReference = body['paymentReference']?.toString();
    if (paymentMethod == 'SPLIT') {
      if (tenders is! List || tenders.length != 2 || customerId == null) {
        return _error(400, 'A split payment needs cash, debt, and a customer');
      }
      final tenderRows = tenders.whereType<Map>().toList();
      final creditTenders = tenderRows
          .where((tender) => tender['method']?.toString() == 'CREDIT')
          .toList();
      final cashTenders = tenderRows
          .where((tender) => tender['method']?.toString() == 'CASH')
          .toList();
      if (tenderRows.length != 2 ||
          creditTenders.length != 1 ||
          cashTenders.length != 1) {
        return _error(
            400, 'A split payment needs one cash and one debt portion');
      }
      final creditAmount = _number(creditTenders.single['amount']);
      final cashAmount = _number(cashTenders.single['amount']);
      if (creditAmount == null ||
          cashAmount == null ||
          !creditAmount.isFinite ||
          !cashAmount.isFinite ||
          creditAmount <= 0 ||
          cashAmount <= 0 ||
          (creditAmount + cashAmount - total).abs() > 0.01) {
        return _error(400, 'Cash and debt must add up to the sale total');
      }
      debtAmount = creditAmount;
      paymentReference = jsonEncode(tenders);
    } else if (paymentMethod == 'CREDIT') {
      if (customerId == null || customerId.isEmpty) {
        return _error(400, 'Choose a customer before recording a credit sale');
      }
      paymentReference ??= customerId;
    }

    final now = DateTime.now();
    final receiptNumber = _generateReceiptNo();
    final cashierId = access.userId;
    final saleCompanion = PendingSalesCompanion.insert(
      id: saleId,
      receiptNumber: receiptNumber,
      subtotal: subtotal,
      discount: Value(discount),
      tax: Value(tax),
      total: total,
      paymentMethod: paymentMethod,
      paymentReference: Value(paymentReference),
      customerId: Value(customerId),
      cashierId: cashierId,
      branchId: branchId,
      notes: Value(body['notes']?.toString()),
      status: const Value('COMPLETED'),
      createdAt: now,
      // This route accepts a sale into the host phone's local database. The
      // host still needs to upload it to the cloud when connectivity returns.
      isSynced: const Value(false),
    );

    await _db.createPendingSale(
      saleCompanion,
      itemCompanions,
      customerBalanceDelta: debtAmount,
      decrementLocalStock: true,
    );

    return _saleCreatedResponse(
      id: saleId,
      receiptNumber: receiptNumber,
      created: true,
    );
  }

  shelf.Response _saleCreatedResponse({
    required String id,
    required String receiptNumber,
    required bool created,
  }) {
    return shelf.Response(
      created ? 201 : 200,
      body: jsonEncode({
        'success': true,
        'data': {
          'id': id,
          'offlineId': id,
          'receiptNumber': receiptNumber,
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return value == null ? null : double.tryParse(value.toString());
  }

  /// GET /api/v1/sales?startDate=&endDate=&page=&limit=
  Future<shelf.Response> _handleGetSales(shelf.Request request) async {
    final access = await _loadSalesAccess(request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!access.has('sales.view') &&
        !access.has('sales.create') &&
        !access.has('reporting.sales_summary')) {
      return _error(403, 'You do not have permission to view sales');
    }

    final params = request.url.queryParameters;
    final parsedStart = DateTime.tryParse(params['startDate'] ?? '');
    final parsedEnd = DateTime.tryParse(params['endDate'] ?? '');
    if ((params.containsKey('startDate') && parsedStart == null) ||
        (params.containsKey('endDate') && parsedEnd == null)) {
      return _error(400, 'Sale dates must be valid dates');
    }
    final startDate =
        parsedStart ?? DateTime.now().subtract(const Duration(days: 30));
    final endDate = parsedEnd ?? DateTime.now();
    final page =
        (int.tryParse(params['page'] ?? '1') ?? 1).clamp(1, 1000000).toInt();
    final limit =
        (int.tryParse(params['limit'] ?? '50') ?? 50).clamp(1, 500).toInt();

    final rows = await _db.getSalesByDateRange(startDate, endDate);
    final sales = rows.where((sale) {
      if (access.branchId != null && sale.branchId != access.branchId) {
        return false;
      }
      if (access.has('sales.view_all') ||
          access.has('reporting.sales_summary') ||
          sale.cashierId == access.userId) {
        return true;
      }
      // The receipt screen allows staff with sales.view to open synced
      // receipts; unsynced sales by another cashier remain restricted.
      return access.has('sales.view') && sale.isSynced;
    }).toList();
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
  Future<shelf.Response> _handleGetSale(
      shelf.Request request, String id) async {
    final access = await _loadSalesAccess(request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!access.has('sales.view') && !access.has('sales.create')) {
      return _error(403, 'You do not have permission to view sales');
    }

    final sales = await _db.getSalesByDateRange(
      DateTime.now().subtract(const Duration(days: 365)),
      DateTime.now().add(const Duration(days: 1)),
    );
    final sale = sales.where((s) => s.id == id).firstOrNull;
    if (sale == null) {
      return _error(404, 'Sale not found');
    }
    if (access.branchId != null && sale.branchId != access.branchId) {
      return _error(404, 'Sale not found');
    }
    if (!access.has('sales.view_all') &&
        sale.cashierId != access.userId &&
        !(access.has('sales.view') && sale.isSynced)) {
      return _error(403, 'You can only view receipts for sales you recorded');
    }

    final items = await _db.getSaleItems(id);
    return shelf.Response.ok(
      jsonEncode({
        ..._saleToMap(sale),
        'items': items
            .map((i) => {
                  'id': i.id,
                  'productId': i.productId,
                  'productName': i.productName,
                  'sku': i.sku,
                  'quantity': i.quantity,
                  'unitPrice': i.unitPrice,
                  'discount': i.discount,
                  'total': i.total,
                })
            .toList(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/v1/sales/<saleId>/receipt
  Future<shelf.Response> _handleGetReceipt(
      shelf.Request request, String saleId) async {
    return _handleGetSale(request, saleId);
  }

  /// GET /api/v1/sales/daily-summary
  Future<shelf.Response> _handleDailySummary(shelf.Request request) async {
    final access = await _loadSalesAccess(request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!_canViewSalesSummary(access)) {
      return _error(403, 'You do not have permission to view sales summaries');
    }
    final summary = await _db.getDashboardSummary(branchId: access.branchId);
    return shelf.Response.ok(
      jsonEncode(summary),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/v1/sales/summary/<branchId>/<date>
  Future<shelf.Response> _handleBranchDailySummary(
    shelf.Request request,
    String branchId,
    String date,
  ) async {
    final access = await _loadSalesAccess(request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!_canViewSalesSummary(access)) {
      return _error(403, 'You do not have permission to view sales summaries');
    }
    if (access.branchId != null && branchId != access.branchId) {
      return _error(
          403, 'You can only view summaries for your assigned branch');
    }

    final parsedDate = DateTime.tryParse(date);
    if (parsedDate == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      return _error(400, 'A valid date in YYYY-MM-DD format is required');
    }

    final summary = await _db.getDailySalesSummary(branchId, parsedDate);
    return shelf.Response.ok(
      jsonEncode(summary),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST /api/v1/sales/<id>/void
  Future<shelf.Response> _handleVoidSale(
      shelf.Request request, String id) async {
    final access = await _loadSalesAccess(request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!access.has('sales.void')) {
      return _error(403, 'You do not have permission to void sales');
    }

    final body = getRequestBody(request);
    final reason = body?['reason']?.toString().trim() ?? '';
    if (reason.isEmpty) {
      return _error(400, 'A reason is required to void a sale');
    }

    final sale = await _db.getPendingSaleById(id);
    if (sale == null) {
      return _error(404, 'Sale not found');
    }
    if (access.branchId != null && sale.branchId != access.branchId) {
      return _error(404, 'Sale not found');
    }

    // This is the authoritative phone-server copy. The database operation
    // marks the receipt and restores stock atomically, and is idempotent if
    // the caller retries after losing the response.
    if (sale.status != 'VOIDED') {
      await _db.voidPendingSale(
        id,
        reason: reason,
        voidedBy: access.userId,
      );
    }
    return shelf.Response.ok(
      jsonEncode({
        'success': true,
        'data': {
          'id': id,
          'status': 'VOIDED',
          'voidReason': sale.voidReason ?? reason,
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<_SalesAccess?> _loadSalesAccess(shelf.Request request) async {
    final authUser = getAuthUser(request);
    final userId = authUser?['sub']?.toString();
    if (userId == null || userId.isEmpty) return null;
    final rows = await _db.customSelect(
      'SELECT permissions_json, is_active, branch_id, tenant_id '
      'FROM server_users WHERE id = ?',
      variables: [Variable.withString(userId)],
    ).get();
    if (rows.isEmpty || rows.first.read<int>('is_active') != 1) return null;
    final tokenTenantId = authUser?['tenantId']?.toString();
    final userTenantId = rows.first.read<String>('tenant_id');
    if (tokenTenantId == null || tokenTenantId != userTenantId) return null;

    final permissionsJson = rows.first.readNullable<String>('permissions_json');
    if (permissionsJson == null) return null;
    try {
      final permissions = jsonDecode(permissionsJson);
      if (permissions is! List) return null;
      return _SalesAccess(
        userId: userId,
        branchId: _nonEmpty(rows.first.readNullable<String>('branch_id')),
        permissions: permissions.map((item) => item.toString()).toSet(),
      );
    } on FormatException {
      return null;
    }
  }

  bool _canViewSalesSummary(_SalesAccess access) =>
      access.has('sales.view_all') ||
      access.has('reporting.dashboard') ||
      access.has('reporting.sales_summary');

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
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

class _SalesAccess {
  final String userId;
  final String? branchId;
  final Set<String> permissions;

  const _SalesAccess({
    required this.userId,
    required this.branchId,
    required this.permissions,
  });

  bool has(String permission) => permissions.contains(permission);
}
