import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import 'overview_logic.dart';

/// Revenue by month as a bar chart (fl_chart 1.x). The current month is drawn
/// in full brand colour, earlier months softer. Callers show an honest empty
/// state instead of this widget when [hasRevenue] is false.
class RevenueChart extends StatelessWidget {
  const RevenueChart({super.key, required this.months});

  final List<MonthRevenue> months;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final peak = months.fold<num>(0, (m, e) => math.max(m, e.amountKes));
    final axis = niceAxis(peak);
    final last = months.length - 1;

    final summary = months.map((m) => '${Fmt.monthLabel(m.month)} ${Fmt.kes(m.amountKes)}').join(', ');

    return Semantics(
      label: 'Revenue by month: $summary',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 210,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: axis.max,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: axis.interval,
                getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 1, dashArray: const [4, 4]),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: axis.interval,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      space: 6,
                      child: Text(compactAmount(value), style: TextStyle(fontSize: 11, color: p.textFaint)),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= months.length) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        space: 8,
                        child: Text(
                          Fmt.monthLabel(months[i].month),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: i == last ? FontWeight.w800 : FontWeight.w500,
                            color: i == last ? p.text : p.textMuted,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipColor: (_) => p.surfaceHigh,
                  tooltipBorder: BorderSide(color: p.border),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final m = months[groupIndex];
                    return BarTooltipItem(
                      '${Fmt.monthLabel(m.month)}\n${Fmt.kesCompact(rod.toY)}',
                      TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.3),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < months.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: math.max(0, months[i].amountKes.toDouble()),
                        width: 20,
                        color: i == last ? p.brand : p.brand.withValues(alpha: 0.5),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: axis.max,
                          color: p.surfaceHigh.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
