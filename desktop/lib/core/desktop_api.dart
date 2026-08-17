import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

const defaultApiBaseUrl = 'https://arche-axon-pos-api.onrender.com/api/v1';

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class DesktopSession extends ChangeNotifier {
  DesktopSession()
    : _api = DesktopApi(),
      _storage = const FlutterSecureStorage();

  static const _accessTokenKey = 'desktop_access_token';
  static const _refreshTokenKey = 'desktop_refresh_token';
  static const _userKey = 'desktop_user';
  static const _deviceIdKey = 'desktop_device_id';
  static const _serverUrlKey = 'desktop_api_url';

  final DesktopApi _api;
  final FlutterSecureStorage _storage;
  bool _initializing = true;
  bool _authenticated = false;
  bool _refreshing = false;
  Map<String, dynamic>? _user;
  String? _refreshToken;
  String? _deviceId;
  Completer<bool>? _refreshCompleter;

  DesktopApi get api => _api;
  bool get initializing => _initializing;
  bool get authenticated => _authenticated;
  Map<String, dynamic>? get user => _user;
  String get apiBaseUrl => _api.baseUrl;
  String get displayName {
    final first = _user?['firstName']?.toString().trim() ?? '';
    final last = _user?['lastName']?.toString().trim() ?? '';
    final name = '$first $last'.trim();
    return name.isEmpty ? (_user?['email']?.toString() ?? 'User') : name;
  }

  List<Map<String, dynamic>> get branches => jsonMaps(_user?['branches']);
  String? get branchId => _user?['branchId']?.toString();
  String? get tenantSlug =>
      _user?['tenantSlug']?.toString() ??
      (_user?['tenant'] is Map
          ? (_user?['tenant'] as Map)['slug']?.toString()
          : null);
  String get deviceId => _deviceId ?? '';

  Future<void> initialize() async {
    try {
      final savedUrl = await _storage.read(key: _serverUrlKey);
      _api.setBaseUrl(savedUrl ?? defaultApiBaseUrl);
      _deviceId = await _storage.read(key: _deviceIdKey);
      _deviceId ??= const Uuid().v4();
      await _storage.write(key: _deviceIdKey, value: _deviceId);

      final accessToken = await _storage.read(key: _accessTokenKey);
      _refreshToken = await _storage.read(key: _refreshTokenKey);
      final savedUser = await _storage.read(key: _userKey);
      if (savedUser != null) {
        final parsed = jsonDecode(savedUser);
        if (parsed is Map<String, dynamic>) _user = parsed;
        if (parsed is Map && parsed is! Map<String, dynamic>) {
          _user = Map<String, dynamic>.from(parsed);
        }
      }

      _api.setAccessToken(accessToken);
      _api.onUnauthorized = _refreshAccessToken;
      if (accessToken != null && _user != null) {
        try {
          _user = await _api.getProfile();
          await _persistUser();
          _authenticated = true;
        } on ApiFailure {
          _authenticated = await _refreshAccessToken();
        }
      }
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> login({
    required String email,
    required String password,
    required String tenantSlug,
  }) async {
    final response = await _api.login(
      email: email,
      password: password,
      tenantSlug: tenantSlug,
      deviceId: deviceId,
    );
    await _applyAuthResponse(response);
    notifyListeners();
  }

  Future<void> setApiBaseUrl(String value) async {
    final normalized = normalizeApiUrl(value);
    _api.setBaseUrl(normalized);
    await _storage.write(key: _serverUrlKey, value: normalized);
    notifyListeners();
  }

  Future<void> changeBranch(String branchId) async {
    final updated = Map<String, dynamic>.from(_user ?? const {});
    updated['branchId'] = branchId;
    final branch = branches
        .where((item) => item['id']?.toString() == branchId)
        .firstOrNull;
    if (branch != null) updated['branchName'] = branch['name'];
    _user = updated;
    await _persistUser();
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await _api.logout(_refreshToken);
    } catch (_) {
      // Local logout must still succeed when the network is unavailable.
    }
    await _clearSession();
    notifyListeners();
  }

  Future<bool> _refreshAccessToken() async {
    if (_refreshing) return _refreshCompleter?.future ?? false;
    if (_refreshToken == null || _refreshToken!.isEmpty) {
      await _clearSession();
      return false;
    }
    _refreshing = true;
    _refreshCompleter = Completer<bool>();
    try {
      final response = await _api.refresh(_refreshToken!);
      await _applyAuthResponse(response, notify: false);
      _refreshCompleter!.complete(true);
      return true;
    } catch (_) {
      await _clearSession();
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> _applyAuthResponse(
    Map<String, dynamic> response, {
    bool notify = true,
  }) async {
    final accessToken = response['accessToken']?.toString();
    final refreshToken = response['refreshToken']?.toString();
    final candidateUser = response['user'];
    if (accessToken == null || refreshToken == null || candidateUser is! Map) {
      throw const ApiFailure(
        'The server returned an incomplete sign-in response.',
      );
    }
    _user = Map<String, dynamic>.from(candidateUser);
    _refreshToken = refreshToken;
    _authenticated = true;
    _api.setAccessToken(accessToken);
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _persistUser();
    if (notify) notifyListeners();
  }

  Future<void> _persistUser() {
    return _storage.write(key: _userKey, value: jsonEncode(_user));
  }

  Future<void> _clearSession() async {
    _authenticated = false;
    _user = null;
    _refreshToken = null;
    _api.setAccessToken(null);
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _userKey),
    ]);
  }
}

