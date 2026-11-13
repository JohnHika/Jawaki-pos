import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

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

/// Location and phone printed under the shop name on a device-only shop's
/// receipts: what the owner typed under Settings > Receipt details, else what
/// the branch was saved with.
Future<({String address, String phone})> localReceiptContact(
  AppDatabase database,
  Map<String, dynamic>? user,
  String branchId,
) async {
  String clean(Object? value) => value?.toString().trim() ?? '';
  final tenant = user?['tenant'];
  final settings = tenant is Map ? tenant['settings'] : null;
  var address = clean(settings is Map ? settings['receiptAddress'] : null);
  var phone = clean(settings is Map ? settings['receiptPhone'] : null);
  if (address.isEmpty || phone.isEmpty) {
    final branches = await database.getBranches();
    final branch = branches.where((b) => b['id'] == branchId).firstOrNull;
    if (address.isEmpty) address = clean(branch?['location']);
    if (phone.isEmpty) phone = clean(branch?['phone']);
  }
  return (address: address, phone: phone);
}

/// The amount this sale added to the customer's account. Collections are
/// account-level in the local ledger, so a receipt cannot truthfully claim
/// this amount is still outstanding after later payments.
double _extractCreditAmountAtSale(PendingSale sale) {
  if (const {'VOIDED', 'REFUNDED', 'FAILED', 'CANCELLED'}
      .contains(sale.status.toUpperCase())) {
    return 0;
  }
  final method = sale.paymentMethod.toUpperCase();
  if (method == 'CREDIT') {
    return sale.total.isFinite && sale.total > 0 ? sale.total : 0;
  }
  if (method == 'SPLIT' && (sale.paymentReference?.isNotEmpty ?? false)) {
    try {
      final decoded = jsonDecode(sale.paymentReference!);
      if (decoded is! List) return 0;
      final creditTenders = decoded
          .whereType<Map>()
          .where((tender) =>
              (tender['method'] ?? '').toString().toUpperCase() == 'CREDIT')
          .toList(growable: false);
      if (creditTenders.isEmpty) return 0;
      var total = 0.0;
      for (final tender in creditTenders) {
        final rawAmount = tender['amount'];
        final amount = rawAmount is num
            ? rawAmount.toDouble()
            : double.tryParse(rawAmount?.toString() ?? '');
        if (amount == null || !amount.isFinite || amount <= 0) return 0;
        total += amount;
      }
      return total.isFinite && total > 0 ? total : 0;
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
    return _normalizeReceiptTenders(jsonDecode(sale.paymentReference!));
  } catch (_) {
    return null;
  }
}

List<Map<String, dynamic>>? _normalizeReceiptTenders(Object? value) {
  if (value is! List || value.isEmpty) return null;
  final tenders = <Map<String, dynamic>>[];
  for (final row in value) {
    if (row is! Map) return null;
    final method = row['method']?.toString().trim().toUpperCase() ?? '';
    final rawAmount = row['amount'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse(rawAmount?.toString() ?? '');
    if (method.isEmpty || amount == null || !amount.isFinite || amount <= 0) {
      return null;
    }
    tenders.add({'method': method, 'amount': amount});
  }
  return tenders;
}

double _receiptAmount(Object? value) {
  final amount = value is num ? value.toDouble() : double.tryParse('$value');
  return amount != null && amount.isFinite ? amount : 0;
}

bool _containsCustomerData(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key.toString().toLowerCase().startsWith('customer') &&
          entry.value != null) {
        return true;
      }
      if (_containsCustomerData(entry.value)) return true;
    }
  } else if (value is Iterable) {
    return value.any(_containsCustomerData);
  }
  return false;
}

Object? _removeCustomerFields(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        if (!entry.key.toString().toLowerCase().startsWith('customer'))
          entry.key.toString(): _removeCustomerFields(entry.value),
    };
  }
  if (value is List) {
    return value.map(_removeCustomerFields).toList(growable: false);
  }
  return value;
}

Map<String, dynamic> receiptForCustomerVisibility(
  Map<String, dynamic> receipt, {
  required bool canViewCustomerDetails,
}) {
  if (canViewCustomerDetails) return Map<String, dynamic>.from(receipt);
  return Map<String, dynamic>.from(_removeCustomerFields(receipt) as Map);
}

