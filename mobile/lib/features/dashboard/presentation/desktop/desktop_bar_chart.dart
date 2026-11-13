import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/theme/design_system.dart';

/// One bar of a [DesktopBarChart]: the label under it, its value, and the two
/// lines the hover tooltip shows.
class DesktopChartBar {
  const DesktopChartBar({
    required this.label,
    required this.value,
    required this.tooltipTitle,
    required this.tooltipValue,
  });

  /// Short text under the bar ("5p", "Mon", "12 Nov").
  final String label;
  final double value;

  /// First tooltip line ("5 pm", "Mon 12 Nov").
  final String tooltipTitle;

  /// Second tooltip line ("KES 12,400 · 6 sales").
  final String tooltipValue;
}

/// "12k", "1.5M", "850": axis labels short enough for a narrow gutter.
String compactAmount(double value) {
  final abs = value.abs();
  String trimmed(double v) {
    final text = v.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  if (abs >= 1000000) return '${trimmed(value / 1000000)}M';
  if (abs >= 1000) return '${trimmed(value / 1000)}k';
  return trimmed(value);
}

/// A round axis top and step so the grid lines fall on friendly numbers
/// (0, 5k, 10k, 15k, 20k) instead of 0, 3,100, 6,200.
({double top, double interval}) niceAxis(double maxValue, {int lines = 4}) {
  if (maxValue <= 0) return (top: 1000, interval: 250);
  final raw = maxValue / lines;
  final magnitude =
      math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / magnitude;
  final nice = norm <= 1
      ? 1.0
      : norm <= 2
          ? 2.0
          : norm <= 2.5
              ? 2.5
              : norm <= 5
                  ? 5.0
                  : 10.0;
  final interval = nice * magnitude;
  return (top: interval * lines, interval: interval);
}

/// A flat bar chart for desktop pages: hairline grid, left amounts, neutral
/// bars with the busiest bar (or the one under the pointer) in the accent.
/// Hovering a bar shows a tooltip. No entrance animation.
class DesktopBarChart extends StatefulWidget {
  const DesktopBarChart({
    super.key,
    required this.bars,
    this.height = 220,
    this.semanticLabel,
  });

  final List<DesktopChartBar> bars;
  final double height;
  final String? semanticLabel;

  @override
  State<DesktopBarChart> createState() => _DesktopBarChartState();
}

class _DesktopBarChartState extends State<DesktopBarChart> {
  int? _hover;

  static const double _axisWidth = 46;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final bars = widget.bars;
    final maxValue = bars.fold<double>(0, (m, b) => math.max(m, b.value));
    final axis = niceAxis(maxValue);

    var peak = -1;
    for (var i = 0; i < bars.length; i++) {
      if (bars[i].value > 0 && (peak < 0 || bars[i].value > bars[peak].value)) {
        peak = i;
      }
    }
    final active = _hover ?? (peak >= 0 ? peak : null);

    final neutral = p.dark ? const Color(0xFF8C8478) : const Color(0xFF9C8E78);
    final tooltipBg = p.dark ? p.text : const Color(0xFF211B12);
    final tooltipInk = p.dark ? DesignColors.darkSurface : Colors.white;

    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final plotWidth = math.max(0.0, constraints.maxWidth - _axisWidth);
            final slot = bars.isEmpty ? plotWidth : plotWidth / bars.length;
            final barWidth = (slot * 0.62).clamp(5.0, 44.0);
            // Labels are about 34px wide; skip bars until they fit.
            final step = math.max(1, (38 / math.max(slot, 1)).ceil());

            return BarChart(
              BarChartData(
                minY: 0,
                maxY: axis.top,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: axis.interval,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: p.border, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _axisWidth,
                      interval: axis.interval,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        axisSide: meta.axisSide,
                        space: 8,
                        child: Text(
                          compactAmount(value),
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= bars.length || i % step != 0) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 6,
                          child: Text(
                            bars[i].label,
                            maxLines: 1,
                            style: GoogleFonts.plusJakartaSans(
                              color: i == active ? p.text : p.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < bars.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: bars[i].value,
                          width: barWidth,
                          color: i == active ? DesignColors.accent : neutral,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ],
                    ),
                ],
                barTouchData: BarTouchData(
                  enabled: bars.isNotEmpty,
                  touchCallback: (event, response) {
                    final next = event.isInterestedForInteractions
                        ? response?.spot?.touchedBarGroupIndex
                        : null;
                    if (next != _hover) setState(() => _hover = next);
                  },
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: tooltipBg,
                    tooltipRoundedRadius: 6,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    tooltipMargin: 6,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final bar = bars[groupIndex];
                      return BarTooltipItem(
                        '${bar.tooltipTitle}\n',
                        GoogleFonts.plusJakartaSans(
                          color: tooltipInk.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          TextSpan(
                            text: bar.tooltipValue,
                            style: GoogleFonts.plusJakartaSans(
                              color: tooltipInk,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              swapAnimationDuration: Duration.zero,
            );
          },
        ),
      ),
    );
  }
}
