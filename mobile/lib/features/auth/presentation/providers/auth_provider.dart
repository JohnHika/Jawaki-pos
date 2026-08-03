import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/auth/app_roles.dart';

// Auth state
class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final bool isLocked;
  final String? error;
  final Map<String, dynamic>? user;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.isLocked = false,
    this.error,
    this.user,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    bool? isLocked,
    String? error,
    Map<String, dynamic>? user,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLocked: isLocked ?? this.isLocked,
      error: error,
      user: user ?? this.user,
    );
  }
}

// Auth controller
class AuthController extends StateNotifier<AuthState> {
  final AuthService _authService;
  StreamSubscription<AuthStatus>? _authStatusSubscription;

  AuthController(this._authService) : super(const AuthState()) {
    _initAuth();
    _authStatusSubscription =
        _authService.authStatusStream.listen((_) => refreshFromService());
  }

  @override
  void dispose() {
    _authStatusSubscription?.cancel();
    super.dispose();
  }

  void _initAuth() => refreshFromService();

  /// Re-reads the current user/tenant snapshot from [AuthService] into
  /// provider state. Called automatically on auth status changes (login,
  /// logout, lock/unlock) — but AuthService.updateTenantSession() mutates
  /// the session in place without emitting one of those events, so any
  /// caller that updates tenant data (e.g. logo, name) directly must call
  /// this afterward, or dependents like tenantIdentityProvider stay stale
  /// until the next login.
  void refreshFromService() {
    state = state.copyWith(
      isAuthenticated: _authService.isAuthenticated,
      isLocked: _authService.isLocked,
      user: _authService.currentUser,
    );
  }

  Future<bool> login({
    required String email,
    required String password,
    String? tenantSlug,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _authService.login(
        email: email,
        password: password,
        tenantSlug: tenantSlug,
      );
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        user: _authService.currentUser,
      );
      _registerPushTokenIfPermitted();
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      );
      return false;
    }
  }

  Future<bool> loginWithGoogle({
    required String idToken,
    required String tenantSlug,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _authService.loginWithGoogle(
        idToken: idToken,
        tenantSlug: tenantSlug,
      );
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        user: _authService.currentUser,
      );
      _registerPushTokenIfPermitted();
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      );
      return false;
    }
  }

  Future<bool> loginWithPin(String pin) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _authService.loginWithPin(pin);
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        isLocked: false,
        user: _authService.currentUser,
      );
      _registerPushTokenIfPermitted();
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      );
      return false;
    }
  }

  /// Logs into a phone-server (offline mode) as a user who set up an
  /// offline-access PIN in advance while online. Only meaningful when
  /// this device's base URL is already pointed at a phone-server.
  Future<bool> loginWithOfflinePin({
    required String email,
    required String pin,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _authService.loginWithOfflinePin(email: email, pin: pin);
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        user: _authService.currentUser,
      );
      _registerPushTokenIfPermitted();
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      );
      return false;
    }
  }

  Future<bool> hasLocalPinSet() => _authService.hasLocalPinSet();

  Future<void> setLocalPin(String pin) => _authService.setLocalPin(pin);

  /// Local, offline PIN unlock for an already-locked session — tries this
  /// first from the PIN screen; only falls back to the network-dependent
  /// [loginWithPin] if this device has no local PIN configured yet.
  Future<bool> unlockWithPin(String pin) async {
    state = state.copyWith(isLoading: true, error: null);

    final unlocked = await _authService.unlockWithPin(pin);
    if (unlocked) {
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        isLocked: false,
        user: _authService.currentUser,
      );
      _registerPushTokenIfPermitted();
      return true;
    }

    state = state.copyWith(
      isLoading: false,
      error: 'Incorrect PIN. Try again.',
    );
    return false;
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      await getIt<NotificationService>().unregisterToken();
    } catch (_) {
      // Non-fatal — a stale token just goes unused until it expires.
    }
    await _authService.logout();
    state = const AuthState();
  }

  Future<bool> loginWithBiometrics() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _authService.loginWithBiometrics();
      if (result) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: _authService.currentUser,
        );
        _registerPushTokenIfPermitted();
        return true;
      }
      state = state.copyWith(
        isLoading: false,
        error: 'Biometric authentication failed',
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      );
      return false;
    }
  }

  /// Re-associates this device's push token with whichever user just
  /// authenticated, if notification permission was already granted in a
  /// previous session — fire-and-forget so a slow/failed network call
  /// never delays showing the authenticated UI.
  void _registerPushTokenIfPermitted() {
    unawaited(() async {
      try {
        final notifications = getIt<NotificationService>();
        if (await notifications.hasPermission()) {
          await notifications.registerToken();
        }
      } catch (_) {
        // Non-fatal — next cold start or explicit toggle will retry.
      }
    }());
  }

  Future<bool> isBiometricAvailable() async {
    return _authService.isBiometricAvailable();
  }

  Future<bool> isDeviceAuthenticationAvailable() async {
    return _authService.isDeviceAuthenticationAvailable();
  }

  String _getErrorMessage(dynamic error) {
    final msg = error.toString();
    if (msg.contains('401') || msg.contains('Invalid credentials')) {
      return 'Invalid email or password';
    }
    if (msg.contains('network') ||
        msg.contains('Connection refused') ||
        msg.contains('SocketException')) {
      return 'Cloud POS is not reachable. Check your internet connection and try again.';
    }
    if (msg.contains('403') || msg.contains('deactivated')) {
      return 'Account deactivated. Contact administrator.';
    }
    // Show the actual error when debugging
    if (msg.contains('400') || msg.contains('Bad Request')) {
      return 'Cloud POS error. Please try again in a moment.';
    }
    debugPrint('[AuthError] $error');
    return msg.length > 80
        ? 'Login failed. Check your internet connection and try again.'
        : msg;
  }
}

// Providers
final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(getIt<AuthService>());
});

final currentUserProvider = Provider<Map<String, dynamic>?>((ref) {
  return ref.watch(authControllerProvider).user;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authControllerProvider).isAuthenticated;
});

final isLockedProvider = Provider<bool>((ref) {
  return ref.watch(authControllerProvider).isLocked;
});

final userRoleProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?['role'];
});

/// Effective permission keys from the backend's login response — the real
/// source of truth. Falls back to an empty set (no access) if absent
/// rather than guessing, since an empty/missing list from a logged-in
/// session would itself indicate something is wrong upstream.
final userPermissionsProvider = Provider<List<dynamic>>((ref) {
  return ref.watch(currentUserProvider)?['permissions'] as List<dynamic>? ??
      const [];
});

final permissionsProvider = Provider<RolePermissions>((ref) {
  return RolePermissions(ref.watch(userPermissionsProvider));
});

/// Display-only role chip derived from the permission set — never used
/// for gating, see RolePermissions/AppRole docs in app_roles.dart.
final appRoleProvider = Provider<AppRole>((ref) {
  return ref.watch(permissionsProvider).role;
});
