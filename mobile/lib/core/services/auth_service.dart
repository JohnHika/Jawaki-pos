import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:axon_pos/core/di/injection.dart' as di;
import 'company_caches.dart';
import 'storage_service.dart';
import 'lifecycle_lock_controller.dart';
import '../auth/app_roles.dart';
import '../auth/local_staff_roles.dart';
import '../../features/team/data/services/invitation_cache_service.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/local_first_network_guard.dart';

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

class AuthService implements LifecycleLockAuth {
  final StorageService _storage;
  final ApiClient _apiClient;
  final AppDatabase _database;
  final LocalAuthentication _localAuth;

  final StreamController<AuthStatus> _authStatusController =
      StreamController<AuthStatus>.broadcast();

  AuthStatus _currentStatus = AuthStatus.unknown;
  Map<String, dynamic>? _currentUser;
  String? _accessToken;
  DateTime? _lastTenantSettingsRefreshAt;
  bool _creatingLocalWorkspace = false;

  // ── Quick-unlock PIN throttle ──
  // Exponential backoff after consecutive wrong quick-unlock PINs, so a
  // thief holding the phone can't machine-gun the 10k-value PIN space.
  // The counter is mirrored in memory and persisted via StorageService
  // (SharedPreferences) so an app restart can't rewind it; the larger of
  // the two wins when registering the next failure.
  static const int _pinThrottleThreshold = 5;
  static const int _pinThrottleBaseSeconds = 30;
  static const int _pinThrottleMaxSeconds = 15 * 60;
  // 30 << 5 = 960s already exceeds the 15-minute cap, so the shift never
  // needs a wider exponent (and stays well clear of int overflow).
  static const int _pinThrottleMaxExponent = 5;
  int _pinUnlockFailures = 0;

  AuthService({
    required StorageService storage,
    required ApiClient apiClient,
    required AppDatabase database,
    LocalAuthentication? localAuth,
  })  : _storage = storage,
        _apiClient = apiClient,
        _database = database,
        _localAuth = localAuth ?? LocalAuthentication() {
    // Note: Auth initialization is now done explicitly in main.dart
    // to avoid async operations in constructor which can cause crashes
    _updateStatus(AuthStatus.unknown);
  }

