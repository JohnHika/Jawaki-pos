import 'dart:async';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/database/app_database.dart' hide CartItem;
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/reports/presentation/providers/reports_provider.dart';
import 'package:axon_pos/features/reports/presentation/screens/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

const _customer = <String, dynamic>{
  'id': 'customer-1',
  'name': 'Private Customer',
  'phone': '0712345678',
  'balance': 450.0,
  'totalPurchases': 12,
  'totalSpent': 12345.0,
  'lastPurchaseAt': '2026-11-12T10:00:00',
};

void main() {
  testWidgets(
      'mobile customer report does not fetch or display PII without customers.view',
      (tester) async {
    final harness = await _pump(
      tester,
      permissions: const ['reporting.sales_summary', 'customers.create'],
    );
    addTearDown(harness.dispose);

    await tester.ensureVisible(find.text('Customer Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer Report'));
    await tester.pumpAndSettle();

    expect(harness.database.customerReads, 0);
    expect(find.text('Private Customer'), findsNothing);
    expect(find.text('0712345678'), findsNothing);
    expect(find.textContaining('12 purchases'), findsNothing);
    expect(find.textContaining('12,345'), findsNothing);
  });

  testWidgets('customers.view preserves the mobile customer report',
      (tester) async {
    final harness = await _pump(
      tester,
      permissions: const ['reporting.sales_summary', 'customers.view'],
    );
    addTearDown(harness.dispose);

    await tester.ensureVisible(find.text('Customer Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer Report'));
    await tester.pumpAndSettle();

    expect(harness.database.customerReads, 1);
    expect(find.text('Private Customer'), findsOneWidget);
    expect(find.textContaining('0712345678'), findsOneWidget);
    expect(find.textContaining('12 purchases'), findsOneWidget);
    expect(find.textContaining('12,345'), findsOneWidget);
  });
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required List<dynamic> permissions,
}) async {
  getIt.pushNewScope();
  final auth = _Auth();
  final database = _CustomerDatabase();
  getIt.registerSingleton<AuthService>(auth);
  getIt.registerSingleton<AppDatabase>(database);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      permissionsProvider.overrideWithValue(RolePermissions(permissions)),
      dashboardSummaryProvider.overrideWith((ref) async => const {
            'totalRevenue': 1000.0,
            'transactionCount': 3,
            'avgTicket': 333.33,
            'itemsSold': 5.0,
          }),
      businessLayoutProvider.overrideWithValue(businessLayoutFromUser(null)),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: const ReportsScreen()),
  ));
  await tester.pumpAndSettle();
  return _Harness(database, auth);
}

class _Harness {
  const _Harness(this.database, this.auth);
  final _CustomerDatabase database;
  final _Auth auth;
  Future<void> dispose() async {
    await database.close();
    await getIt.popScope();
    await auth.close();
  }
}

class _CustomerDatabase extends AppDatabase {
  _CustomerDatabase()
      : super.forTesting(NativeDatabase.memory(), _NoopStorage());

  var customerReads = 0;

  @override
  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    customerReads++;
    return [_customer];
  }
}

class _Auth implements AuthService {
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
        'permissions': ['reporting.sales_summary'],
      };
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
