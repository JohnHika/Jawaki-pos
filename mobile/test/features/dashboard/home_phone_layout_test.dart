import 'dart:async';
import 'dart:convert';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/providers/local_workspace_capabilities.dart';
import 'package:axon_pos/core/providers/tenant_provider.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/sync_service.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/dashboard/domain/dashboard_summary_cache.dart';
import 'package:axon_pos/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:axon_pos/features/dashboard/presentation/widgets/home_cards.dart';
import 'package:axon_pos/features/dashboard/presentation/widgets/home_phone_widgets.dart';
import 'package:axon_pos/features/home/domain/home_quick_actions.dart';
import 'package:axon_pos/features/licence/presentation/licence_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

PendingSale _sale(String id, double total, {String method = 'CASH'}) =>
    PendingSale(
      id: id,
      receiptNumber: 'R-$id',
      subtotal: total,
      discount: 0,
      tax: 0,
      total: total,
      paymentMethod: method,
      customerId: null,
      cashierId: 'cashier-1',
      branchId: 'branch-1',
      status: 'COMPLETED',
      createdAt: DateTime.now(),
      isSynced: true,
    );

BusinessLayoutConfig _layout(String profileId) {
  final base = businessLayoutFromUser({
    'tenant': {
      'settings': {
        'businessLayout': {'profileId': profileId},
      },
    },
  });
  // No AI brief or cost card: they reach the network when "More" is opened.
  return BusinessLayoutConfig(
    preset: base.preset,
    priorityPaths: base.priorityPaths,
    dashboardSections: const ['summary_metrics', 'recent_sales'],
  );
}