  /// Initialize auth state - call this after AuthService is registered in DI
  Future<void> initialize() async {
    try {
      debugPrint('[AuthService] Initializing auth service...');
      await _initializeAuth();
      await _applySharedRegisterBiometricPolicy();
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

  /// Returns the in-memory access token if available, otherwise attempts to
  /// reload it from secure storage. This is the safe getter for the auth
  /// interceptor to use — it handles the edge case where the token was
  /// cleared from memory (e.g. after a lock/unlock cycle) but still exists
  /// in storage.
  Future<String?> getAccessTokenWithFallback() async {
    // Locking clears only the in-memory token so PIN/biometric unlock can
    // restore the session. Never let the interceptor reload that token while
    // the authentication challenge is still active.
    if (!isAuthenticated) return null;
    if (_accessToken?.isNotEmpty == true) return _accessToken;
    final stored = await _storage.getAccessToken();
    if (stored != null && stored.isNotEmpty) {
      _accessToken = stored;
    } else {
      _accessToken = null;
    }
    return _accessToken;
  }

  @override
  bool get isAuthenticated => _currentStatus == AuthStatus.authenticated;
  @override
  bool get isLocked => _currentStatus == AuthStatus.locked;
  bool get isLocalWorkspace => _currentUser?['authMode'] == 'local';
  bool get hasLocalWorkspace => _storage.hasLocalWorkspace();
  bool get isLocalWorkspaceOwner {
    if (!isLocalWorkspace) return false;
    final owner = _storage.getLocalWorkspace()?['user'];
    return owner is Map &&
        owner['id']?.toString() == _currentUser?['id']?.toString();
  }

  List<Map<String, dynamic>> get localStaffAccounts =>
      _storage.getLocalStaffAccounts();
  bool get hasActiveLocalStaff =>
      _storage.hasLocalWorkspace() &&
      localStaffAccounts.any((account) => account['isActive'] != false);

  /// Device biometrics confirm that an enrolled person matched, not which
  /// staff member it was. Shared registers therefore require each person to
  /// use their own PIN instead of unlocking the last-used owner's profile.
  Future<void> _applySharedRegisterBiometricPolicy() async {
    if (!hasActiveLocalStaff) return;
    try {
      await _storage.setBiometricEnabled(false);
    } catch (error) {
      debugPrint(
          '[AuthService] Could not disable shared-register biometrics: $error');
    }
    if (_storage.getPrimaryLoginMethod() == 'biometric') {
      try {
        await _storage.setPrimaryLoginMethod('pin');
      } catch (error) {
        debugPrint(
            '[AuthService] Could not set shared-register PIN as primary: $error');
      }
    }
  }

  bool get isUsingConfiguredLocalServer {
    final serverUrl = _storage.getServerBaseUrl();
    return serverUrl != null &&
        LocalFirstNetworkGuard.isLocalNetworkUrl(serverUrl);
  }

  bool get requiresLocalWorkspaceAdoption =>
      !isLocalWorkspace && !isUsingConfiguredLocalServer;

  String? get userId => _currentUser?['id'];
  String? get branchId => _storage.getBranchId();
  String? get deviceId => _storage.getDeviceId();
  String? get tenantId => _storage.getTenantId();
  String? get tenantSlug => _storage.getTenantSlug();
  String? get userRole => _currentUser?['role'];

  /// Reload the local owner profile after a confirmed full workspace restore.
  /// The receiving device's PIN and other secure credentials remain local.
  Future<void> refreshLocalWorkspaceProfile() async {
    final user = _storage.getUser();
    if (user == null || user['authMode'] != 'local') {
      throw StateError('The restored local owner profile is unavailable.');
    }
    _currentUser = user;
    _accessToken = null;
    await _storage.setAuthLocked(false);
    _updateStatus(AuthStatus.authenticated);
  }

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

    // Upgrade older device-only installs that still remember Email or Google
    // as their primary method. The standalone sign-in screen only supports a
    // local PIN or an explicitly enabled biometric unlock.
    if (_storage.hasLocalWorkspace() &&
        !{'pin', 'biometric'}.contains(_storage.getPrimaryLoginMethod())) {
      try {
        await _storage.setPrimaryLoginMethod('pin');
      } catch (_) {
        // A preference migration must not prevent opening a local workspace.
      }
    }

    final hasLocalSession = _currentUser?['authMode'] == 'local';
    if (_currentUser != null &&
        (hasLocalSession || _accessToken?.isNotEmpty == true)) {
      // "Remember me" was off at the last login: a stored session surviving
      // to a fresh cold start must not restore the account's authenticated
      // state.
      if (!_storage.isRememberLoginEnabled()) {
        await _storage.clearSession();
        _accessToken = null;
        _currentUser = null;
        _updateStatus(AuthStatus.unauthenticated);
        return;
      }

      // A lock already placed before a process death must remain enforced,
      // even if the owner later changes the lock preference. Otherwise a
      // saved session could bypass an outstanding authentication challenge.
      if (_storage.isAuthLocked()) {
        _accessToken = null;
        _updateStatus(AuthStatus.locked);
        return;
      }

      final backgroundedAt = _storage.getAppBackgroundedAt();
      final autoLockMinutes = _storage.getAutoLockMinutes();
      final shouldLockOnColdStart = _storage.requireUnlockOnResume() ||
          (autoLockMinutes > 0 &&
              backgroundedAt != null &&
              DateTime.now().difference(backgroundedAt) >=
                  Duration(minutes: autoLockMinutes));
      // This process has resumed from a prior background period. Consume the
      // timestamp before any navigation; a successful unlock clears it too.
      await _storage.clearAppBackgroundedAt();

      _updateStatus(AuthStatus.authenticated);
      if (shouldLockOnColdStart) {
        await lockSession();
        if (isLocked) return;
      }
      // Fire-and-forget: a session restored from local storage on a cold
      // start carries whatever `permissions` (if any) was saved at the
      // last login/refresh — stale if the backend was redeployed with a
      // newer permission set since then. This brings it current without
      // blocking startup on the network call.
      if (isUsingConfiguredLocalServer) unawaited(refreshPermissions());
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

    final response = await _apiClient
        .login(
          email: email,
          password: password,
          tenantSlug: tenantSlug,
          deviceId: resolvedDeviceId,
        )
        .timeout(const Duration(seconds: 30));

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

    final response = await _apiClient
        .loginWithGoogle(
          idToken: idToken,
          tenantSlug: tenantSlug,
          deviceId: resolvedDeviceId,
        )
        .timeout(const Duration(seconds: 30));

    await _handleAuthResponse(response);
  }

  /// Creates a first-owner session only after Google verifies the identity.
  Future<void> createWorkspaceWithGoogle({
    required String idToken,
    required WorkspaceCreationRequest workspace,
  }) async {
    final response = await _apiClient.createWorkspaceWithGoogle(
      idToken: idToken,
      workspace: workspace,
    );
    await _applyAuthResponse(response);
  }

  /// Sends an ownership code; it intentionally does not change local auth.
  Future<Map<String, dynamic>> requestWorkspaceEmailOtp(String email) =>
      _apiClient.requestWorkspaceEmailOtp(email: email);

  /// Creates a first-owner session only after the server consumes the OTP.
  Future<void> createWorkspaceWithEmailOtp({
    required String email,
    required String challengeId,
    required String code,
    required WorkspaceCreationRequest workspace,
  }) async {
    final response = await _apiClient.createWorkspaceWithEmailOtp(
      email: email,
      challengeId: challengeId,
      code: code,
      workspace: workspace,
    );
    await _applyAuthResponse(response);
  }

  /// Authenticates with a PIN via the server. Used the first time a device
  /// enters a PIN (before a local PIN has ever been configured on it) — a
  /// real network round-trip against the account's server-side PIN, just
  /// like email/password login.
  Future<void> loginWithPin(String pin) async {
    if (_storage.hasLocalWorkspace()) {
      final throttleError = _pinThrottleRemaining();
      if (throttleError != null) {
        throw StateError(throttleError);
      }
      final localUser = await _localWorkspaceUserForPin(pin);
      if (localUser == null) {
        await _registerPinFailure();
        throw StateError(_pinThrottleRemaining() ?? _defaultPinError);
      }
      await _activateLocalWorkspaceUser(localUser);
      await _resetPinThrottle();
      return;
    }

    final resolvedDeviceId = await _storage.ensureDeviceId();

    final response = await _apiClient
        .loginWithPin(
          pin: pin,
          deviceId: resolvedDeviceId,
          branchId: _storage.getBranchId(),
        )
        .timeout(const Duration(seconds: 30));

    await _applyAuthResponse(response);
  }

  Future<Map<String, dynamic>?> _localWorkspaceUserForPin(String pin) async {
    final workspace = _storage.getLocalWorkspace();
    final owner = workspace?['user'];
    if (owner is! Map) return null;
    final ownerUser = Map<String, dynamic>.from(owner);
    if (await _storage.verifyLocalPin(pin)) return ownerUser;

    for (final staff in _storage.getLocalStaffAccounts()) {
      final id = staff['id']?.toString().trim() ?? '';
      final role = staff['role']?.toString() ?? '';
      final permissions = LocalStaffRoles.permissionsFor(role);
      // Fail closed for malformed/stale profile metadata. Local staff
      // permissions are derived from the fixed role template, never trusted
      // from the editable profile JSON. A staff ID must also never alias the
      // owner ID, which is the local owner privilege boundary.
      if (id.isEmpty ||
          id == ownerUser['id']?.toString() ||
          staff['isActive'] != true ||
          permissions == null) {
        continue;
      }
      if (await _storage.verifyLocalStaffPin(id, pin)) {
        return <String, dynamic>{
          ...staff,
          'role': role,
          'permissions': permissions,
          'authMode': 'local',
          'isLocalStaff': true,
        };
      }
    }
    return null;
  }

  Future<void> _activateLocalWorkspaceUser(
    Map<String, dynamic> localUser,
  ) async {
    final tenantId = localUser['tenantId']?.toString().trim() ?? '';
    final tenantSlug = localUser['tenantSlug']?.toString().trim() ?? '';
    final branchId = localUser['branchId']?.toString().trim() ?? '';
    if (localUser['authMode'] != 'local' ||
        tenantId.isEmpty ||
        tenantSlug.isEmpty ||
        branchId.isEmpty) {
      throw StateError(
        'The saved workspace profile is incomplete. Restore a workspace backup before signing in.',
      );
    }
    final workspaceOwner = _storage.getLocalWorkspace()?['user'];
    if (workspaceOwner is Map &&
        workspaceOwner['id']?.toString() != localUser['id']?.toString()) {
      final ownerTenantId = workspaceOwner['tenantId']?.toString().trim() ?? '';
      final ownerTenantSlug =
          workspaceOwner['tenantSlug']?.toString().trim() ?? '';
      if (tenantId != ownerTenantId || tenantSlug != ownerTenantSlug) {
        throw StateError(
          'This staff profile belongs to a different local shop. Ask the owner to update its shop access before signing in.',
        );
      }
      final assignedBranches = localUser['branches'];
      if (assignedBranches is List &&
          assignedBranches.isNotEmpty &&
          !assignedBranches.whereType<Map>().any(
                (branch) => branch['id']?.toString() == branchId,
              )) {
        throw StateError(
          'This staff profile is not assigned to its saved branch. Ask the owner to update its shop access.',
        );
      }
    }

    // Start from a clean session so no cloud token or previous staff identity
    // survives a local sign-in or a switch between people at the till.
    await _storage.clearSession();
    await _storage.saveTenantId(tenantId);
    await _storage.saveTenantSlug(tenantSlug);
    await _storage.saveBranchId(branchId);
    await _storage.setAuthLocked(false);
    await _storage.saveUser(localUser);
    _accessToken = null;
    _currentUser = localUser;
    _updateStatus(AuthStatus.authenticated);
  }

  /// Creates an offline-only staff profile on this installation. Accounts
  /// are deliberately not described as invitations or cloud identities.
  Future<void> createLocalStaffAccount({
    required String name,
    required String role,
    required String pin,
  }) async {
    if (!isLocalWorkspaceOwner) {
      throw StateError('Only the workspace owner can manage local staff.');
    }
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final permissions = LocalStaffRoles.permissionsFor(role);
    if (normalizedName.length < 2 || normalizedName.length > 80) {
      throw StateError('Enter a staff name between 2 and 80 characters.');
    }
    if (permissions == null) throw StateError('Choose a valid staff role.');
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw StateError('Staff PINs must contain 4 to 6 digits.');
    }
    if (await _localPinAlreadyAssigned(pin)) {
      throw StateError('That PIN is already in use. Choose a different PIN.');
    }

    final workspace = _storage.getLocalWorkspace();
    final owner = workspace?['user'];
    final tenant = workspace?['tenant'];
    final branch = workspace?['branch'];
    if (owner is! Map || tenant is! Map || branch is! Map) {
      throw StateError('The saved local workspace profile is incomplete.');
    }
    final id = const Uuid().v4();
    final nameParts = normalizedName.split(' ');
    final branchId = _currentUser?['branchId']?.toString() ?? '';
    final profile = <String, dynamic>{
      'id': id,
      'name': normalizedName,
      'firstName': nameParts.first,
      'lastName': nameParts.skip(1).join(' '),
      'email': null,
      'role': role,
      'permissions': permissions,
      'tenantId': _currentUser?['tenantId'],
      'tenantSlug': _currentUser?['tenantSlug'],
      'tenant': Map<String, dynamic>.from(tenant),
      'branchId': branchId,
      'branchName': branch['name']?.toString() ?? '',
      'branches': [Map<String, dynamic>.from(branch)],
      'hasPinSet': true,
      'authMode': 'local',
      'isLocalStaff': true,
      'isActive': true,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

    await _storage.setLocalStaffPin(id, pin);
    try {
      await _storage.saveLocalStaffAccounts([
        ..._storage.getLocalStaffAccounts(),
        profile,
      ]);
    } catch (_) {
      await _storage.clearLocalStaffPin(id);
      rethrow;
    }
    await _applySharedRegisterBiometricPolicy();
  }

  /// Updates a local staff role, display name, active state, or optional PIN.
  Future<void> updateLocalStaffAccount({
    required String userId,
    required String name,
    required String role,
    required bool isActive,
    String? pin,
  }) async {
    if (!isLocalWorkspaceOwner) {
      throw StateError('Only the workspace owner can manage local staff.');
    }
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final permissions = LocalStaffRoles.permissionsFor(role);
    if (normalizedName.length < 2 || normalizedName.length > 80) {
      throw StateError('Enter a staff name between 2 and 80 characters.');
    }
    if (permissions == null) throw StateError('Choose a valid staff role.');
    final newPin = pin?.trim() ?? '';
    if (newPin.isNotEmpty) {
      if (!RegExp(r'^\d{4,6}$').hasMatch(newPin)) {
        throw StateError('Staff PINs must contain 4 to 6 digits.');
      }
      if (await _localPinAlreadyAssigned(newPin, exceptUserId: userId)) {
        throw StateError('That PIN is already in use. Choose a different PIN.');
      }
    }

    final accounts = _storage.getLocalStaffAccounts().toList();
    final index = accounts.indexWhere((account) => account['id'] == userId);
    if (index < 0) {
      throw StateError('That staff profile is no longer available.');
    }
    final oldPinCredential =
        newPin.isNotEmpty ? await _storage.snapshotLocalStaffPin(userId) : null;
    final old = accounts[index];
    final updated = <String, dynamic>{
      ...old,
      'name': normalizedName,
      'firstName': normalizedName.split(' ').first,
      'lastName': normalizedName.split(' ').skip(1).join(' '),
      'role': role,
      'permissions': permissions,
      'isActive': isActive,
    };
    accounts[index] = updated;
    try {
      if (newPin.isNotEmpty) await _storage.setLocalStaffPin(userId, newPin);
      await _storage.saveLocalStaffAccounts(accounts);
    } catch (_) {
      if (newPin.isNotEmpty) {
        await _storage.restoreLocalStaffPin(userId, oldPinCredential);
      }
      rethrow;
    }
    if (_currentUser?['id']?.toString() == userId) {
      _currentUser = updated;
      await _storage.saveUser(updated);
      _updateStatus(_currentStatus);
    }
    await _applySharedRegisterBiometricPolicy();
  }

  Future<bool> _localPinAlreadyAssigned(
    String pin, {
    String? exceptUserId,
  }) async {
    if (await _storage.verifyLocalPin(pin)) return true;
    for (final account in _storage.getLocalStaffAccounts()) {
      final id = account['id']?.toString() ?? '';
      if (id.isEmpty || id == exceptUserId) continue;
      if (await _storage.verifyLocalStaffPin(id, pin)) return true;
    }
    return false;
  }

  Future<bool> _localStaffPinAlreadyAssigned(
    String pin, {
    String? exceptUserId,
  }) async {
    for (final account in _storage.getLocalStaffAccounts()) {
      final id = account['id']?.toString() ?? '';
      if (id.isEmpty || id == exceptUserId) continue;
      if (await _storage.verifyLocalStaffPin(id, pin)) return true;
    }
    return false;
  }

  /// Creates the first shop directly on this device. No account, API, or
  /// remote identity provider is involved; the owner PIN is stored as a
  /// stretched digest in platform secure storage.
  Future<void> createLocalWorkspace({
    required WorkspaceCreationRequest workspace,
    required String ownerEmail,
    required String ownerPin,
    required bool acceptedLocalDataNotice,
  }) async {
    if (_creatingLocalWorkspace) {
      throw StateError('Workspace setup is already in progress.');
    }
    if (_storage.hasLocalWorkspace()) {
      throw StateError('A local workspace already exists on this device.');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(ownerPin)) {
      throw ArgumentError.value(ownerPin, 'ownerPin', 'Use a six-digit PIN.');
    }
    if (!acceptedLocalDataNotice) {
      throw StateError('Review the local data notice before continuing.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    const uuid = Uuid();
    final tenantId = uuid.v4();
    final ownerId = uuid.v4();
    final branchId = uuid.v4();
    final slug = _localSlug(workspace.companyName);
    final branch = <String, dynamic>{
      'id': branchId,
      'name': workspace.branch.name,
      'code': workspace.branch.code ?? 'MAIN',
      'location': workspace.branch.address ?? '',
      'phone': workspace.branch.phone ?? '',
      'isActive': true,
      'isPrimary': true,
      'createdAt': now,
    };
    final tenant = <String, dynamic>{
      'id': tenantId,
      'name': workspace.companyName.trim(),
      'slug': slug,
      'settings': workspace.settings ?? <String, dynamic>{},
      'isActive': true,
      'activationStatus': 'ACTIVE',
    };
    final user = <String, dynamic>{
      'id': ownerId,
      'email': ownerEmail.trim(),
      'firstName': workspace.firstName.trim(),
      'lastName': workspace.lastName.trim(),
      'name': '${workspace.firstName.trim()} ${workspace.lastName.trim()}',
      'role': 'admin',
      'permissions': const ['*'],
      'tenantId': tenantId,
      'tenantSlug': slug,
      'branchId': branchId,
      'branchName': workspace.branch.name,
      'branches': [branch],
      'tenant': tenant,
      'hasPinSet': true,
      'authMode': 'local',
    };
    final localWorkspace = <String, dynamic>{
      'schemaVersion': 1,
      'createdAt': now,
      'tenant': tenant,
      'branch': branch,
      'user': user,
      'localDataNotice': {
        'version': 'local-data-v1',
        'acceptedAt': now,
      },
    };

    _creatingLocalWorkspace = true;
    LocalPinCredentialSnapshot? previousPin;
    final previousRememberLogin = _storage.isRememberLoginEnabled();
    final previousRememberedEmail = _storage.getRememberedEmail() ?? '';
    final previousRememberedSlug = _storage.getRememberedTenantSlug() ?? '';
    final previousPrimaryLoginMethod = _storage.getPrimaryLoginMethod();
    var branchSeeded = false;
    var setupStorageStarted = false;
    try {
      previousPin = await _storage.snapshotLocalPinCredential();
      setupStorageStarted = true;
      await _storage.clearSession();

      // Seed the local database before publishing a workspace profile. This
      // keeps failed database opens or branch setup from leaving a profile
      // that blocks the owner from retrying setup.
      await _database.transaction(() async {
        await _database.insertBranch(
          branchId,
          workspace.branch.name,
          workspace.branch.address ?? '',
          workspace.branch.phone ?? '',
        );
        await _database.ensureLocalDefaultCategory();
      });
      branchSeeded = true;

      await _storage.setLocalPin(ownerPin);
      // The complete profile is the recovery source for a PIN sign-in. Save
      // it before the session cache so a process interruption can recover the
      // user and branch from this record.
      await _storage.saveLocalWorkspace(localWorkspace);
      await _storage.saveUser(user);
      await _storage.saveTenantId(tenantId);
      await _storage.saveTenantSlug(slug);
      await _storage.saveBranchId(branchId);
      await _storage.saveRememberedLogin(
        enabled: true,
        email: ownerEmail.trim(),
        tenantSlug: slug,
      );
      // A device-only workspace unlocks with its local PIN. Do not leave the
      // first-run screen claiming Email or Google is the primary method.
      await _storage.setPrimaryLoginMethod('pin');
      await _storage.setAuthLocked(false);
      // A new workspace has a new PIN; never inherit throttling from a prior
      // account or a previously configured PIN on this device.
      await _resetPinThrottle();

      _accessToken = null;
      _currentUser = user;
      _updateStatus(AuthStatus.authenticated);
    } catch (_) {
      // SharedPreferences, secure storage, and SQLite cannot share one
      // transaction. Compensate each store so a normal setup failure returns
      // the app to a retryable first-run state.
      if (setupStorageStarted) {
        try {
          await _storage.clearLocalWorkspace();
        } catch (_) {}
        try {
          await _storage.clearSession();
        } catch (_) {}
      }
      if (branchSeeded) {
        try {
          await _database.deleteBranch(branchId);
        } catch (_) {}
      }
      if (setupStorageStarted) {
        try {
          await _storage.saveRememberedLogin(
            enabled: previousRememberLogin,
            email: previousRememberedEmail,
            tenantSlug: previousRememberedSlug,
          );
        } catch (_) {}
        try {
          await _storage.setPrimaryLoginMethod(previousPrimaryLoginMethod);
        } catch (_) {}
        if (previousPin != null) {
          try {
            await _storage.restoreLocalPinCredential(previousPin);
          } catch (_) {}
        }
      }
      rethrow;
    } finally {
      _creatingLocalWorkspace = false;
    }
  }

  /// Converts the currently unlocked online session into a device-only
  /// workspace while keeping its existing tenant and active branch IDs. The
  /// encrypted local database is never cleared, so cached catalog, customers,
  /// and device-recorded sales remain in the same scope. Server credentials
  /// are removed only after the local profile and PIN are ready.
  Future<void> adoptCurrentWorkspaceLocally({
    required String ownerPin,
    required bool acceptedLocalDataNotice,
  }) async {
    if (_creatingLocalWorkspace) {
      throw StateError('Workspace setup is already in progress.');
    }
    if (!isAuthenticated || _currentUser == null || isLocalWorkspace) {
      throw StateError('Sign in to the workspace before continuing.');
    }
    if (_storage.hasLocalWorkspace()) {
      throw StateError('A local workspace already exists on this device.');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(ownerPin)) {
      throw ArgumentError.value(ownerPin, 'ownerPin', 'Use a six-digit PIN.');
    }
    if (!acceptedLocalDataNotice) {
      throw StateError('Review the local data notice before continuing.');
    }

    final sourceUser = Map<String, dynamic>.from(_currentUser!);
    final permissions = sourceUser['permissions'] is List
        ? List<dynamic>.from(sourceUser['permissions'] as List)
        : const <dynamic>[];
    final permissionRole = RolePermissions(permissions).role;
    final accountRole = sourceUser['role']?.toString().trim().toLowerCase();
    if (permissionRole != AppRole.admin && accountRole != 'admin') {
      throw StateError(
        'Ask a workspace administrator to move this device to local mode.',
      );
    }

    final rawTenant = sourceUser['tenant'];
    final tenant = rawTenant is Map
        ? Map<String, dynamic>.from(rawTenant)
        : <String, dynamic>{};
    final tenantId =
        (tenant['id'] ?? sourceUser['tenantId'] ?? _storage.getTenantId())
            ?.toString()
            .trim();
    final tenantName = (tenant['name'] ??
            sourceUser['tenantName'] ??
            sourceUser['companyName'])
        ?.toString()
        .trim();
    if (tenantId == null ||
        tenantId.isEmpty ||
        tenantName == null ||
        tenantName.isEmpty) {
      throw StateError(
        'This workspace is missing its saved business identity. Export its data before setting up a new local workspace.',
      );
    }

    final rawBranches = sourceUser['branches'];
    final branches = rawBranches is List
        ? rawBranches.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    final savedBranchId =
        (_storage.getBranchId() ?? sourceUser['branchId'])?.toString().trim();
    Map<String, dynamic>? branch;
    if (savedBranchId != null && savedBranchId.isNotEmpty) {
      for (final candidate in branches) {
        if (candidate['id']?.toString() == savedBranchId) {
          branch = candidate;
          break;
        }
      }
    } else if (branches.isNotEmpty) {
      branch = branches.firstWhere(
        (candidate) => candidate['isPrimary'] == true,
        orElse: () => branches.first,
      );
    }
    final branchId = savedBranchId?.isNotEmpty == true
        ? savedBranchId
        : branch?['id']?.toString().trim();
    if (branchId == null || branchId.isEmpty) {
      throw StateError(
        'This workspace has no active branch saved on the device. Reopen it while connected and try again.',
      );
    }

    final branchName = (branch?['name'] ?? sourceUser['branchName'])
            ?.toString()
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ') ??
        '';
    final branchRecord = <String, dynamic>{
      if (branch != null) ...branch,
      'id': branchId,
      'name': branchName.isEmpty ? 'Main branch' : branchName,
      'code': branch?['code']?.toString() ?? 'MAIN',
      'location': (branch?['address'] ?? branch?['location'])?.toString() ?? '',
      'phone': branch?['phone']?.toString() ?? '',
      'isActive': true,
      'isPrimary': true,
      'createdAt': branch?['createdAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
    };
    final tenantSlug =
        (tenant['slug'] ?? sourceUser['tenantSlug'] ?? _storage.getTenantSlug())
            ?.toString()
            .trim();
    final slug = tenantSlug == null || tenantSlug.isEmpty
        ? _localSlug(tenantName)
        : tenantSlug;
    final localTenant = <String, dynamic>{
      ...tenant,
      'id': tenantId,
      'name': tenantName,
      'slug': slug,
      'settings': tenant['settings'] is Map
          ? Map<String, dynamic>.from(tenant['settings'] as Map)
          : <String, dynamic>{},
      'isActive': true,
      'activationStatus': 'ACTIVE',
    };
    final localUser = <String, dynamic>{
      ...sourceUser,
      'id': sourceUser['id']?.toString() ?? const Uuid().v4(),
      'tenantId': tenantId,
      'tenantSlug': slug,
      'tenant': localTenant,
      'branchId': branchId,
      'branchName': branchRecord['name'],
      'branches': [branchRecord],
      'permissions': permissions,
      'hasPinSet': true,
      'authMode': 'local',
    };
    for (final key in const [
      'password',
      'passwordHash',
      'pin',
      'offlineAccessPinHash',
      'refreshToken',
      'accessToken',
    ]) {
      localUser.remove(key);
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final localWorkspace = <String, dynamic>{
      'schemaVersion': 1,
      'createdAt': now,
      'tenant': localTenant,
      'branch': branchRecord,
      'user': localUser,
      'localDataNotice': {
        'version': 'local-data-v1',
        'acceptedAt': now,
      },
      'adoptedFromOnlineWorkspace': true,
    };

    final previousPin = await _storage.snapshotLocalPinCredential();
    final previousUser = _storage.getUser();
    final previousTenantId = _storage.getTenantId();
    final previousTenantSlug = _storage.getTenantSlug();
    final previousBranchId = _storage.getBranchId();
    final previousAccessToken = await _storage.getAccessToken();
    final previousRefreshToken = await _storage.getRefreshToken();
    final previousPrimaryLoginMethod = _storage.getPrimaryLoginMethod();
    var sessionStorageStarted = false;

    _creatingLocalWorkspace = true;
    try {
      await _database.transaction(() async {
        await _database.ensureLocalBranch(
          id: branchId,
          name: branchRecord['name'].toString(),
          location: branchRecord['location'].toString(),
          phone: branchRecord['phone'].toString(),
        );
        await _database.ensureLocalDefaultCategory();
      });

      sessionStorageStarted = true;
      await _storage.setLocalPin(ownerPin);
      // Keep an explicitly selected, enabled biometric preference. Legacy
      // Email/Google preferences cannot unlock a standalone local workspace.
      final localPrimaryMethod = previousPrimaryLoginMethod == 'biometric' &&
              _storage.isBiometricEnabled()
          ? 'biometric'
          : 'pin';
      await _storage.setPrimaryLoginMethod(localPrimaryMethod);
      await _storage.clearSession();
      await _storage.saveLocalWorkspace(localWorkspace);
      await _storage.saveUser(localUser);
      await _storage.saveTenantId(tenantId);
      await _storage.saveTenantSlug(slug);
      await _storage.saveBranchId(branchId);
      await _storage.setAuthLocked(false);

      _accessToken = null;
      _currentUser = localUser;
      await _resetPinThrottle();
      _updateStatus(AuthStatus.authenticated);
    } catch (_) {
      if (sessionStorageStarted) {
        try {
          await _storage.clearLocalWorkspace();
          await _storage.clearSession();
          if (previousUser != null) await _storage.saveUser(previousUser);
          if (previousTenantId != null) {
            await _storage.saveTenantId(previousTenantId);
          }
          if (previousTenantSlug != null) {
            await _storage.saveTenantSlug(previousTenantSlug);
          }
          if (previousBranchId != null) {
            await _storage.saveBranchId(previousBranchId);
          }
          if (previousAccessToken != null) {
            await _storage.saveAccessToken(previousAccessToken);
          }
          if (previousRefreshToken != null) {
            await _storage.saveRefreshToken(previousRefreshToken);
          }
          await _storage.setPrimaryLoginMethod(previousPrimaryLoginMethod);
          await _storage.restoreLocalPinCredential(previousPin);
        } catch (_) {
          // Preserve the original migration error; the device database and
          // its cached records are still untouched.
        }
      }
      rethrow;
    } finally {
      _creatingLocalWorkspace = false;
    }
  }

  String _localSlug(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'my-shop' : slug;
  }

  /// Logs into a phone-server (offline mode) using the offline-access PIN
  /// a user set up in advance while online — see
  /// ApiClient.loginWithOfflinePin. Only works when the app's base URL is
  /// already pointed at a phone-server (Settings → Backend Server).
  Future<void> loginWithOfflinePin({
    required String email,
    required String pin,
  }) async {
    final response = await _apiClient
        .loginWithOfflinePin(email: email, pin: pin)
        .timeout(const Duration(seconds: 30));
    await _applyAuthResponse(response);
  }

  /// Whether this device has a local quick-unlock PIN configured, i.e.
  /// whether [unlockWithPin] can be used instead of the network-dependent
  /// [loginWithPin].
  Future<bool> hasLocalPinSet() => _storage.hasLocalPinSet();

  /// Sets (or replaces) this device's local quick-unlock PIN. Only call
  /// this while already authenticated — it does not itself grant access,
  /// it just configures the fast path for future unlocks.
  Future<void> setLocalPin(String pin) async {
    if (isLocalWorkspace) {
      if (!isLocalWorkspaceOwner) {
        throw StateError('Only the workspace owner can change the device PIN.');
      }
      if (await _localStaffPinAlreadyAssigned(pin)) {
        throw StateError(
          'That PIN is already assigned to a staff member. Choose a different PIN.',
        );
      }
    }
    await _storage.setLocalPin(pin);
    await _resetPinThrottle();
  }

  /// Changes the signed-in local staff member's PIN without touching the
  /// workspace owner's device PIN.
  Future<void> setCurrentLocalStaffPin(String pin) async {
    if (!isLocalWorkspace || _currentUser?['isLocalStaff'] != true) {
      throw StateError('A local staff profile is not signed in.');
    }
    final userId = _currentUser?['id']?.toString() ?? '';
    if (userId.isEmpty || !RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw StateError('Enter a valid 4–6 digit PIN.');
    }
    if (await _localPinAlreadyAssigned(pin, exceptUserId: userId)) {
      throw StateError('That PIN is already in use. Choose a different PIN.');
    }
    await _storage.setLocalStaffPin(userId, pin);
    await _resetPinThrottle();
  }

  /// Verifies a PIN entirely on-device against the already-stored session,
  /// with no network call — the PIN equivalent of [loginWithBiometrics].
  /// This is what actually re-enters an app that's merely locked (session
  /// still present in storage), so it works offline exactly like biometric
  /// unlock does, instead of re-authenticating against the server.
  ///
  /// Consecutive failures trigger an exponential-backoff lockout
  /// (persisted, so restarting the app does not reset it): after
  /// [_pinThrottleThreshold] failures each further attempt must wait
  /// 30s doubling per failure, capped at 15 minutes. The counter resets
  /// on success. The bool return type is unchanged for callers; a
  /// throttled-out attempt simply returns false after surfacing the
  /// remaining wait in [AuthState.error] via [pinThrottleMessage].
  Future<bool> unlockWithPin(String pin) async {
    _pinThrottleMessage = null;
    final throttleError = _pinThrottleRemaining();
    if (throttleError != null) {
      _pinThrottleMessage = throttleError;
      return false;
    }

    final localWorkspaceUser = _storage.hasLocalWorkspace()
        ? await _localWorkspaceUserForPin(pin)
        : null;
    final validPin = _storage.hasLocalWorkspace()
        ? localWorkspaceUser != null
        : await _storage.verifyLocalPin(pin);
    if (!validPin) {
      await _registerPinFailure();
      _pinThrottleMessage = _pinThrottleRemaining() ?? _defaultPinError;
      return false;
    }

    if (localWorkspaceUser != null) {
      try {
        await _activateLocalWorkspaceUser(localWorkspaceUser);
      } catch (_) {
        _pinThrottleMessage = 'Could not open this local staff profile.';
        return false;
      }
      await _resetPinThrottle();
      return true;
    }

    _accessToken = await _storage.getAccessToken();
    _currentUser = _storage.getUser();
    if (_currentUser == null ||
        (_accessToken?.isNotEmpty != true && !isLocalWorkspace)) {
      return false;
    }

    await _resetPinThrottle();
    await _storage.setAuthLocked(false);
    _updateStatus(AuthStatus.authenticated);
    return true;
  }

  /// Verifies the current local PIN for a sensitive settings action without
  /// changing the signed-in/locked state. Failed attempts share the same
  /// persistent backoff as the normal unlock screen.
  Future<bool> verifyLocalPinForSensitiveAction(String pin) async {
    _pinThrottleMessage = null;
    final throttleError = _pinThrottleRemaining();
    if (throttleError != null) {
      _pinThrottleMessage = throttleError;
      return false;
    }

    final validPin = isLocalWorkspace
        ? (_currentUser?['isLocalStaff'] == true
            ? await _storage.verifyLocalStaffPin(
                _currentUser?['id']?.toString() ?? '',
                pin,
              )
            : await _storage.verifyLocalPin(pin))
        : await _storage.verifyLocalPin(pin);
    if (!validPin) {
      await _registerPinFailure();
      _pinThrottleMessage = _pinThrottleRemaining() ?? _defaultPinError;
      return false;
    }

    await _resetPinThrottle();
    return true;
  }

  static const String _defaultPinError = 'Incorrect PIN. Try again.';
  String? _pinThrottleMessage;

  /// The throttle/incorrect-PIN message produced by the most recent
  /// [unlockWithPin] attempt (null after a success or when never run).
  /// The PIN screen reads this to show "wait Ns" errors without any
  /// signature change to [unlockWithPin].
  String? get pinThrottleMessage => _pinThrottleMessage;

  /// Returns the active lockout message, or null when attempts are
  /// allowed. Also enforces (and clears) an expired persisted deadline.
  String? _pinThrottleRemaining() {
    final until = _storage.getPinUnlockLockoutUntil();
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    if (remaining.isNegative) {
      // Backoff served; allow the next attempt (counter persists so a
      // further failure escalates from where it left off).
      return null;
    }
    final seconds =
        remaining.inSeconds + (remaining.inMilliseconds > 0 ? 1 : 0);
    final plural = seconds == 1 ? '' : 's';
    return 'Too many incorrect PIN attempts. '
        'Try again in $seconds second$plural.';
  }

  /// Increments the consecutive-failure count (in memory and persisted,
  /// taking the larger of the two so a restart can't rewind it) and, once
  /// the threshold is crossed, schedules the exponential backoff deadline.
  Future<void> _registerPinFailure() async {
    final persisted = _storage.getPinUnlockFailureCount();
    _pinUnlockFailures =
        (_pinUnlockFailures > persisted ? _pinUnlockFailures : persisted) + 1;
    await _storage.setPinUnlockFailureCount(_pinUnlockFailures);

    final overBy = _pinUnlockFailures - _pinThrottleThreshold;
    if (overBy < 0) return; // under threshold: no wait imposed yet

    final exponent =
        overBy > _pinThrottleMaxExponent ? _pinThrottleMaxExponent : overBy;
    final seconds = (_pinThrottleBaseSeconds << exponent).clamp(
      _pinThrottleBaseSeconds,
      _pinThrottleMaxSeconds,
    );
    await _storage.setPinUnlockLockoutUntil(
      DateTime.now().add(Duration(seconds: seconds)),
    );
  }

  /// Clears both the counter and any backoff deadline after a successful
  /// unlock (or a PIN reset) so throttle state never outlives success.
  Future<void> _resetPinThrottle() async {
    _pinUnlockFailures = 0;
    _pinThrottleMessage = null;
    await _storage.setPinUnlockFailureCount(0);
    await _storage.setPinUnlockLockoutUntil(null);
  }

  Future<void> refreshTokens({String? expectedTenantId}) async {
    if (isLocalWorkspace) {
      throw StateError('Local workspaces do not use remote sessions.');
    }
    if (expectedTenantId != null && tenantId != expectedTenantId) {
      throw StateError('The signed-in workspace changed during sync.');
    }
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) {
      throw Exception('No refresh token available');
    }
    if (expectedTenantId != null && tenantId != expectedTenantId) {
      throw StateError('The signed-in workspace changed during sync.');
    }

    final response = await _apiClient
        .refreshToken(refreshToken)
        .timeout(const Duration(seconds: 30));

    // A queued sync can outlive logout or a sign-in to another shop. Never
    // let its late refresh response replace the next workspace's credentials.
    if (expectedTenantId != null && tenantId != expectedTenantId) {
      throw StateError('The signed-in workspace changed during sync.');
    }

    _accessToken = response['accessToken'];
    await _storage.saveAccessToken(_accessToken!);

    if (response['refreshToken'] != null) {
      if (expectedTenantId != null && tenantId != expectedTenantId) {
        throw StateError('The signed-in workspace changed during sync.');
      }
      await _storage.saveRefreshToken(response['refreshToken']);
    }
  }

  Future<void> logout({bool allDevices = false}) async {
    final localWorkspace = isLocalWorkspace;
    final refreshToken =
        allDevices || localWorkspace ? null : await _storage.getRefreshToken();

    if (!localWorkspace) {
      try {
        await _apiClient.logout(
          refreshToken: refreshToken,
          allDevices: allDevices,
        );
      } catch (_) {
        // Ignore logout API errors
      }
    }

    await _storage.clearSession();

    // A different tenant/org may log in next on this same device. The
    // catalog sync only runs once per app process, so without wiping this
    // here, the next org would keep seeing whatever this org's products
    // happened to be cached locally (or an empty cache from a sync that
    // never succeeded). Deliberately does not touch cart/pending-sales/
    // sync-queue tables, which may hold unsynced offline data.
    if (!localWorkspace) {
      try {
        await _database.clearCatalogCache();
      } catch (_) {
        // Non-fatal: the next login's sync will still overwrite stale rows
        // once it succeeds.
      }
    }

    // Till rules and coupons belong to one company too.
    await CompanyCaches.clearAll();

    // Wipe the staff-invitation cache: it holds other people's names and
    // emails in plaintext, and the next login on this device may belong to
    // a different org entirely.
    try {
      await di.getIt<InvitationCacheService>().invalidateAll();
    } catch (_) {
      // Non-fatal: the cache is tenant-keyed too, so a stale entry would
      // never be shown to a different tenant anyway.
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
    if (_currentUser == null ||
        !isAuthenticated ||
        isLocalWorkspace ||
        !isUsingConfiguredLocalServer) {
      return;
    }

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

  /// Refresh shared shop identity and settings when the app returns to the
  /// foreground. This lets layout and terminology changes made on another
  /// device reach the current session without forcing staff to sign in again.
  Future<void> refreshTenantSettings() async {
    if (_currentUser == null ||
        !isAuthenticated ||
        isLocalWorkspace ||
        !isUsingConfiguredLocalServer) {
      return;
    }
    final now = DateTime.now();
    final lastRefresh = _lastTenantSettingsRefreshAt;
    if (lastRefresh != null && now.difference(lastRefresh).inSeconds < 60) {
      return;
    }
    // Set before the request to coalesce rapid resume events. A failed request
    // clears the timestamp so the next resume can retry immediately.
    _lastTenantSettingsRefreshAt = now;

    final rawTenant = _currentUser!['tenant'];
    final currentTenant = rawTenant is Map
        ? Map<String, dynamic>.from(rawTenant)
        : <String, dynamic>{};
    final tenantId =
        (currentTenant['id'] ?? _currentUser!['tenantId'])?.toString();
    if (tenantId == null || tenantId.isEmpty) return;

    try {
      final latestTenant = await _apiClient.getCurrentTenant();
      if (!isAuthenticated || _currentUser == null) return;
      if (latestTenant['id']?.toString() != tenantId) return;

      final settingsChanged = jsonEncode(currentTenant['settings'] ?? {}) !=
          jsonEncode(latestTenant['settings'] ?? {});
      final identityChanged = currentTenant['name'] != latestTenant['name'] ||
          currentTenant['slug'] != latestTenant['slug'] ||
          currentTenant['logo'] != latestTenant['logo'] ||
          currentTenant['logoPublicId'] != latestTenant['logoPublicId'];
      if (!settingsChanged && !identityChanged) return;

      await updateTenantSession({
        for (final key in const [
          'id',
          'name',
          'slug',
          'logo',
          'logoPublicId',
          'settings',
          'isActive',
        ])
          if (latestTenant.containsKey(key)) key: latestTenant[key],
      });
      _authStatusController.add(AuthStatus.authenticated);
    } catch (_) {
      _lastTenantSettingsRefreshAt = null;
      // Keep the last known shop settings when the device is offline.
    }
  }

  Future<void> updateTenantSession(Map<String, dynamic> tenantData) async {
    final previousUser = _currentUser;
    if (previousUser == null) return;

    final currentTenant = previousUser['tenant'] is Map
        ? Map<String, dynamic>.from(previousUser['tenant'] as Map)
        : <String, dynamic>{};
    final updatedTenant = <String, dynamic>{...currentTenant, ...tenantData};
    final updatedUser = <String, dynamic>{
      ...previousUser,
      'tenant': updatedTenant,
    };

    // Local workspaces keep their canonical owner profile inside the local
    // workspace record too. Persist settings there as well, so signing out
    // and back in with the owner PIN does not restore stale business settings.
    if (isLocalWorkspace) {
      final previousWorkspace = _storage.getLocalWorkspace();
      if (previousWorkspace == null) {
        throw StateError('The saved local shop profile is missing.');
      }
      final previousTenantSlug = _storage.getTenantSlug();
      final updatedWorkspace = <String, dynamic>{
        ...previousWorkspace,
        'tenant': updatedTenant,
        'user': updatedUser,
      };
      final updatedTenantSlug = tenantData['slug'] as String?;

      try {
        await _storage.saveLocalWorkspace(updatedWorkspace);
        await _storage.saveUser(updatedUser);
        if (updatedTenantSlug != null && updatedTenantSlug.isNotEmpty) {
          await _storage.saveTenantSlug(updatedTenantSlug);
        }
        _currentUser = updatedUser;
      } catch (_) {
        // Keep the active profile and the PIN-unlock profile in step if one
        // of the local preference writes fails partway through.
        _currentUser = previousUser;
        try {
          await _storage.saveLocalWorkspace(previousWorkspace);
          await _storage.saveUser(previousUser);
          if (updatedTenantSlug != null && updatedTenantSlug.isNotEmpty) {
            if (previousTenantSlug == null || previousTenantSlug.isEmpty) {
              await _storage.clearTenantSlug();
            } else {
              await _storage.saveTenantSlug(previousTenantSlug);
            }
          }
        } catch (_) {
          // Preserve the original save failure for the caller.
        }
        rethrow;
      }
      return;
    }

    _currentUser = updatedUser;
    await _storage.saveUser(updatedUser);

    final updatedTenantSlug = tenantData['slug'] as String?;
    if (updatedTenantSlug != null && updatedTenantSlug.isNotEmpty) {
      await _storage.saveTenantSlug(updatedTenantSlug);
    }
  }

  /// Adds imported branches to an unlocked local owner profile while keeping
  /// the current branch selected. Both copies of the local profile are
  /// updated so the added branches survive a sign-out and PIN unlock.
  Future<void> updateLocalWorkspaceBranches(
    List<Map<String, dynamic>> branches,
  ) async {
    if (!isLocalWorkspace || !isAuthenticated || _currentUser == null) {
      throw StateError('Unlock the local shop before updating its branches.');
    }
    final activeBranchId = _storage.getBranchId()?.trim();
    if (activeBranchId == null ||
        !branches.any((branch) => branch['id']?.toString() == activeBranchId)) {
      throw StateError(
        'The archive does not contain this device’s active shop branch.',
      );
    }

    final normalizedBranches = branches
        .map((branch) => <String, dynamic>{
              ...branch,
              'isPrimary': branch['id']?.toString() == activeBranchId,
            })
        .toList(growable: false);
    final previousUser = Map<String, dynamic>.from(_currentUser!);
    final updatedUser = <String, dynamic>{
      ...previousUser,
      'branches': normalizedBranches,
    };
    final previousWorkspace = _storage.getLocalWorkspace();
    if (previousWorkspace == null) {
      throw StateError('The saved local shop profile is missing.');
    }
    final updatedWorkspace = <String, dynamic>{
      ...previousWorkspace,
      'branches': normalizedBranches,
      'user': updatedUser,
    };
    final availableBranches = {
      for (final branch in normalizedBranches)
        branch['id']?.toString() ?? '': branch,
    }..remove('');
    final previousStaffAccounts = _storage.getLocalStaffAccounts();
    final updatedStaffAccounts = previousStaffAccounts.map((staff) {
      final assignedBranchIds = <String>[];
      final staffBranches = staff['branches'];
      if (staffBranches is List) {
        for (final value in staffBranches.whereType<Map>()) {
          final id = value['id']?.toString() ?? '';
          if (availableBranches.containsKey(id) &&
              !assignedBranchIds.contains(id)) {
            assignedBranchIds.add(id);
          }
        }
      }
      var staffBranchId = staff['branchId']?.toString() ?? '';
      if (!availableBranches.containsKey(staffBranchId)) {
        staffBranchId = assignedBranchIds.isEmpty
            ? activeBranchId
            : assignedBranchIds.first;
      }
      if (assignedBranchIds.isEmpty) assignedBranchIds.add(staffBranchId);
      final scopedBranches = assignedBranchIds
          .map((id) => <String, dynamic>{
                ...availableBranches[id]!,
                'isPrimary': id == staffBranchId,
              })
          .toList(growable: false);
      final tenant = updatedUser['tenant'];
      return <String, dynamic>{
        ...staff,
        'tenantId': updatedUser['tenantId'],
        'tenantSlug': updatedUser['tenantSlug'],
        if (tenant is Map) 'tenant': Map<String, dynamic>.from(tenant),
        'branchId': staffBranchId,
        'branchName': availableBranches[staffBranchId]!['name'],
        'branches': scopedBranches,
      };
    }).toList(growable: false);

    try {
      await _storage.saveLocalWorkspace(updatedWorkspace);
      await _storage.saveUser(updatedUser);
      if (previousStaffAccounts.isNotEmpty) {
        await _storage.saveLocalStaffAccounts(updatedStaffAccounts);
      }
      _currentUser = updatedUser;
    } catch (_) {
      try {
        await _storage.saveLocalWorkspace(previousWorkspace);
        await _storage.saveUser(previousUser);
        if (previousStaffAccounts.isNotEmpty) {
          await _storage.saveLocalStaffAccounts(previousStaffAccounts);
        }
      } catch (_) {
        // Keep the original persistence error for the user.
      }
      rethrow;
    }
  }

  /// Binds a new, empty local workspace to the identity from a trusted shop
  /// archive. The caller must verify the workspace has no business records
  /// before invoking this migration.
  Future<void> adoptLocalArchiveIdentity({
    required String tenantId,
    required String tenantName,
    required String tenantSlug,
    required String activeBranchId,
    required List<Map<String, dynamic>> branches,
  }) async {
    if (!isLocalWorkspace || !isAuthenticated || _currentUser == null) {
      throw StateError('Unlock the local shop before restoring its archive.');
    }
    if (tenantId.trim().isEmpty ||
        tenantName.trim().isEmpty ||
        tenantSlug.trim().isEmpty) {
      throw StateError('The archive shop identity is incomplete.');
    }
    if (!branches.any((branch) => branch['id']?.toString() == activeBranchId)) {
      throw StateError('The archive has no selected branch.');
    }

    final normalizedBranches = branches
        .map((branch) => <String, dynamic>{
              ...branch,
              'isPrimary': branch['id']?.toString() == activeBranchId,
            })
        .toList(growable: false);
    final previousUser = Map<String, dynamic>.from(_currentUser!);
    final previousWorkspace = _storage.getLocalWorkspace();
    if (previousWorkspace == null) {
      throw StateError('The saved local shop profile is missing.');
    }
    final previousStaffAccounts = _storage.getLocalStaffAccounts();
    final previousTenantId = _storage.getTenantId();
    final previousTenantSlug = _storage.getTenantSlug();
    final previousBranchId = _storage.getBranchId();
    final previousTenant = previousUser['tenant'] is Map
        ? Map<String, dynamic>.from(previousUser['tenant'] as Map)
        : <String, dynamic>{};
    final updatedTenant = <String, dynamic>{
      ...previousTenant,
      'id': tenantId,
      'name': tenantName,
      'slug': tenantSlug,
      'isActive': true,
    };
    final activeBranch = normalizedBranches.firstWhere(
      (branch) => branch['id']?.toString() == activeBranchId,
    );
    final updatedUser = <String, dynamic>{
      ...previousUser,
      'tenantId': tenantId,
      'tenantSlug': tenantSlug,
      'tenant': updatedTenant,
      'branchId': activeBranchId,
      'branchName': activeBranch['name'],
      'branches': normalizedBranches,
    };
    final updatedWorkspace = <String, dynamic>{
      ...previousWorkspace,
      'tenant': updatedTenant,
      'branch': activeBranch,
      'branches': normalizedBranches,
      'user': updatedUser,
      'restoredFromArchiveAt': DateTime.now().toUtc().toIso8601String(),
    };
    final updatedStaffAccounts = previousStaffAccounts
        .map((staff) => <String, dynamic>{
              ...staff,
              'tenantId': tenantId,
              'tenantSlug': tenantSlug,
              'tenant': updatedTenant,
              'branchId': activeBranchId,
              'branchName': activeBranch['name'],
              // Existing device-local staff keep their roles and PINs, but
              // must not retain a branch assignment from the previous shop.
              'branches': [Map<String, dynamic>.from(activeBranch)],
            })
        .toList(growable: false);

    try {
      await _storage.saveLocalWorkspace(updatedWorkspace);
      await _storage.saveUser(updatedUser);
      await _storage.saveTenantId(tenantId);
      await _storage.saveTenantSlug(tenantSlug);
      await _storage.saveBranchId(activeBranchId);
      if (previousStaffAccounts.isNotEmpty) {
        await _storage.saveLocalStaffAccounts(updatedStaffAccounts);
      }
      _currentUser = updatedUser;
    } catch (_) {
      try {
        await _storage.saveLocalWorkspace(previousWorkspace);
        await _storage.saveUser(previousUser);
        if (previousStaffAccounts.isNotEmpty) {
          await _storage.saveLocalStaffAccounts(previousStaffAccounts);
        }
        if (previousTenantId != null) {
          await _storage.saveTenantId(previousTenantId);
        }
        if (previousTenantSlug != null) {
          await _storage.saveTenantSlug(previousTenantSlug);
        }
        if (previousBranchId != null) {
          await _storage.saveBranchId(previousBranchId);
        }
      } catch (_) {
        // Preserve the original profile persistence error.
      }
      rethrow;
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
    if (isLocalWorkspace) return;
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

  /// Locks the session into the PIN/biometric unlock screen — but only if
  /// the user actually has a way to unlock it. A device with no local PIN,
  /// no biometric enabled, and no server-side PIN on the account has no
  /// working unlock path (PIN screen's fallbacks — local unlock and server
  /// PIN login — would both fail), so locking would strand the user on a
  /// numpad that can never succeed. In that case the session simply stays
  /// authenticated, same as an app with no lock feature configured at all.
  @override
  Future<void> lockSession() async {
    if (!isAuthenticated) return;

    // The preference can outlive the enrolled fingerprint/face or its saved
    // session. Only count biometrics as an unlock route when the same checks
    // used by the lock screen confirm that this device can restore the
    // current session right now.
    final hasBiometricUnlock =
        _storage.isBiometricEnabled() && await isBiometricAvailable();
    final hasUnlockMethod = await _storage.hasLocalPinSet() ||
        hasBiometricUnlock ||
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
      if (!canCheck || !isSupported) return false;
      return (await _localAuth.getAvailableBiometrics()).isNotEmpty;
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
      if (_storage.hasLocalWorkspace() && hasActiveLocalStaff) return false;
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;
      if ((await _localAuth.getAvailableBiometrics()).isEmpty) return false;

      return await _localAuth.authenticate(
        localizedReason:
            'Confirm your fingerprint or face to enable biometric login',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      debugPrint('[AuthService] Biometric enrollment confirmation failed: $e');
      return false;
    }
  }

  Future<bool> isBiometricAvailable() async {
    try {
      if (_storage.hasLocalWorkspace() && hasActiveLocalStaff) return false;
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      debugPrint(
          '[AuthService] Biometric check - canCheck: $canCheck, isSupported: $isSupported');

      final availableBiometrics = canCheck && isSupported
          ? await getAvailableBiometrics()
          : const <BiometricType>[];
      debugPrint('[AuthService] Available biometrics: $availableBiometrics');

      final storedAccessToken = await _storage.getAccessToken();
      final storedUser = _storage.getUser();
      final hasStoredSession = storedUser != null &&
          ((storedAccessToken?.isNotEmpty ?? false) ||
              storedUser['authMode'] == 'local');
      final localWorkspaceUser = _storage.getLocalWorkspace()?['user'];
      final hasLocalWorkspaceProfile = localWorkspaceUser is Map &&
          localWorkspaceUser['authMode'] == 'local' &&
          (localWorkspaceUser['tenantId']?.toString().trim().isNotEmpty ??
              false) &&
          (localWorkspaceUser['tenantSlug']?.toString().trim().isNotEmpty ??
              false) &&
          (localWorkspaceUser['branchId']?.toString().trim().isNotEmpty ??
              false);
      return canCheck &&
          isSupported &&
          availableBiometrics.isNotEmpty &&
          (hasStoredSession || hasLocalWorkspaceProfile);
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

      // Biometric APIs do not identify which enrolled person authenticated.
      // Never use one to sign a shared local register into its saved owner.
      if (_storage.hasLocalWorkspace() && hasActiveLocalStaff) return false;

      if (!_storage.isBiometricEnabled()) {
        debugPrint('[AuthService] Biometric login is disabled in settings');
        return false;
      }

      if (!await isBiometricAvailable()) {
        debugPrint('[AuthService] No enrolled biometric or saved session');
        return false;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Sign in to your POS workspace',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      debugPrint(
          '[AuthService] Biometric authentication result: $didAuthenticate');

      if (didAuthenticate) {
        // Check if we have a stored user session to restore
        _accessToken = await _storage.getAccessToken();
        _currentUser = _storage.getUser();
        var restoredLocalWorkspaceProfile = false;
        final hasRestorableSession = _currentUser != null &&
            (_currentUser!['authMode'] == 'local' ||
                _accessToken?.isNotEmpty == true);

        // A full local-workspace logout clears the cached session user but
        // intentionally keeps the device-owned workspace profile and PIN.
        // Restore that profile after successful device biometric proof, just
        // as loginWithPin does, instead of showing a biometric button that
        // can never complete sign-in. A stale cloud user with an empty token
        // must not prevent recovery of the saved local workspace either.
        if (!hasRestorableSession && _storage.hasLocalWorkspace()) {
          _currentUser = null;
          _accessToken = null;
          final rawUser = _storage.getLocalWorkspace()?['user'];
          if (rawUser is Map) {
            final localUser = Map<String, dynamic>.from(rawUser);
            final tenantId = localUser['tenantId']?.toString().trim() ?? '';
            final tenantSlug = localUser['tenantSlug']?.toString().trim() ?? '';
            final branchId = localUser['branchId']?.toString().trim() ?? '';
            if (localUser['authMode'] == 'local' &&
                tenantId.isNotEmpty &&
                tenantSlug.isNotEmpty &&
                branchId.isNotEmpty) {
              await _storage.saveTenantId(tenantId);
              await _storage.saveTenantSlug(tenantSlug);
              await _storage.saveBranchId(branchId);
              await _storage.setAuthLocked(false);
              await _resetPinThrottle();
              // Persist the user last: a partial secure-storage recovery must
              // not leave a cached local session that cold-start auth could
              // mistake for a completed biometric sign-in.
              await _storage.saveUser(localUser);
              _currentUser = localUser;
              _accessToken = null;
              restoredLocalWorkspaceProfile = true;
            }
          }
        }

        debugPrint(
            '[AuthService] Restored session - accessToken: ${_accessToken?.isNotEmpty == true}, user: ${_currentUser != null}');

        if (_currentUser != null &&
            (_accessToken?.isNotEmpty == true || isLocalWorkspace)) {
          if (!restoredLocalWorkspaceProfile) {
            await _resetPinThrottle();
            await _storage.setAuthLocked(false);
          }
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

  // ── Tenant onboarding helpers ──

  /// Fetches the current tenant's onboarding progress.
  Future<Map<String, dynamic>> getTenantOnboarding() =>
      _apiClient.getTenantOnboarding();

  /// Marks an onboarding step as completed (or updates its status).
  Future<Map<String, dynamic>> updateTenantOnboardingStep({
    required String key,
    required String status,
  }) =>
      _apiClient.updateTenantOnboardingStep(key: key, status: status);

  /// Sends a staff invitation during onboarding.
  Future<Map<String, dynamic>> createStaffInvitation({
    required String email,
    required String firstName,
    required String lastName,
    required String roleId,
    required String branchId,
  }) =>
      _apiClient.createStaffInvitation(
        email: email,
        firstName: firstName,
        lastName: lastName,
        roleId: roleId,
        branchId: branchId,
      );

  /// Accepts a staff invitation using the challenge/code from the
  /// invitation email.
  Future<Map<String, dynamic>> acceptStaffInvitation({
    required String invitationId,
    required String challengeId,
    required String code,
  }) =>
      _apiClient.acceptStaffInvitation(
        invitationId: invitationId,
        challengeId: challengeId,
        code: code,
      );

  /// Fetches tenant-scoped roles (for the staff invitation form).
  Future<List<dynamic>> getRoles() => _apiClient.getRoles();

  /// Fetches tenant-scoped branches (for the staff invitation form).
  Future<List<dynamic>> getBranches() => _apiClient.getBranches();

  void dispose() {
    _authStatusController.close();
  }
}
