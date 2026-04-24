import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/glassmorphism_theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';

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

          _paymentSummary = await database.getPaymentSummary(startOfDay, endOfDay);
          _paymentMethodBreakdown = await database.getSalesByPaymentMethod(startOfDay, endOfDay);
          _transactionTrends = await database.getHourlySales(startOfDay, endOfDay);
          _peakHours = await database.getPeakHours(startOfDay, endOfDay);

        case 1: // This Week
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          final endOfWeek = startOfWeek.add(const Duration(days: 7));

          _paymentSummary = await database.getPaymentSummary(startOfWeek, endOfWeek);
          _paymentMethodBreakdown = await database.getSalesByPaymentMethod(startOfWeek, endOfWeek);
          _transactionTrends = await database.getDailySales(startOfWeek, endOfWeek);
          _peakHours = await database.getPeakHours(startOfWeek, endOfWeek);

        case 2: // This Month
          final startOfMonth = DateTime(now.year, now.month, 1);
          final endOfMonth = DateTime(now.year, now.month + 1, 0);

          _paymentSummary = await database.getPaymentSummary(startOfMonth, endOfMonth);
          _paymentMethodBreakdown = await database.getSalesByPaymentMethod(startOfMonth, endOfMonth);
          _transactionTrends = await database.getDailySales(startOfMonth, endOfMonth);
          _peakHours = await database.getPeakHours(startOfMonth, endOfMonth);
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('Payment analytics load error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Payment Analytics'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadPaymentData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPaymentData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Period Selector
                    _buildPeriodSelector(),
                    const SizedBox(height: 24),

                    // Payment Summary Cards
                    _buildPaymentSummaryCards(),
                    const SizedBox(height: 24),

                    // Payment Method Breakdown
                    _buildPaymentMethodBreakdown(),
                    const SizedBox(height: 24),

                    // Transaction Trend Chart
                    _buildTransactionTrendChart(),
                    const SizedBox(height: 24),

                    // Peak Hours Analysis
                    _buildPeakHoursAnalysis(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPeriodSelector() {
    return GlassUI.glassBox(
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
                _loadPaymentData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  period,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPaymentSummaryCards() {
    final totalPayments = (_paymentSummary['totalAmount'] ?? 0.0).toDouble();
    final transactionCount = _paymentSummary['transactionCount'] ?? 0;
    final avgPayment = (_paymentSummary['avgPayment'] ?? 0.0).toDouble();
    final cashCount = _paymentSummary['cashCount'] ?? 0;
    final cardCount = _paymentSummary['cardCount'] ?? 0;
    final digitalCount = _paymentSummary['digitalCount'] ?? 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: GlassUI.glassMetricCard(
              title: 'Total Payments',
              value: 'KSh ${totalPayments.toStringAsFixed(0)}',
              icon: Icons.payments_rounded,
              color: AppColors.primary,
              trend: '+12.5%',
              trendValue: 12.5,
            )),
            const SizedBox(width: 12),
            Expanded(child: GlassUI.glassMetricCard(
              title: 'Transactions',
              value: transactionCount.toString(),
              icon: Icons.receipt_long_rounded,
              color: AppColors.secondary,
              trend: '+8.2%',
              trendValue: 8.2,
            )),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: GlassUI.glassMetricCard(
              title: 'Avg Payment',
              value: 'KSh ${avgPayment.toStringAsFixed(0)}',
              icon: Icons.calculate_rounded,
              color: AppColors.accentOrange,
              trend: '+5.3%',
              trendValue: 5.3,
            )),
            const SizedBox(width: 12),
            Expanded(child: GlassUI.glassMetricCard(
              title: 'Success Rate',
              value: '98.5%',
              icon: Icons.check_circle_rounded,
              color: AppColors.success,
              trend: '+0.5%',
              trendValue: 0.5,
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentMethodBreakdown() {
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
                  color: AppColors.info.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.info.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.payment_rounded,
                  color: AppColors.info,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Payment Method Breakdown',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_paymentMethodBreakdown.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'No payment data available',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ..._paymentMethodBreakdown.map((payment) {
              final method = payment['paymentMethod'] ?? 'Unknown';
              final count = payment['count'] ?? 0;
              final total = payment['totalAmount'] ?? 0.0;
              final color = _getPaymentMethodColor(method);

              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
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
                        const SizedBox(width: 10),
                        Text(
                          _formatPaymentMethod(method),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${count} transactions',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: (_paymentMethodBreakdown.isNotEmpty
                                      ? (_paymentMethodBreakdown.fold(0, (sum, p) => sum + (p['totalAmount'] ?? 0)) as num)
                                      : 1)
                                  .toDouble(),
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                              minHeight: 10,
                              backgroundColor: AppColors.border,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'KSh ${total.toStringAsFixed(0)}',
                          style: TextStyle(
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
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildTransactionTrendChart() {
    return GlassUI.glassChartContainer(
      title: 'Transaction Trends',
      icon: Icons.trending_up_rounded,
      primaryColor: AppColors.primary,
      chart: SizedBox(
        height: 280,
        child: LineChart(
          LineChartData(
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (int i = 0; i < _transactionTrends.length; i++)
                    FlSpot(i.toDouble(), (_transactionTrends[i]['totalAmount'] ?? 0).toDouble()),
                ],
                isCurved: true,
                gradient: AppColors.primaryGradient,
                barWidth: 4,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: AppColors.primaryGradient,
                  gradientBlendColors: [
                    AppColors.primary.withOpacity(0.1),
                    AppColors.primary.withOpacity(0.0),
                  ],
                ),
              ),
            ],
            minX: 0,
            maxX: (_transactionTrends.length - 1).toDouble(),
            minY: 0,
            maxY: (_transactionTrends.isNotEmpty
                    ? (_transactionTrends.map((e) => e['totalAmount']).reduce((a, b) => a > b ? a : b) as num)
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
                      final date = DateTime.parse(_transactionTrends[index]['date'] ?? '');
                      final time = _selectedPeriod == 0
                          ? '${date.hour}:00'
                          : '${date.day}/${date.month}';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          time,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
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
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'KSh ${value.toInt() ~/ 1000}k',
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
              horizontalInterval: (_transactionTrends.isNotEmpty
                      ? (_transactionTrends.map((e) => e['totalAmount']).reduce((a, b) => a > b ? a : b) as num)
                      : 1000)
                  .toDouble() /
                  5,
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

  Widget _buildPeakHoursAnalysis() {
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
                  color: AppColors.accentCyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.accentCyan.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  color: AppColors.accentCyan,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Peak Hours Analysis',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_peakHours.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'No peak hours data available',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ..._peakHours.map((hour) {
              final hourNum = hour['hour'] ?? 0;
              final count = hour['transactionCount'] ?? 0;
              final total = hour['totalAmount'] ?? 0.0;
              final color = _getPeakHourColor(hourNum);

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: color.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${hourNum}:00',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                color: AppColors.textSecondary,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatHourLabel(hourNum),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$count transactions',
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
                          'KSh ${total.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(count / (_peakHours.fold(0, (sum, h) => sum + (h['transactionCount'] ?? 0)) as num) * 100).toStringAsFixed(1)}% of traffic',
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
        ],
      ),
    );
  }

  Color _getPaymentMethodColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return AppColors.cash;
      case 'mpesa':
        return AppColors.mpesa;
      case 'card':
      case 'credit':
        return AppColors.credit;
      case 'pesapal':
        return AppColors.pesapal;
      case 'touristtap':
        return AppColors.touristtap;
      default:
        return AppColors.primary;
    }
  }

  Color _getPeakHourColor(int hour) {
    if (hour >= 8 && hour <= 10) return AppColors.success;
    if (hour >= 12 && hour <= 14) return AppColors.accentOrange;
    if (hour >= 17 && hour <= 19) return AppColors.primary;
    return AppColors.info;
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
