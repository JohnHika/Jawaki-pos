import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_table_frame.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/statement_models.dart';

/// Which replies the table shows.
enum DesktopReplyFilter {
  waiting('Waiting'),
  all('All');

  const DesktopReplyFilter(this.label);
  final String label;
}

/// What the page says instead of a table.
enum DesktopRepliesNotice {
  /// A standalone workspace cannot receive replies from a hosted link.
  localWorkspace,

  /// Replies need the online workspace.
  needsOnline,

  /// A temporary failure; "Try again" is offered.
  failed,
}

String _replyHeadline(StatementClaim c) => c.isPaid
    ? 'Says they paid ${kesWhole(c.amount ?? 0)}'
    : 'Will pay on ${c.promisedFor == null ? 'a later date' : '${c.promisedFor!.day}/${c.promisedFor!.month}'}';

(String, Color) _replyStatus(StatementClaim c) => switch (c.status) {
      'CONFIRMED' => ('Done', DesignColors.success),
      'REJECTED' => ('Rejected', DesignColors.error),
      _ => (c.isPaid ? 'Says paid' : 'Promise', DesignColors.warning),
    };

/// Customer replies to a statement link, on a computer: a table of replies
/// and, on the right, the open reply with its actions.
///
/// A customer's "I have paid" claim stays informational; it never settles a
/// debt, so the only buttons are Open Finance, Noted and Reject.
class DesktopStatementRepliesView extends StatefulWidget {
  const DesktopStatementRepliesView({
    super.key,
    required this.title,
    required this.claims,
    required this.canDecide,
    required this.onDecide,
    required this.onOpenFinance,
    required this.onRefresh,
    this.busyId,
    this.notice,
    this.noticeMessage,
    this.onOpenCustomers,
    this.loading = false,
  });

  final String title;
  final List<StatementClaim> claims;
  final bool canDecide;
  final void Function(StatementClaim claim, {required bool confirm}) onDecide;
  final VoidCallback onOpenFinance;
  final VoidCallback onRefresh;

  /// The reply being sent, so its buttons are disabled.
  final String? busyId;
  final DesktopRepliesNotice? notice;
  final String? noticeMessage;
  final VoidCallback? onOpenCustomers;
  final bool loading;

  @override
  State<DesktopStatementRepliesView> createState() =>
      _DesktopStatementRepliesViewState();
}

