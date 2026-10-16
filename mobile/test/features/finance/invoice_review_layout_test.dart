import 'package:axon_pos/core/services/supplier_receipt_ocr_service.dart';
import 'package:axon_pos/features/finance/presentation/screens/invoice_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SupplierReceiptScan _scan({int lines = 2}) => SupplierReceiptScan(
      imagePath: '',
      rawText: '',
      suggestedSupplierName: 'Kamau Wholesalers',
      invoiceNumber: 'INV-0042',
      totalAmount: 12400,
      summary: 'Test invoice',
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

Future<void> _pump(WidgetTester tester,
    {double textScale = 1, int lines = 2}) async {
  tester.view.physicalSize = const Size(720, 1280); // 360 x 640 dp
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearAllTestValues();
  });
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(home: InvoiceReviewScreen(scan: _scan(lines: lines))),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  testWidgets('opens with the supplier and invoice number filled in',
      (tester) async {
    await _pump(tester);

    expect(find.text('Kamau Wholesalers'), findsOneWidget);
    expect(find.text('INV-0042'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a manual invoice with no scanned lines still opens',
      (tester) async {
    await _pump(tester, lines: 0);
    expect(tester.takeException(), isNull);
  });
}
