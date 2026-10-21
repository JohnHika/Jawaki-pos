import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';

/// Every failed call surfaces as one of these, so screens can show a precise
/// message and branch on `status`/`code` instead of parsing strings.
class ApiException implements Exception {
  ApiException(this.status, this.message, {this.code, this.body, this.retryAfterSeconds});

  /// HTTP status, or 0 when the server could not be reached at all.
  final int status;
  final String message;

  /// Machine code from the API: ACCOUNT_LOCKED, MISSING_PERMISSION, PASSWORD_CHANGE_REQUIRED...
  final String? code;
  final Map<String, dynamic>? body;
  final int? retryAfterSeconds;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isConflict => status == 409;
  bool get isLocked => status == 423 || code == 'ACCOUNT_LOCKED';
  bool get isPasswordChangeRequired => code == 'PASSWORD_CHANGE_REQUIRED';
  bool get isRateLimited => status == 429;

  @override
  String toString() => message;
}

/// Access/refresh tokens. Kept in the Android keystore-backed secure storage;
/// never in shared preferences, never logged.
class AuthTokens {
  const AuthTokens({required this.access, required this.refresh, required this.accessExpiresAt});
  final String access;
  final String refresh;
  final DateTime? accessExpiresAt;

  bool get accessLikelyValid =>
      accessExpiresAt == null || accessExpiresAt!.isAfter(DateTime.now().add(const Duration(seconds: 30)));
}

class TokenStore {
  TokenStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static const _kAccess = 'aca.access';
  static const _kRefresh = 'aca.refresh';
  static const _kExp = 'aca.exp';

  Future<AuthTokens?> read() async {
    try {
      final a = await _s.read(key: _kAccess);
      final r = await _s.read(key: _kRefresh);
      if (a == null || r == null) return null;
      final exp = await _s.read(key: _kExp);
      return AuthTokens(access: a, refresh: r, accessExpiresAt: exp == null ? null : DateTime.tryParse(exp));
    } catch (_) {
      // A corrupt keystore entry must not brick the app: treat as signed out.
      await clear();
      return null;
    }
  }

  Future<void> write(AuthTokens t) async {
    await _s.write(key: _kAccess, value: t.access);
    await _s.write(key: _kRefresh, value: t.refresh);
    if (t.accessExpiresAt != null) {
      await _s.write(key: _kExp, value: t.accessExpiresAt!.toUtc().toIso8601String());
    }
  }

  Future<void> clear() async {
    for (final k in [_kAccess, _kRefresh, _kExp]) {
      try {
        await _s.delete(key: k);
      } catch (_) {}
    }
  }
}

/// HTTP client for the Counterbase platform-admin API.
///
///  * attaches the access token and refreshes it transparently (single flight,
///    so concurrent 401s never replay a retired refresh token);
///  * maps every failure to [ApiException];
///  * flags [waking] when a request is slow, because the free-tier host sleeps
///    after inactivity and the first call can take up to a minute.
class AcaApi {
  AcaApi({required this.store, http.Client? client, this.deviceLabel = 'Android', this.appVersion = ''})
      : _client = client ?? http.Client();

  final TokenStore store;
  final http.Client _client;
  String deviceLabel;
  String appVersion;

  /// True while any request has been in flight for more than a few seconds.
  final ValueNotifier<bool> waking = ValueNotifier(false);

  /// Called once when the refresh token is rejected: the session is gone.
  void Function()? onSessionExpired;

  AuthTokens? _tokens;
  Future<bool>? _refreshing;
  int _slow = 0;

  static const _timeout = Duration(seconds: 75);
  static const _slowAfter = Duration(seconds: 5);

  AuthTokens? get tokens => _tokens;
  bool get hasSession => _tokens != null;

  Future<AuthTokens?> loadTokens() async => _tokens = await store.read();

  Future<void> setTokens(AuthTokens t) async {
    _tokens = t;
    await store.write(t);
  }

