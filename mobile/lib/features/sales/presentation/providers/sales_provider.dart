import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';

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
      'items': items
          .map((i) => {
                'productName': i.productName,
                'name': i.productName,
                'sku': i.sku,
                'quantity': i.quantity,
                'unitPrice': i.unitPrice,
                'price': i.unitPrice,
                'total': i.total,
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
