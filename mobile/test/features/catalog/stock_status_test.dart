import 'package:axon_pos/features/catalog/domain/starter_products.dart';
import 'package:axon_pos/features/catalog/domain/stock_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stockLevelFor', () {
    test('a product that is not counted never shows a number', () {
      expect(
        stockLevelFor(trackInventory: false, quantity: 5, minStock: 10),
        StockLevel.notTracked,
      );
    });

    test('zero is out, and so is anything below zero', () {
      expect(stockLevelFor(trackInventory: true, quantity: 0, minStock: 5),
          StockLevel.out);
      expect(stockLevelFor(trackInventory: true, quantity: -2, minStock: 0),
          StockLevel.out);
    });

    test('at or under the warning level is low, above it is in stock', () {
      expect(stockLevelFor(trackInventory: true, quantity: 10, minStock: 10),
          StockLevel.low);
      expect(stockLevelFor(trackInventory: true, quantity: 11, minStock: 10),
          StockLevel.inStock);
      expect(stockLevelFor(trackInventory: true, quantity: 1, minStock: 0),
          StockLevel.inStock);
    });

    test('a counted product with no stock record yet is unknown', () {
      expect(stockLevelFor(trackInventory: true, quantity: null, minStock: 3),
          StockLevel.unknown);
    });
  });

  test('the short words beside a price', () {
    expect(stockWords(StockLevel.inStock, 48), '48 in stock');
    expect(stockWords(StockLevel.low, 3), '3 left');
    expect(stockWords(StockLevel.out, 0), 'Out');
    expect(stockWords(StockLevel.notTracked, null), 'Not tracked');
    expect(stockNumber(2.5), '2.5');
    expect(stockNumber(2.0), '2');
  });

  group('summarizeStock', () {
    const lines = [
      StockLine(
          trackInventory: true, quantity: 48, minStock: 10, price: 195, costPrice: 160),
      StockLine(
          trackInventory: true, quantity: 3, minStock: 6, price: 310, costPrice: 255),
      StockLine(trackInventory: true, quantity: 0, minStock: 12, price: 60),
      StockLine(trackInventory: false, quantity: null, minStock: 0, price: 120),
    ];

    test('counts low and out and totals the worth at what was paid', () {
      final s = summarizeStock(lines);
      expect(s.products, 4);
      expect(s.low, 1);
      expect(s.out, 1);
      expect(s.needsReorder, 2);
      expect(s.worthAtCost, isTrue);
      expect(s.worth, 48 * 160 + 3 * 255);
    });

    test('with no buying price anywhere it falls back to selling prices', () {
      final s = summarizeStock(const [
        StockLine(trackInventory: true, quantity: 10, minStock: 2, price: 100),
      ]);
      expect(s.worthAtCost, isFalse);
      expect(s.worth, 1000);
    });
  });

  test('a movement reads in plain words with a sign', () {
    final sale = StockMovement(
        kind: StockMovementKind.sale, at: DateTime(2026, 11, 5), quantity: -2);
    final delivery = StockMovement(
        kind: StockMovementKind.delivery, at: DateTime(2026, 11, 5), quantity: 60);
    expect(sale.title, 'Sold 2');
    expect(sale.signed, '−2');
    expect(delivery.title, 'Received 60');
    expect(delivery.signed, '+60');
  });

  group('starterProductsFor', () {
    test('a general shop starts with everyday goods', () {
      expect(starterProductsFor('general_retail'),
          containsAll(['Unga', 'Sugar', 'Cooking oil']));
    });

    test('a pharmacy gets its own list', () {
      expect(starterProductsFor('pharmacy_retail'), contains('Paracetamol'));
    });

    test('an unknown or missing type falls back to the general list', () {
      expect(starterProductsFor(null), starterProductsFor('general_retail'));
      expect(starterProductsFor('nope'), starterProductsFor('general_retail'));
    });
  });
}
