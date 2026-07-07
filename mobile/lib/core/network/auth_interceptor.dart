import 'package:dio/dio.dart';
import '../services/auth_service.dart';

class AuthInterceptor extends Interceptor {
  final AuthService _authService;
  bool _isRefreshing = false;
  
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

    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;

      try {
        // Try to refresh the token
        await _authService.refreshTokens();
        _isRefreshing = false;

        // Retry the original request
        final opts = err.requestOptions;
        opts.headers['Authorization'] = 'Bearer ${_authService.accessToken}';

        final response = await Dio().fetch(opts);
        return handler.resolve(response);
      } catch (e) {
        _isRefreshing = false;

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
    }
    
    handler.next(err);
  }
}
