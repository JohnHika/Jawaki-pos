import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_cash_flow_view.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_figures_row.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_finance_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

const _allTabs = {
  FinanceSection.overview,
  FinanceSection.expenses,
  FinanceSection.cashFlow,
};

Widget _tabs(FinanceSection current, {ValueChanged<FinanceSection>? onSelect}) =>
    DesktopFinanceTabs(
      current: current,
      available: _allTabs,
      onSelect: onSelect ?? (_) {},
    );

/// A local shop's day: cash in, cash out and the till count.
DesktopCashFlowView _local({
  bool counted = true,
  VoidCallback? onClose,
  VoidCallback? onHistory,
  double shortfall = -250,
}) {
  return DesktopCashFlowView(
    title: 'Cash flow',
    dateLabel: 'Tuesday, 10 November',
    headerBottom: _tabs(FinanceSection.cashFlow),
    onRefresh: () {},
    figures: const [
      DesktopFigure(label: 'Cash sales', value: 'KES 18,420', hint: '23 sales'),
      DesktopFigure(label: 'Debt collected', value: 'KES 2,500'),
      DesktopFigure(
        label: 'Paid out of the till',
        value: '-KES 6,900',
        hint: 'Suppliers and refunds',
      ),
      DesktopFigure(
        label: 'Net cash movement',
        value: 'KES 14,320',
        hint: 'Before the opening float',
      ),
    ],
    lines: const [
      CashLedgerLine('Cash sales', 18420),
      CashLedgerLine('Debt collected', 2500),
      CashLedgerLine('Cash received on voided sales', 300),
      CashLedgerLine('Cash refunded', -400),
      CashLedgerLine('Supplier payments from the till', -6500),
    ],
    totalLabel: 'Net cash movement',
    total: 14320,
    side: DesktopTillCountPanel(
      counted: counted,
      expected: 14320,
      countedCash: 14320 + shortfall,
      difference: shortfall,
      closedAtLabel: '6:42 PM',
      onClose: onClose ?? () {},
      onHistory: onHistory ?? () {},
    ),
    footnote: 'These figures include completed cash sales, cash received on '
        'voided sales, debt collections, recorded cash refunds and supplier '
        'payments from this branch’s till. They do not include the opening '
        'float, unrecorded expenses, a bank balance or payment-provider '
        'confirmations.',
  );
}

DesktopCashFlowView _cloud({ValueChanged<String>? onMode}) {
  return DesktopCashFlowView(
    title: 'Cash flow',
    dateLabel: 'Today',
    headerBottom: _tabs(FinanceSection.cashFlow),
    onRefresh: () {},
    figures: const [
      DesktopFigure(
        label: 'Available to restock',
        value: 'KES 9,860',
        hint: 'Cash only',
      ),
      DesktopFigure(label: 'Cash in today', value: 'KES 18,420'),
      DesktopFigure(label: 'Cash out today', value: '-KES 8,560'),
    ],
    lines: const [
      CashLedgerLine('Cash sales', 18420),
      CashLedgerLine('Restock purchases', -6500),
      CashLedgerLine('Expenses', -2060),
    ],
    totalLabel: 'Available to restock',
    total: 9860,
    side: DesktopCashModePanel(
      options: const [
        (
          id: 'cashOnly',
          label: 'Cash only',
          description: "Today's cash sales minus today's cash payouts."
        ),
        (
          id: 'allRevenue',
          label: 'All revenue',
          description: "Today's total revenue from any payment method."
        ),
        (
          id: 'runningBalance',
          label: 'Running balance',
          description: 'A running balance carried forward across days.'
        ),
      ],
      selectedId: 'cashOnly',
      changing: false,
      onChanged: onMode ?? (_) {},
      onReconcile: () {},
      onEndOfDay: () {},
    ),
  );
}

Widget _app(Widget body, {bool dark = false, GlobalKey? boundary}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  final home = Scaffold(body: body);
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
      testWidgets('cash flow, a local shop $mode ${entry.key}', (tester) async {
        useWindow(tester, entry.value);
        final key = GlobalKey();
        await tester.pumpWidget(_app(_local(), dark: dark, boundary: key));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveShot(
            tester, key, 'build/shots/finance-cashflow-$mode-${entry.key}.png');
      });
    }
  }

  testWidgets('cash flow for a cloud shop lets the mode be changed',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    String? picked;
    final key = GlobalKey();
    await tester.pumpWidget(
        _app(_cloud(onMode: (id) => picked = id), boundary: key));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('All revenue'));
    expect(picked, 'allRevenue');
    await saveShot(tester, key, 'build/shots/finance-cashflow-cloud-light-1366.png');
  });

  testWidgets('the ledger shows outflows with a minus and totals the day',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_local()));
    await tester.pumpAndSettle();
    expect(find.text('-KES 6,500.00'), findsOneWidget);
    expect(find.text('+KES 18,420.00'), findsOneWidget);
    expect(find.text('+KES 14,320.00'), findsOneWidget);
  });

  testWidgets('an uncounted till offers the count, a counted one shows the gap',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    var closed = 0;
    await tester.pumpWidget(
        _app(_local(counted: false, onClose: () => closed++)));
    await tester.pumpAndSettle();
    expect(find.text('Not counted'), findsOneWidget);
    await tester.tap(find.text('Count the till'));
    expect(closed, 1);

    await tester.pumpWidget(_app(_local()));
    await tester.pumpAndSettle();
    expect(find.text('Shortfall'), findsOneWidget);
    expect(find.text('Review or close again'), findsOneWidget);
  });

  testWidgets('loading, error and empty states say what is going on',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const DesktopCashFlowView(
      title: 'Cash flow',
      figures: [],
      lines: [],
      totalLabel: '',
      total: 0,
      loading: true,
    )));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(_app(DesktopCashFlowView(
      title: 'Cash flow',
      figures: const [],
      lines: const [],
      totalLabel: '',
      total: 0,
      errorMessage: 'No connection. Try again when you are online.',
      onRetry: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load cash flow"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.pumpWidget(_app(const DesktopCashFlowView(
      title: 'Cash flow',
      figures: [],
      lines: [],
      totalLabel: '',
      total: 0,
      emptyTitle: 'No shop selected',
      emptyMessage: 'Choose or create a local shop to view cash activity.',
    )));
    await tester.pumpAndSettle();
    expect(find.text('No shop selected'), findsOneWidget);
  });

  group('finance tabs', () {
    testWidgets('mark the current page and move to another', (tester) async {
      FinanceSection? went;
      await tester.pumpWidget(_app(_tabs(
        FinanceSection.expenses,
        onSelect: (s) => went = s,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash flow'));
      expect(went, FinanceSection.cashFlow);
      went = null;
      await tester.tap(find.text('Expenses'));
      expect(went, isNull, reason: 'the current tab does nothing');
    });

    testWidgets('leave out a page the role cannot open', (tester) async {
      await tester.pumpWidget(_app(const DesktopFinanceTabs(
        current: FinanceSection.cashFlow,
        available: {FinanceSection.cashFlow},
      )));
      await tester.pumpAndSettle();
      // A single tab is not worth showing.
      expect(find.text('Cash flow'), findsNothing);

      expect(
        DesktopFinanceTabs.forRole(canViewFinance: true, canViewCashFlow: false),
        {FinanceSection.overview, FinanceSection.expenses},
      );
    });
  });
}
