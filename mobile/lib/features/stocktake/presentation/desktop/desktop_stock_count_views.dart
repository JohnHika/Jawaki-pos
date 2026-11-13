import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart' show kitNumber;
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../../finance/presentation/desktop/desktop_figures_row.dart';
import '../../domain/stocktake_models.dart';

({String label, Color color}) _statusLook(String status) => switch (status) {
      'IN_PROGRESS' => (label: 'Counting', color: DesignColors.info),
      'SUBMITTED' => (label: 'Needs approval', color: DesignColors.warning),
      'APPROVED' => (label: 'Done', color: DesignColors.success),
      _ => (label: 'Cancelled', color: DesignColors.error),
    };

BoxDecoration _surface(DesktopPalette p) => BoxDecoration(
      color: p.dark ? p.panelAlt : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: p.border),
    );

/// The list of stock counts as a table. Click a row to open the count.
class DesktopStockCountsView extends StatefulWidget {
  const DesktopStockCountsView({
    super.key,
    required this.title,
    required this.rows,
    this.canCreate = false,
    this.loading = false,
    this.errorMessage,
    this.onOpen,
    this.onStart,
    this.onRefresh,
    this.onRetry,
  });

  final String title;
  final List<StockCountSummary> rows;
  final bool canCreate;
  final bool loading;
  final String? errorMessage;
  final ValueChanged<StockCountSummary>? onOpen;
  final VoidCallback? onStart;
  final VoidCallback? onRefresh;
  final VoidCallback? onRetry;

  @override
  State<DesktopStockCountsView> createState() => _DesktopStockCountsViewState();
}

class _DesktopStockCountsViewState extends State<DesktopStockCountsView> {
  String _filter = 'ALL';

