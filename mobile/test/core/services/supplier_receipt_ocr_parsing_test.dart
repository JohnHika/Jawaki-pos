import 'package:axon_pos/core/services/supplier_receipt_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = SupplierReceiptOcrService();

  test('a size in the product name is not read as a quantity or price', () {
    final items = service.parseItems([
      'Omo 1kg      10 x 200   2000',
      'Cooking Oil 5L   4 x 800   3200',
    ]);

    expect(items, hasLength(2));
    expect(items[0].name, 'Omo 1kg');
    expect(items[0].quantity, 10);
    expect(items[0].unitCost, 200);
    expect(items[0].lineTotal, 2000);
    expect(items[1].name, 'Cooking Oil 5L');
    expect(items[1].quantity, 4);
    expect(items[1].unitCost, 800);
    expect(items[1].lineTotal, 3200);
  });

  test('decimal sizes and millilitres stay in the name', () {
    final items = service.parseItems([
      'Rice 1.5kg 6 x 350 2100',
      'Soda 500ml 24 x 40 960',
    ]);

    expect(items.map((i) => i.name), ['Rice 1.5kg', 'Soda 500ml']);
    expect(items[0].quantity, 6);
    expect(items[0].lineTotal, 2100);
    expect(items[1].quantity, 24);
    expect(items[1].unitCost, 40);
  });

  test('plain lines still parse as before', () {
    final items = service.parseItems(['Sugar 3 450 1350', 'Bread 65']);

    expect(items[0].name, 'Sugar');
    expect(items[0].quantity, 3);
    expect(items[0].lineTotal, 1350);
    expect(items[1].name, 'Bread');
    expect(items[1].lineTotal, 65);
  });
}
