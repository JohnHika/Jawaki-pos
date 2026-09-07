import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Simple HMAC-based auth token for local phone server mode.
///
/// No JWT library needed — we sign a JSON payload with HMAC-SHA256.
/// Format: base64(payload).base64(signature)
///
/// The signing secret is NOT compiled into the app: it is generated
/// per-device on first use (Random.secure) and persisted so tokens
/// survive restarts. A hardcoded secret would let anyone holding the
/// APK forge valid tokens for any user/role/tenant against any
/// phone-server on the LAN.
class AuthToken {
  static const String _secretStorageKey = 'phone_server_token_secret_v1';

  /// Cached per-process secret; loaded lazily via [secretProvider].
  static String? _cachedSecret;

  /// Injected by the phone-server bootstrap so the secret persists via
  /// the app's secure storage rather than this class knowing about
  /// storage internals. Must be set before the server starts serving.
  static String Function()? secretProvider;

  static String _secret() {
    if (_cachedSecret != null) return _cachedSecret!;

    final provider = secretProvider;
    if (provider == null) {
      throw StateError(
        'AuthToken.secretProvider not set — phone server cannot mint tokens safely',
      );
    }
    var secret = provider();
    if (secret.isEmpty) {
      // First boot on this device: generate a 256-bit secret.
      final bytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
      secret = base64Url.encode(bytes);
      secretPersistHook?.call(_secretStorageKey, secret);
    }
    _cachedSecret = secret;
    return secret;
  }

  /// Optional persistence callback so a freshly generated secret is
  /// written back to secure storage on first use.
  static void Function(String key, String secret)? secretPersistHook;

  /// Test/bootstrap seam: allow explicit secret initialization.
  static void initSecret(String secret) {
    _cachedSecret = secret;
  }

  static final Random _secureRandom = Random.secure();

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

      // Verify signature (constant-time comparison so timing can't leak
      // signature bytes across repeated guesses).
      final expectedSig = _sign(payloadBase64);
      if (!_constantTimeEquals(signature, expectedSig)) return null;

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

  /// Generate a refresh token (opaque URL-safe string).
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
    final key = _secret().codeUnits;
    final data = utf8.encode(payload);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(data);
    return base64Url.encode(digest.bytes);
  }

  static String _base64Encode(String data) {
    return base64Url.encode(utf8.encode(data));
  }

  static Uint8List _generateRandomBytes(int count) {
    // Cryptographically secure randomness. The previous DateTime-based
    // entropy was enumerable by a peer who knew the rough time, defeating
    // the hashed refresh-token store.
    final bytes = List<int>.generate(count, (_) => _secureRandom.nextInt(256));
    return Uint8List.fromList(bytes);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Extract Bearer token from Authorization header.
  static String? extractBearer(String? authHeader) {
    if (authHeader == null || !authHeader.startsWith('Bearer ')) return null;
    return authHeader.substring(7);
  }
}