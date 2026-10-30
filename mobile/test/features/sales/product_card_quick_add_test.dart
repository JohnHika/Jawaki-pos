import 'package:axon_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/catalog_provider.dart';
import 'package:axon_pos/features/sales/presentation/widgets/product_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _product(
  String id,
  String name, {
  int stock = 20,
  double price = 100,
  List<Map<String, dynamic>> pricingTiers = const [],
}) =>
    {
      'id': id,
      'name': name,
      'sku': 'SKU-$id',
      'price': price,
      'unit': 'piece',
      'stock': stock,
      'trackInventory': true,
      'pricingTiers': pricingTiers,
    };

Future<Map<String, dynamic>> _anyStock(
        String productId, double quantity) async =>
    {'available': true, 'message': 'ok', 'currentStock': 99};

late CartNotifier _cart;

Future<void> _pumpGrid(
  WidgetTester tester,
  List<Map<String, dynamic>> products,
) async {
  SharedPreferences.setMockInitialValues({});
  // Exercise the catalog at a common phone size instead of flutter_test's
  // wide 800x600 desktop viewport, which compresses card controls together.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  _cart = CartNotifier(stockValidator: _anyStock);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cartProvider.overrideWith((ref) => _cart),
        filteredProductsProvider
            .overrideWith((ref, params) => Stream.value(products)),
        favoritesProvider.overrideWith(
          (ref) => FavoritesNotifier.emptyForTesting(),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: ProductGrid())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'every in-stock product has a quick add, an out-of-stock one does not',
      (tester) async {
    await _pumpGrid(tester, [
      _product('1', 'Maize flour'),
      _product('2', 'Sugar 1kg'),
      _product('3', 'Peanuts', stock: 0),
    ]);

    expect(find.byKey(const ValueKey('quick-add')), findsNWidgets(2));
    expect(find.bySemanticsLabel('Add Maize flour to cart'), findsOneWidget);
    expect(find.bySemanticsLabel('Add Peanuts to cart'), findsNothing);
    expect(find.text('OUT OF STOCK'), findsOneWidget);
  });

  testWidgets('one tap adds one straight to the cart, no sheet',
      (tester) async {
    await _pumpGrid(tester, [_product('1', 'Maize flour')]);
    await tester.tap(find.byKey(const ValueKey('quick-add')));
    await tester.pumpAndSettle();

    expect(_cart.state.items, hasLength(1));
    expect(_cart.state.items.single.quantity, 1);
    expect(_cart.state.items.single.unitPrice, 100);
    // The "+" has become a stepper showing 1, and no sheet opened.
    expect(find.byKey(const ValueKey('quick-stepper')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-qty')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('quick-qty'))).data, '1');
    expect(find.text('Add to Cart'), findsNothing);
  });

  testWidgets('the stepper adds and removes, and returns to the + when empty',
      (tester) async {
    await _pumpGrid(tester, [_product('1', 'Maize flour')]);

    await tester.tap(find.byKey(const ValueKey('quick-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-more')));
    await tester.pumpAndSettle();
    expect(_cart.state.items.single.quantity, 3);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('quick-qty'))).data, '3');

    await tester.tap(find.byKey(const ValueKey('quick-less')));
    await tester.pumpAndSettle();
    expect(_cart.state.items.single.quantity, 2);

    await tester.tap(find.byKey(const ValueKey('quick-less')));
    await tester.tap(find.byKey(const ValueKey('quick-less')));
    await tester.pumpAndSettle();
    expect(_cart.state.items, isEmpty);
    expect(find.byKey(const ValueKey('quick-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-stepper')), findsNothing);
  });

  testWidgets('a line sold by the box steps one box at a time at the box price',
      (tester) async {
    await _pumpGrid(tester, [_product('1', 'Maize flour')]);
    await _cart.addItem(
      productId: '1',
      productName: 'Maize flour',
      sku: 'SKU-1',
      unitPrice: 90,
      quantity: 24,
      saleUnit: 'box',
      saleQuantity: 2,
      unitConversionFactor: 12,
    );
    await tester.pumpAndSettle();

    expect(
        tester.widget<Text>(find.byKey(const ValueKey('quick-qty'))).data, '2');
    await tester.tap(find.byKey(const ValueKey('quick-more')));
    await tester.pumpAndSettle();

    final line = _cart.state.items.single;
    expect(line.quantity, 36);
    expect(line.unitPrice, 90,
        reason: 'the box discount must survive a quick add');
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('quick-qty'))).data, '3');
  });

  testWidgets(
      'reopening a product keeps its selected tier, quantity, and price',
      (tester) async {
    await _pumpGrid(
      tester,
      [
        _product(
          '1',
          'Maize flour',
          stock: 100,
          pricingTiers: [
            {
              'unit': 'box',
              'quantityPerUnit': 12,
              'price': 1200,
              'sortOrder': 1,
            },
          ],
        ),
      ],
    );
    await _cart.addItem(
      productId: '1',
      productName: 'Maize flour',
      sku: 'SKU-1',
      unitPrice: 80,
      quantity: 24,
      saleUnit: 'box',
      saleQuantity: 2,
      unitConversionFactor: 12,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maize flour'));
    await tester.pumpAndSettle();
    expect(find.text('Update Cart'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        '2');
    await tester.enterText(find.byType(TextField).first, '3');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Update Cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update Cart'));
    await tester.pumpAndSettle();

    final line = _cart.state.items.single;
    expect(line.quantity, 36);
    expect(line.saleQuantity, 3);
    expect(line.saleUnit, 'box');
    expect(line.unitConversionFactor, 12);
    expect(line.unitPrice, 80,
        reason: 'the saved price override must survive reopening the sheet');
  });

  testWidgets('tapping the card itself still opens the full quantity sheet',
      (tester) async {
    await _pumpGrid(tester, [_product('1', 'Maize flour')]);

    await tester.tap(find.text('Maize flour'));
    await tester.pumpAndSettle();

    expect(find.text('Add to Cart'), findsOneWidget);
    expect(_cart.state.items, isEmpty,
        reason: 'opening the sheet adds nothing');
  });

  testWidgets('hitting the stock limit says so instead of adding',
      (tester) async {
    _cart = CartNotifier(
        stockValidator: (id, qty) async => {
              'available': qty <= 1,
              'stockBlocked': qty > 1,
              'message': 'Insufficient stock available',
              'currentStock': 1,
            });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartProvider.overrideWith((ref) => _cart),
          favoritesProvider.overrideWith(
            (ref) => FavoritesNotifier.emptyForTesting(),
          ),
          filteredProductsProvider.overrideWith(
            (ref, params) =>
                Stream.value([_product('1', 'Maize flour', stock: 1)]),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ProductGrid())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('quick-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-more')));
    await tester.pumpAndSettle();

    expect(_cart.state.items.single.quantity, 1);
    expect(find.textContaining('Only 1 unit'), findsOneWidget);
  });
  testWidgets('the stepper fits a narrow phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1600); // 360dp wide at 2x
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearAllTestValues();
    });

    await _pumpGrid(tester, [
      _product('1', 'Aberlife Water 500ml (bale of 24)'),
      _product('2', 'Sugar 1kg'),
    ]);
    await tester.tap(find.byKey(const ValueKey('quick-add')).first);
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byKey(const ValueKey('quick-more')));
      await tester.pumpAndSettle();
    }

    expect(tester.takeException(), isNull,
        reason: 'no overflow at 360dp / 1.3x');
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('quick-qty'))).data, '9');
  });
}
