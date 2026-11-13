import 'package:axon_pos/core/desktop/desktop_split.dart';
import 'package:axon_pos/core/desktop/desktop_table.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/desktop/desktop_widgets.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/payments/presentation/desktop/desktop_payment_inspector.dart';
import 'package:axon_pos/features/payments/presentation/desktop/desktop_payments_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

final _today = DateTime(2026, 11, 10, 16, 20);

List<DesktopPaymentRow> _sample([int count = 24]) {
  const methods = [
    'CASH',
    'MPESA',
    'MPESA_RECORDED',
    'CASH',
    'CARD',
    'SPLIT',
    'BANK_RECORDED',
    'CREDIT',
  ];
  return [
    for (var i = 0; i < count; i++)
      () {
        final m = methods[i % methods.length];
        final recorded = m.endsWith('_RECORDED');
        final amount = 180.0 + i * 64;
        return DesktopPaymentRow(
          saleId: 's$i',
          receiptNumber: 'R-${(2400 - i).toString().padLeft(5, '0')}',
          at: _today.subtract(Duration(minutes: i * 38)),
          method: m,
          amount: amount,
          reference: m == 'MPESA'
              ? 'SKB${7 + i}X9Q2LM'
              : recorded
                  ? 'TKD${i}M4P8ZQ'
                  : m == 'CARD'
                      ? 'POS-77${i}1'
                      : null,
          recorded: recorded,
          checked: recorded && i % 4 == 0,
          checkedBy: 'Wanjiru',
          checkedAt: _today,
          checkNote: 'Seen on the statement',
          recordedBy: recorded ? 'Wanjiru' : null,
          tenders: m == 'SPLIT'
              ? [
                  (method: 'CASH', amount: 100.0),
                  (method: 'MPESA', amount: amount - 100),
                ]
              : const [],
        );
      }(),
  ];
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.payments,
    this.selectedId,
    this.loading = false,
    this.errorMessage,
    this.restricted = false,
    this.pending = const [],
    this.onMatch,
    this.onCheck,
  });

  final List<DesktopPaymentRow> payments;
  final String? selectedId;
  final bool loading;
  final String? errorMessage;
  final bool restricted;
  final List<DesktopPendingCharge> pending;
  final ValueChanged<DesktopPaymentRow>? onMatch;
  final ValueChanged<String>? onCheck;

  @override
  Widget build(BuildContext context) {
    final total = payments.fold<double>(0, (sum, r) => sum + r.amount);
    return Scaffold(
      body: DesktopPaymentsView(
        title: 'Payments',
        payments: payments,
        totalToday: total,
        loading: loading,
        errorMessage: errorMessage,
        onRetry: () {},
        onRefresh: () {},
        initialSelectedId: selectedId,
        pendingCharges: pending,
        onCheckCharge: onCheck,
        footnote: 'Figures include sales saved on this computer only, not '
            'other devices.',
        links: [
          DesktopPaymentLink(
            label: 'Receipts',
            icon: Icons.receipt_long_outlined,
            onTap: () {},
          ),
          DesktopPaymentLink(
            label: 'Reports',
            icon: Icons.analytics_outlined,
            onTap: () {},
          ),
          DesktopPaymentLink(
            label: 'Customer credit',
            icon: Icons.credit_score_outlined,
            onTap: () {},
          ),
        ],
        restrictedMessage: restricted
            ? 'Your role can see which payment methods the shop accepts, but '
                'not the takings.'
            : null,
        methodsAvailable: const ['Cash', 'M-Pesa', 'Customer debt'],
        inspectorBuilder: (context, row, close) => DesktopPaymentInspector(
          payment: row,
          onClose: close,
          onOpenReceipt: () {},
          onMatch: row.unmatched ? () => onMatch?.call(row) : null,
        ),
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

/// Text inside the table (its footer), not the figures strip above it.
Finder _inTable(String text) => find.descendant(
      of: find.byType(DesktopDataTable<DesktopPaymentRow>),
      matching: find.text(text),
    );

/// Page area inside the shell at 1366 (sidebar) and 1093 (rail).
const _sizes = {
  '1366': Size(1134, 700),
  '1093': Size(1037, 498),
};

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final entry in _sizes.entries) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('payments table with an unmatched payment $mode ${entry.key}',
          (tester) async {
        useWindow(tester, entry.value);
        final key = GlobalKey();
        await tester.pumpWidget(_app(
          _Harness(
            payments: _sample(),
            selectedId: 's2',
            pending: const [
              DesktopPendingCharge(
                reference: 'CHG-7731',
                amount: '1,500',
                status: 'PENDING',
              ),
            ],
          ),
          dark: dark,
          boundary: key,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveShot(
            tester, key, 'build/shots/payments-table-$mode-${entry.key}.png');
      });
    }
  }

  testWidgets('the Unmatched tab narrows to typed-in codes not yet checked',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(_Harness(payments: _sample()), boundary: key));
    await tester.pumpAndSettle();
    // Recorded rows are i % 8 == 2 or 6 in 0..23: 2, 6, 10, 14, 18, 22; those
    // with i % 4 == 0 are checked: none of them (all are 2 mod 4), so 6.
    await tester.tap(find.widgetWithText(DesktopFilterChip, 'Unmatched'));
    await tester.pumpAndSettle();
    expect(_inTable('6 payments'), findsOneWidget);
    await saveShot(tester, key, 'build/shots/payments-unmatched-light-1366.png');
  });

  testWidgets('Match shows only for an unmatched payment and reports it',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    DesktopPaymentRow? matched;
    await tester.pumpWidget(_app(
      _Harness(payments: _sample(), onMatch: (r) => matched = r),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Match'), findsNothing);
    await tester.tap(find.text('#R-02398').first);
    await tester.pumpAndSettle();
    expect(find.text('Match'), findsOneWidget);
    await tester.tap(find.text('Match'));
    await tester.pump();
    expect(matched?.saleId, 's2');

    // A cash payment has nothing to match.
    await tester.tap(find.text('#R-02400').first);
    await tester.pumpAndSettle();
    expect(find.text('Match'), findsNothing);
  });

  testWidgets('method tabs count split payments under each of their methods',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(payments: _sample())));
    await tester.pumpAndSettle();
    // Cash: i%8 in {0, 3} -> 6 rows, plus split (i%8==5) -> 3 rows = 9.
    await tester.tap(find.widgetWithText(DesktopFilterChip, 'Cash'));
    await tester.pumpAndSettle();
    expect(_inTable('9 payments'), findsOneWidget);
  });

  testWidgets('Esc closes the inspector', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(payments: _sample())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#R-02400').first);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopInspector), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopInspector), findsNothing);
  });

  testWidgets('a pending M-Pesa request can be checked', (tester) async {
    useWindow(tester, _sizes['1366']!);
    String? checked;
    await tester.pumpWidget(_app(_Harness(
      payments: _sample(),
      pending: const [
        DesktopPendingCharge(
          reference: 'CHG-7731',
          amount: '1,500',
          status: 'NEEDS_REVIEW',
        ),
      ],
      onCheck: (ref) => checked = ref,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check'));
    expect(checked, 'CHG-7731');
  });

  testWidgets('an empty day teaches the page', (tester) async {
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(
      _app(const _Harness(payments: []), dark: true, boundary: key),
    );
    await tester.pumpAndSettle();
    expect(find.text('No payments yet today'), findsOneWidget);
    await saveShot(tester, key, 'build/shots/payments-empty-dark-1366.png');
  });

  testWidgets('a role without takings access is told why', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(
      _app(const _Harness(payments: [], restricted: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Takings are not shown to your role'), findsOneWidget);
    expect(find.text('Customer debt'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness(
      payments: [],
      errorMessage: 'No connection. Your saved sales are safe.',
    )));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load payments"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('loading shows skeleton rows', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness(payments: [], loading: true)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Receipt'), findsOneWidget);
  });
}
