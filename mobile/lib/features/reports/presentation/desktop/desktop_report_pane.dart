import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../dashboard/presentation/desktop/desktop_bar_chart.dart';

/// The totals row pinned under a report table. It lays its cells out with the
/// same fixed and flexible widths as the table's [columns] so each total sits
/// under its own column.
class DesktopTotalsFooter<T> extends StatelessWidget {
  const DesktopTotalsFooter({
    super.key,
    required this.columns,
    required this.values,
  });

  final List<DesktopColumn<T>> columns;

  /// One entry per column; null leaves that cell empty.
  final List<String?> values;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      height: 40,
      color: p.dark ? p.panel : p.panelAlt,
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            _cell(
              columns[i],
              values.length > i ? values[i] : null,
              p,
              first: i == 0,
            ),
        ],
      ),
    );
  }

  Widget _cell(
    DesktopColumn<T> column,
    String? text,
    DesktopPalette p, {
    required bool first,
  }) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment:
            column.numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: text == null
            ? const SizedBox.shrink()
            : Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: column.numeric
                    ? DesignType.numeric(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: p.text,
                        letterSpacing: 0,
                      )
                    : GoogleFonts.plusJakartaSans(
                        color: first ? p.text : p.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
              ),
      ),
    );
    return column.width != null
        ? SizedBox(width: column.width, child: child)
        : Expanded(flex: column.flex, child: child);
  }
}

/// One report: an optional chart (or any summary widget) above a table with a
/// sticky header and a totals footer. Takes plain data, so a test can feed
/// rows, and degrades by letting the page scroll when the window is short.
class ReportPane<R> extends StatefulWidget {
  const ReportPane({
    super.key,
    required this.rows,
    required this.loading,
    required this.columns,
    required this.rowId,
    required this.totals,
    required this.empty,
    this.error,
    this.onRetry,
    this.chartTitle,
    this.chartSubtitle,
    this.bars,
    this.leading,
    this.leadingHeight = 112,
    this.onRowActivated,
    this.initialSortColumn,
    this.initialSortAscending = true,
    this.tableMinWidth = 560,
  });

  /// Null while the first read is in flight or after it failed.
  final List<R>? rows;
  final bool loading;

  /// A readable reason the report could not load.
  final String? error;
  final VoidCallback? onRetry;
  final List<DesktopColumn<R>> columns;
  final Object Function(R row) rowId;

  /// One total per column for the pinned footer.
  final List<String?> Function(List<R> rows) totals;

  /// Shown instead of the table when the period has no data.
  final Widget empty;
  final String? chartTitle;
  final String? chartSubtitle;
  final List<DesktopChartBar>? bars;

  /// A summary strip drawn in place of the chart.
  final Widget? leading;
  final double leadingHeight;
  final ValueChanged<R>? onRowActivated;
  final int? initialSortColumn;
  final bool initialSortAscending;
  final double tableMinWidth;

  static const double _gap = 12;
  static const double _minTable = 220;
  // Title, subtitle and the panel's own padding around the chart.
  static const double _chartOverhead = 76;

  @override
  State<ReportPane<R>> createState() => _ReportPaneState<R>();
}

class _ReportPaneState<R> extends State<ReportPane<R>> {
  Object? _selected;

  static const double _gap = ReportPane._gap;
  static const double _minTable = ReportPane._minTable;
  static const double _chartOverhead = ReportPane._chartOverhead;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final data = widget.rows;

    if (widget.error != null) {
      return DesktopEmptyState(
        icon: Icons.error_outline_rounded,
        title: "Couldn't load this report",
        message: widget.error,
        action: widget.onRetry == null
            ? null
            : OutlinedButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
      );
    }
    if (!widget.loading && data != null && data.isEmpty) return widget.empty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesktopTokens.gutter,
        14,
        DesktopTokens.gutter,
        DesktopTokens.gutter,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final hasTop = widget.bars != null || widget.leading != null;
          // The table is the report; the chart is a glance, about a third.
          final chartHeight = (box.maxHeight * 0.3).clamp(140.0, 230.0);
          final topHeight = widget.leading != null
              ? widget.leadingHeight
              : chartHeight + _chartOverhead;
          final needed = hasTop ? topHeight + _gap + _minTable : _minTable;
          final height = math.max(box.maxHeight, needed);

          return SingleChildScrollView(
            child: SizedBox(
              height: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.leading != null) ...[
                    SizedBox(
                        height: widget.leadingHeight, child: widget.leading),
                    const SizedBox(height: _gap),
                  ] else if (widget.bars != null) ...[
                    DesktopPanel(
                      title: widget.chartTitle,
                      subtitle: widget.chartSubtitle,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: widget.loading
                          ? _ChartPlaceholder(height: chartHeight)
                          : DesktopBarChart(
                              bars: widget.bars!,
                              height: chartHeight,
                              semanticLabel: widget.chartTitle,
                            ),
                    ),
                    const SizedBox(height: _gap),
                  ],
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.dark ? p.panelAlt : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: DesktopDataTable<R>(
                        columns: widget.columns,
                        rows: data ?? const [],
                        rowId: widget.rowId,
                        loading: false,
                        empty: widget.loading && data == null
                            ? const _RowsSkeleton()
                            : null,
                        minWidth: widget.tableMinWidth,
                        initialSortColumn: widget.initialSortColumn,
                        initialSortAscending: widget.initialSortAscending,
                        selectedId: _selected,
                        onRowSelected: (row) =>
                            setState(() => _selected = widget.rowId(row)),
                        onRowActivated: widget.onRowActivated,
                        footer: data == null
                            ? null
                            : DesktopTotalsFooter<R>(
                                columns: widget.columns,
                                values: widget.totals(data),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChartPlaceholder extends StatelessWidget {
  const _ChartPlaceholder({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.hover,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Quiet placeholder rows while the first read is in flight. Scrolls (never)
/// instead of overflowing when the table is short.
class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Semantics(
      label: 'Loading report',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 8; i++)
            SizedBox(
              height: DesktopTokens.rowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.2 + (i % 4) * 0.15,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: p.hover,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
