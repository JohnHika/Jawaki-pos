import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';

import '../../support/shot.dart';

/// Window sizes the desktop sign-in screens are designed for: a 1366x768
/// laptop, the same laptop at 125% display scaling, and a full-HD monitor.
const authShotSizes = <String, Size>{
  '1366': Size(1366, 768),
  '1093': Size(1093, 566),
  '1920': Size(1920, 1080),
};

/// A device that has no stored sign-in details unless a test adds them.
class FakeAuthStorage extends StorageService {
  FakeAuthStorage({
    this.local = false,
    this.staff = const [],
    this.rememberedSlug,
    this.rememberedEmail,
    this.pinLength,
  });

  final bool local;
  final List<Map<String, dynamic>> staff;
  final String? rememberedSlug;
  final String? rememberedEmail;
  final int? pinLength;

  @override
  bool hasLocalWorkspace() => local;

  @override
  Map<String, dynamic>? getLocalWorkspace() => local
      ? {
          'tenant': {'name': 'Mama Njeri Mini Mart'},
          'branch': {'name': 'Gikomba stall'},
          'user': {
            'id': 'owner-1',
            'name': 'Njeri Wanjiku',
            'email': 'njeri@example.com',
          },
        }
      : null;

  @override
  List<Map<String, dynamic>> getLocalStaffAccounts() => staff;

  @override
  Future<bool> hasLocalPinSet() async => local;

  @override
  Future<int?> getConfiguredPinLength() async => pinLength;

  @override
  String? getRememberedTenantSlug() => rememberedSlug;

  @override
  String? getRememberedEmail() => rememberedEmail;

  @override
  Map<String, dynamic>? getUser() => null;
}

/// Answers company lookups like the online service would.
class FakeCompanyApi extends ApiClient {
  FakeCompanyApi() : super(Dio());

  @override
  Future<Map<String, dynamic>?> getCompanyInfo(String slug) async =>
      slug == 'evisa-ventures'
          ? {'name': 'Evisa Ventures', 'logoUrl': null, 'isActive': true}
          : null;
}

/// Signed out. Sign-in always fails with a wrong-password answer, so a test can
/// show the error state without a network.
class FakeAuthService implements AuthService {
  final StreamController<AuthStatus> _status =
      StreamController<AuthStatus>.broadcast();
  final logins = <Map<String, String?>>[];
  final pins = <String>[];
  bool pinAccepted = false;
  bool _locked = false;

  FakeAuthService({bool locked = false}) : _locked = locked;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');

  @override
  bool get isAuthenticated => false;
  @override
  bool get isLocked => _locked;
  @override
  bool get isLocalWorkspace => false;
  @override
  Map<String, dynamic>? get currentUser => null;
  @override
  String? get deviceId => 'test-device';
  @override
  Stream<AuthStatus> get authStatusStream => _status.stream;
  @override
  String? get pinThrottleMessage => null;

  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  Future<bool> isDeviceAuthenticationAvailable() async => false;
  @override
  Future<bool> hasLocalPinSet() async => false;

  @override
  Future<void> login({
    required String email,
    required String password,
    String? tenantSlug,
    String? deviceId,
  }) async {
    logins.add({'email': email, 'password': password, 'tenant': tenantSlug});
    throw DioException(
      requestOptions: RequestOptions(path: '/auth/login'),
      response: Response(
        requestOptions: RequestOptions(path: '/auth/login'),
        statusCode: 401,
      ),
    );
  }

  @override
  Future<void> loginWithPin(String pin) async {
    pins.add(pin);
    throw DioException(
      requestOptions: RequestOptions(path: '/auth/pin'),
      response: Response(
        requestOptions: RequestOptions(path: '/auth/pin'),
        statusCode: 401,
      ),
    );
  }

  @override
  Future<bool> unlockWithPin(String pin) async {
    pins.add(pin);
    _locked = !pinAccepted;
    return pinAccepted;
  }

  @override
  Future<void> logout({bool allDevices = false}) async {}
}

class FakeUpdates extends UpdateCheckService {
  @override
  void beginPostLoginCheck() {}
  @override
  void cancelPostLoginCheck() {}
  @override
  Future<void> checkAfterLogin() async {}
}

/// Pumps [home] as the only route in a router that also knows the pages the
/// sign-in screens link to, wrapped in a boundary for [saveShot].
Future<void> pumpAuthPage(
  WidgetTester tester,
  Widget home, {
  required Size size,
  required bool dark,
  required GlobalKey boundary,
  List<GoRoute> extraRoutes = const [],
}) async {
  useWindow(tester, size);
  Widget stub(String name) => Scaffold(body: Center(child: Text(name)));
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => ShotFrame(boundaryKey: boundary, child: home),
      ),
      ...extraRoutes,
      for (final path in const [
        '/login',
        '/pin-login',
        '/company-choice',
        '/company-setup',
        '/accept-invite',
        '/legal/terms',
        '/legal/privacy',
        '/products',
        '/settings',
        '/payments',
      ])
        if (!extraRoutes.any((r) => r.path == path))
          GoRoute(path: path, builder: (_, __) => stub(path)),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

String shotName(String screen, bool dark, String size) =>
    'build/shots/auth-$screen-${dark ? 'dark' : 'light'}-$size.png';
