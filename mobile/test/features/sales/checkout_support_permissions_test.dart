import 'dart:async';

import 'package:axon_pos/core/database/app_database.dart' hide CartItem;
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/features/sales/presentation/desktop/checkout_support.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _customer = <String, dynamic>{
  'id': 'customer-1',
  'name': 'Private Customer',
  'phone': '0712345678',
  'balance': 450.0,
};

void main() {
  test(
      'desktop checkout host does not read customer PII without customers.view',
      () async {
    getIt.pushNewScope();
    final auth = _Auth(const ['customers.create']);
    final database = _CountingDatabase();
    getIt.registerSingleton<AuthService>(auth);
    getIt.registerSingleton<AppDatabase>(database);
    addTearDown(() async {
      await database.close();
      await getIt.popScope();
      await auth.close();
    });

    const host = GetItSellCheckoutHost();

    expect(await host.searchCustomers('Private'), isEmpty);
    expect(await host.customerPhone('customer-1'), isNull);
    expect(database.searchCalls, 0);
    expect(database.customerLookups, 0);
  });

  test('desktop checkout host still reads customers with customers.view',
      () async {
    getIt.pushNewScope();
    final auth = _Auth(const ['customers.view']);
    final database = _CountingDatabase();
    getIt.registerSingleton<AuthService>(auth);
    getIt.registerSingleton<AppDatabase>(database);
    addTearDown(() async {
      await database.close();
      await getIt.popScope();
      await auth.close();
    });

    const host = GetItSellCheckoutHost();

    expect(await host.searchCustomers('Private'), [_customer]);
    expect(await host.customerPhone('customer-1'), '0712345678');
    expect(database.searchCalls, 1);
    expect(database.customerLookups, 1);
  });
}

class _CountingDatabase extends AppDatabase {
  _CountingDatabase()
      : super.forTesting(NativeDatabase.memory(), _NoopStorage());

  var searchCalls = 0;
  var customerLookups = 0;

  @override
  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    searchCalls++;
    return [_customer];
  }

  @override
  Future<Map<String, dynamic>?> getCustomer(String id) async {
    customerLookups++;
    return _customer;
  }
}

class _Auth implements AuthService {
  _Auth(List<String> permissions)
      : currentUser = {
          'authMode': 'local',
          'permissions': permissions,
        };

  final _status = StreamController<AuthStatus>.broadcast();
  @override
  final Map<String, dynamic> currentUser;

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
  Stream<AuthStatus> get authStatusStream => _status.stream;
  Future<void> close() => _status.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopStorage implements StorageService {
  @override
  Future<void> initialize() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
