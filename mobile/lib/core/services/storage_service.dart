import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  FlutterSecureStorage? _secureStorage;
  SharedPreferences? _prefs;
  static const Uuid _uuid = Uuid();

  bool _initialized = false;

  // Storage keys
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUser = 'user';
  static const String keyDeviceId = 'device_id';
  static const String keyBranchId = 'branch_id';
  static const String keyTenantId = 'tenant_id';
  static const String keyTenantSlug = 'tenant_slug';
  static const String keyLastSyncAt = 'last_sync_at';
  static const String keySyncCursor = 'sync_cursor';
  static const String keyPinHash = 'pin_hash';
  static const String keyPinSalt = 'pin_salt';
  static const String keyFavoriteProducts = 'favorite_products';
  static const String keyRememberLogin = 'remember_login';
  static const String keyRememberedEmail = 'remembered_email';
  static const String keyRememberedTenantSlug = 'remembered_tenant_slug';
  static const String keyBiometricEnabled = 'setting_biometric_enabled';
  static const String keyRequireUnlockOnResume =
      'setting_require_unlock_on_resume';
  static const String keyAutoLockMinutes = 'setting_auto_lock_minutes';
  static const String keyAuthLocked = 'auth_locked';
  static const String keySupplierDataMigrated = 'supplier_data_migrated_v1';
  static const String keyHasSeenStaffTour = 'has_seen_staff_tour';

  Future<void> initialize() async {
    if (_initialized) return;

    _secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
      ),
    );
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  // Secure Storage Methods (for sensitive data)

  void _checkInitialized() {
    if (!_initialized || _secureStorage == null) {
      throw Exception(
          'StorageService not initialized. Call initialize() first.');
    }
  }

  Future<void> saveAccessToken(String token) async {
    _checkInitialized();
    await _secureStorage!.write(key: keyAccessToken, value: token);
  }

  Future<String?> getAccessToken() async {
    _checkInitialized();
    return await _secureStorage!.read(key: keyAccessToken);
  }

  Future<void> saveRefreshToken(String token) async {
    _checkInitialized();
    await _secureStorage!.write(key: keyRefreshToken, value: token);
  }

  Future<String?> getRefreshToken() async {
    _checkInitialized();
    return await _secureStorage!.read(key: keyRefreshToken);
  }

  /// Sets (or replaces) the on-device quick-unlock PIN. Stores a salted
  /// SHA-256 hash, never the raw digits — a PIN only has 10,000 possible
  /// values, so a per-device random salt is what stops the stored value
  /// from being trivially reversed via a precomputed table.
  Future<void> setLocalPin(String pin) async {
    _checkInitialized();
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);
    await _secureStorage!.write(key: keyPinSalt, value: salt);
    await _secureStorage!.write(key: keyPinHash, value: hash);
  }

  Future<bool> hasLocalPinSet() async {
    _checkInitialized();
    final hash = await _secureStorage!.read(key: keyPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Verifies a PIN entirely on-device — no network call, matching how
  /// biometric unlock already works — by re-hashing the input with the
  /// stored salt and comparing against the stored hash.
  Future<bool> verifyLocalPin(String pin) async {
    _checkInitialized();
    final salt = await _secureStorage!.read(key: keyPinSalt);
    final storedHash = await _secureStorage!.read(key: keyPinHash);
    if (salt == null || storedHash == null) return false;
    return _hashPin(pin, salt) == storedHash;
  }

  Future<void> clearLocalPin() async {
    _checkInitialized();
    await _secureStorage!.delete(key: keyPinHash);
    await _secureStorage!.delete(key: keyPinSalt);
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _hashPin(String pin, String salt) {
    final digest = sha256.convert(utf8.encode('$salt:$pin'));
    return digest.toString();
  }

  // Deliberately does not delete keyPinHash/keyPinSalt — this is called
  // from clearSession() (logout keeps the device's local PIN so the same
  // person doesn't have to reconfigure quick-unlock next time they log
  // in). clearAll() removes the PIN explicitly via clearLocalPin().
  Future<void> clearSecureStorage() async {
    _checkInitialized();
    await _secureStorage!.delete(key: keyAccessToken);
    await _secureStorage!.delete(key: keyRefreshToken);
  }

  // Shared Preferences Methods (for non-sensitive data)

  Future<void> saveUser(Map<String, dynamic> user) async {
    _checkInitialized();
    await _prefs!.setString(keyUser, jsonEncode(user));
  }

  Map<String, dynamic>? getUser() {
    if (!_initialized || _prefs == null) return null;
    final userJson = _prefs!.getString(keyUser);
    if (userJson == null) return null;
    return jsonDecode(userJson) as Map<String, dynamic>;
  }

  Future<void> saveDeviceId(String deviceId) async {
    _checkInitialized();
    await _prefs!.setString(keyDeviceId, deviceId);
  }

  String? getDeviceId() {
    if (!_initialized || _prefs == null) return null;
    return _prefs!.getString(keyDeviceId);
  }

  Future<String> ensureDeviceId() async {
    _checkInitialized();

    final existingDeviceId = _prefs!.getString(keyDeviceId);
    if (existingDeviceId != null && existingDeviceId.isNotEmpty) {
      return existingDeviceId;
    }

    final generatedDeviceId = _uuid.v4();
    await _prefs!.setString(keyDeviceId, generatedDeviceId);
    return generatedDeviceId;
  }

  Future<void> saveBranchId(String branchId) async {
    _checkInitialized();
    await _prefs!.setString(keyBranchId, branchId);
  }

  String? getBranchId() {
    if (!_initialized || _prefs == null) return null;
    return _prefs!.getString(keyBranchId);
  }

  Future<void> saveTenantId(String tenantId) async {
    _checkInitialized();
    await _prefs!.setString(keyTenantId, tenantId);
  }

  String? getTenantId() {
    if (!_initialized || _prefs == null) return null;
    return _prefs!.getString(keyTenantId);
  }

  Future<void> saveTenantSlug(String tenantSlug) async {
    _checkInitialized();
    await _prefs!.setString(keyTenantSlug, tenantSlug);
  }

  String? getTenantSlug() {
    if (!_initialized || _prefs == null) return null;
    return _prefs!.getString(keyTenantSlug);
  }

  String _lastSyncKey(String? branchId) => branchId == null || branchId.isEmpty
      ? keyLastSyncAt
      : '${keyLastSyncAt}_$branchId';

  Future<void> saveLastSyncAt(DateTime dateTime, {String? branchId}) async {
    _checkInitialized();
    final value = dateTime.toIso8601String();
    await _prefs!.setString(keyLastSyncAt, value);
    if (branchId != null && branchId.isNotEmpty) {
      await _prefs!.setString(_lastSyncKey(branchId), value);
    }
  }

  DateTime? getLastSyncAt({String? branchId}) {
    if (!_initialized || _prefs == null) return null;
    final dateStr = _prefs!.getString(_lastSyncKey(branchId));
    if (dateStr == null) return null;
    return DateTime.parse(dateStr);
  }

  String _syncCursorKey(String? branchId) =>
      branchId == null || branchId.isEmpty
          ? keySyncCursor
          : '${keySyncCursor}_$branchId';

  Future<void> saveSyncCursor(String cursor, {String? branchId}) async {
    _checkInitialized();
    await _prefs!.setString(_syncCursorKey(branchId), cursor);
  }

  String? getSyncCursor({String? branchId}) {
    if (!_initialized || _prefs == null) return null;
    return _prefs!.getString(_syncCursorKey(branchId));
  }

  Future<void> saveFavoriteProducts(List<String> productIds) async {
    _checkInitialized();
    await _prefs!.setStringList(keyFavoriteProducts, productIds);
  }

  List<String> getFavoriteProducts() {
    if (!_initialized || _prefs == null) return [];
    return _prefs!.getStringList(keyFavoriteProducts) ?? [];
  }

  Future<void> addFavoriteProduct(String productId) async {
    final favorites = getFavoriteProducts();
    if (!favorites.contains(productId)) {
      favorites.add(productId);
      await saveFavoriteProducts(favorites);
    }
  }

  Future<void> removeFavoriteProduct(String productId) async {
    final favorites = getFavoriteProducts();
    favorites.remove(productId);
    await saveFavoriteProducts(favorites);
  }

  bool isFavoriteProduct(String productId) {
    return getFavoriteProducts().contains(productId);
  }

  /// Trusted devices retain their authenticated session by default. Shared
  /// devices can opt out at sign-in or enable an explicit Security lock timer.
  bool isRememberLoginEnabled() {
    return _prefs?.getBool(keyRememberLogin) ?? true;
  }

  String? getRememberedEmail() {
    return _prefs?.getString(keyRememberedEmail);
  }

  String? getRememberedTenantSlug() {
    return _prefs?.getString(keyRememberedTenantSlug);
  }

  Future<void> saveRememberedLogin({
    required bool enabled,
    required String email,
    required String tenantSlug,
  }) async {
    _checkInitialized();
    await _prefs!.setBool(keyRememberLogin, enabled);
    if (enabled) {
      await _prefs!.setString(keyRememberedEmail, email);
      await _prefs!.setString(keyRememberedTenantSlug, tenantSlug);
    } else {
      await _prefs!.remove(keyRememberedEmail);
      await _prefs!.remove(keyRememberedTenantSlug);
    }
  }

  bool isBiometricEnabled() {
    return _prefs?.getBool(keyBiometricEnabled) ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    _checkInitialized();
    await _prefs!.setBool(keyBiometricEnabled, enabled);
  }

  /// New trusted devices stay signed in across normal app switching by
  /// default. Owners can opt into an explicit lock timer in Security.
  bool requireUnlockOnResume() {
    return _prefs?.getBool(keyRequireUnlockOnResume) ?? false;
  }

  Future<void> setRequireUnlockOnResume(bool enabled) async {
    _checkInitialized();
    await _prefs!.setBool(keyRequireUnlockOnResume, enabled);
  }

  // Per-device flag: has this device already shown the first-login staff
  // coach-mark tour? Not user-scoped (same convention as
  // last_seen_update_notice in UpdateCheckService) — a device that's
  // already seen the tour once doesn't need it again for a different user.
  bool hasSeenStaffTour() {
    return _prefs?.getBool(keyHasSeenStaffTour) ?? false;
  }

  Future<void> setHasSeenStaffTour(bool value) async {
    _checkInitialized();
    await _prefs!.setBool(keyHasSeenStaffTour, value);
  }

  int getAutoLockMinutes() {
    return _prefs?.getInt(keyAutoLockMinutes) ?? 0;
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    _checkInitialized();
    await _prefs!.setInt(keyAutoLockMinutes, minutes);
  }

  bool isAuthLocked() {
    return _prefs?.getBool(keyAuthLocked) ?? false;
  }

  Future<void> setAuthLocked(bool locked) async {
    _checkInitialized();
    await _prefs!.setBool(keyAuthLocked, locked);
  }

  /// Whether this device's pre-existing local supplier invoices/payments
  /// (from the old device-local Finance screen) have already been pushed
  /// to the backend. Guards the one-time migration so it only runs once
  /// per device, not on every login.
  bool isSupplierDataMigrated() {
    return _prefs?.getBool(keySupplierDataMigrated) ?? false;
  }

  Future<void> setSupplierDataMigrated(bool migrated) async {
    _checkInitialized();
    await _prefs!.setBool(keySupplierDataMigrated, migrated);
  }

  // Server mode keys
  static const String keyServerModeEnabled = 'server_mode_enabled';
  static const String keyServerPort = 'server_port';
  static const String keyBackendServerIp = 'backend_server_ip';
  static const String keyBackendServerPort = 'backend_server_port';
  static const String keyServerBaseUrl = 'server_base_url';

  bool isServerModeEnabled() {
    return _prefs?.getBool(keyServerModeEnabled) ?? false;
  }

  Future<void> setServerModeEnabled(bool enabled) async {
    _checkInitialized();
    await _prefs!.setBool(keyServerModeEnabled, enabled);
  }

  int getServerPort() {
    return _prefs?.getInt(keyServerPort) ?? 3000;
  }

  Future<void> setServerPort(int port) async {
    _checkInitialized();
    await _prefs!.setInt(keyServerPort, port);
  }

  String? getBackendServerIp() {
    return _prefs?.getString(keyBackendServerIp);
  }

  Future<void> setBackendServerIp(String ip) async {
    _checkInitialized();
    await _prefs!.setString(keyBackendServerIp, ip);
  }

  int getBackendServerPort() {
    return _prefs?.getInt(keyBackendServerPort) ?? 3000;
  }

  Future<void> setBackendServerPort(int port) async {
    _checkInitialized();
    await _prefs!.setInt(keyBackendServerPort, port);
  }

  String? getServerBaseUrl() {
    return _prefs?.getString(keyServerBaseUrl);
  }

  Future<void> setServerBaseUrl(String url) async {
    _checkInitialized();
    final normalized = url.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        url,
        'url',
        'Server address must be a valid http(s) URL without credentials.',
      );
    }
    await _prefs!.setString(keyServerBaseUrl, normalized);
  }

  // Clear all data
  Future<void> clearAll() async {
    await clearSecureStorage();
    await clearLocalPin();
    _checkInitialized();
    await _prefs!.clear();
  }

  // Clear session data (keep device registration)
  Future<void> clearSession() async {
    await clearSecureStorage();
    _checkInitialized();
    await _prefs!.remove(keyUser);
    await _prefs!.remove(keyBranchId);
    await _prefs!.remove(keyTenantId);
    await _prefs!.remove(keyTenantSlug);
    await _prefs!.remove(keyLastSyncAt);
    await _prefs!.remove(keyAuthLocked);
  }
}
