import 'dart:async';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/providers/tenant_provider.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/sync_service.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:axon_pos/features/licence/presentation/licence_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PendingSale _sale() => PendingSale(
      id: 'sale-from-laptop',
      receiptNumber: 'R-LAPTOP-1',
      subtotal: 250,
      discount: 0,
      tax: 0,
      total: 250,
      paymentMethod: 'CASH',
      customerId: null,
      cashierId: 'cashier-1',
      branchId: 'branch-1',
      status: 'COMPLETED',
      createdAt: DateTime.now(),
      isSynced: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home refresh pulls cloud sales into the recent-sales list',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    getIt.pushNewScope();
    final database = _DashboardDatabase();
    final sync = _DashboardSyncService(database);
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<AuthService>(_DashboardAuth());
    getIt.registerSingleton<ApiClient>(_DashboardApiClient(database));
    getIt.registerSingleton<SyncService>(sync);

    final baseLayout = businessLayoutFromUser(null);
    final quietTestLayout = BusinessLayoutConfig(
      preset: baseLayout.preset,
      priorityPaths: baseLayout.priorityPaths,
      dashboardSections: const ['summary_metrics', 'recent_sales'],
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.salesUpdates.close();
      await database.close();
      await getIt.popScope();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWithValue(
          RolePermissions(const ['sales.create', 'sales.view']),
        ),
        tenantIdentityProvider.overrideWithValue(TenantIdentity.empty),
        businessLayoutProvider.overrideWithValue(quietTestLayout),
        licenceViewProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ));
    await tester.pumpAndSettle();

    expect(sync.pullCalls, 1);
    expect(find.text('No sales today yet'), findsOneWidget);

    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await refresh.onRefresh();
    await tester.pumpAndSettle();

    expect(sync.pullCalls, 2);
    expect(find.text('R-LAPTOP-1'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(sync.pullCalls, 3);
    expect(find.text('R-LAPTOP-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DashboardDatabase extends AppDatabase {
  _DashboardDatabase()
      : super.forTesting(NativeDatabase.memory(), StorageService());

  final salesUpdates = StreamController<List<PendingSale>>.broadcast();
  List<PendingSale> sales = const [];

  void addSale(PendingSale sale) {
    sales = [sale, ...sales];
    salesUpdates.add(sales);
  }

  Map<String, dynamic> summary() {
    final revenue = sales.fold<double>(0, (sum, sale) => sum + sale.total);
    return {
      'transactionCount': sales.length,
      'totalRevenue': revenue,
      'avgTicket': sales.isEmpty ? 0.0 : revenue / sales.length,
      'itemsSold': 0.0,
      'unsyncedTransactionCount': 0,
      'unsyncedRevenue': 0.0,
      'unsyncedItemsSold': 0.0,
    };
  }

  @override
  Future<Map<String, dynamic>> getDashboardSummary({String? branchId}) async =>
      summary();

  @override
  Stream<List<PendingSale>> watchTodaysSales() async* {
    yield sales;
    yield* salesUpdates.stream;
  }

  @override
  Future<double> getTodaysTotalPurchases(String branchId) async => 0;
}

class _DashboardAuth implements AuthService {
  @override
  bool get isLocalWorkspace => false;

  @override
  bool get isAuthenticated => true;

  @override
  String? get branchId => null;

  @override
  Map<String, dynamic>? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DashboardApiClient implements ApiClient {
  _DashboardApiClient(this.database);

  final _DashboardDatabase database;

  @override
  Future<Map<String, dynamic>> getDashboard(
      {String? period, String? branchId}) async {
    final local = database.summary();
    return {
      'sales': {
        'totalSales': local['transactionCount'],
        'totalRevenue': local['totalRevenue'],
        'averageTicket': local['avgTicket'],
        'itemsSold': local['itemsSold'],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getTenantOnboarding() async => {
        'steps': [
          {'key': 'invite_staff', 'status': 'COMPLETED'},
        ],
      };

  @override
  Future<Map<String, dynamic>> getNotifications({
    int limit = 50,
    String? before,
  }) async =>
      {
        'items': const [],
        'unreadCount': 0,
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DashboardSyncService implements SyncService {
  _DashboardSyncService(this.database);

  final _DashboardDatabase database;
  var pullCalls = 0;

  @override
  Future<void> pullChanges({String? since}) async {
    pullCalls++;
    if (pullCalls > 1 && database.sales.isEmpty) database.addSale(_sale());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
