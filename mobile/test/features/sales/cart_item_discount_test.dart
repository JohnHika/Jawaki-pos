import 'package:axon_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>> _stock(String _, double quantity) async => {
      'available': true,
      'message': 'ok',
      'currentStock': quantity,
    };

Future<CartMutationResult> _add(CartNotifier cart,
    {int quantity = 2, double unitPrice = 125}) {
  return cart.addItem(
    productId: 'p1',
    productName: 'Test item',
    sku: 'SKU-1',
    unitPrice: unitPrice,
    quantity: quantity,
  );
}

void main() {
  group('updateItemDiscount', () {
    test('accepts a valid line discount in cents', () async {
      final cart = CartNotifier(stockValidator: _stock);
      await _add(cart);

      final result = cart.updateItemDiscount('p1', 50.25);

      expect(result.success, isTrue);
      expect(cart.state.items.single.discount, 50.25);
      expect(cart.state.items.single.total, 199.75);
    });

    test('preserves the adjusted rate when line quantity changes', () async {
      final cart = CartNotifier(stockValidator: _stock);
      await _add(cart);
      cart.updateItemDiscount('p1', 50);

      final result = await cart.updateQuantity('p1', 4);

      expect(result.success, isTrue);
      expect(cart.state.items.single.discount, 100);
      expect(cart.state.items.single.total, 400);
    });

    test('scales the adjustment when adding more to an adjusted line',
        () async {
      final cart = CartNotifier(stockValidator: _stock);
      await _add(cart);
      cart.updateItemDiscount('p1', 50);

      await _add(cart);

      expect(cart.state.items.single.quantity, 4);
      expect(cart.state.items.single.discount, 100);
      expect(cart.state.items.single.total, 400);
    });

    test('rejects discounts that increase the line total', () async {
      final cart = CartNotifier(stockValidator: _stock);
      await _add(cart);

      final result = cart.updateItemDiscount('p1', -0.01);

      expect(result.success, isFalse);
      expect(cart.state.items.single.discount, 0);
      expect(cart.state.items.single.total, 250);
    });

    test('rejects a discount greater than the line total', () async {
      final cart = CartNotifier(stockValidator: _stock);
      await _add(cart);

      final result = cart.updateItemDiscount('p1', 250.01);

      expect(result.success, isFalse);
      expect(cart.state.items.single.discount, 0);
    });

    test('rejects non-finite discounts', () async {
      final cart = CartNotifier(stockValidator: _stock);
      await _add(cart);

      final result = cart.updateItemDiscount('p1', double.nan);

      expect(result.success, isFalse);
      expect(cart.state.items.single.discount, 0);
    });

    test('returns a recoverable result when the line was removed', () {
      final cart = CartNotifier(stockValidator: _stock);

      final result = cart.updateItemDiscount('missing', 1);

      expect(result.success, isFalse);
      expect(result.message, contains('no longer in the cart'));
    });
  });
}
