import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../widgets/home_cards.dart';
import 'desktop_bar_chart.dart';
import 'desktop_home_models.dart';
import 'desktop_segmented_control.dart';

/// The computer version of Home: a header with the period switch, one strip of
/// key figures, a sales chart beside what needs attention, then recent sales
/// beside the best sellers. Takes plain data; the routed screen feeds it from
/// the same providers the phone Home reads.
class DesktopHomeView extends StatefulWidget {
  const DesktopHomeView({
    super.key,
    required this.data,
    required this.updatedAt,
    required this.onRangeChanged,
    required this.onRefresh,
    required this.onOpen,
    this.onAdjustProfit,
    this.onRetry,
    this.footer,
  });

  final DesktopHomeData data;

  /// When the figures were last read, for "Updated 10:42".
  final DateTime updatedAt;
  final ValueChanged<HomeRange> onRangeChanged;
  final VoidCallback onRefresh;

  /// Go to a page: `/receipts`, `/receipt/<id>`, `/mpesa-match`, `/` (Sell).
  final ValueChanged<String> onOpen;
  final VoidCallback? onAdjustProfit;
  final VoidCallback? onRetry;

  /// Lower-priority extras (the daily brief, the invite-staff nudge).
  final Widget? footer;

  /// Below this content width the two-column rows stack into one column.
  static const double stackBelow = 880;

  /// Content never grows past this on a wide monitor.
  static const double maxContentWidth = 1600;

  @override
  State<DesktopHomeView> createState() => _DesktopHomeViewState();
}

class _DesktopHomeViewState extends State<DesktopHomeView> {
  Object? _selectedSale;

