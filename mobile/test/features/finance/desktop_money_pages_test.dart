import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/services/supplier_receipt_ocr_service.dart';
import 'package:axon_pos/features/finance/domain/collections_ledger.dart';
import 'package:axon_pos/features/finance/domain/finance_models.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_end_of_day_view.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_figures_row.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_invoice_review_view.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_reconciliation_view.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_shop_ledger_view.dart';
import 'package:axon_pos/features/finance/presentation/screens/invoice_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

// ── End of day ──────────────────────────────────────────────────────────

DesktopEndOfDayView _eod({
  bool closed = false,
  VoidCallback? onPrimary,
  bool restricted = false,
  bool loading = false,
  String? error,
}) =>
    DesktopEndOfDayView(
      dateLabel: 'Tuesday, 10 November',
      closed: closed,
      statusLabel: closed
          ? 'Day closed at 10 Nov, 18:42'
          : 'On-device sales summary',
      restricted: restricted,
      loading: loading,
      errorMessage: error,
      onRetry: () {},
      notices: const [
        DesktopEodNotice(
            'Figures come from this computer. When you close, enter your '
            'opening float and any cash you added or took out, and explain '
            'it in the notes.'),
        DesktopEodNotice(
          '3 recorded payments to check against your own M-Pesa or bank '
          'statement. Counterbase has not verified them.',
          icon: Icons.fact_check_outlined,
        ),
      ],
      figures: const [
        DesktopFigure(label: 'Total sales', value: 'KES 31,640', hint: '42 sales'),
        DesktopFigure(label: 'Average sale', value: 'KES 753'),
        DesktopFigure(label: 'Cash sales', value: 'KES 18,420'),
        DesktopFigure(label: 'Expected cash in till', value: 'KES 14,320'),
      ],
      salesRows: const [
        DesktopEodRow('Total sales', 'KES 31,640', strong: true),
        DesktopEodRow('Transactions', '42'),
        DesktopEodRow('Cash sales', 'KES 18,420'),
        DesktopEodRow('Cash debt collections', 'KES 2,500'),
        DesktopEodRow('Supplier payments from till', '-KES 6,500'),
        DesktopEodRow('M-Pesa', 'KES 9,800'),
        DesktopEodRow('Card', 'KES 1,200'),
        DesktopEodRow('Credit', 'KES 2,220'),
        DesktopEodRow('Expected cash in till', 'KES 14,320', strong: true),
      ],
      closeTitle: closed ? 'Latest till close' : 'Close the day',
      closeRows: closed
          ? const [
              DesktopEodRow('Opening float', 'KES 2,000'),
              DesktopEodRow('Counted cash', 'KES 14,070'),
              DesktopEodRow('Discrepancy', '-KES 250'),
            ]
          : const [],
      closeNote: closed
          ? 'The day is already closed. Re-close only if you re-counted the till.'
          : null,
      actions: [
        DesktopEodAction('Add an expense paid today',
            Icons.request_quote_outlined, () {}),
        DesktopEodAction('Match M-Pesa statement', Icons.fact_check_outlined, () {}),
      ],
      primaryLabel: closed ? 'Re-close day' : 'Close end of day',
      onPrimary: onPrimary ?? () {},
      onBack: () {},
      onRefresh: () {},
    );

// ── Reconciliation ──────────────────────────────────────────────────────

final _counts = [
  DesktopCountRecord(
    id: 'c1',
    at: DateTime(2026, 11, 10, 18, 42),
    expected: 14320,
    counted: 14070,
    difference: -250,
    countedBy: 'Asha',
    notes: 'Two KES 100 notes were given as change twice.',
  ),
  DesktopCountRecord(
    id: 'c2',
    at: DateTime(2026, 11, 9, 19, 5),
    expected: 11800,
    counted: 11800,
    difference: 0,
    countedBy: 'Njeri',
  ),
  DesktopCountRecord(
    id: 'c3',
    at: DateTime(2026, 11, 8, 18, 30),
    expected: 9650,
    counted: 9700,
    difference: 50,
    countedBy: 'Asha',
  ),
];

