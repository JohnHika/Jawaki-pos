import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';

class AnalyticsDashboardScreen extends ConsumerStatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  ConsumerState<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState
    extends ConsumerState<AnalyticsDashboardScreen> {
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _hourlySales = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _salesByPayment = [];
  List<Map<String, dynamic>> _salesByCategory = [];
  bool _isLoading = true;
  int _selectedPeriod = 0; // 0: Today, 1: Week, 2: Month

  final List<String> _periods = ['Today', 'This Week', 'This Month'];

  @override
  void initState() {
    super.initState();
    _loadAnalyticsData();
  }

  Future<void> _loadAnalyticsData() async {
    setState(() => _isLoading = true);

    try {
      final database = getIt<AppDatabase>();
      final now = DateTime.now();

      switch (_selectedPeriod) {
        case 0: // Today
          final startOfDay = DateTime(now.year, now.month, now.day);
          final endOfDay = startOfDay.add(const Duration(days: 1));

          _summary = await database.getDashboardSummary();
          _hourlySales = await database.getHourlySales(startOfDay, endOfDay);
          _topProducts =
              await database.getTopProducts(startOfDay, endOfDay, limit: 10);
          _salesByPayment =
              await database.getSalesByPaymentMethod(startOfDay, endOfDay);
          _salesByCategory =
              await database.getSalesByCategory(startOfDay, endOfDay);

        case 1: // This Week
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          final endOfWeek = startOfWeek.add(const Duration(days: 7));

          _summary = await database.getWeeklySummary(startOfWeek, endOfWeek);
          _hourlySales = await database.getDailySales(startOfWeek, endOfWeek);
          _topProducts =
              await database.getTopProducts(startOfWeek, endOfWeek, limit: 10);
          _salesByPayment =
              await database.getSalesByPaymentMethod(startOfWeek, endOfWeek);
          _salesByCategory =
              await database.getSalesByCategory(startOfWeek, endOfWeek);

        case 2: // This Month
          final startOfMonth = DateTime(now.year, now.month, 1);
          final endOfMonth = DateTime(now.year, now.month + 1, 0);

          _summary = await database.getMonthlySummary(startOfMonth, endOfMonth);
          _hourlySales = await database.getDailySales(startOfMonth, endOfMonth);
          _topProducts = await database.getTopProducts(startOfMonth, endOfMonth,
              limit: 10);
          _salesByPayment =
              await database.getSalesByPaymentMethod(startOfMonth, endOfMonth);
          _salesByCategory =
              await database.getSalesByCategory(startOfMonth, endOfMonth);
      }

      setState(() => _isLoading = false);
    } catch (e) {
      if (!kReleaseMode) debugPrint('Analytics load error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        showGlassSnackBar(
          context,
          "Couldn't load analytics. Check your connection and try again.",
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
        title: 'Analytics',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAnalyticsData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: DesignColors.brand))
          : RefreshIndicator(
              onRefresh: _loadAnalyticsData,
              child: PageContainer(
                withScroll: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // First-mount entrance: each section fades/rises in
                    // once, staggered (see StaggeredItem); stable keys keep
                    // pull-to-refresh and period switches from replaying.

                    // Date Period Selector
                    _buildPeriodSelector(isDark),
                    const SizedBox(height: DesignSpacing.xxl),

                    // Summary Cards with MetricCard
                    StaggeredItem(
                      itemKey: 'analytics-summary',
                      child: _buildSummaryCards(),
                    ),
                    const SizedBox(height: DesignSpacing.xxl),

                    // Main Sales Chart
                    StaggeredItem(
                      itemKey: 'analytics-trend',
                      index: 1,
                      child: _buildSalesTrendChart(isDark),
                    ),
                    const SizedBox(height: DesignSpacing.xxl),

                    // Top Products & Payment Methods — side-by-side on
                    // tablets, stacked on phones so the payment panel never
                    // becomes a clipped sliver.
                    StaggeredItem(
                      itemKey: 'analytics-top-payments',
                      index: 2,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final topProducts = _buildTopProducts(isDark);
                          final payments = _buildPaymentMethods(isDark);
                          if (constraints.maxWidth < 680) {
                            return Column(
                              children: [
                                topProducts,
                                const SizedBox(height: DesignSpacing.xxl),
                                payments,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 2, child: topProducts),
                              const SizedBox(width: DesignSpacing.lg),
                              Expanded(child: payments),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.xxl),

                    // Category Breakdown
                    StaggeredItem(
                      itemKey: 'analytics-category',
                      index: 3,
                      child: _buildCategoryBreakdown(isDark),
                    ),
                    const SizedBox(height: DesignSpacing.xxl),

                    // Hourly Distribution
                    StaggeredItem(
                      itemKey: 'analytics-hourly',
                      index: 4,
                      child: _buildHourlyDistribution(isDark),
                    ),
                    const SizedBox(height: DesignSpacing.lg),
                  ],
                ),
              ),
            ),
    );
  }

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
                    _loadAnalyticsData();
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

  Widget _buildSummaryCards() {
    final revenue = (_summary['totalRevenue'] ?? 0.0).toDouble();
    final transactions = _summary['transactionCount'] ?? 0;
    final avgTicket = (_summary['avgTicket'] ?? 0.0).toDouble();
    final itemsSold = _summary['itemsSold'] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.xs - 2),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'Total Revenue',
                  value: 'KSh ${revenue.toStringAsFixed(0)}',
                  icon: Icons.attach_money_rounded,
                  color: DesignColors.success,
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: MetricCard(
                  title: 'Transactions',
                  value: transactions.toString(),
                  icon: Icons.receipt_long_rounded,
                  color: DesignColors.brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.md),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'Avg Ticket',
                  value: 'KSh ${avgTicket.toStringAsFixed(0)}',
                  icon: Icons.trending_up_rounded,
                  color: DesignColors.accent,
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: MetricCard(
                  title: 'Items Sold',
                  value: itemsSold.toString(),
                  icon: Icons.shopping_bag_rounded,
                  color: DesignColors.info,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTrendChart(bool isDark) {
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
              const Icon(Icons.bar_chart_rounded,
                  color: DesignColors.brand, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Text(
                'Sales Trend',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.xl),
          SizedBox(
            height: 250,
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (int i = 0; i < _hourlySales.length; i++)
                        FlSpot(i.toDouble(),
                            (_hourlySales[i]['totalAmount'] ?? 0).toDouble()),
                    ],
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [DesignColors.brand, DesignColors.brandLight],
                    ),
                    barWidth: 3,
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
                maxX: (_hourlySales.length - 1).toDouble(),
                minY: 0,
                maxY: (_hourlySales.isNotEmpty
                            ? (_hourlySales
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
                        if (_hourlySales.isEmpty) return const Text('');
                        final index = value.toInt();
                        if (index >= 0 && index < _hourlySales.length) {
                          final date =
                              DateTime.parse(_hourlySales[index]['date'] ?? '');
                          final time = _selectedPeriod == 0
                              ? '${date.hour}:00'
                              : '${date.day}/${date.month}';
                          return Padding(
                            padding: const EdgeInsets.only(top: DesignSpacing.sm),
                            child: Text(
                              time,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: tertiaryColor,
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
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
                  horizontalInterval: (_hourlySales.isNotEmpty
                              ? (_hourlySales
                                  .map((e) => e['totalAmount'])
                                  .reduce((a, b) => a > b ? a : b) as num)
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

  Widget _buildTopProducts(bool isDark) {
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
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
              const Icon(Icons.star_rounded,
                  color: DesignColors.info, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Text(
                'Top Products',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.xl),
          if (_topProducts.isEmpty)
            const EmptyState(
              icon: Icons.shopping_bag_rounded,
              title: 'No sales data available',
            )
          else
            ..._topProducts.asMap().entries.map((entry) {
              final index = entry.key;
              final product = entry.value;
              final revenue = (product['totalRevenue'] ?? 0).toDouble();

              return Padding(
                padding: const EdgeInsets.only(bottom: DesignSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: index == 0
                            ? Colors.amber.withValues(alpha: 0.2)
                            : index == 1
                                ? Colors.grey.withValues(alpha: 0.2)
                                : index == 2
                                    ? Colors.orange.withValues(alpha: 0.2)
                                    : (isDark
                                        ? DesignColors.darkSurfaceElevated
                                        : DesignColors.surfaceSubtle),
                        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd - 2),
                        border: Border.all(
                          color: (index == 0
                                  ? Colors.amber
                                  : index == 1
                                      ? Colors.grey
                                      : index == 2
                                          ? Colors.orange
                                          : tertiaryColor)
                              .withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '#${index + 1}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: index == 0
                              ? Colors.amber[700]
                              : index == 1
                              ? Colors.grey[700]
                              : index == 2
                              ? Colors.orange[700]
                              : tertiaryColor,
                              fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignSpacing.md + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product['productName'] ?? 'Unknown',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: DesignSpacing.xs),
                          Text(
                            '${product['totalQty']} units sold',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'KSh ${revenue.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: DesignColors.success,
                          ),
                        ),
                        const SizedBox(height: DesignSpacing.xs),
                        Text(
                          '${(revenue / (_summary['totalRevenue'] ?? 1) * 100).toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: secondaryColor,
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

  Widget _buildPaymentMethods(bool isDark) {
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
              const Icon(Icons.payment_rounded,
                  color: DesignColors.info, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Text(
                'Payments',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.xl),
          if (_salesByPayment.isEmpty)
            const EmptyState(
              icon: Icons.payment_rounded,
              title: 'No payment data',
            )
          else
            ..._salesByPayment.map((payment) {
              final method = payment['paymentMethod'] ?? 'Unknown';
              final count = payment['count'] ?? 0;
              final total =
                  (payment['totalAmount'] as num?)?.toDouble() ?? 0;
              final color = _getPaymentMethodColor(method);
              final totalBreakdown = _salesByPayment.isNotEmpty
                  ? _salesByPayment.fold<double>(
                      0,
                      (sum, p) =>
                          sum + ((p['totalAmount'] as num?)?.toDouble() ?? 0),
                    )
                  : 1.0;
              final percentage = totalBreakdown;
              final percent = (total / percentage * 100).toStringAsFixed(1);

              return Padding(
                padding: const EdgeInsets.only(bottom: DesignSpacing.md + 2),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                        border: Border.all(
                          color: color.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          _getPaymentMethodIcon(method),
                          color: color,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignSpacing.md + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatPaymentMethod(method),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                            ),
                          ),
                          const SizedBox(height: DesignSpacing.xs),
                          Text(
                            '$count transactions',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'KSh ${total.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: titleColor,
                          ),
                        ),
                        const SizedBox(height: DesignSpacing.xs),
                        Text(
                          '$percent%',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: secondaryColor,
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

  Widget _buildCategoryBreakdown(bool isDark) {
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
              const Icon(Icons.category_rounded,
                  color: DesignColors.info, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Text(
                'Sales by Category',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.xl),
          if (_salesByCategory.isEmpty)
            const EmptyState(
              icon: Icons.category_rounded,
              title: 'No category data available',
            )
          else
            ..._salesByCategory.map((category) {
              final catName = category['categoryName'] ?? 'Unknown';
              final total =
                  (category['totalRevenue'] as num?)?.toDouble() ?? 0;
              final color = _getCategoryColor(catName);
              final grandTotal = _salesByCategory.fold<double>(
                0,
                (sum, c) =>
                    sum + ((c['totalRevenue'] as num?)?.toDouble() ?? 0),
              );
              final share = grandTotal > 0 ? total / grandTotal : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: DesignSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: DesignSpacing.sm),
                        Expanded(
                          child: Text(
                            catName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: titleColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: DesignSpacing.md),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              'KSh ${total.toStringAsFixed(0)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: titleColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignSpacing.sm - 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(DesignSpacing.radiusSm - 2),
                      child: LinearProgressIndicator(
                        value: share,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 8,
                        backgroundColor: border,
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

  Widget _buildHourlyDistribution(bool isDark) {
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
              const Icon(Icons.access_time_rounded,
                  color: DesignColors.accent, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Text(
                'Hourly Sales Distribution',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.xl),
          if (_hourlySales.isEmpty)
            const EmptyState(
              icon: Icons.access_time_rounded,
              title: 'No hourly data available',
            )
          else
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (_hourlySales.isNotEmpty
                              ? _hourlySales.fold<double>(
                                  0,
                                  (sum, e) {
                                    final amount =
                                        (e['totalAmount'] as num?)?.toDouble() ?? 0;
                                    return amount > sum ? amount : sum;
                                  })
                              : 1000)
                          .toDouble() *
                      1.2,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipPadding: const EdgeInsets.all(DesignSpacing.md),
                      tooltipMargin: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          'KSh ${(rod.toY).toStringAsFixed(0)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (_hourlySales.isEmpty) return const Text('');
                          final index = value.toInt();
                          if (index >= 0 && index < _hourlySales.length) {
                            final date = DateTime.parse(
                                _hourlySales[index]['date'] ?? '');
                            final hour = date.hour;
                            final time = hour >= 12
                                ? '${hour > 12 ? hour - 12 : 12} PM'
                                : '$hour AM';
                            return Padding(
                              padding: const EdgeInsets.only(top: DesignSpacing.sm),
                              child: Text(
                                time,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: tertiaryColor,
                                ),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
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
                    horizontalInterval: (_hourlySales.isNotEmpty
                                ? (_hourlySales
                                    .map((e) => e['totalAmount'])
                                    .reduce((a, b) => a > b ? a : b) as num)
                                : 1000)
                            .toDouble() /
                        5,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(color: border, strokeWidth: 1);
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (int i = 0; i < _hourlySales.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: (_hourlySales[i]['totalAmount'] ?? 0)
                                .toDouble(),
                            gradient: const LinearGradient(
                              colors: [
                                DesignColors.brand,
                                DesignColors.brandLight
                              ],
                            ),
                            width: 14,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
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

  IconData _getPaymentMethodIcon(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Icons.money_rounded;
      case 'mpesa':
        return Icons.phone_android_rounded;
      case 'card':
      case 'credit':
        return Icons.credit_card_rounded;
      case 'pesapal':
        return Icons.account_balance_rounded;
      case 'touristtap':
        return Icons.nfc_rounded;
      default:
        return Icons.payment_rounded;
    }
  }

  String _formatPaymentMethod(String method) {
    return method.split('_').map((word) {
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'electronics':
        return DesignColors.info;
      case 'clothing':
        return DesignColors.credit;
      case 'food':
        return DesignColors.success;
      case 'services':
        return DesignColors.accent;
      default:
        return DesignColors.brand;
    }
  }
}