  static const double _rowHeight = DesktopTokens.compactRowHeight;
  static const double _tableHeader = 37;
  static const double _tableFooter = 41;
  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final data = widget.data;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            widget.onRefresh,
      },
      child: Focus(
        autofocus: true,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth:
                  DesktopHomeView.maxContentWidth + 2 * DesktopTokens.gutter,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, p),
                Expanded(
                  child: data.error != null
                      ? _errorBody(context)
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(
                            DesktopTokens.gutter,
                            0,
                            DesktopTokens.gutter,
                            DesktopTokens.gutter,
                          ),
                          child: _body(context, p),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────

  Widget _header(BuildContext context, DesktopPalette p) {
    final data = widget.data;
    final now = DateTime.now();
    final subtitle = switch (data.range) {
      HomeRange.today => DateFormat('EEEE d MMMM').format(now),
      _ =>
        '${DateFormat('d MMM').format(now.subtract(Duration(days: data.range.days - 1)))} to ${DateFormat('d MMM').format(now)}',
    };
    return DesktopPageHeader(
      title: 'Home',
      subtitle: subtitle,
      padding: const EdgeInsets.fromLTRB(
        DesktopTokens.gutter,
        16,
        DesktopTokens.gutter,
        14,
      ),
      actions: [
        SegmentedRangeControl<HomeRange>(
          semanticLabel: 'Period',
          selected: data.range,
          onChanged: widget.onRangeChanged,
          options: [
            for (final range in HomeRange.values)
              SegmentedOption(range, range.label),
          ],
        ),
        Tooltip(
          message: 'Refresh (Ctrl+R)',
          child: TextButton.icon(
            onPressed: widget.onRefresh,
            icon: Icon(Icons.refresh_rounded, size: 16, color: p.textMuted),
            label: Text(
              'Updated ${DateFormat('HH:mm').format(widget.updatedAt)} · Refresh (Ctrl+R)',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () => widget.onOpen('/'),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Start a sale'),
        ),
      ],
    );
  }

  Widget _errorBody(BuildContext context) {
    final data = widget.data;
    return DesktopEmptyState(
      icon: Icons.error_outline_rounded,
      title: "Couldn't load the figures",
      message: data.error,
      action: widget.onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: widget.onRetry,
              style: _outlineStyle(context.desktop),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────

  Widget _body(BuildContext context, DesktopPalette p) {
    final data = widget.data;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= DesktopHomeView.stackBelow;
        final chartPanel = _chartPanel(context, p, fixedHeight: wide);
        final attentionPanel = _attentionPanel(context, p, fixedHeight: wide);
        final salesPanel = _salesPanel(context, p);
        final productsPanel = _productsPanel(context, p);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (data.deviceOnly) ...[
              _deviceNote(context, p),
              const SizedBox(height: 12),
            ],
            if (data.showFigures) ...[
              _metricStrip(context, p),
              const SizedBox(height: _gap),
            ],
            if (wide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 8, child: chartPanel),
                    const SizedBox(width: _gap),
                    Expanded(flex: 4, child: attentionPanel),
                  ],
                ),
              )
            else ...[
              chartPanel,
              const SizedBox(height: _gap),
              attentionPanel,
            ],
            if (data.showRecentSales) ...[
              const SizedBox(height: _gap),
              if (wide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 8, child: salesPanel),
                      const SizedBox(width: _gap),
                      Expanded(flex: 4, child: productsPanel),
                    ],
                  ),
                )
              else ...[
                salesPanel,
                const SizedBox(height: _gap),
                productsPanel,
              ],
            ],
            if (widget.footer != null) ...[
              const SizedBox(height: _gap),
              widget.footer!,
            ],
          ],
        );
      },
    );
  }

  Widget _deviceNote(BuildContext context, DesktopPalette p) {
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: p.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Showing sales saved on this computer. Sales from other devices may be missing.',
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  // ── Key figures ───────────────────────────────────────────────────

  Widget _metricStrip(BuildContext context, DesktopPalette p) {
    final data = widget.data;
    final loading = data.loading;
    String money(num value) => loading ? '—' : formatMoney(value);

    final revenue = data.revenue;
    final split = data.split;
    final cashShare = revenue > 0 && !loading
        ? '${(split.cash / revenue * 100).round()}% of sales'
        : null;

    final cost = data.cost;
    final DesktopMetric fifth;
    if (data.range == HomeRange.today && data.showProfit) {
      final hasCost = cost != null && cost > 0;
      fifth = DesktopMetric(
        label: hasCost || data.costLoading ? 'Profit' : 'Profit (no cost yet)',
        value: data.costLoading || cost == null || loading
            ? '—'
            : formatMoney(revenue - cost),
        hint: data.costLoading || loading
            ? null
            : hasCost
                ? 'Cost ${formatMoney(cost)}'
                : data.canAdjustCost
                    ? "Enter today's stock cost"
                    : 'Needs the stock cost',
        hintColor: hasCost || data.costLoading ? null : p.accent,
        onTap: data.canAdjustCost && !data.costLoading
            ? widget.onAdjustProfit
            : null,
      );
    } else {
      fifth = DesktopMetric(
        label: 'Average sale',
        value: money(data.avgTicket),
        hint: loading ? null : '${_items(data.itemsSold)} sold',
        onTap: () => widget.onOpen('/reports'),
      );
    }

    return DesktopMetricStrip(
      metrics: [
        DesktopMetric(
          label: 'Sales',
          value: money(revenue),
          hint: loading
              ? null
              : data.transactions == 0
                  ? 'No sales yet'
                  : '${data.transactions} ${data.transactions == 1 ? 'sale' : 'sales'} · avg ${formatMoney(data.avgTicket)}',
          onTap: () => widget.onOpen('/receipts'),
        ),
        DesktopMetric(
          label: 'Cash',
          value: money(split.cash),
          hint: cashShare,
          onTap: () => widget.onOpen('/cash-flow'),
        ),
        DesktopMetric(
          label: 'M-Pesa or bank',
          value: money(split.recorded),
          hint: loading
              ? null
              : split.recordedCount > 0
                  ? '${split.recordedCount} to match'
                  : 'Recorded payments',
          hintColor: split.recordedCount > 0 && !loading ? p.accent : null,
          onTap: () => widget.onOpen('/mpesa-match'),
        ),
        DesktopMetric(
          label: 'On credit',
          value: money(split.credit),
          hint: loading ? null : 'Owed to you',
          onTap: () => widget.onOpen('/customers'),
        ),
        fifth,
      ],
    );
  }

  static String _items(double items) {
    final whole = items == items.roundToDouble();
    final text = whole ? items.round().toString() : items.toStringAsFixed(1);
    return '$text ${items == 1 ? 'item' : 'items'}';
  }

  // ── Chart ─────────────────────────────────────────────────────────

  Widget _chartPanel(
    BuildContext context,
    DesktopPalette p, {
    required bool fixedHeight,
  }) {
    final data = widget.data;
    final today = data.range == HomeRange.today;
    final title = today ? 'Sales by hour' : 'Sales by day';

    String? subtitle;
    if (!data.loading && data.hasSales && data.bars.isNotEmpty) {
      var best = data.bars.first;
      for (final bar in data.bars) {
        if (bar.value > best.value) best = bar;
      }
      if (best.value > 0) {
        subtitle =
            'Busiest ${today ? 'hour' : 'day'}: ${best.tooltipTitle.split(' to ').first} · ${formatMoney(best.value)}'
            '${data.itemsSold > 0 ? ' · ${_items(data.itemsSold)} sold' : ''}';
      }
    }
    subtitle ??= today ? 'Takings through the day' : 'Takings per day';

    const chartHeight = 232.0;
    final Widget body;
    if (data.loading) {
      body = const _ChartSkeleton();
    } else if (!data.hasSales) {
      body = _firstSteps(context, p, today: today);
    } else {
      body = DesktopBarChart(
        bars: data.bars,
        height: chartHeight,
        semanticLabel: '$title chart',
      );
    }

    return DesktopPanel(
      title: title,
      subtitle: subtitle,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SizedBox(height: chartHeight, child: body),
    );
  }

  /// The empty shop: what Home is for and the first two things to do.
  Widget _firstSteps(
    BuildContext context,
    DesktopPalette p, {
    required bool today,
  }) {
    return _CompactEmpty(
      icon: Icons.storefront_outlined,
      title: today
          ? 'No sales yet today'
          : 'No sales in ${widget.data.range.phrase}',
      message:
          'Ring up a sale and your takings show here, hour by hour. If the shop is new, add your products first.',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () => widget.onOpen('/'),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Start a sale'),
          ),
          OutlinedButton(
            onPressed: () => widget.onOpen('/products'),
            style: _outlineStyle(p),
            child: const Text('Add products'),
          ),
        ],
      ),
    );
  }

  // ── Needs attention ───────────────────────────────────────────────

  Widget _attentionPanel(
    BuildContext context,
    DesktopPalette p, {
    required bool fixedHeight,
  }) {
    final data = widget.data;
    final open = data.attention
        .where((i) => i.level != HomeAttentionLevel.ok)
        .toList(growable: false);

    final Widget list;
    if (open.isEmpty) {
      list = _AttentionRow(
        item: HomeAttentionItem(
          id: 'clear',
          level: data.attentionLoaded
              ? HomeAttentionLevel.ok
              : HomeAttentionLevel.info,
          title: data.attentionLoaded
              ? 'Nothing needs your attention'
              : 'Checking the shop',
          detail: data.attentionLoaded
              ? 'No odd sales, voids or payments waiting to be checked.'
              : 'Alerts will show here as soon as they load.',
        ),
        onOpen: widget.onOpen,
      );
    } else {
      list = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in open)
            _AttentionRow(item: item, onOpen: widget.onOpen),
        ],
      );
    }

    return DesktopPanel(
      title: 'Needs attention',
      subtitle: open.isEmpty
          ? 'All clear'
          : '${open.length} ${open.length == 1 ? 'thing' : 'things'} to look at',
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: fixedHeight
          ? SizedBox(
              height: 232 + 4,
              child: SingleChildScrollView(child: list),
            )
          : list,
    );
  }

  // ── Recent sales ──────────────────────────────────────────────────

  Widget _salesPanel(BuildContext context, DesktopPalette p) {
    final data = widget.data;
    final today = data.range == HomeRange.today;
    final shown = data.sales.take(10).toList(growable: false);
    final visibleRows = data.loading
        ? 8
        : shown.isEmpty
            ? 5
            : shown.length.clamp(5, 10);
    final tableHeight = _tableHeader + visibleRows * _rowHeight + _tableFooter;

    final timeFormat =
        today ? DateFormat('h:mm a') : DateFormat('d MMM, h:mm a');

    Widget open(HomeSaleRow row, Widget child, {bool right = false}) {
      return _CellTap(
        onTap: () => widget.onOpen('/receipt/${row.id}'),
        alignment: right ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      );
    }

    final columns = <DesktopColumn<HomeSaleRow>>[
      DesktopColumn(
        label: 'Receipt',
        flex: 3,
        minWidth: 120,
        cell: (c, r) => open(r, DesktopCellText(r.receiptNumber, strong: true)),
      ),
      DesktopColumn(
        label: 'Time',
        width: today ? 92 : 150,
        cell: (c, r) => open(
          r,
          DesktopCellText(timeFormat.format(r.createdAt.toLocal()),
              muted: true),
        ),
      ),
      DesktopColumn(
        label: 'Paid with',
        flex: 3,
        minWidth: 130,
        cell: (c, r) => open(r, _PaidWith(row: r)),
      ),
      DesktopColumn(
        label: 'Total',
        width: 110,
        numeric: true,
        sortBy: (r) => r.total,
        cell: (c, r) => open(
          r,
          DesktopCellText(formatMoney(r.total), numeric: true, strong: true),
          right: true,
        ),
      ),
    ];

    return DesktopPanel(
      title: 'Recent sales',
      subtitle: today ? "Today's transactions" : 'In ${data.range.phrase}',
      trailing: TextButton(
        onPressed: () => widget.onOpen('/receipts'),
        style: _linkStyle(p),
        child: const Text('All receipts'),
      ),
      padding: const EdgeInsets.only(top: 8),
      clip: true,
      child: SizedBox(
        height: tableHeight,
        child: DesktopDataTable<HomeSaleRow>(
          columns: columns,
          rows: shown,
          rowId: (r) => r.id,
          loading: data.loading,
          rowHeight: _rowHeight,
          minWidth: 460,
          selectedId: _selectedSale,
          onRowSelected: (r) => setState(() => _selectedSale = r.id),
          onRowActivated: (r) => widget.onOpen('/receipt/${r.id}'),
          empty: const _CompactEmpty(
            icon: Icons.receipt_long_outlined,
            title: 'No sales to list yet',
            message:
                'Each sale you ring up appears here with the time and how it was paid.',
          ),
          footer: _TableNote(
            text: shown.isEmpty
                ? 'Nothing sold in this period'
                : 'Showing ${shown.length} of ${data.salesCount > shown.length ? data.salesCount : shown.length}'
                    ' · Enter opens the selected receipt',
          ),
        ),
      ),
    );
  }

  // ── Best sellers ──────────────────────────────────────────────────

  Widget _productsPanel(BuildContext context, DesktopPalette p) {
    final data = widget.data;
    final shown = data.topProducts.take(8).toList(growable: false);
    final visibleRows =
        data.loading ? 8 : data.sales.take(10).length.clamp(5, 10);
    final tableHeight = _tableHeader + visibleRows * _rowHeight + _tableFooter;

    final columns = <DesktopColumn<HomeProductRow>>[
      DesktopColumn(
        label: 'Product',
        flex: 3,
        minWidth: 110,
        cell: (c, r) => Tooltip(
          message: r.name,
          child: DesktopCellText(r.name, strong: true),
        ),
      ),
      DesktopColumn(
        label: 'Units',
        width: 64,
        numeric: true,
        cell: (c, r) => DesktopCellText(_qty(r.quantity), numeric: true),
      ),
      DesktopColumn(
        label: 'Sales',
        width: 104,
        numeric: true,
        cell: (c, r) => DesktopCellText(formatMoney(r.revenue),
            numeric: true, strong: true),
      ),
    ];

    return DesktopPanel(
      title: 'Top products',
      subtitle: data.range == HomeRange.today
          ? 'Most sold today'
          : 'Most sold in ${data.range.phrase}',
      padding: const EdgeInsets.only(top: 8),
      clip: true,
      child: SizedBox(
        height: tableHeight,
        child: DesktopDataTable<HomeProductRow>(
          columns: columns,
          rows: shown,
          rowId: (r) => r.name,
          loading: data.loading,
          rowHeight: _rowHeight,
          minWidth: 280,
          empty: const _CompactEmpty(
            icon: Icons.star_outline_rounded,
            title: 'No best sellers yet',
            message: 'Your most sold products rank here after the first sales.',
          ),
          footer: const _TableNote(text: 'Ranked by units sold'),
        ),
      ),
    );
  }

  static String _qty(double qty) => qty == qty.roundToDouble()
      ? qty.round().toString()
      : qty.toStringAsFixed(1);
}

