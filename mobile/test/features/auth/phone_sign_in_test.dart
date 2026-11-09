import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/features/auth/presentation/screens/phone_sign_in_screen.dart';
import 'package:axon_pos/features/settings/presentation/screens/desktop_approvals_screen.dart';

/// Stands in for the online service's computer sign-in endpoints.
class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  String? claimChallenge;
  String status = 'pending';
  Map<String, dynamic> preview = const {};
  final decisions = <Map<String, dynamic>>[];
  final previews = <Map<String, String?>>[];

  @override
  Future<Map<String, dynamic>> startDesktopLink({
    required String desktopName,
    required String platform,
    required String claimChallenge,
  }) async {
    this.claimChallenge = claimChallenge;
    return {
      'linkId': 'link-1',
      'code': '123456',
      'qr': jsonEncode({'v': 2, 'app': 'counterbase', 'id': 'link-1', 'code': '123456'}),
      'expiresAt': DateTime.now().add(const Duration(minutes: 2)).toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> desktopLinkStatus(String linkId) async =>
      {'status': status};

  @override
  Future<Map<String, dynamic>> previewDesktopLink({
    String? payload,
    String? code,
  }) async {
    previews.add({'payload': payload, 'code': code});
    return preview;
  }

  @override
  Future<Map<String, dynamic>> decideDesktopLink({
    required String linkId,
    required bool approve,
    String? pin,
  }) async {
    decisions.add({'linkId': linkId, 'approve': approve, 'pin': pin});
    return {'status': approve ? 'approved' : 'denied'};
  }
}

/// Signed-in phone, or a computer finishing its sign-in.
class _FakeAuth implements AuthService {
  final _status = StreamController<AuthStatus>.broadcast();
  final linked = <Map<String, String>>[];
  bool signedIn;

  _FakeAuth({this.signedIn = true});

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');

  @override
  bool get isAuthenticated => signedIn;
  @override
  bool get isLocked => false;
  @override
  bool get isLocalWorkspace => false;
  @override
  Map<String, dynamic>? get currentUser => signedIn
      ? {
          'firstName': 'Mathais',
          'lastName': 'Owner',
          'role': 'ADMIN',
          'tenant': {'name': 'levisa ventures'},
        }
      : null;
  @override
  Stream<AuthStatus> get authStatusStream => _status.stream;

  @override
  Future<void> loginWithLinkedPhone({
    required String linkId,
    required String verifier,
  }) async {
    linked.add({'linkId': linkId, 'verifier': verifier});
    signedIn = true;
  }
}

void main() {
  late _FakeApi api;

  setUp(() {
    getIt.pushNewScope();
    api = _FakeApi();
    getIt.registerSingleton<ApiClient>(api);
  });
  tearDown(() async => getIt.popScope());

  group('phone: Sign in a computer', () {
    Future<void> pump(WidgetTester tester) async {
      getIt.registerSingleton<AuthService>(_FakeAuth());
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: DesktopApprovalsScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a typed code shows the computer and approves it',
        (tester) async {
      api.preview = {
        'linkId': 'link-1',
        'desktopName': 'FRONT-DESK',
        'platform': 'windows',
        'place': 'Nairobi, KE',
        'sameNetwork': true,
        'pinRequired': false,
      };
      await pump(tester);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(api.previews.single['code'], '123456');
      expect(find.text('FRONT-DESK'), findsOneWidget);
      expect(find.text('Windows · Nairobi, KE'), findsOneWidget);
      expect(find.textContaining('It will open levisa ventures as Mathais Owner'),
          findsOneWidget);
      expect(find.textContaining('same internet connection as this phone.'),
          findsOneWidget);

      await tester.tap(find.text('Sign it in'));
      await tester.pumpAndSettle();

      expect(api.decisions.single, {'linkId': 'link-1', 'approve': true, 'pin': null});
      expect(find.text('Approved'), findsOneWidget);
    });

    testWidgets('a computer on another connection needs the PIN',
        (tester) async {
      api.preview = {
        'linkId': 'link-2',
        'desktopName': 'UNKNOWN-PC',
        'platform': 'windows',
        'place': null,
        'sameNetwork': false,
        'pinRequired': true,
      };
      await pump(tester);

      await tester.enterText(find.byType(TextField), '654321');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.textContaining('not on the same internet connection'), findsOneWidget);

      await tester.tap(find.text('Sign it in'));
      await tester.pumpAndSettle();
      expect(api.decisions, isEmpty);
      expect(find.text('Enter your PIN to approve this computer.'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Your PIN'), '2468');
      await tester.tap(find.text('Sign it in'));
      await tester.pumpAndSettle();
      expect(api.decisions.single['pin'], '2468');
    });

    testWidgets("That's not me refuses the computer", (tester) async {
      api.preview = {
        'linkId': 'link-3',
        'desktopName': 'FRONT-DESK',
        'sameNetwork': true,
        'pinRequired': false,
      };
      await pump(tester);
      await tester.enterText(find.byType(TextField), '111222');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.text("That's not me"));
      await tester.pumpAndSettle();
      expect(api.decisions.single['approve'], false);
      expect(find.text('Refused'), findsOneWidget);
    });
  });

  group('computer: Sign in with your phone', () {
    testWidgets('shows the code and signs in once the phone approves',
        (tester) async {
      final auth = _FakeAuth(signedIn: false);
      getIt.registerSingleton<AuthService>(auth);
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/phone',
        routes: [
          GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
          GoRoute(path: '/phone', builder: (_, __) => const PhoneSignInScreen()),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('123 456'), findsOneWidget);
      expect(find.text('Open your shop on this computer'), findsOneWidget);
      expect(api.claimChallenge, matches(RegExp(r'^[a-f0-9]{64}$')));

      api.status = 'approved';
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump();

      final linked = auth.linked.single;
      expect(linked['linkId'], 'link-1');
      // The verifier stayed here; only its hash was sent when starting.
      expect(sha256.convert(utf8.encode(linked['verifier']!)).toString(),
          api.claimChallenge);
      expect(jsonEncode(api.claimChallenge), isNot(contains(linked['verifier']!)));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
