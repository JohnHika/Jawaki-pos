import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/glassmorphism_theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';

final _random = Random();

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
      _lowStockItems = await database.getLowStockProducts(threshold: 10);

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

      // Generate forecast data
      _forecastData = await _generateForecast();

      setState(() => _isLoading = false);
    } catch (e) {
      print('Inventory forecast load error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _generateForecast() async {
    // Generate synthetic forecast data for demo
    // In production, this would use actual forecasting algorithms
    final forecast = <Map<String, dynamic>>[];
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime.now().day;

    for (int i = 0; i < 7; i++) {
      final dayIndex = (today + i) % 7;
      // Simulate higher sales on weekends
      final baseDemand = dayIndex >= 5 ? 150 : 100;
      final variance = (_random.nextDouble() * 40 - 20).round();
      final forecastedDemand = (baseDemand + variance).clamp(50, 200);

      forecast.add({
        'day': days[dayIndex],
        'forecastedDemand': forecastedDemand,
        'currentStock': (forecastedDemand * 0.8).round(),
        'reorderPoint': (forecastedDemand * 0.6).round(),
      });
    }

    return forecast;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Inventory Forecast'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadInventoryData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadInventoryData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Forecast Summary
                    _buildForecastSummary(),
                    const SizedBox(height: 24),

                    // Demand Forecast Chart
                    _buildDemandForecastChart(),
                    const SizedBox(height: 24),

                    // Low Stock Alerts
                    _buildLowStockAlerts(),
                    const SizedBox(height: 24),

                    // Fast Moving Items
                    _buildFastMovingItems(),
                    const SizedBox(height: 24),

                    // Slow Moving Items
                    _buildSlowMovingItems(),
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
    final totalReorderRisk = (lowStockCount / (lowStockCount + fastMovingCount + slowMovingCount + 1) * 100).round();

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: GlassUI.glassBox(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reorder Risk',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '$totalReorderRisk%',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: totalReorderRisk > 50
                              ? AppColors.error
                              : totalReorderRisk > 25
                                  ? AppColors.warning
                                  : AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              totalReorderRisk > 50
                                  ? Icons.warning_rounded
                                  : Icons.check_circle_rounded,
                              color: totalReorderRisk > 50
                                  ? AppColors.error
                                  : AppColors.success,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              totalReorderRisk > 50 ? 'High' : 'Low',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: totalReorderRisk > 50
                                    ? AppColors.error
                                    : AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildDemandForecastChart() {
    return GlassUI.glassChartContainer(
      title: '7-Day Demand Forecast',
      icon: Icons.trending_up_rounded,
      primaryColor: AppColors.primary,
      chart: SizedBox(
        height: 280,
        child: LineChart(
          LineChartData(
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (int i = 0; i < _forecastData.length; i++)
                    FlSpot(i.toDouble(), (_forecastData[i]['forecastedDemand'] ?? 0).toDouble()),
                ],
                isCurved: true,
                gradient: AppColors.primaryGradient,
                barWidth: 4,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: AppColors.primaryGradient,
                ),
              ),
            ],
            minX: 0,
            maxX: 6.toDouble(),
            minY: 0,
            maxY: 200.toDouble(),
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
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }
                    return const Text('');
                  },
                ),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${value.toInt()}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
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
              horizontalInterval: 50,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: AppColors.border.withOpacity(0.3),
                  strokeWidth: 1,
                );
              },
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }

  Widget _buildLowStockAlerts() {
    return GlassUI.glassBox(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.warning.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  const Text(
                    'Low Stock Alerts',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_lowStockItems.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_lowStockItems.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'No low stock items',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ..._lowStockItems.take(4).map((item) {
              final name = item['name'] ?? 'Unknown';
              final quantity = item['quantity'] ?? 0;
              final reorderLevel = item['reorderLevel'] ?? 0;
              final sku = item['sku'] ?? '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: quantity == 0
                            ? AppColors.error.withOpacity(0.15)
                            : AppColors.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (quantity == 0 ? AppColors.error : AppColors.warning).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          quantity == 0
                              ? Icons.error_outline_rounded
                              : Icons.inventory_2_outlined,
                          color: quantity == 0 ? AppColors.error : AppColors.warning,
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sku,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          quantity == 0 ? 'Out of Stock' : '$quantity left',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: quantity == 0 ? AppColors.error : AppColors.warning,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Reorder: $reorderLevel',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          if (_lowStockItems.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: TextButton(
                  onPressed: () {},
                  child: Text(
                    'View all ${_lowStockItems.length} items',
                    style: TextStyle(
                      color: AppColors.primary,
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

  Widget _buildFastMovingItems() {
    return GlassUI.glassBox(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.success.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: AppColors.success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Fast Moving Items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_fastMovingItems.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'No sales data available',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
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
                            ? Colors.amber.withOpacity(0.2)
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '#${index + 1}',
                          style: TextStyle(
                            color: index == 0 ? Colors.amber[700] : AppColors.textSecondary,
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
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${product['totalRevenue']?.toStringAsFixed(0) ?? 0} revenue',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$qty units',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
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

  Widget _buildSlowMovingItems() {
    return GlassUI.glassBox(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accentOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.accentOrange.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.trending_down_rounded,
                  color: AppColors.accentOrange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Slow Moving Items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_slowMovingItems.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'No slow moving items detected',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
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
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '#${index + 1}',
                          style: TextStyle(
                            color: AppColors.textSecondary,
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${product['totalRevenue']?.toStringAsFixed(0) ?? 0} revenue',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accentOrange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$qty units',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentOrange,
                        ),
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
}

import 'dart:math' show Random;
