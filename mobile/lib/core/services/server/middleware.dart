import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'auth_token.dart';

/// CORS middleware — allows cross-origin requests from any phone on the network.
shelf.Middleware corsMiddleware() {
  return (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      // Handle preflight OPTIONS requests
      if (request.method == 'OPTIONS') {
        return shelf.Response.ok('', headers: _corsHeaders());
      }

      final response = await innerHandler(request);
      return response.change(headers: _corsHeaders());
    };
  };
}

Map<String, String> _corsHeaders() => {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
      'Access-Control-Allow-Headers':
          'Content-Type, Authorization, X-Device-ID',
      'Access-Control-Max-Age': '86400',
    };

/// JSON body parser middleware — parses request bodies as JSON.
shelf.Middleware jsonBodyParser() {
  return (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      if (request.method == 'POST' ||
          request.method == 'PUT' ||
          request.method == 'PATCH') {
        final contentType = request.headers['content-type'] ?? '';
        if (contentType.contains('application/json')) {
          final body = await request.readAsString();
          if (body.isNotEmpty) {
            try {
              final data = jsonDecode(body);
              request = request.change(context: {'body': data});
            } catch (_) {
              return shelf.Response.badRequest(
                body: jsonEncode({'error': 'Invalid JSON'}),
                headers: {'content-type': 'application/json'},
              );
            }
          }
        }
      }
      return innerHandler(request);
    };
  };
}

/// Auth middleware — validates tokens for protected routes.
///
/// Routes in [noAuthPaths] are skipped. For all others, extracts the
/// Bearer token, validates it, and attaches the user payload to
/// request.context['user'].
shelf.Middleware authMiddleware({
  Set<String> noAuthPaths = const {
    '/api/v1/auth/login',
    '/api/v1/auth/pin-login',
    '/api/v1/auth/register',
    '/api/v1/auth/refresh',
  },
}) {
  return (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      final path = request.url.path;

      // Check if this path starts with any no-auth prefix
      final needsAuth = !noAuthPaths.any((p) {
        final normalizedPath = p.startsWith('/') ? p.substring(1) : p;
        return path.startsWith(normalizedPath);
      });

      if (!needsAuth) {
        return innerHandler(request);
      }

      // Extract and validate token
      final authHeader = request.headers['authorization'];
      final token = AuthToken.extractBearer(authHeader);

      if (token == null) {
        return shelf.Response(
          401,
          body:
              jsonEncode({'error': 'Missing or invalid Authorization header'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final payload = AuthToken.validate(token);
      if (payload == null) {
        return shelf.Response(
          401,
          body: jsonEncode({'error': 'Invalid or expired token'}),
          headers: {'content-type': 'application/json'},
        );
      }

      request = request.change(context: {'user': payload});
      return innerHandler(request);
    };
  };
}

/// Helper to parse request body from context.
Map<String, dynamic>? getRequestBody(shelf.Request request) {
  return request.context['body'] as Map<String, dynamic>?;
}

/// Helper to get authenticated user from context.
Map<String, dynamic>? getAuthUser(shelf.Request request) {
  return request.context['user'] as Map<String, dynamic>?;
}

/// Error handler middleware — catches exceptions and returns JSON errors.
shelf.Middleware errorHandler() {
  return (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      try {
        final response = await innerHandler(request);
        return response;
      } catch (e, stack) {
        debugPrint('[Server Error] $e');
        debugPrint(stack.toString());
        return shelf.Response.internalServerError(
          body: jsonEncode(
              {'error': 'Internal server error', 'message': e.toString()}),
          headers: {'content-type': 'application/json'},
        );
      }
    };
  };
}
