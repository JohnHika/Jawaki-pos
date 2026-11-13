import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_nav.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_shell.dart';
import 'package:axon_pos/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/shot.dart';

class _FakeInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxController {
  _FakeInbox() : super(const NotificationInboxState(unreadCount: 3));

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
    keywords: ['sale', 'checkout'],
  ),
  DesktopNavItem(
    icon: Icons.auto_awesome_outlined,
    activeIcon: Icons.auto_awesome_rounded,
    label: 'AI',
    path: '/ai',
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
    icon: Icons.warehouse_outlined,
    activeIcon: Icons.warehouse_rounded,
    label: 'Inventory',
    path: '/inventory',
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
    icon: Icons.payments_outlined,
    activeIcon: Icons.payments_rounded,
    label: 'Payments',
    path: '/payments',
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

void main() {
  setUpAll(loadShotFonts);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<String>> pump(
    WidgetTester tester, {
    Size size = const Size(1366, 768),
    ThemeData? theme,
    String location = '/products',
    DesktopConnection connection = DesktopConnection.online,
    GlobalKey? boundary,
  }) async {
    useWindow(tester, size);
    final visited = <String>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationInboxProvider.overrideWith((ref) => _FakeInbox()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: ShotFrame(
          boundaryKey: boundary ?? GlobalKey(),
          child: DesktopShell(
            items: _items,
            settingsItem: _settings,
            location: location,
            onNavigate: visited.add,
            companyName: 'Evisa Ventures',
            userName: 'Wanjiku Kamau',
            role: 'Owner',
            connection: connection,
            child: Scaffold(
              appBar: AppBar(title: const Text('Products')),
              body: const Center(child: Text('page body')),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    return visited;
  }

  testWidgets('shows grouped sidebar, search and the page', (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    for (final label in [
      'Workspace',
      'Stock',
      'Money',
      'People',
      'Home',
      'Sell',
      'Products',
      'Receipts',
      'Customers',
      'Settings',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Search pages and actions'), findsOneWidget);
    expect(find.text('page body'), findsOneWidget);
    expect(find.text('Evisa Ventures'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    // No phone chrome.
    expect(find.text('More'), findsNothing);
  });

  testWidgets('sidebar tap navigates', (tester) async {
    final visited = await pump(tester);
    await tester.tap(find.text('Receipts'));
    expect(visited, ['/receipts']);
  });

  testWidgets('Ctrl+K opens the palette, typing filters, Enter navigates',
      (tester) async {
    final visited = await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Search pages and actions'), findsWidgets);
    expect(find.text('Esc'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'checkout');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(visited, ['/']);
    expect(find.text('Esc'), findsNothing);
  });

  testWidgets('Alt+number jumps to the nth sidebar item', (tester) async {
    final visited = await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(visited, ['/products']);
  });

  testWidgets('narrow window folds the sidebar into an icon rail',
      (tester) async {
    await pump(tester, size: const Size(1024, 720));
    expect(find.text('Workspace'), findsNothing);
    expect(find.text('Evisa Ventures'), findsNothing);
    final sidebar = tester.getSize(find.byType(AnimatedContainer).first);
    expect(sidebar.width, DesktopTokens.railWidth);
  });

  testWidgets('Ctrl+B toggles the sidebar and remembers it', (tester) async {
    await pump(tester);
    expect(find.text('Workspace'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Workspace'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('desktop_sidebar_collapsed'), isTrue);
  });

  for (final dark in [false, true]) {
    testWidgets('screenshot ${dark ? 'dark' : 'light'}', (tester) async {
      final key = GlobalKey();
      await pump(
        tester,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        boundary: key,
        connection: DesktopConnection.localOnly,
      );
      await saveShot(
        tester,
        key,
        'build/shots/desktop-shell-${dark ? 'dark' : 'light'}.png',
      );
    });
  }
}
