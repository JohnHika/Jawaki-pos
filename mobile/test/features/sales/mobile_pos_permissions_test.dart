import 'dart:async';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/database/app_database.dart' hide CartItem;
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/connectivity_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/catalog_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/payment_provider.dart';
import 'package:axon_pos/features/sales/presentation/screens/cart_screen.dart';
import 'package:axon_pos/features/sales/presentation/screens/payment_screen.dart';
import 'package:axon_pos/features/sales/presentation/screens/pos_screen.dart';
import 'package:axon_pos/features/sales/presentation/widgets/price_adjustment_widget.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _row = <String, dynamic>{
  'id': 'customer-1',
  'name': 'Private Customer',
  'phone': '0712345678',
  'balance': 450.0,
  'totalPurchases': 12,
  'totalSpent': 12345.0,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'mobile cart hides the manual discount action without sales.discount',
      (tester) async {
    final harness =
        await _pumpCart(tester, permissions: const ['sales.create']);
    addTearDown(harness.dispose);

    expect(find.text('Discount'), findsNothing);
    expect(find.text('Apply discount'), findsNothing);
  });

  testWidgets('manual line adjustment is rejected without sales.discount',
      (tester) async {
    final scope = _openGetItScope();
    final cart = _newCart();
    await cart.addItem(
      productId: 'item-1',
      productName: 'Bread',
      sku: 'BREAD-1',
      unitPrice: 100,
      quantity: 1,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        cartProvider.overrideWith((ref) => cart),
        permissionsProvider.overrideWithValue(
          RolePermissions(const ['sales.create']),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const PriceAdjustmentWidget(
                  productId: 'item-1',
                  originalPrice: 100,
                  currentPrice: 100,
                  quantityLabel: '1 unit',
                ),
              ),
              child: const Text('Open adjustment'),
            ),
          ),
        ),
      ),
    ));
    addTearDown(scope);

    await tester.tap(find.text('Open adjustment'));
    await tester.pumpAndSettle();

    expect(cart.state.items.single.discount, 0);
    expect(find.text('Discount access required'), findsOneWidget);
    expect(
      find.text('You do not have permission to adjust item prices.'),
      findsOneWidget,
    );
  });

  testWidgets('sales.discount still permits manual line adjustment',
      (tester) async {
    final scope = _openGetItScope();
    final cart = _newCart();
    await cart.addItem(
      productId: 'item-1',
      productName: 'Bread',
      sku: 'BREAD-1',
      unitPrice: 100,
      quantity: 1,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        cartProvider.overrideWith((ref) => cart),
        permissionsProvider.overrideWithValue(
          RolePermissions(const ['sales.create', 'sales.discount']),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const PriceAdjustmentWidget(
                  productId: 'item-1',
                  originalPrice: 100,
                  currentPrice: 100,
                  quantityLabel: '1 unit',
                ),
              ),
              child: const Text('Open adjustment'),
            ),
          ),
        ),
      ),
    ));
    addTearDown(scope);

    await tester.tap(find.text('Open adjustment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '80');
    await tester.tap(find.text('Save Adjustment'));
    await tester.pumpAndSettle();

    expect(cart.state.items.single.discount, 20);
    expect(find.text('Price Adjustment'), findsNothing);
  });

  testWidgets('mobile cart exposes manual discounts with sales.discount',
      (tester) async {
    final harness = await _pumpCart(
      tester,
      permissions: const ['sales.create', 'sales.discount'],
    );
    addTearDown(harness.dispose);

    expect(find.text('Discount'), findsOneWidget);
  });

  testWidgets(
      'mobile cart does not display a saved customer without customers.view',
      (tester) async {
    final harness = await _pumpCart(
      tester,
      permissions: const ['sales.create'],
      selectedCustomer: true,
    );
    addTearDown(harness.dispose);

    expect(find.text('Private Customer'), findsNothing);
    expect(find.text('Selected customer'), findsOneWidget);
  });

  test(
      'cart clears only its customer display name when customers.view is revoked',
      () async {
    final auth = _TestAuth();
    final authController = AuthController(auth);
    final permissions = _MutableSalesPermissions(
      RolePermissions(const ['sales.create', 'customers.view']),
    );
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith((ref) => authController),
      permissionsProvider.overrideWith(
        (ref) => ref.watch(_mutableSalesPermissionsProvider),
      ),
      _mutableSalesPermissionsProvider.overrideWith((ref) => permissions),
    ]);
    addTearDown(() async {
      container.dispose();
      await auth.close();
    });

    final cart = container.read(cartProvider.notifier);
    cart.setCustomer('customer-1', customerName: 'Private Customer');
    permissions.state = RolePermissions(const ['sales.create']);

    expect(container.read(cartProvider).customerId, 'customer-1');
    expect(container.read(cartProvider).customerName, isNull);
  });

  testWidgets(
      'mobile POS picker hides saved customer details without customers.view',
      (tester) async {
    final harness = await _pumpPos(
      tester,
      permissions: const ['sales.create', 'customers.create'],
      selectedCustomer: true,
    );
    addTearDown(() => harness.dispose(tester));

    harness.container.read(customerPickerRequestProvider.notifier).state = true;
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('pos-customer-name')), 'Priv');
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    expect(harness.database.searchCalls, 0);
    expect(harness.database.customerLookups, 0);
    expect(find.text('Private Customer'), findsNothing);
    expect(find.text('0712345678'), findsNothing);
    expect(find.text('12 purchases'), findsNothing);
    expect(find.text('Create & select'), findsOneWidget);
    expect(find.text('Walk-in'), findsOneWidget);
  });

  testWidgets('mobile POS still reads saved customers with customers.view',
      (tester) async {
    final harness = await _pumpPos(
      tester,
      permissions: const ['sales.create', 'customers.view'],
    );
    addTearDown(() => harness.dispose(tester));

    harness.container.read(customerPickerRequestProvider.notifier).state = true;
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('pos-customer-name')), 'Priv');
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    expect(harness.database.searchCalls, 1);
    expect(find.text('Private Customer'), findsOneWidget);
    expect(find.text('12 purchases'), findsOneWidget);
    expect(find.text('Create & select'), findsNothing);
  });

  testWidgets(
    'mobile POS clears a customer search and drops its result when customers.view is revoked',
    (tester) async {
      final harness = await _pumpPos(
        tester,
        permissions: const [
          'sales.create',
          'customers.view',
          'customers.create',
        ],
      );
      addTearDown(() => harness.dispose(tester));
      final pendingSearch = Completer<List<Map<String, dynamic>>>();
      harness.database.searchCompleter = pendingSearch;

      harness.container.read(customerPickerRequestProvider.notifier).state =
          true;
      await tester.pumpAndSettle();
      final searchField = find.byKey(const ValueKey('pos-customer-name'));
      await tester.enterText(searchField, 'Private');
      await tester.pump(const Duration(milliseconds: 260));
      expect(harness.database.searchCalls, 1);

      harness.permissions.state =
          RolePermissions(const ['sales.create', 'customers.create']);
      await tester.pump();

      expect(tester.widget<TextField>(searchField).controller!.text, isEmpty);
      expect(find.text('Private Customer'), findsNothing);

      pendingSearch.complete([_row]);
      await tester.pumpAndSettle();

      expect(find.text('Private Customer'), findsNothing);
      expect(find.text('0712345678'), findsNothing);
      expect(find.text('12 purchases'), findsNothing);
      expect(harness.cart.state.customerId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
      'mobile payment customer picker hides saved PII without customers.view',
      (tester) async {
    final harness = await _pumpPayment(
      tester,
      permissions: const ['sales.create', 'customers.create'],
    );
    addTearDown(harness.dispose);

    await tester.tap(find.text('Customer credit'));
    await tester.pumpAndSettle();

    expect(harness.database.searchCalls, 0);
    expect(find.text('Private Customer'), findsNothing);
    expect(find.text('0712345678'), findsNothing);
    expect(find.text('Owes KES 450'), findsNothing);
    expect(find.text('Add customer'), findsOneWidget);
  });

  testWidgets(
      'mobile payment picker preserves existing-customer access with customers.view',
      (tester) async {
    final harness = await _pumpPayment(
      tester,
      permissions: const ['sales.create', 'customers.view'],
    );
    addTearDown(harness.dispose);

    await tester.tap(find.text('Customer credit'));
    await tester.pumpAndSettle();

    expect(harness.database.searchCalls, 1);
    expect(find.text('Private Customer'), findsOneWidget);
    expect(find.textContaining('0712345678'), findsOneWidget);
    expect(find.textContaining('Owes KES 450'), findsOneWidget);
    expect(find.text('Add customer'), findsNothing);
  });

  testWidgets(
    'payment picker clears and drops in-flight customer results when customers.view is revoked',
    (tester) async {
      final harness = await _pumpPayment(
        tester,
        permissions: const ['sales.create', 'customers.view'],
      );
      addTearDown(harness.dispose);
      final pendingSearch = Completer<List<Map<String, dynamic>>>();
      harness.database.searchCompleter = pendingSearch;

      await tester.tap(find.text('Customer credit'));
      await tester.pump();
      expect(harness.database.searchCalls, 1);

      harness.permissions.state =
          RolePermissions(const ['sales.create', 'customers.create']);
      await tester.pump();

      expect(find.text('Private Customer'), findsNothing);
      expect(find.text('0712345678'), findsNothing);
      expect(find.textContaining('Owes KES 450'), findsNothing);

      pendingSearch.complete([_row]);
      await tester.pumpAndSettle();

      expect(find.text('Private Customer'), findsNothing);
      expect(find.text('0712345678'), findsNothing);
      expect(find.textContaining('Owes KES 450'), findsNothing);
      expect(harness.cart.state.customerId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
      'mobile checkout blocks an inherited manual discount without sales.discount',
      (tester) async {
    final harness = await _pumpPayment(
      tester,
      permissions: const ['sales.create'],
      manualDiscount: true,
    );
    addTearDown(harness.dispose);

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm cash payment'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(harness.payments.cashCalls, 0);
    expect(harness.cart.state.items, hasLength(1));
    expect(
      find.text('You do not have permission to apply discounts.'),
      findsOneWidget,
    );
    expect(find.text('Cash received'), findsNothing);
  });

  testWidgets(
      'mobile checkout also blocks manually discounted lines without sales.discount',
      (tester) async {
    final harness = await _pumpPayment(
      tester,
      permissions: const ['sales.create'],
      manualLineDiscount: true,
    );
    addTearDown(harness.dispose);

    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm cash payment'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(harness.payments.cashCalls, 0);
    expect(harness.cart.state.items.single.discount, 10);
    expect(
      find.text('You do not have permission to apply discounts.'),
      findsOneWidget,
    );
    expect(find.text('Cash received'), findsNothing);
  });
}

Future<_CartHarness> _pumpCart(
  WidgetTester tester, {
  required List<dynamic> permissions,
  bool selectedCustomer = false,
}) async {
  final scope = _openGetItScope();
  final cart = _newCart();
  if (selectedCustomer) {
    cart.setCustomer('customer-1', customerName: 'Private Customer');
  }
  await cart.addItem(
    productId: 'item-1',
    productName: 'Bread',
    sku: 'BREAD-1',
    unitPrice: 100,
    quantity: 1,
  );
  final storage = _TestStorage();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      cartProvider.overrideWith((ref) => cart),
      permissionsProvider.overrideWithValue(RolePermissions(permissions)),
      businessLayoutProvider.overrideWithValue(businessLayoutFromUser(null)),
      parkedSalesProvider.overrideWith((ref) => ParkedSalesNotifier(
            storage: storage,
            tenantId: null,
            branchId: null,
            isLocalWorkspace: true,
          )),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: const CartScreen()),
  ));
  await tester.pumpAndSettle();
  return _CartHarness(cart: cart, closeScope: scope);
}

