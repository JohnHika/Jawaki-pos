import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';

/// Date range for reports.
class DateRangeState {
  final DateTime from;
  final DateTime to;
  final String label;
  DateRangeState({required this.from, required this.to, required this.label});
}

class DateRangeNotifier extends StateNotifier<DateRangeState> {
  DateRangeNotifier() : super(_today());

  static DateRangeState _today() {
    final now = DateTime.now();
    return DateRangeState(
      from: DateTime(now.year, now.month, now.day),
      to: DateTime(now.year, now.month, now.day, 23, 59, 59),
      label: 'Today',
    );
  }

  void setToday() => state = _today();

  void setThisWeek() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    state = DateRangeState(
      from: DateTime(monday.year, monday.month, monday.day),
      to: DateTime(now.year, now.month, now.day, 23, 59, 59),
      label: 'This Week',
    );
  }

  void setThisMonth() {
    final now = DateTime.now();
    state = DateRangeState(
      from: DateTime(now.year, now.month, 1),
      to: DateTime(now.year, now.month, now.day, 23, 59, 59),
      label: 'This Month',
    );
  }

  void setCustom(DateTime from, DateTime to) {
    final fmt = DateFormat('d MMM');
    state = DateRangeState(
      from: from,
      to: DateTime(to.year, to.month, to.day, 23, 59, 59),
      label: '${fmt.format(from)} – ${fmt.format(to)}',
    );
  }
}

final dateRangeProvider = StateNotifierProvider<DateRangeNotifier, DateRangeState>(
  (ref) => DateRangeNotifier(),
);

// -- Dashboard summary (real-time) --
final dashboardSummaryProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final db = getIt<AppDatabase>();
  await for (final _ in db.watchTodaysSales()) {
    yield await db.getDashboardSummary();
  }
});

// -- Sales list for date range --
final salesListProvider = FutureProvider<List<PendingSale>>((ref) {
  final range = ref.watch(dateRangeProvider);
  return getIt<AppDatabase>().getSalesByDateRange(range.from, range.to);
});

// -- Payment method breakdown --
final paymentMethodProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  final range = ref.watch(dateRangeProvider);
  return getIt<AppDatabase>().getSalesByPaymentMethod(range.from, range.to);
});

// -- Cashier performance --
final cashierPerformanceProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  final range = ref.watch(dateRangeProvider);
  return getIt<AppDatabase>().getSalesByCashier(range.from, range.to);
});

// -- Category sales --
final categorySalesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  final range = ref.watch(dateRangeProvider);
  return getIt<AppDatabase>().getSalesByCategory(range.from, range.to);
});

// -- Top products --
final topProductsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  final range = ref.watch(dateRangeProvider);
  return getIt<AppDatabase>().getTopProducts(range.from, range.to);
});

// -- Inventory report --
final inventoryReportProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return getIt<AppDatabase>().getInventoryReport();
});
