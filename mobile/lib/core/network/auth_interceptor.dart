import 'package:dio/dio.dart';
import '../services/auth_service.dart';

class AuthInterceptor extends Interceptor {
  final AuthService _authService;
  final Dio _dio;

  // Single in-flight refresh shared by every request that hits a 401 while
  // it's running. The backend rotates refresh tokens (each one is deleted
  // the moment it's used), so two concurrent refresh calls are fatal: the
  // second presents an already-consumed token, gets rejected, and the
  // session dies. A shared Future means exactly one network refresh happens
  // no matter how many requests 401 at once (easy with the background sync
  // polling every 30s against a 15-minute access token), and every waiter
  // retries with the fresh token afterwards.
  Future<void>? _refreshFuture;

  AuthInterceptor(this._authService, this._dio);

  bool _matchesExpectedTenant(RequestOptions options) {
    final expectedTenantId = options.extra['expectedTenantId']?.toString();
    return expectedTenantId == null ||
        expectedTenantId == _authService.tenantId;
  }

  DioException _sessionChanged(RequestOptions options) => DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        message: 'The signed-in workspace changed during sync.',
      );

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_matchesExpectedTenant(options)) {
      return handler.reject(_sessionChanged(options));
    }

    // Skip auth for public auth endpoints; logout still needs the bearer token.
    final noAuthPaths = ['/auth/login', '/auth/register', '/auth/refresh'];
    if (noAuthPaths.any((path) => options.path.contains(path))) {
      return handler.next(options);
    }

    // A locked session retains its credentials for a later PIN/biometric
    // unlock, but protected foreground calls must not reuse them.
    if (_authService.isLocked) {
      options.headers.remove('Authorization');
      return handler.next(options);
    }

    // Add access token if available — use the async fallback to reload from
    // storage if the in-memory token was cleared (e.g. after lock/unlock).
    try {
      final token = await _authService.getAccessTokenWithFallback();
      if (!_matchesExpectedTenant(options)) {
        return handler.reject(_sessionChanged(options));
      }
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // If reading the token fails (e.g. secure storage locked), continue
      // without it and let the backend return 401 if auth is required.
    }
    if (!_matchesExpectedTenant(options)) {
      return handler.reject(_sessionChanged(options));
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
    if (!_matchesExpectedTenant(err.requestOptions)) {
      return handler.next(err);
    }

    // Do not rotate or restore credentials for a request that failed after
    // the app was locked while it was in flight.
    if (!_authService.isAuthenticated) {
      return handler.next(err);
    }

    // Don't retry logout or login endpoints
    // /auth/refresh must be here too: it travels through this same Dio, so its
    // own 401 would re-enter this handler and wait on the very refresh it is
    // part of, hanging until the 30s timeout instead of ending the session.
    final skipRetryPaths = [
      '/auth/logout',
      '/auth/login',
      '/auth/register',
      '/auth/refresh',
    ];
    if (skipRetryPaths.any((path) => err.requestOptions.path.contains(path))) {
      return handler.next(err);
    }

    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Refresh (or wait for the refresh already in flight), then retry.
    // We retry the refresh itself on transient failures so a cold-starting
    // backend (e.g. Render free tier) doesn't kill a live session.
    const maxRefreshAttempts = 3;
    for (var attempt = 0; attempt < maxRefreshAttempts; attempt++) {
      try {
        final expectedTenantId =
            err.requestOptions.extra['expectedTenantId']?.toString();
        _refreshFuture ??= _authService
            .refreshTokens(expectedTenantId: expectedTenantId)
            .whenComplete(() {
          _refreshFuture = null;
        });
        await _refreshFuture;
        if (!_matchesExpectedTenant(err.requestOptions)) {
          return handler.next(err);
        }
        break; // Refresh succeeded.
      } catch (e) {
        if (!_matchesExpectedTenant(err.requestOptions)) {
          return handler.next(err);
        }
        final refreshStatus = e is DioException ? e.response?.statusCode : null;

        // Server explicitly rejected the refresh token → session is dead.
        if (refreshStatus == 401 || refreshStatus == 403) {
          await _authService.logout();
          return handler.next(err);
        }

        // Transient failure (timeout, DNS, 5xx from cold backend). Retry
        // with exponential backoff unless we've exhausted attempts.
        _refreshFuture = null;
        if (attempt < maxRefreshAttempts - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }

        // Exhausted retries on transient failures. Don't kill the session;
        // just propagate the original 401 so the caller can show a retryable
        // error instead of forcing a full re-login.
        return handler.next(err);
      }
    }

    // Refresh succeeded — retry the original request with the new token.
    try {
      final opts = err.requestOptions;
      if (!_matchesExpectedTenant(opts)) return handler.next(err);
      opts.headers['Authorization'] = 'Bearer ${_authService.accessToken}';
      final response = await _dio.fetch(opts);
      return handler.resolve(response);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    } catch (_) {
      return handler.next(err);
    }
  }
}
