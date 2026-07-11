import 'dart:async';

import 'package:dio/dio.dart';

/// Retries only safe, read-only requests when the network or a temporarily
/// unavailable server fails. Mutating requests are deliberately excluded: a
/// retry after an ambiguous timeout could create a duplicate sale or payment.
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
    const safeMethods = {'GET', 'HEAD', 'OPTIONS'};
    if (!safeMethods.contains(error.requestOptions.method.toUpperCase())) {
      return false;
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return true;
    }

    final status = error.response?.statusCode;
    return status != null && status >= 500 && status < 600;
  }
}
