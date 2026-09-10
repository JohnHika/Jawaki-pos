import 'dart:async';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/connectivity_service.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/billing/domain/billing_entitlement.dart';
import 'package:axon_pos/features/billing/presentation/providers/entitlement_provider.dart';
import 'package:axon_pos/features/billing/presentation/widgets/subscription_restricted_banner.dart';
import 'package:axon_pos/features/home/presentation/screens/home_nav_keys.dart';
import 'package:axon_pos/features/home/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _active = BillingEntitlement(
  plan: 'CORE',
  status: 'ACTIVE',
  daysRemaining: 30,
);
const _restricted = BillingEntitlement(
  plan: 'CORE',
  status: 'RESTRICTED',
  restrictedMode: true,
  restrictedReason: 'Payment overdue',
);

void main() {
  for (final entry in <String, BillingEntitlement?>{
    'null entitlement': null,
    'active entitlement without a banner': _active,
  }.entries) {
    testWidgets('${entry.key} keeps routed content finite and navigable',
        (tester) async {
      final harness = await _pumpHome(tester, entitlement: entry.value);

      _expectFinitePage(tester, harness, 'POS');
      expect(find.byType(SubscriptionRestrictedBanner), findsNothing);
      expect(find.text('Offline Mode'), findsNothing);
      await _exerciseNavigation(tester, harness);
    });
  }

  testWidgets(
      'restricted banner preserves layout through navigation and dismissal',
      (tester) async {
    final harness = await _pumpHome(tester, entitlement: _restricted);

    _expectFinitePage(tester, harness, 'POS');
    expect(find.text('Subscription paused').hitTestable(), findsOneWidget);
    await _exerciseNavigation(tester, harness);
    expect(find.text('Subscription paused').hitTestable(), findsOneWidget);
    final heightWithBanner = harness.constraints['POS']!.maxHeight;

    await tester.tap(find.descendant(
      of: find.byType(SubscriptionRestrictedBanner),
      matching: find.byIcon(Icons.close_rounded),
    ));
    await tester.pumpAndSettle();

    _expectFinitePage(tester, harness, 'POS');
    expect(find.byType(SubscriptionRestrictedBanner), findsNothing);
    expect(
        harness.constraints['POS']!.maxHeight, greaterThan(heightWithBanner));
    await _exerciseNavigation(tester, harness);
    expect(find.byType(SubscriptionRestrictedBanner), findsNothing);
  });

  testWidgets(
      'offline and restricted banners share finite space with routed content',
      (tester) async {
    final harness = await _pumpHome(
      tester,
      entitlement: _restricted,
      status: ConnectionStatus.offline,
    );

    _expectFinitePage(tester, harness, 'POS');
    expect(find.text('Offline Mode').hitTestable(), findsOneWidget);
    expect(find.text('Subscription paused').hitTestable(), findsOneWidget);
    await _exerciseNavigation(tester, harness);
    final offlineHeight = harness.constraints['POS']!.maxHeight;

    harness.connectivity.setStatus(ConnectionStatus.online);
    await tester.pumpAndSettle();

    _expectFinitePage(tester, harness, 'POS');
    expect(find.text('Offline Mode'), findsNothing);
    expect(find.text('Subscription paused').hitTestable(), findsOneWidget);
    expect(harness.constraints['POS']!.maxHeight, greaterThan(offlineHeight));
    await _exerciseNavigation(tester, harness);
  });
}