// ── Small parts ─────────────────────────────────────────────────────

/// A quiet text link: deep orange on light, the accent on dark.
ButtonStyle _linkStyle(DesktopPalette p) => TextButton.styleFrom(
      foregroundColor: p.accent,
      textStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );

/// A secondary button: ink text, hairline border. Orange stays for the one
/// primary action on the page.
ButtonStyle _outlineStyle(DesktopPalette p) => OutlinedButton.styleFrom(
      foregroundColor: p.text,
      minimumSize: const Size(64, DesktopTokens.controlHeight),
      side: BorderSide(color: p.borderStrong),
      textStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    );

/// A short "nothing here yet" for spots that are only a few rows tall, where
/// the kit's full-size empty state would not fit.
class _CompactEmpty extends StatelessWidget {
  const _CompactEmpty({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: p.textMuted),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.sora(
                    color: p.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 14), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TableNote extends StatelessWidget {
  const _TableNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return SizedBox(
      height: 40,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Makes a whole table cell clickable, not only its text. It listens to the
/// raw pointer instead of joining the gesture arena: the table row also
/// listens for double-clicks, and the arena would hold a plain click back for
/// the double-click timeout.
class _CellTap extends StatefulWidget {
  const _CellTap({
    required this.onTap,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  final VoidCallback onTap;
  final Widget child;
  final Alignment alignment;

  @override
  State<_CellTap> createState() => _CellTapState();
}

class _CellTapState extends State<_CellTap> {
  Offset? _down;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _down = e.position,
        onPointerUp: (e) {
          final down = _down;
          _down = null;
          if (down != null && (e.position - down).distance < 10) {
            widget.onTap();
          }
        },
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Align(alignment: widget.alignment, child: widget.child),
        ),
      ),
    );
  }
}

class _PaidWith extends StatelessWidget {
  const _PaidWith({required this.row});

  final HomeSaleRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final method = row.paymentMethod.toUpperCase();
    final color = switch (method) {
      'CASH' => kCashColor,
      'MPESA_RECORDED' || 'BANK_RECORDED' => kRecordedColor,
      'CREDIT' => kCreditColor,
      _ => kOtherColor,
    };
    final status = row.status.toUpperCase();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            paymentMethodLabel(row.paymentMethod),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: p.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (status != 'COMPLETED') ...[
          const SizedBox(width: 8),
          DesktopStatusChip(
            label: switch (status) {
              'VOIDED' => 'Voided',
              'REFUNDED' => 'Refunded',
              'FAILED' => 'Failed',
              'CANCELLED' => 'Cancelled',
              'PENDING' => 'Pending',
              _ => status[0] + status.substring(1).toLowerCase(),
            },
            color:
                status == 'PENDING' ? DesignColors.warning : DesignColors.error,
          ),
        ],
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item, required this.onOpen});

