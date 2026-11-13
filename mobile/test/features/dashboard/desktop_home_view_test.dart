import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/dashboard/presentation/desktop/desktop_bar_chart.dart';
import 'package:axon_pos/features/dashboard/presentation/desktop/desktop_home_models.dart';
import 'package:axon_pos/features/dashboard/presentation/desktop/desktop_home_view.dart';
import 'package:axon_pos/features/home/domain/shop_guidance.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_nav.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_shell.dart';
import 'package:axon_pos/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
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
    icon: Icons.inventory_2_outlined,
    activeIcon: Icons.inventory_2_rounded,
    label: 'Products',
    path: '/products',
    group: DesktopNavGroup.stock,
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
  DesktopNavItem(
    icon: Icons.people_outlined,
    activeIcon: Icons.people_rounded,
    label: 'Customers',
    path: '/customers',
    group: DesktopNavGroup.people,
  ),
];

const _settings = DesktopNavItem(
  icon: Icons.settings_outlined,
  activeIcon: Icons.settings_rounded,
  label: 'Settings',
  path: '/settings',
  group: DesktopNavGroup.more,
);

DateTime _at(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

final _sales = <HomeSaleRow>[
  HomeSaleRow(
      id: 's12',
      receiptNumber: 'RCP-000412',
      createdAt: _at(17, 42),
      paymentMethod: 'CASH',
      total: 1840),
  HomeSaleRow(
      id: 's11',
      receiptNumber: 'RCP-000411',
      createdAt: _at(17, 18),
      paymentMethod: 'MPESA_RECORDED',
      total: 650),
  HomeSaleRow(
      id: 's10',
      receiptNumber: 'RCP-000410',
      createdAt: _at(16, 55),
      paymentMethod: 'CREDIT',
      total: 3200),
  HomeSaleRow(
      id: 's9',
      receiptNumber: 'RCP-000409',
      createdAt: _at(16, 31),
      paymentMethod: 'CASH',
      total: 420,
      status: 'VOIDED'),
  HomeSaleRow(
      id: 's8',
      receiptNumber: 'RCP-000408',
      createdAt: _at(15, 12),
      paymentMethod: 'MPESA_RECORDED',
      total: 1250),
  HomeSaleRow(
      id: 's7',
      receiptNumber: 'RCP-000407',
      createdAt: _at(13, 40),
      paymentMethod: 'CASH',
      total: 780),
  HomeSaleRow(
      id: 's6',
      receiptNumber: 'RCP-000406',
      createdAt: _at(12, 5),
      paymentMethod: 'CASH',
      total: 2290),
  HomeSaleRow(
      id: 's5',
      receiptNumber: 'RCP-000405',
      createdAt: _at(10, 50),
      paymentMethod: 'MPESA_RECORDED',
      total: 560),
  HomeSaleRow(
      id: 's4',
      receiptNumber: 'RCP-000404',
      createdAt: _at(9, 26),
      paymentMethod: 'CASH',
      total: 310),
  HomeSaleRow(
      id: 's3',
      receiptNumber: 'RCP-000403',
      createdAt: _at(8, 44),
      paymentMethod: 'CASH',
      total: 1480),
  HomeSaleRow(
      id: 's2',
      receiptNumber: 'RCP-000402',
      createdAt: _at(8, 10),
      paymentMethod: 'CASH',
      total: 95),
  HomeSaleRow(
      id: 's1',
      receiptNumber: 'RCP-000401',
      createdAt: _at(7, 35),
      paymentMethod: 'CASH',
      total: 240),
];

const _products = <HomeProductRow>[
  HomeProductRow(
      name: 'Unga Jogoo maize flour 2kg', quantity: 38, revenue: 5700),
  HomeProductRow(
      name: 'Brookside fresh milk 500ml', quantity: 31, revenue: 2015),
  HomeProductRow(name: 'Elianto cooking oil 1L', quantity: 14, revenue: 4340),
  HomeProductRow(name: 'Mumias sugar 2kg', quantity: 12, revenue: 3960),
  HomeProductRow(
      name: 'Kenchic chicken, whole, free range', quantity: 7, revenue: 4900),
  HomeProductRow(name: 'Safaricom airtime KES 100', quantity: 6, revenue: 600),
];

DesktopHomeData _full({
  HomeRange range = HomeRange.today,
  bool loading = false,
}) {
  final completed = _sales.where((s) => s.isCompleted).toList();
  final revenue = completed.fold<double>(0, (a, s) => a + s.total);
  return DesktopHomeData(
    range: range,
    loading: loading,
    revenue: loading ? 0 : revenue,
    transactions: loading ? 0 : completed.length,
    avgTicket: revenue / completed.length,
    itemsSold: 108,
    split: TakingsSplit(
      cash: completed
          .where((s) => s.paymentMethod == 'CASH')
          .fold<double>(0, (a, s) => a + s.total),
      recorded: 2460,
      credit: 3200,
      recordedCount: 3,
    ),
    cost: 9800,
    canAdjustCost: true,
    bars: loading ? const [] : hourlyBarsFromSales(_sales),
    sales: loading ? const [] : _sales,
    salesCount: loading ? 0 : _sales.length,
    topProducts: loading ? const [] : _products,
    attention: const [
      HomeAttentionItem(
        id: 'alerts',
        level: HomeAttentionLevel.serious,
        title: '2 serious alerts to check',
        detail: 'Sales below cost, voids, stock written off, credit and more.',
        path: '/shop-alerts',
      ),
      HomeAttentionItem(
        id: 'recorded',
        level: HomeAttentionLevel.warning,
        title: '3 recorded payments to match',
        detail: 'Check them against your M-Pesa or bank statement.',
        path: '/mpesa-match',
      ),
      HomeAttentionItem(
        id: 'end-of-day',
        level: HomeAttentionLevel.info,
        title: "Close today's till",
        detail: 'Review the sales and count the till when you finish selling.',
        path: '/cash-flow/end-of-day',
      ),
    ],
  );
}

const _empty = DesktopHomeData(range: HomeRange.today);

void main() {
  setUpAll(loadShotFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<String>> pump(
    WidgetTester tester, {
    required DesktopHomeData data,
    Size size = const Size(1366, 768),
    bool dark = false,
    GlobalKey? boundary,
    ValueChanged<HomeRange>? onRange,
    VoidCallback? onRefresh,
  }) async {
    useWindow(tester, size);
    final opened = <String>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationInboxProvider.overrideWith((ref) => _FakeInbox()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: ShotFrame(
          boundaryKey: boundary ?? GlobalKey(),
          child: DesktopShell(
            items: _items,
            settingsItem: _settings,
            location: '/dashboard',
            onNavigate: (_) {},
            companyName: 'Wanjiku General Store',
            userName: 'Wanjiku Kamau',
            role: 'Owner',
            connection: DesktopConnection.online,
            child: Scaffold(
              body: DesktopHomeView(
                data: data,
                updatedAt: DateTime(2026, 11, 10, 17, 44),
                onRangeChanged: onRange ?? (_) {},
                onRefresh: onRefresh ?? () {},
                onOpen: opened.add,
                onAdjustProfit: () => opened.add('adjust'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    return opened;
  }

  testWidgets('shows the strip, chart, attention list and both tables',
      (tester) async {
    await pump(tester, data: _full());
    expect(tester.takeException(), isNull);
    expect(find.text('Home'), findsWidgets);
    for (final label in [
      'Sales',
      'Cash',
      'M-Pesa or bank',
      'On credit',
      'Profit',
      'Sales by hour',
      'Needs attention',
      'Recent sales',
      'Top products',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Start a sale'), findsOneWidget);
    expect(find.textContaining('Updated 17:44'), findsOneWidget);
    expect(find.text('RCP-000412'), findsOneWidget);
    expect(find.text('Voided'), findsOneWidget);
    expect(find.text('2 serious alerts to check'), findsOneWidget);
    expect(find.text('Unga Jogoo maize flour 2kg'), findsOneWidget);
  });

  testWidgets('key figures and rows are clickable and go to their pages',
      (tester) async {
    final opened = await pump(tester, data: _full());
    await tester.tap(find.text('M-Pesa or bank'));
    await tester.tap(find.text('Cash').first);
    await tester.tap(find.text('3 recorded payments to match'));
    await tester.ensureVisible(find.text('RCP-000411'));
    await tester.pump();
    await tester.tap(find.text('RCP-000411'));
    await tester.tap(find.text('Start a sale'));
    await tester.tap(find.text('All receipts'));
    expect(opened, [
      '/mpesa-match',
      '/cash-flow',
      '/mpesa-match',
      '/receipt/s11',
      '/',
      '/receipts',
    ]);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('the period switch and Ctrl+R call back', (tester) async {
    final ranges = <HomeRange>[];
    var refreshed = 0;
    await pump(
      tester,
      data: _full(),
      onRange: ranges.add,
      onRefresh: () => refreshed++,
    );
    await tester.tap(find.text('7 days'));
    await tester.tap(find.text('30 days'));
    expect(ranges, [HomeRange.week, HomeRange.month]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(refreshed, 1);
    await tester.tap(find.textContaining('Refresh (Ctrl+R)'));
    expect(refreshed, 2);
  });

  testWidgets('empty shop teaches what to do first', (tester) async {
    final opened = await pump(tester, data: _empty);
    expect(tester.takeException(), isNull);
    expect(find.text('No sales yet today'), findsOneWidget);
    expect(find.text('Add products'), findsOneWidget);
    expect(find.text('Nothing needs your attention'), findsOneWidget);
    await tester.tap(find.text('Add products'));
    expect(opened, ['/products']);
  });

  testWidgets('hovering a bar shows the hour and its takings', (tester) async {
    useWindow(tester, const Size(900, 500));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: DesktopBarChart(
            bars: hourlyBarsFromSales(_sales),
            height: 260,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    final chart = find.byType(DesktopBarChart);
    final box = tester.getRect(chart);
    // 5 pm is the eleventh bar of the 7am to 7pm axis.
    await mouse.moveTo(Offset(
      box.left + 46 + (box.width - 46) * (10.5 / 13),
      box.bottom - 50,
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // The tooltip is painted on the canvas, so read what it would say.
    final data = tester.widget<BarChart>(find.byType(BarChart)).data;
    final group = data.barGroups[10]; // 5 pm
    final item = data.barTouchData.touchTooltipData
        .getTooltipItem(group, 10, group.barRods.first, 0)!;
    expect(item.text, contains('5 pm'));
    expect(item.children!.first.toPlainText(), contains('KES 2,490 · 2 sales'));
  });

  for (final size in const [Size(1366, 768), Size(1093, 566)]) {
    for (final dark in [false, true]) {
      final tag = '${size.width.round()}x${size.height.round()}';
      final mode = dark ? 'dark' : 'light';

      testWidgets('screenshot full $mode $tag', (tester) async {
        final key = GlobalKey();
        await pump(tester,
            data: _full(), size: size, dark: dark, boundary: key);
        expect(tester.takeException(), isNull);
        await saveShot(tester, key, 'build/shots/dash-home-$mode-$tag.png');

        // The same page scrolled to the bottom, to check the tables.
        await tester.drag(
            find.byType(SingleChildScrollView).last, const Offset(0, -2000));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        await saveShot(
            tester, key, 'build/shots/dash-home-$mode-$tag-scrolled.png');
      });

      testWidgets('screenshot empty shop $mode $tag', (tester) async {
        final key = GlobalKey();
        await pump(tester, data: _empty, size: size, dark: dark, boundary: key);
        expect(tester.takeException(), isNull);
        await saveShot(tester, key, 'build/shots/dash-empty-$mode-$tag.png');
      });
    }
  }

  testWidgets('screenshot loading light 1366x768', (tester) async {
    final key = GlobalKey();
    await pump(tester, data: _full(loading: true), boundary: key);
    expect(tester.takeException(), isNull);
    await saveShot(tester, key, 'build/shots/dash-loading-light-1366x768.png');
  });

  testWidgets('screenshot 7 days light 1920x1080', (tester) async {
    final key = GlobalKey();
    await pump(
      tester,
      data: _full(range: HomeRange.week),
      size: const Size(1920, 1080),
      boundary: key,
    );
    expect(tester.takeException(), isNull);
    await saveShot(tester, key, 'build/shots/dash-home-light-1920x1080.png');
  });

  testWidgets('narrow window stacks the grid into one column', (tester) async {
    await pump(tester, data: _full(), size: const Size(960, 600));
    expect(tester.takeException(), isNull);
    final chart = tester.getTopLeft(find.text('Sales by hour'));
    final attention = tester.getTopLeft(find.text('Needs attention'));
    expect(attention.dx, chart.dx);
    expect(attention.dy, greaterThan(chart.dy));
  });
}
