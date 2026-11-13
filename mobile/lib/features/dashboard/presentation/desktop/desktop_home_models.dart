import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/format.dart';
import '../../../home/domain/shop_guidance.dart';
import 'desktop_bar_chart.dart';

/// The period the desktop Home shows. Today is live; the others are the last
/// 7 and 30 days counting today.
enum HomeRange {
  today('Today', 'today', 1),
  week('7 days', 'the last 7 days', 7),
  month('30 days', 'the last 30 days', 30);

  const HomeRange(this.label, this.phrase, this.days);

  final String label;

  /// For sentences: "No sales in the last 7 days".
  final String phrase;
  final int days;
}

/// How loud a "Needs attention" row is.
enum HomeAttentionLevel { ok, info, warning, serious }

/// One row of the Needs attention list. Only things the phone Home already
/// raises: shop alerts, recorded payments to match, the licence standing, the
/// end-of-day close and unfinished setup.
@immutable
class HomeAttentionItem {
  const HomeAttentionItem({
    required this.id,
    required this.level,
    required this.title,
    this.detail,
    this.path,
  });

  final String id;
  final HomeAttentionLevel level;
  final String title;
  final String? detail;

  /// Where a click goes. Null rows are information only.
  final String? path;
}

/// A sale as the Home table needs it. Plain data so a test can feed rows.
@immutable
class HomeSaleRow {
  const HomeSaleRow({
    required this.id,
    required this.receiptNumber,
    required this.createdAt,
    required this.paymentMethod,
    required this.total,
    this.status = 'COMPLETED',
    this.paymentReference,
  });

  final String id;
  final String receiptNumber;
  final DateTime createdAt;
  final String paymentMethod;
  final double total;
  final String status;

  /// For split payments: the JSON that says how the sale was divided.
  final String? paymentReference;

  bool get isCompleted => status.toUpperCase() == 'COMPLETED';
}

@immutable
class HomeProductRow {
  const HomeProductRow({
    required this.name,
    required this.quantity,
    required this.revenue,
  });

  final String name;
  final double quantity;
  final double revenue;
}

/// Everything the 7 and 30 day views show, loaded in one go.
@immutable
class HomeRangeData {
  const HomeRangeData({
    required this.revenue,
    required this.transactions,
    required this.avgTicket,
    required this.itemsSold,
    required this.split,
    required this.bars,
    required this.sales,
    required this.salesCount,
    required this.topProducts,
    this.deviceOnly = false,
  });

  final double revenue;
  final int transactions;
  final double avgTicket;
  final double itemsSold;
  final TakingsSplit split;
  final List<DesktopChartBar> bars;
  final List<HomeSaleRow> sales;
  final int salesCount;
  final List<HomeProductRow> topProducts;

  /// True when the shop is on the cloud but the figures had to come from this
  /// computer's own records (offline, or the server did not answer).
  final bool deviceOnly;
}

/// Everything the desktop Home view draws. Built by the routed screen from the
/// same providers the phone Home reads.
@immutable
class DesktopHomeData {
  const DesktopHomeData({
    required this.range,
    this.loading = false,
    this.error,
    this.revenue = 0,
    this.transactions = 0,
    this.avgTicket = 0,
    this.itemsSold = 0,
    this.split = const TakingsSplit(),
    this.cost,
    this.costLoading = false,
    this.canAdjustCost = false,
    this.bars = const [],
    this.sales = const [],
    this.salesCount = 0,
    this.topProducts = const [],
    this.attention = const [],
    this.attentionLoaded = true,
    this.showFigures = true,
    this.showProfit = true,
    this.showRecentSales = true,
    this.deviceOnly = false,
  });

  final HomeRange range;

  /// The figures are still being read.
  final bool loading;

  /// A readable reason the figures could not load.
  final String? error;
  final double revenue;
  final int transactions;
  final double avgTicket;
  final double itemsSold;
  final TakingsSplit split;

  /// What today's stock cost. Null for 7 and 30 days: cost is entered per day.
  final double? cost;
  final bool costLoading;
  final bool canAdjustCost;
  final List<DesktopChartBar> bars;

  /// Newest first. The view shows the first ten.
  final List<HomeSaleRow> sales;

  /// How many sales there are in the period (may exceed [sales].length).
  final int salesCount;
  final List<HomeProductRow> topProducts;
  final List<HomeAttentionItem> attention;

  /// False while the alert feed has not answered yet, so "all clear" is not
  /// claimed before it is known.
  final bool attentionLoaded;
  final bool showFigures;
  final bool showProfit;
  final bool showRecentSales;
  final bool deviceOnly;

  bool get hasSales => transactions > 0 || sales.isNotEmpty;
}

// ── Chart builders ──────────────────────────────────────────────────

String _hourLabel(int hour) {
  if (hour == 0) return '12a';
  if (hour < 12) return '${hour}a';
  if (hour == 12) return '12p';
  return '${hour - 12}p';
}

String _hourName(int hour) {
  if (hour == 0) return '12 am';
  if (hour < 12) return '$hour am';
  if (hour == 12) return '12 pm';
  return '${hour - 12} pm';
}

String _tip(double amount, int count) =>
    '${formatMoney(amount)} · ${count == 1 ? '1 sale' : '$count sales'}';

/// Sales by hour for one day. The axis always spans trading hours (7am to 7pm)
/// and stretches to cover any sale outside them.
List<DesktopChartBar> hourlyBarsFromSales(Iterable<HomeSaleRow> sales) {
  final amount = <int, double>{};
  final count = <int, int>{};
  for (final sale in sales) {
    if (!sale.isCompleted) continue;
    final hour = sale.createdAt.toLocal().hour;
    amount[hour] = (amount[hour] ?? 0) + sale.total;
    count[hour] = (count[hour] ?? 0) + 1;
  }
  var first = 7;
  var last = 19;
  for (final hour in amount.keys) {
    if (hour < first) first = hour;
    if (hour > last) last = hour;
  }
  return [
    for (var hour = first; hour <= last; hour++)
      DesktopChartBar(
        label: _hourLabel(hour),
        value: amount[hour] ?? 0,
        tooltipTitle: '${_hourName(hour)} to ${_hourName((hour + 1) % 24)}',
        tooltipValue: _tip(amount[hour] ?? 0, count[hour] ?? 0),
      ),
  ];
}

/// One bar per day for the [days] days ending on [end]. [byDate] maps
/// `yyyy-MM-dd` to that day's takings; days with no sales are zero bars so the
/// axis stays steady.
List<DesktopChartBar> dailyBars({
  required DateTime end,
  required int days,
  required Map<String, ({double amount, int count})> byDate,
}) {
  final key = DateFormat('yyyy-MM-dd');
  final last = DateTime(end.year, end.month, end.day);
  return [
    for (var i = days - 1; i >= 0; i--)
      () {
        final day = DateTime(last.year, last.month, last.day - i);
        final entry = byDate[key.format(day)];
        return DesktopChartBar(
          label: days <= 7
              ? DateFormat('EEE').format(day)
              : DateFormat('d MMM').format(day),
          value: entry?.amount ?? 0,
          tooltipTitle: DateFormat('EEEE d MMM').format(day),
          tooltipValue: _tip(entry?.amount ?? 0, entry?.count ?? 0),
        );
      }(),
  ];
}