  final HomeAttentionItem item;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final color = switch (item.level) {
      HomeAttentionLevel.ok => DesignColors.success,
      HomeAttentionLevel.info => DesignColors.info,
      HomeAttentionLevel.warning => DesignColors.warning,
      HomeAttentionLevel.serious => DesignColors.error,
    };
    final path = item.path;
    return Semantics(
      button: path != null,
      label: item.title,
      child: InkWell(
        onTap: path == null ? null : () => onOpen(path),
        hoverColor: p.hover,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: p.dark ? 0.18 : 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    switch (item.level) {
                      HomeAttentionLevel.ok => Icons.check_rounded,
                      HomeAttentionLevel.info => Icons.info_outline_rounded,
                      HomeAttentionLevel.warning => Icons.priority_high_rounded,
                      HomeAttentionLevel.serious => Icons.error_outline_rounded,
                    },
                    size: 16,
                    color: p.text,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.detail != null)
                        Text(
                          item.detail!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                    ],
                  ),
                ),
                if (path != null)
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: p.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet placeholder bars while the first read is in flight.
class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    const heights = [
      0.25,
      0.4,
      0.3,
      0.55,
      0.7,
      0.45,
      0.6,
      0.35,
      0.5,
      0.3,
      0.2,
      0.15
    ];
    return Semantics(
      label: 'Loading sales',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(46, 8, 0, 26),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final h in heights)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: FractionallySizedBox(
                    heightFactor: h,
                    alignment: Alignment.bottomCenter,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: p.hover,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
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
}
