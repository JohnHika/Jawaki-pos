import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/design_system.dart';

/// One (x, y) point for a bar/line chart, mirroring the backend's ChartPoint.
class AiChartPoint {
  final String label;
  final double value;
  const AiChartPoint({required this.label, required this.value});

  factory AiChartPoint.fromJson(Map<String, dynamic> json) {
    return AiChartPoint(
      label: (json['label'] ?? '').toString(),
      value: (json['value'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One cell of a day×hour heatmap grid, mirroring the backend's HeatmapCell.
class AiHeatmapCell {
  final int dayOfWeek; // 0=Sun..6=Sat
  final int hour; // 0-23
  final double value;
  const AiHeatmapCell({
    required this.dayOfWeek,
    required this.hour,
    required this.value,
  });

  factory AiHeatmapCell.fromJson(Map<String, dynamic> json) {
    return AiHeatmapCell(
      dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 0,
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      value: (json['value'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// A chart the AI generated from real shop data — parsed from the backend's
/// GeneratedChart shape (see reporting/dto/chart-data.dto.ts).
class AiChartData {
  final String kind; // 'bar' | 'line' | 'heatmap'
  final String title;
  final String subtitle;
  final String valueLabel;
  final List<AiChartPoint> points;
  final List<AiHeatmapCell> cells;

  const AiChartData({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    this.points = const [],
    this.cells = const [],
  });

  factory AiChartData.fromJson(Map<String, dynamic> json) {
    return AiChartData(
      kind: (json['kind'] ?? 'bar').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      valueLabel: (json['valueLabel'] ?? '').toString(),
      points: (json['points'] as List?)
              ?.map((p) => AiChartPoint.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
      cells: (json['cells'] as List?)
              ?.map((c) => AiHeatmapCell.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// Renders an [AiChartData] as a real fl_chart widget inline in the AI chat
/// — a bar chart, a line trend, or a day×hour busiest-times heatmap grid.
/// One card handles all three kinds so the chat screen doesn't need to know
/// which shape came back, matching the same "one generic shape, one
/// renderer" approach the report export service uses for PDF/DOCX tables.
class AiChartCard extends StatelessWidget {
  final AiChartData chart;
  const AiChartCard({super.key, required this.chart});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final subtitleColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(chart.kind), color: DesignColors.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  chart.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                ),
              ),
            ],
          ),
          if (chart.subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              chart.subtitle,
              style: TextStyle(fontSize: 11, color: subtitleColor),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: chart.kind == 'heatmap' ? 220 : 200,
            child: switch (chart.kind) {
              'line' => _LineChart(chart: chart, isDark: isDark),
              'heatmap' => _HeatmapGrid(chart: chart, isDark: isDark),
              _ => _BarChart(chart: chart, isDark: isDark),
            },
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String kind) => switch (kind) {
        'line' => Icons.show_chart_rounded,
        'heatmap' => Icons.grid_on_rounded,
        _ => Icons.bar_chart_rounded,
      };
}

class _BarChart extends StatelessWidget {
  final AiChartData chart;
  final bool isDark;
  const _BarChart({required this.chart, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (chart.points.isEmpty) {
      return const Center(child: Text('No data for this period.'));
    }
    final tertiary =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final maxValue = chart.points.map((p) => p.value).reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxValue * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= chart.points.length) return const Text('');
                final label = chart.points[index].label;
                final short = label.length > 10 ? '${label.substring(0, 9)}…' : label;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(short, style: TextStyle(color: tertiary, fontSize: 9)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < chart.points.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: chart.points[i].value,
                  color: DesignColors.accent,
                  width: 18,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  final AiChartData chart;
  final bool isDark;
  const _LineChart({required this.chart, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (chart.points.isEmpty) {
      return const Center(child: Text('No data for this period.'));
    }
    final tertiary =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final maxValue = chart.points.map((p) => p.value).reduce((a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: maxValue * 1.2 == 0 ? 1 : maxValue * 1.2,
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= chart.points.length) return const Text('');
                final label = chart.points[index].label;
                final short = label.length > 10 ? label.substring(label.length - 5) : label;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(short, style: TextStyle(color: tertiary, fontSize: 9)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < chart.points.length; i++)
                FlSpot(i.toDouble(), chart.points[i].value),
            ],
            isCurved: true,
            color: DesignColors.accent,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  DesignColors.accent.withValues(alpha: 0.25),
                  DesignColors.accent.withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  final AiChartData chart;
  final bool isDark;
  const _HeatmapGrid({required this.chart, required this.isDark});

  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context) {
    if (chart.cells.isEmpty) {
      return const Center(child: Text('No data for this period.'));
    }
    final textColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final maxValue = chart.cells.map((c) => c.value).reduce((a, b) => a > b ? a : b);

    // Bucket into a 7 (day) x 24 (hour) grid, defaulting empty cells to 0.
    final grid = List.generate(7, (_) => List.filled(24, 0.0));
    for (final cell in chart.cells) {
      if (cell.dayOfWeek >= 0 && cell.dayOfWeek < 7 && cell.hour >= 0 && cell.hour < 24) {
        grid[cell.dayOfWeek][cell.hour] = cell.value;
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int day = 0; day < 7; day++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      _dayLabels[day],
                      style: TextStyle(fontSize: 9, color: textColor),
                    ),
                  ),
                  for (int hour = 0; hour < 24; hour++)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: DesignColors.accent.withValues(
                            alpha: maxValue == 0 ? 0.05 : (grid[day][hour] / maxValue) * 0.85 + 0.05,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
