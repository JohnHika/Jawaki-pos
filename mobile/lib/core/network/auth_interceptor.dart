import 'package:dio/dio.dart';
import '../services/auth_service.dart';

class AuthInterceptor extends Interceptor {
  final AuthService _authService;

  // Single in-flight refresh shared by every request that hits a 401 while
  // it's running. The backend rotates refresh tokens (each one is deleted
  // the moment it's used), so two concurrent refresh calls are fatal: the
  // second presents an already-consumed token, gets rejected, and the
  // session dies. A shared Future means exactly one network refresh happens
  // no matter how many requests 401 at once (easy with the background sync
  // polling every 30s against a 15-minute access token), and every waiter
  // retries with the fresh token afterwards.
  Future<void>? _refreshFuture;

  AuthInterceptor(this._authService);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Skip auth for public auth endpoints; logout still needs the bearer token.
    final noAuthPaths = ['/auth/login', '/auth/register', '/auth/refresh'];
    if (noAuthPaths.any((path) => options.path.contains(path))) {
      return handler.next(options);
    }

    // Add access token if available
    final token = _authService.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    // Add device ID if available
    final deviceId = _authService.deviceId;
    if (deviceId != null) {
      options.headers['X-Device-ID'] = deviceId;
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Don't retry logout or login endpoints
    final skipRetryPaths = ['/auth/logout', '/auth/login', '/auth/register'];
    if (skipRetryPaths.any((path) => err.requestOptions.path.contains(path))) {
      return handler.next(err);
    }

    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Refresh (or wait for the refresh already in flight), then retry.
    try {
      _refreshFuture ??= _authService.refreshTokens().whenComplete(() {
        _refreshFuture = null;
      });
      await _refreshFuture;
    } catch (e) {
      // Only the server explicitly rejecting the refresh token (401/403)
      // means the session is truly dead. Anything else — timeout, no
      // connectivity, DNS failure, a 5xx from a cold-starting backend —
      // is a transient failure to *verify* the session, not proof it's
      // invalid, so we must not log the user out for it.
      final refreshStatus = e is DioException ? e.response?.statusCode : null;
      if (refreshStatus == 401 || refreshStatus == 403) {
        await _authService.logout();
      }
      return handler.next(err);
    }

    // Refresh succeeded — retry the original request with the new token.
    // A failure here is the retried request's own problem (its real
    // response/error), not a reason to kill the session.
    try {
      final opts = err.requestOptions;
      opts.headers['Authorization'] = 'Bearer ${_authService.accessToken}';
      final response = await Dio().fetch(opts);
      return handler.resolve(response);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    } catch (_) {
      return handler.next(err);
    }
  }
}
