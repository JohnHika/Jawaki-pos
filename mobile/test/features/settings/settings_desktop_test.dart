import 'package:axon_pos/core/services/desktop_update_service.dart';
import 'package:axon_pos/features/settings/presentation/desktop/settings_desktop_page.dart';
import 'package:axon_pos/features/settings/presentation/desktop/settings_desktop_panes.dart';
import 'package:axon_pos/features/settings/presentation/desktop/settings_desktop_widgets.dart';
import 'package:axon_pos/features/settings/presentation/widgets/settings_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/shot.dart';
import 'support/desktop_host.dart';

SettingsEntry _entry(
  String id,
  IconData icon,
  String title,
  String subtitle, {
  VoidCallback? onTap,
  bool destructive = false,
  List<String> keywords = const [],
}) =>
    SettingsEntry(
      id: id,
      icon: icon,
      title: title,
      subtitle: subtitle,
      keywords: keywords,
      destructive: destructive,
      onTap: onTap ?? () {},
    );

List<SettingsSection> _sections(List<String> opened) {
  void open(String id) => opened.add(id);
  return [
    SettingsSection(id: 'shop', title: 'Shop', entries: [
      _entry('business-layout', Icons.tune_rounded, 'Layout actions',
          'Shape Counterbase around your shop and daily work',
          onTap: () => open('business-layout')),
      _entry('logo', Icons.image_rounded, 'Business logo',
          'Change the logo for your shop',
          onTap: () => open('logo')),
      _entry('branches', Icons.store_rounded, 'Branches',
          'Add or edit your shop locations',
          onTap: () => open('branches')),
      _entry('hours', Icons.schedule_rounded, 'Opening hours',
          'Choose when each branch opens and closes',
          onTap: () => open('hours')),
    ]),
    SettingsSection(id: 'team', title: 'Team', entries: [
      _entry('staff', Icons.people_rounded, 'Staff & roles',
          'Add your team and choose what each person can do',
          onTap: () => open('staff')),
    ]),
    SettingsSection(id: 'money', title: 'Money', entries: [
      _entry('tax', Icons.percent_rounded, 'Tax & receipts',
          '16% tax is added to sales',
          keywords: const ['vat'], onTap: () => open('tax')),
      _entry(
          'merchant-payouts',
          Icons.account_balance_rounded,
          'Customer payments & payouts',
          'Manage the bank account for sales and debt collections'),
      _entry('billing', Icons.workspace_premium_rounded, 'Plan & billing',
          'Your plan, renewal date, M-Pesa payments and invoices',
          onTap: () => open('billing')),
    ]),
    SettingsSection(id: 'devices', title: 'Devices & printing', entries: [
      _entry('local-data', Icons.storage_rounded, 'Local data',
          'See where this device keeps shop records'),
      _entry('printers', Icons.print_rounded, 'Receipts & printers',
          'Connect a Bluetooth printer and set how receipts print',
          keywords: const ['printer'], onTap: () => open('printers')),
      _entry('notification-centre', Icons.inbox_rounded, 'Inbox',
          'Everything the app has told you, in one place'),
      _entry('notifications', Icons.notifications_rounded, 'Alert settings',
          'Choose which alerts you get on this phone'),
      _entry('appearance', Icons.palette_rounded, 'Appearance',
          'Light or dark look'),
    ]),
    SettingsSection(id: 'security', title: 'Security', entries: [
      _entry('pin', Icons.lock_rounded, 'Quick-unlock PIN',
          'A 4–6 digit PIN to open the app on this phone',
          keywords: const ['password'], onTap: () => open('pin')),
      _entry(
          'device-security',
          Icons.fingerprint_rounded,
          'Sign-in & auto-lock',
          'Choose PIN or biometric unlock and when the app locks'),
      _entry(
          'desktop-approvals',
          Icons.laptop_windows_rounded,
          'Sign in a computer',
          'Scan the code on a computer to open your shop there'),
    ]),
    SettingsSection(id: 'data', title: 'Your data', entries: [
      _entry('export', Icons.download_rounded, 'Download my data',
          'Save your sales, stock and products as PDF or CSV'),
      _entry('activity', Icons.history_rounded, 'Activity history',
          'See who did what in your shop'),
    ]),
    SettingsSection(id: 'help', title: 'Help', entries: [
      _entry('help', Icons.help_rounded, 'Help & support',
          'Contact us, common questions and guides'),
      _entry('report', Icons.bug_report_rounded, 'Report a problem',
          'Tell us if something is not working'),
      _entry('legal', Icons.policy_outlined, 'Legal & policies',
          'Terms, privacy, billing, and payment policies'),
    ]),
    SettingsSection(id: 'sign-out', title: 'Sign out', entries: [
      _entry('logout', Icons.logout_rounded, 'Sign out of this phone',
          'Anything not yet backed up stays safe on this phone',
          destructive: true, onTap: () => open('logout')),
      _entry('logout-all', Icons.devices_rounded, 'Sign out of all devices',
          'Signs you out on every phone and browser',
          destructive: true, onTap: () => open('logout-all')),
    ]),
  ];
}