class DesktopApi {
  DesktopApi()
    : _dio = Dio(
        BaseOptions(
          baseUrl: defaultApiBaseUrl,
          connectTimeout: const Duration(seconds: 25),
          receiveTimeout: const Duration(seconds: 30),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_accessToken != null && _accessToken!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_accessToken';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  String? _accessToken;
  Future<bool> Function()? onUnauthorized;

  String get baseUrl => _dio.options.baseUrl;

  void setBaseUrl(String value) =>
      _dio.options.baseUrl = normalizeApiUrl(value);
  void setAccessToken(String? token) => _accessToken = token;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String tenantSlug,
    required String deviceId,
  }) async {
    final response = await _send(
      'POST',
      '/auth/login',
      data: {
        'email': email,
        'password': password,
        'tenantSlug': tenantSlug,
        'deviceId': deviceId,
      },
      allowRefresh: false,
    );
    return jsonMap(response.data);
  }

  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final response = await _send(
      'POST',
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
      allowRefresh: false,
    );
    return jsonMap(response.data);
  }

  Future<void> logout(String? refreshToken) async {
    await _send(
      'POST',
      '/auth/logout',
      data: {if (refreshToken != null) 'refreshToken': refreshToken},
      allowRefresh: false,
    );
  }

  Future<Map<String, dynamic>> getProfile() async =>
      jsonMap((await _send('GET', '/auth/profile')).data);

  Future<List<Map<String, dynamic>>> getCategories() async =>
      jsonMaps((await _send('GET', '/catalog/categories')).data);

  Future<List<Map<String, dynamic>>> getProducts({
    String? branchId,
    String? categoryId,
    String? search,
  }) async {
    final response = await _send(
      'GET',
      '/catalog/products',
      query: {
        'page': 1,
        'limit': 200,
        if (branchId != null) 'branchId': branchId,
        if (categoryId != null) 'categoryId': categoryId,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    return jsonMaps(jsonMap(response.data)['items']);
  }

  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> payload,
  ) async =>
      jsonMap((await _send('POST', '/catalog/products', data: payload)).data);

  Future<Map<String, dynamic>> updateProduct(
    String id,
    Map<String, dynamic> payload,
  ) async => jsonMap(
    (await _send('PATCH', '/catalog/products/$id', data: payload)).data,
  );

  Future<void> deleteProduct(String id) async {
    await _send('DELETE', '/catalog/products/$id');
  }

  Future<List<Map<String, dynamic>>> getCustomers() async =>
      jsonMaps((await _send('GET', '/customers')).data);

  Future<Map<String, dynamic>> createCustomer(
    Map<String, dynamic> payload,
  ) async => jsonMap((await _send('POST', '/customers', data: payload)).data);

  Future<Map<String, dynamic>> updateCustomer(
    String id,
    Map<String, dynamic> payload,
  ) async =>
      jsonMap((await _send('PATCH', '/customers/$id', data: payload)).data);

  Future<void> deleteCustomer(String id) async {
    await _send('DELETE', '/customers/$id');
  }

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> payload) async =>
      jsonMap((await _send('POST', '/sales', data: payload)).data);

  Future<List<Map<String, dynamic>>> getSales({String? branchId}) async {
    final response = await _send(
      'GET',
      '/sales',
      query: {
        'page': 1,
        'limit': 100,
        if (branchId != null) 'branchId': branchId,
      },
    );
    return jsonMaps(jsonMap(response.data)['items']);
  }

  Future<List<Map<String, dynamic>>> getStock(String branchId) async =>
      jsonMaps((await _send('GET', '/inventory/stock/$branchId')).data);

  Future<Map<String, dynamic>> adjustStock(
    Map<String, dynamic> payload,
  ) async =>
      jsonMap((await _send('POST', '/inventory/adjust', data: payload)).data);

  Future<List<Map<String, dynamic>>> getLowStock(String branchId) async =>
      jsonMaps(
        (await _send(
          'GET',
          '/inventory/low-stock',
          query: {'branchId': branchId},
        )).data,
      );

  Future<Map<String, dynamic>> getDashboard({String? branchId}) async =>
      jsonMap(
        (await _send(
          'GET',
          '/reports/dashboard',
          query: {
            'period': 'TODAY',
            if (branchId != null) 'branchId': branchId,
          },
        )).data,
      );

  Future<List<Map<String, dynamic>>> getSalesTrend({String? branchId}) async =>
      jsonMaps(
        (await _send(
          'GET',
          '/reports/sales/trend',
          query: {
            'period': 'THIS_WEEK',
            if (branchId != null) 'branchId': branchId,
          },
        )).data,
      );

  Future<List<Map<String, dynamic>>> getTopProducts({String? branchId}) async =>
      jsonMaps(
        (await _send(
          'GET',
          '/reports/products/top',
          query: {
            'period': 'THIS_MONTH',
            'limit': 10,
            if (branchId != null) 'branchId': branchId,
          },
        )).data,
      );

  Future<List<Map<String, dynamic>>> getPaymentMethods() async =>
      jsonMaps((await _send('GET', '/payments/methods')).data);

  Future<Response<dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
    bool allowRefresh = true,
  }) async {
    try {
      return await _dio.request(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method),
      );
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 401 && allowRefresh && onUnauthorized != null) {
        final refreshed = await onUnauthorized!();
        if (refreshed) {
          return _send(
            method,
            path,
            data: data,
            query: query,
            allowRefresh: false,
          );
        }
      }
      throw _asFailure(error);
    }
  }
}

ApiFailure _asFailure(DioException error) {
  final data = error.response?.data;
  var message =
      'Unable to reach the POS service. Check your connection and try again.';
  if (data is Map && data['message'] != null) {
    final value = data['message'];
    message = value is List ? value.join('\n') : value.toString();
  } else if (error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout) {
    message = 'The POS service took too long to respond. Please try again.';
  }
  return ApiFailure(message, statusCode: error.response?.statusCode);
}

String normalizeApiUrl(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) return defaultApiBaseUrl;
  return trimmed.endsWith('/api/v1') ? trimmed : '$trimmed/api/v1';
}

Map<String, dynamic> jsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> jsonMaps(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
