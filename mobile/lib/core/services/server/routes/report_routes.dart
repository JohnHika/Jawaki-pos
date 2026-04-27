import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;
import '../../../database/app_database.dart';
import '../middleware.dart';

/// Report routes for phone server mode.
class ReportRoutes {
  final AppDatabase _db;

  ReportRoutes(this._db);

  void addRoutes(Router r) {
    r.get('/api/v1/reports/dashboard', _handleDashboard);
    r.get('/api/v1/reports/profit-loss/<branchId>/<date>', _handleProfitLoss);
  }

  /// GET /api/v1/reports/dashboard?period=&branchId=
  Future<shelf.Response> _handleDashboard(shelf.Request request) async {
    final params = request.url.queryParameters;
    final period = params['period'] ?? 'daily';

    final now = DateTime.now();
    DateTime from;
    DateTime to = now;

    switch (period) {
      case 'weekly':
        from = now.subtract(const Duration(days: 7));
        break;
      case 'monthly':
        from = now.subtract(const Duration(days: 30));
        break;
      case 'yearly':
        from = now.subtract(const Duration(days: 365));
        break;
      case 'daily':
      default:
        from = DateTime(now.year, now.month, now.day);
        to = from.add(const Duration(days: 1));
        break;
    }

    final summary = await _db.getDashboardSummary();
    final paymentSummary = await _db.getPaymentSummary(from, to);
    final topProducts = await _db.getTopProducts(from, to);

    return shelf.Response.ok(
      jsonEncode({
        'summary': summary,
        'paymentSummary': paymentSummary,
        'topProducts': topProducts,
        'period': period,
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/v1/reports/profit-loss/<branchId>/<date>
  Future<shelf.Response> _handleProfitLoss(shelf.Request request, String branchId, String date) async {
    final dateObj = DateTime.tryParse(date) ?? DateTime.now();
    final from = DateTime(dateObj.year, dateObj.month, dateObj.day);
    final to = from.add(const Duration(days: 1));

    final sales = await _db.getSalesByDateRange(from, to);
    final totalRevenue = sales.fold<double>(0, (sum, s) => sum + s.total);

    // Cost of goods sold from inventory report
    final inventory = await _db.getInventoryReport();
    final totalCost = inventory.fold<double>(0, (sum, item) {
      final costPrice = (item['costPrice'] as num?)?.toDouble() ?? 0;
      final stock = (item['stock'] as num?)?.toInt() ?? 0;
      return sum + (costPrice * stock);
    });

    // Expenses (use a rough estimate for now)
    final totalExpenses = totalRevenue * 0.3; // 30% estimated overhead

    return shelf.Response.ok(
      jsonEncode({
        'date': date,
        'branchId': branchId,
        'revenue': totalRevenue,
        'costOfGoods': totalCost,
        'expenses': totalExpenses,
        'grossProfit': totalRevenue - totalCost,
        'netProfit': totalRevenue - totalCost - totalExpenses,
      }),
      headers: {'content-type': 'application/json'},
    );
  }
}
