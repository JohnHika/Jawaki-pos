import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../home/domain/shop_guidance.dart';
import '../../../reports/domain/analytics_mapping.dart';
import 'desktop_home_models.dart';

/// Rows from the local SQLite sales table, mapped to what Home draws.
HomeSaleRow homeSaleRowFromSale(PendingSale sale) => HomeSaleRow(
      id: sale.id,
      receiptNumber: sale.receiptNumber,
      createdAt: sale.createdAt,
      paymentMethod: sale.paymentMethod,
      total: sale.total,
      status: sale.status,
      paymentReference: sale.paymentReference,
    );

/// The money split of a list of sales, by the same rules the phone Home uses.
TakingsSplit splitOfSales(Iterable<HomeSaleRow> sales) => splitTakings(
      sales.map(
        (sale) => (
          method: sale.paymentMethod,
          reference: sale.paymentReference,
          total: sale.total,
          status: sale.status,
        ),
      ),
    );

List<HomeProductRow> _productRows(List<Map<String, dynamic>> rows) => [
      for (final row in rows)
        HomeProductRow(
          name: row['productName']?.toString() ?? 'Unknown',
          quantity: (row['totalQty'] as num?)?.toDouble() ?? 0,
          revenue: (row['totalRevenue'] as num?)?.toDouble() ?? 0,
        ),
    ];

/// Best sellers for the [days] days ending today: the shop's own server when
/// signed in to a cloud shop, this computer's records otherwise or if the
/// server does not answer. [stamp] changes whenever a new sale lands so the
/// live Today view refreshes the ranking.
final desktopTopProductsProvider = FutureProvider.autoDispose
    .family<List<HomeProductRow>, ({int days, int stamp})>((ref, key) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final from = today.subtract(Duration(days: key.days - 1));
  final to = today.add(const Duration(days: 1)).subtract(
        const Duration(microseconds: 1),
      );
  return _productRows(await _loadTopProducts(from, to, limit: 8));
});

Future<List<Map<String, dynamic>>> _loadTopProducts(
  DateTime from,
  DateTime to, {
  required int limit,
}) async {
  final auth = getIt<AuthService>();
  if (!auth.isLocalWorkspace) {
    try {
      final iso = DateFormat('yyyy-MM-dd');
      final rows = await getIt<ApiClient>().getTopProductsReport(
        startDate: iso.format(from),
        endDate: iso.format(to),
        branchId: auth.branchId,
        limit: limit,
      );
      return topProductsFromServer(rows);
    } catch (e) {
      if (!kReleaseMode) debugPrint('Home top products: server failed: $e');
    }
  }
  return getIt<AppDatabase>().getTopProducts(from, to, limit: limit);
}

/// The last 7 or 30 days for the desktop Home, keyed by the number of days.
/// Reads the same queries the Analytics screen does (server first for a cloud
/// shop, this computer's records as the fallback).
final desktopHomeRangeProvider =
    FutureProvider.autoDispose.family<HomeRangeData, int>((ref, days) async {
  final db = getIt<AppDatabase>();
  final auth = getIt<AuthService>();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final from = today.subtract(Duration(days: days - 1));
  final to = today.add(const Duration(days: 1)).subtract(
        const Duration(microseconds: 1),
      );

  // Receipts and the money split always come from this computer's records,
  // as they do on the phone Home.
  final localSales = (await db.getSalesByDateRange(from, to))
      .map(homeSaleRowFromSale)
      .toList(growable: false);
  final completed = localSales.where((s) => s.isCompleted).length;

  Map<String, dynamic> summary;
  List<Map<String, dynamic>> trend;
  List<Map<String, dynamic>> top;
  var deviceOnly = auth.isLocalWorkspace;

  Future<void> loadLocal() async {
    summary = await db.getWeeklySummary(from, to);
    trend = await db.getDailySales(from, to);
    top = await db.getTopProducts(from, to, limit: 8);
  }

  // Dart needs these definitely assigned before use.
  summary = const {};
  trend = const [];
  top = const [];
  if (auth.isLocalWorkspace) {
    await loadLocal();
  } else {
    try {
      final api = getIt<ApiClient>();
      final iso = DateFormat('yyyy-MM-dd');
      final results = await Future.wait<Object?>([
        api.getSalesSummaryReport(
          startDate: iso.format(from),
          endDate: iso.format(to),
          branchId: auth.branchId,
        ),
        api.getSalesTrendReport(
          startDate: iso.format(from),
          endDate: iso.format(to),
          branchId: auth.branchId,
          groupBy: 'DAY',
        ),
        api.getTopProductsReport(
          startDate: iso.format(from),
          endDate: iso.format(to),
          branchId: auth.branchId,
          limit: 8,
        ),
      ]);
      summary = summaryFromServer(results[0]);
      trend = dailyFromServer(results[1]);
      top = topProductsFromServer(results[2]);
    } catch (e) {
      if (!kReleaseMode) debugPrint('Home range: server failed, local: $e');
      deviceOnly = true;
      await loadLocal();
    }
  }

  final byDate = <String, ({double amount, int count})>{};
  for (final row in trend) {
    final raw = row['date']?.toString() ?? '';
    if (raw.length < 10) continue;
    final key = raw.substring(0, 10);
    final previous = byDate[key];
    byDate[key] = (
      amount: (previous?.amount ?? 0) +
          ((row['totalAmount'] as num?)?.toDouble() ?? 0),
      count: (previous?.count ?? 0) +
          ((row['transactionCount'] as num?)?.toInt() ?? 0),
    );
  }

  return HomeRangeData(
    revenue: (summary['totalRevenue'] as num?)?.toDouble() ?? 0,
    transactions: (summary['transactionCount'] as num?)?.toInt() ?? completed,
    avgTicket: (summary['avgTicket'] as num?)?.toDouble() ?? 0,
    itemsSold: (summary['itemsSold'] as num?)?.toDouble() ?? 0,
    split: splitOfSales(localSales),
    bars: dailyBars(end: today, days: days, byDate: byDate),
    sales: localSales.take(40).toList(growable: false),
    salesCount: localSales.length,
    topProducts: _productRows(top),
    deviceOnly: deviceOnly,
  );
});
