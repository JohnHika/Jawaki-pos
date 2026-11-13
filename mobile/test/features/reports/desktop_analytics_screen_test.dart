import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/core/desktop/desktop_table.dart';
import 'package:axon_pos/core/desktop/desktop_widgets.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_nav.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_shell.dart';
import 'package:axon_pos/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:axon_pos/features/reports/presentation/screens/analytics_dashboard_screen.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/shot.dart';

class _StubStorage extends StorageService {
  _StubStorage() : super();

  @override
  Future<void> initialize() async {}
}

class _AnalyticsDatabase extends AppDatabase {
  _AnalyticsDatabase()
      : super.forTesting(NativeDatabase.memory(), _StubStorage());

  @override
  Future<Map<String, dynamic>> getDashboardSummary({String? branchId}) async =>
      {
        'totalRevenue': 10000.0,
        'transactionCount': 10,
        'avgTicket': 1000.0,
        'itemsSold': 26.0,
      };

  @override
  Future<List<Map<String, dynamic>>> getHourlySales(
    DateTime from,
    DateTime to,
  ) async =>
      [
        {
          'hour': '10',
          'transactionCount': 4,
          'totalAmount': 3600.0,
          'date': '2026-11-10T10:00:00',
        },
        {
          'hour': '11',
          'transactionCount': 6,
          'totalAmount': 6400.0,
          'date': '2026-11-10T11:00:00',
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> getTopProducts(
    DateTime from,
    DateTime to, {
    int limit = 20,
  }) async =>
      [
        {
          'productId': 'p1',
          'productName': 'Maize flour 2kg',
          'totalQty': 16.0,
          'totalRevenue': 4800.0,
        },
        {
          'productId': 'p2',
          'productName': 'Fresh milk 500ml',
          'totalQty': 10.0,
          'totalRevenue': 3200.0,
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> getSalesByPaymentMethod(
    DateTime from,
    DateTime to,
  ) async =>
      [
        {
          'paymentMethod': 'CASH',
          'count': 7,
          'totalAmount': 7100.0,
        },
        {
          'paymentMethod': 'MPESA',
          'count': 3,
          'totalAmount': 2900.0,
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> getSalesByCategory(
    DateTime from,
    DateTime to,
  ) async =>
      [
        {
          'categoryId': 'c1',
          'categoryName': 'Groceries',
          'totalQty': 20.0,
          'totalRevenue': 7800.0,
        },
        {
          'categoryId': 'c2',
          'categoryName': 'Dairy',
          'totalQty': 6.0,
          'totalRevenue': 2200.0,
        },
      ];
}

class _LocalAuthService extends AuthService {
  _LocalAuthService(AppDatabase database)
      : super(
          storage: _StubStorage(),
          apiClient: ApiClient(Dio()),
          database: database,
        );

  @override
  bool get isLocalWorkspace => true;

  @override
  String? get branchId => 'branch-1';
}

class _FakeInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxController {
  _FakeInbox() : super(const NotificationInboxState(unreadCount: 0));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _navItems = [
  DesktopNavItem(
    icon: Icons.bar_chart_outlined,
    activeIcon: Icons.bar_chart_rounded,
    label: 'Reports',
    path: '/reports',
    group: DesktopNavGroup.money,
  ),
];

const _settingsItem = DesktopNavItem(
  icon: Icons.settings_outlined,
  activeIcon: Icons.settings_rounded,
  label: 'Settings',
  path: '/settings',
  group: DesktopNavGroup.more,
);

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final size in [const Size(1366, 768), const Size(1093, 566)]) {
      testWidgets(
        'desktop analytics ${dark ? 'dark' : 'light'} ${size.width.toInt()}',
        (tester) async {
          getIt.pushNewScope();
          final database = _AnalyticsDatabase();
          getIt.registerSingleton<AppDatabase>(database);
          getIt.registerSingleton<AuthService>(_LocalAuthService(database));
          addTearDown(() async {
            await database.close();
            await getIt.popScope();
          });

          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                notificationInboxProvider.overrideWith((ref) => _FakeInbox()),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                home: DesktopShell(
                  items: _navItems,
                  settingsItem: _settingsItem,
                  location: '/reports',
                  onNavigate: (_) {},
                  companyName: 'Evisa Ventures',
                  userName: 'Wanjiru Kamau',
                  role: 'Owner',
                  version: '1.0.181',
                  child: ShotFrame(
                    boundaryKey: boundary,
                    child: const AnalyticsDashboardScreen(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(DesktopMetricStrip), findsOneWidget);
          expect(find.byType(DesktopDataTable), findsNWidgets(3));
          expect(find.text('Maize flour 2kg'), findsOneWidget);
          expect(find.text('Groceries'), findsOneWidget);
          expect(find.byType(RefreshIndicator), findsNothing);
          expect(tester.takeException(), isNull);
          await saveShot(
            tester,
            boundary,
            'build/shots/desktop-analytics-${dark ? 'dark' : 'light'}-${size.width.toInt()}.png',
          );
        },
      );
    }
  }
}
