import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import 'desktop_figures_row.dart';

/// One line of the cash ledger: money in is positive, money out is negative.
class CashLedgerLine {
  const CashLedgerLine(this.label, this.amount, {this.note});

  final String label;
  final double amount;
  final String? note;
}

/// The Cash flow page on a computer: the day's cash figures in a strip, an
/// accounting-style ledger with a total, and a side panel (till count or the
/// calculation mode). Plain data in; the routed screen reads the providers.
class DesktopCashFlowView extends StatelessWidget {
  const DesktopCashFlowView({
    super.key,
    required this.title,
    required this.figures,
    required this.lines,
    required this.totalLabel,
    required this.total,
    this.dateLabel,
    this.headerBottom,
    this.onRefresh,
    this.side,
    this.footnote,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.emptyTitle,
    this.emptyMessage,
  });

  final String title;
  final List<DesktopFigure> figures;
  final List<CashLedgerLine> lines;
  final String totalLabel;
  final double total;
  final String? dateLabel;
  final Widget? headerBottom;
  final VoidCallback? onRefresh;

  /// A panel to the right of the ledger.
  final Widget? side;
  final String? footnote;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// Set when there is nothing to show (no shop selected).
  final String? emptyTitle;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (onRefresh != null)
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              onRefresh!,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: title,
              subtitle: dateLabel,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              bottom: headerBottom,
              actions: [
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh (Ctrl+R)',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
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
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (errorMessage != null) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load cash flow",
        message: errorMessage,
        action: onRetry == null
            ? null
            : OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
      );
    }
    if (emptyTitle != null) {
      return DesktopEmptyState(
        icon: Icons.store_mall_directory_outlined,
        title: emptyTitle!,
        message: emptyMessage,
      );
    }
    final p = context.desktop;
    return SingleChildScrollView(
      child: DesktopContent(
        maxWidth: 1100 + 2 * DesktopTokens.gutter,
        padding: const EdgeInsets.fromLTRB(
          DesktopTokens.gutter,
          14,
          DesktopTokens.gutter,
          DesktopTokens.gutter,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopFiguresRow(figures: figures),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, box) {
                final ledger = _Ledger(
                  lines: lines,
                  totalLabel: totalLabel,
                  total: total,
                );
                if (side == null) return ledger;
                if (box.maxWidth < 860) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [ledger, const SizedBox(height: 16), side!],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: ledger),
                    const SizedBox(width: 16),
                    SizedBox(width: 340, child: side),
                  ],
                );
              },
            ),
            if (footnote != null) ...[
              const SizedBox(height: 14),
              Text(
                footnote!,
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({
    required this.lines,
    required this.totalLabel,
    required this.total,
  });

  final List<CashLedgerLine> lines;
  final String totalLabel;
  final double total;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    String signed(double v) {
      if (v == 0) return formatMoney(0, decimals: true);
      return '${v < 0 ? '-' : '+'}${formatMoney(v.abs(), decimals: true)}';
    }

    Color? tone(double v) => v < 0 ? negativeAmountColor(p) : null;

    Widget row(String label, double amount,
        {String? note, bool strong = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.text,
                      fontSize: 13.5,
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (note != null)
                    Text(
                      note,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textFaint,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              signed(amount),
              style: DesignType.numeric(
                fontSize: strong ? 15 : 13.5,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                color: tone(amount) ?? p.text,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Today's cash",
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Amount',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          for (final line in lines) ...[
            row(line.label, line.amount, note: line.note),
            Divider(height: 1, color: p.border),
          ],
          Container(
            color: p.dark ? p.hover : p.panelAlt,
            child: row(totalLabel, total, strong: true),
          ),
        ],
      ),
    );
  }
}

/// A bordered side panel with a title, for the till count and the mode picker.
class DesktopSidePanel extends StatelessWidget {
  const DesktopSidePanel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Container(
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.sora(
                      color: p.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// The till count: expected against counted cash, with the way into the count.
class DesktopTillCountPanel extends StatelessWidget {
  const DesktopTillCountPanel({
    super.key,
    required this.counted,
    required this.expected,
    required this.countedCash,
    required this.difference,
    required this.closedAtLabel,
    required this.onClose,
    required this.onHistory,
  });

  /// The till was counted today.
  final bool counted;
  final double expected;
  final double countedCash;
  final double difference;
  final String? closedAtLabel;
  final VoidCallback onClose;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    Widget kv(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  k,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                v,
                style: DesignType.numeric(
                  fontSize: 13.5,
                  color: color ?? p.text,
                ),
              ),
            ],
          ),
        );
    return DesktopSidePanel(
      title: 'Till count',
      trailing: DesktopStatusChip(
        label: counted ? 'Counted' : 'Not counted',
        color: counted ? DesignColors.success : DesignColors.warning,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            counted
                ? (closedAtLabel == null
                    ? 'The till was counted today.'
                    : 'Last count at $closedAtLabel.')
                : 'Close the day to compare expected and counted cash.',
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (counted) ...[
            const SizedBox(height: 8),
            kv('Expected cash', formatMoney(expected, decimals: true)),
            kv('Counted cash', formatMoney(countedCash, decimals: true)),
            if (difference.abs() >= 0.01)
              kv(
                difference < 0 ? 'Shortfall' : 'Overage',
                formatMoney(difference.abs(), decimals: true),
                color: difference < 0 ? negativeAmountColor(p) : null,
              ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            style: desktopPrimaryButton(context),
            onPressed: onClose,
            child: Text(counted ? 'Review or close again' : 'Count the till'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: desktopSecondaryButton(context),
            onPressed: onHistory,
            child: const Text('Close history'),
          ),
        ],
      ),
    );
  }
}

/// How cash is worked out (cloud shops): three modes as radio rows, then the
/// two pages the figures lead to.
class DesktopCashModePanel extends StatelessWidget {
  const DesktopCashModePanel({
    super.key,
    required this.options,
    required this.selectedId,
    required this.changing,
    required this.onChanged,
    required this.onReconcile,
    required this.onEndOfDay,
  });

  final List<({String id, String label, String description})> options;
  final String selectedId;
  final bool changing;
  final ValueChanged<String> onChanged;
  final VoidCallback onReconcile;
  final VoidCallback onEndOfDay;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return DesktopSidePanel(
      title: 'How cash is worked out',
      trailing: changing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in options)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              hoverColor: p.hover,
              onTap: changing ? null : () => onChanged(o.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        o.id == selectedId
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 19,
                        color: o.id == selectedId ? p.accent : p.textFaint,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.label,
                            style: GoogleFonts.plusJakartaSans(
                              color: p.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            o.description,
                            style: GoogleFonts.plusJakartaSans(
                              color: p.textMuted,
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: desktopSecondaryButton(context),
            onPressed: onReconcile,
            child: const Text('Cash reconciliation'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: desktopSecondaryButton(context),
            onPressed: onEndOfDay,
            child: const Text('End of day'),
          ),
        ],
      ),
    );
  }
}
