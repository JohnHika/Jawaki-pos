import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'storage_service.dart';
import '../network/api_client.dart';

enum AuthStatus {
  unknown,
  authenticated,
  unauthenticated,
}

class AuthService {
  final StorageService _storage;
  final ApiClient _apiClient;
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  final StreamController<AuthStatus> _authStatusController = 
      StreamController<AuthStatus>.broadcast();
  
  AuthStatus _currentStatus = AuthStatus.unknown;
  Map<String, dynamic>? _currentUser;
  String? _accessToken;
  
  AuthService({
    required StorageService storage,
    required ApiClient apiClient,
  }) : _storage = storage, _apiClient = apiClient {
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
  
  String? get userId => _currentUser?['id'];
  String? get branchId => _storage.getBranchId();
  String? get deviceId => _storage.getDeviceId();
  String? get tenantId => _storage.getTenantId();
  String? get userRole => _currentUser?['role'];
  
  Future<void> _initializeAuth() async {
    // Always require fresh login on app start — clear any stored session
    await _storage.clearSession();
    _accessToken = null;
    _currentUser = null;
    _updateStatus(AuthStatus.unauthenticated);
  }
  
  Future<void> login({
    required String email,
    required String password,
    String? deviceId,
  }) async {
    final response = await _apiClient.login(
      email: email,
      password: password,
      deviceId: deviceId ?? _storage.getDeviceId(),
    );

    await _handleAuthResponse(response);
  }

  Future<void> loginWithPin(String pin) async {
    final response = await _apiClient.loginWithPin(
      pin: pin,
      deviceId: _storage.getDeviceId()!,
    );

    await _handleAuthResponse(response);
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
  
  Future<void> logout() async {
    try {
      await _apiClient.logout();
    } catch (_) {
      // Ignore logout API errors
    }

    await _storage.clearSession();
    _accessToken = null;
    _currentUser = null;
    _updateStatus(AuthStatus.unauthenticated);
  }
  
  Future<void> _handleAuthResponse(Map<String, dynamic> response) async {
    _accessToken = response['accessToken'];
    Map<String, dynamic> userData = Map<String, dynamic>.from(response['user']);

    // Normalize name from firstName + lastName if name is not present
    if (userData['name'] == null && userData['firstName'] != null) {
      userData['name'] = '${userData['firstName']} ${userData['lastName'] ?? ''}'.trim();
    }

    // Extract branch ID from branches array if branchId is not directly present
    if (userData['branchId'] == null && userData['branches'] is List && (userData['branches'] as List).isNotEmpty) {
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

    if (_currentUser!['branchId'] != null) {
      await _storage.saveBranchId(_currentUser!['branchId']);
    }
    if (_currentUser!['tenantId'] != null) {
      await _storage.saveTenantId(_currentUser!['tenantId']);
    }

    _updateStatus(AuthStatus.authenticated);
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
  
  // Hierarchical role checks (higher inherits lower)
  bool get isAdmin => userRole == 'admin';
  bool get isStoreManager => hasAnyRole(['admin', 'store_manager', 'manager']);
  bool get isStockKeeper => hasAnyRole(['admin', 'store_manager', 'manager', 'stock_keeper']);
  bool get isSeller => true; // everyone can sell
  
  // Legacy aliases
  bool get isManager => isStoreManager;
  bool get isCashier => isSeller;
  
  // Biometric Authentication
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
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
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Sign in to Levisa Adventures POS',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow PIN/pattern fallback
        ),
      );
      
      if (didAuthenticate) {
        // Check if we have a stored user session to restore
        _accessToken = await _storage.getAccessToken();
        _currentUser = _storage.getUser();
        
        if (_currentUser != null && _accessToken != null) {
          _updateStatus(AuthStatus.authenticated);
          return true;
        }
        
        // No stored session — cannot auto-login
        return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
  
  void dispose() {
    _authStatusController.close();
  }
}
