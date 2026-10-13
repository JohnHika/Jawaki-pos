import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/utils/format.dart';
import '../../domain/analytics_mapping.dart';

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

      final now = DateTime.now();
      try {
        // Sales figures come from the server so a second phone or fresh install
        // sees the shop's real history; this device's records are the fallback.
        final api = getIt<ApiClient>();
        final branchId = getIt<AuthService>().branchId;
        final iso = DateFormat('yyyy-MM-dd');
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final results = await Future.wait<Object?>([
          api.getTopProductsReport(
              startDate: iso.format(monday),
              endDate: iso.format(now),
              branchId: branchId,
              limit: 100),
          api.getSalesTrendReport(
              startDate: iso.format(now.subtract(const Duration(days: 6))),
              endDate: iso.format(now),
              branchId: branchId,
              groupBy: 'DAY'),
        ]);
        final ranking = topProductsFromServer(results[0]);
        _fastMovingItems = ranking.take(10).toList();
        _slowMovingItems = slowestFromRanking(ranking);
        _forecastData = weeklyVelocityFromServer(results[1], now);
      } catch (e) {
        if (!kReleaseMode) debugPrint('Forecast server load failed, using local: $e');
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        _fastMovingItems =
            await database.getTopProducts(startOfWeek, endOfWeek, limit: 10);
        _slowMovingItems =
            await database.getSlowMovingProducts(startOfWeek, endOfWeek, limit: 10);
        _forecastData = await _loadDailySalesVelocity();
      }

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
          IconButton(tooltip: 'Refresh', 
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
                    // First-mount entrance: each section fades/rises in
                    // once, staggered (see StaggeredItem); stable keys keep
                    // pull-to-refresh from replaying them.

                    // Forecast Summary
                    StaggeredItem(
                      itemKey: 'forecast-summary',
                      child: _buildForecastSummary(),
                    ),
                    const SizedBox(height: DesignSpacing.xxl),

                    // Demand Forecast Chart
                    StaggeredItem(
                      itemKey: 'forecast-chart',
                      index: 1,
                      child: _buildDemandForecastChart(isDark),
                    ),
                    const SizedBox(height: DesignSpacing.xxl),

                    // Low Stock Alerts
                    StaggeredItem(
                      itemKey: 'forecast-low-stock',
                      index: 2,
                      child: _buildLowStockAlerts(isDark),
                    ),
                    const SizedBox(height: DesignSpacing.xxl),

                    // Fast Moving Items
                    StaggeredItem(
                      itemKey: 'forecast-fast-moving',
                      index: 3,
                      child: _buildFastMovingItems(isDark),
                    ),
                    const SizedBox(height: DesignSpacing.xxl),

                    // Slow Moving Items
                    StaggeredItem(
                      itemKey: 'forecast-slow-moving',
                      index: 4,
                      child: _buildSlowMovingItems(isDark),
                    ),
                    const SizedBox(height: DesignSpacing.lg),
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
      padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.xs - 2),
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
      padding: const EdgeInsets.all(DesignSpacing.xl),
      decoration: BoxDecoration(color: surface, border: Border.all(color: border), borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: DesignColors.brand, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Text(
                'Last 7 Days — Units Sold',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                      for (int i = 0; i < _forecastData.length; i++)
                        FlSpot(
                            i.toDouble(),
                            ((_forecastData[i]['itemsSold'] ?? 0) as int)
                                .toDouble()),
                    ],
                    isCurved: true,
                    preventCurveOverShooting: true,
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
                            padding: const EdgeInsets.only(top: DesignSpacing.sm),
                            child: Text(
                              _forecastData[index]['day'] ?? '',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: tertiaryColor,
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
                      // Reserve room for the label; without it the top tick
                      // squeezed to one character wide and wrapped vertically.
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        // Hide the uneven tick fl_chart adds at the very top.
                        if (value == meta.max && value % 5 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: DesignSpacing.sm),
                          child: Text(
                            '${value.toInt()}',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: tertiaryColor,
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
      padding: const EdgeInsets.all(DesignSpacing.xl),
      decoration: BoxDecoration(color: surface, border: Border.all(color: border), borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: DesignColors.warning, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'Low Stock Alerts',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
          const SizedBox(height: DesignSpacing.lg),
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
                padding: const EdgeInsets.only(bottom: DesignSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isOut
                            ? DesignColors.error.withValues(alpha: 0.15)
                            : DesignColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
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
                    const SizedBox(width: DesignSpacing.md + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: DesignSpacing.xs),
                          Text(sku,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: secondaryColor,
                              )),
                        ],
                      ),
                    ),
                    Text(
                      isOut ? 'Out of Stock' : '${quantity is num ? (quantity == quantity.roundToDouble() ? quantity.toInt() : quantity) : quantity} left',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
              padding: const EdgeInsets.only(top: DesignSpacing.md),
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
      padding: const EdgeInsets.all(DesignSpacing.xl),
      decoration: BoxDecoration(color: surface, border: Border.all(color: border), borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: DesignColors.success, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Text(
                'Fast Moving Items',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.lg),
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
                padding: const EdgeInsets.only(bottom: DesignSpacing.md),
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
                        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd - 2),
                      ),
                      child: Center(
                        child: Text(
                          '#${index + 1}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: index == 0
                              ? Colors.amber[700]
                              : secondaryColor,
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
                            '${formatMoney(product['totalRevenue'])} sold',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      label: countLabel(qty, 'unit'),
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
      padding: const EdgeInsets.all(DesignSpacing.xl),
      decoration: BoxDecoration(color: surface, border: Border.all(color: border), borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_down_rounded, color: DesignColors.accent, size: 20),
              const SizedBox(width: DesignSpacing.sm + 2),
              Text(
                'Slow Moving Items',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.lg),
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
                padding: const EdgeInsets.only(bottom: DesignSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark
                            ? DesignColors.darkSurfaceElevated
                            : DesignColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd - 2),
                      ),
                      child: Center(
                        child: Text(
                          '#${index + 1}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: secondaryColor,
                              fontWeight: FontWeight.w600,
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
                            '${formatMoney(product['totalRevenue'])} sold',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      label: countLabel(qty, 'unit'),
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
