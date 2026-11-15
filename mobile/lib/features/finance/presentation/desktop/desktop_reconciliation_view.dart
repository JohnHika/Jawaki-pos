import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_facts.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import 'desktop_figures_row.dart';

/// One saved till count: what the till should have held against what was
/// counted. [difference] is counted minus expected, so a shortfall is negative.
class DesktopCountRecord {
  const DesktopCountRecord({
    required this.id,
    required this.at,
    required this.expected,
    required this.counted,
    required this.difference,
    this.countedBy,
    this.notes,
  });

  final String id;
  final DateTime? at;
  final double expected;
  final double counted;
  final double difference;
  final String? countedBy;
  final String? notes;

  bool get matches => difference.abs() < 0.01;
  String get statusLabel =>
      matches ? 'Matches' : (difference < 0 ? 'Shortfall' : 'Overage');
  Color get statusColor => matches
      ? DesignColors.success
      : (difference < 0 ? DesignColors.error : DesignColors.warning);
}

/// Cash reconciliation on a computer: the history of till counts as a table
/// with the selected count in a side panel. Counting opens from the header.
///
/// Plain data in; the routed screen owns the providers and the count sheet.
class DesktopReconciliationView extends StatefulWidget {
  const DesktopReconciliationView({
    super.key,
    required this.records,
    this.title = 'Cash reconciliation',
    this.subtitle,
    this.countLabel = 'Count cash',
    this.onCount,
    this.onBack,
    this.onRefresh,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.emptyTitle,
    this.emptyMessage,
    this.restricted = false,
    this.historyHidden = false,
    this.dateLabel,
  });

  final List<DesktopCountRecord> records;
  final String title;
  final String? subtitle;
  final String countLabel;

  /// null hides the count button (the role cannot reconcile).
  final VoidCallback? onCount;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// Shown when there is no history yet (or no branch).
  final String? emptyTitle;
  final String? emptyMessage;

  /// The role can neither count nor read history.
  final bool restricted;

  /// The role can count but not read history.
  final bool historyHidden;

  /// Formats a count's date.
  final String Function(DateTime at)? dateLabel;

  @override
  State<DesktopReconciliationView> createState() =>
      _DesktopReconciliationViewState();
}

class _DesktopReconciliationViewState extends State<DesktopReconciliationView> {
  String? _selected;

  String _when(DateTime? at) {
    if (at == null) return '—';
    final fmt = widget.dateLabel;
    if (fmt != null) return fmt(at);
    final m = at.month.toString().padLeft(2, '0');
    final d = at.day.toString().padLeft(2, '0');
    final h = at.hour.toString().padLeft(2, '0');
    final min = at.minute.toString().padLeft(2, '0');
    return '${at.year}-$m-$d $h:$min';
  }

