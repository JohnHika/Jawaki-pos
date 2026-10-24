/// Maps the server's report JSON onto the row shapes the Analytics screens were
/// written against (they were built on the device's own SQLite queries, so a
/// phone that hadn't recorded the sales itself showed empty charts).
///
/// All functions are pure and tolerant of missing/odd fields: a bad row is
/// skipped or zeroed rather than throwing, since these feed charts.
library;

/// Tolerates a Prisma `{id: n}` count wrapper as well as a plain number.
num _num(Object? v) => v is num
    ? v
    : v is Map
        ? _num(v['id'])
        : num.tryParse(v?.toString() ?? '') ?? 0;

List<Map<String, dynamic>> _rows(Object? v) => v is List
    ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : const [];

/// `{totalSales,totalRevenue,averageTicket,itemsSold}` -> dashboard summary keys.
Map<String, dynamic> summaryFromServer(Object? sales) {
  final m = sales is Map ? sales : const {};
  return {
    'transactionCount': _num(m['totalSales']).toInt(),
    'totalRevenue': _num(m['totalRevenue']).toDouble(),
    'avgTicket': _num(m['averageTicket']).toDouble(),
    'itemsSold': _num(m['itemsSold']).toDouble(),
  };
}

/// Server hourly trend (`period: "2026-10-13 14:00"`) -> rows keyed by the hour.
/// Hours with no sales are filled with zero so the chart keeps a stable axis.
List<Map<String, dynamic>> hourlyFromServer(Object? trend, DateTime day) {
  final byHour = <int, Map<String, num>>{};
  for (final row in _rows(trend)) {
    final period = row['period']?.toString() ?? '';
    final hour = int.tryParse(
        RegExp(r'(\d{1,2}):00$').firstMatch(period)?.group(1) ?? '');
    if (hour == null || hour < 0 || hour > 23) continue;
    final slot = byHour.putIfAbsent(hour, () => {'count': 0, 'amount': 0});
    slot['count'] = slot['count']! + _num(row['salesCount']);
    slot['amount'] = slot['amount']! + _num(row['revenue']);
  }
  final base = DateTime(day.year, day.month, day.day);
  return [
    for (var h = 0; h < 24; h++)
      {
        'hour': h.toString().padLeft(2, '0'),
        'transactionCount': (byHour[h]?['count'] ?? 0).toInt(),
        'totalAmount': (byHour[h]?['amount'] ?? 0).toDouble(),
        'date': base.add(Duration(hours: h)).toIso8601String(),
      },
  ];
}

/// Server daily trend (`period: "2026-10-13"`) -> rows keyed by `date`.
List<Map<String, dynamic>> dailyFromServer(Object? trend) => [
      for (final row in _rows(trend))
        if ((row['period']?.toString() ?? '').isNotEmpty)
          {
            'date': row['period'].toString(),
            'transactionCount': _num(row['salesCount']).toInt(),
            'totalAmount': _num(row['revenue']).toDouble(),
          },
    ];

List<Map<String, dynamic>> topProductsFromServer(Object? rows) => [
      for (final r in _rows(rows))
        {
          'productId': r['productId']?.toString() ?? '',
          'productName': r['productName']?.toString() ?? 'Unknown',
          'totalQty': _num(r['quantitySold']).toDouble(),
          'totalRevenue': _num(r['revenue']).toDouble(),
        },
    ];

List<Map<String, dynamic>> paymentsFromServer(Object? rows) => [
      for (final r in _rows(rows))
        {
          'paymentMethod': r['method']?.toString() ?? 'UNKNOWN',
          'count': _num(r['transactionsCount']).toInt(),
          'totalAmount': _num(r['amount']).toDouble(),
        },
    ];

List<Map<String, dynamic>> categoriesFromServer(Object? rows) => [
      for (final r in _rows(rows))
        {
          'categoryId': r['categoryId']?.toString() ?? '',
          'categoryName': r['categoryName']?.toString() ?? 'Uncategorised',
          'totalQty': _num(r['itemsSold']).toDouble(),
          'totalRevenue': _num(r['revenue']).toDouble(),
        },
    ];

/// Payment summary from the server's totals: same keys as the local query
/// (the cash/card/digital counts are derived from the method breakdown).
Map<String, dynamic> paymentSummaryFromServer(
  Object? sales,
  List<Map<String, dynamic>> byMethod,
) {
  final base = summaryFromServer(sales);
  int countOf(bool Function(String) test) => byMethod
      .where((m) => test((m['paymentMethod'] as String).toUpperCase()))
      .fold<int>(0, (sum, m) => sum + (m['count'] as int));
  return {
    'transactionCount': base['transactionCount'],
    'totalAmount': base['totalRevenue'],
    'avgPayment': base['avgTicket'],
    'cashCount': countOf((m) => m == 'CASH'),
    'cardCount': countOf((m) => m == 'CARD'),
    'digitalCount': countOf((m) => m != 'CASH' && m != 'CARD' && m != 'CREDIT'),
  };
}

/// Busiest hours (up to [limit]) from 24 hourly rows, most traffic first.
/// Hours with no sales are left out.
List<Map<String, dynamic>> peakHoursFromHourly(
  List<Map<String, dynamic>> hourly, {
  int limit = 5,
}) {
  final rows = [
    for (final r in hourly)
      if (((r['transactionCount'] as num?) ?? 0) > 0)
        {
          'hour': int.tryParse(r['hour']?.toString() ?? '') ?? 0,
          'transactionCount': (r['transactionCount'] as num).toInt(),
          'totalAmount': ((r['totalAmount'] as num?) ?? 0).toDouble(),
        },
  ]..sort((a, b) {
      final byCount = (b['transactionCount'] as int)
          .compareTo(a['transactionCount'] as int);
      return byCount != 0
          ? byCount
          : (b['totalAmount'] as double).compareTo(a['totalAmount'] as double);
    });
  return rows.take(limit).toList();
}

/// Seven most recent days of units sold, ending [today], one row per day with
/// zeros for days that have no sales (so the chart always has seven bars).
List<Map<String, dynamic>> weeklyVelocityFromServer(
    Object? trend, DateTime today) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final byDate = <String, double>{};
  for (final r in _rows(trend)) {
    final key = (r['period']?.toString() ?? '');
    if (key.length >= 10) {
      final day = key.substring(0, 10);
      byDate[day] = (byDate[day] ?? 0) + _num(r['itemsSold']).toDouble();
    }
  }
  final start = DateTime(today.year, today.month, today.day)
      .subtract(const Duration(days: 6));
  return [
    for (var i = 0; i < 7; i++)
      () {
        final d = start.add(Duration(days: i));
        final key =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        return {
          'day': names[d.weekday - 1],
          'itemsSold': byDate[key] ?? 0,
          'date': key
        };
      }(),
  ];
}

/// The [limit] products that sold least from a full ranking (lowest units first).
List<Map<String, dynamic>> slowestFromRanking(
  List<Map<String, dynamic>> ranking, {
  int limit = 10,
}) =>
    ([...ranking]..sort((a, b) => ((a['totalQty'] as num?) ?? 0)
            .compareTo((b['totalQty'] as num?) ?? 0)))
        .take(limit)
        .toList();
