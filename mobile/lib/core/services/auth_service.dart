import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'storage_service.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';

enum AuthStatus {
  unknown,
  authenticated,
  // A previously-authenticated session that background/foreground auto-lock
  // (or a fresh app launch with "remember me" on) has soft-locked: the
  // stored session is still intact, but the user must pass PIN or biometric
  // before the app trusts it again. Distinct from `unauthenticated`, which
  // means there is no session to unlock at all (never logged in, or fully
  // logged out) — this distinction is what lets the router send returning
  // users to the fast /pin-login screen instead of the full /login form.
  locked,
  unauthenticated,
}

class AuthService {
  final StorageService _storage;
  final ApiClient _apiClient;
  final AppDatabase _database;
  final LocalAuthentication _localAuth = LocalAuthentication();

  final StreamController<AuthStatus> _authStatusController =
      StreamController<AuthStatus>.broadcast();

  AuthStatus _currentStatus = AuthStatus.unknown;
  Map<String, dynamic>? _currentUser;
  String? _accessToken;
  DateTime? _backgroundedAt;

  AuthService({
    required StorageService storage,
    required ApiClient apiClient,
    required AppDatabase database,
  })  : _storage = storage,
        _apiClient = apiClient,
        _database = database {
    // Note: Auth initialization is now done explicitly in main.dart
    // to avoid async operations in constructor which can cause crashes
    _updateStatus(AuthStatus.unknown);
  }

