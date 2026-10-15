import 'package:axon_pos/features/settings/presentation/widgets/settings_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({ThemeMode mode = ThemeMode.light, double width = 400}) {
  var taps = 0;
  final sections = [
    SettingsSection(
      id: 'business',
      title: 'My business',
      entries: [
        SettingsEntry(
          id: 'tax',
          icon: Icons.percent_rounded,
          title: 'Tax & receipts',
          subtitle: 'Set the tax charged on sales and shown on receipts, '
              'with a very long description that must wrap on small phones',
          keywords: const ['vat'],
          onTap: () => taps++,
        ),
      ],
    ),
    SettingsSection(
      id: 'security',
      title: 'Security',
      entries: [
        SettingsEntry(
          id: 'pin',
          icon: Icons.lock_rounded,
          title: 'Quick-unlock PIN',
          subtitle: 'A 4–6 digit PIN to open the app on this phone',
          onTap: () => taps++,
        ),
      ],
    ),
    const SettingsSection(
      id: 'sign-out',
      title: 'Sign out',
      entries: [
        SettingsEntry(
          id: 'logout',
          icon: Icons.logout_rounded,
          title: 'Sign out of this phone',
          destructive: true,
        ),
      ],
    ),
  ];

  return MaterialApp(
    themeMode: mode,
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: Scaffold(
        body: SettingsSectionList(
          header: const SettingsProfileHeader(
            name: 'A Very Long Shop Owner Name That Keeps Going',
            email: 'owner.with.a.long.address@example-business-domain.co.ke',
            roleLabel: 'Admin',
            businessName: 'Mama Njeri General Store And Wholesale Limited',
            companyCode: 'MAMANJERI',
            branchName: 'Main branch',
            isOnline: true,
          ),
          sections: sections,
          footer: const Text('Axon POS'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows header, grouped sections and footer', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.textContaining('MAMANJERI', findRichText: true), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-copy-company-code')),
        findsOneWidget);
    expect(find.text('My business'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-tile-tax')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters rows and shows an empty state', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('settings-search')), 'vat');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-tile-tax')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-tile-pin')), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('settings-search')), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No settings found'), findsOneWidget);
  });

  testWidgets('renders without overflow in dark theme', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(mode: ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(find.text('Quick-unlock PIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