final _staff = RolePermissions(const [
  'sales.create',
  'sales.view',
  'products.view',
  'customers.view',
  'inventory.stock.view',
  'reporting.dashboard',
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _HomeDatabase database;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    getIt.pushNewScope();
    database = _HomeDatabase();
    getIt.registerSingleton<AppDatabase>(database);
    getIt.registerSingleton<AuthService>(_HomeAuth());
    getIt.registerSingleton<ApiClient>(_HomeApi(database));
    getIt.registerSingleton<SyncService>(_HomeSync());
  });

  tearDown(() async {
    await database.salesUpdates.close();
    await database.close();
    await getIt.popScope();
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    required Size size,
    String profile = 'kamukunji_counter',
    double textScale = 1,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        permissionsProvider.overrideWithValue(_staff),
        tenantIdentityProvider.overrideWithValue(TenantIdentity.empty),
        businessLayoutProvider.overrideWithValue(_layout(profile)),
        licenceViewProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const DashboardScreen(),
      ),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  group('phone Home keeps a calm order', () {
    for (final entry in <String, ({Size size, double scale})>{
      'phone 390x844': (size: const Size(390, 844), scale: 1),
      'small phone 360x640': (size: const Size(360, 640), scale: 1),
      'small phone, large text': (size: const Size(360, 640), scale: 1.4),
      'fold cover 360x740': (size: const Size(360, 740), scale: 1),
      'fold opened 840x760': (size: const Size(840, 760), scale: 1),
      'tablet 820x1180': (size: const Size(820, 1180), scale: 1),
    }.entries) {
      testWidgets('${entry.key}: no overflow, the essentials are there',
          (tester) async {
        database.sales = [
          _sale('1', 250),
          _sale('2', 400, method: 'MPESA_RECORDED'),
          _sale('3', 120, method: 'CREDIT'),
          _sale('4', 90),
          _sale('5', 60),
          _sale('6', 30),
        ];
        await pumpHome(tester, size: entry.value.size, textScale: entry.value.scale);

        expect(tester.takeException(), isNull);
        expect(find.text('Sold today'), findsOneWidget);
        expect(find.text('Start a sale'), findsOneWidget);
        expect(find.text('Quick actions'), findsOneWidget);
        expect(find.text('Recent sales'), findsOneWidget);
        expect(find.text('More for today'), findsOneWidget);
        // The reminder for the recorded payment is one of the cards that need
        // doing now.
        expect(find.textContaining('recorded payment'), findsOneWidget);
        // Only four recent rows; the rest are in Receipts.
        expect(find.textContaining('R-'), findsNWidgets(4));
        // The fold stays closed until asked for.
        expect(find.text('Your shop, up to date'), findsNothing);

        await tester.ensureVisible(find.text('More for today'));
        await tester.tap(find.text('More for today'));
        await tester.pumpAndSettle();
        expect(find.text('Your shop, up to date'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('More for today'));
        await tester.pumpAndSettle();
        expect(find.text('Your shop, up to date'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('a phone stacks one column; a wide page puts the lists beside it',
      (tester) async {
    database.sales = [_sale('1', 250), _sale('2', 90)];

    await pumpHome(tester, size: const Size(390, 844));
    final phoneHero = tester.getTopLeft(find.byType(HomeTakingsCard));
    final phoneRecent = tester.getTopLeft(find.text('Recent sales'));
    // Same left edge (the label is inset 4 px), and below the hero.
    expect(phoneRecent.dx, closeTo(phoneHero.dx + 4, 0.5));
    expect(phoneRecent.dy, greaterThan(phoneHero.dy));

    await pumpHome(tester, size: const Size(840, 760));
    final wideHero = tester.getTopLeft(find.byType(HomeTakingsCard));
    final wideRecent = tester.getTopLeft(find.text('Recent sales'));
    expect(wideRecent.dx, greaterThan(wideHero.dx + 200));
    expect(wideRecent.dy, lessThan(wideHero.dy + 60));
  });

  testWidgets('the fold is the same Home with the shop profile accent',
      (tester) async {
    database.sales = [_sale('1', 250)];
    await pumpHome(tester, size: const Size(390, 844), profile: 'bakery_food_counter');

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Start a sale'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(
      button.style!.backgroundColor!.resolve(<WidgetState>{}),
      const Color(0xFFE8893A),
    );
  });

  testWidgets('saved figures show at once with Updating, never zeros or a spinner',
      (tester) async {
    final key = DashboardSummaryCache.keyFor(
      tenantId: null,
      branchId: null,
      day: DateTime.now(),
    );
    SharedPreferences.setMockInitialValues({
      'swr:dashboard-summary:$key': jsonEncode({
        'v': 1,
        't': DateTime.now().millisecondsSinceEpoch,
        'd': {
          'totalRevenue': 4321.0,
          'transactionCount': 7,
          'avgTicket': 617.0,
          'itemsSold': 12,
        },
      }),
    });
    final gate = Completer<void>();
    database.summaryGate = gate.future;
    database.sales = [_sale('1', 250)];

    await pumpHome(tester, size: const Size(390, 844), settle: false);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('4,321'), findsOneWidget);
    expect(find.text('Updating…'), findsOneWidget);
    expect(find.byType(HomeTakingsSkeleton), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Updating…'), findsNothing);
    expect(find.text('4,321'), findsNothing);
    // The hero and the Cash legend both show 250.
    expect(find.text('250'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with nothing saved yet the hero is a skeleton, not zeros',
      (tester) async {
    final gate = Completer<void>();
    database.summaryGate = gate.future;

    await pumpHome(tester, size: const Size(390, 844), settle: false);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(HomeTakingsSkeleton), findsOneWidget);
    expect(find.text('No sales yet today'), findsNothing);
    expect(find.text('Start a sale'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(HomeTakingsSkeleton), findsNothing);
    expect(find.text('No sales yet today'), findsOneWidget);
  });

  testWidgets('pull to refresh says it is up to date', (tester) async {
    database.sales = [_sale('1', 250)];
    await pumpHome(tester, size: const Size(390, 844));

    final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    await refresh.onRefresh();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Up to date'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  group('quick actions follow the shop layout and the person', () {
    final full = RolePermissions(const ['*']);

    test('lead with the profile order, leave out Sell and Home, max four', () {
      final layout = _layout('kamukunji_counter');
      final actions = homeQuickActions(
        layout: layout,
        permissions: full,
        localWorkspace: false,
      );
      expect(actions.length, 4);
      final paths = actions.map((a) => a.path).toList();
      expect(paths, isNot(contains('/')));
      expect(paths, isNot(contains('/dashboard')));
      expect(paths.toSet().length, paths.length);
      final expectedFirst = layout.priorityPaths.firstWhere(
        (p) => p != '/' && p != '/dashboard' && p != '/ai',
      );
      expect(paths.first, expectedFirst);
    });

    test('a hidden area and a closed door are not offered', () {
      final base = _layout('kamukunji_counter');
      final hiding = BusinessLayoutConfig(
        preset: base.preset,
        priorityPaths: base.priorityPaths,
        hiddenPaths: const ['/products'],
      );
      final paths = homeQuickActions(
        layout: hiding,
        permissions: full,
        localWorkspace: false,
      ).map((a) => a.path);
      expect(paths, isNot(contains('/products')));

      expect(
        homeQuickActions(
          layout: base,
          permissions: RolePermissions(const ['sales.create']),
          localWorkspace: false,
        ),
        isEmpty,
      );
    });

    test('a device-only shop is offered only what it supports', () {
      final actions = homeQuickActions(
        layout: _layout('bookshop'),
        permissions: full,
        localWorkspace: true,
      );
      expect(actions, isNotEmpty);
      for (final action in actions) {
        expect(LocalWorkspaceCapabilities.supportsPath(action.path), isTrue);
      }
    });

    test('the profile sets the accent, otherwise the app orange', () {
      expect(homeAccentFor(_layout('kamukunji_counter')), const Color(0xFF2F9E8F));
      expect(homeAccentFor(_layout('bakery_food_counter')), const Color(0xFFE8893A));
    });
  });

  test('saved figures are per shop, branch and day', () async {
    final cache = DashboardSummaryCache();
    final today = DateTime(2026, 11, 15);
    final key = DashboardSummaryCache.keyFor(
        tenantId: 't1', branchId: 'b1', day: today);
    await cache.write(key, {
      'totalRevenue': 100.0,
      'transactionCount': 2,
      'avgTicket': 50.0,
      'itemsSold': 3,
      'notStored': 'x',
    });

    final back = await cache.read(key);
    expect(back!['totalRevenue'], 100.0);
    expect(back.containsKey('notStored'), isFalse);
    expect(
      await cache.read(DashboardSummaryCache.keyFor(
          tenantId: 't1', branchId: 'b1', day: DateTime(2026, 11, 16))),
      isNull,
    );
    expect(
      await cache.read(DashboardSummaryCache.keyFor(
          tenantId: 't2', branchId: 'b1', day: today)),
      isNull,
    );
  });
}

class _HomeDatabase extends AppDatabase {
  _HomeDatabase() : super.forTesting(NativeDatabase.memory(), StorageService());

  final salesUpdates = StreamController<List<PendingSale>>.broadcast();
  List<PendingSale> sales = const [];

  /// When set, the local totals are not ready until it completes.
  Future<void>? summaryGate;

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
  Future<Map<String, dynamic>> getDashboardSummary({String? branchId}) async {
    final gate = summaryGate;
    if (gate != null) await gate;
    return summary();
  }

  @override
  Stream<List<PendingSale>> watchTodaysSales() async* {
    yield sales;
    yield* salesUpdates.stream;
  }

  @override
  Future<double> getTodaysTotalPurchases(String branchId) async => 0;
}

class _HomeAuth implements AuthService {
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

class _HomeApi implements ApiClient {
  _HomeApi(this.database);

  final _HomeDatabase database;

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
      {'items': const [], 'unreadCount': 0};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HomeSync implements SyncService {
  @override
  Future<void> pullChanges({String? since}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
