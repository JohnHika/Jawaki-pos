import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;
import '../../../database/app_database.dart';
import '../middleware.dart';
import '../server_user_access.dart';
import '../sql_helper.dart';

/// Sync routes for phone server mode.
///
/// Client phones push their offline events here, and pull changes.
class SyncRoutes {
  final AppDatabase _db;
  final double _taxRatePercent;

  SyncRoutes(this._db, {double taxRatePercent = 0})
      : _taxRatePercent = taxRatePercent;

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
    final access = await ServerUserAccess.load(_db, request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!access.has('sync.push')) {
      return _error(403, 'You do not have permission to sync changes');
    }

    final body = getRequestBody(request);
    if (body == null) return _error(400, 'Request body required');
    final rawEvents = body['events'];
    if (rawEvents is! List) return _error(400, 'Sync events must be a list');
    if (rawEvents.length > 100) {
      return _error(413, 'Sync batches cannot contain more than 100 events');
    }
    final events = <Map<String, dynamic>>[];
    for (final rawEvent in rawEvents) {
      if (rawEvent is! Map) {
        return _error(400, 'Each sync event must be an object');
      }
      try {
        events.add(Map<String, dynamic>.from(rawEvent));
      } on TypeError {
        return _error(400, 'Each sync event must have string keys');
      }
    }
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
        final permission = _permissionForEvent(eventType);
        if (permission == null) {
          throw UnsupportedError('Unsupported sync event: $eventType');
        }
        if (!access.has(permission)) {
          throw const _SyncAuthorizationException(
            'You do not have permission to sync this change',
          );
        }
        final branchId = _branchForEvent(eventType, payload) ?? access.branchId;
        if (const {
              'SALE_CREATED',
              'STOCK_ADJUSTED',
              'SUPPLIER_INVOICE_CREATED',
            }.contains(eventType) &&
            (branchId == null || branchId.isEmpty)) {
          throw const FormatException('This sync event needs a branch');
        }
        if (branchId != null && !_canWriteBranch(access, branchId)) {
          throw const _SyncAuthorizationException(
            'You cannot sync changes for another branch',
          );
        }

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
              await _processSaleCreated(
                payload,
                access,
                branchId: branchId!,
              );
              break;
            case 'SALE_VOIDED':
              await _processSaleVoided(payload, access);
              break;
            case 'STOCK_ADJUSTED':
              await _processStockAdjusted(payload, branchId: branchId!);
              break;
            case 'CUSTOMER_CREATED':
            case 'CUSTOMER_UPDATED':
              await _processCustomer(payload);
              break;
            case 'SUPPLIER_INVOICE_CREATED':
              await _processSupplierInvoice(
                payload,
                eventId,
                branchId: branchId,
              );
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
        final saleVoidConflict = e is LocalSaleVoidConflict;
        results.add({
          'success': false,
          'eventId': eventId,
          'error': unsupportedEvent
              ? 'This update is not supported by the shop phone. Update it, then retry Sync.'
              : e is _SyncAuthorizationException
                  ? e.message
                  : e is LocalSaleVoidConflict
                      ? e.message
                      : 'This update could not be saved. We’ll retry shortly; check Sync status if the problem continues.',
          'retryable': !unsupportedEvent &&
              e is! _SyncAuthorizationException &&
              !saleVoidConflict,
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
    final access = await ServerUserAccess.load(_db, request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!access.has('sync.pull')) {
      return _error(403, 'You do not have permission to pull sync changes');
    }
    final body = getRequestBody(request);
    final rawSince = body?['since'];
    if (rawSince != null && rawSince is! String) {
      return _error(400, 'Sync timestamp must be a valid date');
    }
    final since = rawSince as String?;
    final sinceDate = since != null
        ? DateTime.tryParse(since)
        : DateTime.now().subtract(const Duration(days: 7));
    if (sinceDate == null) {
      return _error(400, 'Sync timestamp must be a valid date');
    }

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
    final access = await ServerUserAccess.load(_db, request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!access.has('sync.resolve_conflicts')) {
      return _error(
          403, 'You do not have permission to resolve sync conflicts');
    }
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
    final access = await ServerUserAccess.load(_db, request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!access.has('sync.status')) {
      return _error(403, 'You do not have permission to view sync status');
    }
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
    final access = await ServerUserAccess.load(_db, request);
    if (access == null) return _error(401, 'Your session is no longer active');
    if (!access.has('sync.push')) {
      return _error(403, 'You do not have permission to retry sync');
    }
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

  Future<void> _processSaleCreated(
    Map<String, dynamic> payload,
    ServerUserAccess access, {
    required String branchId,
  }) async {
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
      if (existing.branchId != branchId ||
          (existing.cashierId != access.userId &&
              !access.has('sales.view_all'))) {
        throw const _SyncAuthorizationException(
          'You cannot sync this sale from another cashier or branch',
        );
      }
      await _db.markSaleAsSynced(saleId);
      return;
    }

    final createdAt = _parseTimestamp(payload['createdAt']) ?? DateTime.now();
    final items = payload['items'] as List<dynamic>? ?? [];
    final saleItems = items.whereType<Map>().toList();
    final paymentMethod =
        (payload['paymentMethod']?.toString() ?? 'CASH').toUpperCase();
    if (saleItems.isEmpty ||
        saleItems.length != items.length ||
        !const {'CASH', 'CREDIT', 'SPLIT'}.contains(paymentMethod) ||
        !_taxRatePercent.isFinite ||
        _taxRatePercent < 0) {
      throw const FormatException(
          'Sale sync event has an invalid payment method or item list');
    }

    final saleItemCompanions = <PendingSaleItemsCompanion>[];
    var computedSubtotal = 0.0;
    for (final item in saleItems) {
      final productId = item['productId']?.toString().trim() ?? '';
      final quantity = _parseNumber(item['quantity']) ?? 0;
      final unitPrice = _parseNumber(item['unitPrice']) ?? 0;
      final lineDiscount = _parseNumber(item['discount']) ?? 0;
      if (productId.isEmpty ||
          !quantity.isFinite ||
          quantity <= 0 ||
          quantity > 10000000 ||
          !unitPrice.isFinite ||
          unitPrice < 0 ||
          !lineDiscount.isFinite ||
          lineDiscount < 0 ||
          lineDiscount > unitPrice * quantity) {
        throw const FormatException(
            'Sale sync item has an invalid product, price, discount, or quantity');
      }
      final lineTotal = unitPrice * quantity - lineDiscount;
      if (!lineTotal.isFinite || lineTotal < 0) {
        throw const FormatException('Sale sync item total is invalid');
      }
      final reportedLineTotal =
          _parseNumber(item['total'] ?? item['totalAmount']);
      if (reportedLineTotal != null &&
          (!reportedLineTotal.isFinite ||
              reportedLineTotal < 0 ||
              (reportedLineTotal - lineTotal).abs() > 0.01)) {
        throw const FormatException(
            'Sale sync item total does not match its price');
      }
      computedSubtotal += lineTotal;
      saleItemCompanions.add(PendingSaleItemsCompanion.insert(
        saleId: saleId,
        productId: productId,
        productName: item['productName']?.toString() ?? '',
        sku: item['sku']?.toString() ??
            (item['product'] is Map
                ? (item['product'] as Map)['sku']?.toString() ?? ''
                : ''),
        quantity: quantity,
        unitPrice: unitPrice,
        discount: Value(lineDiscount),
        total: lineTotal,
        unit: Value(item['unit']?.toString()),
        quantityPerUnit: Value(_parseNumber(item['quantityPerUnit'])),
      ));
    }

    final reportedSubtotal = _parseNumber(payload['subtotal']);
    if (reportedSubtotal != null &&
        (!reportedSubtotal.isFinite ||
            (reportedSubtotal - computedSubtotal).abs() > 0.01)) {
      throw const FormatException(
          'Sale sync subtotal does not match its items');
    }
    final subtotal = computedSubtotal;
    final discount = _parseNumber(payload['discountAmount']) ?? 0;
    if (!discount.isFinite || discount < 0 || discount > subtotal) {
      throw const FormatException('Sale sync discount is invalid');
    }
    final computedTax = (subtotal - discount) * (_taxRatePercent / 100);
    final reportedTax = _parseNumber(payload['taxAmount']);
    if (reportedTax != null && (!reportedTax.isFinite || reportedTax < 0)) {
      throw const FormatException('Sale sync tax is invalid');
    }
    final tax = reportedTax ?? computedTax;
    final total = subtotal + tax - discount;
    final reportedTotal = _parseNumber(payload['totalAmount']);
    if (!total.isFinite ||
        total <= 0 ||
        total > 10000000 ||
        (reportedTotal != null &&
            (!reportedTotal.isFinite ||
                reportedTotal < 0 ||
                (reportedTotal - total).abs() > 0.01))) {
      throw const FormatException('Sale sync total is invalid');
    }

    final customerId = payload['customerId']?.toString().trim();
    final paidAmount = _parseNumber(payload['paidAmount']) ??
        (paymentMethod == 'CASH' ? total : 0);
    if (!paidAmount.isFinite ||
        paidAmount < 0 ||
        (paymentMethod != 'CASH' && paidAmount > total) ||
        (paymentMethod == 'CASH' && paidAmount < total)) {
      throw const FormatException('Sale sync paid amount is invalid');
    }
    var debtAmount = 0.0;
    String? paymentReference = payload['paymentReference']?.toString();
    if (paymentMethod == 'CREDIT') {
      if (customerId == null || customerId.isEmpty) {
        throw const FormatException('A credit sale needs a customer');
      }
      debtAmount = total - paidAmount;
      paymentReference ??= customerId;
    } else if (paymentMethod == 'SPLIT') {
      if (customerId == null || customerId.isEmpty) {
        throw const FormatException('A split sale needs a customer');
      }
      final rawTenders = payload['tenders'];
      final tenders =
          rawTenders is List ? rawTenders.whereType<Map>().toList() : <Map>[];
      final creditTenders = tenders
          .where((tender) =>
              tender['method']?.toString().toUpperCase() == 'CREDIT')
          .toList();
      final cashTenders = tenders
          .where(
              (tender) => tender['method']?.toString().toUpperCase() == 'CASH')
          .toList();
      if (tenders.length != 2 ||
          creditTenders.length != 1 ||
          cashTenders.length != 1) {
        throw const FormatException(
            'A split sale needs cash and credit tenders');
      }
      final creditAmount = _parseNumber(creditTenders.single['amount']);
      final cashAmount = _parseNumber(cashTenders.single['amount']);
      if (creditAmount == null ||
          cashAmount == null ||
          !creditAmount.isFinite ||
          !cashAmount.isFinite ||
          creditAmount <= 0 ||
          cashAmount <= 0 ||
          (creditAmount + cashAmount - total).abs() > 0.01) {
        throw const FormatException(
            'Split sale tenders do not match its total');
      }
      debtAmount = creditAmount;
      paymentReference = jsonEncode(tenders);
    }

    await _db.createPendingSale(
      PendingSalesCompanion(
        id: Value(saleId),
        receiptNumber: Value(payload['receiptNumber']?.toString() ?? ''),
        subtotal: Value(subtotal),
        discount: Value(discount),
        tax: Value(tax),
        total: Value(total),
        paymentMethod: Value(paymentMethod),
        paymentReference: Value(paymentReference),
        customerId: Value(customerId),
        cashierId: Value(access.userId),
        branchId: Value(branchId),
        notes: Value(payload['notes']?.toString()),
        status: const Value('COMPLETED'),
        createdAt: Value(createdAt),
        isSynced: const Value(true),
        syncedAt: Value(createdAt),
      ),
      saleItemCompanions,
      customerBalanceDelta: debtAmount,
      decrementLocalStock: true,
    );
  }

  Future<void> _processSaleVoided(
    Map<String, dynamic> payload,
    ServerUserAccess access,
  ) async {
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
    if (!_canWriteBranch(access, sale.branchId)) {
      throw const _SyncAuthorizationException(
        'You cannot void a sale from another branch',
      );
    }
    if (sale.status != 'VOIDED') {
      await _db.voidPendingSale(
        saleId,
        reason: reason,
        voidedBy: access.userId,
        guardUnallocatedCollections: true,
      );
    }
  }

  Future<void> _processStockAdjusted(
    Map<String, dynamic> payload, {
    required String branchId,
  }) async {
    final productId = payload['productId'] as String?;
    final quantity = _parseNumber(payload['quantity']);
    if (productId == null ||
        productId.trim().isEmpty ||
        branchId.trim().isEmpty ||
        quantity == null ||
        !quantity.isFinite ||
        quantity == 0 ||
        quantity.abs() > 10000000) {
      throw const FormatException('Stock sync event has invalid details');
    }
    await _db.decrementStock(productId, branchId, quantity);
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
    String eventId, {
    String? branchId,
  }) async {
    final supplierName = payload['supplierName']?.toString().trim() ?? '';
    if (supplierName.isEmpty) {
      throw const FormatException(
          'Supplier invoice is missing the supplier name');
    }

    final rawItems = payload['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw const FormatException('Supplier invoice has no valid items');
    }
    final invoiceItems = <Map<String, dynamic>>[];
    var invoiceTotal = 0.0;
    for (final rawItem in rawItems) {
      if (rawItem is! Map) {
        throw const FormatException('Supplier invoice item is invalid');
      }
      final name =
          (rawItem['name'] ?? rawItem['productName'])?.toString().trim() ?? '';
      final quantity = _parseNumber(rawItem['quantity']) ?? 1;
      final unitCost = _parseNumber(rawItem['unitCost']) ?? 0;
      final lineTotal =
          _parseNumber(rawItem['lineTotal'] ?? rawItem['total']) ??
              quantity * unitCost;
      if (name.isEmpty ||
          !quantity.isFinite ||
          quantity < 0.001 ||
          quantity > 10000000 ||
          !unitCost.isFinite ||
          unitCost < 0 ||
          !lineTotal.isFinite ||
          lineTotal < 0 ||
          (lineTotal - quantity * unitCost).abs() > 0.01) {
        throw const FormatException('Supplier invoice item has invalid values');
      }
      final confidence = _parseNumber(rawItem['confidence']) ?? 0;
      if (!confidence.isFinite || confidence < 0 || confidence > 1) {
        throw const FormatException('Supplier invoice confidence is invalid');
      }
      invoiceTotal += lineTotal;
      invoiceItems.add({
        'name': name,
        'sku': rawItem['sku']?.toString(),
        'quantity': quantity,
        'unit': rawItem['unit']?.toString() ?? 'piece',
        'unitCost': unitCost,
        'lineTotal': lineTotal,
        'confidence': confidence,
        'rawText': rawItem['rawText']?.toString(),
      });
    }
    if (!invoiceTotal.isFinite || invoiceTotal > 1000000000) {
      throw const FormatException('Supplier invoice total is invalid');
    }
    final paidAmount = _parseNumber(payload['paidAmount']) ?? 0;
    if (!paidAmount.isFinite || paidAmount < 0 || paidAmount > invoiceTotal) {
      throw const FormatException('Supplier invoice payment is invalid');
    }

    await _db.recordSupplierInvoice(
      invoiceId: payload['offlineId']?.toString() ?? eventId,
      branchId: branchId,
      supplierName: supplierName,
      phone: payload['phone']?.toString(),
      email: payload['email']?.toString(),
      invoiceNumber: payload['invoiceNumber']?.toString(),
      terms: payload['fundingSource']?.toString() == 'CREDIT_SUPPLIER'
          ? 'pay_later'
          : 'paid',
      paidAmount: paidAmount,
      dueDate: _parseTimestamp(payload['dueDate']),
      items: invoiceItems,
    );
  }

  String? _permissionForEvent(String eventType) => switch (eventType) {
        'SALE_CREATED' => 'sales.create',
        'SALE_VOIDED' => 'sales.void',
        'STOCK_ADJUSTED' => 'inventory.stock.adjust',
        'CUSTOMER_CREATED' => 'customers.create',
        'CUSTOMER_UPDATED' => 'customers.update',
        'SUPPLIER_INVOICE_CREATED' => 'suppliers.invoices_create',
        _ => null,
      };

  String? _branchForEvent(String eventType, Map<String, dynamic> payload) {
    if (!const {
      'SALE_CREATED',
      'STOCK_ADJUSTED',
      'SUPPLIER_INVOICE_CREATED',
    }.contains(eventType)) {
      return null;
    }
    final branchId = payload['branchId']?.toString().trim();
    return branchId == null || branchId.isEmpty ? null : branchId;
  }

  bool _canWriteBranch(ServerUserAccess access, String branchId) {
    final normalized = branchId.trim();
    if (normalized.isEmpty) return false;
    if (access.branchId != null) return access.branchId == normalized;
    return access.has('branches.update') || access.has('sales.view_all');
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

class _SyncAuthorizationException implements Exception {
  final String message;
  const _SyncAuthorizationException(this.message);
}
