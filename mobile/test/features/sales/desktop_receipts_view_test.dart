import 'package:axon_pos/core/database/app_database.dart' show PendingSale;
import 'package:axon_pos/core/desktop/desktop_split.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/sales/presentation/receipts_desktop/desktop_receipt_inspector.dart';
import 'package:axon_pos/features/sales/presentation/receipts_desktop/desktop_receipt_page.dart';
import 'package:axon_pos/features/sales/presentation/receipts_desktop/desktop_receipts_view.dart';
import 'package:axon_pos/features/sales/presentation/receipts_desktop/receipt_thermal_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

const _customers = {
  'c1': 'Wanjiru Kamau',
  'c2': 'Otieno Hardware & General Supplies Limited',
  'c3': 'Halima Abdi',
  'c4': 'Mama Njeri',
};
const _phones = {
  'c1': '0712 345 678',
  'c2': '0722 111 222',
  'c3': '+254733987654',
  'c4': '0700 000 111',
};
const _methods = ['CASH', 'MPESA', 'CASH', 'CARD', 'MPESA', 'CREDIT', 'SPLIT'];

final _now = DateTime(2026, 11, 10, 15, 30);

PendingSale _sale(int i, {String? id}) => PendingSale(
      id: id ?? 'sale-${i.toString().padLeft(4, '0')}-abcdef',
      receiptNumber: 'R-${(2400 - i).toString().padLeft(5, '0')}',
      subtotal: 150.0 + i * 37.5,
      discount: 0,
      tax: 0,
      total: 150.0 + i * 37.5,
      paymentMethod: _methods[i % _methods.length],
      paymentReference: i % 5 == 4 ? 'SBK4X9Q2LM' : null,
      customerId: i % 3 == 0 ? 'c${(i ~/ 3) % 4 + 1}' : null,
      cashierId: i % 4 == 0 ? 'u2' : 'u1',
      branchId: 'b1',
      notes: null,
      status: i % 11 == 5 ? 'VOIDED' : 'COMPLETED',
      createdAt: _now.subtract(Duration(minutes: i * 47)),
      isSynced: i % 13 != 7,
      syncedAt: null,
      voidReason: i % 11 == 5 ? 'Wrong item rung up' : null,
      voidedBy: null,
      voidedAt: null,
    );

List<PendingSale> _sales([int count = 36]) =>
    [for (var i = 0; i < count; i++) _sale(i)];

/// What `receiptProvider` yields for a sale, built from sample data.
Map<String, dynamic> _receipt(PendingSale s) => {
      'id': s.id,
      'receiptNumber': s.receiptNumber,
      'subtotal': s.subtotal,
      'discount': 0.0,
      'tax': 0.0,
      'total': s.total,
      'paymentMethod': s.paymentMethod,
      'paymentReference': s.paymentReference,
      'createdAt': s.createdAt.toIso8601String(),
      'branchName': 'Mama Njeri Supplies - Githurai',
      'branchAddress': 'Githurai 45, next to the market',
      'branchPhone': '0722 000 111',
      'hasCustomer': s.customerId != null,
      'linkedCustomerDetailsHidden': false,
      if (s.paymentMethod == 'CASH') 'cashGiven': 2000.0,
      if (s.paymentMethod == 'CASH') 'changeGiven': 2000.0 - s.total,
      'cashierName': 'Wanjiru',
      'customerName': _customers[s.customerId],
      'customerPhone': _phones[s.customerId],
      'status': s.status,
      'isSynced': s.isSynced,
      'voidReason': s.voidReason,
      'creditAmountAtSale': s.paymentMethod == 'CREDIT' ? s.total : 0.0,
      'paymentTenders': s.paymentMethod == 'SPLIT'
          ? [
              {'method': 'CASH', 'amount': 100.0},
              {'method': 'MPESA', 'amount': s.total - 100},
            ]
          : null,
      'items': [
        {
          'productName': 'Sugar 2kg',
          'quantity': 2.0,
          'unitPrice': 310.0,
          'total': 620.0,
          'unit': 'piece',
          'quantityPerUnit': 1.0,
        },
        {
          'productName':
              'Blue Band margarine Original 500g tub family pack special offer',
          'quantity': 1.0,
          'unitPrice': 285.0,
          'total': 285.0,
          'unit': 'piece',
          'quantityPerUnit': 1.0,
        },
        {
          'productName': 'Maize flour 2kg',
          'quantity': 3.0,
          'unitPrice': 155.0,
          'total': 465.0,
          'unit': 'box',
          'quantityPerUnit': 12.0,
        },
      ],
    };