Future<_PosHarness> _pumpPos(
  WidgetTester tester, {
  required List<dynamic> permissions,
  bool selectedCustomer = false,
}) async {
  final scope = _openGetItScope();
  final database = _TestDatabase();
  final storage = _TestStorage();
  final connectivity = _TestConnectivity();
  getIt.registerSingleton<AppDatabase>(database);
  getIt.registerSingleton<StorageService>(storage);
  getIt.registerSingleton<ConnectivityService>(connectivity);
  final cart = _newCart();
  if (selectedCustomer) {
    cart.setCustomer('customer-1', customerName: 'Private Customer');
  }
  final containerKey = GlobalKey<NavigatorState>();
  final permissionState =
      _MutableSalesPermissions(RolePermissions(permissions));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      cartProvider.overrideWith((ref) => cart),
      paymentProvider.overrideWith((ref) => _TestPayments()),
      permissionsProvider.overrideWith(
        (ref) => ref.watch(_mutableSalesPermissionsProvider),
      ),
      _mutableSalesPermissionsProvider.overrideWith((ref) => permissionState),
      businessLayoutProvider.overrideWithValue(businessLayoutFromUser(null)),
      notificationInboxProvider.overrideWith((ref) => _TestInbox()),
      filteredProductsProvider.overrideWith(
        (ref, params) => Stream.value(const <Map<String, dynamic>>[]),
      ),
      categoriesProvider.overrideWith((ref) async => const []),
      favoriteProductsProvider.overrideWith((ref) async => const []),
      favoritesProvider
          .overrideWith((ref) => FavoritesNotifier.emptyForTesting()),
      parkedSalesProvider.overrideWith((ref) => ParkedSalesNotifier(
            storage: storage,
            tenantId: null,
            branchId: null,
            isLocalWorkspace: true,
          )),
    ],
    child: MaterialApp(
      navigatorKey: containerKey,
      theme: AppTheme.lightTheme,
      home: const POSScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(POSScreen)),
  );
  return _PosHarness(
    database: database,
    cart: cart,
    container: container,
    closeScope: scope,
    closeConnectivity: connectivity.close,
    permissions: permissionState,
  );
}

