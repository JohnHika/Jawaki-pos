import 'dart:async';
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
    _initializeAuth();
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
    _accessToken = await _storage.getAccessToken();
    _currentUser = _storage.getUser();
    
    if (_accessToken != null && _currentUser != null) {
      _updateStatus(AuthStatus.authenticated);
    } else {
      _updateStatus(AuthStatus.unauthenticated);
    }
  }
  
  Future<void> login({
    required String email,
    required String password,
    String? deviceId,
  }) async {
    // DEV MODE: Hardcoded admin login
    // TODO: Remove before production and use API auth
    if (email == 'johnkimani576@gmail.com' && password == 'admin123') {
      final adminUser = {
        'id': 'admin-001',
        'email': 'johnkimani576@gmail.com',
        'name': 'John Kimani',
        'role': 'admin',
        'branchId': 'branch-001',
        'tenantId': 'jawaki-adventures',
      };
      _accessToken = 'admin-token-${DateTime.now().millisecondsSinceEpoch}';
      _currentUser = adminUser;
      await _storage.saveAccessToken(_accessToken!);
      await _storage.saveRefreshToken('admin-refresh-token');
      await _storage.saveUser(adminUser);
      await _storage.saveBranchId('branch-001');
      await _storage.saveTenantId('jawaki-adventures');
      _updateStatus(AuthStatus.authenticated);
      return;
    }
    
    final response = await _apiClient.login(
      email: email,
      password: password,
      deviceId: deviceId ?? _storage.getDeviceId(),
    );
    
    await _handleAuthResponse(response);
  }
  
  Future<void> loginWithPin(String pin) async {
    // DEV MODE: Accept dummy PIN 0000 for development testing
    // TODO: Remove this before production deployment
    if (pin == '0000') {
      final devUser = {
        'id': 'admin-001',
        'email': 'johnkimani576@gmail.com',
        'name': 'John Kimani',
        'role': 'admin',
        'branchId': 'branch-001',
        'tenantId': 'jawaki-adventures',
      };
      _accessToken = 'dev-token-${DateTime.now().millisecondsSinceEpoch}';
      _currentUser = devUser;
      await _storage.saveAccessToken(_accessToken!);
      await _storage.saveRefreshToken('dev-refresh-token');
      await _storage.saveUser(devUser);
      await _storage.saveBranchId('branch-001');
      await _storage.saveTenantId('jawaki-adventures');
      _updateStatus(AuthStatus.authenticated);
      return;
    }
    
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
    // Only call logout API if we have a valid token and it's not a dev token
    if (_accessToken != null && !_accessToken!.startsWith('admin-token-')) {
      try {
        await _apiClient.logout();
      } catch (_) {
        // Ignore logout API errors
      }
    }
    
    await _storage.clearSession();
    _accessToken = null;
    _currentUser = null;
    _updateStatus(AuthStatus.unauthenticated);
  }
  
  Future<void> _handleAuthResponse(Map<String, dynamic> response) async {
    _accessToken = response['accessToken'];
    _currentUser = response['user'];
    
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
        localizedReason: 'Sign in to JAWAKI ADVENTURES POS',
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
        
        // No stored session - use default admin for dev
        // TODO: Remove before production
        final adminUser = {
          'id': 'admin-001',
          'email': 'johnkimani576@gmail.com',
          'name': 'John Kimani',
          'role': 'admin',
          'branchId': 'branch-001',
          'tenantId': 'jawaki-adventures',
        };
        _accessToken = 'bio-token-${DateTime.now().millisecondsSinceEpoch}';
        _currentUser = adminUser;
        await _storage.saveAccessToken(_accessToken!);
        await _storage.saveRefreshToken('bio-refresh-token');
        await _storage.saveUser(adminUser);
        await _storage.saveBranchId('branch-001');
        await _storage.saveTenantId('jawaki-adventures');
        _updateStatus(AuthStatus.authenticated);
        return true;
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
