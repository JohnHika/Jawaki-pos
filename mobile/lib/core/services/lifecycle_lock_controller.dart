import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Abstract interface for the auth service methods that
/// [LifecycleLockController] depends on. This allows the controller to be
/// tested without platform dependencies (local_auth, secure storage, etc.).
abstract class LifecycleLockAuth {
  bool get isAuthenticated;
  bool get isLocked;
  Future<void> lockSession();
}

/// Abstract interface for the storage service methods that
/// [LifecycleLockController] depends on.
abstract class LifecycleLockStorage {
  bool requireUnlockOnResume();
  int getAutoLockMinutes();
}

/// Controller that listens to [AppLifecycleState] changes and enforces the
/// app's auto-lock and require-unlock-on-resume policies.
///
/// Responsibilities:
/// 1. Records a timestamp when the app backgrounds (paused/detached).
/// 2. On resume, checks if [requireUnlockOnResume] is true (immediate lock)
///    or if [getAutoLockMinutes] > 0 and the elapsed background time exceeds
///    the configured window.
/// 3. If a lock is required, calls [LifecycleLockAuth.lockSession] and
///    navigates to the PIN/biometric unlock screen.
/// 4. On successful unlock, the router's redirect guard returns the user to
///    their previous route automatically (the locked-session redirect in
///    app_router.dart sends locked users to `/pin-login` and lets them back
///    through once [isLocked] becomes false).
///
/// This controller is designed to be testable: the [authService] and
/// [storageService] can be injected as mocks in tests.
class LifecycleLockController extends WidgetsBindingObserver {
  final LifecycleLockAuth authService;
  final LifecycleLockStorage storageService;
  final GlobalKey<NavigatorState>? navigatorKey;

  DateTime? _backgroundedAt;

  LifecycleLockController({
    required this.authService,
    required this.storageService,
    this.navigatorKey,
  });

  /// The timestamp when the app was last backgrounded, or null if it has
  /// never been backgrounded since the controller was created.
  DateTime? get backgroundedAt => _backgroundedAt;

  /// Called by [didChangeAppLifecycleState] when the app transitions to
  /// a background state (paused or detached).
  @visibleForTesting
  void onAppBackgrounded() {
    _backgroundedAt = DateTime.now();
    debugPrint(
      '[LifecycleLock] App backgrounded at $_backgroundedAt',
    );
  }

  /// Called by [didChangeAppLifecycleState] when the app transitions to
  /// the resumed state. Evaluates lock policies and triggers a lock if
  /// the conditions are met.
  @visibleForTesting
  Future<void> onAppResumed() async {
    debugPrint('[LifecycleLock] App resumed');

    // Only enforce locks for authenticated sessions.
    if (!authService.isAuthenticated) {
      debugPrint('[LifecycleLock] Not authenticated — skipping lock check');
      _backgroundedAt = null;
      return;
    }

    final requireUnlock = storageService.requireUnlockOnResume();
    final autoLockMinutes = storageService.getAutoLockMinutes();
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;

    debugPrint(
      '[LifecycleLock] requireUnlockOnResume=$requireUnlock, '
      'autoLockMinutes=$autoLockMinutes, '
      'backgroundedAt=$backgroundedAt',
    );

    // Determine whether a lock is needed.
    final bool shouldLock;

    if (requireUnlock) {
      // Immediate lock on resume — always lock regardless of timer.
      shouldLock = true;
    } else if (autoLockMinutes > 0 && backgroundedAt != null) {
      // Timer-based lock: lock only if the elapsed time exceeds the window.
      final elapsed = DateTime.now().difference(backgroundedAt);
      shouldLock = elapsed.inMinutes >= autoLockMinutes;
    } else {
      shouldLock = false;
    }

    if (!shouldLock) {
      debugPrint('[LifecycleLock] No lock required');
      return;
    }

    debugPrint('[LifecycleLock] Lock required — locking session');
    await authService.lockSession();

    // Navigate to the PIN/biometric unlock screen. The router's redirect
    // guard in app_router.dart will redirect any locked session to
    // `/pin-login`, so we just need to trigger a re-evaluation.
    if (navigatorKey?.currentContext != null) {
      final ctx = navigatorKey!.currentContext!;
      if (!ctx.mounted) return;
      final currentPath = GoRouterState.of(ctx).matchedLocation;
      if (currentPath != '/pin-login') {
        ctx.go('/pin-login');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only `paused`/`detached` mean the user actually left the app.
    // `inactive` also fires for transient system UI (notification shade,
    // app-switcher preview, permission dialogs) and would otherwise trigger
    // an unwanted re-lock moments later on `resumed`.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      onAppBackgrounded();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(onAppResumed());
    }
  }
}
