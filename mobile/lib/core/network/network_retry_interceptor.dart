import 'dart:async';

import 'package:dio/dio.dart';

/// Retries requests when the network or a temporarily unavailable server
/// fails. Read-only requests are retried on connection errors and 5xx.
/// Mutating requests (POST/PUT/PATCH/DELETE) are retried only when the
/// failure is ambiguously transient: a connection that never delivered the
/// request body (connection error, timeout, or a 502/503/504 from a proxy
/// that did not forward the body) — these are safe because the server never
/// saw the request. A 5xx after the body was delivered is NOT retried for
/// mutating methods, because we cannot tell whether the mutation executed.
class NetworkRetryInterceptor extends Interceptor {
  NetworkRetryInterceptor(this._dio);

  static const _maxRetries = 2;
  final Dio _dio;

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final attempt = (options.extra['networkRetryAttempt'] as int?) ?? 0;

    if (!_isRetryable(err) || attempt >= _maxRetries) {
      return handler.next(err);
    }

    options.extra['networkRetryAttempt'] = attempt + 1;
    await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));

    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  bool _isRetryable(DioException error) {
    final method = error.requestOptions.method.toUpperCase();
    final status = error.response?.statusCode;

    // True connection-level failures (request never reached the server).
    final neverReachedServer =
        error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.sendTimeout;

    // Read-only methods: retry any retryable error.
    const safeMethods = {'GET', 'HEAD', 'OPTIONS'};
    if (safeMethods.contains(method)) {
      return neverReachedServer || (status != null && status >= 500 && status < 600);
    }

    // Mutating methods: only retry when we can be confident the server did
    // not process the request. 502/503/504 from a proxy before the backend
    // generally means the backend never saw the body. A plain 5xx with no
    // response body from a cold-starting backend is also retryable.
    if (neverReachedServer) return true;
    if (status == 502 || status == 503 || status == 504) return true;

    return false;
  }
}
