import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/collections_ledger.dart';
import '../../domain/finance_models.dart';
import 'desktop_figures_row.dart';

/// One other shop's account on a computer: what it still owes in one strip,
/// then its debts and the instalments it has paid, side by side.
///
/// Plain data in ([ShopStatement] and the merged instalments); the routed
/// screen owns the providers and the record-an-instalment sheet.
class DesktopShopLedgerView extends StatelessWidget {
  const DesktopShopLedgerView({
    super.key,
    required this.title,
    this.statement,
    this.instalments = const [],
    this.canRecord = false,
    this.onRecord,
    this.statementAction,
    this.onBack,
    this.onRefresh,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.notFound = false,
  });

  final String title;
  final ShopStatement? statement;
  final List<CollectionEntry> instalments;
  final bool canRecord;
  final VoidCallback? onRecord;

  /// The "send statement" button, built by the routed screen.
  final Widget? statementAction;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final bool notFound;

  @override
  Widget build(BuildContext context) {
    final s = statement;
    final showRecord = canRecord && s != null && s.outstanding > 0;
    return CallbackShortcuts(
      bindings: {
        if (onRefresh != null)
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              onRefresh!,
        if (showRecord && onRecord != null)
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              onRecord!,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: title,
              subtitle: s == null ? null : 'Shop account',
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
              leading: onBack == null
                  ? null
                  : IconButton(
                      tooltip: 'Back',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    ),
              actions: [
                if (s != null && s.outstanding > 0 && statementAction != null)
                  SizedBox(width: 190, child: statementAction),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh (Ctrl+R)',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                if (showRecord)
                  Tooltip(
                    message: 'Ctrl+N',
                    child: FilledButton.icon(
                      key: const ValueKey('record-installment'),
                      style: desktopPrimaryButton(context),
                      onPressed: onRecord,
                      icon: const Icon(Icons.add_card_rounded, size: 18),
                      label: const Text('Record instalment'),
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
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    final s = statement;
    if (errorMessage != null && s == null) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load shop account',
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
    if (notFound || s == null) {
      return const DesktopEmptyState(
        icon: Icons.store_outlined,
        title: 'Shop account not found',
        message: 'Refresh Finance and open the shop from the list again.',
      );
    }
    final p = context.desktop;
    final success = context.readable(DesignColors.success);
    final figures = [
      DesktopFigure(
        label: s.isSettled ? 'All settled' : 'Still owes you',
        value: formatMoney(s.outstanding),
        hint: s.isSettled ? 'Paid up' : '${s.openDebts.length} open',
      ),
      DesktopFigure(
        label: 'Original total',
        value: formatMoney(s.originalTotal),
        hint: '${s.debts.length} on record',
      ),
      DesktopFigure(
        label: 'Paid so far',
        value: formatMoney(s.paid),
        hint: '${(s.progress * 100).round()}% paid back',
        valueColor: s.paid > 0 ? success : null,
      ),
    ];
    final debts = _Panel(
      title: 'Debts',
      trailing: '${s.debts.length} on record',
      child: _debtsTable(context, s),
    );
    final paid = _Panel(
      title: 'Instalments received',
      trailing:
          '${instalments.length} payment${instalments.length == 1 ? '' : 's'}',
      child: _instalmentsTable(context),
    );
    return Padding(
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
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth < 760) {
                  return Column(
                    children: [
                      Expanded(child: debts),
                      const SizedBox(height: 12),
                      Expanded(child: paid),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 11, child: debts),
                    const SizedBox(width: 14),
                    Expanded(flex: 9, child: paid),
                  ],
                );
              },
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              errorMessage!,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _debtsTable(BuildContext context, ShopStatement s) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    bool overdue(PeerReceivable d) =>
        d.outstandingAmount > 0 &&
        d.dueDate != null &&
        d.dueDate!.toLocal().isBefore(startOfToday);
    return DesktopDataTable<PeerReceivable>(
      minWidth: 380,
      rowHeight: 52,
      rows: s.debts,
      rowId: (d) => d.id,
      empty: const DesktopEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No debts recorded',
        message: 'No debts recorded for this shop yet.',
      ),
      columns: [
        DesktopColumn<PeerReceivable>(
          label: 'Debt',
          flex: 3,
          minWidth: 160,
          sortBy: (d) => d.description.toLowerCase(),
          cell: (context, d) {
            final paid = d.originalAmount - d.outstandingAmount;
            final progress = d.originalAmount <= 0
                ? 0.0
                : (paid / d.originalAmount).clamp(0.0, 1.0);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DesktopCellText(d.description, strong: true),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: context.desktop.hover,
                    color: d.outstandingAmount <= 0
                        ? DesignColors.success
                        : DesignColors.accent,
                  ),
                ),
              ],
            );
          },
        ),
        DesktopColumn<PeerReceivable>(
          label: 'Status',
          width: 112,
          sortBy: (d) => d.dueDate ?? DateTime(2100),
          cell: (_, d) {
            if (d.outstandingAmount <= 0) {
              return const DesktopStatusChip(
                  label: 'Paid', color: DesignColors.success);
            }
            if (overdue(d)) {
              return const DesktopStatusChip(
                  label: 'Overdue', color: DesignColors.error);
            }
            if (d.dueDate != null) {
              return DesktopStatusChip(
                label: 'Due ${DateFormat('d MMM').format(d.dueDate!.toLocal())}',
                color: DesignColors.warning,
              );
            }
            return const DesktopCellText('No due date', muted: true);
          },
        ),
        DesktopColumn<PeerReceivable>(
          label: 'Original',
          width: 112,
          numeric: true,
          sortBy: (d) => d.originalAmount,
          cell: (_, d) => DesktopCellText(
            formatMoney(d.originalAmount),
            numeric: true,
            muted: true,
          ),
        ),
        DesktopColumn<PeerReceivable>(
          label: 'Left',
          width: 96,
          numeric: true,
          sortBy: (d) => d.outstandingAmount,
          cell: (_, d) => DesktopCellText(
            d.outstandingAmount <= 0 ? 'Cleared' : formatMoney(d.outstandingAmount),
            numeric: true,
            strong: true,
          ),
        ),
      ],
    );
  }

  Widget _instalmentsTable(BuildContext context) {
    return DesktopDataTable<CollectionEntry>(
      minWidth: 340,
      rowHeight: 52,
      rows: instalments,
      rowId: (e) => e.paymentId,
      initialSortColumn: 0,
      initialSortAscending: false,
      empty: DesktopEmptyState(
        icon: Icons.south_west_rounded,
        title: 'Nothing collected yet',
        message: canRecord
            ? 'Record an instalment when this shop pays.'
            : 'Nothing collected yet.',
      ),
      columns: [
        DesktopColumn<CollectionEntry>(
          label: 'Received',
          width: 118,
          sortBy: (e) => e.paidAt,
          cell: (_, e) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesktopCellText(DateFormat('d MMM y').format(e.paidAt),
                  strong: true),
              DesktopCellText(DateFormat('h:mm a').format(e.paidAt),
                  muted: true),
            ],
          ),
        ),
        DesktopColumn<CollectionEntry>(
          label: 'How and what for',
          flex: 3,
          minWidth: 120,
          cell: (_, e) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesktopCellText(
                [
                  paymentMethodLabel(e.method),
                  if (e.reference != null) e.reference!,
                ].join(' · '),
              ),
              DesktopCellText('Towards ${e.what}', muted: true),
            ],
          ),
        ),
        DesktopColumn<CollectionEntry>(
          label: 'Amount',
          width: 104,
          numeric: true,
          sortBy: (e) => e.amount,
          cell: (context, e) => DesktopCellText(
            '+${formatMoney(e.amount)}',
            numeric: true,
            strong: true,
            color: context.readable(DesignColors.success),
          ),
        ),
      ],
    );
  }
}

/// A titled, bordered table container that fills its slot.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.trailing,
    required this.child,
  });

  final String title;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final head = GoogleFonts.plusJakartaSans(
      color: p.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
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
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.sora(
                      color: p.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(trailing, style: head),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
