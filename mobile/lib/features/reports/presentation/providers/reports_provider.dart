import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../domain/analytics_mapping.dart';

/// Date range for reports.
class DateRangeState {
  final DateTime from;
  final DateTime to;
  final String label;
  DateRangeState({required this.from, required this.to, required this.label});

  static final _isoFmt = DateFormat('yyyy-MM-dd');
  String get fromIso => _isoFmt.format(from);
  String get toIso => _isoFmt.format(to);
}

class DateRangeNotifier extends StateNotifier<DateRangeState> {
  DateRangeNotifier() : super(_today());

  static DateRangeState _today() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateRangeState(
      from: today,
      to: today.add(const Duration(days: 1)).subtract(
            const Duration(microseconds: 1),
          ),
      label: 'Today',
    );
  }

  void setToday() => state = _today();

  void setThisWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    state = DateRangeState(
      from: DateTime(monday.year, monday.month, monday.day),
      to: today.add(const Duration(days: 1)).subtract(
            const Duration(microseconds: 1),
          ),
      label: 'This Week',
    );
  }

  void setThisMonth() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    state = DateRangeState(
      from: DateTime(now.year, now.month, 1),
      to: today.add(const Duration(days: 1)).subtract(
            const Duration(microseconds: 1),
          ),
      label: 'This Month',
    );
  }

  void setCustom(DateTime from, DateTime to) {
    final fmt = DateFormat('d MMM');
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day)
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
    state = DateRangeState(
      from: start,
      to: end,
      label: '${fmt.format(start)} – ${fmt.format(end)}',
    );
  }
}

final dateRangeProvider =
    StateNotifierProvider<DateRangeNotifier, DateRangeState>(
  (ref) => DateRangeNotifier(),
);

String? get _branchId => getIt<AuthService>().branchId;

// -- Dashboard summary --
// Sourced from the real backend (/reports/dashboard) instead of local
// SQLite: local-only figures were device-specific and missed any sale made
// or synced on a different device (the same class of gap that hid 77 real
// sales from every screen until the sync bugs behind it were fixed).
// Flattened to the same top-level keys the screen already reads
// (totalRevenue/transactionCount/avgTicket/itemsSold) so reports_screen.dart
// needs no changes for this section.
final dashboardSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  if (getIt<AuthService>().isLocalWorkspace) {
    return getIt<AppDatabase>().getDashboardSummary();
  }
  final data = await getIt<ApiClient>().getDashboard(
      // Dashboard reads today's own range regardless of the reports date
      // picker below it — matches the previous local behavior exactly.
      );
  final sales = (data['sales'] as Map<String, dynamic>?) ?? {};
  return summaryFromServer(sales);
});

// -- Sales list for date range --
// Real backend receipts (GET /sales) — raw JSON maps, not the local Drift
// PendingSale class, since a device only ever writes its own PendingSale
// rows locally.
final salesListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final range = ref.watch(dateRangeProvider);
  if (getIt<AuthService>().isLocalWorkspace) {
    final sales =
        await getIt<AppDatabase>().getSalesByDateRange(range.from, range.to);
    return sales
        .where((sale) => sale.status.toUpperCase() == 'COMPLETED')
        .map((sale) => <String, dynamic>{
              'id': sale.id,
              'receiptNumber': sale.receiptNumber,
              'totalAmount': sale.total,
              'paymentMethod': sale.paymentMethod,
              'createdAt': sale.createdAt.toIso8601String(),
            })
        .toList(growable: false);
  }
  final items = await getIt<ApiClient>()
      .getSales(startDate: range.fromIso, endDate: range.toIso, limit: 500);
  return items.cast<Map<String, dynamic>>();
});

