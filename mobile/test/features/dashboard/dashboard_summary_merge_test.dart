import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/dashboard/presentation/screens/dashboard_screen.dart';

void main() {
  group('mergeDashboardSummary', () {
    const empty = {
      'transactionCount': 0,
      'totalRevenue': 0.0,
      'avgTicket': 0.0,
      'itemsSold': 0,
    };

    test('a fresh device shows the shop\'s takings from the server', () {
      final merged = mergeDashboardSummary(empty, {
        'totalSales': 5,
        'totalRevenue': 2210,
        'averageTicket': 442,
        'itemsSold': 16,
      });
      expect(merged['transactionCount'], 5);
      expect(merged['totalRevenue'], 2210);
      expect(merged['avgTicket'], 442);
      expect(merged['itemsSold'], 16);
    });

    test('an unsynced local sale is never hidden by a lagging server', () {
      final merged = mergeDashboardSummary({
        'transactionCount': 6,
        'totalRevenue': 2500.0,
        'avgTicket': 416.0,
        'itemsSold': 18,
      }, {
        'totalSales': 5,
        'totalRevenue': 2210,
        'averageTicket': 442,
        'itemsSold': 16,
      });
      expect(merged['transactionCount'], 6);
      expect(merged['totalRevenue'], 2500.0);
    });

    test('missing server fields fall back to the local figures', () {
      final merged = mergeDashboardSummary({
        'transactionCount': 2,
        'totalRevenue': 300.0,
        'avgTicket': 150.0,
        'itemsSold': 4,
      }, const {});
      expect(merged['transactionCount'], 2);
      expect(merged['itemsSold'], 4);
    });
  });
}
