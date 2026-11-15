import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// Where one recorded payment stands against the pasted statement.
enum DesktopMatchState {
  /// No statement pasted yet.
  waiting,
  matched,
  checked,
  differs,
  notFound;

  bool get needsAction => this == differs || this == notFound;

  String get label => switch (this) {
        waiting => 'Waiting',
        matched => 'Matched',
        checked => 'Checked',
        differs => 'Amount differs',
        notFound => 'Not found',
      };

  Color get color => switch (this) {
        waiting => const Color(0xFF8C8478),
        matched => MoneyColors.cash,
        checked => MoneyColors.verified,
        differs => MoneyColors.recorded,
        notFound => MoneyColors.recorded,
      };
}

/// One payment the shop recorded today, ready to draw.
class DesktopMatchRow {
  const DesktopMatchRow({
    required this.saleId,
    required this.code,
    required this.amount,
    required this.isBank,
    required this.state,
    this.time,
    this.recordedBy = '',
    this.statementAmounts = const [],
    this.checkNote,
    this.checkedBy,
  });

  final String saleId;
  final String code;
  final double amount;
  final bool isBank;
  final DesktopMatchState state;
  final DateTime? time;
  final String recordedBy;

  /// Amounts found next to the code, when the amount differs.
  final List<double> statementAmounts;
  final String? checkNote;
  final String? checkedBy;

  String get source => isBank ? 'Bank' : 'M-Pesa';
}

/// Match payments on a computer: the pasted statement on the left, today's
/// recorded payments as a table on the right, and a side panel for the one
/// picked, where a payment the statement does not confirm is marked checked
/// with a note (no bottom sheet).
///
/// It only draws. The routed screen owns the statement text, the matching and
/// saving the notes.
class DesktopMatchView extends StatefulWidget {
  const DesktopMatchView({
    super.key,
    required this.rows,
    required this.statement,
    required this.onStatementChanged,
    required this.onPaste,
    required this.onSaveCheck,
    this.initialSelectedId,
  });

  final List<DesktopMatchRow> rows;
  final TextEditingController statement;
  final VoidCallback onStatementChanged;
  final VoidCallback onPaste;

  /// Mark [row] checked with the typed note.
  final void Function(DesktopMatchRow row, String note) onSaveCheck;
  final String? initialSelectedId;

  @override
  State<DesktopMatchView> createState() => _DesktopMatchViewState();
}

