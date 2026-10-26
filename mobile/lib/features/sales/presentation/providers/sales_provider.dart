import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/auth/app_roles.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';

/// Name printed at the top of a receipt: the business, plus the branch when it
/// differs and the line still fits a 58mm (32 character) printout. Without this
/// every receipt fell back to the placeholder "POS Store".
String? receiptHeaderName(Map<String, dynamic>? user) {
  String? clean(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  final tenant = user?['tenant'];
  final company = clean(tenant is Map ? tenant['name'] : null) ??
      clean(user?['tenantName']) ??
      clean(user?['companyName']);
  final branch = clean(user?['branchName']);

  if (company == null) return branch;
  if (branch == null || branch.toLowerCase() == company.toLowerCase()) {
    return company;
  }
  final combined = '$company - $branch';
  return combined.length <= 32 ? combined : company;
}

/// The credit/debt portion still owed on a sale, for the receipt's
/// "Balance owed" line. A pure CREDIT sale owes its whole total; a SPLIT
/// sale owes the sum of its CREDIT tenders (parsed from paymentReference,
/// where split tenders are stored as JSON). Everything else owes nothing.
double _extractOutstanding(PendingSale sale) {
  final method = sale.paymentMethod.toUpperCase();
  if (method == 'CREDIT') return sale.total;
  if (method == 'SPLIT' && (sale.paymentReference?.isNotEmpty ?? false)) {
    try {
      final tenders = jsonDecode(sale.paymentReference!) as List;
      return tenders
          .whereType<Map>()
          .where(
              (t) => (t['method'] ?? '').toString().toUpperCase() == 'CREDIT')
          .fold<double>(
              0, (sum, t) => sum + ((t['amount'] as num?)?.toDouble() ?? 0));
    } catch (_) {
      return 0;
    }
  }
  return 0;
}

/// Parsed split tenders for the receipt's payment breakdown, or null when
/// the sale isn't a split.
List<Map<String, dynamic>>? _extractTenders(PendingSale sale) {
  if (sale.paymentMethod.toUpperCase() != 'SPLIT') return null;
  if (!(sale.paymentReference?.isNotEmpty ?? false)) return null;
  try {
    final list = jsonDecode(sale.paymentReference!) as List;
    return list
        .whereType<Map>()
        .map((t) => {
              'method': (t['method'] ?? '').toString(),
              'amount': (t['amount'] as num?)?.toDouble() ?? 0,
            })
        .toList();
  } catch (_) {
    return null;
  }
}

double _receiptAmount(Object? value) {
  final amount = value is num ? value.toDouble() : double.tryParse('$value');
  return amount != null && amount.isFinite ? amount : 0;
}

Map<String, dynamic> _normalizeRemoteReceipt(Map<String, dynamic> response) {
  final payload = response['data'] is Map
      ? Map<String, dynamic>.from(response['data'] as Map)
      : response;
  final total = _receiptAmount(payload['total'] ?? payload['totalAmount']);
  final paid = _receiptAmount(payload['paidAmount']);
  final change = _receiptAmount(payload['changeAmount']);
  final method = (payload['paymentMethod'] ?? 'CASH').toString().toUpperCase();
  final rawTenders = payload['paymentTenders'] ?? payload['tenders'];
  final tenders = rawTenders is List
      ? rawTenders
          .whereType<Map>()
          .map((tender) => Map<String, dynamic>.from(tender))
          .toList()
      : const <Map<String, dynamic>>[];
  final creditTenders = tenders
      .where((tender) =>
          (tender['method'] ?? '').toString().toUpperCase() == 'CREDIT')
      .fold<double>(0, (sum, tender) => sum + _receiptAmount(tender['amount']));
  final remaining = total - paid + change;
  final outstanding = method == 'SPLIT' && creditTenders > 0
      ? creditTenders
      : remaining > 0
          ? remaining
          : 0.0;
  final rawItems = payload['items'] as List? ?? const [];
  final items = rawItems.whereType<Map>().map((item) {
    final normalized = Map<String, dynamic>.from(item);
    normalized['total'] = item['total'] ?? item['totalAmount'] ?? 0;
    normalized['productName'] = item['productName'] ?? item['name'] ?? 'Item';
    return normalized;
  }).toList();
  final branch = payload['branch'] is Map
      ? Map<String, dynamic>.from(payload['branch'] as Map)
      : const <String, dynamic>{};

  return {
    ...payload,
    'subtotal': payload['subtotal'] ?? 0,
    'discount': payload['discount'] ?? payload['discountAmount'] ?? 0,
    'tax': payload['tax'] ?? payload['taxAmount'] ?? 0,
    'total': total,
    'branchName': payload['branchName'] ?? branch['name'],
    'branchAddress': payload['branchAddress'] ?? branch['address'],
    'branchPhone': payload['branchPhone'] ?? branch['phone'],
    'cashierName': payload['cashierName'] ?? payload['userName'],
    'customerName': payload['customerName'],
    'customerPhone': payload['customerPhone'],
    'paymentMethod': method,
    'paymentTenders': tenders,
    'outstandingBalance': outstanding,
    'items': items,
  };
}

// Receipt data comes from the local sale first, including offline sales. A
// live row watcher also updates the temporary receipt number and sync badge
// once the background outbox receives the server's canonical result.
final receiptProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, saleId) async* {
  final database = getIt<AppDatabase>();
  final sale = await database.getPendingSaleById(saleId);

  if (sale == null) {
    // A remote sale from another device has no local row to watch.
    yield _normalizeRemoteReceipt(await getIt<ApiClient>().getSale(saleId));
    return;
  }

  final auth = getIt<AuthService>();
  final permissions = RolePermissions(
    auth.currentUser?['permissions'] as List<dynamic>?,
  );
  final isOwnSale = sale.cashierId == auth.userId;

  if (!permissions.canMakeSales && !permissions.has('sales.view')) {
    throw StateError('Your account cannot view sales receipts.');
  }

  if (!permissions.has('sales.view_all') && !isOwnSale) {
    if (sale.isSynced && permissions.has('sales.view')) {
      yield _normalizeRemoteReceipt(await getIt<ApiClient>().getSale(saleId));
      return;
    }
    throw StateError('You can only view receipts for sales you recorded.');
  }

  await for (final currentSale in database.watchPendingSaleById(saleId)) {
    if (currentSale == null) return;
    final items = await database.getSaleItems(saleId);
    final customer = currentSale.customerId == null
        ? null
        : await database.getCustomer(currentSale.customerId!);

    yield {
      'id': currentSale.id,
      'receiptNumber': currentSale.receiptNumber,
      'subtotal': currentSale.subtotal,
      'discount': currentSale.discount,
      'tax': currentSale.tax,
      'total': currentSale.total,
      'paymentMethod': currentSale.paymentMethod,
      'paymentReference': currentSale.paymentReference,
      'createdAt': currentSale.createdAt.toIso8601String(),
      'branchName': receiptHeaderName(auth.currentUser),
      'cashierName': auth.currentUser?['name'],
      'customerName': customer?['name'],
      'customerPhone': customer?['phone'],
      'status': currentSale.status,
      // Keep cloud delivery state visible on the receipt so a device-only
      // sale cannot be mistaken for one already synced across the workspace.
      'isSynced': currentSale.isSynced,
      'voidReason': currentSale.voidReason,
      'voidedAt': currentSale.voidedAt?.toIso8601String(),
      'outstandingBalance': _extractOutstanding(currentSale),
      'paymentTenders': _extractTenders(currentSale),
      'items': items
          .map((item) => {
                'productName': item.productName,
                'name': item.productName,
                'sku': item.sku,
                'quantity': item.quantity,
                'unitPrice': item.unitPrice,
                'price': item.unitPrice,
                'total': item.total,
                'unit': item.unit,
                'quantityPerUnit': item.quantityPerUnit,
              })
          .toList(),
    };
  }
});

// Daily Profit & Loss provider (with expense integration)
final dailyProfitLossProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, branchId) async {
  final apiClient = getIt<ApiClient>();
  final today = DateTime.now().toIso8601String().split('T').first;
  return await apiClient.getDailyProfitLoss(branchId, today);
});

// Sales history provider
final salesHistoryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final apiClient = getIt<ApiClient>();
  return (await apiClient.getSales()).cast<Map<String, dynamic>>();
});
