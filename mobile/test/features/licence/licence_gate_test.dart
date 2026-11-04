import 'package:axon_pos/features/licence/data/licence_service.dart';
import 'package:axon_pos/features/licence/domain/licence_standing.dart';
import 'package:axon_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>> _anyStock(String productId, double quantity) async =>
    {'available': true, 'message': 'ok', 'currentStock': 99};

Future<CartMutationResult> _add(CartNotifier cart) => cart.addItem(
      productId: 'p1',
      productName: 'Sugar 1kg',
      sku: 'SU',
      unitPrice: 165,
    );

void main() {
  tearDown(() => LicenceGate.standing = null);

  test('with no licence rules switched on, selling is never blocked', () async {
    LicenceGate.standing = null;
    final result = await _add(CartNotifier(stockValidator: _anyStock));
    expect(result.success, isTrue);
    expect(LicenceGate.canSell, isTrue);
  });

  test('while paid up or in grace, items can be added', () async {
    for (final status in [LicenceStatus.active, LicenceStatus.grace]) {
      LicenceGate.standing = LicenceStanding(
        status: status,
        dueAt: DateTime(2026, 12, 1),
        daysLeft: 2,
      );
      final result = await _add(CartNotifier(stockValidator: _anyStock));
      expect(result.success, isTrue, reason: status.name);
    }
  });

  test('when sales are paused, no new item goes in the sale', () async {
    LicenceGate.standing = LicenceStanding(
      status: LicenceStatus.salesPaused,
      dueAt: DateTime(2026, 11, 1),
      daysLeft: 0,
    );
    final cart = CartNotifier(stockValidator: _anyStock);
    final result = await _add(cart);

    expect(result.success, isFalse);
    expect(result.message, LicenceGate.pausedMessage);
    expect(cart.state.items, isEmpty);
  });
}
