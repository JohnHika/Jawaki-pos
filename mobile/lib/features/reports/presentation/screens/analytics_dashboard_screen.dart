import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/theme/design_system.dart';
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
      print('Analytics load error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAnalyticsData,
              child: PageContainer(
                withScroll: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date Period Selector
                    _buildPeriodSelector(),
                    const SizedBox(height: 24),

                    // Summary Cards with MetricCard
                    _buildSummaryCards(),
                    const SizedBox(height: 24),

                    // Main Sales Chart
                    _buildSalesTrendChart(),
                    const SizedBox(height: 24),

                    // Top Products & Payment Methods Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildTopProducts()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildPaymentMethods()),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Category Breakdown
                    _buildCategoryBreakdown(),
                    const SizedBox(height: 24),

                    // Hourly Distribution
                    _buildHourlyDistribution(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPeriodSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        borderRadius: 14,
        blur: 10,
        tint: Colors.transparent,
        borderColor: DesignColors.surfaceBorder,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: _periods.asMap().entries.map((entry) {
            final index = entry.key;
            final period = entry.value;
            final isSelected = _selectedPeriod == index;

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedPeriod = index);
                  _loadAnalyticsData();
                },
                child: AnimatedContainer(
                  duration: DesignAnimation.fast,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? DesignColors.brand.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    period,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? DesignColors.brand
                          : DesignColors.textSecondary,
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
      padding: const EdgeInsets.symmetric(horizontal: 2),
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
              const SizedBox(width: 12),
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
          const SizedBox(height: 12),
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
              const SizedBox(width: 12),
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

  Widget _buildSalesTrendChart() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 16,
      blur: 12,
      tint: DesignColors.brand.withValues(alpha: 0.05),
      borderColor: DesignColors.brand.withValues(alpha: 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DesignColors.brand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: DesignColors.brand.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: DesignColors.brand,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Sales Trend',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: DesignColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              time,
                              style: const TextStyle(
                                color: DesignColors.textTertiary,
                                fontSize: 11,
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
                    return FlLine(
                      color: DesignColors.surfaceBorder.withValues(alpha: 0.5),
                      strokeWidth: 1,
                    );
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

  Widget _buildTopProducts() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 16,
      blur: 12,
      tint: DesignColors.teal.withValues(alpha: 0.04),
      borderColor: DesignColors.teal.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DesignColors.teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: DesignColors.teal.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: DesignColors.teal,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Top Products',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: DesignColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
                padding: const EdgeInsets.only(bottom: 12),
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
                                    : DesignColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (index == 0
                                  ? Colors.amber
                                  : index == 1
                                      ? Colors.grey
                                      : index == 2
                                          ? Colors.orange
                                          : DesignColors.textTertiary)
                              .withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '#${index + 1}',
                          style: TextStyle(
                            color: index == 0
                                ? Colors.amber[700]
                                : index == 1
                                    ? Colors.grey[700]
                                    : index == 2
                                        ? Colors.orange[700]
                                        : DesignColors.textTertiary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product['productName'] ?? 'Unknown',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: DesignColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${product['totalQty']} units sold',
                            style: const TextStyle(
                              fontSize: 12,
                              color: DesignColors.textSecondary,
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: DesignColors.success,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(revenue / (_summary['totalRevenue'] ?? 1) * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 11,
                            color: DesignColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 16,
      blur: 12,
      tint: DesignColors.info.withValues(alpha: 0.04),
      borderColor: DesignColors.info.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DesignColors.info.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: DesignColors.info.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.payment_rounded,
                  color: DesignColors.info,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Payments',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: DesignColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_salesByPayment.isEmpty)
            const EmptyState(
              icon: Icons.payment_rounded,
              title: 'No payment data',
            )
          else
            ..._salesByPayment.map((payment) {
              final method = payment['paymentMethod'] ?? 'Unknown';
              final count = payment['count'] ?? 0;
              final total = payment['totalAmount'] ?? 0.0;
              final color = _getPaymentMethodColor(method);
              final totalBreakdown = (_salesByPayment.isNotEmpty
                  ? _salesByPayment.fold<double>(
                      0, (sum, p) => sum + ((p['totalAmount'] ?? 0) as double))
                  : 1);
              final percentage = totalBreakdown;
              final percent = (total / percentage * 100).toStringAsFixed(1);

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
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
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatPaymentMethod(method),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: DesignColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$count transactions',
                            style: const TextStyle(
                              fontSize: 12,
                              color: DesignColors.textSecondary,
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: DesignColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$percent%',
                          style: const TextStyle(
                            fontSize: 11,
                            color: DesignColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 16,
      blur: 12,
      tint: DesignColors.teal.withValues(alpha: 0.04),
      borderColor: DesignColors.teal.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DesignColors.teal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: DesignColors.teal.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.category_rounded,
                  color: DesignColors.teal,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Sales by Category',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: DesignColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_salesByCategory.isEmpty)
            const EmptyState(
              icon: Icons.category_rounded,
              title: 'No category data available',
            )
          else
            ..._salesByCategory.map((category) {
              final catName = category['categoryName'] ?? 'Unknown';
              final total = category['totalAmount'] ?? 0.0;
              final color = _getCategoryColor(catName);

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
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
                        const SizedBox(width: 8),
                        Text(
                          catName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: DesignColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'KSh ${total.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DesignColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (_salesByCategory.isNotEmpty
                                ? _salesByCategory.fold<double>(
                                    0,
                                    (sum, c) =>
                                        sum +
                                        ((c['totalAmount'] ?? 0) as double))
                                : 1)
                            .toDouble(),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 8,
                        backgroundColor: DesignColors.surfaceBorder,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildHourlyDistribution() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 16,
      blur: 12,
      tint: DesignColors.info.withValues(alpha: 0.04),
      borderColor: DesignColors.info.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DesignColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: DesignColors.accent.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  color: DesignColors.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Hourly Sales Distribution',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: DesignColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
                                  (sum, e) => (e['totalAmount'] ?? 0) > sum
                                      ? (e['totalAmount'] ?? 0) as double
                                      : sum)
                              : 1000)
                          .toDouble() *
                      1.2,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipPadding: const EdgeInsets.all(12),
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
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                time,
                                style: const TextStyle(
                                  color: DesignColors.textTertiary,
                                  fontSize: 11,
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
                      return FlLine(
                        color:
                            DesignColors.surfaceBorder.withValues(alpha: 0.5),
                        strokeWidth: 1,
                      );
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
        return DesignColors.teal;
      case 'food':
        return DesignColors.success;
      case 'services':
        return DesignColors.accent;
      default:
        return DesignColors.brand;
    }
  }
}
