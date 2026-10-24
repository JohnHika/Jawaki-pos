import 'package:axon_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:axon_pos/features/sales/presentation/widgets/cart_item_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cart +/- controls step by whole selected sale units',
      (tester) async {
    final cart = CartNotifier(
      stockValidator: (productId, quantity) async => {
        'available': quantity <= 120,
        'message': 'ok',
        'currentStock': 120,
      },
    );
    await cart.addItem(
      productId: 'p1',
      productName: 'Maize flour',
      sku: 'SKU-1',
      unitPrice: 90,
      quantity: 12,
      saleUnit: 'box',
      saleQuantity: 1,
      unitConversionFactor: 12,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [cartProvider.overrideWith((ref) => cart)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => CartItemTile(
                item: ref.watch(cartProvider).items.single,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Increase quantity'));
    await tester.pumpAndSettle();
    expect(cart.state.items.single.quantity, 24);
    expect(cart.state.items.single.saleQuantity, 2);
    expect(cart.state.items.single.quantity % 12, 0);

    await tester.tap(find.bySemanticsLabel('Decrease quantity'));
    await tester.pumpAndSettle();
    expect(cart.state.items.single.quantity, 12);
    expect(cart.state.items.single.saleQuantity, 1);
    expect(cart.state.items.single.quantity % 12, 0);
  });
}