Future<_PaymentHarness> _pumpPayment(
  WidgetTester tester, {
  required List<dynamic> permissions,
  bool manualDiscount = false,
  bool manualLineDiscount = false,
}) async {
  final scope = _openGetItScope();
  final database = _TestDatabase();
  final storage = _TestStorage();
  getIt.registerSingleton<AppDatabase>(database);
  getIt.registerSingleton<StorageService>(storage);
  final cart = _newCart();
  await cart.addItem(
    productId: 'item-1',
    productName: 'Bread',
    sku: 'BREAD-1',
    unitPrice: 100,
    quantity: 1,
  );
  if (manualDiscount) cart.setDiscountPercent(10);
  if (manualLineDiscount) cart.updateItemDiscount('item-1', 10);
  final payments = _TestPayments();
  final permissionState =
      _MutableSalesPermissions(RolePermissions(permissions));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      cartProvider.overrideWith((ref) => cart),
      paymentProvider.overrideWith((ref) => payments),
      permissionsProvider.overrideWith(
        (ref) => ref.watch(_mutableSalesPermissionsProvider),
      ),
      _mutableSalesPermissionsProvider.overrideWith((ref) => permissionState),
      businessLayoutProvider.overrideWithValue(businessLayoutFromUser(null)),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const PaymentScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return _PaymentHarness(
    database: database,
    cart: cart,
    payments: payments,
    closeScope: scope,
    permissions: permissionState,
  );
}

