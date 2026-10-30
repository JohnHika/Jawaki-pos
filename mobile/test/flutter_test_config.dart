import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/auth_service.dart';

/// A cloud-workspace auth stub registered for every widget test process.
///
/// Since the local-first commit (a8bef26) roughly sixty screens, widgets, and
/// providers resolve `getIt<AuthService>()` at build time — for the
/// local-workspace flag, entitlement refresh gating, or the current user.
/// Registering one stub here means widget suites don't each have to register
/// their own; a suite can still shadow it with a scoped singleton of its own.
/// Every unstubbed member throws, so a test silently depending on more of the
/// real service fails loudly instead of passing vacuously.
class _CloudWorkspaceAuthStub implements AuthService {
  final _statusController = StreamController<AuthStatus>.broadcast();

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not stubbed in _CloudWorkspaceAuthStub');

  @override
  bool get isAuthenticated => true;
  @override
  bool get isLocked => false;
  @override
  bool get isLocalWorkspace => false;
  @override
  Map<String, dynamic>? get currentUser => {'role': 'ADMIN'};
  @override
  Stream<AuthStatus> get authStatusStream => _statusController.stream;
}

/// Keep widget tests independent from the host platform's shader defaults.
///
/// Flutter's Android Material 3 default uses InkSparkle, which requires the
/// engine's compiled ink_sparkle.frag runtime asset. The headless test engine
/// does not need that visual effect and can reject the shader manifest when
/// the SDK and test engine caches differ, so use the ripple default instead.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  if (!getIt.isRegistered<AuthService>()) {
    getIt.registerSingleton<AuthService>(_CloudWorkspaceAuthStub());
  }
  try {
    await testMain();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
