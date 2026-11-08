import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/app_roles.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../domain/expenses.dart';
import '../widgets/add_expense_sheet.dart';

typedef _ExpenseData = ({
  ExpenseSummary summary,
  List<Map<String, dynamic>> expenses,
  int saleCount,
});

/// What the shop spent, set against what it sold, for today, this week or
/// this month. Expenses paid in cash also come off the till at End of day.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  ExpensePeriod _period = ExpensePeriod.today;
  late Future<_ExpenseData> _data = _load();

  Future<_ExpenseData> _load() async {
    final auth = getIt<AuthService>();
    final branchId = auth.branchId;
    if (branchId == null) {
      throw StateError('Choose a branch first.');
    }
    final db = getIt<AppDatabase>();
    final range = expensePeriodRange(_period, DateTime.now());
    final sales = await db.getLocalCompletedSalesTotal(
      branchId: branchId,
      from: range.from,
      to: range.to,
    );
    final expenses = await db.getLocalExpenses(
      branchId: branchId,
      from: range.from,
      to: range.to,
    );
    return (
      summary: ExpenseSummary.from(sales: sales.total, expenses: expenses),
      expenses: expenses,
      saleCount: sales.count,
    );
  }

  void _reload() => setState(() {
        _data = _load();
      });

  bool get _canRemove {
    final permissions = ref.read(permissionsProvider);
    return permissions.isAdmin || permissions.role == AppRole.storeManager;
  }

  Future<void> _add() async {
    final entry = await showAddExpenseSheet(context);
    if (entry == null || !mounted) return;
    final auth = getIt<AuthService>();
    try {
      await getIt<AppDatabase>().addLocalExpense(
        branchId: auth.branchId!,
        amount: entry.amount,
        category: entry.category,
        paymentMethod: entry.method,
        note: entry.note,
        recordedBy: auth.currentUser?['name']?.toString() ?? 'Owner',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Saved: ${formatMoney(entry.amount)} for ${entry.category.toLowerCase()}.'),
      ));
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(error))));
    }
  }

  Future<void> _remove(Map<String, dynamic> expense) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove this expense?',
      message:
          '${formatMoney(expense['amount'] as double)} for ${(expense['category'] as String).toLowerCase()}. It stops counting in your totals and at End of day. The app keeps a note that you removed it.',
      confirmLabel: 'Remove',
      confirmColor: DesignColors.error,
    );
    if (!ok || !mounted) return;
    final auth = getIt<AuthService>();
    try {
      await getIt<AppDatabase>().removeLocalExpense(
        id: expense['id'] as String,
        removedBy: auth.currentUser?['name']?.toString() ?? 'Owner',
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(apiErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: Text('Expenses',
            style: DesignType.display.copyWith(
                color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _data.catchError((_) => _emptyData);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final period in ExpensePeriod.values)
                        ChoicePill(
                          label: period.label,
                          selected: _period == period,
                          onTap: () {
                            if (_period == period) return;
                            _period = period;
                            _reload();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<_ExpenseData>(
                    future: _data,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _Note(
                          text:
                              'Could not read expenses. ${apiErrorMessage(snapshot.error!)}',
                        );
                      }
                      final data = snapshot.data;
                      if (data == null) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SummaryCard(
                            summary: data.summary,
                            saleCount: data.saleCount,
                            period: _period,
                          ),
                          if (data.summary.byCategory.length > 1) ...[
                            const SizedBox(height: 20),
                            const _SectionTitle('WHERE IT WENT'),
                            _CategoryBreakdown(summary: data.summary),
                          ],
                          const SizedBox(height: 20),
                          const _SectionTitle('PAID OUT'),
                          if (data.expenses.isEmpty)
                            _Note(
                              text: _period == ExpensePeriod.today
                                  ? 'Nothing recorded today. Add rent, transport, wages or anything else you pay for, and see what is left from your sales.'
                                  : 'Nothing recorded ${_period.label.toLowerCase()}.',
                            )
                          else
                            _ExpenseList(
                              expenses: data.expenses,
                              showDay: _period != ExpensePeriod.today,
                              onRemove: _canRemove ? _remove : null,
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          PinnedActionBar(
            child: SafeArea(
              top: false,
              child: SignInButton(label: 'Add expense', onPressed: _add),
            ),
          ),
        ],
      ),
    );
  }

  static final _ExpenseData _emptyData = (
    summary: ExpenseSummary.from(sales: 0, expenses: const []),
    expenses: const <Map<String, dynamic>>[],
    saleCount: 0,
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.saleCount,
    required this.period,
  });

  final ExpenseSummary summary;
  final int saleCount;
  final ExpensePeriod period;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    const ink = Color(0xFF1A1610);
    const onInk = Color(0xFFF6EFE6);
    const mutedOnInk = Color(0xFFB3A89A);
    final background = palette.isDark ? const Color(0xFF211C16) : ink;
    final left = summary.left;
    final share = summary.spentShare;

    Widget line(String label, String value, {Color color = onInk}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: mutedOnInk, fontSize: 14)),
              ),
              Text(value,
                  style: DesignType.numeric(
                      fontSize: 15, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Semantics(
      container: true,
      label:
          '${period.label}: sales ${formatMoney(summary.sales)}, expenses ${formatMoney(summary.expenses)}, left ${formatMoney(left)}',
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'LEFT FROM SALES, ${period.label.toUpperCase()}',
              style: DesignType.numeric(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: mutedOnInk,
                  letterSpacing: 1.2),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatMoney(left),
                style: DesignType.display.copyWith(
                  color: left < 0 ? const Color(0xFFFF9B8A) : onInk,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            line('Sales ($saleCount)', formatMoney(summary.sales)),
            line(
              'Expenses',
              summary.expenses > 0
                  ? '-${formatMoney(summary.expenses)}'
                  : formatMoney(0),
              color: summary.expenses > 0 ? const Color(0xFFFFC9A8) : onInk,
            ),
            if (share != null && summary.expenses > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF2B251E),
                  color: DesignColors.accent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(share * 100).round()}% of sales went on expenses',
                style: const TextStyle(color: mutedOnInk, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'The cost of the stock you sold is not taken off here.',
              style: TextStyle(color: mutedOnInk, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: DesignType.numeric(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: SignInPalette.of(context).soft,
              letterSpacing: 1.1)),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: palette.line),
      ),
      child: Text(text, style: TextStyle(color: palette.soft, height: 1.45)),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.summary});

  final ExpenseSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final biggest = summary.byCategory.first.amount;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        children: [
          for (final row in summary.byCategory)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(expenseIcon(row.category),
                          size: 18, color: palette.soft),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(row.category,
                            style: TextStyle(
                                color: palette.ink,
                                fontWeight: FontWeight.w600)),
                      ),
                      Text(formatMoney(row.amount),
                          style: DesignType.numeric(
                              fontSize: 14, color: palette.ink)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: biggest <= 0 ? 0 : row.amount / biggest,
                      minHeight: 4,
                      backgroundColor: palette.line,
                      color: DesignColors.accent,
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

class _ExpenseList extends StatelessWidget {
  const _ExpenseList({
    required this.expenses,
    required this.showDay,
    required this.onRemove,
  });

  final List<Map<String, dynamic>> expenses;
  final bool showDay;
  final void Function(Map<String, dynamic> expense)? onRemove;

  static final _time = DateFormat('HH:mm');
  static final _day = DateFormat('EEE d MMM');

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < expenses.length; i++) ...[
            if (i > 0) Divider(height: 1, color: palette.line),
            _row(context, palette, expenses[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    SignInPalette palette,
    Map<String, dynamic> expense,
  ) {
    final spentAt = expense['spentAt'] as DateTime;
    final category = expense['category'] as String;
    final note = (expense['note'] as String?)?.trim() ?? '';
    final when = showDay
        ? '${_day.format(spentAt)}, ${_time.format(spentAt)}'
        : _time.format(spentAt);
    final details = [
      when,
      expenseMethodLabel(expense['paymentMethod'] as String),
      expense['recordedBy'] as String,
    ].join(' · ');
    return InkWell(
      onLongPress: onRemove == null ? null : () => onRemove!(expense),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: context.themed(DesignColors.accentSubtle),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(expenseIcon(category),
                  size: 20, color: DesignColors.accentDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.isEmpty ? category : '$category · $note',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: palette.ink, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(details,
                      style: TextStyle(color: palette.soft, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('-${formatMoney(expense['amount'] as double)}',
                style: DesignType.numeric(
                    fontSize: 14,
                    color: palette.ink,
                    fontWeight: FontWeight.w600)),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.more_vert_rounded,
                    size: 20, color: palette.faint),
                onPressed: () => onRemove!(expense),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