  /// Initialize auth state - call this after AuthService is registered in DI
  Future<void> initialize() async {
    try {
      debugPrint('[AuthService] Initializing auth service...');
      await _initializeAuth();
      debugPrint('[AuthService] Auth service initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('[AuthService] Initialization error: $e');
      debugPrint('[AuthService] Stack trace: $stackTrace');
      // Set to unauthenticated on error - app can still function
      _currentStatus = AuthStatus.unauthenticated;
    }
  }

  Stream<AuthStatus> get authStatusStream => _authStatusController.stream;
  AuthStatus get currentStatus => _currentStatus;
  Map<String, dynamic>? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  bool get isAuthenticated => _currentStatus == AuthStatus.authenticated;
  bool get isLocked => _currentStatus == AuthStatus.locked;

  String? get userId => _currentUser?['id'];
  String? get branchId => _storage.getBranchId();
  String? get deviceId => _storage.getDeviceId();
  String? get tenantId => _storage.getTenantId();
  String? get tenantSlug => _storage.getTenantSlug();
  String? get userRole => _currentUser?['role'];

  String? get activationStatus {
    final tenant = _currentUser?['tenant'];
    if (tenant is Map) return tenant['activationStatus'] as String?;
    return _currentUser?['activationStatus'] as String?;
  }

  bool get requiresTenantActivation => activationStatus == 'PENDING';

  /// Whether this account has a PIN set server-side — refreshed on every
  /// login and token refresh, so it stays current even on a device that
  /// never locally stored a PIN itself (e.g. the account's PIN was set
  /// from a different device). Combined with the local check in
  /// [lockSession], this is what lets a synced-but-not-local PIN still
  /// unlock correctly here instead of the app assuming no PIN exists.
  bool get hasServerPinSet => _currentUser?['hasPinSet'] == true;

  /// VAT/sales tax percentage configured by the business admin. Defaults
  /// to 0 (no tax) when nothing has been set — tax is opt-in, not assumed.
  double get taxRatePercent {
    final tenant = _currentUser?['tenant'];
    if (tenant is! Map) return 0;
    final settings = tenant['settings'];
    if (settings is! Map) return 0;
    final value = settings['taxRatePercent'];
    if (value is num) return value.toDouble();
    return 0;
  }

  /// Whether the tax line should be printed on receipts. Defaults to true
  /// whenever a tax rate is configured, so tax is visible unless an admin
  /// explicitly hides it (e.g. tax-inclusive pricing).
  bool get showTaxOnReceipt {
    final tenant = _currentUser?['tenant'];
    if (tenant is! Map) return true;
    final settings = tenant['settings'];
    if (settings is! Map) return true;
    final value = settings['showTaxOnReceipt'];
    if (value is bool) return value;
    return true;
  }

  Future<void> _initializeAuth() async {
    _accessToken = await _storage.getAccessToken();
    _currentUser = _storage.getUser();

    if (_accessToken?.isNotEmpty == true && _currentUser != null) {
      // "Remember me" was off at the last login: a stored session surviving
      // to a fresh cold start means the app was fully closed and reopened
      // (not just backgrounded — resume-locking is handled separately by
      // lockIfRequiredAfterResume while the process stays alive), so this
      // is exactly the point where an opted-out user should be required to
      // log in again rather than quick-unlock.
      if (!_storage.isRememberLoginEnabled()) {
        await _storage.clearSession();
        _accessToken = null;
        _currentUser = null;
        _updateStatus(AuthStatus.unauthenticated);
        return;
      }

      if (_storage.requireUnlockOnResume() && _storage.isAuthLocked()) {
        _accessToken = null;
        _updateStatus(AuthStatus.locked);
        return;
      }

      _updateStatus(AuthStatus.authenticated);
      // Fire-and-forget: a session restored from local storage on a cold
      // start carries whatever `permissions` (if any) was saved at the
      // last login/refresh — stale if the backend was redeployed with a
      // newer permission set since then. This brings it current without
      // blocking startup on the network call.
      unawaited(refreshPermissions());
      return;
    }

    _updateStatus(AuthStatus.unauthenticated);
  }

  Future<void> login({
    required String email,
    required String password,
    String? tenantSlug,
    String? deviceId,
  }) async {
    final resolvedDeviceId = (deviceId != null && deviceId.isNotEmpty)
        ? deviceId
        : await _storage.ensureDeviceId();

    if (_storage.getDeviceId() != resolvedDeviceId) {
      await _storage.saveDeviceId(resolvedDeviceId);
    }

    final response = await _apiClient.login(
      email: email,
      password: password,
      tenantSlug: tenantSlug,
      deviceId: resolvedDeviceId,
    );

    await _handleAuthResponse(response);
  }

  Future<void> loginWithGoogle({
    required String idToken,
    required String tenantSlug,
    String? deviceId,
  }) async {
    final resolvedDeviceId = (deviceId != null && deviceId.isNotEmpty)
        ? deviceId
        : await _storage.ensureDeviceId();

    if (_storage.getDeviceId() != resolvedDeviceId) {
      await _storage.saveDeviceId(resolvedDeviceId);
    }

    final response = await _apiClient.loginWithGoogle(
      idToken: idToken,
      tenantSlug: tenantSlug,
      deviceId: resolvedDeviceId,
    );

    await _handleAuthResponse(response);
  }

  /// Authenticates with a PIN via the server. Used the first time a device
  /// enters a PIN (before a local PIN has ever been configured on it) — a
  /// real network round-trip against the account's server-side PIN, just
  /// like email/password login.
  Future<void> loginWithPin(String pin) async {
    final resolvedDeviceId = await _storage.ensureDeviceId();

    final response = await _apiClient.loginWithPin(
      pin: pin,
      deviceId: resolvedDeviceId,
      branchId: _storage.getBranchId(),
    );

    await _applyAuthResponse(response);
  }

  /// Logs into a phone-server (offline mode) using the offline-access PIN
  /// a user set up in advance while online — see
  /// ApiClient.loginWithOfflinePin. Only works when the app's base URL is
  /// already pointed at a phone-server (Settings → Backend Server).
  Future<void> loginWithOfflinePin({
    required String email,
    required String pin,
  }) async {
    final response =
        await _apiClient.loginWithOfflinePin(email: email, pin: pin);
    await _applyAuthResponse(response);
  }

  /// Whether this device has a local quick-unlock PIN configured, i.e.
  /// whether [unlockWithPin] can be used instead of the network-dependent
  /// [loginWithPin].
  Future<bool> hasLocalPinSet() => _storage.hasLocalPinSet();

  /// Sets (or replaces) this device's local quick-unlock PIN. Only call
  /// this while already authenticated — it does not itself grant access,
  /// it just configures the fast path for future unlocks.
  Future<void> setLocalPin(String pin) => _storage.setLocalPin(pin);

  /// Verifies a PIN entirely on-device against the already-stored session,
  /// with no network call — the PIN equivalent of [loginWithBiometrics].
  /// This is what actually re-enters an app that's merely locked (session
  /// still present in storage), so it works offline exactly like biometric
  /// unlock does, instead of re-authenticating against the server.
  Future<bool> unlockWithPin(String pin) async {
    final validPin = await _storage.verifyLocalPin(pin);
    if (!validPin) return false;

    _accessToken = await _storage.getAccessToken();
    _currentUser = _storage.getUser();
    if (_currentUser == null || _accessToken == null) return false;

    await _storage.setAuthLocked(false);
    _updateStatus(AuthStatus.authenticated);
    return true;
  }

  Future<void> refreshTokens() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) {
      throw Exception('No refresh token available');
    }

