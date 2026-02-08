import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';

// Receipt provider
final receiptProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, saleId) async {
  final apiClient = getIt<ApiClient>();
  return await apiClient.getReceipt(saleId);
});

// Daily summary provider
final dailySummaryProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final apiClient = getIt<ApiClient>();
  return await apiClient.getDailySummary();
});

// Sales history provider
final salesHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final apiClient = getIt<ApiClient>();
  return (await apiClient.getSales()).cast<Map<String, dynamic>>();
});