  DesktopCountRecord? get _record {
    for (final r in widget.records) {
      if (r.id == _selected) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return CallbackShortcuts(
      bindings: {
        if (w.onRefresh != null)
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              w.onRefresh!,
        if (w.onCount != null)
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              w.onCount!,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: w.title,
              subtitle: w.subtitle,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
              leading: w.onBack == null
                  ? null
                  : IconButton(
                      tooltip: 'Back',
                      onPressed: w.onBack,
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    ),
              actions: [
                if (w.onRefresh != null && !w.historyHidden && !w.restricted)
                  IconButton(
                    tooltip: 'Refresh (Ctrl+R)',
                    onPressed: w.onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                if (w.onCount != null && !w.restricted)
                  Tooltip(
                    message: 'Ctrl+N',
                    child: FilledButton.icon(
                      style: desktopPrimaryButton(context),
                      onPressed: w.onCount,
                      icon: const Icon(Icons.calculate_rounded, size: 18),
                      label: Text(w.countLabel),
                    ),
                  ),
              ],
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final w = widget;
    if (w.restricted) {
      return const DesktopEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Cash reconciliation is restricted',
        message: 'Only store managers and admins can reconcile cash.',
      );
    }
    if (w.historyHidden) {
      return const DesktopEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'History access not enabled',
        message:
            'You can record a cash count, but your role cannot view reconciliation history.',
      );
    }
    if (w.loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (w.errorMessage != null) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load reconciliation history',
        message: w.errorMessage,
        action: w.onRetry == null
            ? null
            : OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: w.onRetry,
                child: const Text('Try again'),
              ),
      );
    }
    if (w.emptyTitle != null || w.records.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.calculate_outlined,
        title: w.emptyTitle ?? 'No reconciliations yet',
        message: w.emptyMessage,
      );
    }
    final records = w.records;
    final shorts = records.where((r) => !r.matches && r.difference < 0);
    final overs = records.where((r) => !r.matches && r.difference > 0);
    final net = records.fold<double>(0, (s, r) => s + r.difference);
    final p = context.desktop;
    final figures = [
      DesktopFigure(
        label: 'Counts shown',
        value: '${records.length}',
        hint: 'Most recent first',
      ),
      DesktopFigure(
        label: 'Matched',
        value: '${records.where((r) => r.matches).length}',
        hint: 'Exact matches',
      ),
      DesktopFigure(
        label: 'Short',
        value: '${shorts.length}',
        hint: shorts.isEmpty ? ' ' : 'Cash missing from the till',
        valueColor: shorts.isEmpty ? null : negativeAmountColor(p),
      ),
      DesktopFigure(
        label: 'Net difference',
        value: _signed(net),
        hint: overs.isEmpty ? ' ' : '${overs.length} over',
        valueColor: net < -0.005 ? negativeAmountColor(p) : null,
      ),
    ];
    final selected = _record;
    return DesktopInspectorLayout(
      onClose: () => setState(() => _selected = null),
      inspectorWidth: 340,
      inspector: selected == null ? null : _inspector(context, selected),
      main: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesktopTokens.gutter,
          4,
          DesktopTokens.gutter,
          DesktopTokens.gutter,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopFiguresRow(
              figures: figures,
              dense: MediaQuery.sizeOf(context).height < 620,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: p.dark ? p.panelAlt : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border),
                ),
                child: DesktopDataTable<DesktopCountRecord>(
                  minWidth: 600,
                  rows: records,
                  rowId: (r) => r.id,
                  selectedId: _selected,
                  onRowSelected: (r) => setState(() => _selected = r.id),
                  initialSortColumn: 0,
                  initialSortAscending: false,
                  columns: [
                    DesktopColumn<DesktopCountRecord>(
                      label: 'Counted',
                      flex: 2,
                      minWidth: 130,
                      sortBy: (r) => r.at ?? DateTime(1970),
                      cell: (_, r) => DesktopCellText(_when(r.at), strong: true),
                    ),
                    DesktopColumn<DesktopCountRecord>(
                      label: 'Result',
                      width: 104,
                      sortBy: (r) => r.difference,
                      cell: (_, r) => DesktopStatusChip(
                        label: r.statusLabel,
                        color: r.statusColor,
                      ),
                    ),
                    DesktopColumn<DesktopCountRecord>(
                      label: 'Expected',
                      width: 110,
                      numeric: true,
                      sortBy: (r) => r.expected,
                      cell: (_, r) => DesktopCellText(
                        formatMoney(r.expected),
                        numeric: true,
                      ),
                    ),
                    DesktopColumn<DesktopCountRecord>(
                      label: 'Counted cash',
                      width: 118,
                      numeric: true,
                      sortBy: (r) => r.counted,
                      cell: (_, r) => DesktopCellText(
                        formatMoney(r.counted),
                        numeric: true,
                      ),
                    ),
                    DesktopColumn<DesktopCountRecord>(
                      label: 'Difference',
                      width: 112,
                      numeric: true,
                      sortBy: (r) => r.difference,
                      cell: (context, r) => DesktopCellText(
                        r.matches ? 'KES 0' : _signed(r.difference),
                        numeric: true,
                        color: r.difference < -0.005
                            ? negativeAmountColor(context.desktop)
                            : null,
                        muted: r.matches,
                      ),
                    ),
                    DesktopColumn<DesktopCountRecord>(
                      label: 'Counted by',
                      flex: 2,
                      minWidth: 100,
                      cell: (_, r) =>
                          DesktopCellText(r.countedBy ?? '—', muted: true),
                    ),
                  ],
                  footer: Container(
                    height: 36,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    color: p.dark ? p.panelAlt : p.panel,
                    child: Text(
                      'Click a row, or use the arrow keys, to see its notes.',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _signed(double v) {
    if (v.abs() < 0.005) return 'KES 0';
    return '${v < 0 ? '-' : '+'}${formatMoney(v.abs())}';
  }

  Widget _inspector(BuildContext context, DesktopCountRecord r) {
    final p = context.desktop;
    return DesktopInspector(
      title: _when(r.at),
      subtitle: r.countedBy == null ? null : 'Counted by ${r.countedBy}',
      onClose: () => setState(() => _selected = null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: DesktopStatusChip(label: r.statusLabel, color: r.statusColor),
          ),
          const SizedBox(height: 14),
          DesktopFactList(
            facts: [
              DesktopFact('Expected in till', formatMoney(r.expected),
                  numeric: true),
              DesktopFact('Counted cash', formatMoney(r.counted),
                  numeric: true),
              DesktopFact(
                r.matches
                    ? 'Difference'
                    : (r.difference < 0 ? 'Shortfall' : 'Overage'),
                r.matches ? 'KES 0' : formatMoney(r.difference.abs()),
                numeric: true,
                color: r.difference < -0.005 ? negativeAmountColor(p) : null,
              ),
            ],
          ),
          if (r.notes != null && r.notes!.isNotEmpty) ...[
            const SizedBox(height: 18),
            const DesktopSectionLabel('Notes'),
            Text(
              r.notes!,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