Future<_HomeHarness> _pumpHome(
  WidgetTester tester, {
  required BillingEntitlement? entitlement,
  ConnectionStatus status = ConnectionStatus.online,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final connectivity = _FakeConnectivityService(status);
  // HomeScreen resolves connectivity through GetIt, not its Riverpod fallback.
  // A scope isolates the fake without initializing database/platform services.
  getIt.pushNewScope();
  getIt.registerSingleton<ConnectivityService>(connectivity);
  final constraints = <String, BoxConstraints>{};
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => HomeScreen(child: child),
        routes: [
          for (final route in <String, String>{
            '/': 'POS',
            '/products': 'Products',
            '/settings': 'Settings',
          }.entries)
            GoRoute(
              path: route.key,
              builder: (context, state) => _RouteContent(
                label: route.value,
                onLayout: (value) => constraints[route.value] = value,
              ),
            ),
        ],
      ),
    ],
  );
  addTearDown(() async {
    // Unmount before disposing the router, stream, and scoped dependencies.
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await getIt.popScope();
    await connectivity.close();
  });

  await tester.pumpWidget(ProviderScope(
    overrides: [
      permissionsProvider.overrideWithValue(
        RolePermissions(const ['products.view', 'sales.create']),
      ),
      // Start in the specified resolved branch, avoiding a transient loading
      // branch masking the restricted host's own flex-constraint regression.
      entitlementProvider.overrideWith((ref) => entitlement),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return _HomeHarness(router, connectivity, constraints);
}

void _expectFinitePage(
  WidgetTester tester,
  _HomeHarness harness,
  String label,
) {
  // Do not swallow/expect the regression's render errors: the repaired shell
  // must render without any framework exception, not just avoid a blank screen.
  expect(tester.takeException(), isNull, reason: '$label must render cleanly');
  final constraints = harness.constraints[label];
  expect(constraints, isNotNull, reason: '$label must be laid out');
  expect(constraints!.hasBoundedWidth, isTrue);
  expect(constraints.hasBoundedHeight, isTrue);
  expect(constraints.maxWidth, greaterThan(0));
  expect(constraints.maxHeight, greaterThan(0));

  final page = find.byKey(ValueKey('page-$label'));
  expect(page, findsOneWidget);
  final size = tester.getSize(page);
  expect(size.width.isFinite && size.height.isFinite, isTrue);
  expect(size.width, greaterThan(0));
  expect(size.height, greaterThan(0));
  expect(find.text('$label content 0').hitTestable(), findsOneWidget);
  expect(find.byKey(HomeNavKeys.pos).hitTestable(), findsOneWidget);
}

Future<void> _exerciseNavigation(
  WidgetTester tester,
  _HomeHarness harness,
) async {
  await tester.tap(find.text('Products').hitTestable());
  await tester.pumpAndSettle();
  expect(harness.router.routeInformationProvider.value.uri.path, '/products');
  _expectFinitePage(tester, harness, 'Products');

  await tester.tap(find.byKey(HomeNavKeys.more));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.tap(find.byKey(HomeNavKeys.moreSheetSettings));
  await tester.pumpAndSettle();
  expect(harness.router.routeInformationProvider.value.uri.path, '/settings');
  _expectFinitePage(tester, harness, 'Settings');

  await tester.tap(find.byKey(HomeNavKeys.pos));
  await tester.pumpAndSettle();
  expect(harness.router.routeInformationProvider.value.uri.path, '/');
  _expectFinitePage(tester, harness, 'POS');
}

class _RouteContent extends StatelessWidget {
  const _RouteContent({required this.label, required this.onLayout});

  final String label;
  final ValueChanged<BoxConstraints> onLayout;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          onLayout(constraints);
          // Real routed screens own a Scaffold and a scrolling viewport. Do not
          // add a fixed height/shrinkWrap here: that would hide the shell bug.
          return Scaffold(
            key: ValueKey('page-$label'),
            body: label == 'POS'
                ? GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                    ),
                    itemCount: 30,
                    itemBuilder: (context, index) =>
                        Center(child: Text('$label content $index')),
                  )
                : ListView.builder(
                    itemCount: 30,
                    itemExtent: 56,
                    itemBuilder: (context, index) =>
                        ListTile(title: Text('$label content $index')),
                  ),
          );
        },
      );
}

class _HomeHarness {
  _HomeHarness(this.router, this.connectivity, this.constraints);

  final GoRouter router;
  final _FakeConnectivityService connectivity;
  final Map<String, BoxConstraints> constraints;
}

// Implements rather than constructs the platform-backed ConnectivityService.
class _FakeConnectivityService extends Fake implements ConnectivityService {
  _FakeConnectivityService(this._status);

  ConnectionStatus _status;
  final _controller = StreamController<ConnectionStatus>.broadcast();

  @override
  ConnectionStatus get currentStatus => _status;

  @override
  Stream<ConnectionStatus> get statusStream => _controller.stream;

  void setStatus(ConnectionStatus status) {
    _status = status;
    _controller.add(status);
  }

  Future<void> close() => _controller.close();
}
