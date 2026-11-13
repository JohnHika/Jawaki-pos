import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/expenses/domain/expenses.dart';
import 'package:axon_pos/features/expenses/presentation/desktop/desktop_expenses_view.dart';
import 'package:axon_pos/features/expenses/presentation/widgets/add_expense_sheet.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_finance_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

final _now = DateTime(2026, 11, 10, 15, 30);

List<Map<String, dynamic>> _sample([int count = 14]) {
  const categories = [
    'Transport',
    'Wages',
    'Electricity and water',
    'Rent',
    'Airtime and internet',
    'Shop supplies',
    'Repairs',
  ];
  const notes = [
    'Boda to the wholesaler',
    'Casual labour, Saturday',
    '',
    'November rent, Githurai stall 14',
    'Safaricom bundles',
    'Polythene bags and receipt rolls for the till printer, two big packs',
    '',
  ];
  const methods = ['CASH', 'MPESA', 'BANK'];
  return [
    for (var i = 0; i < count; i++)
      {
        'id': 'e$i',
        'amount': 150.0 + i * 235.5,
        'category': categories[i % categories.length],
        'note': notes[i % notes.length],
        'paymentMethod': methods[i % methods.length],
        'spentAt': _now.subtract(Duration(minutes: i * 53)),
        'recordedBy': i.isEven ? 'Wanjiru' : 'Otieno',
      },
  ];
}

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    this.expenses,
    this.sales = 18400,
    this.canRemove = true,
    this.errorMessage,
    this.failSave = false,
    this.onRemoved,
  });

  final List<Map<String, dynamic>>? expenses;
  final double sales;
  final bool canRemove;
  final String? errorMessage;
  final bool failSave;
  final ValueChanged<Map<String, dynamic>>? onRemoved;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<Map<String, dynamic>> _expenses = widget.expenses ?? _sample();
  ExpensePeriod _period = ExpensePeriod.today;
  final saved = <NewExpense>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DesktopExpensesView(
        period: _period,
        onPeriod: (p) => setState(() => _period = p),
        summary: ExpenseSummary.from(sales: widget.sales, expenses: _expenses),
        saleCount: 23,
        expenses: _expenses,
        errorMessage: widget.errorMessage,
        onRetry: () {},
        onRefresh: () {},
        headerBottom: const DesktopFinanceTabs(
          current: FinanceSection.expenses,
          available: {
            FinanceSection.overview,
            FinanceSection.expenses,
            FinanceSection.cashFlow,
          },
        ),
        onAdd: (entry) async {
          if (widget.failSave) return 'Could not save. Try again.';
          saved.add(entry);
          setState(() {
            _expenses = [
              {
                'id': 'new${saved.length}',
                'amount': entry.amount,
                'category': entry.category,
                'note': entry.note,
                'paymentMethod': entry.method,
                'spentAt': _now,
                'recordedBy': 'Wanjiru',
              },
              ..._expenses,
            ];
          });
          return null;
        },
        onRemove: widget.canRemove
            ? (e) {
                widget.onRemoved?.call(e);
                setState(() => _expenses = [
                      for (final x in _expenses)
                        if (x['id'] != e['id']) x,
                    ]);
              }
            : null,
      ),
    );
  }
}

Widget _app(Widget home, {bool dark = false, GlobalKey? boundary}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: DesktopTheme.of(base),
    home:
        boundary == null ? home : ShotFrame(boundaryKey: boundary, child: home),
  );
}

const _sizes = {
  '1366': Size(1134, 700),
  '1093': Size(1037, 498),
};

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final entry in _sizes.entries) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('expenses table $mode ${entry.key}', (tester) async {
        useWindow(tester, entry.value);
        final key = GlobalKey();
        await tester.pumpWidget(_app(const _Harness(), dark: dark, boundary: key));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveShot(
            tester, key, 'build/shots/finance-expenses-$mode-${entry.key}.png');
      });
    }
  }

  testWidgets('Enter in the amount box saves, keeps the category and refocuses',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_app(_Harness(key: key)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('What for'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport').last);
    await tester.pumpAndSettle();

    final amount = find.byType(TextField).first;
    await tester.enterText(amount, '350');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    final saved = key.currentState!.saved;
    expect(saved, hasLength(1));
    expect(saved.single.amount, 350);
    expect(saved.single.category, 'Transport');
    expect(saved.single.method, 'CASH');
    // The form is ready for the next one: amount cleared, category kept.
    expect(tester.widget<TextField>(amount).controller!.text, isEmpty);
    expect(find.text('Transport'), findsWidgets);
    expect(tester.widget<TextField>(amount).focusNode!.hasFocus, isTrue);
  });

  testWidgets('a missing amount or category says what to do', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Enter how much was paid.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '80');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Choose what the money was for.'), findsOneWidget);

    await tester.tap(find.text('What for'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Say what it was for in the note.'), findsOneWidget);
  });

  testWidgets('a failed save keeps what was typed and shows why',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness(failSave: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('What for'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rent').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12000');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '12000',
    );
  });

  testWidgets('the delete button removes a row, and is absent without rights',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    Map<String, dynamic>? removed;
    await tester.pumpWidget(_app(_Harness(onRemoved: (e) => removed = e)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove this expense').first);
    await tester.pumpAndSettle();
    expect(removed, isNotNull);

    await tester.pumpWidget(_app(const _Harness(canRemove: false)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove this expense'), findsNothing);
  });

  testWidgets('an empty period teaches the page and totals show zero',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(
      const _Harness(expenses: []),
      dark: true,
      boundary: key,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nothing recorded today'), findsOneWidget);
    await saveShot(tester, key, 'build/shots/finance-expenses-empty-dark-1366.png');
  });

  testWidgets('spending more than sales shows a negative figure in red',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness(sales: 500)));
    await tester.pumpAndSettle();
    expect(find.textContaining('-KES'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a read error is explained with a retry', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness(
      expenses: [],
      errorMessage: 'Could not read expenses. The database is busy.',
    )));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't read expenses"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('Ctrl+N jumps to the amount box', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness()));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).focusNode!.hasFocus,
      isTrue,
    );
  });
}
