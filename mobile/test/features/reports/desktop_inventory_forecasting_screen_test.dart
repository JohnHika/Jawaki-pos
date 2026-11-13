import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_table.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/desktop/desktop_widgets.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/reports/presentation/screens/inventory_forecasting_screen.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

class _StubStorage extends StorageService {
  _StubStorage() : super();

  @override
  Future<void> initialize() async {}
}

class _ForecastDatabase extends AppDatabase {
  _ForecastDatabase()
      : super.forTesting(NativeDatabase.memory(), _StubStorage());

  @override
  Future<List<Map<String, dynamic>>> getLowStockProducts(
          {String? branchId}) async =>
      [
        {
          'id': 'low-1',
          'name': 'Cooking oil 1L',
          'sku': 'OIL-1L',
          'quantity': 0.0,
          'minStock': 4,
        },
        {
          'id': 'low-2',
          'name': 'Fresh milk 500ml',
          'sku': 'MILK-500',
          'quantity': 3.0,
          'minStock': 6,
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
          'productId': 'fast-1',
          'productName': 'Maize flour 2kg',
          'totalQty': 12.0,
          'totalRevenue': 1800.0,
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> getSlowMovingProducts(
    DateTime from,
    DateTime to, {
    int limit = 10,
  }) async =>
      [
        {
          'productId': 'slow-1',
          'productName': 'Dish soap 500ml',
          'totalQty': 2.0,
          'totalRevenue': 300.0,
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> getDailyItemsSold(
    DateTime from,
    DateTime to,
  ) async =>
      [
        {
          'date': DateTime.now().toIso8601String().substring(0, 10),
          'itemsSold': 5.0,
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
}

void main() {
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final entry in desktopSizes.entries) {
      testWidgets(
        'desktop forecasting ${dark ? 'dark' : 'light'} ${entry.key}',
        (tester) async {
          getIt.pushNewScope();
          final database = _ForecastDatabase();
          getIt.registerSingleton<AppDatabase>(database);
          getIt.registerSingleton<AuthService>(_LocalAuthService(database));
          addTearDown(() async {
            await database.close();
            await getIt.popScope();
          });

          useWindow(tester, entry.value);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: DesktopTheme.of(
                  dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                ),
                home: DesktopScope(
                  sidebarCollapsed: entry.key == '1093',
                  child: ShotFrame(
                    boundaryKey: boundary,
                    child: const InventoryForecastingScreen(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
          expect(scaffold.appBar, isNull);
          expect(find.byType(DesktopMetricStrip), findsOneWidget);
          expect(find.byType(DesktopSearchField), findsOneWidget);
          expect(
            find.byType(DesktopDataTable<Map<String, dynamic>>),
            findsNWidgets(3),
          );
          expect(find.byType(RefreshIndicator), findsNothing);
          expect(find.text('Last 7 Days — Units Sold'), findsOneWidget);
          expect(find.text('Historical actuals'), findsOneWidget);
          expect(find.text('Cooking oil 1L'), findsOneWidget);
          expect(find.text('Maize flour 2kg'), findsOneWidget);
          expect(find.text('Dish soap 500ml'), findsOneWidget);
          for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
            expect(find.text(day), findsOneWidget);
          }
          expect(tester.takeException(), isNull);

          await saveShot(
            tester,
            boundary,
            'build/shots/desktop-forecast-${dark ? 'dark' : 'light'}-${entry.key}.png',
          );

          await tester.enterText(find.byType(TextField), 'soap');
          await tester.pumpAndSettle();
          expect(find.text('Dish soap 500ml'), findsOneWidget);
          expect(find.text('Maize flour 2kg'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
