import 'dart:async';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/sales/presentation/providers/sales_provider.dart';
import 'package:axon_pos/features/sales/presentation/screens/receipts_list_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _saleId = 'sale-1';
const _customer = <String, dynamic>{
  'id': 'customer-1',
  'name': 'Private Customer',
  'phone': '0712345678',
  'email': 'private@example.test',
};

PendingSale _sale() => PendingSale(
      id: _saleId,
      receiptNumber: 'R-1001',
      subtotal: 100,
      discount: 0,
      tax: 0,
      total: 100,
      paymentMethod: 'CASH',
      customerId: 'customer-1',
      cashierId: 'cashier-1',
      branchId: 'branch-1',
      status: 'COMPLETED',
      createdAt: DateTime.now(),
      isSynced: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'receipts remain available without customers.view and do not query or render customer PII',
    (tester) async {
      getIt.pushNewScope();
      final database = _ReceiptDatabase(sale: _sale());
      getIt.registerSingleton<AppDatabase>(database);
      getIt.registerSingleton<AuthService>(
        _ReceiptAuth(local: true, permissions: const ['sales.view']),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await database.close();
        await getIt.popScope();
      });

      await tester.pumpWidget(ProviderScope(
        overrides: [
          permissionsProvider.overrideWithValue(
            RolePermissions(const ['sales.view']),
          ),
          businessLayoutProvider
              .overrideWithValue(businessLayoutFromUser(null)),
        ],
        child: const MaterialApp(home: ReceiptsListScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('R-1001'), findsOneWidget);
      expect(find.text('Private Customer'), findsNothing);
      expect(find.text('0712345678'), findsNothing);
      expect(database.allCustomerCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('receipts still show customer details with customers.view',
      (tester) async {
    getIt.pushNewScope();
    final database = _ReceiptDatabase(sale: _sale());
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<AuthService>(
      _ReceiptAuth(
        local: true,
        permissions: const ['sales.view', 'customers.view'],
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
      await getIt.popScope();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWithValue(
          RolePermissions(const ['sales.view', 'customers.view']),
        ),
        businessLayoutProvider.overrideWithValue(businessLayoutFromUser(null)),
      ],
      child: const MaterialApp(home: ReceiptsListScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('R-1001'), findsOneWidget);
    expect(find.text('Private Customer'), findsOneWidget);
    expect(find.text('0712345678'), findsNothing);
    expect(database.allCustomerCalls, 1);
  });

  testWidgets(
      'receipt list drops an in-flight customer lookup after permission revocation',
      (tester) async {
    getIt.pushNewScope();
    final database = _ReceiptDatabase(sale: _sale());
    final pending = Completer<List<Map<String, dynamic>>>();
    final pendingRefresh = Completer<List<Map<String, dynamic>>>();
    database.customerQueries
      ..add(pending)
      ..add(pendingRefresh);
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<AuthService>(
      _ReceiptAuth(
        local: true,
        permissions: const ['sales.view', 'customers.view'],
      ),
    );
    final permissions = _MutableReceiptPermissions(
      RolePermissions(const ['sales.view', 'customers.view']),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!pending.isCompleted) pending.complete([_customer]);
      if (!pendingRefresh.isCompleted) pendingRefresh.complete([_customer]);
      await database.close();
      await getIt.popScope();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWith(
          (ref) => ref.watch(_mutableReceiptPermissionsProvider),
        ),
        _mutableReceiptPermissionsProvider.overrideWith((ref) => permissions),
        businessLayoutProvider.overrideWithValue(businessLayoutFromUser(null)),
      ],
      child: const MaterialApp(home: ReceiptsListScreen()),
    ));
    await tester.pump();
    expect(database.allCustomerCalls, 1);

    permissions.state = RolePermissions(const ['sales.view']);
    await tester.pump();
    permissions.state = RolePermissions(const ['sales.view', 'customers.view']);
    await tester.pump();

    pending.complete([_customer]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Private Customer'), findsNothing);
    expect(find.text('0712345678'), findsNothing);
    if (database.allCustomerCalls > 1) {
      pendingRefresh.complete([_customer]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Private Customer'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('receipt list clears stored customer details on revocation',
      (tester) async {
    getIt.pushNewScope();
    final database = _ReceiptDatabase(sale: _sale());
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<AuthService>(
      _ReceiptAuth(
        local: true,
        permissions: const ['sales.view', 'customers.view'],
      ),
    );
    final permissions = _MutableReceiptPermissions(
      RolePermissions(const ['sales.view', 'customers.view']),
    );
    final refresh = Completer<List<Map<String, dynamic>>>();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!refresh.isCompleted) refresh.complete([_customer]);
      await database.close();
      await getIt.popScope();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWith(
          (ref) => ref.watch(_mutableReceiptPermissionsProvider),
        ),
        _mutableReceiptPermissionsProvider.overrideWith((ref) => permissions),
        businessLayoutProvider.overrideWithValue(businessLayoutFromUser(null)),
      ],
      child: const MaterialApp(home: ReceiptsListScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Private Customer'), findsOneWidget);
    database.customerQueries.add(refresh);

    permissions.state = RolePermissions(const ['sales.view']);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Private Customer'), findsNothing);

    permissions.state = RolePermissions(const ['sales.view', 'customers.view']);
    await tester.pump();
    expect(find.text('Private Customer'), findsNothing);

    refresh.complete([_customer]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Private Customer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
      'local receipt provider does not read or return customer details without customers.view',
      () async {
    getIt.pushNewScope();
    final database = _ReceiptDatabase(sale: _sale());
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<AuthService>(
      _ReceiptAuth(local: true, permissions: const ['sales.view']),
    );
    final container = ProviderContainer(overrides: [
      permissionsProvider.overrideWithValue(
        RolePermissions(const ['sales.view']),
      ),
    ]);
    addTearDown(() async {
      container.dispose();
      await database.close();
      await getIt.popScope();
    });

    final receipt = await container.read(receiptProvider(_saleId).future);

    expect(database.customerLookups, 0);
    expect(receipt, isNot(contains('customerName')));
    expect(receipt, isNot(contains('customerPhone')));
    expect(receipt['hasCustomer'], isTrue);
    expect(receipt['linkedCustomerDetailsHidden'], isTrue);
    expect(receipt['receiptNumber'], 'R-1001');
    expect(receipt['total'], 100);
  });

  test(
      'receipt provider rebuilds with customer details scrubbed after customers.view is revoked',
      () async {
    getIt.pushNewScope();
    final database = _ReceiptDatabase(sale: _sale());
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<AuthService>(
      _ReceiptAuth(
        local: true,
        permissions: const ['sales.view', 'customers.view'],
      ),
    );
    final permissions = _MutableReceiptPermissions(
      RolePermissions(const ['sales.view', 'customers.view']),
    );
    final container = ProviderContainer(overrides: [
      permissionsProvider.overrideWith(
        (ref) => ref.watch(_mutableReceiptPermissionsProvider),
      ),
      _mutableReceiptPermissionsProvider.overrideWith((ref) => permissions),
    ]);
    final subscription = container.listen(receiptProvider(_saleId), (_, __) {});
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await database.close();
      await getIt.popScope();
    });

    final visible = await container.read(receiptProvider(_saleId).future);
    expect(visible['customerName'], 'Private Customer');
    expect(visible['customerPhone'], '0712345678');

    permissions.state = RolePermissions(const ['sales.view']);
    await Future<void>.delayed(Duration.zero);
    final current = container.read(receiptProvider(_saleId));
    if (current.hasValue) {
      expect(current.requireValue, isNot(contains('customerName')));
      expect(current.requireValue, isNot(contains('customerPhone')));
    }
    final restricted = await container.read(receiptProvider(_saleId).future);

    expect(restricted, isNot(contains('customerName')));
    expect(restricted, isNot(contains('customerPhone')));
    expect(restricted['hasCustomer'], isTrue);
    expect(restricted['linkedCustomerDetailsHidden'], isTrue);
  });

  test(
      'customer visibility scrub removes nested PII keys without dropping unrelated receipt data',
      () {
    final receipt = receiptForCustomerVisibility(
      {
        'total': 200,
        'metadata': {
          'customerName': 'Private Customer',
          'note': 'Sale imported',
          'nested': {'customerId': 'customer-1', 'status': 'PAID'},
        },
        'events': [
          {
            'customerPhone': '0712345678',
            'status': 'COMPLETED',
            'details': [
              {'customerEmail': 'private@example.test', 'method': 'CASH'},
            ],
          },
        ],
      },
      canViewCustomerDetails: false,
    );

    void expectNoCustomerKeys(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          expect(entry.key.toString().toLowerCase().startsWith('customer'),
              isFalse);
          expectNoCustomerKeys(entry.value);
        }
      } else if (value is Iterable) {
        for (final item in value) {
          expectNoCustomerKeys(item);
        }
      }
    }

    expectNoCustomerKeys(receipt);
    expect(receipt['total'], 200);
    expect((receipt['metadata'] as Map)['note'], 'Sale imported');
    expect((receipt['metadata'] as Map)['nested']['status'], 'PAID');
    expect((receipt['events'] as List).single['status'], 'COMPLETED');
    expect(
      ((receipt['events'] as List).single['details'] as List).single['method'],
      'CASH',
    );
  });

  test(
      'remote receipt provider removes nested and flattened customer PII without customers.view',
      () async {
    getIt.pushNewScope();
    final database = _ReceiptDatabase();
    final api = _ReceiptApiClient({
      'data': {
        'id': 'remote-sale',
        'receiptNumber': 'R-REMOTE',
        'subtotal': 200,
        'total': 200,
        'paymentMethod': 'CASH',
        'customerId': 'customer-remote',
        'customerName': 'Private Customer',
        'customerPhone': '0712345678',
        'customerEmail': 'private@example.test',
        'customer': _customer,
        'items': const [
          {'name': 'Bread', 'quantity': 1, 'unitPrice': 200, 'total': 200},
        ],
      },
    });
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<ApiClient>(api);
    getIt.registerSingleton<AuthService>(
      _ReceiptAuth(local: false, permissions: const ['sales.view']),
    );
    final container = ProviderContainer(overrides: [
      permissionsProvider.overrideWithValue(
        RolePermissions(const ['sales.view']),
      ),
    ]);
    addTearDown(() async {
      container.dispose();
      await database.close();
      await getIt.popScope();
    });

    final receipt = await container.read(receiptProvider('remote-sale').future);

    expect(api.calls, 1);
    expect(
      receipt.keys.where((key) => key.toLowerCase().startsWith('customer')),
      isEmpty,
    );
    expect(receipt['hasCustomer'], isTrue);
    expect(receipt['linkedCustomerDetailsHidden'], isTrue);
    expect(receipt['receiptNumber'], 'R-REMOTE');
    expect(receipt['total'], 200);
    expect(receipt['items'], hasLength(1));
  });

  test(
      'remote receipt keeps a generic linked-customer flag when nested details are scrubbed',
      () async {
    getIt.pushNewScope();
    final database = _ReceiptDatabase();
    final api = _ReceiptApiClient({
      'data': {
        'receiptNumber': 'R-NESTED',
        'total': 200,
        'metadata': {
          'customerId': 'customer-remote',
          'note': 'Imported sale',
        },
        'items': const [],
      },
    });
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<ApiClient>(api);
    getIt.registerSingleton<AuthService>(
      _ReceiptAuth(local: false, permissions: const ['sales.view']),
    );
    final container = ProviderContainer(overrides: [
      permissionsProvider.overrideWithValue(
        RolePermissions(const ['sales.view']),
      ),
    ]);
    addTearDown(() async {
      container.dispose();
      await database.close();
      await getIt.popScope();
    });

    final receipt = await container.read(receiptProvider('remote-sale').future);

    expect(receipt['hasCustomer'], isTrue);
    expect(receipt['linkedCustomerDetailsHidden'], isTrue);
    expect(receipt['metadata'], {'note': 'Imported sale'});
    expect(receipt['receiptNumber'], 'R-NESTED');
  });

  test('remote receipt provider preserves customer details with customers.view',
      () async {
    getIt.pushNewScope();
    final database = _ReceiptDatabase();
    final api = _ReceiptApiClient({
      'data': {
        'receiptNumber': 'R-REMOTE',
        'total': 200,
        'customerName': 'Private Customer',
        'customerPhone': '0712345678',
        'items': const [],
      },
    });
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<ApiClient>(api);
    getIt.registerSingleton<AuthService>(
      _ReceiptAuth(
        local: false,
        permissions: const ['sales.view', 'customers.view'],
      ),
    );
    final container = ProviderContainer(overrides: [
      permissionsProvider.overrideWithValue(
        RolePermissions(const ['sales.view', 'customers.view']),
      ),
    ]);
    addTearDown(() async {
      container.dispose();
      await database.close();
      await getIt.popScope();
    });

    final receipt = await container.read(receiptProvider('remote-sale').future);

    expect(receipt['customerName'], 'Private Customer');
    expect(receipt['customerPhone'], '0712345678');
    expect(receipt['total'], 200);
  });
}

final _mutableReceiptPermissionsProvider =
    StateNotifierProvider<_MutableReceiptPermissions, RolePermissions>(
  (ref) => _MutableReceiptPermissions(RolePermissions(const [])),
);

class _MutableReceiptPermissions extends StateNotifier<RolePermissions> {
  _MutableReceiptPermissions(super.state);
}

class _ReceiptDatabase extends AppDatabase {
  _ReceiptDatabase({PendingSale? sale})
      : _sale = sale,
        super.forTesting(NativeDatabase.memory(), StorageService());

  final PendingSale? _sale;
  var allCustomerCalls = 0;
  var customerLookups = 0;
  final customerQueries = <Completer<List<Map<String, dynamic>>>>[];

  @override
  Future<List<PendingSale>> getSalesByDateRange(
          DateTime from, DateTime to) async =>
      _sale == null ? const [] : [_sale];

  @override
  Future<List<Map<String, dynamic>>> getAllCustomers() {
    allCustomerCalls++;
    if (customerQueries.isNotEmpty) return customerQueries.removeAt(0).future;
    return Future.value([_customer]);
  }

  @override
  Future<PendingSale?> getPendingSaleById(String saleId) async =>
      _sale?.id == saleId ? _sale : null;

  @override
  Stream<PendingSale?> watchPendingSaleById(String saleId) =>
      Stream.value(_sale?.id == saleId ? _sale : null);

  @override
  Future<List<PendingSaleItem>> getSaleItems(String saleId) async => const [];

  @override
  Future<Map<String, dynamic>?> getCustomer(String id) async {
    customerLookups++;
    return _customer;
  }

  @override
  Future<Map<String, double>?> getSaleCashTender(String saleId) async => null;

  @override
  Future<List<Map<String, dynamic>>> getBranches() async => const [];
}

class _ReceiptAuth implements AuthService {
  _ReceiptAuth({required this.local, required this.permissions});

  final bool local;
  final List<String> permissions;

  @override
  bool get isLocalWorkspace => local;

  @override
  String? get userId => 'cashier-1';

  @override
  Map<String, dynamic>? get currentUser => {
        'name': 'Cashier',
        'tenantName': 'Test Shop',
        'permissions': permissions,
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReceiptApiClient implements ApiClient {
  _ReceiptApiClient(this.response);

  final Map<String, dynamic> response;
  var calls = 0;

  @override
  Future<Map<String, dynamic>> getSale(String id) async {
    calls++;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