DesktopUpdateService _updater({DesktopUpdateInfo? latest}) =>
    DesktopUpdateService(
      supported: true,
      releaseLoader: () async => latest,
      packageInfo: () async => PackageInfo(
        appName: 'Counterbase',
        packageName: 'com.example.counterbase',
        version: '1.0.181',
        buildNumber: '2224',
      ),
    );

Widget _page({
  required List<String> opened,
  DesktopUpdateService? updates,
  String? initialPaneId,
  bool local = false,
}) {
  return Scaffold(
    body: DesktopSettingsPage(
      initialPaneId: initialPaneId,
      panes: buildDesktopSettingsPanes(
        DesktopSettingsDeps(
          sections: _sections(opened),
          isLocalWorkspace: local,
          version: const DesktopAppVersion('1.0.181', '2224'),
          updates: updates,
          notifyKeys: const DesktopNotifyKeys(
            sales: 'notify_sales',
            inventory: 'notify_inventory',
            sync: 'notify_sync',
          ),
          osNotificationsGranted: () async => true,
          requestOsNotifications: () async => true,
          openUserGuide: () => opened.add('user-guide'),
          openWebsite: () => opened.add('website'),
          profile: const DesktopSettingsProfile(
            name: 'Wanjiku Kamau',
            email: 'wanjiku@mamanjeri.co.ke',
            roleLabel: 'Owner',
            businessName: 'Mama Njeri General Store And Wholesale',
            branchName: 'Kamukunji main branch',
            companyCode: 'MAMANJERI',
            isOnline: true,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadShotFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pretendToBeAComputer();
  });

  group('screenshots', () {
    for (final dark in [false, true]) {
      for (final size in [laptop, laptopScaled, monitor]) {
        final mode = dark ? 'dark' : 'light';
        testWidgets('business pane $mode ${size.width.toInt()}',
            (tester) async {
          useWindow(tester, size);
          final key = GlobalKey();
          await tester.pumpWidget(desktopHost(
            boundary: key,
            dark: dark,
            page: _page(opened: [], updates: _updater()),
          ));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          await saveShot(tester, key,
              'build/shots/settings-business-$mode-${size.width.toInt()}.png');
        });
      }

      testWidgets('appearance pane $dark', (tester) async {
        useWindow(tester, laptop);
        final key = GlobalKey();
        await tester.pumpWidget(desktopHost(
          boundary: key,
          dark: dark,
          page: _page(opened: [], initialPaneId: 'appearance'),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Dark').first);
        await tester.pump(const Duration(milliseconds: 100));
        await saveShot(tester, key,
            'build/shots/settings-appearance-${dark ? 'dark' : 'light'}-1366.png');
        expect(tester.takeException(), isNull);
        // Put the theme back for the next test.
        SharedPreferences.setMockInitialValues({});
      });

      testWidgets('updates pane ${dark ? 'dark' : 'light'}', (tester) async {
        useWindow(tester, laptop);
        final key = GlobalKey();
        final updates = _updater();
        await updates.initialize();
        await tester.pumpWidget(desktopHost(
          boundary: key,
          dark: dark,
          page: _page(opened: [], updates: updates, initialPaneId: 'updates'),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        await saveShot(tester, key,
            'build/shots/settings-updates-${dark ? 'dark' : 'light'}-1366.png');
        expect(tester.takeException(), isNull);
      });

      testWidgets('notifications pane ${dark ? 'dark' : 'light'}',
          (tester) async {
        useWindow(tester, laptopScaled);
        final key = GlobalKey();
        await tester.pumpWidget(desktopHost(
          boundary: key,
          dark: dark,
          page: _page(opened: [], initialPaneId: 'notifications'),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        await saveShot(tester, key,
            'build/shots/settings-notifications-${dark ? 'dark' : 'light'}-1093.png');
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('left navigation lists the panes in three groups',
      (tester) async {
    useWindow(tester, laptop);
    await tester.pumpWidget(desktopHost(
        boundary: GlobalKey(), page: _page(opened: [], updates: _updater())));
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in [
      'Shop',
      'This computer',
      'Account',
      'Business',
      'Receipts and printing',
      'Payments',
      'Users and roles',
      'Security and devices',
      'Notifications',
      'Appearance',
      'Data and backup',
      'Updates',
      'Plan and billing',
      'About and help',
      'Sign out',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    // The Business pane is first and shows the profile card.
    expect(find.text('Wanjiku Kamau'), findsWidgets);
    expect(find.text('MAMANJERI'), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-setting-logo')), findsOneWidget);
  });

  testWidgets('choosing a pane shows its rows, and a row runs the same handler',
      (tester) async {
    final opened = <String>[];
    useWindow(tester, laptop);
    await tester.pumpWidget(
        desktopHost(boundary: GlobalKey(), page: _page(opened: opened)));
    await tester.pump(const Duration(milliseconds: 300));

    await tester
        .tap(find.byKey(const ValueKey('desktop-settings-nav-receipts')));
    await tester.pump();
    expect(find.byKey(const ValueKey('desktop-setting-tax')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('desktop-setting-printers')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-setting-logo')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('desktop-setting-tax')));
    expect(opened, ['tax']);
  });

  testWidgets('Users and roles opens the Users page instead of a pane',
      (tester) async {
    final opened = <String>[];
    useWindow(tester, laptop);
    await tester.pumpWidget(
        desktopHost(boundary: GlobalKey(), page: _page(opened: opened)));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('desktop-settings-nav-users')));
    await tester.pump();
    expect(opened, ['staff']);
    // Still on the Business pane.
    expect(find.byKey(const ValueKey('desktop-settings-pane-business')),
        findsOneWidget);
  });

  testWidgets('says computer instead of phone', (tester) async {
    useWindow(tester, laptop);
    await tester.pumpWidget(desktopHost(
        boundary: GlobalKey(),
        page: _page(opened: [], initialPaneId: 'signout')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sign out of this computer'), findsOneWidget);
    expect(find.textContaining('this phone'), findsNothing);
    expect(find.text('Sign out of all devices'), findsOneWidget);
    expect(find.textContaining('every phone, computer and browser'),
        findsOneWidget);
  });

  testWidgets('sign out buttons call the existing handlers', (tester) async {
    final opened = <String>[];
    useWindow(tester, laptop);
    await tester.pumpWidget(desktopHost(
        boundary: GlobalKey(),
        page: _page(opened: opened, initialPaneId: 'signout')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester
        .tap(find.widgetWithText(OutlinedButton, 'Sign out everywhere'));
    expect(opened, ['logout', 'logout-all']);
  });

  testWidgets('a notification switch saves at once and says Saved',
      (tester) async {
    useWindow(tester, laptop);
    await tester.pumpWidget(desktopHost(
        boundary: GlobalKey(),
        page: _page(opened: [], initialPaneId: 'notifications')));
    await tester.pump(const Duration(milliseconds: 400));

    final saved = find.byType(DesktopSavedIndicator);
    expect(
        tester
            .widget<AnimatedOpacity>(find.descendant(
                of: saved, matching: find.byType(AnimatedOpacity)))
            .opacity,
        0);

    final row = find.byKey(const ValueKey('desktop-setting-alerts-sales'));
    expect(row, findsOneWidget);
    await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await tester.pump(const Duration(milliseconds: 100));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notify_sales'), isFalse);
    expect(
        tester
            .widget<AnimatedOpacity>(find.descendant(
                of: saved, matching: find.byType(AnimatedOpacity)))
            .opacity,
        1);

    await tester.pump(const Duration(seconds: 3));
    expect(
        tester
            .widget<AnimatedOpacity>(find.descendant(
                of: saved, matching: find.byType(AnimatedOpacity)))
            .opacity,
        0);
  });

  testWidgets('a device-only workspace explains why alerts are off',
      (tester) async {
    useWindow(tester, laptop);
    await tester.pumpWidget(desktopHost(
        boundary: GlobalKey(),
        page: _page(opened: [], initialPaneId: 'notifications', local: true)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Device-only notifications'), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-setting-alerts-sales')),
        findsNothing);
  });

  testWidgets('theme choice applies at once and persists', (tester) async {
    useWindow(tester, laptop);
    await tester.pumpWidget(desktopHost(
        boundary: GlobalKey(),
        page: _page(opened: [], initialPaneId: 'appearance')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Dark').first);
    await tester.pump(const Duration(milliseconds: 100));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_mode'), 'dark');
    expect(find.text('Use system setting'), findsOneWidget);
  });

  testWidgets('Check for updates opens the Windows updater and rechecks',
      (tester) async {
    useWindow(tester, laptop);
    final updates = _updater();
    await tester.pumpWidget(desktopHost(
        boundary: GlobalKey(),
        page: _page(opened: [], updates: updates, initialPaneId: 'updates')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('1.0.181 (build 2224)'), findsOneWidget);
    expect(updates.overlayOpen, isFalse);
    await tester
        .tap(find.byKey(const ValueKey('desktop-check-updates-button')));
    await tester.pump();
    expect(updates.overlayOpen, isTrue);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('latest version'), findsOneWidget);
  });

  testWidgets('an available update is announced with a View update button',
      (tester) async {
    useWindow(tester, laptop);
    final updates = _updater(
      latest: DesktopUpdateInfo(
        version: '1.0.182',
        build: 2230,
        tag: 'v1.0.182-2230',
        installerUrl: Uri.parse(
            'https://github.com/JohnHika/Jawaki-pos/releases/download/v1.0.182-2230/Counterbase-Setup.exe'),
        notes: 'Faster till and a fix for printing receipts.',
      ),
    );
    await updates.initialize();
    await updates.checkForUpdates(force: true);
    await tester.pumpWidget(desktopHost(
        boundary: GlobalKey(),
        page: _page(opened: [], updates: updates, initialPaneId: 'updates')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('1.0.182'), findsWidgets);
    expect(find.text('View update'), findsOneWidget);
    expect(find.textContaining('Faster till'), findsOneWidget);
  });

  testWidgets('search finds a setting in any pane', (tester) async {
    final opened = <String>[];
    useWindow(tester, laptop);
    await tester.pumpWidget(
        desktopHost(boundary: GlobalKey(), page: _page(opened: opened)));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
        find.byKey(const ValueKey('desktop-settings-search')), 'printer');
    await tester.pump();
    expect(
        find.byKey(const ValueKey('desktop-settings-results')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('desktop-setting-printers')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-setting-logo')), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('desktop-settings-search')), 'zzzz');
    await tester.pump();
    expect(find.text('No settings found'), findsOneWidget);
  });

  testWidgets('arrow keys move through the navigation', (tester) async {
    useWindow(tester, laptop);
    await tester.pumpWidget(
        desktopHost(boundary: GlobalKey(), page: _page(opened: [])));
    await tester.pump(const Duration(milliseconds: 300));
    await tester
        .tap(find.byKey(const ValueKey('desktop-settings-nav-business')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const ValueKey('desktop-settings-pane-receipts')),
        findsOneWidget);
  });

  testWidgets('a role without access sees no pane for what is hidden',
      (tester) async {
    useWindow(tester, laptop);
    await tester.pumpWidget(desktopHost(
      boundary: GlobalKey(),
      page: Scaffold(
        body: DesktopSettingsPage(
          panes: buildDesktopSettingsPanes(
            DesktopSettingsDeps(
              sections: [
                SettingsSection(id: 'sign-out', title: 'Sign out', entries: [
                  _entry('logout', Icons.logout_rounded,
                      'Sign out of this phone', 'Stays safe on this phone',
                      destructive: true),
                ]),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('desktop-settings-nav-signout')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-settings-nav-payments')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('desktop-settings-nav-users')), findsNothing);
  });
}
