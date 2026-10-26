import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('held sales survive restart without leaking into another shop or branch', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    final first = ParkedSalesNotifier(
      storage: storage,
      tenantId: 'shop-a',
      branchId: 'branch-1',
    );
    first.park(CartState(
      items: [CartItem(
        id: 'line-1',
        productId: 'product-1',
        productName: 'Tea',
        sku: 'TEA',
        quantity: 2,
        unitPrice: 15,
      )],
      customerId: 'customer-1',
      customerName: 'Amina',
      discountAmount: 5,
      notes: 'collect later',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final restored = ParkedSalesNotifier(
      storage: storage,
      tenantId: 'shop-a',
      branchId: 'branch-1',
    );
    expect(restored.state, hasLength(1));
    expect(restored.state.single.cart.items.single.productName, 'Tea');
    expect(restored.state.single.cart.customerName, 'Amina');
    expect(restored.state.single.cart.discountAmount, 5);
    expect(restored.state.single.cart.notes, 'collect later');

    final otherShop = ParkedSalesNotifier(
      storage: storage,
      tenantId: 'shop-b',
      branchId: 'branch-1',
    );
    final otherBranch = ParkedSalesNotifier(
      storage: storage,
      tenantId: 'shop-a',
      branchId: 'branch-2',
    );
    expect(otherShop.state, isEmpty);
    expect(otherBranch.state, isEmpty);

    final saleId = restored.state.single.id;
    final resumedCart = await restored.resume(saleId);
    expect(resumedCart?.items.single.quantity, 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ParkedSalesNotifier(
      storage: storage,
      tenantId: 'shop-a',
      branchId: 'branch-1',
    ).state, isEmpty);
  });
}