    final response = await _apiClient.refreshToken(refreshToken);

    _accessToken = response['accessToken'];
    await _storage.saveAccessToken(_accessToken!);

    if (response['refreshToken'] != null) {
      await _storage.saveRefreshToken(response['refreshToken']);
    }
  }

  Future<void> logout({bool allDevices = false}) async {
    final refreshToken = allDevices ? null : await _storage.getRefreshToken();

    try {
      await _apiClient.logout(
        refreshToken: refreshToken,
        allDevices: allDevices,
      );
    } catch (_) {
      // Ignore logout API errors
    }

    await _storage.clearSession();

    // A different tenant/org may log in next on this same device. The
    // catalog sync only runs once per app process, so without wiping this
    // here, the next org would keep seeing whatever this org's products
    // happened to be cached locally (or an empty cache from a sync that
    // never succeeded). Deliberately does not touch cart/pending-sales/
    // sync-queue tables, which may hold unsynced offline data.
    try {
      await _database.clearCatalogCache();
    } catch (_) {
      // Non-fatal: the next login's sync will still overwrite stale rows
      // once it succeeds.
    }

    _accessToken = null;
    _currentUser = null;
    _updateStatus(AuthStatus.unauthenticated);
  }

  Future<void> _handleAuthResponse(Map<String, dynamic> response) async {
    await _applyAuthResponse(response);
  }

  Future<void> applyAuthResponse(Map<String, dynamic> response) async {
    await _applyAuthResponse(response);
  }

  /// Re-pulls this user's effective permissions from the backend and
  /// patches them into the stored user map, so a role or override edit an
  /// admin makes elsewhere takes effect without forcing a re-login. Safe
  /// to call opportunistically (e.g. on app resume) — a network failure
  /// here just means permissions stay as they were until the next try.
  Future<void> refreshPermissions() async {
    if (_currentUser == null || !isAuthenticated) return;

    try {
      final permissions = await _apiClient.getMyPermissions();
      _currentUser = {
        ..._currentUser!,
        'permissions': permissions,
      };
      await _storage.saveUser(_currentUser!);
      _authStatusController.add(
        isLocked ? AuthStatus.locked : AuthStatus.authenticated,
      );
    } catch (_) {
      // Fail soft — stale permissions are better than crashing app resume.
    }
  }

  Future<void> updateTenantSession(Map<String, dynamic> tenantData) async {
    if (_currentUser == null) return;

    final currentTenant = _currentUser!['tenant'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(_currentUser!['tenant'])
        : <String, dynamic>{};

    _currentUser = {
      ..._currentUser!,
      'tenant': {
        ...currentTenant,
        ...tenantData,
      },
    };

    await _storage.saveUser(_currentUser!);

    final updatedTenantSlug = tenantData['slug'] as String?;
    if (updatedTenantSlug != null && updatedTenantSlug.isNotEmpty) {
      await _storage.saveTenantSlug(updatedTenantSlug);
    }
  }

  Future<void> _applyAuthResponse(Map<String, dynamic> response) async {
    _accessToken = response['accessToken'];
    Map<String, dynamic> userData = Map<String, dynamic>.from(response['user']);

    // Normalize name from firstName + lastName if name is not present
    if (userData['name'] == null && userData['firstName'] != null) {
      userData['name'] =
          '${userData['firstName']} ${userData['lastName'] ?? ''}'.trim();
    }

    // Extract branch ID from branches array if branchId is not directly present
    if (userData['branchId'] == null &&
        userData['branches'] is List &&
        (userData['branches'] as List).isNotEmpty) {
      final primaryBranch = (userData['branches'] as List).firstWhere(
        (b) => b['isPrimary'] == true,
        orElse: () => (userData['branches'] as List).first,
      );
      userData['branchId'] = primaryBranch['id'];
      if (primaryBranch['name'] != null) {
        userData['branchName'] = primaryBranch['name'];
      }
    }

    _currentUser = userData;

    await _storage.saveAccessToken(_accessToken!);
    await _storage.saveRefreshToken(response['refreshToken']);
    await _storage.saveUser(_currentUser!);
    await _storage.setAuthLocked(false);

    if (_currentUser!['branchId'] != null) {
      await _storage.saveBranchId(_currentUser!['branchId']);
    }
    if (_currentUser!['tenantId'] != null) {
      await _storage.saveTenantId(_currentUser!['tenantId']);
    }
    if (_currentUser!['tenantSlug'] != null) {
      await _storage.saveTenantSlug(_currentUser!['tenantSlug']);
    }

    _updateStatus(AuthStatus.authenticated);
    _registerDeviceIfPossible();
  }

  /// Best-effort device registration — without this, POST /branches/:id/
  /// devices is never called by anything, so the Device table stays empty
  /// forever. That breaks PIN login's branch-by-device lookup on a fresh
  /// device and leaves branch device lists empty in Settings. Runs after
  /// [_updateStatus] so it never delays the login the user is waiting on,
  /// and any failure (offline, or a cashier/seller account that isn't
  /// authorized to register devices) is silently ignored — this is a
  /// nice-to-have side effect of login, not something login should ever
  /// fail over.
  Future<void> _registerDeviceIfPossible() async {
    final deviceId = await _storage.ensureDeviceId();
    final branchId = _currentUser?['branchId'] as String?;
    if (branchId == null) return;

    try {
      await _apiClient.registerDevice(
        branchId: branchId,
        deviceUuid: deviceId,
        name: 'Mobile POS',
      );
    } catch (_) {
      // Offline, or this account isn't ADMIN/MANAGER — fine either way.
    }
  }

  void _updateStatus(AuthStatus status) {
    _currentStatus = status;
    _authStatusController.add(status);
  }

  bool hasRole(String role) {
    return userRole == role;
  }

  bool hasAnyRole(List<String> roles) {
    return roles.contains(userRole);
  }

  void markAppBackgrounded() {
    _backgroundedAt = DateTime.now();
  }

  Future<void> lockIfRequiredAfterResume() async {
    if (!isAuthenticated || !_storage.requireUnlockOnResume()) return;

    final autoLockMinutes = _storage.getAutoLockMinutes();
    if (autoLockMinutes == 0) return;

    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null) return;

    final shouldLock = autoLockMinutes < 0 ||
        DateTime.now().difference(backgroundedAt).inMinutes >= autoLockMinutes;
    if (shouldLock) {
      await lockSession();
    }
  }

  /// Locks the session into the PIN/biometric unlock screen — but only if
  /// the user actually has a way to unlock it. A device with no local PIN,
  /// no biometric enabled, and no server-side PIN on the account has no
  /// working unlock path (PIN screen's fallbacks — local unlock and server
  /// PIN login — would both fail), so locking would strand the user on a
  /// numpad that can never succeed. In that case the session simply stays
  /// authenticated, same as an app with no lock feature configured at all.
  Future<void> lockSession() async {
    if (!isAuthenticated) return;

    final hasUnlockMethod = await _storage.hasLocalPinSet() ||
        _storage.isBiometricEnabled() ||
        hasServerPinSet;
    if (!hasUnlockMethod) return;

    await _storage.setAuthLocked(true);
    _accessToken = null;
    _currentUser = _storage.getUser();
    _updateStatus(AuthStatus.locked);
  }

  // Hierarchical role checks (higher inherits lower)
  bool get isAdmin => userRole == 'admin';
  bool get isStoreManager => hasAnyRole(['admin', 'store_manager', 'manager']);
  bool get isStockKeeper =>
      hasAnyRole(['admin', 'store_manager', 'manager', 'stock_keeper']);
  bool get isSeller => true; // everyone can sell

  // Legacy aliases
  bool get isManager => isStoreManager;
  bool get isCashier => isSeller;

  // Biometric Authentication
  Future<bool> isDeviceAuthenticationAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (e) {
      debugPrint('[AuthService] Device auth availability check failed: $e');
      return false;
    }
  }

  /// Runs a real OS biometric/device-credential prompt to confirm the
  /// device's fingerprint/face actually works, before the "Biometric
  /// Login" setting is turned on. Distinct from [loginWithBiometrics] (used
  /// to unlock a locked session) — this is the one-time enrollment check
  /// invoked from Settings > Security when the toggle is flipped on. A
  /// cancelled or failed prompt means the setting must NOT be enabled.
  Future<bool> confirmBiometricEnrollment() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;

      return await _localAuth.authenticate(
        localizedReason:
            'Confirm your fingerprint or face to enable biometric login',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      debugPrint('[AuthService] Biometric enrollment confirmation failed: $e');
      return false;
    }
  }

  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      debugPrint(
          '[AuthService] Biometric check - canCheck: $canCheck, isSupported: $isSupported');

      if (canCheck && isSupported) {
        final availableBiometrics = await getAvailableBiometrics();
        debugPrint('[AuthService] Available biometrics: $availableBiometrics');
      }

      final storedAccessToken = await _storage.getAccessToken();
      final hasStoredSession = _storage.getUser() != null &&
          (storedAccessToken?.isNotEmpty ?? false);
      return canCheck && isSupported && hasStoredSession;
    } catch (e) {
      debugPrint('[AuthService] Biometric availability check failed: $e');
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  Future<bool> loginWithBiometrics() async {
    try {
      debugPrint('[AuthService] Starting biometric authentication...');

      if (!_storage.isBiometricEnabled()) {
        debugPrint('[AuthService] Biometric login is disabled in settings');
        return false;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Sign in to your POS workspace',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow PIN/pattern fallback
        ),
      );

      debugPrint(
          '[AuthService] Biometric authentication result: $didAuthenticate');

      if (didAuthenticate) {
        // Check if we have a stored user session to restore
        _accessToken = await _storage.getAccessToken();
        _currentUser = _storage.getUser();

        debugPrint(
            '[AuthService] Restored session - accessToken: ${_accessToken != null}, user: ${_currentUser != null}');

        if (_currentUser != null && _accessToken != null) {
          await _storage.setAuthLocked(false);
          _updateStatus(AuthStatus.authenticated);
          debugPrint('[AuthService] Biometric login successful!');
          return true;
        }

        debugPrint(
            '[AuthService] No stored session available for biometric login');
        return false;
      }

      debugPrint('[AuthService] Biometric authentication failed or cancelled');
      return false;
    } catch (e) {
      debugPrint('[AuthService] Biometric authentication error: $e');
      return false;
    }
  }

  void dispose() {
    _authStatusController.close();
  }
}
