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
import '../../../finance/presentation/desktop/desktop_figures_row.dart';
import '../../domain/expenses.dart';
import '../widgets/add_expense_sheet.dart' show NewExpense;

/// The Expenses page on a computer: what was left from sales, a table of what
/// was paid out with a one-line add form on top, and where the money went.
///
/// It takes plain data. The routed screen reads and writes the database; this
/// widget draws it and keeps only the form's own state.
class DesktopExpensesView extends StatefulWidget {
  const DesktopExpensesView({
    super.key,
    required this.period,
    required this.onPeriod,
    required this.summary,
    required this.saleCount,
    required this.expenses,
    required this.onAdd,
    this.onRemove,
    this.onRefresh,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.headerBottom,
  });

  final ExpensePeriod period;
  final ValueChanged<ExpensePeriod> onPeriod;
  final ExpenseSummary summary;
  final int saleCount;

  /// Rows as the database returns them: id, amount, category, note,
  /// paymentMethod, spentAt, recordedBy.
  final List<Map<String, dynamic>> expenses;

  /// Saves one entry. Returns null when it worked, or what to tell the person.
  final Future<String?> Function(NewExpense entry) onAdd;

  /// null when the signed-in role may not remove expenses.
  final void Function(Map<String, dynamic> expense)? onRemove;
  final VoidCallback? onRefresh;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// The Overview | Expenses | Cash flow tabs.
  final Widget? headerBottom;

  @override
  State<DesktopExpensesView> createState() => _DesktopExpensesViewState();
}