CartNotifier _newCart() => CartNotifier(
      stockValidator: (_, quantity) async => {
        'available': true,
        'message': 'ok',
        'currentStock': quantity,
      },
    );

Future<void> Function() _openGetItScope() {
  getIt.pushNewScope();
  final auth = _TestAuth();
  getIt.registerSingleton<AuthService>(auth);
  return () async {
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt<AppDatabase>().close();
    }
    await getIt.popScope();
    await auth.close();
  };
}

class _CartHarness {
  const _CartHarness({required this.cart, required this.closeScope});
  final CartNotifier cart;
  final Future<void> Function() closeScope;
  Future<void> dispose() => closeScope();
}

final _mutableSalesPermissionsProvider =
    StateNotifierProvider<_MutableSalesPermissions, RolePermissions>(
  (ref) => _MutableSalesPermissions(RolePermissions(const [])),
);

class _MutableSalesPermissions extends StateNotifier<RolePermissions> {
  _MutableSalesPermissions(super.state);
}

class _PosHarness {
  const _PosHarness({
    required this.database,
    required this.cart,
    required this.container,
    required this.closeScope,
    required this.closeConnectivity,
    required this.permissions,
  });
  final _TestDatabase database;
  final CartNotifier cart;
  final ProviderContainer container;
  final Future<void> Function() closeScope;
  final Future<void> Function() closeConnectivity;
  final _MutableSalesPermissions permissions;
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeConnectivity();
    await closeScope();
  }
}

