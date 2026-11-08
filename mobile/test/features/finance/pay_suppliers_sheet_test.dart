import 'package:axon_pos/features/finance/domain/finance_models.dart';
import 'package:axon_pos/features/finance/presentation/widgets/pay_suppliers_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FinancePayable _bill(
        String id, String supplierId, String supplier, double balance) =>
    FinancePayable(
      id: id,
      supplierId: supplierId,
      supplierName: supplier,
      supplierPhone: null,
      invoiceNumber: id.toUpperCase(),
      totalAmount: balance,
      paidAmount: 0,
      outstandingAmount: balance,
      dueDate: DateTime(2026, 11, 12),
      status: 'open',
      createdAt: DateTime(2026, 11, 1),
    );

void main() {
  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
  }

  final bills = [
    _bill('inv-m1', 's-m', 'Mwalimu Wholesalers', 12000),
    _bill('inv-m2', 's-m', 'Mwalimu Wholesalers', 3000),
    _bill('inv-k1', 's-k', 'Kamau Distributors', 8000),
    _bill('inv-paid', 's-k', 'Kamau Distributors', 0),
  ];

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> showSheet(WidgetTester tester,
      Future<void> Function(SupplierBatch batch) onPay) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PaySuppliersSheet(payables: bills, onPay: onPay)),
    ));
    await tester.pump();
  }

  testWidgets('pays bills from two suppliers in one go', (tester) async {
    phoneSize(tester);
    SupplierBatch? sent;
    await showSheet(tester, (batch) async => sent = batch);

    expect(find.text('Mwalimu Wholesalers'), findsOneWidget);
    expect(find.text('Kamau Distributors'), findsOneWidget);
    expect(find.text('INV-PAID'), findsNothing);
    expect(find.text('Tick the bills to pay'), findsOneWidget);

    // Kamau sorts first, so Mwalimu's Tick all is the second one.
    await tapVisible(tester, find.text('Tick all').last);
    await tapVisible(tester, find.text('INV-K1'));
    await tester.enterText(
        find.byKey(const ValueKey('pay-amount-inv-m2')), '1,000');
    await tester.pump();

    expect(find.text('3 bills from 2 suppliers'), findsOneWidget);
    expect(find.text('Pay KES 21,000'), findsOneWidget);

    await tapVisible(tester, find.text('Bank or M-Pesa'));
    await tester.enterText(
        find.byKey(const ValueKey('pay-suppliers-note')), 'QK12AB34CD');
    await tapVisible(tester, find.text('Pay KES 21,000'));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!.fundingSource, 'BANK_OR_MPESA');
    expect(sent!.notes, 'QK12AB34CD');
    expect(sent!.payments, [
      (invoiceId: 'inv-k1', amount: 8000.0),
      (invoiceId: 'inv-m1', amount: 12000.0),
      (invoiceId: 'inv-m2', amount: 1000.0),
    ]);
  });

  testWidgets('refuses more than the balance and keeps the sheet on failure',
      (tester) async {
    phoneSize(tester);
    var calls = 0;
    await showSheet(tester, (batch) async {
      calls++;
      throw StateError('Invoice balance changed. Refresh and try again.');
    });

    await tapVisible(tester, find.text('INV-K1'));
    await tester.enterText(
        find.byKey(const ValueKey('pay-amount-inv-k1')), '9000');
    await tester.pump();
    await tapVisible(tester, find.text('Pay KES 9,000'));

    expect(find.textContaining('no more than KES 8,000.00'), findsOneWidget);
    expect(calls, 0);

    await tester.enterText(
        find.byKey(const ValueKey('pay-amount-inv-k1')), '8000');
    await tester.pump();
    await tapVisible(tester, find.text('Pay KES 8,000'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.textContaining('Nothing was paid.'), findsOneWidget);
  });
}
