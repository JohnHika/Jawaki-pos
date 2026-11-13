import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/core/desktop/desktop_split.dart';
import 'package:axon_pos/core/desktop/desktop_table.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/desktop/desktop_widgets.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/coupons/domain/coupon_models.dart';
import 'package:axon_pos/features/coupons/presentation/providers/coupon_provider.dart';
import 'package:axon_pos/features/coupons/presentation/screens/coupons_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

final _coupons = <ShopCoupon>[
  ShopCoupon(
    id: 'coupon-1',
    code: 'SAVE10',
    name: 'Harvest discount',
    isPercent: true,
    value: 10,
    maxDiscount: 500,
    minSpend: 1000,
    startsAt: DateTime(2026, 10, 1),
    expiresAt: DateTime(2026, 11, 30),
    usageLimit: 20,
    usedCount: 4,
    perCustomerLimit: 2,
    isActive: true,
    status: 'ACTIVE',
    description: '10% off up to KES 500',
  ),
  const ShopCoupon(
    id: 'coupon-2',
    code: 'KES250OFF',
    name: null,
    isPercent: false,
    value: 250,
    maxDiscount: null,
    minSpend: null,
    startsAt: null,
    expiresAt: null,
    usageLimit: null,
    usedCount: 1,
    perCustomerLimit: null,
    isActive: false,
    status: 'OFF',
    description: 'KES 250 off',
  ),
];

const _report = CouponReport(
  days: 30,
  uses: 7,
  totalGiven: 1250,
  byCashier: [
    CouponUse(label: 'Asha', uses: 5, given: 900),
    CouponUse(label: 'Njeri', uses: 2, given: 350),
  ],
);

GoRouter _router({bool desktopShell = true, GlobalKey? boundary}) => GoRouter(
      initialLocation: '/coupons',
      routes: [
        GoRoute(
          path: '/coupons',
          builder: (context, state) {
            Widget page = const CouponsScreen();
            if (boundary != null) {
              page = ShotFrame(boundaryKey: boundary, child: page);
            }
            return desktopShell
                ? DesktopScope(sidebarCollapsed: true, child: page)
                : page;
          },
        ),
      ],
    );

Widget _app(GoRouter router, {bool dark = false, bool desktop = true}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  return ProviderScope(
    overrides: [
      couponsProvider.overrideWith((ref) async => _coupons),
      couponReportProvider.overrideWith((ref) async => _report),
      permissionsProvider.overrideWithValue(
        RolePermissions(const ['coupons.view', 'coupons.manage']),
      ),
      businessLayoutProvider
          .overrideWith((ref) => businessLayoutFromUser(null)),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: desktop ? DesktopTheme.of(base) : base,
      routerConfig: router,
    ),
  );
}

void main() {
  setUpAll(loadShotFonts);

  setUp(() {
    DesktopLayout.debugIsDesktopPlatform = true;
  });

  tearDown(() {
    DesktopLayout.debugIsDesktopPlatform = null;
  });

  for (final dark in [false, true]) {
    for (final entry in desktopSizes.entries) {
      testWidgets(
        'desktop coupons workspace ${dark ? 'dark' : 'light'} ${entry.key}',
        (tester) async {
          useWindow(tester, entry.value);
          final boundary = GlobalKey();
          final router = _router(boundary: boundary);
          addTearDown(router.dispose);

          await tester.pumpWidget(_app(router, dark: dark));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(DesktopPageHeader), findsOneWidget);
          expect(find.byType(DesktopDataTable<ShopCoupon>), findsOneWidget);
          expect(find.text('Last 30 days'), findsOneWidget);
          expect(find.text('7 used'), findsOneWidget);
          expect(find.text('KES 1,250'), findsOneWidget);
          expect(find.text('Most by Asha'), findsOneWidget);
          expect(find.text('5 (KES 900)'), findsOneWidget);
          expect(find.text('SAVE10'), findsOneWidget);
          expect(find.text('KES250OFF'), findsOneWidget);
          expect(find.byType(FloatingActionButton), findsNothing);
          expect(find.byType(RefreshIndicator), findsNothing);

          await tester.tap(find.text('SAVE10'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(DesktopInspector), findsOneWidget);
          expect(find.text('Minimum spend'), findsOneWidget);
          expect(find.text('KES 1,000.00'), findsOneWidget);

          await saveShot(
            tester,
            boundary,
            'build/shots/coupons-desktop-${dark ? 'dark' : 'light'}-${entry.key}.png',
          );
        },
      );
    }
  }

  testWidgets('desktop create action opens the existing coupon editor',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coupons-create')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Code (optional)'), findsOneWidget);
    expect(find.text('Create coupon'), findsOneWidget);
    expect(find.text('Minimum spend (optional)'), findsOneWidget);
    expect(find.text('Total uses'), findsOneWidget);
    expect(find.text('Per customer'), findsOneWidget);
    expect(find.text('Valid for'), findsOneWidget);
    expect(find.text('30 days'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Create coupon'), findsNothing);
  });

  testWidgets('desktop inspector edit action keeps the existing edit rules',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE10'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coupon-edit')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Code (optional)'), findsNothing);
    expect(find.text('Delete (switches off, keeps history)'), findsOneWidget);
    expect(find.text('Switched on'), findsOneWidget);
  });

  testWidgets('phone coupons screen retains its existing list and actions',
      (tester) async {
    useWindow(tester, const Size(430, 850));
    final router = _router(desktopShell: false);
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router, desktop: false));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DesktopPageHeader), findsNothing);
    expect(find.byType(DesktopDataTable<ShopCoupon>), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('SAVE10'), findsOneWidget);

    await tester.tap(find.text('SAVE10'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Delete (switches off, keeps history)'), findsOneWidget);
  });
}
