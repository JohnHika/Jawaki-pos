import 'dart:async';

import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_nav.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_shell.dart';
import 'package:axon_pos/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:axon_pos/features/reports/presentation/desktop/desktop_report_tabs.dart';
import 'package:axon_pos/features/reports/presentation/desktop/desktop_reports_view.dart';
import 'package:axon_pos/features/reports/presentation/providers/reports_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/shot.dart';

class _FakeInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxController {
  _FakeInbox() : super(const NotificationInboxState(unreadCount: 0));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _items = <DesktopNavItem>[
  DesktopNavItem(
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard_rounded,
    label: 'Home',
    path: '/dashboard',
    group: DesktopNavGroup.workspace,
  ),
  DesktopNavItem(
    icon: Icons.point_of_sale_outlined,
    activeIcon: Icons.point_of_sale_rounded,
    label: 'Sell',
    path: '/',
    group: DesktopNavGroup.workspace,
  ),
  DesktopNavItem(
    icon: Icons.analytics_outlined,
    activeIcon: Icons.analytics_rounded,
    label: 'Reports',
    path: '/reports',
    group: DesktopNavGroup.money,
  ),
  DesktopNavItem(
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long_rounded,
    label: 'Receipts',
    path: '/receipts',
    group: DesktopNavGroup.money,
  ),
];

const _settings = DesktopNavItem(
  icon: Icons.settings_outlined,
  activeIcon: Icons.settings_rounded,
  label: 'Settings',
  path: '/settings',
  group: DesktopNavGroup.more,
);

String _at(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute).toIso8601String();
}

final _sales = <Map<String, dynamic>>[
  for (var i = 0; i < 14; i++)
    {
      'id': 's$i',
      'receiptNumber': 'RCP-${(412 - i).toString().padLeft(6, '0')}',
      'totalAmount': [
        1840.0,
        650.0,
        3200.0,
        420.0,
        1250.0,
        780.0,
        2290.0
      ][i % 7],
      'paymentMethod': ['CASH', 'MPESA_RECORDED', 'CREDIT', 'CASH'][i % 4],
      'createdAt': _at(8 + i, (i * 7) % 60),
    },
];

const _payments = <Map<String, dynamic>>[
  {'paymentMethod': 'CASH', 'totalAmount': 14200.0, 'count': 21},
  {'paymentMethod': 'MPESA', 'totalAmount': 9860.0, 'count': 12},
  {'paymentMethod': 'CREDIT', 'totalAmount': 3200.0, 'count': 1},
];

const _top = <Map<String, dynamic>>[
  {
    'productName': 'Unga Jogoo maize flour 2kg',
    'totalQty': 38.0,
    'totalRevenue': 5700.0
  },
  {
    'productName': 'Brookside fresh milk 500ml',
    'totalQty': 31.0,
    'totalRevenue': 2015.0
  },
  {
    'productName': 'Elianto cooking oil 1L',
    'totalQty': 14.0,
    'totalRevenue': 4340.0
  },
  {
    'productName': 'Kenchic chicken, whole, free range',
    'totalQty': 7.0,
    'totalRevenue': 4900.0
  },
];

const _stock = <Map<String, dynamic>>[
  {
    'id': 'p1',
    'name': 'Cooking oil 1L',
    'sku': '6001234000035',
    'stock': 0.0,
    'minStock': 6,
    'categoryName': 'Groceries'
  },
  {
    'id': 'p2',
    'name': 'Fresh milk 500ml',
    'sku': '6001234000028',
    'stock': 6.0,
    'minStock': 12,
    'categoryName': 'Dairy'
  },
  {
    'id': 'p3',
    'name': 'Sugar 2kg',
    'sku': '6001234000011',
    'stock': 48.0,
    'minStock': 10,
    'categoryName': 'Groceries'
  },
  {
    'id': 'p4',
    'name': 'Bread, white',
    'sku': '6001234000042',
    'stock': 22.0,
    'minStock': 8,
    'categoryName': 'Bakery'
  },
];