class _DesktopStatementRepliesViewState
    extends State<DesktopStatementRepliesView> {
  DesktopReplyFilter _filter = DesktopReplyFilter.waiting;
  String? _selectedId;

  List<StatementClaim> get _rows => [
        for (final c in widget.claims)
          if (_filter == DesktopReplyFilter.all || c.isPending) c,
      ];

  StatementClaim? get _selected {
    for (final c in widget.claims) {
      if (c.id == _selectedId) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final waiting = widget.claims.where((c) => c.isPending).length;

    final Widget body;
    if (widget.notice != null) {
      body = _noticeView();
    } else {
      body = DesktopInspectorLayout(
        onClose: () => setState(() => _selectedId = null),
        inspector: _selected == null ? null : _inspector(_selected!),
        main: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesktopTokens.gutter,
                0,
                DesktopTokens.gutter,
                12,
              ),
              child: Row(
                children: [
                  for (final f in DesktopReplyFilter.values) ...[
                    DesktopFilterChip(
                      key: ValueKey('replies-filter-${f.name}'),
                      label: f.label,
                      count: f == DesktopReplyFilter.waiting
                          ? waiting
                          : widget.claims.length,
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesktopTokens.gutter,
                  0,
                  DesktopTokens.gutter,
                  DesktopTokens.gutter,
                ),
                child: DesktopTableFrame(
      child: _table(p),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: widget.title,
          subtitle: 'What customers said after opening a statement you sent.',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, size: 19),
              onPressed: widget.onRefresh,
            ),
          ],
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _noticeView() {
    switch (widget.notice!) {
      case DesktopRepliesNotice.localWorkspace:
        return DesktopEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Replies need a hosted statement link',
          message: 'This standalone workspace keeps records on this computer. '
              'It cannot receive replies from a customer\'s online statement '
              'link. You can still share a local statement from a customer '
              'profile.',
          action: widget.onOpenCustomers == null
              ? null
              : OutlinedButton(
                  style: desktopSecondaryButton(context),
                  onPressed: widget.onOpenCustomers,
                  child: const Text('Open customers'),
                ),
        );
      case DesktopRepliesNotice.needsOnline:
        return const DesktopEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Replies need the online workspace',
          message: 'Customer replies are available when this app is connected '
              'to your online Counterbase workspace. Your sales and debts '
              'remain saved on this computer.',
        );
      case DesktopRepliesNotice.failed:
        return DesktopEmptyState(
          icon: Icons.mark_chat_read_outlined,
          title: "Couldn't load customer replies",
          message: widget.noticeMessage,
          action: OutlinedButton(
            style: desktopSecondaryButton(context),
            onPressed: widget.onRefresh,
            child: const Text('Try again'),
          ),
        );
    }
  }

  Widget _table(DesktopPalette p) {
    return DesktopDataTable<StatementClaim>(
      key: const ValueKey('replies-table'),
      rows: _rows,
      rowId: (c) => c.id,
      selectedId: _selectedId,
      loading: widget.loading,
      minWidth: 640,
      onRowSelected: (c) => setState(() => _selectedId = c.id),
      onRowActivated: (c) => setState(() => _selectedId = c.id),
      columns: [
        DesktopColumn<StatementClaim>(
          label: 'Customer',
          flex: 3,
          minWidth: 140,
          sortBy: (c) => c.debtorName.toLowerCase(),
          cell: (context, c) => DesktopCellText(c.debtorName, strong: true),
        ),
        DesktopColumn<StatementClaim>(
          label: 'Reply',
          flex: 3,
          minWidth: 160,
          cell: (context, c) => DesktopCellText(_replyHeadline(c), muted: true),
        ),
        DesktopColumn<StatementClaim>(
          label: 'Still owes',
          width: 110,
          numeric: true,
          sortBy: (c) => c.outstanding,
          cell: (context, c) =>
              DesktopCellText(kesWhole(c.outstanding), numeric: true),
        ),
        DesktopColumn<StatementClaim>(
          label: 'When',
          width: 110,
          sortBy: (c) => c.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          cell: (context, c) => DesktopCellText(
            c.createdAt == null ? '' : timeAgo(c.createdAt!),
            muted: true,
          ),
        ),
        DesktopColumn<StatementClaim>(
          label: 'Status',
          width: 110,
          cell: (context, c) {
            final (label, color) = _replyStatus(c);
            return DesktopStatusChip(label: label, color: color);
          },
        ),
      ],
      empty: DesktopEmptyState(
        icon: Icons.mark_chat_read_outlined,
        title: _filter == DesktopReplyFilter.waiting && widget.claims.isNotEmpty
            ? 'Nothing waiting'
            : 'No replies yet',
        message: 'When a customer opens a statement you sent and taps '
            '"I have paid" or "I will pay on", it shows up here.',
      ),
    );
  }

  Widget _inspector(StatementClaim c) {
    final p = context.desktop;
    final (label, color) = _replyStatus(c);
    final busy = widget.busyId == c.id;

    Widget fact(String name, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

    Widget? footer;
    if (c.isPending && c.isPaid) {
      footer = Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('reply-open-finance'),
              style: desktopPrimaryButton(context),
              onPressed: widget.onOpenFinance,
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 17),
              label: const Text('Open Finance'),
            ),
          ),
          if (widget.canDecide) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              key: const ValueKey('reply-reject'),
              style: desktopSecondaryButton(context),
              onPressed: busy ? null : () => widget.onDecide(c, confirm: false),
              child: const Text('Reject claim'),
            ),
          ],
        ],
      );
    } else if (c.isPending && widget.canDecide) {
      footer = Row(
        children: [
          Expanded(
            child: FilledButton(
              key: const ValueKey('reply-noted'),
              style: desktopPrimaryButton(context),
              onPressed: busy ? null : () => widget.onDecide(c, confirm: true),
              child: const Text('Noted'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const ValueKey('reply-reject'),
            style: desktopSecondaryButton(context),
            onPressed: busy ? null : () => widget.onDecide(c, confirm: false),
            child: const Text('Reject'),
          ),
        ],
      );
    }

    return DesktopInspector(
      key: const ValueKey('reply-inspector'),
      title: c.debtorName,
      subtitle: c.debtorPhone,
      onClose: () => setState(() => _selectedId = null),
      footer: footer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: DesktopStatusChip(label: label, color: color),
          ),
          Text(
            _replyHeadline(c),
            style: GoogleFonts.sora(
              color: p.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (c.isPaid && c.mpesaCode != null) fact('M-Pesa code', c.mpesaCode!),
          if (c.payerName != null && c.payerName!.isNotEmpty)
            fact('Sent by', c.payerName!),
          fact('Still owes', kesWhole(c.outstanding)),
          if (c.createdAt != null) fact('Replied', timeAgo(c.createdAt!)),
          if (c.isPending && c.isPaid) ...[
            const SizedBox(height: 6),
            Text(
              'This is the customer\'s claim, not payment confirmation. Check '
              'the payment partner or a trusted M-Pesa statement before '
              'recording it. A new payment request is only for money still '
              'owed.',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