class _DesktopExpensesViewState extends State<DesktopExpensesView> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _amountFocus = FocusNode(debugLabel: 'ExpenseAmount');
  String? _category;
  String _method = 'CASH';
  String? _error;
  bool _saving = false;

  static final _time = DateFormat('HH:mm');
  static final _day = DateFormat('EEE d MMM');

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    final note = _note.text.trim();
    final String? problem;
    if (amount == null || amount <= 0) {
      problem = 'Enter how much was paid.';
    } else if (_category == null) {
      problem = 'Choose what the money was for.';
    } else if (_category == 'Other' && note.isEmpty) {
      problem = 'Say what it was for in the note.';
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() => _error = problem);
      if (amount == null || amount <= 0) _amountFocus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final failure = await widget.onAdd((
      amount: amount!,
      category: _category!,
      method: _method,
      note: note.isEmpty ? null : note,
    ));
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = failure;
    });
    if (failure == null) {
      // Keep the category and method: the next receipt is often the same kind.
      _amount.clear();
      _note.clear();
      _amountFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final w = widget;
    final s = w.summary;
    final share = s.spentShare;
    return LayoutBuilder(builder: (context, outer) {
      // A laptop at 125% display scaling leaves about 500px: fold the period
      // chips into the header and drop the figure hints so the table keeps room.
      final short = outer.maxHeight < 620;
      Widget periods() => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final period in ExpensePeriod.values)
                DesktopFilterChip(
                  label: period.label,
                  selected: w.period == period,
                  onTap: () => w.onPeriod(period),
                ),
            ],
          );
      return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _amountFocus.requestFocus(),
        if (w.onRefresh != null)
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              w.onRefresh!,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: 'Expenses',
              subtitle:
                  short ? null : 'What you paid out, set against what you sold',
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              bottom: w.headerBottom,
              actions: [
                if (short) periods(),
                if (w.onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh (Ctrl+R)',
                    onPressed: w.onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, short ? 10 : 14, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!short) ...[
                      periods(),
                      const SizedBox(height: 12),
                    ],
                    DesktopFiguresRow(
                      dense: short,
                      figures: [
                        DesktopFigure(
                          label: 'Sales',
                          value: formatMoney(s.sales),
                          hint: '${w.saleCount} '
                              '${w.saleCount == 1 ? 'sale' : 'sales'}',
                        ),
                        DesktopFigure(
                          label: 'Expenses',
                          value: s.expenses > 0
                              ? '-${formatMoney(s.expenses)}'
                              : formatMoney(0),
                          hint: share != null && s.expenses > 0
                              ? '${(share * 100).round()}% of sales'
                              : null,
                        ),
                        DesktopFigure(
                          label: 'Left from sales',
                          value: s.left < 0
                              ? '-${formatMoney(-s.left)}'
                              : formatMoney(s.left),
                          hint: 'Stock cost is not taken off',
                          valueColor: s.left < 0 ? negativeAmountColor(p) : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final wide = box.maxWidth >= 1050;
                          final table = _tablePanel(context);
                          if (!wide) return table;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: table),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 280,
                                child: _breakdown(context),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    });
  }

  Widget _tablePanel(BuildContext context) {
    final p = context.desktop;
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
          _addRow(context),
          Divider(height: 1, color: p.border),
          Expanded(child: _table(context)),
        ],
      ),
    );
  }

  Widget _addRow(BuildContext context) {
    final p = context.desktop;
    final amount = SizedBox(
      width: 148,
      height: DesktopTokens.controlHeight,
      child: TextField(
        controller: _amount,
        focusNode: _amountFocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          LengthLimitingTextInputFormatter(12),
        ],
        textInputAction: TextInputAction.next,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _save(),
        cursorColor: p.accent,
        style: DesignType.numeric(fontSize: 14, color: p.text),
        decoration: _fieldDecoration(p, hint: 'Amount (KES)'),
      ),
    );
    final note = SizedBox(
      height: DesktopTokens.controlHeight,
      child: TextField(
        controller: _note,
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: [LengthLimitingTextInputFormatter(120)],
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _save(),
        cursorColor: p.accent,
        style: GoogleFonts.plusJakartaSans(
          color: p.text,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        decoration: _fieldDecoration(
          p,
          hint: _category == 'Other'
              ? 'Note (needed)'
              : 'Note, like boda to the wholesaler',
        ),
      ),
    );
    final addButton = Tooltip(
      message: 'Save expense (Enter)',
      child: FilledButton.icon(
        style: desktopPrimaryButton(context),
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add'),
      ),
    );
    final category = _PickField<String>(
      hint: 'What for',
      value: _category,
      leading: _category == null ? null : expenseIcon(_category!),
      options: [
        for (final c in kExpenseCategories)
          (value: c.label, label: c.label, icon: c.icon),
      ],
      onSelected: (v) => setState(() {
        _category = v;
        _error = null;
      }),
      width: 196,
    );
    final method = _PickField<String>(
      hint: 'Paid with',
      value: _method,
      options: [
        for (final m in kExpenseMethods)
          (value: m.code, label: m.label, icon: null),
      ],
      onSelected: (v) => setState(() => _method = v),
      width: 176,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth >= 720) {
                return Row(
                  children: [
                    amount,
                    const SizedBox(width: 8),
                    category,
                    const SizedBox(width: 8),
                    method,
                    const SizedBox(width: 8),
                    Expanded(child: note),
                    const SizedBox(width: 8),
                    addButton,
                  ],
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  amount,
                  category,
                  method,
                  SizedBox(width: box.maxWidth - 92, child: note),
                  addButton,
                ],
              );
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: GoogleFonts.plusJakartaSans(
                color: negativeAmountColor(p),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if (_method == 'CASH' && _category != null) ...[
            const SizedBox(height: 8),
            Text(
              'End of day takes cash expenses off the cash that should be in '
              'the till. Enter saves and keeps the category for the next one.',
              style: GoogleFonts.plusJakartaSans(
                color: p.textFaint,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(DesktopPalette p, {required String hint}) {
    OutlineInputBorder border(Color c, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
          borderSide: BorderSide(color: c, width: width),
        );
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: GoogleFonts.plusJakartaSans(color: p.textFaint, fontSize: 13.5),
      filled: true,
      fillColor: p.dark ? p.panelAlt : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      enabledBorder: border(p.border),
      border: border(p.border),
      focusedBorder: border(p.accent, 1.4),
    );
  }

  Widget _table(BuildContext context) {
    final w = widget;
    final p = context.desktop;
    if (w.errorMessage != null && w.expenses.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't read expenses",
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
    final showDay = w.period != ExpensePeriod.today;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 700;
        final columns = <DesktopColumn<Map<String, dynamic>>>[
          DesktopColumn<Map<String, dynamic>>(
            label: 'When',
            width: showDay ? 136 : 80,
            sortBy: (r) => r['spentAt'] as DateTime,
            cell: (context, r) {
              final at = r['spentAt'] as DateTime;
              return DesktopCellText(
                showDay ? '${_day.format(at)}, ${_time.format(at)}' : _time.format(at),
                muted: true,
              );
            },
          ),
          DesktopColumn<Map<String, dynamic>>(
            label: 'Category',
            flex: 3,
            minWidth: 120,
            sortBy: (r) => r['category'] as String,
            cell: (context, r) => Row(
              children: [
                Icon(expenseIcon(r['category'] as String),
                    size: 17, color: p.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: DesktopCellText(r['category'] as String, strong: true),
                ),
              ],
            ),
          ),
          DesktopColumn<Map<String, dynamic>>(
            label: 'Note',
            flex: 2,
            minWidth: 100,
            cell: (context, r) => DesktopCellText(
              ((r['note'] as String?) ?? '').trim().isEmpty
                  ? '—'
                  : (r['note'] as String).trim(),
              muted: true,
            ),
          ),
          if (!compact)
            DesktopColumn<Map<String, dynamic>>(
              label: 'Paid with',
              width: 110,
              sortBy: (r) => expenseMethodLabel(r['paymentMethod'] as String),
              cell: (context, r) => DesktopCellText(
                expenseMethodLabel(r['paymentMethod'] as String),
                muted: true,
              ),
            ),
          if (!compact)
            DesktopColumn<Map<String, dynamic>>(
              label: 'Recorded by',
              width: 120,
              sortBy: (r) => (r['recordedBy'] as String).toLowerCase(),
              cell: (context, r) =>
                  DesktopCellText(r['recordedBy'] as String, muted: true),
            ),
          DesktopColumn<Map<String, dynamic>>(
            label: 'Amount',
            width: 120,
            numeric: true,
            sortBy: (r) => (r['amount'] as num).toDouble(),
            cell: (context, r) => DesktopCellText(
              '-${formatMoney(r['amount'] as num)}',
              numeric: true,
            ),
          ),
          if (w.onRemove != null)
            DesktopColumn<Map<String, dynamic>>(
              label: '',
              width: 56,
              cell: (context, r) => IconButton(
                tooltip: 'Remove this expense',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline_rounded,
                    size: 18, color: p.textMuted),
                onPressed: () => w.onRemove!(r),
              ),
            ),
        ];
        return DesktopDataTable<Map<String, dynamic>>(
          columns: columns,
          rows: w.expenses,
          rowId: (r) => r['id'] as String,
          rowHeight: 46,
          minWidth: compact ? 540 : (showDay ? 800 : 760),
          loading: w.loading,
          initialSortColumn: 0,
          initialSortAscending: false,
          empty: DesktopEmptyState(
            icon: Icons.receipt_outlined,
            title: w.period == ExpensePeriod.today
                ? 'Nothing recorded today'
                : 'Nothing recorded ${w.period.label.toLowerCase()}',
            message: 'Type an amount above, pick what it was for and press '
                'Enter. Rent, transport, wages and anything else you pay for '
                'comes off your sales here.',
          ),
          footer: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                Text(
                  '${w.expenses.length} '
                  '${w.expenses.length == 1 ? 'expense' : 'expenses'}',
                  style: _footStyle(p),
                ),
                const Spacer(),
                Text('Total', style: _footStyle(p)),
                const SizedBox(width: 8),
                Text(
                  '-${formatMoney(w.summary.expenses, decimals: true)}',
                  style: DesignType.numeric(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
                if (w.onRemove != null) const SizedBox(width: 44),
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

  Widget _breakdown(BuildContext context) {
    final p = context.desktop;
    final rows = widget.summary.byCategory;
    final biggest = rows.isEmpty ? 0.0 : rows.first.amount;
    final total = widget.summary.expenses;
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Where it went',
                    style: GoogleFonts.sora(
                      color: p.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Text(
                  widget.period.label,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text(
                      'Your biggest costs show up here once you record some.',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    children: [
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(expenseIcon(row.category),
                                      size: 16, color: p.textMuted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      row.category,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: p.text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatMoney(row.amount),
                                    style: DesignType.numeric(
                                      fontSize: 12.5,
                                      color: p.text,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(99),
                                      child: LinearProgressIndicator(
                                        value: biggest <= 0
                                            ? 0
                                            : row.amount / biggest,
                                        minHeight: 4,
                                        backgroundColor: p.border,
                                        color: p.textMuted,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 44,
                                    child: Text(
                                      total > 0
                                          ? '${(row.amount / total * 100).round()}%'
                                          : '',
                                      textAlign: TextAlign.right,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: p.textFaint,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// A drop-down styled like the text fields beside it, for the add row.
class _PickField<T> extends StatelessWidget {
  const _PickField({
    required this.hint,
    required this.value,
    required this.options,
    required this.onSelected,
    required this.width,
    this.leading,
  });

  final String hint;
  final T? value;
  final IconData? leading;
  final List<({T value, String label, IconData? icon})> options;
  final ValueChanged<T> onSelected;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final current = options.where((o) => o.value == value).firstOrNull;
    return PopupMenuButton<T>(
      tooltip: hint,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final o in options)
          PopupMenuItem<T>(
            value: o.value,
            child: Row(
              children: [
                if (o.icon != null) ...[
                  Icon(o.icon, size: 18),
                  const SizedBox(width: 10),
                ],
                Text(
                  o.label,
                  style: TextStyle(
                    fontWeight: o.value == value
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        width: width,
        height: DesktopTokens.controlHeight,
        padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
        decoration: BoxDecoration(
          color: p.dark ? p.panelAlt : Colors.white,
          borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              Icon(leading, size: 17, color: p.textMuted),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                current?.label ?? hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: current == null ? p.textFaint : p.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}
