import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:axon_pos/core/network/auth_interceptor.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with the status [statusFor] picks for its path.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.statusFor);
  final int Function(String path) statusFor;
  final seen = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options.path);
    final status = statusFor(options.path);
    return ResponseBody.fromString(
      jsonEncode(status == 200
          ? {'accessToken': 'new', 'refreshToken': 'new-refresh'}
          : {'message': 'nope'}),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Refreshes through the very same Dio the interceptor guards, exactly like
/// the real AuthService -> ApiClient.refreshToken path.
class _FakeAuth extends Fake implements AuthService {
  _FakeAuth(this.dio);
  final Dio dio;
  int logouts = 0;
  String? _token = 'old';

  @override
  String? get accessToken => _token;

  @override
  bool get isLocked => false;

  @override
  String? get deviceId => null;

  @override
  Future<String?> getAccessTokenWithFallback() async => _token;

  @override
  Future<void> refreshTokens({String? expectedTenantId}) async {
    final res = await dio.post('/auth/refresh', data: {'refreshToken': 'r'});
    _token = res.data['accessToken'] as String;
  }

  @override
  Future<void> logout({bool allDevices = false}) async {
    logouts++;
  }
}

void main() {
  test('a rejected refresh token logs out immediately instead of hanging',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://x'));
    final adapter = _Adapter((_) => 401);
    dio.httpClientAdapter = adapter;
    final auth = _FakeAuth(dio);
    dio.interceptors.add(AuthInterceptor(auth, dio));

    // Before the fix the refresh call's own 401 re-entered the interceptor,
    // waited on the refresh it was part of and only gave up after the 30s
    // timeout, so the session stayed "signed in" while every call failed.
    await expectLater(
      dio.get('/sales').timeout(const Duration(seconds: 5)),
      throwsA(isA<DioException>()
          .having((e) => e.response?.statusCode, 'status', 401)),
    );
    expect(auth.logouts, 1);
    expect(adapter.seen.where((p) => p == '/auth/refresh').length, 1);
  });

  test('an expired access token is refreshed and the request retried',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://x'));
    var salesCalls = 0;
    final adapter = _Adapter((path) {
      if (path == '/auth/refresh') return 200;
      salesCalls++;
      return salesCalls == 1 ? 401 : 200;
    });
    dio.httpClientAdapter = adapter;
    final auth = _FakeAuth(dio);
    dio.interceptors.add(AuthInterceptor(auth, dio));

    final res = await dio.get('/sales').timeout(const Duration(seconds: 5));
    expect(res.statusCode, 200);
    expect(auth.logouts, 0);
    expect(salesCalls, 2);
  });
}