/// A provider's future resolves between frames: pump twice.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(loadShotFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<String>> pump(
    WidgetTester tester, {
    Size size = const Size(1366, 768),
    bool dark = false,
    GlobalKey? boundary,
    List<Map<String, dynamic>>? sales,
    Future<List<Map<String, dynamic>>> Function()? salesFuture,
    Future<List<Map<String, dynamic>>> Function()? customerFuture,
    Future<bool> Function(DesktopReportKind)? gate,
    DesktopReportKind? kind,
    List<dynamic> permissions = const [
      'reporting.sales_summary',
      'customers.view',
    ],
  }) async {
    useWindow(tester, size);
    final navigated = <String>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationInboxProvider.overrideWith((ref) => _FakeInbox()),
        permissionsProvider.overrideWithValue(RolePermissions(permissions)),
        salesListProvider.overrideWith(
            (ref) => salesFuture?.call() ?? Future.value(sales ?? _sales)),
        paymentMethodProvider.overrideWith((ref) async => _payments),
        cashierPerformanceProvider.overrideWith((ref) async => const []),
        categorySalesProvider.overrideWith((ref) async => const []),
        topProductsProvider.overrideWith((ref) async => _top),
        inventoryReportProvider.overrideWith((ref) async => _stock),
        desktopCustomerReportProvider.overrideWith(
          (ref) => customerFuture?.call() ?? Future.value(const []),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: ShotFrame(
          boundaryKey: boundary ?? GlobalKey(),
          child: DesktopShell(
            items: _items,
            settingsItem: _settings,
            location: '/reports',
            onNavigate: (_) {},
            companyName: 'Wanjiku General Store',
            userName: 'Wanjiku Kamau',
            role: 'Owner',
            connection: DesktopConnection.online,
            child: Scaffold(
              body: DesktopReportsView(
                onNavigate: navigated.add,
                gate: gate,
                initialKind: kind,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    return navigated;
  }

  testWidgets('sales report: chart, sortable table, totals footer',
      (tester) async {
    await pump(tester);
    final problem = tester.takeException();
    if (problem is FlutterError) debugPrint(problem.toStringDeep());
    expect(problem, isNull);
    expect(find.text('Reports'), findsWidgets);
    for (final tab in [
      'Sales',
      'Payments',
      'Cashiers',
      'Categories',
      'Top products',
      'Stock',
      'Customers',
      'Analytics',
      'Forecast',
    ]) {
      expect(find.text(tab), findsWidgets, reason: tab);
    }
    expect(find.text('Sales by hour'), findsOneWidget);
    expect(find.text('Date and time'), findsOneWidget);
    expect(find.text('14 sales'), findsOneWidget);
    // 2 x (1840+650+3200+420+1250+780+2290) = 20,860
    expect(find.text('KES 20,860'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
  });

  testWidgets('tabs switch reports and Stock hides the period switch',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Payments'));
    await settle(tester);
    expect(find.text('Takings by payment method'), findsOneWidget);
    expect(find.text('M-Pesa'), findsWidgets);
    expect(find.text('KES 27,260'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    await tester.tap(find.text('Top products'));
    await settle(tester);
    expect(find.text('Best sellers by sales'), findsOneWidget);
    expect(find.text('Top 4'), findsOneWidget);

    await tester.tap(find.text('Stock'));
    await settle(tester);
    expect(find.text('Out of stock'), findsWidgets);
    expect(find.text('Low stock'), findsWidgets);
    expect(find.text('4 products'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
  });

  testWidgets('the licence gate can keep a tab closed', (tester) async {
    final asked = <DesktopReportKind>[];
    await pump(tester, gate: (kind) async {
      asked.add(kind);
      return false;
    });
    await tester.tap(find.text('Payments'));
    await settle(tester);
    expect(asked, [DesktopReportKind.payments]);
    expect(find.text('Sales by hour'), findsOneWidget);
    // Sales itself is not gated.
    await tester.tap(find.text('Stock'));
    await settle(tester);
    expect(asked, [DesktopReportKind.payments]);
  });

  testWidgets(
      'Customers tab does not load or display PII without customers.view',
      (tester) async {
    var reads = 0;
    await pump(
      tester,
      permissions: const ['reporting.sales_summary', 'customers.create'],
      customerFuture: () async {
        reads++;
        return const [
          {
            'id': 'c1',
            'name': 'Private Customer',
            'phone': '0712345678',
            'totalPurchases': 4,
            'totalSpent': 12345.0,
          },
        ];
      },
    );

    await tester.tap(find.text('Customers'));
    await settle(tester);

    expect(reads, 0);
    expect(find.text('Private Customer'), findsNothing);
    expect(find.text('0712345678'), findsNothing);
    expect(find.text('KES 12,345'), findsNothing);
    expect(find.text('Sales by hour'), findsOneWidget);
  });

  testWidgets(
      'direct Customers report state withholds PII without customers.view',
      (tester) async {
    var reads = 0;
    await pump(
      tester,
      kind: DesktopReportKind.customers,
      permissions: const ['reporting.sales_summary', 'customers.create'],
      customerFuture: () async {
        reads++;
        return const [
          {
            'id': 'c1',
            'name': 'Private Customer',
            'phone': '0712345678',
            'totalPurchases': 4,
            'totalSpent': 12345.0,
          },
        ];
      },
    );

    expect(reads, 0);
    expect(find.text('Private Customer'), findsNothing);
    expect(find.text('0712345678'), findsNothing);
    expect(find.text('KES 12,345'), findsNothing);
  });

  testWidgets('customers.view keeps the desktop customer report available',
      (tester) async {
    var reads = 0;
    await pump(
      tester,
      kind: DesktopReportKind.customers,
      permissions: const ['reporting.sales_summary', 'customers.view'],
      customerFuture: () async {
        reads++;
        return const [
          {
            'id': 'c1',
            'name': 'Private Customer',
            'phone': '0712345678',
            'totalPurchases': 4,
            'totalSpent': 12345.0,
          },
        ];
      },
    );
    await settle(tester);

    expect(reads, 1);
    expect(find.text('Private Customer'), findsWidgets);
    expect(find.text('0712345678'), findsOneWidget);
    expect(find.text('KES 12,345'), findsWidgets);
  });

  testWidgets('Analytics and Forecast tabs go to their own routes',
      (tester) async {
    final navigated = await pump(tester);
    await tester.tap(find.text('Analytics'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Forecast'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(navigated, ['/reports/analytics', '/reports/inventory-forecast']);
  });

  testWidgets('opening a sale row with Enter goes to its receipt',
      (tester) async {
    final navigated = await pump(tester);
    // Newest first: s13 is the latest sale of the day.
    await tester.tap(find.text('RCP-000399'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 100));
    expect(navigated, ['/receipt/s13']);
  });

  testWidgets('period switch changes the shared date range', (tester) async {
    await pump(tester);
    await tester.tap(find.text('This week'));
    await settle(tester);
    expect(find.text('Sales by day'), findsOneWidget);
  });

  testWidgets('empty period says what to do', (tester) async {
    final navigated = await pump(tester, sales: const []);
    expect(find.text('No sales in this period'), findsOneWidget);
    await tester.tap(find.text('Start a sale'));
    expect(navigated, ['/']);
  });

  testWidgets('error explains and offers a retry', (tester) async {
    await pump(
      tester,
      salesFuture: () =>
          Future<List<Map<String, dynamic>>>.error(StateError('x')),
    );
    expect(find.text("Couldn't load this report"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  for (final size in const [Size(1366, 768), Size(1093, 566)]) {
    for (final dark in [false, true]) {
      final tag = '${size.width.round()}x${size.height.round()}';
      final mode = dark ? 'dark' : 'light';
      testWidgets('screenshot sales $mode $tag', (tester) async {
        final key = GlobalKey();
        await pump(tester, size: size, dark: dark, boundary: key);
        expect(tester.takeException(), isNull);
        await saveShot(tester, key, 'build/shots/reports-sales-$mode-$tag.png');
      });
    }
  }

  testWidgets('screenshot stock light 1366x768', (tester) async {
    final key = GlobalKey();
    await pump(tester, boundary: key, kind: DesktopReportKind.stock);
    expect(tester.takeException(), isNull);
    await saveShot(tester, key, 'build/shots/reports-stock-light-1366x768.png');
  });

  testWidgets('screenshot payments dark 1366x768', (tester) async {
    final key = GlobalKey();
    await pump(
      tester,
      boundary: key,
      dark: true,
      kind: DesktopReportKind.payments,
    );
    expect(tester.takeException(), isNull);
    await saveShot(
        tester, key, 'build/shots/reports-payments-dark-1366x768.png');
  });

  testWidgets('screenshot empty light 1366x768', (tester) async {
    final key = GlobalKey();
    await pump(tester, boundary: key, sales: const []);
    expect(tester.takeException(), isNull);
    await saveShot(tester, key, 'build/shots/reports-empty-light-1366x768.png');
  });

  testWidgets('screenshot loading light 1366x768', (tester) async {
    final key = GlobalKey();
    await pump(
      tester,
      boundary: key,
      salesFuture: () => Completer<List<Map<String, dynamic>>>().future,
    );
    expect(tester.takeException(), isNull);
    await saveShot(
        tester, key, 'build/shots/reports-loading-light-1366x768.png');
  });
}
