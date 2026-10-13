import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/reports/domain/analytics_mapping.dart';

void main() {
  test('summary maps server names onto the screen keys', () {
    final s = summaryFromServer({
      'totalSales': 3,
      'totalRevenue': 2090,
      'averageTicket': 696.67,
      'itemsSold': 14,
    });
    expect(s['transactionCount'], 3);
    expect(s['totalRevenue'], 2090.0);
    expect(s['avgTicket'], closeTo(696.67, 0.001));
    expect(s['itemsSold'], 14);
  });

  test('summary tolerates null and strings', () {
    expect(summaryFromServer(null)['totalRevenue'], 0.0);
    expect(summaryFromServer({'totalSales': '5'})['transactionCount'], 5);
  });

  test('hourly rows always cover 24 hours, filling quiet hours with zero', () {
    final rows = hourlyFromServer([
      {'period': '2026-10-13 14:00', 'salesCount': 2, 'revenue': 500},
      {'period': '2026-10-13 9:00', 'salesCount': 1, 'revenue': 120},
      {'period': 'garbage', 'salesCount': 9, 'revenue': 9},
    ], DateTime(2026, 10, 13));
    expect(rows.length, 24);
    expect(rows[14]['transactionCount'], 2);
    expect(rows[14]['totalAmount'], 500.0);
    expect(rows[9]['totalAmount'], 120.0);
    expect(rows[0]['totalAmount'], 0.0);
    expect(rows[14]['hour'], '14');
    expect(DateTime.parse(rows[14]['date'] as String).hour, 14);
  });

  test('hourly rows merge repeated hours (a range spanning several days)', () {
    final rows = hourlyFromServer([
      {'period': '2026-10-12 14:00', 'salesCount': 1, 'revenue': 100},
      {'period': '2026-10-13 14:00', 'salesCount': 2, 'revenue': 250},
    ], DateTime(2026, 10, 13));
    expect(rows[14]['transactionCount'], 3);
    expect(rows[14]['totalAmount'], 350.0);
  });

  test('daily rows keep server order and skip rows without a period', () {
    final rows = dailyFromServer([
      {'period': '2026-10-12', 'salesCount': 3, 'revenue': 1690},
      {'salesCount': 1, 'revenue': 5},
      {'period': '2026-10-13', 'salesCount': 3, 'revenue': 2090},
    ]);
    expect(rows.map((r) => r['date']), ['2026-10-12', '2026-10-13']);
    expect(rows.last['totalAmount'], 2090.0);
  });

  test('top products, payments and categories map names and numbers', () {
    expect(topProductsFromServer([
      {'productId': 'p1', 'productName': 'Oil', 'quantitySold': 3, 'revenue': 990}
    ]).single, {
      'productId': 'p1',
      'productName': 'Oil',
      'totalQty': 3,
      'totalRevenue': 990.0,
    });
    expect(paymentsFromServer([
      {'method': 'MPESA', 'transactionsCount': 2, 'amount': 1910}
    ]).single, {'paymentMethod': 'MPESA', 'count': 2, 'totalAmount': 1910.0});
    expect(categoriesFromServer([
      {'categoryId': 'c1', 'categoryName': 'Beverages', 'itemsSold': 4, 'revenue': 600}
    ]).single['totalQty'], 4);
  });

  test('non-list input gives empty lists, not exceptions', () {
    expect(dailyFromServer(null), isEmpty);
    expect(topProductsFromServer('nope'), isEmpty);
    expect(paymentsFromServer({'a': 1}), isEmpty);
  });

  test('payment summary derives cash / card / digital counts from methods', () {
    final byMethod = paymentsFromServer([
      {'method': 'CASH', 'transactionsCount': 2, 'amount': 300},
      {'method': 'MPESA', 'transactionsCount': 3, 'amount': 900},
      {'method': 'CARD', 'transactionsCount': 1, 'amount': 100},
      {'method': 'CREDIT', 'transactionsCount': 4, 'amount': 400},
    ]);
    final summary = paymentSummaryFromServer(
        {'totalSales': 6, 'totalRevenue': 1300, 'averageTicket': 216.67}, byMethod);
    expect(summary['transactionCount'], 6);
    expect(summary['totalAmount'], 1300.0);
    expect(summary['cashCount'], 2);
    expect(summary['cardCount'], 1);
    // M-Pesa counts as digital; unpaid credit does not.
    expect(summary['digitalCount'], 3);
  });

  test('peak hours are the busiest hours, most traffic first, zeros dropped', () {
    final hourly = hourlyFromServer([
      {'period': '2026-10-13 14:00', 'salesCount': 2, 'revenue': 500},
      {'period': '2026-10-13 16:00', 'salesCount': 5, 'revenue': 300},
      {'period': '2026-10-13 18:00', 'salesCount': 2, 'revenue': 900},
    ], DateTime(2026, 10, 13));
    final peaks = peakHoursFromHourly(hourly, limit: 2);
    expect(peaks.map((p) => p['hour']), [16, 18]); // tie on count -> higher revenue
    expect(peaks.first['transactionCount'], 5);
    expect(peakHoursFromHourly(hourlyFromServer([], DateTime(2026, 10, 13))), isEmpty);
  });
}