// ── Shop ledger ─────────────────────────────────────────────────────────

final _now = DateTime.now();

PeerDebtor _shop() => PeerDebtor(
      id: 's1',
      tenantId: 't',
      name: 'Mama Njeri Wholesalers',
      contactName: 'Njeri W.',
      phone: '0712 000 111',
      email: null,
      address: null,
      notes: null,
      isActive: true,
      createdAt: _now,
      updatedAt: _now,
    );

PeerReceivable _debt(String id, String what, double original, double left,
        {DateTime? due}) =>
    PeerReceivable(
      id: id,
      debtor: _shop(),
      reference: null,
      description: what,
      originalAmount: original,
      outstandingAmount: left,
      dueDate: due,
      status: left <= 0 ? 'PAID' : 'OPEN',
      createdAt: _now.subtract(const Duration(days: 30)),
      payments: const [],
    );

ShopStatement _statement() => ShopStatement(
      shop: _shop(),
      debts: [
        _debt('d1', '12 cartons of soap', 14400, 9400,
            due: _now.subtract(const Duration(days: 3))),
        _debt('d2', 'Cooking oil 20L x6', 9000, 9000,
            due: _now.add(const Duration(days: 9))),
        _debt('d3', 'Sugar 50kg', 5000, 0),
      ],
      collections: [
        CollectionEntry(
          paymentId: 'p1',
          receivableId: 'd1',
          who: 'Mama Njeri Wholesalers',
          what: '12 cartons of soap',
          amount: 5000,
          method: 'MPESA',
          paidAt: _now.subtract(const Duration(days: 2)),
          isShop: true,
          reference: 'SKL92KD0',
        ),
        CollectionEntry(
          paymentId: 'p2',
          receivableId: 'd3',
          who: 'Mama Njeri Wholesalers',
          what: 'Sugar 50kg',
          amount: 5000,
          method: 'CASH',
          paidAt: _now.subtract(const Duration(days: 12)),
          isShop: true,
        ),
      ],
      originalTotal: 28400,
      outstanding: 18400,
    );

DesktopShopLedgerView _ledger({
  bool canRecord = true,
  VoidCallback? onRecord,
  bool empty = false,
}) {
  final s = empty
      ? ShopStatement(
          shop: _shop(),
          debts: const [],
          collections: const [],
          originalTotal: 0,
          outstanding: 0,
        )
      : _statement();
  return DesktopShopLedgerView(
    title: 'Mama Njeri Wholesalers',
    statement: s,
    instalments: mergeInstalments(s.collections),
    canRecord: canRecord,
    onRecord: onRecord ?? () {},
    onBack: () {},
    onRefresh: () {},
    statementAction: OutlinedButton(
      onPressed: () {},
      child: const Text('Send statement'),
    ),
  );
}

// ── Invoice review ──────────────────────────────────────────────────────

SupplierReceiptScan _scan({int lines = 3}) => SupplierReceiptScan(
      imagePath: '',
      rawText: '',
      suggestedSupplierName: 'Kamau Wholesalers',
      invoiceNumber: 'INV-0042',
      totalAmount: 12400,
      summary: 'Three lines read from a printed invoice dated 9 Nov.',
      readByAi: true,
      documentType: 'supplier_invoice',
      items: [
        for (var i = 0; i < lines; i++)
          SupplierReceiptLineItem(
            name: 'Aberlife Water 500ml (bale of 24) $i',
            quantity: 10,
            unit: 'bale',
            unitCost: 620,
            lineTotal: 6200,
            confidence: 0.9,
            rawText: '',
          ),
      ],
    );

Widget _invoiceScreen({int lines = 3}) => ProviderScope(
      child: DesktopScope(
        sidebarCollapsed: true,
        child: InvoiceReviewScreen(scan: _scan(lines: lines)),
      ),
    );