  Future<void> clearTokens() async {
    _tokens = null;
    await store.clear();
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);
  Future<dynamic> post(String path, {Object? body, bool auth = true}) =>
      _send('POST', path, body: body ?? const <String, dynamic>{}, auth: auth);
  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Convenience: the JSON object at [path], or {} when the body is empty.
  Future<Map<String, dynamic>> getMap(String path, {Map<String, dynamic>? query}) async {
    final r = await get(path, query: query);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> postMap(String path, {Object? body}) async {
    final r = await post(path, body: body);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  Uri _uri(String path, Map<String, dynamic>? query) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    return Uri.parse('${AcaConfig.platformBase}$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool auth = true,
    bool retried = false,
  }) async {
    if (auth) {
      final t = _tokens;
      if (t != null && !t.accessLikelyValid) await _refreshSingleFlight();
    }

    final slowTimer = Timer(_slowAfter, () {
      _slow++;
      waking.value = true;
    });
    var counted = false;
    http.Response res;
    try {
      res = await _request(method, _uri(path, query), body, auth).timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'The server took too long to respond. Check your connection and try again.');
    } on SocketException {
      throw ApiException(0, 'Can\'t reach the server. Check your internet connection.');
    } on http.ClientException {
      throw ApiException(0, 'Can\'t reach the server. Check your internet connection.');
    } on HandshakeException {
      throw ApiException(0, 'Secure connection to the server failed.');
    } finally {
      counted = !slowTimer.isActive;
      slowTimer.cancel();
      if (counted && _slow > 0) {
        _slow--;
        if (_slow == 0) waking.value = false;
      }
    }

    if (res.statusCode == 401 && auth && !retried && _tokens != null) {
      if (await _refreshSingleFlight()) {
        return _send(method, path, query: query, body: body, auth: auth, retried: true);
      }
    }

    return _decode(res);
  }

  Future<http.Response> _request(String method, Uri uri, Object? body, bool auth) {
    final headers = <String, String>{
      'accept': 'application/json',
      'content-type': 'application/json',
      'user-agent': 'ACA/$appVersion (Android)',
      'x-aca-device': deviceLabel,
      if (auth && _tokens != null) 'authorization': 'Bearer ${_tokens!.access}',
    };
    final encoded = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri, headers: headers, body: encoded);
      case 'PUT':
        return _client.put(uri, headers: headers, body: encoded);
      case 'PATCH':
        return _client.patch(uri, headers: headers, body: encoded);
      case 'DELETE':
        return _client.delete(uri, headers: headers);
    }
    throw ArgumentError('Unsupported method $method');
  }

  dynamic _decode(http.Response res) {
    dynamic parsed;
    if (res.body.isNotEmpty) {
      try {
        parsed = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        parsed = null;
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return parsed;

    String message = 'Something went wrong (HTTP ${res.statusCode}).';
    String? code;
    int? retryAfter;
    Map<String, dynamic>? bodyMap;
    if (parsed is Map) {
      bodyMap = Map<String, dynamic>.from(parsed);
      final m = bodyMap['message'];
      if (m is String && m.isNotEmpty) {
        message = m;
      } else if (m is List && m.isNotEmpty) {
        message = m.map((e) => e.toString()).join('\n');
      }
      code = bodyMap['code'] as String?;
      retryAfter = bodyMap['retryAfterSeconds'] is num ? (bodyMap['retryAfterSeconds'] as num).toInt() : null;
    }
    if (res.statusCode == 429) {
      message = 'Too many attempts. Wait a minute and try again.';
    } else if (res.statusCode >= 500) {
      message = 'The server hit a problem. Try again in a moment.';
    }
    throw ApiException(res.statusCode, message, code: code, body: bodyMap, retryAfterSeconds: retryAfter);
  }

  /// Exactly one refresh at a time; concurrent callers share its result.
  Future<bool> _refreshSingleFlight() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _refresh() async {
    final t = _tokens;
    if (t == null) return false;
    try {
      final res = await _request('POST', _uri('/auth/refresh', null), {'refreshToken': t.refresh}, false)
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        await setTokens(AuthTokens(
          access: j['accessToken'] as String,
          refresh: j['refreshToken'] as String,
          accessExpiresAt: DateTime.tryParse((j['accessTokenExpiresAt'] ?? '') as String),
        ));
        return true;
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        await clearTokens();
        onSessionExpired?.call();
        return false;
      }
      return false; // 5xx / 429: keep the session, let the caller see the failure
    } catch (_) {
      return false; // offline: keep the session
    }
  }
}
