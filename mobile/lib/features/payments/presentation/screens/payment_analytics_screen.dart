import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/theme/design_system.dart';
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
          final endOfMonth = DateTime(now.year, now.month + 1, 0);

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
          ? const Center(child: CircularProgressIndicator(color: DesignColors.brand))
          : RefreshIndicator(
              onRefresh: _loadPaymentData,
              child: PageContainer(
                withScroll: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Period Selector
                    _buildPeriodSelector(isDark),
                    const SizedBox(height: 24),

                    // Payment Summary Cards
                    _buildPaymentSummaryCards(),
                    const SizedBox(height: 24),

                    // Payment Method Breakdown
                    _buildPaymentMethodBreakdown(isDark),
                    const SizedBox(height: 24),

                    // Transaction Trend Chart
                    _buildTransactionTrendChart(isDark),
                    const SizedBox(height: 24),

                    // Peak Hours Analysis
                    _buildPeakHoursAnalysis(isDark),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPeriodSelector(bool isDark) {
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
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
                child: AnimatedContainer(
                  duration: DesignAnimation.fast,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? DesignColors.accent.withValues(alpha: 0.15)
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
                          ? DesignColors.accent
                          : secondaryColor,
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
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'Total Payments',
                  value: 'KSh ${totalPayments.toStringAsFixed(0)}',
                  icon: Icons.payments_rounded,
                  color: DesignColors.brand,
                ),
              ),
              const SizedBox(width: 12),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'Avg Payment',
                  value: 'KSh ${avgPayment.toStringAsFixed(0)}',
                  icon: Icons.calculate_rounded,
                  color: DesignColors.accent,
                ),
              ),
              const SizedBox(width: 12),
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
              const Icon(Icons.payment_rounded, color: DesignColors.info, size: 20),
              const SizedBox(width: 10),
              Text(
                'Payment Method Breakdown',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
              final share = grandTotal > 0
                  ? (total as double) / grandTotal
                  : 0.0;

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
                          style: TextStyle(fontSize: 14, color: titleColor),
                        ),
                        const Spacer(),
                        Text(
                          '$count transactions',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
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
                              value: share,
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                              minHeight: 10,
                              backgroundColor: border,
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
                'Transaction Trends',
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
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              time,
                              style: TextStyle(
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
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            'KSh ${(value as num).toInt() ~/ 1000}k',
                            style: TextStyle(
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
              const Icon(Icons.access_time_rounded, color: DesignColors.accent, size: 20),
              const SizedBox(width: 10),
              Text(
                'Peak Hours Analysis',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: color.withValues(alpha: 0.3),
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
                                color: secondaryColor,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatHourLabel(hourNum),
                                style: TextStyle(fontSize: 13, color: titleColor),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$count transactions',
                            style: TextStyle(fontSize: 12, color: secondaryColor),
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
                          '${trafficShare.toStringAsFixed(1)}% of traffic',
                          style: TextStyle(fontSize: 11, color: secondaryColor),
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