// -- Payment method breakdown --
// Transformed to the field names the existing report sheet already reads
// (paymentMethod/totalAmount/count) so reports_screen.dart's rendering
// code is untouched; only the data source moved from local to backend.
final paymentMethodProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final range = ref.watch(dateRangeProvider);
  if (getIt<AuthService>().isLocalWorkspace) {
    return getIt<AppDatabase>().getSalesByPaymentMethod(range.from, range.to);
  }
  final rows = await getIt<ApiClient>().getPaymentMethodReport(
    startDate: range.fromIso,
    endDate: range.toIso,
    branchId: _branchId,
  );
  return rows
      .cast<Map<String, dynamic>>()
      .map((d) => {
            'paymentMethod': d['method'],
            'totalAmount': d['amount'],
            'count': d['transactionsCount'],
          })
      .toList();
});

// -- Cashier performance --
final cashierPerformanceProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final range = ref.watch(dateRangeProvider);
  if (getIt<AuthService>().isLocalWorkspace) {
    final user = getIt<AuthService>().currentUser ?? const <String, dynamic>{};
    final userId = user['id']?.toString();
    final displayName = [user['firstName'], user['lastName']]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
    final rows =
        await getIt<AppDatabase>().getSalesByCashier(range.from, range.to);
    return rows
        .map((row) => {
              ...row,
              'cashierId': row['cashierId'] == userId
                  ? (displayName.isEmpty ? 'You' : displayName)
                  : 'Staff',
            })
        .toList(growable: false);
  }
  final rows = await getIt<ApiClient>().getCashierPerformanceReport(
    startDate: range.fromIso,
    endDate: range.toIso,
    branchId: _branchId,
  );
  return rows
      .cast<Map<String, dynamic>>()
      .map((d) => {
            // Display the cashier's real name rather than a raw user ID —
            // the report sheet renders this value directly as its title.
            'cashierId': d['name'],
            'count': d['salesCount'],
            'totalAmount': d['revenue'],
          })
      .toList();
});

// -- Category sales --
final categorySalesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final range = ref.watch(dateRangeProvider);
  if (getIt<AuthService>().isLocalWorkspace) {
    return getIt<AppDatabase>().getSalesByCategory(range.from, range.to);
  }
  final rows = await getIt<ApiClient>().getCategorySalesReport(
    startDate: range.fromIso,
    endDate: range.toIso,
    branchId: _branchId,
  );
  return rows
      .cast<Map<String, dynamic>>()
      .map((d) => {
            'categoryName': d['categoryName'],
            'totalQty': d['itemsSold'],
            'totalRevenue': d['revenue'],
          })
      .toList();
});

// -- Top products --
final topProductsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final range = ref.watch(dateRangeProvider);
  if (getIt<AuthService>().isLocalWorkspace) {
    return getIt<AppDatabase>().getTopProducts(range.from, range.to, limit: 20);
  }
  final rows = await getIt<ApiClient>().getTopProductsReport(
    startDate: range.fromIso,
    endDate: range.toIso,
    branchId: _branchId,
    limit: 20,
  );
  return rows
      .cast<Map<String, dynamic>>()
      .map((d) => {
            'productName': d['productName'],
            'totalQty': d['quantitySold'],
            'totalRevenue': d['revenue'],
          })
      .toList();
});

// -- Inventory report --
// This is current stock-on-hand (not date-range-scoped), so it's sourced
// from the live per-product stock endpoint rather than the aggregate-only
// /reports/inventory summary (which has no per-product breakdown).
final inventoryReportProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final branchId = _branchId;
  if (getIt<AuthService>().isLocalWorkspace) {
    return getIt<AppDatabase>().getInventoryReport();
  }
  if (branchId == null) return [];
  final rows = await getIt<ApiClient>().getStock(branchId: branchId);
  final mapped = rows
      .cast<Map<String, dynamic>>()
      .map((d) => {
            'id': d['productId'],
            'name': d['productName'],
            'sku': d['sku'],
            'stock': d['quantity'],
            'minStock': d['minStock'],
            'categoryName': '',
          })
      .toList();
  mapped.sort((a, b) => (a['stock'] as num).compareTo(b['stock'] as num));
  return mapped;
});
