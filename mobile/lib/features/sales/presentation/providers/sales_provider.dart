import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';

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
          .where((t) => (t['method'] ?? '').toString().toUpperCase() == 'CREDIT')
          .fold<double>(0, (sum, t) => sum + ((t['amount'] as num?)?.toDouble() ?? 0));
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

// Receipt provider — reads the local sale first. The sale, its items, and
// the customer all already exist locally the instant a sale is completed
// (written by PaymentNotifier), so the receipt loads instantly and offline
// instead of depending on a server round-trip that hasn't happened yet (or
// hitting the wrong endpoint with a local id). Falls back to the remote
// receipt only if the local row is genuinely missing.
final receiptProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, saleId) async {
  final database = getIt<AppDatabase>();
  final sale = await database.getPendingSaleById(saleId);

  if (sale != null) {
    final items = await database.getSaleItems(saleId);
    final auth = getIt<AuthService>();

    Map<String, dynamic>? customer;
    if (sale.customerId != null) {
      customer = await database.getCustomer(sale.customerId!);
    }

    return {
      'id': sale.id,
      'receiptNumber': sale.receiptNumber,
      'subtotal': sale.subtotal,
      'discount': sale.discount,
      'tax': sale.tax,
      'total': sale.total,
      'paymentMethod': sale.paymentMethod,
      'paymentReference': sale.paymentReference,
      'createdAt': sale.createdAt.toIso8601String(),
      'cashierName': auth.currentUser?['name'],
      'customerName': customer?['name'],
      'customerPhone': customer?['phone'],
      'status': sale.status,
      'voidReason': sale.voidReason,
      'voidedAt': sale.voidedAt?.toIso8601String(),
      // Amount still owed on a credit sale, if the payment metadata carries
      // it (shown as "Balance owed" on the receipt).
      'outstandingBalance': _extractOutstanding(sale),
      // Split-payment breakdown (method + amount per tender), or null.
      'paymentTenders': _extractTenders(sale),
      'items': items
          .map((i) => {
                'productName': i.productName,
                'name': i.productName,
                'sku': i.sku,
                'quantity': i.quantity,
                'unitPrice': i.unitPrice,
                'price': i.unitPrice,
                'total': i.total,
                'unit': i.unit,
                'quantityPerUnit': i.quantityPerUnit,
              })
          .toList(),
    };
  }

  // Local row missing (e.g. viewing an old sale from another device) —
  // fall back to the server. getReceipt is keyed on receiptNumber, so this
  // only succeeds if saleId happens to be a receipt number.
  final apiClient = getIt<ApiClient>();
  return await apiClient.getReceipt(saleId);
});

// Daily summary provider
final dailySummaryProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final apiClient = getIt<ApiClient>();
  return await apiClient.getDailySummary();
});

// Daily Profit & Loss provider (with expense integration)
final dailyProfitLossProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, branchId) async {
  final apiClient = getIt<ApiClient>();
  final today = DateTime.now().toIso8601String().split('T').first;
  return await apiClient.getDailyProfitLoss(branchId, today);
});

// Sales history provider
final salesHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final apiClient = getIt<ApiClient>();
  return (await apiClient.getSales()).cast<Map<String, dynamic>>();
});
