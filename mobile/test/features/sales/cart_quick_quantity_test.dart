import 'package:axon_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stock check that allows up to [stock] of anything, after a short async
/// gap like the real database lookup.
Future<Map<String, dynamic>> Function(String, int) _stock(int stock) {
  return (productId, quantity) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final ok = quantity <= stock;
    return {
      'available': ok,
      'message': ok ? 'ok' : 'Insufficient stock available',
      'currentStock': stock,
    };
  };
}

Future<void> _add(CartNotifier cart, {int quantity = 1, double? conversion}) {
  return cart.addItem(
    productId: 'p1',
    productName: 'Maize flour',
    sku: 'SKU-1',
    unitPrice: 100,
    quantity: quantity,
    saleUnit: 'piece',
    saleQuantity: quantity.toDouble(),
    unitConversionFactor: conversion ?? 1,
  );
}

void main() {
  group('addItem', () {
    test('two taps in quick succession make one line of 2, not two lines',
        () async {
      final cart = CartNotifier(stockValidator: _stock(50));
      // Both start before either has finished its (asynchronous) stock check.
      await Future.wait([_add(cart), _add(cart)]);

      expect(cart.state.items, hasLength(1));
      expect(cart.state.items.single.quantity, 2);
    });

    test('five rapid taps add up to five', () async {
      final cart = CartNotifier(stockValidator: _stock(50));
      await Future.wait([for (var i = 0; i < 5; i++) _add(cart)]);

      expect(cart.state.items, hasLength(1));
      expect(cart.state.items.single.quantity, 5);
    });

    test('re-adding a box preserves its existing tier price and unit',
        () async {
      final cart = CartNotifier(stockValidator: _stock(500));
      await cart.addItem(
        productId: 'p1',
        productName: 'Maize flour',
        sku: 'SKU-1',
        unitPrice: 90,
        quantity: 24,
        saleUnit: 'box',
        saleQuantity: 2,
        unitConversionFactor: 12,
      );

      final result = await cart.addItem(
        productId: 'p1',
        productName: 'Maize flour',
        sku: 'SKU-1',
        unitPrice: 100,
        quantity: 12,
        saleUnit: 'box',
        saleQuantity: 1,
        unitConversionFactor: 12,
      );

      expect(result.success, isTrue);
      expect(cart.state.items, hasLength(1));
      expect(cart.state.items.single.quantity, 36);
      expect(cart.state.items.single.unitPrice, 90,
          reason: 'an add action must not reprice the existing box line');
      expect(cart.state.items.single.saleUnit, 'box');
      expect(cart.state.items.single.saleQuantity, 3);
      expect(cart.state.items.single.unitConversionFactor, 12);
    });

    test('a different sale tier cannot silently overwrite the cart line',
        () async {
      final cart = CartNotifier(stockValidator: _stock(500));
      await cart.addItem(
        productId: 'p1',
        productName: 'Maize flour',
        sku: 'SKU-1',
        unitPrice: 90,
        quantity: 24,
        saleUnit: 'box',
        saleQuantity: 2,
        unitConversionFactor: 12,
      );

      final result = await cart.addItem(
        productId: 'p1',
        productName: 'Maize flour',
        sku: 'SKU-1',
        unitPrice: 100,
        quantity: 1,
        saleUnit: 'piece',
        saleQuantity: 1,
        unitConversionFactor: 1,
      );

      expect(result.success, isFalse);
      expect(cart.state.items, hasLength(1));
      expect(cart.state.items.single.quantity, 24);
      expect(cart.state.items.single.unitPrice, 90);
      expect(cart.state.items.single.saleUnit, 'box');
      expect(cart.state.items.single.saleQuantity, 2);
    });
  });

  group('changeQuantityBy', () {
    test('rapid + taps accumulate instead of overwriting each other', () async {
      final cart = CartNotifier(stockValidator: _stock(50));
      await _add(cart);
      await Future.wait([
        cart.changeQuantityBy('p1', 1),
        cart.changeQuantityBy('p1', 1),
        cart.changeQuantityBy('p1', 1),
      ]);
      expect(cart.state.items.single.quantity, 4);
    });

    test('keeps the line price and rescales the units sold for a box line',
        () async {
      final cart = CartNotifier(stockValidator: _stock(500));
      // 2 boxes of 12, sold at 90 a piece (a discount against the 100 base price).
      await cart.addItem(
        productId: 'p1',
        productName: 'Maize flour',
        sku: 'SKU-1',
        unitPrice: 90,
        quantity: 24,
        saleUnit: 'box',
        saleQuantity: 2,
        unitConversionFactor: 12,
      );

      await cart.changeQuantityBy('p1', 12); // one more box
      final line = cart.state.items.single;
      expect(line.quantity, 36);
      expect(line.saleQuantity, 3);
      expect(line.unitPrice, 90);

      await cart.changeQuantityBy('p1', -12);
      expect(cart.state.items.single.saleQuantity, 2);
    });

    test('normalizes a legacy fractional pack before stepping', () async {
      final cart = CartNotifier(stockValidator: _stock(500));
      await cart.addItem(
        productId: 'p1',
        productName: 'Maize flour',
        sku: 'SKU-1',
        unitPrice: 90,
        quantity: 13,
        saleUnit: 'box',
        saleQuantity: 1.08,
        unitConversionFactor: 12,
      );

      await cart.changeQuantityBy('p1', 12);
      final line = cart.state.items.single;
      expect(line.quantity, 24);
      expect(line.saleQuantity, 2);
      expect(line.quantity % 12, 0);
    });

    test('going to zero removes the line', () async {
      final cart = CartNotifier(stockValidator: _stock(50));
      await _add(cart);
      final result = await cart.changeQuantityBy('p1', -1);
      expect(result.success, isTrue);
      expect(cart.state.items, isEmpty);
    });

    test('refuses to go past the stock and leaves the cart as it was',
        () async {
      final cart = CartNotifier(stockValidator: _stock(2));
      await _add(cart, quantity: 2);
      final result = await cart.changeQuantityBy('p1', 1);

      expect(result.success, isFalse);
      expect(result.currentStock, 2);
      expect(cart.state.items.single.quantity, 2);
    });

    test('is a polite no-op for something that is not in the cart', () async {
      final cart = CartNotifier(stockValidator: _stock(50));
      final result = await cart.changeQuantityBy('missing', 1);
      expect(result.success, isFalse);
      expect(cart.state.items, isEmpty);
    });

    test('a - tap that lands after the line was removed does not bring it back',
        () async {
      final cart = CartNotifier(stockValidator: _stock(50));
      await _add(cart);
      final pending = cart.changeQuantityBy('p1', 1); // slow: waits on stock
      cart.removeItem('p1'); // cashier removes it meanwhile
      await pending;
      expect(cart.state.items, isEmpty);
    });
  });
}
