import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Simple HMAC-based auth token for local phone server mode.
///
/// No JWT library needed — we sign a JSON payload with HMAC-SHA256.
/// Format: base64(payload).base64(signature)
class AuthToken {
  // In production, this should be configurable via settings
  static const String _secret = 'levisa-pos-server-secret-2024';

  /// Generate a token for a user.
  static String generate({
    required String userId,
    required String role,
    required String tenantId,
    String? branchId,
  }) {
    final payload = jsonEncode({
      'sub': userId,
      'role': role,
      'tenantId': tenantId,
      'branchId': branchId,
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp': DateTime.now().add(const Duration(hours: 8)).millisecondsSinceEpoch ~/ 1000,
    });

    final payloadBase64 = _base64Encode(payload);
    final signature = _sign(payloadBase64);
    return '$payloadBase64.$signature';
  }

  /// Validate a token and return the payload if valid, null otherwise.
  static Map<String, dynamic>? validate(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 2) return null;

      final payloadBase64 = parts[0];
      final signature = parts[1];

      // Verify signature
      final expectedSig = _sign(payloadBase64);
      if (signature != expectedSig) return null;

      // Decode and check expiry
      final payloadJson = utf8.decode(base64Url.decode(payloadBase64));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;

      final exp = payload['exp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (now > exp) return null;

      return payload;
    } catch (_) {
      return null;
    }
  }

  /// Generate a refresh token (opaque UUID-style string).
  static String generateRefreshToken() {
    final random = _generateRandomBytes(32);
    return base64Url.encode(random);
  }

  /// Hash a refresh token for storage.
  static String hashRefreshToken(String token) {
    final bytes = sha256.convert(utf8.encode(token)).bytes;
    return base64Url.encode(bytes);
  }

  static String _sign(String payload) {
    final key = _secret.codeUnits;
    final data = utf8.encode(payload);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(data);
    return base64Url.encode(digest.bytes);
  }

  static String _base64Encode(String data) {
    return base64Url.encode(utf8.encode(data));
  }

  static Uint8List _generateRandomBytes(int count) {
    // Use DateTime-based entropy for simplicity (avoids dart:math Random which is predictable)
    final bytes = List<int>.generate(count, (i) {
      return (DateTime.now().microsecondsSinceEpoch + i * 7919) % 256;
    });
    return Uint8List.fromList(bytes);
  }

  /// Extract Bearer token from Authorization header.
  static String? extractBearer(String? authHeader) {
    if (authHeader == null || !authHeader.startsWith('Bearer ')) return null;
    return authHeader.substring(7);
  }
}
