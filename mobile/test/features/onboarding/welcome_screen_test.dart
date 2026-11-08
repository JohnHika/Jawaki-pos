import 'dart:async';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/providers/tenant_provider.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
  }

  Future<void> showWelcome(
    WidgetTester tester, {
    required bool owner,
    required List<String> permissions,
  }) async {
    getIt.pushNewScope();
    addTearDown(getIt.popScope);
    getIt.registerSingleton<AuthService>(_LocalShopAuth(owner: owner));
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/welcome'),
              child: const Text('home'),
            ),
          ),
        ),
        GoRoute(
          path: '/welcome',
          builder: (context, state) => const WelcomeScreen(),
        ),
        GoRoute(
          path: '/setup',
          builder: (context, state) =>
              const Scaffold(body: Text('setup checklist')),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tenantIdentityProvider.overrideWithValue(const TenantIdentity(
          companyName: 'Levisa Ventures',
          logoUrl: null,
          userFirstName: 'Mathias',
          userFullName: 'Mathias',
          branchName: 'Main store',
          role: 'Owner',
        )),
        permissionsProvider.overrideWithValue(RolePermissions(permissions)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('home'));
    await tester.pumpAndSettle();
  }

  testWidgets('the owner reads the tour and goes on to set up the shop',
      (tester) async {
    phoneSize(tester);
    await showWelcome(tester, owner: true, permissions: const [
      'sales.create',
      'customers.view',
      'inventory.stock.view',
      'finance.view',
    ]);

    expect(find.text('Karibu, Mathias'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Your records stay yours'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    expect(find.text('I will set up later'), findsOneWidget);

    await tester.tap(find.text('Set up my shop'));
    await tester.pumpAndSettle();

    expect(find.text('setup checklist'), findsOneWidget);
  });

  testWidgets('a cashier can skip the tour and go back to work',
      (tester) async {
    phoneSize(tester);
    await showWelcome(tester,
        owner: false, permissions: const ['sales.create']);

    expect(find.text('Karibu, Mathias'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a cashier finishes the tour on their PIN page',
      (tester) async {
    phoneSize(tester);
    await showWelcome(tester,
        owner: false, permissions: const ['sales.create']);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Your PIN, your sales'), findsOneWidget);
    expect(find.text('I will set up later'), findsNothing);
    await tester.tap(find.text('Start working'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });
}

class _LocalShopAuth implements AuthService {
  _LocalShopAuth({required this.owner});

  final bool owner;
  final _statusController = StreamController<AuthStatus>.broadcast();

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not stubbed in _LocalShopAuth');

  @override
  bool get isAuthenticated => true;
  @override
  bool get isLocked => false;
  @override
  bool get isLocalWorkspace => true;
  @override
  bool get isLocalWorkspaceOwner => owner;
  @override
  Map<String, dynamic>? get currentUser =>
      {'id': owner ? 'owner-1' : 'cashier-1', 'authMode': 'local'};
  @override
  Stream<AuthStatus> get authStatusStream => _statusController.stream;
}
