import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/features/catalog/presentation/widgets/stock_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product(String id, String name,
        {int minStock = 0, bool track = true, double price = 100, double? cost}) =>
    Product(
      id: id,
      sku: id.toUpperCase(),
      name: name,
      metadata: '{}',
      categoryId: 'food',
      price: price,
      costPrice: cost,
      unit: 'piece',
      isActive: true,
      trackInventory: track,
      allowFractions: false,
      minStock: minStock,
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
    );

Widget _pane(List<Product> products, Map<String, double> quantities) => MaterialApp(
      home: Scaffold(
        body: StockPane(
          products: products,
          quantities: quantities,
          canReceive: true,
        ),
      ),
    );

void main() {
  final products = [
    _product('unga', 'Unga Jogoo 2kg', minStock: 10, price: 195, cost: 160),
    _product('oil', 'Cooking oil 1L', minStock: 6, price: 310, cost: 255),
    _product('milk', 'Milk 500ml', minStock: 12, price: 60),
    _product('soap', 'Bar soap', track: false),
  ];
  const quantities = {'unga': 48.0, 'oil': 3.0, 'milk': 0.0};

  testWidgets('opens on what to buy, out first, then running low', (tester) async {
    await tester.pumpWidget(_pane(products, quantities));

    expect(find.text('OUT'), findsOneWidget);
    expect(find.text('RUNNING LOW'), findsOneWidget);
    expect(find.text('Milk 500ml'), findsOneWidget);
    expect(find.text('Cooking oil 1L'), findsOneWidget);
    // In stock and uncounted products are not on the reorder list.
    expect(find.text('Unga Jogoo 2kg'), findsNothing);
    expect(find.text('Bar soap'), findsNothing);
    expect(find.text('Receive'), findsNWidgets(2));
    expect(find.text('Needs reorder 2'), findsOneWidget);
  });

  testWidgets('the summary totals the worth at what was paid', (tester) async {
    await tester.pumpWidget(_pane(products, quantities));
    // 48 x 160 + 3 x 255 = 8,445
    expect(find.text('STOCK WORTH, AT WHAT YOU PAID'), findsOneWidget);
    expect(find.text('8,445'), findsOneWidget);
    expect(find.text('running low'), findsOneWidget);
  });

  testWidgets('All lists every product with its stock word', (tester) async {
    await tester.pumpWidget(_pane(products, quantities));
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.text('Unga Jogoo 2kg'), findsOneWidget);
    expect(find.text('Bar soap'), findsOneWidget);
    expect(find.text('48 in stock'), findsOneWidget);
    expect(find.text('3 left'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
    expect(find.text('Not tracked'), findsOneWidget);
  });

  testWidgets('with nothing short it opens on All, and Needs reorder says so',
      (tester) async {
    await tester.pumpWidget(_pane(
      [_product('unga', 'Unga Jogoo 2kg', minStock: 10)],
      const {'unga': 48.0},
    ));
    expect(find.text('48 in stock'), findsOneWidget);

    await tester.tap(find.text('Needs reorder'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to reorder'), findsOneWidget);
  });
}
