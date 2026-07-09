import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';

class InventoryForecastingScreen extends ConsumerStatefulWidget {
  const InventoryForecastingScreen({super.key});

  @override
  ConsumerState<InventoryForecastingScreen> createState() =>
      _InventoryForecastingScreenState();
}

class _InventoryForecastingScreenState
    extends ConsumerState<InventoryForecastingScreen> {
  List<Map<String, dynamic>> _lowStockItems = [];
  List<Map<String, dynamic>> _fastMovingItems = [];
  List<Map<String, dynamic>> _slowMovingItems = [];
  List<Map<String, dynamic>> _forecastData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInventoryData();
  }

  Future<void> _loadInventoryData() async {
    setState(() => _isLoading = true);

    try {
      final database = getIt<AppDatabase>();

      // Load low stock items
      _lowStockItems = await database.getLowStockProducts();

      // Load fast moving items (top sellers)
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 7));

      _fastMovingItems = await database.getTopProducts(
        startOfWeek,
        endOfWeek,
        limit: 10,
      );

      // Load slow moving items
      _slowMovingItems = await database.getSlowMovingProducts(
        startOfWeek,
        endOfWeek,
        limit: 10,
      );

      // Load real trailing sales-velocity data
      _forecastData = await _loadDailySalesVelocity();

      setState(() => _isLoading = false);
    } catch (e) {
      if (!kReleaseMode) debugPrint('Inventory forecast load error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        showGlassSnackBar(
          context,
          "Couldn't load inventory data. Check your connection and try again.",
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    }
  }

  /// Builds the last 7 days of *actual* units sold per day, so the chart
  /// reflects real sell-through instead of a fabricated projection.
  Future<List<Map<String, dynamic>>> _loadDailySalesVelocity() async {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final startOfRange = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final endOfRange = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final dailySales =
        await getIt<AppDatabase>().getDailyItemsSold(startOfRange, endOfRange);
    final byDate = {
      for (final row in dailySales) row['date'] as String: row['itemsSold'] as int,
    };

    return [
      for (int i = 0; i < 7; i++)
        () {
          final date = startOfRange.add(Duration(days: i));
          final dateKey = date.toIso8601String().substring(0, 10);
          return {
            'day': days[date.weekday - 1],
            'itemsSold': byDate[dateKey] ?? 0,
            'date': dateKey,
          };
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Inventory Forecast',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadInventoryData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: DesignColors.brand))
          : RefreshIndicator(
              onRefresh: _loadInventoryData,
              child: PageContainer(
                withScroll: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Forecast Summary
                    _buildForecastSummary(),
                    const SizedBox(height: 24),

                    // Demand Forecast Chart
                    _buildDemandForecastChart(isDark),
                    const SizedBox(height: 24),

                    // Low Stock Alerts
                    _buildLowStockAlerts(isDark),
                    const SizedBox(height: 24),

                    // Fast Moving Items
                    _buildFastMovingItems(isDark),
                    const SizedBox(height: 24),

                    // Slow Moving Items
                    _buildSlowMovingItems(isDark),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildForecastSummary() {
    final lowStockCount = _lowStockItems.length;
    final fastMovingCount = _fastMovingItems.length;
    final slowMovingCount = _slowMovingItems.length;
    final totalReorderRisk = (lowStockCount /
            (lowStockCount + fastMovingCount + slowMovingCount + 1) *
            100)
        .round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: MetricCard(
              title: 'Reorder Risk',
              value: '$totalReorderRisk%',
              icon: Icons.warning_amber_rounded,
              color: totalReorderRisk > 50
                  ? DesignColors.error
                  : totalReorderRisk > 25
                      ? DesignColors.warning
                      : DesignColors.success,
              trend: totalReorderRisk > 50 ? 'High' : 'Low',
              trendValue: totalReorderRisk > 50 ? -1 : 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemandForecastChart(bool isDark) {
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: DesignColors.brand, size: 20),
              const SizedBox(width: 10),
              Text(
                'Last 7 Days — Units Sold',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 280,
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (int i = 0; i < _forecastData.length; i++)
                        FlSpot(
                            i.toDouble(),
                            ((_forecastData[i]['itemsSold'] ?? 0) as int)
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
                maxX: 6.toDouble(),
                minY: 0,
                maxY: _forecastData.isEmpty
                    ? 10.0
                    : (_forecastData
                                .map((d) => (d['itemsSold'] ?? 0) as int)
                                .reduce((a, b) => a > b ? a : b) *
                            1.25)
                        .clamp(10, double.infinity)
                        .toDouble(),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < _forecastData.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _forecastData[index]['day'] ?? '',
                              style: TextStyle(color: tertiaryColor, fontSize: 12),
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
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '${value.toInt()}',
                            style: TextStyle(color: tertiaryColor, fontSize: 11),
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
                  horizontalInterval: 50,
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

  Widget _buildLowStockAlerts(bool isDark) {
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: DesignColors.warning, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'Low Stock Alerts',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    const Spacer(),
                    StatusBadge(
                      label: '${_lowStockItems.length}',
                      color: DesignColors.warning,
                      isActive: _lowStockItems.isNotEmpty,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_lowStockItems.isEmpty)
            const EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'No low stock items',
              iconColor: DesignColors.success,
            )
          else
            ..._lowStockItems.take(4).map((item) {
              final name = item['name'] ?? 'Unknown';
              final quantity = item['quantity'] ?? 0;
              final sku = item['sku'] ?? '';
              final isOut = quantity == 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isOut
                            ? DesignColors.error.withValues(alpha: 0.15)
                            : DesignColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (isOut
                                  ? DesignColors.error
                                  : DesignColors.warning)
                              .withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          isOut
                              ? Icons.error_outline_rounded
                              : Icons.inventory_2_outlined,
                          color:
                              isOut ? DesignColors.error : DesignColors.warning,
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
                            name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(sku, style: TextStyle(fontSize: 12, color: secondaryColor)),
                        ],
                      ),
                    ),
                    Text(
                      isOut ? 'Out of Stock' : '$quantity left',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color:
                            isOut ? DesignColors.error : DesignColors.warning,
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (_lowStockItems.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: TextButton(
                  onPressed: () => context.push('/inventory'),
                  child: const Text(
                    'View all in Inventory',
                    style: TextStyle(
                      color: DesignColors.brand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFastMovingItems(bool isDark) {
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: DesignColors.success, size: 20),
              const SizedBox(width: 10),
              Text(
                'Fast Moving Items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_fastMovingItems.isEmpty)
            const EmptyState(
              icon: Icons.trending_up_rounded,
              title: 'No sales data available',
            )
          else
            ..._fastMovingItems.asMap().entries.map((entry) {
              final index = entry.key;
              final product = entry.value;
              final qty = product['totalQty'] ?? 0;

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
                            : (isDark
                                ? DesignColors.darkSurfaceElevated
                                : DesignColors.surfaceSubtle),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '#${index + 1}',
                          style: TextStyle(
                            color: index == 0
                                ? Colors.amber[700]
                                : secondaryColor,
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
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${product['totalRevenue']?.toStringAsFixed(0) ?? 0} revenue',
                            style: TextStyle(fontSize: 12, color: secondaryColor),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      label: '$qty units',
                      color: DesignColors.success,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSlowMovingItems(bool isDark) {
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_down_rounded, color: DesignColors.accent, size: 20),
              const SizedBox(width: 10),
              Text(
                'Slow Moving Items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_slowMovingItems.isEmpty)
            const EmptyState(
              icon: Icons.trending_down_rounded,
              title: 'No slow moving items detected',
              iconColor: DesignColors.success,
            )
          else
            ..._slowMovingItems.asMap().entries.map((entry) {
              final index = entry.key;
              final product = entry.value;
              final qty = product['totalQty'] ?? 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark
                            ? DesignColors.darkSurfaceElevated
                            : DesignColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '#${index + 1}',
                          style: TextStyle(
                            color: secondaryColor,
                            fontWeight: FontWeight.w600,
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
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${product['totalRevenue']?.toStringAsFixed(0) ?? 0} revenue',
                            style: TextStyle(fontSize: 12, color: secondaryColor),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      label: '$qty units',
                      color: DesignColors.accent,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
