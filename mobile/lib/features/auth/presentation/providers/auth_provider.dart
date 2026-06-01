import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/auth/app_roles.dart';

// Auth state
class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final String? error;
  final Map<String, dynamic>? user;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.error,
    this.user,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    String? error,
    Map<String, dynamic>? user,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      error: error,
      user: user ?? this.user,
    );
  }
}

// Auth controller
class AuthController extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthController(this._authService) : super(const AuthState()) {
    _initAuth();
  }

  void _initAuth() {
    final isAuthenticated = _authService.isAuthenticated;
    state = state.copyWith(
      isAuthenticated: isAuthenticated,
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
        user: _authService.currentUser,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _getErrorMessage(e),
      );
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
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

  Future<bool> isBiometricAvailable() async {
    return _authService.isBiometricAvailable();
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

final userRoleProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?['role'];
});

final appRoleProvider = Provider<AppRole>((ref) {
  final roleStr = ref.watch(userRoleProvider);
  return AppRole.fromString(roleStr);
});

final permissionsProvider = Provider<RolePermissions>((ref) {
  return RolePermissions(ref.watch(appRoleProvider));
});
