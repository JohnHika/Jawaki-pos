import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  late final FlutterSecureStorage _secureStorage;
  late final SharedPreferences _prefs;
  
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
    _secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
      ),
    );
    _prefs = await SharedPreferences.getInstance();
  }
  
  // Secure Storage Methods (for sensitive data)
  
  Future<void> saveAccessToken(String token) async {
    await _secureStorage.write(key: keyAccessToken, value: token);
  }
  
  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: keyAccessToken);
  }
  
  Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: keyRefreshToken, value: token);
  }
  
  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: keyRefreshToken);
  }
  
  Future<void> savePinHash(String hash) async {
    await _secureStorage.write(key: keyPinHash, value: hash);
  }
  
  Future<String?> getPinHash() async {
    return await _secureStorage.read(key: keyPinHash);
  }
  
  Future<void> clearSecureStorage() async {
    await _secureStorage.delete(key: keyAccessToken);
    await _secureStorage.delete(key: keyRefreshToken);
    await _secureStorage.delete(key: keyPinHash);
  }
  
  // Shared Preferences Methods (for non-sensitive data)
  
  Future<void> saveUser(Map<String, dynamic> user) async {
    await _prefs.setString(keyUser, jsonEncode(user));
  }
  
  Map<String, dynamic>? getUser() {
    final userJson = _prefs.getString(keyUser);
    if (userJson == null) return null;
    return jsonDecode(userJson) as Map<String, dynamic>;
  }
  
  Future<void> saveDeviceId(String deviceId) async {
    await _prefs.setString(keyDeviceId, deviceId);
  }
  
  String? getDeviceId() {
    return _prefs.getString(keyDeviceId);
  }
  
  Future<void> saveBranchId(String branchId) async {
    await _prefs.setString(keyBranchId, branchId);
  }
  
  String? getBranchId() {
    return _prefs.getString(keyBranchId);
  }
  
  Future<void> saveTenantId(String tenantId) async {
    await _prefs.setString(keyTenantId, tenantId);
  }
  
  String? getTenantId() {
    return _prefs.getString(keyTenantId);
  }
  
  Future<void> saveLastSyncAt(DateTime dateTime) async {
    await _prefs.setString(keyLastSyncAt, dateTime.toIso8601String());
  }
  
  DateTime? getLastSyncAt() {
    final dateStr = _prefs.getString(keyLastSyncAt);
    if (dateStr == null) return null;
    return DateTime.parse(dateStr);
  }
  
  Future<void> saveFavoriteProducts(List<String> productIds) async {
    await _prefs.setStringList(keyFavoriteProducts, productIds);
  }
  
  List<String> getFavoriteProducts() {
    return _prefs.getStringList(keyFavoriteProducts) ?? [];
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
  
  // Clear all data
  Future<void> clearAll() async {
    await clearSecureStorage();
    await _prefs.clear();
  }
  
  // Clear session data (keep device registration)
  Future<void> clearSession() async {
    await clearSecureStorage();
    await _prefs.remove(keyUser);
    await _prefs.remove(keyLastSyncAt);
  }
}