class _Harness extends StatefulWidget {
  const _Harness({
    required this.sales,
    this.selectedId,
    this.rangeDays = 30,
    this.loading = false,
    this.errorMessage,
    this.canViewCustomerDetails = true,
    this.onOpen,
    this.onPrint,
  });

  final List<PendingSale> sales;
  final String? selectedId;
  final int? rangeDays;
  final bool loading;
  final String? errorMessage;
  final bool canViewCustomerDetails;
  final ValueChanged<PendingSale>? onOpen;
  final ValueChanged<PendingSale>? onPrint;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late int? _range = widget.rangeDays;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DesktopReceiptsView(
        title: 'Receipts',
        sales: widget.sales,
        loading: widget.loading,
        errorMessage: widget.errorMessage,
        onRetry: () {},
        onRefresh: () {},
        rangeDays: _range,
        onRangeChanged: (d) => setState(() => _range = d),
        canViewCustomerDetails: widget.canViewCustomerDetails,
        customerNames: _customers,
        customerPhones: _phones,
        cashierNames: const {'u1': 'Wanjiru'},
        initialSelectedId: widget.selectedId,
        onOpen: widget.onOpen,
        onPrint: widget.onPrint,
        inspectorBuilder: (context, sale, close) => DesktopReceiptInspector(
          receipt: _receipt(sale),
          fallbackNumber: sale.id.substring(0, 8).toUpperCase(),
          showTax: false,
          waitingToSync: !sale.isSynced,
          canVoid: true,
          onClose: close,
          onOpen: () => widget.onOpen?.call(sale),
          onPrint: () => widget.onPrint?.call(sale),
          onShare: () {},
          onVoid: () {},
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

/// Page area inside the shell: sidebar 232 at 1366, rail 56 at 1093, top bar
/// 44 and status bar 24 above and below.
const _sizes = {
  '1366': Size(1134, 700),
  '1093': Size(1037, 498),
};

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final entry in _sizes.entries) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('receipts table with inspector $mode ${entry.key}',
          (tester) async {
        useWindow(tester, entry.value);
        final key = GlobalKey();
        final sales = _sales();
        await tester.pumpWidget(_app(
          _Harness(sales: sales, selectedId: sales[1].id),
          dark: dark,
          boundary: key,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveShot(
            tester, key, 'build/shots/receipts-table-$mode-${entry.key}.png');
      });

      testWidgets('receipt page $mode ${entry.key}', (tester) async {
        useWindow(tester, entry.value);
        final key = GlobalKey();
        final sale = _sale(8);
        await tester.pumpWidget(_app(
          Scaffold(
            body: DesktopReceiptPage(
              receipt: _receipt(sale),
              fallbackNumber: 'ABCDEF12',
              showTax: false,
              canVoid: true,
              waitingToSync: true,
              onClose: () {},
              onPrint: () {},
              onShare: () {},
              onVoid: () {},
              onNewSale: () {},
            ),
          ),
          dark: dark,
          boundary: key,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await saveShot(
            tester, key, 'build/shots/receipts-page-$mode-${entry.key}.png');
      });
    }
  }

  testWidgets('without a selection the table fills the page', (tester) async {
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(_Harness(sales: _sales()), boundary: key));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('36 receipts'), findsOneWidget);
    expect(find.byType(DesktopInspector), findsNothing);
    await saveShot(tester, key, 'build/shots/receipts-open-light-1366.png');
  });

  testWidgets('clicking a row shows the thermal receipt, Esc closes it',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(sales: _sales())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#R-02400').first);
    await tester.pumpAndSettle();
    expect(find.text('Receipt preview'), findsOneWidget);
    expect(find.textContaining('Receipt #R-02400'), findsWidgets);
    expect(find.textContaining('Thank you for your purchase!'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Receipt preview'), findsNothing);
  });

  testWidgets('arrow keys move the selection and the preview follows',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(sales: _sales())));
    await tester.pumpAndSettle();
    // Sorted newest first: R-02400, then R-02399.
    await tester.tap(find.text('#R-02400').first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DesktopInspector),
        matching: find.text('Receipt #R-02399'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Open and Ctrl+P act on the picked receipt', (tester) async {
    useWindow(tester, _sizes['1366']!);
    PendingSale? opened;
    PendingSale? printed;
    await tester.pumpWidget(_app(_Harness(
      sales: _sales(),
      onOpen: (s) => opened = s,
      onPrint: (s) => printed = s,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#R-02400').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(opened?.receiptNumber, 'R-02400');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(printed?.receiptNumber, 'R-02400');
  });

  testWidgets('search finds a receipt by number, customer name or phone',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(sales: _sales())));
    await tester.pumpAndSettle();
    final field = find.byType(TextField).first;

    await tester.enterText(field, 'R-02390');
    await tester.pumpAndSettle();
    expect(find.text('1 receipt'), findsOneWidget);

    await tester.enterText(field, 'halima');
    await tester.pumpAndSettle();
    expect(find.textContaining('receipt'), findsWidgets);
    expect(find.text('Halima Abdi'), findsWidgets);

    await tester.enterText(field, 'zzqx');
    await tester.pumpAndSettle();
    expect(find.text('No receipts match'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
  });

  testWidgets(
      'customer details stay hidden and unsearchable without permission',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(
      sales: [_sale(0)],
      canViewCustomerDetails: false,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Customer details hidden'), findsOneWidget);
    expect(find.text('Wanjiru Kamau'), findsNothing);
    expect(find.text('0712 345 678'), findsNothing);
    expect(find.text('Receipt or payment'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Wanjiru Kamau');
    await tester.pumpAndSettle();
    expect(find.text('No receipts match'), findsOneWidget);
    expect(find.text('Customer details hidden'), findsNothing);
  });

  testWidgets('Voided chip narrows the table to cancelled sales',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(sales: _sales())));
    await tester.pumpAndSettle();
    // i % 11 == 5 within 0..35: 5, 16, 27.
    await tester.tap(find.text('Voided').first);
    await tester.pumpAndSettle();
    expect(find.text('3 receipts'), findsOneWidget);
    expect(find.text('Voided'), findsWidgets);
  });

  testWidgets('a quiet day says so and offers a longer range', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness(sales: [], rangeDays: 0)));
    await tester.pumpAndSettle();
    expect(find.text('No receipts today'), findsOneWidget);
    expect(find.text('Show all time'), findsOneWidget);
    await tester.tap(find.text('Show all time'));
    await tester.pumpAndSettle();
    expect(find.text('All time'), findsOneWidget);
  });

  testWidgets('a failed load says what happened and offers a retry',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(
      const _Harness(
        sales: [],
        errorMessage: 'No connection. Your saved receipts are safe.',
      ),
      dark: true,
      boundary: key,
    ));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load receipts"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await saveShot(tester, key, 'build/shots/receipts-error-dark-1366.png');
  });

  testWidgets('loading shows skeleton rows, not a spinner page',
      (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(const _Harness(sales: [], loading: true)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Receipt'), findsOneWidget);
  });

  testWidgets('5,000 receipts stay scrollable', (tester) async {
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(_Harness(sales: _sales(5000))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('5,000 receipts'), findsOneWidget);
  });

  test('the thermal text keeps every line inside the roll width', () {
    final sale = _sale(8);
    for (final cols in [thermalColumns58mm, thermalColumns80mm]) {
      final text = renderThermalReceiptText(
        _receipt(sale),
        fallbackNumber: 'ABCDEF12',
        showTax: false,
        columns: cols,
      );
      for (final line in text.split('\n')) {
        expect(line.length, lessThanOrEqualTo(cols), reason: line);
      }
      expect(text, contains('TOTAL  KES'));
    }
  });
}
