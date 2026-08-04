import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/features/team/presentation/screens/accept_invite_screen.dart';

/// Minimal StorageService stub that overrides all async init methods.
class _StubStorageService extends StorageService {
  _StubStorageService() : super();

  @override
  Future<void> initialize() async {}

  @override
  Future<String> ensureDeviceId() async => 'test-device';

  @override
  String? getDeviceId() => 'test-device';
}

/// Minimal ApiClient stub.
class _StubApiClient extends ApiClient {
  _StubApiClient() : super(Dio());
}

/// A manual AuthService spy that records calls and returns canned data.
/// Uses stubs for its dependencies so it can be constructed in tests.
class _SpyAuthService extends AuthService {
  _SpyAuthService()
      : super(
          storage: _StubStorageService(),
          apiClient: _StubApiClient(),
          database: _StubAppDatabase(),
        );

  Object? acceptError;
  Map<String, dynamic>? lastAcceptCall;

  @override
  Future<Map<String, dynamic>> acceptStaffInvitation({
    required String invitationId,
    required String challengeId,
    required String code,
  }) async {
    if (acceptError != null) throw acceptError!;
    lastAcceptCall = {
      'invitationId': invitationId,
      'challengeId': challengeId,
      'code': code,
    };
    return {'accepted': true};
  }
}

/// Stub AppDatabase that doesn't open a real connection.
/// Must extend AppDatabase to satisfy the type constraint in AuthService.
class _StubAppDatabase extends AppDatabase {
  _StubAppDatabase() : super(_StubStorageService());
}

void main() {
  late _SpyAuthService spyAuth;

  setUp(() {
    spyAuth = _SpyAuthService();
    final getIt = GetIt.instance;
    if (getIt.isRegistered<AuthService>()) {
      getIt.unregister<AuthService>();
    }
    getIt.registerSingleton<AuthService>(spyAuth);
  });

  GoRouter router() => GoRouter(
        initialLocation: '/accept-invite',
        routes: [
          GoRoute(
            path: '/accept-invite',
            builder: (context, state) => const AcceptInviteScreen(
              invitationId: 'inv-123',
              challengeId: 'challenge-456',
            ),
          ),
          GoRoute(
            path: '/set-password-after-invite',
            builder: (context, state) => const Scaffold(
              body: Text('Set Password After Invite'),
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(
              body: Text('Login'),
            ),
          ),
        ],
      );

  group('AcceptInviteScreen', () {
    testWidgets('renders the form with header and code field',
        (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      expect(find.text('Enter your invitation code'), findsOneWidget);
      expect(find.text('Accept invitation'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('shows validation error on empty submit', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please enter the code from your email'),
        findsOneWidget,
      );
    });

    testWidgets('shows validation error for short code', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '12');
      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();

      expect(
        find.text('The code must be at least 4 characters'),
        findsOneWidget,
      );
    });

    testWidgets('calls acceptStaffInvitation on valid submit',
        (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();

      expect(spyAuth.lastAcceptCall, isNotNull);
      expect(spyAuth.lastAcceptCall!['invitationId'], 'inv-123');
      expect(spyAuth.lastAcceptCall!['challengeId'], 'challenge-456');
      expect(spyAuth.lastAcceptCall!['code'], '123456');
    });

    testWidgets('navigates to set-password screen on success',
        (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();

      expect(find.text('Set Password After Invite'), findsOneWidget);
    });

    testWidgets('shows error snackbar on API failure', (tester) async {
      spyAuth.acceptError = Exception('API error');

      await tester.pumpWidget(MaterialApp.router(routerConfig: router()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The invitation code could not be verified. Please check and try again.',
        ),
        findsOneWidget,
      );
    });
  });
}