class _PaymentHarness {
  const _PaymentHarness({
    required this.database,
    required this.cart,
    required this.payments,
    required this.closeScope,
    required this.permissions,
  });
  final _TestDatabase database;
  final CartNotifier cart;
  final _TestPayments payments;
  final Future<void> Function() closeScope;
  final _MutableSalesPermissions permissions;
  Future<void> dispose() => closeScope();
}

class _TestDatabase extends AppDatabase {
  _TestDatabase() : super.forTesting(NativeDatabase.memory(), _TestStorage());

  var searchCalls = 0;
  var customerLookups = 0;
  Completer<List<Map<String, dynamic>>>? searchCompleter;

  @override
  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    searchCalls++;
    final pending = searchCompleter;
    if (pending != null) return await pending.future;
    return [_row];
  }

  @override
  Future<Map<String, dynamic>?> getCustomer(String id) async {
    customerLookups++;
    return _row;
  }
}

class _TestAuth implements AuthService {
  final _status = StreamController<AuthStatus>.broadcast();

  @override
  bool get isAuthenticated => true;
  @override
  bool get isLocked => false;
  @override
  bool get isLocalWorkspace => true;
  @override
  double get taxRatePercent => 0;
  @override
  bool get showTaxOnReceipt => false;
  @override
  Map<String, dynamic>? get currentUser => const {
        'authMode': 'local',
        'tenantId': 'tenant-1',
        'branchId': 'branch-1',
        'permissions': ['sales.create'],
      };
  @override
  Stream<AuthStatus> get authStatusStream => _status.stream;
  Future<void> close() => _status.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestStorage implements StorageService {
  @override
  Future<String?> getSecureHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
  }) async =>
      null;
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
  }) async {}
  @override
  Future<void> saveHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
    required String snapshot,
  }) async {}
  @override
  Future<void> clearLegacyHeldSalesSnapshot({
    required String tenantId,
    required String branchId,
  }) async {}
  @override
  String? getRecordedPaymentRulesJson() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestConnectivity implements ConnectivityService {
  final _status = StreamController<ConnectionStatus>.broadcast();
  @override
  ConnectionStatus get currentStatus => ConnectionStatus.online;
  @override
  Stream<ConnectionStatus> get statusStream => _status.stream;
  Future<void> close() => _status.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPayments extends StateNotifier<PaymentState>
    implements PaymentNotifier {
  _TestPayments() : super(const PaymentState());
  var cashCalls = 0;
  @override
  bool get hasUnresolvedMerchantPayment => state.hasUnresolvedMerchantPayment;
  @override
  Future<String?> processCashPayment({
    required double amount,
    required double tenderedAmount,
    required List<CartItem> items,
    String? customerId,
    double discountAmount = 0,
    String? couponCode,
  }) async {
    cashCalls++;
    return 'sale-1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxController {
  _TestInbox() : super(const NotificationInboxState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