class _DesktopMatchViewState extends State<DesktopMatchView> {
  String? _selectedId;
  bool _onlyToCheck = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedId;
  }

  bool get _hasStatement => widget.statement.text.trim().isNotEmpty;

  void _select(DesktopMatchRow? row) => setState(() => _selectedId = row?.saleId);

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final rows = widget.rows;
    final shown = _onlyToCheck
        ? rows.where((r) => r.state.needsAction).toList()
        : rows;
    final selected = rows.where((r) => r.saleId == _selectedId).firstOrNull;

    return CallbackShortcuts(
      bindings: {
        if (selected != null)
          const SingleActivator(LogicalKeyboardKey.escape): () => _select(null),
      },
      child: Focus(
        autofocus: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DesktopPageHeader(
              title: 'Match M-Pesa',
              subtitle:
                  "Check today's recorded payments against your own statement",
              padding: EdgeInsets.fromLTRB(24, 16, 24, 12),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const DesktopEmptyState(
                      icon: Icons.fact_check_outlined,
                      title: 'No recorded payments today',
                      message:
                          'When a customer pays your own till or bank and you record it at checkout, it will show here to check against your statement.',
                    )
                  : DesktopInspectorLayout(
                      inspectorWidth: 360,
                      overlayBelow: 1280,
                      onClose: () => _select(null),
                      inspector: selected == null
                          ? null
                          : _MatchInspector(
                              key: ValueKey(selected.saleId),
                              row: selected,
                              onClose: () => _select(null),
                              onSaveCheck: (note) =>
                                  widget.onSaveCheck(selected, note),
                            ),
                      main: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 300, child: _statementPanel(context)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _strip(context),
                                  const SizedBox(height: 10),
                                  _toolbar(context),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: Container(
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        color: p.dark ? p.panelAlt : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: p.border),
                                      ),
                                      child: _table(context, shown),
                                    ),
                                  ),
                                ],
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

  Widget _statementPanel(BuildContext context) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Statement',
                  style: GoogleFonts.sora(
                    color: p.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              TextButton.icon(
                style: desktopLinkButton(context),
                onPressed: widget.onPaste,
                icon: const Icon(Icons.content_paste_rounded, size: 16),
                label: const Text('Paste'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Paste today's statement or messages from your own M-Pesa or bank. Counterbase compares them with the payments you recorded. It does not read your texts.",
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TextField(
              controller: widget.statement,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              onChanged: (_) {
                widget.onStatementChanged();
                setState(() {});
              },
              decoration: const InputDecoration(
                hintText: 'Paste the statement here (Ctrl+V)',
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _strip(BuildContext context) {
    final rows = widget.rows;
    int n(DesktopMatchState s) => rows.where((r) => r.state == s).length;
    final toCheck = rows.where((r) => r.state.needsAction).length;
    final recordedTotal = rows.fold<double>(0, (a, r) => a + r.amount);
    return DesktopMetricStrip(
      metrics: [
        DesktopMetric(
          label: 'Recorded today',
          value: formatMoney(recordedTotal),
          hint: '${rows.length} ${rows.length == 1 ? 'payment' : 'payments'}',
        ),
        DesktopMetric(
          label: 'Matched',
          value: _hasStatement ? '${n(DesktopMatchState.matched)}' : '–',
          hint: _hasStatement ? 'in the statement' : 'paste a statement',
        ),
        DesktopMetric(
          label: 'To check',
          value: _hasStatement ? '$toCheck' : '–',
          hint: _hasStatement ? 'need a look' : null,
          hintColor: _hasStatement && toCheck > 0
              ? (context.desktop.dark
                  ? MoneyColors.recorded
                  : const Color(0xFF8A5A00))
              : null,
        ),
        DesktopMetric(
          label: 'Checked by note',
          value: '${n(DesktopMatchState.checked)}',
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    final toCheck = widget.rows.where((r) => r.state.needsAction).length;
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DesktopFilterChip(
            label: 'All',
            count: widget.rows.length,
            selected: !_onlyToCheck,
            onTap: () => setState(() => _onlyToCheck = false),
          ),
          DesktopFilterChip(
            label: 'To check',
            count: toCheck,
            selected: _onlyToCheck,
            onTap: () => setState(() => _onlyToCheck = true),
          ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context, List<DesktopMatchRow> rows) {
    final p = context.desktop;
    final time = DateFormat('h:mm a');
    if (rows.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing left to check',
        message: 'Every recorded payment is matched or carries a note.',
        action: OutlinedButton(
          style: desktopSecondaryButton(context),
          onPressed: () => setState(() => _onlyToCheck = false),
          child: const Text('Show all'),
        ),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxWidth < 620;
      final columns = <DesktopColumn<DesktopMatchRow>>[
        DesktopColumn<DesktopMatchRow>(
          label: 'Status',
          width: 128,
          sortBy: (r) => r.state.index,
          cell: (context, r) =>
              DesktopStatusChip(label: r.state.label, color: r.state.color),
        ),
        DesktopColumn<DesktopMatchRow>(
          label: 'Code',
          flex: 2,
          minWidth: 110,
          sortBy: (r) => r.code,
          cell: (context, r) => DesktopCellText(r.code, strong: true),
        ),
        DesktopColumn<DesktopMatchRow>(
          label: 'Time',
          width: 84,
          sortBy: (r) => r.time ?? DateTime.fromMillisecondsSinceEpoch(0),
          cell: (context, r) => DesktopCellText(
            r.time == null ? '—' : time.format(r.time!),
            muted: true,
          ),
        ),
        if (!compact)
          DesktopColumn<DesktopMatchRow>(
            label: 'Source',
            width: 80,
            sortBy: (r) => r.source,
            cell: (context, r) => DesktopCellText(r.source, muted: true),
          ),
        DesktopColumn<DesktopMatchRow>(
          label: 'Amount',
          width: 104,
          numeric: true,
          sortBy: (r) => r.amount,
          cell: (context, r) =>
              DesktopCellText(formatMoney(r.amount), numeric: true),
        ),
      ];
      return DesktopDataTable<DesktopMatchRow>(
        columns: columns,
        rows: rows,
        rowId: (r) => r.saleId,
        rowHeight: 46,
        minWidth: compact ? 480 : 560,
        initialSortColumn: 2,
        initialSortAscending: false,
        selectedId: _selectedId,
        onRowSelected: _select,
        footer: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Text(
                '${rows.length} ${rows.length == 1 ? 'payment' : 'payments'}',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                formatMoney(rows.fold<double>(0, (a, r) => a + r.amount)),
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
    });
  }
}

class _MatchInspector extends StatefulWidget {
  const _MatchInspector({
    super.key,
    required this.row,
    required this.onClose,
    required this.onSaveCheck,
  });

  final DesktopMatchRow row;
  final VoidCallback onClose;
  final ValueChanged<String> onSaveCheck;

  @override
  State<_MatchInspector> createState() => _MatchInspectorState();
}

class _MatchInspectorState extends State<_MatchInspector> {
  final _note = TextEditingController();
  bool _tooShort = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final text = _note.text.trim();
    if (text.length < 3) {
      setState(() => _tooShort = true);
      return;
    }
    widget.onSaveCheck(text);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final r = widget.row;
    final money = NumberFormat.decimalPattern('en_KE');
    final time = DateFormat('h:mm a');

    Widget line(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 104,
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: value),
              ),
            ],
          ),
        );
    final body = GoogleFonts.plusJakartaSans(
      color: p.textMuted,
      fontSize: 13,
      height: 1.45,
    );

    final explain = switch (r.state) {
      DesktopMatchState.waiting =>
        'Paste your statement on the left to check this payment.',
      DesktopMatchState.matched =>
        'This code is in your statement and the amount agrees.',
      DesktopMatchState.checked => null,
      DesktopMatchState.differs => r.statementAmounts.isEmpty
          ? 'The code is in your statement beside a different amount.'
          : 'The statement shows ${r.statementAmounts.map((a) => money.format(a)).take(3).join(', ')} beside this code. You recorded ${money.format(r.amount.round())}.',
      DesktopMatchState.notFound =>
        'This code is not in the statement you pasted.',
    };

    return DesktopInspector(
      title: r.code,
      subtitle: '${r.source} payment',
      onClose: widget.onClose,
      footer: r.state.needsAction
          ? FilledButton.icon(
              style: desktopPrimaryButton(context),
              onPressed: _save,
              icon: const Icon(Icons.verified_outlined, size: 17),
              label: const Text('Mark checked'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatMoney(r.amount, decimals: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignType.numeric(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
              ),
              DesktopStatusChip(label: r.state.label, color: r.state.color),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: p.border),
          if (r.time != null) line('Recorded', DesktopCellText(time.format(r.time!))),
          if (r.recordedBy.isNotEmpty)
            line('Recorded by', DesktopCellText(r.recordedBy)),
          line('Paid by', DesktopCellText(r.source)),
          Divider(height: 1, color: p.border),
          if (explain != null) ...[
            const SizedBox(height: 14),
            Text(explain, style: body),
          ],
          if (r.state == DesktopMatchState.checked) ...[
            const SizedBox(height: 6),
            if ((r.checkedBy ?? '').isNotEmpty)
              line('Checked by', DesktopCellText(r.checkedBy!)),
            if ((r.checkNote ?? '').isNotEmpty)
              line('Note', DesktopCellText(r.checkNote!)),
          ],
          if (r.state.needsAction) ...[
            const SizedBox(height: 12),
            Text(
              'Ask the cashier to show the M-Pesa message or bank entry, then say how you checked it. The note stays with today\'s record.',
              style: body,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) {
                if (_tooShort) setState(() => _tooShort = false);
              },
              decoration: InputDecoration(
                hintText: 'How did you check it?',
                errorText: _tooShort ? 'Write a few words' : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown on a shop connected to the cloud, where a pasted statement cannot
/// confirm a payment.
class DesktopMatchCloudNotice extends StatelessWidget {
  const DesktopMatchCloudNotice({
    super.key,
    required this.onOpenFinance,
    required this.onOpenSetup,
  });

  final VoidCallback onOpenFinance;
  final VoidCallback onOpenSetup;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DesktopPageHeader(
          title: 'M-Pesa verification',
          padding: EdgeInsets.fromLTRB(24, 16, 24, 12),
        ),
        Expanded(
          child: DesktopEmptyState(
            icon: Icons.verified_user_outlined,
            title: 'Verify debt payments with secure checkout',
            message:
                'Pasted M-Pesa messages cannot confirm a debt payment. Open Finance, choose the customer debt, and send an M-Pesa request. Counterbase will update the balance only after the payment partner confirms the payment.',
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  style: desktopPrimaryButton(context),
                  onPressed: onOpenFinance,
                  icon: const Icon(Icons.account_balance_wallet_outlined,
                      size: 17),
                  label: const Text('Open Finance'),
                ),
                OutlinedButton(
                  style: desktopSecondaryButton(context),
                  onPressed: onOpenSetup,
                  child: const Text('Check customer payment setup'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
