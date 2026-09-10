import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/format.dart';

class PaymentAnalyticsScreen extends ConsumerStatefulWidget {
  const PaymentAnalyticsScreen({super.key});

  @override
  ConsumerState<PaymentAnalyticsScreen> createState() =>
      _PaymentAnalyticsScreenState();
}

class _PaymentAnalyticsScreenState
    extends ConsumerState<PaymentAnalyticsScreen> {
  Map<String, dynamic> _paymentSummary = {};
  List<Map<String, dynamic>> _paymentMethodBreakdown = [];
  List<Map<String, dynamic>> _transactionTrends = [];
  List<Map<String, dynamic>> _peakHours = [];
  bool _isLoading = true;
  int _selectedPeriod = 0;

  final List<String> _periods = ['Today', 'This Week', 'This Month'];

  @override
  void initState() {
    super.initState();
    _loadPaymentData();
  }

  Future<void> _loadPaymentData() async {
    setState(() => _isLoading = true);

    try {
      final database = getIt<AppDatabase>();
      final now = DateTime.now();

      switch (_selectedPeriod) {
        case 0: // Today
          final startOfDay = DateTime(now.year, now.month, now.day);
          final endOfDay = startOfDay.add(const Duration(days: 1));

          _paymentSummary =
              await database.getPaymentSummary(startOfDay, endOfDay);
          _paymentMethodBreakdown =
              await database.getSalesByPaymentMethod(startOfDay, endOfDay);
          _transactionTrends =
              await database.getHourlySales(startOfDay, endOfDay);
          _peakHours = await database.getPeakHours(startOfDay, endOfDay);

        case 1: // This Week
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          final endOfWeek = startOfWeek.add(const Duration(days: 7));

          _paymentSummary =
              await database.getPaymentSummary(startOfWeek, endOfWeek);
          _paymentMethodBreakdown =
              await database.getSalesByPaymentMethod(startOfWeek, endOfWeek);
          _transactionTrends =
              await database.getDailySales(startOfWeek, endOfWeek);
          _peakHours = await database.getPeakHours(startOfWeek, endOfWeek);

        case 2: // This Month
          final startOfMonth = DateTime(now.year, now.month, 1);
          final endOfMonth = DateTime(now.year, now.month + 1, 1);

          _paymentSummary =
              await database.getPaymentSummary(startOfMonth, endOfMonth);
          _paymentMethodBreakdown =
              await database.getSalesByPaymentMethod(startOfMonth, endOfMonth);
          _transactionTrends =
              await database.getDailySales(startOfMonth, endOfMonth);
          _peakHours = await database.getPeakHours(startOfMonth, endOfMonth);
      }

      setState(() => _isLoading = false);
    } catch (e) {
      if (!kReleaseMode) debugPrint('Payment analytics load error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        showGlassSnackBar(
          context,
          "Couldn't load payment analytics. Check your connection and try again.",
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Payment Analytics',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadPaymentData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: DesignColors.brand))
          : RefreshIndicator(
              onRefresh: _loadPaymentData,
              child: PageContainer(
                withScroll: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Period Selector
                    _buildPeriodSelector(isDark),
                    const SizedBox(height: DesignSpacing.xxl),

                    // Payment Summary Cards
                    _buildPaymentSummaryCards(),
                    const SizedBox(height: DesignSpacing.xxl),

                    if (_hasNoTransactions)
                      // No point repeating the same "no data" empty state
                      // four times in a row (breakdown, trend chart, peak
                      // hours all have nothing to show) — one clear message
                      // covers the whole period instead of a long scroll of
                      // near-identical placeholder cards.
                      const StaggeredItem(
                        itemKey: 'pay-analytics-empty',
                        child: Padding(
                          padding: EdgeInsets.only(top: DesignSpacing.md),
                          child: EmptyState(
                            icon: Icons.query_stats_rounded,
                            title: 'No transactions in this period',
                            subtitle:
                                'Payment breakdowns, trends, and peak hours will appear here once sales come in.',
                          ),
                        ),
                      )
                    else ...[
                      // First-mount entrance: each section fades/rises in
                      // once, staggered (see StaggeredItem); stable keys keep
                      // pull-to-refresh and period switches from replaying.

                      // Payment Method Breakdown
                      StaggeredItem(
                        itemKey: 'pay-analytics-breakdown',
                        child: _buildPaymentMethodBreakdown(isDark),
                      ),
                      const SizedBox(height: DesignSpacing.xxl),

                      // Transaction Trend Chart
                      StaggeredItem(
                        itemKey: 'pay-analytics-trend',
                        index: 1,
                        child: _buildTransactionTrendChart(isDark),
                      ),
                      const SizedBox(height: DesignSpacing.xxl),

                      // Peak Hours Analysis
                      StaggeredItem(
                        itemKey: 'pay-analytics-peak',
                        index: 2,
                        child: _buildPeakHoursAnalysis(isDark),
                      ),
                      const SizedBox(height: DesignSpacing.lg),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  bool get _hasNoTransactions =>
      ((_paymentSummary['transactionCount'] as int?) ?? 0) == 0;

  Widget _buildPeriodSelector(bool isDark) {
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.sm, vertical: DesignSpacing.sm - 2),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusXl - 2),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: _periods.asMap().entries.map((entry) {
            final index = entry.key;
            final period = entry.value;
            final isSelected = _selectedPeriod == index;

            return Expanded(
              // Material+InkWell so the segment paints a ripple; the
              // constraint keeps it at the 44px minimum touch target.
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() => _selectedPeriod = index);
                    _loadPaymentData();
                  },
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  child: AnimatedContainer(
                    duration: DesignAnimation.fast,
                    constraints: const BoxConstraints(
                        minHeight: DesignSpacing.xl + 24),
                    alignment: Alignment.center,
                    padding:
                        const EdgeInsets.symmetric(vertical: DesignSpacing.md),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? DesignColors.accent.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                    ),
                    child: Text(
                      period,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color:
                            isSelected ? DesignColors.accent : secondaryColor,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPaymentSummaryCards() {
    final totalPayments = (_paymentSummary['totalAmount'] ?? 0.0).toDouble();
    final transactionCount = _paymentSummary['transactionCount'] ?? 0;
    final avgPayment = (_paymentSummary['avgPayment'] ?? 0.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.xs - 2),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'Total Payments',
                  value: formatMoney(totalPayments, symbol: 'KSh '),
                  icon: Icons.payments_rounded,
                  color: DesignColors.brand,
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: MetricCard(
                  title: 'Transactions',
                  value: transactionCount.toString(),
                  icon: Icons.receipt_long_rounded,
                  color: DesignColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.md),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'Avg Payment',
                  value: formatMoney(avgPayment, symbol: 'KSh '),
                  icon: Icons.calculate_rounded,
                  color: DesignColors.accent,
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: MetricCard(
                  title: 'Payment Methods',
                  value: _paymentMethodBreakdown.length.toString(),
                  icon: Icons.account_balance_wallet_rounded,
                  color: DesignColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodBreakdown(bool isDark) {
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Container(
      padding: const EdgeInsets.all(DesignSpacing.xl),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payment_rounded,
                  color: DesignColors.info, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Text(
                'Payment Method Breakdown',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.xl),
          if (_paymentMethodBreakdown.isEmpty)
            const EmptyState(
              icon: Icons.payment_rounded,
              title: 'No payment data available',
            )
          else
            ..._paymentMethodBreakdown.map((payment) {
              final method = payment['paymentMethod'] ?? 'Unknown';
              final count = payment['count'] ?? 0;
              final total = payment['totalAmount'] ?? 0.0;
              final color = _getPaymentMethodColor(method);
              final grandTotal = _paymentMethodBreakdown.fold<double>(
                0,
                (sum, p) => sum + ((p['totalAmount'] ?? 0) as double),
              );
              final share =
                  grandTotal > 0 ? (total as double) / grandTotal : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: DesignSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: DesignSpacing.sm + 2),
                        Expanded(
                          child: Text(
                            _formatPaymentMethod(method),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, color: titleColor),
                          ),
                        ),
                        const SizedBox(width: DesignSpacing.md),
                        Flexible(
                          child: Text(
                            '$count transactions',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
                            child: LinearProgressIndicator(
                              value: share,
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                              minHeight: 10,
                              backgroundColor: border,
                            ),
                          ),
                        ),
                        const SizedBox(width: DesignSpacing.md),
                        Text(
                          formatMoney(total, symbol: 'KSh '),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTransactionTrendChart(bool isDark) {
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Container(
      padding: const EdgeInsets.all(DesignSpacing.xl),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded,
                  color: DesignColors.brand, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Text(
                'Transaction Trends',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.xl),
          SizedBox(
            height: 280,
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (int i = 0; i < _transactionTrends.length; i++)
                        FlSpot(
                            i.toDouble(),
                            (_transactionTrends[i]['totalAmount'] ?? 0)
                                .toDouble()),
                    ],
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [DesignColors.brand, DesignColors.brandLight],
                    ),
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          DesignColors.brand.withValues(alpha: 0.3),
                          DesignColors.brand.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
                minX: 0,
                maxX: (_transactionTrends.length - 1).toDouble(),
                minY: 0,
                maxY: (_transactionTrends.isNotEmpty
                            ? (_transactionTrends
                                .map((e) => e['totalAmount'])
                                .reduce((a, b) => a > b ? a : b) as num)
                            : 1000)
                        .toDouble() *
                    1.2,
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (_transactionTrends.isEmpty) return const Text('');
                        final index = value.toInt();
                        if (index >= 0 && index < _transactionTrends.length) {
                          final date = DateTime.parse(
                              _transactionTrends[index]['date'] ?? '');
                          final time = _selectedPeriod == 0
                              ? '${date.hour}:00'
                              : '${date.day}/${date.month}';
                          return Padding(
                            padding: const EdgeInsets.only(top: DesignSpacing.sm),
                            child: Text(
                              time,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: tertiaryColor,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(right: DesignSpacing.sm),
                          child: Text(
                            'KSh ${(value as num).toInt() ~/ 1000}k',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: tertiaryColor,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (_transactionTrends.isNotEmpty
                              ? (_transactionTrends
                                  .map((e) => e['totalAmount'])
                                  .reduce((a, b) => a > b ? a : b) as int)
                              : 1000)
                          .toDouble() /
                      5,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(color: border, strokeWidth: 1);
                  },
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeakHoursAnalysis(bool isDark) {
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Container(
      padding: const EdgeInsets.all(DesignSpacing.xl),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time_rounded,
                  color: DesignColors.accent, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Text(
                'Peak Hours Analysis',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.xl),
          if (_peakHours.isEmpty)
            const EmptyState(
              icon: Icons.access_time_rounded,
              title: 'No peak hours data available',
            )
          else
            ..._peakHours.map((hour) {
              final hourNum = hour['hour'] ?? 0;
              final count = hour['transactionCount'] ?? 0;
              final total = hour['totalAmount'] ?? 0.0;
              final color = _getPeakHourColor(hourNum);
              final totalTraffic = _peakHours.fold<int>(
                0,
                (sum, h) => sum + ((h['transactionCount'] ?? 0) as int),
              );
              final trafficShare =
                  totalTraffic > 0 ? (count / totalTraffic * 100) : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: DesignSpacing.md + 2),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                        border: Border.all(
                          color: color.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$hourNum:00',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                color: secondaryColor,
                                size: 14,
                              ),
                              const SizedBox(width: DesignSpacing.xs),
                              Text(
                                _formatHourLabel(hourNum),
                                style:
                                    Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: titleColor),
                              ),
                            ],
                          ),
                          const SizedBox(height: DesignSpacing.xs),
                          Text(
                            '$count transactions',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: secondaryColor),
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              formatMoney(total, symbol: 'KSh '),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                          const SizedBox(height: DesignSpacing.xs),
                          Text(
                            '${trafficShare.toStringAsFixed(1)}% of traffic',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: secondaryColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Color _getPaymentMethodColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return DesignColors.cash;
      case 'mpesa':
        return DesignColors.mpesa;
      case 'card':
      case 'credit':
        return DesignColors.credit;
      case 'pesapal':
        return DesignColors.pesapal;
      case 'touristtap':
        return DesignColors.touristtap;
      default:
        return DesignColors.brand;
    }
  }

  Color _getPeakHourColor(int hour) {
    if (hour >= 8 && hour <= 10) return DesignColors.success;
    if (hour >= 12 && hour <= 14) return DesignColors.accent;
    if (hour >= 17 && hour <= 19) return DesignColors.brand;
    return DesignColors.info;
  }

  String _formatPaymentMethod(String method) {
    return method.split('_').map((word) {
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String _formatHourLabel(int hour) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : hour;
    return '$displayHour:00 $period';
  }
}
