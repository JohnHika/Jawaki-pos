import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_nav.dart';
import 'package:axon_pos/features/home/presentation/desktop/desktop_shell.dart';
import 'package:axon_pos/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/shot.dart';

class _FakeInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxController {
  _FakeInbox() : super(const NotificationInboxState(unreadCount: 2));

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

/// The real desktop shell (sidebar, top bar, status bar) around [page], so a
/// screenshot shows the page at the size it really gets.
Widget desktopHost({
  required Widget page,
  required GlobalKey boundary,
  bool dark = false,
  String location = '/settings',
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      notificationInboxProvider.overrideWith((ref) => _FakeInbox()),
      ...overrides,
    ],
    child: MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: ShotFrame(
        boundaryKey: boundary,
        child: DesktopShell(
          items: _items,
          settingsItem: _settings,
          location: location,
          onNavigate: (_) {},
          companyName: 'Mama Njeri General Store',
          userName: 'Wanjiku Kamau',
          role: 'Owner',
          version: '1.0.181',
          child: page,
        ),
      ),
    ),
  );
}

/// Window sizes the desktop pages are designed for.
const laptop = Size(1366, 768);
const laptopScaled = Size(1093, 566);
const monitor = Size(1920, 1080);

/// Makes the platform a computer for this test.
void pretendToBeAComputer() {
  DesktopLayout.debugIsDesktopPlatform = true;
  addTearDown(() => DesktopLayout.debugIsDesktopPlatform = null);
}
