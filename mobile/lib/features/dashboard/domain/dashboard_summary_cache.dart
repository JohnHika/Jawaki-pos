import 'package:intl/intl.dart';

import '../../../core/cache/swr_cache.dart';

/// The last "Sold today" figures, kept on the phone so Home shows real numbers
/// the instant it opens instead of zeros or a spinner while the shop's totals
/// load.
///
/// A copy is only ever shown for the same shop, branch and calendar day it was
/// saved on, so yesterday's takings never pass for today's. The fresh figures
/// replace it as soon as they arrive.
class DashboardSummaryCache {
  DashboardSummaryCache({SwrCache? cache})
      : _cache = cache ??
            SwrCache(
              namespace: 'dashboard-summary',
              hardTtl: const Duration(days: 1),
            );

  final SwrCache _cache;

  static const _fields = [
    'totalRevenue',
    'transactionCount',
    'avgTicket',
    'itemsSold',
  ];

  /// One key per shop, branch and day.
  static String keyFor({
    required String? tenantId,
    required String? branchId,
    required DateTime day,
  }) =>
      '${tenantId ?? '-'}:${branchId ?? '-'}:${DateFormat('yyyy-MM-dd').format(day)}';

  /// The saved figures, or null when there are none for this key.
  Future<Map<String, dynamic>?> read(String key) async {
    try {
      final entry = await _cache.read(key);
      final json = entry?.json;
      if (json is! Map) return null;
      return {
        for (final field in _fields)
          if (json[field] is num) field: json[field],
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> summary) async {
    try {
      await _cache.write(key, {
        for (final field in _fields)
          if (summary[field] is num) field: summary[field],
      });
    } catch (_) {
      // Keeping a copy is a convenience; Home works without it.
    }
  }
}