Widget _invoiceView({int lines = 2}) => _InvoiceHarness(lines: lines);

class _InvoiceHarness extends StatefulWidget {
  const _InvoiceHarness({required this.lines});
  final int lines;

  @override
  State<_InvoiceHarness> createState() => _InvoiceHarnessState();
}

class _InvoiceHarnessState extends State<_InvoiceHarness> {
  final supplier = TextEditingController(text: 'Kamau Wholesalers');
  final invoice = TextEditingController(text: 'INV-0042');
  final terms = TextEditingController(text: 'Pay later');
  final paid = TextEditingController(text: '2000');
  late final List<List<TextEditingController>> rows = [
    for (var i = 0; i < widget.lines; i++)
      [
        TextEditingController(text: 'Aberlife Water 500ml (bale) $i'),
        TextEditingController(text: 'AW-$i'),
        TextEditingController(text: '10'),
        TextEditingController(text: '620'),
      ],
  ];
  bool credit = false;

  @override
  Widget build(BuildContext context) {
    final total = widget.lines * 6200.0;
    return DesktopInvoiceReviewView(
      supplier: supplier,
      invoiceNumber: invoice,
      terms: terms,
      paid: paid,
      dueLabel: '10 Dec 2026',
      fundingCredit: credit,
      lines: [
        for (final r in rows)
          DesktopInvoiceLine(
            name: r[0],
            sku: r[1],
            quantity: r[2],
            unitCost: r[3],
            lineTotal: 6200,
          ),
      ],
      total: total,
      paidAmount: 2000,
      balanceDue: total - 2000,
      canSave: true,
      saving: false,
      aiLabel: 'Axon AI · Supplier invoice',
      summary: 'Two lines read from a printed invoice dated 9 Nov.',
      onSave: () {},
      onAddLine: () {},
      onPickDue: () {},
      onFundingChanged: (v) => setState(() => credit = v),
      onChanged: () => setState(() {}),
      onRemoveLine: (_) {},
      onBack: () {},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadShotFonts);

  group('End of day', () {
    shotMatrix('eod-open', () => _eod());
    shotMatrix('eod-closed', () => _eod(closed: true));

    testWidgets('Ctrl+Enter and the button both close the day', (tester) async {
      useWindow(tester, desktopSizes['1366']!);
      var closes = 0;
      await tester.pumpWidget(desktopApp(_eod(onPrimary: () => closes++)));
      await tester.pumpAndSettle();
      expect(find.text('Close end of day'), findsOneWidget);
      expect(find.text("Today's sales"), findsOneWidget);
      await tester.tap(find.text('Close end of day'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(closes, 2);
    });

    testWidgets('a blocked close greys the button out', (tester) async {
      useWindow(tester, desktopSizes['1366']!);
      await tester.pumpWidget(desktopApp(const DesktopEndOfDayView(
        statusLabel: 'Close status unavailable',
        primaryLabel: 'Reconnect to verify sales',
        onPrimary: null,
        salesRows: [DesktopEodRow('Total sales', 'Unavailable')],
      )));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('restricted, loading and error states', (tester) async {
      useWindow(tester, desktopSizes['1093']!);
      await tester.pumpWidget(desktopApp(_eod(restricted: true)));
      await tester.pumpAndSettle();
      expect(find.text('End of day is restricted'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      await tester.pumpWidget(desktopApp(_eod(error: 'No connection.')));
      await tester.pumpAndSettle();
      expect(find.text('No connection.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await tester.pumpWidget(desktopApp(_eod(loading: true)));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Cash reconciliation', () {
    shotMatrix(
      'reconciliation',
      () => DesktopReconciliationView(
        records: _counts,
        subtitle: 'Expected against counted cash, most recent first',
        onCount: () {},
        onBack: () {},
        onRefresh: () {},
      ),
    );
    shotMatrix(
      'reconciliation-selected',
      () => DesktopReconciliationView(
        records: _counts,
        onCount: () {},
        onBack: () {},
        onRefresh: () {},
      ),
      beforeShot: (tester) async {
        await tester.tap(find.text('Asha').first);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('a row opens its notes and Esc closes them', (tester) async {
      useWindow(tester, desktopSizes['1366']!);
      await tester.pumpWidget(desktopApp(DesktopReconciliationView(
        records: _counts,
        onCount: () {},
        onRefresh: () {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('Shortfall'), findsWidgets);
      expect(find.textContaining('given as change'), findsNothing);
      await tester.tap(find.text('Asha').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('given as change'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.textContaining('given as change'), findsNothing);
    });

    testWidgets('empty, hidden history and restricted states', (tester) async {
      useWindow(tester, desktopSizes['1366']!);
      await tester.pumpWidget(desktopApp(const DesktopReconciliationView(
        records: [],
        emptyTitle: 'No till closes yet',
        emptyMessage: 'Close the day to save your first record.',
      )));
      await tester.pumpAndSettle();
      expect(find.text('No till closes yet'), findsOneWidget);
      await tester.pumpWidget(desktopApp(DesktopReconciliationView(
        records: const [],
        historyHidden: true,
        onCount: () {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('History access not enabled'), findsOneWidget);
      expect(find.text('Count cash'), findsOneWidget);
      await tester.pumpWidget(desktopApp(const DesktopReconciliationView(
        records: [],
        restricted: true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Cash reconciliation is restricted'), findsOneWidget);
    });
  });

  group('Shop ledger', () {
    shotMatrix('shop-ledger', () => _ledger());

    testWidgets('shows the balance, debts and instalments', (tester) async {
      useWindow(tester, desktopSizes['1366']!);
      var recorded = 0;
      await tester.pumpWidget(
          desktopApp(_ledger(onRecord: () => recorded++)));
      await tester.pumpAndSettle();
      expect(find.text('Still owes you'), findsOneWidget);
      expect(find.text('KES 18,400'), findsWidgets);
      expect(find.text('12 cartons of soap'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Cleared'), findsOneWidget);
      expect(find.textContaining('Towards Sugar 50kg'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-installment')));
      expect(recorded, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no record button without permission or a balance',
        (tester) async {
      useWindow(tester, desktopSizes['1093']!);
      await tester.pumpWidget(desktopApp(_ledger(canRecord: false)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('record-installment')), findsNothing);
      await tester.pumpWidget(desktopApp(_ledger(empty: true)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('record-installment')), findsNothing);
      expect(find.text('No debts recorded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Invoice review', () {
    shotMatrix('invoice-review', () => _invoiceView());

    testWidgets('the routed screen switches to the desktop layout',
        (tester) async {
      useWindow(tester, desktopSizes['1366']!);
      await tester.pumpWidget(MaterialApp(home: _invoiceScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopInvoiceReviewView), findsOneWidget);
      expect(find.text('Kamau Wholesalers'), findsOneWidget);
      expect(find.text('INV-0042'), findsOneWidget);
      expect(find.text('Save invoice'), findsOneWidget);
      // 3 lines x KES 6,200.
      expect(find.text('KES 18,600'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add item and Remove keep totals in step', (tester) async {
      useWindow(tester, desktopSizes['1093']!);
      await tester.pumpWidget(MaterialApp(home: _invoiceScreen(lines: 1)));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove item'), findsNothing);
      await tester.tap(find.text('Add item').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove item'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Remove item').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove item'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('outside the desktop shell the phone layout is kept',
        (tester) async {
      useWindow(tester, const Size(390, 800));
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: InvoiceReviewScreen(scan: _scan())),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopInvoiceReviewView), findsNothing);
      expect(find.text('Review Invoice'), findsOneWidget);
    });
  });
}
