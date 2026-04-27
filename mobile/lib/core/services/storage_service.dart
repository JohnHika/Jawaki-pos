import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  FlutterSecureStorage? _secureStorage;
  SharedPreferences? _prefs;

  bool _initialized = false;
  
  // Storage keys
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUser = 'user';
  static const String keyDeviceId = 'device_id';
  static const String keyBranchId = 'branch_id';
  static const String keyTenantId = 'tenant_id';
  static const String keyLastSyncAt = 'last_sync_at';
  static const String keyPinHash = 'pin_hash';
  static const String keyFavoriteProducts = 'favorite_products';
  
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
      throw Exception('StorageService not initialized. Call initialize() first.');
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

  Future<void> savePinHash(String hash) async {
    _checkInitialized();
    await _secureStorage!.write(key: keyPinHash, value: hash);
  }

  Future<String?> getPinHash() async {
    _checkInitialized();
    return await _secureStorage!.read(key: keyPinHash);
  }

  Future<void> clearSecureStorage() async {
    _checkInitialized();
    await _secureStorage!.delete(key: keyAccessToken);
    await _secureStorage!.delete(key: keyRefreshToken);
    await _secureStorage!.delete(key: keyPinHash);
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

  Future<void> saveLastSyncAt(DateTime dateTime) async {
    _checkInitialized();
    await _prefs!.setString(keyLastSyncAt, dateTime.toIso8601String());
  }

  DateTime? getLastSyncAt() {
    if (!_initialized || _prefs == null) return null;
    final dateStr = _prefs!.getString(keyLastSyncAt);
    if (dateStr == null) return null;
    return DateTime.parse(dateStr);
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

  // Server mode keys
  static const String keyServerModeEnabled = 'server_mode_enabled';
  static const String keyServerPort = 'server_port';
  static const String keyBackendServerIp = 'backend_server_ip';
  static const String keyBackendServerPort = 'backend_server_port';

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

  // Clear all data
  Future<void> clearAll() async {
    await clearSecureStorage();
    _checkInitialized();
    await _prefs!.clear();
  }

  // Clear session data (keep device registration)
  Future<void> clearSession() async {
    await clearSecureStorage();
    _checkInitialized();
    await _prefs!.remove(keyUser);
    await _prefs!.remove(keyLastSyncAt);
  }
}
