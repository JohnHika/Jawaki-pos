import 'dart:async';

import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/providers/local_workspace_capabilities.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/features/auth/presentation/screens/local_workspace_transition_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

class _AdoptingAuthFake implements AuthService {
  final StreamController<AuthStatus> _status =
      StreamController<AuthStatus>.broadcast();

  Map<String, dynamic> user = {
    'id': 'user-1',
    'role': 'ADMIN',
    'permissions': ['*'],
    'branchName': 'Main branch',
    'tenant': {
      'id': 'tenant-1',
      'name': 'Kileleshwa Fresh Mart',
      'slug': 'kileleshwa-fresh-mart',
    },
    'branches': [
      {'id': 'branch-1', 'name': 'Main branch', 'isPrimary': true}
    ],
  };
  int adoptCalls = 0;
  String? adoptedPin;
  bool adoptAccepted = false;
  Object? adoptError;

  @override
  bool get isAuthenticated => true;
  @override
  bool get isLocked => false;
  @override
  bool get isLocalWorkspace => adoptCalls > 0;
  @override
  Map<String, dynamic>? get currentUser => user;

  @override
  Future<void> adoptCurrentWorkspaceLocally({
    required String ownerPin,
    required bool acceptedLocalDataNotice,
  }) async {
    adoptCalls += 1;
    adoptedPin = ownerPin;
    adoptAccepted = acceptedLocalDataNotice;
    final error = adoptError;
    if (error != null) throw error;
    _status.add(AuthStatus.authenticated);
  }

  @override
  Stream<AuthStatus> get authStatusStream => _status.stream;

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not stubbed in _AdoptingAuthFake');
}

GoRouter _router() => GoRouter(
      initialLocation: '/workspace/localize',
      routes: [
        GoRoute(
          path: '/workspace/localize',
          builder: (context, state) => const LocalWorkspaceTransitionScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const Scaffold(
            body: Text('Dashboard home'),
          ),
        ),
      ],
    );

void main() {
  late _AdoptingAuthFake auth;

  setUp(() {
    auth = _AdoptingAuthFake();
    final getIt = GetIt.instance;
    if (getIt.isRegistered<AuthService>()) getIt.unregister<AuthService>();
    getIt.registerSingleton<AuthService>(auth);
  });

  tearDown(() {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<AuthService>()) getIt.unregister<AuthService>();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // The migration page is a full-screen form; give the test a tall phone
    // surface so every section is on-screen without scrolling.
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: _router())),
    );
    await tester.pumpAndSettle();
  }

  group('LocalWorkspaceTransitionScreen', () {
    testWidgets('shows a friendly headline with the shop name, not jargon',
        (tester) async {
      await pumpScreen(tester);

      expect(
        find.text('Counterbase now runs right here on your phone'),
        findsOneWidget,
      );
      expect(find.textContaining('Kileleshwa Fresh Mart'), findsWidgets);
      expect(find.text('The online POS has closed'), findsNothing);
      expect(find.textContaining('online POS service'), findsNothing);
    });

    testWidgets('explains data stays on the device and offline works',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('Everything you have is still here'), findsOneWidget);
      expect(find.text('Works fully offline'), findsOneWidget);
      expect(find.text('Start using my shop'), findsOneWidget);
    });

    testWidgets('PIN mismatch shows a clear error and does not adopt',
        (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'New six-digit PIN'), '123456');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm your PIN'), '654321');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Start using my shop'));
      await tester.pump();

      expect(find.text('The PINs do not match.'), findsOneWidget);
      expect(auth.adoptCalls, 0);
    });

    testWidgets('the notice must be ticked before adopting', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'New six-digit PIN'), '123456');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm your PIN'), '123456');
      await tester.tap(find.text('Start using my shop'));
      await tester.pump();

      expect(
        find.textContaining('confirm you have read the note'),
        findsOneWidget,
      );
      expect(auth.adoptCalls, 0);
    });

    testWidgets('a valid PIN and notice adopts and lands on the shop home',
        (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'New six-digit PIN'), '123456');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm your PIN'), '123456');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Start using my shop'));
      await tester.pumpAndSettle();

      expect(auth.adoptCalls, 1);
      expect(auth.adoptedPin, '123456');
      expect(auth.adoptAccepted, isTrue);
      expect(find.text('Dashboard home'), findsOneWidget);
    });

    testWidgets('an adoption failure shows a calm error and stays retryable',
        (tester) async {
      auth.adoptError =
          StateError('This workspace is missing its saved business identity.');
      await pumpScreen(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'New six-digit PIN'), '123456');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm your PIN'), '123456');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Start using my shop'));
      await tester.pump();

      expect(
        find.text('This workspace is missing its saved business identity.'),
        findsOneWidget,
      );

      // The user can fix the cause and try again.
      auth.adoptError = null;
      await tester.tap(find.text('Start using my shop'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard home'), findsOneWidget);
    });

    testWidgets('non-admin sees a clear "owner does this step" message',
        (tester) async {
      auth.user = {
        ...auth.user,
        'role': 'CASHIER',
        'permissions': ['sales.create'],
      };
      await pumpScreen(tester);

      expect(find.text('The shop owner does this step'), findsOneWidget);
      expect(find.text('New six-digit PIN'), findsNothing);
    });
  });

  test('homePathFor resolves the dashboard for a full-permission admin', () {
    final permissions = RolePermissions(['*']);
    final layout = businessLayoutFromUser(const {
      'role': 'ADMIN',
      'permissions': ['*'],
    });
    expect(
      LocalWorkspaceCapabilities.homePathFor(permissions, layout),
      '/dashboard',
    );
  });
}
