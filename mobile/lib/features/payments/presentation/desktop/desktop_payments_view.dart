import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../../finance/presentation/desktop/desktop_figures_row.dart';
import '../../../sales/presentation/receipts_desktop/receipt_format.dart';

/// One payment taken today: a completed sale and how it was paid.
class DesktopPaymentRow {
  const DesktopPaymentRow({
    required this.saleId,
    required this.receiptNumber,
    required this.at,
    required this.method,
    required this.amount,
    this.reference,
    this.recorded = false,
    this.checked = false,
    this.checkedBy,
    this.checkedAt,
    this.checkNote,
    this.recordedBy,
    this.tenders = const [],
  });

  final String saleId;
  final String receiptNumber;
  final DateTime at;

  /// The sale's payment method code (CASH, MPESA, MPESA_RECORDED, SPLIT...).
  final String method;
  final double amount;

  /// The M-Pesa or bank code, or a card reference.
  final String? reference;

  /// The shop typed this payment in itself (an M-Pesa or bank code to check
  /// against the statement), so Counterbase cannot confirm it.
  final bool recorded;
  final bool checked;
  final String? checkedBy;
  final DateTime? checkedAt;
  final String? checkNote;
  final String? recordedBy;

  /// The parts of a split payment.
  final List<({String method, double amount})> tenders;

  bool get unmatched => recorded && !checked;
  String get methodKey => receiptMethodKey(method);

  /// This payment includes money of the given kind: 'CASH', 'MPESA' or 'CARD'.
  bool has(String kind) {
    bool is_(String key) {
      switch (kind) {
        case 'MPESA':
          return key == 'MPESA' || key == 'MPESARECORDED';
        case 'CARD':
          return key == 'CARD' || key == 'PESAPAL' || key == 'TOURISTTAP';
        default:
          return key == kind;
      }
    }

    if (tenders.isNotEmpty) {
      return tenders.any((t) => is_(receiptMethodKey(t.method)));
    }
    return is_(methodKey);
  }
}

/// An M-Pesa request that has not finished (cloud shops): waiting, needs
/// review, settling.
class DesktopPendingCharge {
  const DesktopPendingCharge({
    required this.reference,
    required this.amount,
    required this.status,
  });

  final String reference;
  final String amount;
  final String status;
}