  static const _filters = [
    ('ALL', 'All'),
    ('IN_PROGRESS', 'Counting'),
    ('SUBMITTED', 'Needs approval'),
    ('APPROVED', 'Done'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final rows = _filter == 'ALL'
        ? widget.rows
        : widget.rows.where((r) => r.status == _filter).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: widget.title,
          subtitle: 'Count the shelf, compare it with the system, find losses early',
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          actions: [
            if (widget.canCreate)
              FilledButton.icon(
                style: desktopPrimaryButton(context),
                onPressed: widget.onStart,
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('New count'),
              ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: widget.loading ? null : widget.onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in _filters)
                DesktopFilterChip(
                  label: f.$2,
                  count: f.$1 == 'ALL'
                      ? widget.rows.length
                      : widget.rows.where((r) => r.status == f.$1).length,
                  selected: _filter == f.$1,
                  onTap: () => setState(() => _filter = f.$1),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: _surface(p),
              child: widget.errorMessage != null && widget.rows.isEmpty
                  ? DesktopEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: "Couldn't load stock counts",
                      message: widget.errorMessage,
                      action: widget.onRetry == null
                          ? null
                          : OutlinedButton(
                              style: desktopSecondaryButton(context),
                              onPressed: widget.onRetry,
                              child: const Text('Try again'),
                            ),
                    )
                  : DesktopDataTable<StockCountSummary>(
                      rows: rows,
                      loading: widget.loading,
                      rowId: (r) => r.id,
                      rowHeight: 48,
                      minWidth: 640,
                      onRowSelected: widget.onOpen,
                      initialSortColumn: 4,
                      initialSortAscending: false,
                      columns: [
                        DesktopColumn<StockCountSummary>(
                          label: 'Count',
                          flex: 3,
                          minWidth: 170,
                          sortBy: (r) => r.displayTitle.toLowerCase(),
                          cell: (_, r) => Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DesktopCellText(r.displayTitle, strong: true),
                              if (r.createdByName != null)
                                DesktopCellText(r.createdByName!, muted: true),
                            ],
                          ),
                        ),
                        DesktopColumn<StockCountSummary>(
                          label: 'Status',
                          width: 136,
                          sortBy: (r) => r.status,
                          cell: (_, r) {
                            final look = _statusLook(r.status);
                            return DesktopStatusChip(
                              label: look.label,
                              color: look.color,
                            );
                          },
                        ),
                        DesktopColumn<StockCountSummary>(
                          label: 'Items',
                          width: 84,
                          numeric: true,
                          sortBy: (r) => r.itemCount,
                          cell: (_, r) =>
                              DesktopCellText('${r.itemCount}', numeric: true),
                        ),
                        DesktopColumn<StockCountSummary>(
                          label: 'Difference',
                          width: 156,
                          numeric: true,
                          sortBy: (r) => r.totalVarianceValue ?? 0,
                          cell: (context, r) {
                            final v = r.totalVarianceValue;
                            if (v == null || v == 0) {
                              return const DesktopCellText('-', muted: true);
                            }
                            return DesktopCellText(
                              '${v < 0 ? 'Missing' : 'Extra'} ${kesWhole(v.abs())}',
                              numeric: true,
                              color: v < 0 ? negativeAmountColor(p) : null,
                            );
                          },
                        ),
                        DesktopColumn<StockCountSummary>(
                          label: 'Started',
                          width: 120,
                          sortBy: (r) => r.createdAt.millisecondsSinceEpoch,
                          cell: (_, r) => DesktopCellText(
                            timeAgo(r.createdAt),
                            muted: true,
                          ),
                        ),
                      ],
                      footer: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${rows.length} ${rows.length == 1 ? 'count' : 'counts'}',
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      empty: const DesktopEmptyState(
                        icon: Icons.fact_check_outlined,
                        title: 'No stock counts yet',
                        message:
                            'Count what is on the shelf and compare it with the system. Do it weekly and losses show up early.',
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One product on the counting sheet.
class DesktopCountLine {
  const DesktopCountLine({
    required this.id,
    required this.name,
    required this.unit,
    required this.controller,
    this.sku,
    this.expected,
  });

  final String id;
  final String name;
  final String unit;
  final String? sku;

  /// Null on a blind count: the counter must not see what the system expects.
  final double? expected;
  final TextEditingController controller;
}

enum DesktopCountShow { toCount, counted, all }

/// The counting sheet: one row per product with the quantity field in the
/// row. Enter or Tab moves to the next product, so a whole shelf can be keyed
/// without the mouse.
class DesktopCountingView extends StatelessWidget {
  const DesktopCountingView({
    super.key,
    required this.title,
    required this.lines,
    required this.counted,
    required this.total,
    required this.show,
    required this.onShow,
    required this.search,
    required this.onSearch,
    required this.onChanged,
    this.expectedHidden = false,
    this.busy = false,
    this.onBack,
    this.onSave,
    this.onHandIn,
  });

  final String title;

  /// Already filtered by [show] and the search text.
  final List<DesktopCountLine> lines;
  final int counted;
  final int total;
  final DesktopCountShow show;
  final ValueChanged<DesktopCountShow> onShow;
  final TextEditingController search;
  final VoidCallback onSearch;
  final ValueChanged<String> onChanged;
  final bool expectedHidden;
  final bool busy;
  final VoidCallback? onBack;
  final VoidCallback? onSave;
  final VoidCallback? onHandIn;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final hasExpected = lines.any((l) => l.expected != null);
    final progress = total == 0 ? 0.0 : counted / total;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (!busy) onSave?.call();
        },
      },
      child: Focus(
        autofocus: true,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopPageHeader(
            title: title,
            subtitle: '$counted of $total counted',
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            leading: onBack == null
                ? null
                : IconButton(
                    tooltip: 'Back to stock counts',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  ),
            actions: [
              OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: busy ? null : onSave,
                child: const Text('Save  (Ctrl+S)'),
              ),
              FilledButton.icon(
                style: desktopPrimaryButton(context),
                onPressed: busy || counted == 0 ? null : onHandIn,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: const Text('Hand in count'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: p.hover,
                color: DesignColors.accent,
              ),
            ),
          ),
          if (expectedHidden)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                decoration: BoxDecoration(
                  color: DesignColors.info.withValues(alpha: p.dark ? 0.16 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_off_outlined,
                        size: 17, color: DesignColors.info),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'System quantities are hidden. Count what is really on the shelf.',
                        style: GoogleFonts.plusJakartaSans(
                          color: p.text,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Row(
              children: [
                DesktopSearchField(
                  controller: search,
                  hint: 'Find an item by name or SKU',
                  width: 320,
                  onChanged: (_) => onSearch(),
                ),
                const SizedBox(width: 14),
                DesktopFilterChip(
                  label: 'To count',
                  count: total - counted,
                  selected: show == DesktopCountShow.toCount,
                  onTap: () => onShow(DesktopCountShow.toCount),
                ),
                const SizedBox(width: 6),
                DesktopFilterChip(
                  label: 'Counted',
                  count: counted,
                  selected: show == DesktopCountShow.counted,
                  onTap: () => onShow(DesktopCountShow.counted),
                ),
                const SizedBox(width: 6),
                DesktopFilterChip(
                  label: 'All',
                  count: total,
                  selected: show == DesktopCountShow.all,
                  onTap: () => onShow(DesktopCountShow.all),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: _surface(p),
                child: Column(
                  children: [
                    _head(p, hasExpected),
                    Divider(height: 1, color: p.border),
                    Expanded(
                      child: lines.isEmpty
                          ? DesktopEmptyState(
                              icon: Icons.task_alt_rounded,
                              title: show == DesktopCountShow.toCount && total > 0
                                  ? 'Everything is counted'
                                  : 'Nothing here',
                              message: show == DesktopCountShow.toCount &&
                                      total > 0
                                  ? 'Hand the count in when you are ready.'
                                  : null,
                            )
                          : ListView.builder(
                              itemExtent: 52,
                              itemCount: lines.length,
                              itemBuilder: (context, i) =>
                                  _row(context, p, lines[i], hasExpected),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _head(DesktopPalette p, bool hasExpected) {
    final style = GoogleFonts.plusJakartaSans(
      color: p.textMuted,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Text('Product', style: style)),
          if (hasExpected)
            SizedBox(
              width: 120,
              child: Text('System', textAlign: TextAlign.right, style: style),
            ),
          SizedBox(
            width: 148,
            child: Text('Counted', textAlign: TextAlign.right, style: style),
          ),
          if (hasExpected)
            SizedBox(
              width: 110,
              child: Text('Difference', textAlign: TextAlign.right, style: style),
            ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    DesktopPalette p,
    DesktopCountLine line,
    bool hasExpected,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DesktopCellText(line.name, strong: true),
                DesktopCellText(
                  [
                    if ((line.sku ?? '').isNotEmpty) line.sku!,
                    line.unit,
                  ].join(' · '),
                  muted: true,
                ),
              ],
            ),
          ),
          if (hasExpected)
            SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerRight,
                child: DesktopCellText(
                  line.expected == null ? '-' : kitNumber(line.expected!),
                  numeric: true,
                  muted: true,
                ),
              ),
            ),
          SizedBox(
            width: 148,
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 108,
                height: 34,
                child: TextField(
                  controller: line.controller,
                  textAlign: TextAlign.right,
                  textInputAction: TextInputAction.next,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) =>
                          RegExp(r'^\d{0,7}(?:\.\d{0,3})?$')
                                  .hasMatch(newValue.text)
                              ? newValue
                              : oldValue,
                    ),
                  ],
                  onChanged: (_) => onChanged(line.id),
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  cursorColor: p.accent,
                  style: DesignType.numeric(
                    fontSize: 14,
                    letterSpacing: 0,
                    color: p.text,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '0',
                    hintStyle: DesignType.numeric(
                      fontSize: 14,
                      letterSpacing: 0,
                      color: p.textFaint,
                    ),
                    filled: true,
                    fillColor: p.dark ? p.panel : p.panelAlt,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: p.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: p.accent, width: 1.4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (hasExpected)
            SizedBox(
              width: 110,
              child: Align(
                alignment: Alignment.centerRight,
                child: _diff(context, p, line),
              ),
            ),
        ],
      ),
    );
  }

  Widget _diff(BuildContext context, DesktopPalette p, DesktopCountLine line) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: line.controller,
      builder: (context, value, _) {
        final entered = double.tryParse(value.text.trim());
        final expected = line.expected;
        if (entered == null || expected == null) {
          return const DesktopCellText('', muted: true);
        }
        final diff = entered - expected;
        if (diff == 0) {
          return const DesktopCellText('0', numeric: true, muted: true);
        }
        return DesktopCellText(
          '${diff > 0 ? '+' : ''}${kitNumber(diff)}',
          numeric: true,
          strong: true,
          color: diff < 0 ? negativeAmountColor(p) : context.readable(DesignColors.success),
        );
      },
    );
  }
}

/// A handed-in count: the money gap, then the products that differ.
class DesktopCountReviewView extends StatelessWidget {
  const DesktopCountReviewView({
    super.key,
    required this.title,
    required this.detail,
    this.canApprove = false,
    this.busy = false,
    this.onBack,
    this.onApprove,
    this.onCancel,
  });

  final String title;
  final StockCountDetail detail;
  final bool canApprove;
  final bool busy;
  final VoidCallback? onBack;
  final VoidCallback? onApprove;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final d = detail;
    final differences = d.items
        .where((l) => l.isCounted && (l.varianceQty ?? 0) != 0)
        .toList()
      ..sort((a, b) => (a.varianceValue ?? 0).compareTo(b.varianceValue ?? 0));
    final status = switch (d.status) {
      'SUBMITTED' =>
        'Handed in${d.submittedByName != null ? ' by ${d.submittedByName}' : ''}. Waiting for approval.',
      'APPROVED' =>
        'Approved${d.approvedByName != null ? ' by ${d.approvedByName}' : ''}. Stock was adjusted.',
      _ => 'This count was cancelled. No stock changed.',
    };
    final short = MediaQuery.sizeOf(context).height < 640;
    final negative = negativeAmountColor(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: title,
          subtitle: status,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          leading: onBack == null
              ? null
              : IconButton(
                  tooltip: 'Back to stock counts',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                ),
          actions: [
            if (d.submitted && canApprove) ...[
              OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: busy ? null : onCancel,
                child: const Text('Cancel count'),
              ),
              FilledButton.icon(
                style: desktopPrimaryButton(context),
                onPressed: busy ? null : onApprove,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_rounded, size: 18),
                label: const Text('Approve & adjust'),
              ),
            ],
          ],
        ),
        if (!d.expectedHidden && !d.cancelled)
          Padding(
            padding: EdgeInsets.fromLTRB(24, short ? 10 : 14, 24, 0),
            child: DesktopFiguresRow(
              dense: short,
              figures: [
                DesktopFigure(
                  label: 'Missing',
                  value: kesWhole(d.lossValue),
                  hint: '${d.shortLines} ${d.shortLines == 1 ? 'item' : 'items'} short',
                  valueColor: d.lossValue > 0 ? negative : null,
                ),
                DesktopFigure(
                  label: 'Extra',
                  value: kesWhole(d.gainValue),
                  hint: '${d.overLines} ${d.overLines == 1 ? 'item' : 'items'} over',
                ),
                DesktopFigure(
                  label: 'Net',
                  value: kesWhole(d.netValue),
                  valueColor: d.netValue < 0 ? negative : null,
                ),
                DesktopFigure(
                  label: 'Counted',
                  value: '${d.countedLines} of ${d.totalLines}',
                  hint: '${d.completionPercent}% done',
                ),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, short ? 10 : 16, 24, 8),
          child: DesktopSectionLabelRow(
            title: 'Differences',
            detail: '${differences.length} of ${d.countedLines} counted',
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: _surface(p),
              child: DesktopDataTable<StockCountLine>(
                rows: differences,
                rowId: (r) => r.productId,
                rowHeight: 48,
                minWidth: 640,
                columns: [
                  DesktopColumn<StockCountLine>(
                    label: 'Product',
                    flex: 3,
                    minWidth: 170,
                    sortBy: (r) => r.productName.toLowerCase(),
                    cell: (_, r) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DesktopCellText(r.productName, strong: true),
                        if ((r.sku ?? '').isNotEmpty)
                          DesktopCellText(r.sku!, muted: true),
                      ],
                    ),
                  ),
                  DesktopColumn<StockCountLine>(
                    label: 'System',
                    width: 96,
                    numeric: true,
                    sortBy: (r) => r.expectedQty ?? 0,
                    cell: (_, r) => DesktopCellText(
                      kitNumber(r.expectedQty ?? 0),
                      numeric: true,
                      muted: true,
                    ),
                  ),
                  DesktopColumn<StockCountLine>(
                    label: 'Counted',
                    width: 96,
                    numeric: true,
                    sortBy: (r) => r.countedQty ?? 0,
                    cell: (_, r) => DesktopCellText(
                      kitNumber(r.countedQty ?? 0),
                      numeric: true,
                    ),
                  ),
                  DesktopColumn<StockCountLine>(
                    label: 'Difference',
                    width: 110,
                    numeric: true,
                    sortBy: (r) => r.varianceQty ?? 0,
                    cell: (context, r) {
                      final v = r.varianceQty ?? 0;
                      return DesktopCellText(
                        '${v > 0 ? '+' : ''}${kitNumber(v)}',
                        numeric: true,
                        strong: true,
                        color: v < 0
                            ? negative
                            : context.readable(DesignColors.success),
                      );
                    },
                  ),
                  DesktopColumn<StockCountLine>(
                    label: 'Value',
                    width: 124,
                    numeric: true,
                    sortBy: (r) => r.varianceValue ?? 0,
                    cell: (_, r) => DesktopCellText(
                      kesWhole(r.varianceValue ?? 0),
                      numeric: true,
                    ),
                  ),
                  DesktopColumn<StockCountLine>(
                    label: 'Counted by',
                    flex: 1,
                    minWidth: 110,
                    cell: (_, r) =>
                        DesktopCellText(r.countedByName ?? '', muted: true),
                  ),
                ],
                empty: const DesktopEmptyState(
                  icon: Icons.verified_rounded,
                  title: 'Everything counted matched the system',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A small "Title  ·  detail" line above a table.
class DesktopSectionLabelRow extends StatelessWidget {
  const DesktopSectionLabelRow({
    super.key,
    required this.title,
    this.detail,
  });

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: GoogleFonts.sora(
            color: p.text,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(width: 10),
          Text(
            detail!,
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