Map<String, dynamic> _normalizeRemoteReceipt(
  Map<String, dynamic> response, {
  required bool canViewCustomerDetails,
}) {
  final payload = response['data'] is Map
      ? Map<String, dynamic>.from(response['data'] as Map)
      : response;
  final visiblePayload = receiptForCustomerVisibility(
    payload,
    canViewCustomerDetails: canViewCustomerDetails,
  );
  final hasCustomer = _containsCustomerData(payload);
  final total = _receiptAmount(payload['total'] ?? payload['totalAmount']);
  final paid = _receiptAmount(payload['paidAmount']);
  final change = _receiptAmount(payload['changeAmount']);
  final method = (payload['paymentMethod'] ?? 'CASH').toString().toUpperCase();
  final status = (payload['status'] ?? '').toString().toUpperCase();
  final rawTenders = payload['paymentTenders'] ?? payload['tenders'];
  final tenders =
      _normalizeReceiptTenders(rawTenders) ?? const <Map<String, dynamic>>[];
  final creditTenders = tenders
      .where((tender) =>
          (tender['method'] ?? '').toString().toUpperCase() == 'CREDIT')
      .fold<double>(0, (sum, tender) => sum + _receiptAmount(tender['amount']));
  final remaining = total - paid + change;
  final rawCreditAmountAtSale = _receiptAmount(
    payload['creditAmountAtSale'] ??
        payload['creditAmount'] ??
        (method == 'SPLIT'
            ? creditTenders
            : method == 'CREDIT'
                ? remaining
                : 0),
  );
  final creditAmountAtSale =
      const {'VOIDED', 'REFUNDED', 'FAILED', 'CANCELLED'}.contains(status)
          ? 0.0
          : rawCreditAmountAtSale > 0
              ? rawCreditAmountAtSale
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
    ...visiblePayload,
    'subtotal': payload['subtotal'] ?? 0,
    'discount': payload['discount'] ?? payload['discountAmount'] ?? 0,
    'tax': payload['tax'] ?? payload['taxAmount'] ?? 0,
    'total': total,
    'branchName': payload['branchName'] ?? branch['name'],
    'branchAddress': payload['branchAddress'] ?? branch['address'],
    'branchPhone': payload['branchPhone'] ?? branch['phone'],
    'cashierName': payload['cashierName'] ?? payload['userName'],
    'hasCustomer': hasCustomer,
    'linkedCustomerDetailsHidden': hasCustomer && !canViewCustomerDetails,
    if (canViewCustomerDetails) 'customerName': payload['customerName'],
    if (canViewCustomerDetails) 'customerPhone': payload['customerPhone'],
    'paymentMethod': method,
    'paymentTenders': tenders,
    'creditAmountAtSale': creditAmountAtSale,
    'items': items,
  };
}

// Receipt data comes from the local sale first, including offline sales. A
// live row watcher also updates the temporary receipt number and sync badge
// once the background outbox receives the server's canonical result.
final receiptProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, saleId) async* {
  final database = getIt<AppDatabase>();
  final auth = getIt<AuthService>();
  final permissions = ref.watch(permissionsProvider);
  final canViewCustomerDetails = permissions.canSeeCustomers;
  final sale = await database.getPendingSaleById(saleId);

  if (sale == null) {
    if (auth.isLocalWorkspace) {
      throw StateError('This receipt is not saved on this device.');
    }
    // A remote sale from another device has no local row to watch.
    yield _normalizeRemoteReceipt(
      await getIt<ApiClient>().getSale(saleId),
      canViewCustomerDetails: canViewCustomerDetails,
    );
    return;
  }

  final isOwnSale = sale.cashierId == auth.userId;

  if (!permissions.canMakeSales && !permissions.has('sales.view')) {
    throw StateError('Your account cannot view sales receipts.');
  }

  if (!permissions.has('sales.view_all') && !isOwnSale) {
    if (permissions.has('sales.view') &&
        (auth.isLocalWorkspace || sale.isSynced)) {
      // In the retired online edition, the server decides whether a synced
      // sale is visible to this cashier. A device-only workspace has no
      // remote receipt endpoint: its saved database is the source of truth.
      if (!auth.isLocalWorkspace) {
        yield _normalizeRemoteReceipt(
          await getIt<ApiClient>().getSale(saleId),
          canViewCustomerDetails: canViewCustomerDetails,
        );
        return;
      }
    } else {
      throw StateError('You can only view receipts for sales you recorded.');
    }
  }

  await for (final currentSale in database.watchPendingSaleById(saleId)) {
    if (currentSale == null) return;
    final items = await database.getSaleItems(saleId);
    final customer = !canViewCustomerDetails || currentSale.customerId == null
        ? null
        : await database.getCustomer(currentSale.customerId!);
    final cashTender = await database.getSaleCashTender(saleId);
    final contact = await localReceiptContact(
      database,
      auth.currentUser,
      currentSale.branchId,
    );

    yield {
      'id': currentSale.id,
      'receiptNumber': currentSale.receiptNumber,
      'hasCustomer': currentSale.customerId != null,
      'linkedCustomerDetailsHidden':
          currentSale.customerId != null && !canViewCustomerDetails,
      'subtotal': currentSale.subtotal,
      'discount': currentSale.discount,
      'tax': currentSale.tax,
      'total': currentSale.total,
      'paymentMethod': currentSale.paymentMethod,
      'paymentReference': currentSale.paymentReference,
      'createdAt': currentSale.createdAt.toIso8601String(),
      'branchName': receiptHeaderName(auth.currentUser),
      if (contact.address.isNotEmpty) 'branchAddress': contact.address,
      if (contact.phone.isNotEmpty) 'branchPhone': contact.phone,
      if (cashTender != null) 'cashGiven': cashTender['cashGiven'],
      if (cashTender != null) 'changeGiven': cashTender['change'],
      'cashierName': auth.currentUser?['name'],
      if (canViewCustomerDetails) 'customerName': customer?['name'],
      if (canViewCustomerDetails) 'customerPhone': customer?['phone'],
      'status': currentSale.status,
      // Keep cloud delivery state visible on the receipt so a device-only
      // sale cannot be mistaken for one already synced across the workspace.
      'isSynced': currentSale.isSynced,
      'voidReason': currentSale.voidReason,
      'voidedAt': currentSale.voidedAt?.toIso8601String(),
      'creditAmountAtSale': _extractCreditAmountAtSale(currentSale),
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