/// A page the toolbar can jump to (Receipts, Analytics, Payout account).
class DesktopPaymentLink {
  const DesktopPaymentLink({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

enum DesktopPaymentTab { all, mpesa, cash, card, unmatched }

/// The Payments page on a computer: today's takings as a strip of figures, a
/// table of every payment with tabs by method, and an inspector for the one
/// picked. Unmatched payments (M-Pesa or bank codes the shop typed in) can be
/// sent to the statement check from the inspector.
///
/// It takes plain rows; the routed screen owns loading and the actions.
class DesktopPaymentsView extends StatefulWidget {
  const DesktopPaymentsView({
    super.key,
    required this.title,
    required this.payments,
    required this.totalToday,
    required this.inspectorBuilder,
    this.links = const [],
    this.pendingCharges = const [],
    this.onCheckCharge,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    this.footnote,
    this.restrictedMessage,
    this.methodsAvailable = const [],
    this.initialSelectedId,
  });

  final String title;
  final List<DesktopPaymentRow> payments;

  /// Today's sales total for the shop (on a cloud shop it covers every
  /// device, so it can be more than the rows add up to).
  final double totalToday;
  final Widget Function(
    BuildContext context,
    DesktopPaymentRow row,
    VoidCallback close,
  ) inspectorBuilder;
  final List<DesktopPaymentLink> links;
  final List<DesktopPendingCharge> pendingCharges;
  final ValueChanged<String>? onCheckCharge;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onRefresh;

  /// Shown under the title ("Figures include sales saved on this computer
  /// only"). Falls back to "Today's takings".
  final String? footnote;

  /// Set for a role that may not see takings: the page explains instead.
  final String? restrictedMessage;
  final List<String> methodsAvailable;
  final String? initialSelectedId;

  @override
  State<DesktopPaymentsView> createState() => _DesktopPaymentsViewState();
}

class _DesktopPaymentsViewState extends State<DesktopPaymentsView> {
  DesktopPaymentTab _tab = DesktopPaymentTab.all;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedId;
  }

  bool _inTab(DesktopPaymentRow r, DesktopPaymentTab tab) {
    switch (tab) {
      case DesktopPaymentTab.all:
        return true;
      case DesktopPaymentTab.mpesa:
        return r.has('MPESA');
      case DesktopPaymentTab.cash:
        return r.has('CASH');
      case DesktopPaymentTab.card:
        return r.has('CARD');
      case DesktopPaymentTab.unmatched:
        return r.unmatched;
    }
  }

  int _count(DesktopPaymentTab tab) =>
      widget.payments.where((r) => _inTab(r, tab)).length;

  void _select(DesktopPaymentRow? row) =>
      setState(() => _selectedId = row?.saleId);

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final w = widget;
    final rows = w.payments.where((r) => _inTab(r, _tab)).toList();
    final selected = w.payments.where((r) => r.saleId == _selectedId).firstOrNull;
    final inspector = selected == null
        ? null
        : w.inspectorBuilder(context, selected, () => _select(null));

    return LayoutBuilder(builder: (context, outer) {
    // A laptop at 125% display scaling leaves about 500px: drop the figure
    // hints so the table keeps its rows.
    final short = outer.maxHeight < 620;
    return CallbackShortcuts(
      bindings: {
        if (w.onRefresh != null)
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              w.onRefresh!,
        if (selected != null)
          const SingleActivator(LogicalKeyboardKey.escape): () => _select(null),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: w.title,
              subtitle: w.footnote ?? "Today's takings",
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              actions: [
                if (w.onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh (Ctrl+R)',
                    onPressed: w.onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                for (final link in w.links.take(2))
                  OutlinedButton.icon(
                    style: desktopSecondaryButton(context),
                    onPressed: link.onTap,
                    icon: Icon(link.icon, size: 17),
                    label: Text(link.label),
                  ),
                if (w.links.length > 2)
                  PopupMenuButton<int>(
                    tooltip: 'More',
                    position: PopupMenuPosition.under,
                    onSelected: (i) => w.links[i].onTap(),
                    itemBuilder: (context) => [
                      for (var i = 2; i < w.links.length; i++)
                        PopupMenuItem(value: i, child: Text(w.links[i].label)),
                    ],
                    icon: const Icon(Icons.more_horiz_rounded, size: 20),
                  ),
              ],
            ),
            Expanded(
              child: w.restrictedMessage != null
                  ? _restricted(context)
                  : DesktopInspectorLayout(
                      inspectorWidth: 380,
                      onClose: () => _select(null),
                      inspector: inspector,
                      main: Padding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          0,
                          inspector == null ? 24 : 16,
                          16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _strip(context, dense: short),
                            const SizedBox(height: 12),
                            if (w.pendingCharges.isNotEmpty) ...[
                              _PendingCharges(
                                charges: w.pendingCharges,
                                onCheck: w.onCheckCharge,
                              ),
                              const SizedBox(height: 10),
                            ],
                            _tabs(context),
                            const SizedBox(height: 10),
                            Expanded(
                              child: Container(
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: p.dark ? p.panelAlt : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: p.border),
                                ),
                                child: _body(context, rows),
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
    });
  }

  Widget _restricted(BuildContext context) {
    final p = context.desktop;
    return DesktopEmptyState(
      icon: Icons.lock_outline_rounded,
      title: 'Takings are not shown to your role',
      message: widget.restrictedMessage,
      action: widget.methodsAvailable.isEmpty
          ? null
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final m in widget.methodsAvailable)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: ShapeDecoration(
                      shape: StadiumBorder(side: BorderSide(color: p.border)),
                    ),
                    child: Text(
                      m,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _strip(BuildContext context, {bool dense = false}) {
    final sums = <String, double>{};
    final counts = <String, int>{};
    void add(String bucket, double amount) {
      sums[bucket] = (sums[bucket] ?? 0) + amount;
    }

    String bucketOf(String key) {
      if (key == 'CASH') return 'cash';
      if (key == 'MPESA' || key == 'MPESARECORDED') return 'mpesa';
      if (key == 'CARD' || key == 'PESAPAL' || key == 'TOURISTTAP') {
        return 'card';
      }
      return 'other';
    }

    for (final r in widget.payments) {
      final seen = <String>{};
      if (r.tenders.isNotEmpty) {
        for (final t in r.tenders) {
          final bucket = bucketOf(receiptMethodKey(t.method));
          add(bucket, t.amount);
          seen.add(bucket);
        }
      } else {
        final bucket = bucketOf(r.methodKey);
        add(bucket, r.amount);
        seen.add(bucket);
      }
      for (final bucket in seen) {
        counts[bucket] = (counts[bucket] ?? 0) + 1;
      }
    }
    String hint(int n) => '$n ${n == 1 ? 'payment' : 'payments'}';
    final n = widget.payments.length;
    final cells = <({String label, String value, String hint})>[
      (
        label: 'Sales today',
        value: widget.loading ? '...' : formatMoney(widget.totalToday),
        hint: hint(n),
      ),
      for (final c in const [
        ('cash', 'Cash'),
        ('mpesa', 'M-Pesa'),
        ('card', 'Card'),
        ('other', 'Credit, other'),
      ])
        (
          label: c.$2,
          value: formatMoney(sums[c.$1] ?? 0),
          hint: hint(counts[c.$1] ?? 0),
        ),
    ];
    return DesktopFiguresRow(
      dense: dense,
      figures: [
        for (final c in cells)
          DesktopFigure(label: c.label, value: c.value, hint: c.hint),
      ],
    );
  }

  Widget _tabs(BuildContext context) {
    final recorded = widget.payments.any((r) => r.recorded);
    Widget chip(String label, DesktopPaymentTab tab) => DesktopFilterChip(
          label: label,
          count: _count(tab),
          selected: _tab == tab,
          onTap: () => setState(() => _tab = tab),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('All', DesktopPaymentTab.all),
        chip('M-Pesa', DesktopPaymentTab.mpesa),
        chip('Cash', DesktopPaymentTab.cash),
        chip('Card', DesktopPaymentTab.card),
        if (recorded) chip('Unmatched', DesktopPaymentTab.unmatched),
      ],
    );
  }

  Widget _body(BuildContext context, List<DesktopPaymentRow> rows) {
    final w = widget;
    if (w.errorMessage != null && w.payments.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load payments",
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
    if (rows.isEmpty && !w.loading) return _empty(context);

    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 780;
        final p = context.desktop;
        final columns = <DesktopColumn<DesktopPaymentRow>>[
          DesktopColumn<DesktopPaymentRow>(
            label: 'Time',
            width: compact ? 76 : 84,
            sortBy: (r) => r.at,
            cell: (context, r) => DesktopCellText(_time(r.at), muted: true),
          ),
          DesktopColumn<DesktopPaymentRow>(
            label: 'Receipt',
            width: compact ? 104 : 112,
            sortBy: (r) => r.receiptNumber,
            cell: (context, r) =>
                DesktopCellText('#${r.receiptNumber}', strong: true),
          ),
          DesktopColumn<DesktopPaymentRow>(
            label: 'Method',
            width: compact ? 150 : 164,
            sortBy: (r) => paymentMethodLabel(r.method),
            cell: (context, r) => DesktopStatusChip(
              label: paymentMethodLabel(r.method),
              color: receiptMethodColor(r.method),
            ),
          ),
          if (!compact)
            DesktopColumn<DesktopPaymentRow>(
              label: 'Reference',
              flex: 2,
              minWidth: 120,
              sortBy: (r) => r.reference ?? '',
              cell: (context, r) => DesktopCellText(
                r.reference == null || r.reference!.isEmpty
                    ? '—'
                    : r.reference!,
                muted: true,
              ),
            ),
          DesktopColumn<DesktopPaymentRow>(
            label: 'Amount',
            width: compact ? 112 : 116,
            numeric: true,
            sortBy: (r) => r.amount,
            cell: (context, r) =>
                DesktopCellText(formatMoney(r.amount), numeric: true),
          ),
          DesktopColumn<DesktopPaymentRow>(
            label: 'Status',
            width: compact ? 118 : 120,
            sortBy: (r) => r.unmatched ? 0 : 1,
            cell: (context, r) {
              if (r.unmatched) {
                return const DesktopStatusChip(
                  label: 'Unmatched',
                  color: DesignColors.warning,
                );
              }
              if (r.recorded) {
                return const DesktopStatusChip(
                  label: 'Checked',
                  color: DesignColors.success,
                );
              }
              return DesktopCellText('Confirmed', muted: true, color: p.textMuted);
            },
          ),
        ];
        var total = 0.0;
        for (final r in rows) {
          total += r.amount;
        }
        return DesktopDataTable<DesktopPaymentRow>(
          columns: columns,
          rows: rows,
          rowId: (r) => r.saleId,
          rowHeight: 46,
          minWidth: compact ? 560 : 760,
          loading: w.loading,
          initialSortColumn: 0,
          initialSortAscending: false,
          selectedId: _selectedId,
          onRowSelected: _select,
          footer: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                Text(
                  '${formatMoney(rows.length, symbol: '')} '
                  '${rows.length == 1 ? 'payment' : 'payments'}',
                  style: _footStyle(p),
                ),
                const Spacer(),
                Text('Total', style: _footStyle(p)),
                const SizedBox(width: 8),
                Text(
                  formatMoney(total, decimals: true),
                  style: DesignType.numeric(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  TextStyle _footStyle(DesktopPalette p) => GoogleFonts.plusJakartaSans(
        color: p.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );

  String _time(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  Widget _empty(BuildContext context) {
    if (widget.payments.isNotEmpty) {
      final unmatched = _tab == DesktopPaymentTab.unmatched;
      return DesktopEmptyState(
        icon: unmatched
            ? Icons.check_circle_outline_rounded
            : Icons.search_off_rounded,
        title: unmatched
            ? 'Every recorded payment is checked'
            : 'No payments in this tab today',
        message: unmatched
            ? 'M-Pesa and bank codes you typed in all match your statement or '
                'carry a note.'
            : 'Switch to All to see every payment taken today.',
        action: unmatched
            ? null
            : OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: () => setState(() => _tab = DesktopPaymentTab.all),
                child: const Text('Show all'),
              ),
      );
    }
    return const DesktopEmptyState(
      icon: Icons.payments_outlined,
      title: 'No payments yet today',
      message: 'Cash, M-Pesa, card and credit sales appear here the moment '
          'they are taken, with a reference you can check.',
    );
  }
}

/// M-Pesa requests that have not finished: check them before asking again.
class _PendingCharges extends StatelessWidget {
  const _PendingCharges({required this.charges, required this.onCheck});

  final List<DesktopPendingCharge> charges;
  final ValueChanged<String>? onCheck;

  String _status(String s) => switch (s) {
        'PENDING' => 'Waiting for the customer',
        'NEEDS_REVIEW' => 'Needs review',
        'SETTLING' => 'Settling',
        'COMPLETED' => 'Confirmed',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final shown = charges.take(3).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: p.dark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(
              'M-Pesa payments to check. Review these before asking for '
              'another payment.',
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final c in shown)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'KES ${c.amount}  ·  ${_status(c.status)}  ·  ${c.reference}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  style: desktopLinkButton(context),
                  onPressed: onCheck == null || c.reference.isEmpty
                      ? null
                      : () => onCheck!(c.reference),
                  child: const Text('Check'),
                ),
              ],
            ),
          if (charges.length > shown.length)
            Text(
              'and ${charges.length - shown.length} more',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}
