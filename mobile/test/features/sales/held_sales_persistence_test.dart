import 'dart:async';
import 'dart:convert';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'scoped held sales survive restoration without leaking across shops or branches',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    final first = ParkedSalesNotifier(
      storage: storage,
      tenantId: 'shop-a',
      branchId: 'branch-1',
      isLocalWorkspace: false,
    );
    first.park(CartState(
      items: [
        CartItem(
          id: 'line-1',
          productId: 'product-1',
          productName: 'Tea',
          sku: 'TEA',
          quantity: 2,
          unitPrice: 15,
        )
      ],
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
      isLocalWorkspace: false,
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
      isLocalWorkspace: false,
    );
    final otherBranch = ParkedSalesNotifier(
      storage: storage,
      tenantId: 'shop-a',
      branchId: 'branch-2',
      isLocalWorkspace: false,
    );
    expect(otherShop.state, isEmpty);
    expect(otherBranch.state, isEmpty);

    final saleId = restored.state.single.id;
    final resumedCart = await restored.resume(saleId);
    expect(resumedCart?.items.single.quantity, 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
        ParkedSalesNotifier(
          storage: storage,
          tenantId: 'shop-a',
          branchId: 'branch-1',
          isLocalWorkspace: false,
        ).state,
        isEmpty);
  });

  test('held sale defaults to a generic label rather than its customer name',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    final heldSales = ParkedSalesNotifier(
      storage: storage,
      tenantId: 'shop-a',
      branchId: 'branch-1',
      isLocalWorkspace: false,
    );

    await heldSales.park(CartState(
      items: [
        CartItem(
          id: 'line-1',
          productId: 'product-1',
          productName: 'Tea',
          sku: 'TEA',
          quantity: 1,
          unitPrice: 15,
        ),
      ],
      customerId: 'customer-1',
      customerName: 'Private Customer',
    ));

    expect(heldSales.state.single.label, 'Sale #1');
  });

  test('held snapshots omit customer names without customers.view', () async {
    SharedPreferences.setMockInitialValues({});
    getIt.pushNewScope();
    final storage = _HeldSnapshotStorage();
    getIt.registerSingleton<StorageService>(storage);
    final auth = _HeldAuth();
    final authController = AuthController(auth);
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith((ref) => authController),
      permissionsProvider.overrideWithValue(
        RolePermissions(const ['sales.create']),
      ),
    ]);
    addTearDown(() async {
      container.dispose();
      await auth.close();
      await getIt.popScope();
    });

    final held = container.read(parkedSalesProvider.notifier);
    await held.park(
      CartState(
        items: [
          CartItem(
            id: 'line-1',
            productId: 'product-1',
            productName: 'Tea',
            sku: 'TEA',
            quantity: 1,
            unitPrice: 15,
          ),
        ],
        customerId: 'customer-1',
        customerName: 'Private Customer',
      ),
      label: 'Private Customer',
    );

    final saved = jsonDecode(storage.secureSnapshot!) as Map<String, dynamic>;
    final savedSale = (saved['sales'] as List).single as Map<String, dynamic>;
    final savedCart = savedSale['cart'] as Map<String, dynamic>;
    expect(savedSale['label'], isNot('Private Customer'));
    expect(savedCart['customerName'], isNull);
    expect(savedCart['customerId'], 'customer-1');

    final resumed = await held.resume(held.state.single.id);
    expect(resumed?.customerId, 'customer-1');
    expect(resumed?.customerName, isNull);
  });

  test('permission revocation clears held-sale identity and rewrites snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    getIt.pushNewScope();
    final storage = _HeldSnapshotStorage();
    getIt.registerSingleton<StorageService>(storage);
    final auth = _HeldAuth();
    final authController = AuthController(auth);
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith((ref) => authController),
      permissionsProvider.overrideWith(
        (ref) => ref.watch(_mutableHeldPermissionsProvider),
      ),
      _mutableHeldPermissionsProvider.overrideWith(
        (ref) => RolePermissions(['sales.create', 'customers.view']),
      ),
    ]);
    addTearDown(() async {
      container.dispose();
      await auth.close();
      await getIt.popScope();
    });

    final held = container.read(parkedSalesProvider.notifier);
    await held.park(
      CartState(
        items: [
          CartItem(
            id: 'line-1',
            productId: 'product-1',
            productName: 'Tea',
            sku: 'TEA',
            quantity: 1,
            unitPrice: 15,
          ),
        ],
        customerId: 'customer-1',
        customerName: 'Private Customer',
      ),
      label: 'Private Customer',
    );
    expect(held.state.single.cart.customerName, 'Private Customer');

    final permissions =
        container.read(_mutableHeldPermissionsProvider.notifier);
    permissions.state = RolePermissions(['sales.create']);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(held.state.single.cart.customerName, isNull);
    expect(held.state.single.label, isNot('Private Customer'));
    final saved = jsonDecode(storage.secureSnapshot!) as Map<String, dynamic>;
    final sale = (saved['sales'] as List).single as Map<String, dynamic>;
    final cart = sale['cart'] as Map<String, dynamic>;
    expect(sale['label'], isNot('Private Customer'));
    expect(cart['customerName'], isNull);
    expect(cart['customerId'], 'customer-1');
  });
}

final _mutableHeldPermissionsProvider = StateProvider<RolePermissions>(
  (ref) => RolePermissions([]),
);

class _HeldSnapshotStorage extends StorageService {
  String? secureSnapshot;

  @override
  Future<String?> getSecureHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
  }) async =>
      secureSnapshot;

  @override
  String? getHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
  }) =>
      null;

  @override
  Future<void> saveSecureHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
    required String snapshot,
  }) async {
    secureSnapshot = snapshot;
  }

  @override
  Future<void> clearLegacyHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
  }) async {}
}

class _HeldAuth implements AuthService {
  final _status = StreamController<AuthStatus>.broadcast();

  @override
  bool get isAuthenticated => true;
  @override
  bool get isLocked => false;
  @override
  bool get isLocalWorkspace => true;
  @override
  Map<String, dynamic>? get currentUser => const {
        'authMode': 'local',
        'tenantId': 'tenant-1',
        'branchId': 'branch-1',
        'id': 'cashier-1',
        'permissions': ['sales.create'],
      };
  @override
  Stream<AuthStatus> get authStatusStream => _status.stream;
  Future<void> close() => _status.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
