import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;
import 'package:uuid/uuid.dart';
import '../../../database/app_database.dart';
import '../auth_token.dart';
import '../middleware.dart';
import '../sql_helper.dart';

/// Auth routes for phone server mode.
///
/// These replace the NestJS auth endpoints:
///   POST /api/v1/auth/login     → validate email + password, return tokens + user
///   POST /api/v1/auth/pin-login → validate PIN, return tokens + user
///   POST /api/v1/auth/refresh   → validate refresh token, issue new tokens
///   POST /api/v1/auth/logout    → invalidate refresh token
class AuthRoutes {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  AuthRoutes(this._db);

  void addRoutes(Router r) {
    r.post('/api/v1/auth/login', _handleLogin);
    r.post('/api/v1/auth/pin-login', _handlePinLogin);
    r.post('/api/v1/auth/offline-pin-login', _handleOfflinePinLogin);
    r.post('/api/v1/auth/refresh', _handleRefresh);
    r.post('/api/v1/auth/logout', _handleLogout);
  }

  /// POST /api/v1/auth/login
  Future<shelf.Response> _handleLogin(shelf.Request request) async {
    final body = getRequestBody(request);
    if (body == null) {
      return _error(400, 'Request body is required');
    }

    final email = body['email'] as String?;
    final password = body['password'] as String?;

    if (email == null || password == null) {
      return _error(400, 'Email and password are required');
    }

    final user = await _findUserByEmail(email);
    if (user == null) {
      return _error(401, 'Invalid credentials');
    }

    if (user['isActive'] != true) {
      return _error(403, 'Account is deactivated. Contact your administrator.');
    }

    final passwordHash = user['passwordHash'] as String;
    if (!_verifyPassword(password, passwordHash)) {
      return _error(401, 'Invalid credentials');
    }

    // Transparent upgrade: if this row still uses the legacy unsalted
    // SHA-256 format, re-hash it with salted PBKDF2 now that we've
    // confirmed the caller knows the real password.
    if (!passwordHash.startsWith('pbkdf2\$')) {
      try {
        final upgraded = _hashPassword(password);
        await _db.customStatement(
          'UPDATE server_users SET password_hash = ${Sql.str(upgraded)}, updated_at = ${Sql.str(DateTime.now().toIso8601String())} WHERE id = ${Sql.str(user['id'] as String)}',
        );
      } catch (_) {
        // Non-fatal: legacy verification still works next time.
      }
    }

    return _generateAuthResponse(user);
  }

  /// POST /api/v1/auth/pin-login
  Future<shelf.Response> _handlePinLogin(shelf.Request request) async {
    final body = getRequestBody(request);
    if (body == null) {
      return _error(400, 'Request body is required');
    }

    final pin = body['pin'] as String?;
    if (pin == null) {
      return _error(400, 'PIN is required');
    }

    await _ensureServerUsersTable();
    final result = await _db.customSelect(
      'SELECT * FROM server_users WHERE pin_hash IS NOT NULL',
    ).get();

    for (final row in result) {
      final pinHash = row.readNullable<String>('pin_hash');
      if (pinHash != null && _verifyPassword(pin, pinHash)) {
        final user = _rowToMap(row);
        if (user['isActive'] != true) {
          return _error(403, 'Account is deactivated. Contact your administrator.');
        }
        return _generateAuthResponse(user);
      }
    }

    return _error(401, 'Invalid PIN');
  }

  /// POST /api/v1/auth/offline-pin-login
  ///
  /// Verifies against `offline_pin_hash` — set on the real backend via
  /// POST /auth/offline-access-pin and pulled into this device via
  /// LocalServerService._syncOfflineDirectory. Distinct from
  /// [_handlePinLogin]'s `pin_hash`, which is this device's own local
  /// quick-unlock PIN and has nothing to do with other users.
  Future<shelf.Response> _handleOfflinePinLogin(shelf.Request request) async {
    final body = getRequestBody(request);
    if (body == null) {
      return _error(400, 'Request body is required');
    }

    final email = body['email'] as String?;
    final pin = body['pin'] as String?;
    if (email == null || pin == null) {
      return _error(400, 'Email and PIN are required');
    }

    final user = await _findUserByEmail(email);
    if (user == null) {
      return _error(401, 'Invalid credentials');
    }

    if (user['isActive'] != true) {
      return _error(403, 'Account is deactivated. Contact your administrator.');
    }

    final offlinePinHash = user['offlinePinHash'] as String?;
    if (offlinePinHash == null) {
      return _error(
        401,
        'This account has not set up offline access. Set an offline-access PIN in Settings while online first.',
      );
    }

    if (!_verifySaltedPin(pin, offlinePinHash)) {
      return _error(401, 'Invalid credentials');
    }

    return _generateAuthResponse(user);
  }

  /// POST /api/v1/auth/refresh
  Future<shelf.Response> _handleRefresh(shelf.Request request) async {
    final body = getRequestBody(request);
    if (body == null) {
      return _error(400, 'Request body is required');
    }

    final refreshToken = body['refreshToken'] as String?;
    if (refreshToken == null) {
      return _error(400, 'Refresh token is required');
    }

    await _ensureRefreshTokensTable();
    final tokenHash = AuthToken.hashRefreshToken(refreshToken);

    final result = await _db.customSelect(
      'SELECT * FROM server_refresh_tokens WHERE token_hash = ${Sql.str(tokenHash)} AND expires_at > ${Sql.str(DateTime.now().toIso8601String())}',
    ).get();

    if (result.isEmpty) {
      return _error(401, 'Invalid or expired refresh token');
    }

    final row = result.first;
    final userId = row.read<String>('user_id');

    // Delete old token
    await _db.customStatement(
      'DELETE FROM server_refresh_tokens WHERE token_hash = ${Sql.str(tokenHash)}',
    );

    // Get user
    final userResult = await _db.customSelect(
      'SELECT * FROM server_users WHERE id = ${Sql.str(userId)}',
    ).get();

    if (userResult.isEmpty) {
      return _error(401, 'User not found');
    }

    if (userResult.first.readNullable<int>('is_active') != 1) {
      return _error(403, 'Account is deactivated');
    }

    return _generateAuthResponse(_rowToMap(userResult.first));
  }

  /// POST /api/v1/auth/logout
  Future<shelf.Response> _handleLogout(shelf.Request request) async {
    final body = getRequestBody(request);
    final refreshToken = body?['refreshToken'] as String?;

    if (refreshToken != null) {
      await _ensureRefreshTokensTable();
      final tokenHash = AuthToken.hashRefreshToken(refreshToken);
      await _db.customStatement(
        'DELETE FROM server_refresh_tokens WHERE token_hash = ${Sql.str(tokenHash)}',
      );
    }

    return shelf.Response.ok(
      jsonEncode({'message': 'Logged out successfully'}),
      headers: {'content-type': 'application/json'},
    );
  }

  // ─── Internal helpers ───

  Future<Map<String, dynamic>?> _findUserByEmail(String email) async {
    await _ensureServerUsersTable();
    final result = await _db.customSelect(
      'SELECT * FROM server_users WHERE LOWER(email) = LOWER(${Sql.str(email)})',
    ).get();
    if (result.isEmpty) return null;
    return _rowToMap(result.first);
  }

  Future<shelf.Response> _generateAuthResponse(Map<String, dynamic> user) async {
    final userId = user['id'] as String;
    final role = (user['role'] as String?) ?? 'CASHIER';
    final tenantId = (user['tenantId'] as String?) ?? 'local';
    final branchId = user['branchId'] as String?;
    final permissions = (user['permissions'] as List<dynamic>?) ?? const [];

    // Generate tokens
    final accessToken = AuthToken.generate(
      userId: userId,
      role: role,
      tenantId: tenantId,
      branchId: branchId,
    );
    final refreshToken = AuthToken.generateRefreshToken();
    final refreshTokenHash = AuthToken.hashRefreshToken(refreshToken);

    // Store refresh token
    await _ensureRefreshTokensTable();
    await _db.customStatement(
      'INSERT INTO server_refresh_tokens (id, user_id, token_hash, expires_at, created_at) '
      'VALUES (${Sql.str(_uuid.v4())}, ${Sql.str(userId)}, ${Sql.str(refreshTokenHash)}, '
      '${Sql.str(DateTime.now().add(const Duration(days: 7)).toIso8601String())}, '
      '${Sql.str(DateTime.now().toIso8601String())})',
    );

    // Update last login
    await _db.customStatement(
      'UPDATE server_users SET last_login_at = ${Sql.str(DateTime.now().toIso8601String())} WHERE id = ${Sql.str(userId)}',
    );

    return shelf.Response.ok(
      jsonEncode({
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresIn': 28800, // 8 hours in seconds
        'user': {
          'id': userId,
          'email': user['email'],
          'firstName': user['firstName'],
          'lastName': user['lastName'],
          'role': role,
          'tenantId': tenantId,
          'branchId': branchId,
          'permissions': permissions,
          'branches': [
            {'id': branchId ?? '', 'name': 'Default Branch', 'isPrimary': true},
          ],
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Verifies a password against the stored `password_hash`.
  ///
  /// Accepts both hash formats for migration:
  /// - `pbkdf2$<iter>$<saltB64>$<hashB64>` — salted PBKDF2-HMAC-SHA256
  ///   (current, see [_hashPassword]),
  /// - bare SHA-256 hex — legacy rows, still matched so existing devices
  ///   keep working.
  ///
  /// A plain unsalted SHA-256 cracks instantly via rainbow tables if the
  /// SQLCipher database is ever extracted.
  bool _verifyPassword(String plainText, String hash) {
    if (hash.startsWith('pbkdf2\$')) {
      final parts = hash.split('\$'); // pbkdf2, iter, saltB64, hashB64
      if (parts.length != 4) return false;
      final iterations = int.tryParse(parts[1]) ?? 0;
      if (iterations < 1) return false;
      final salt = base64Url.decode(parts[2]);
      final derived = _pbkdf2Sha256(utf8.encode(plainText), salt, iterations, 32);
      return _constantTimeEquals(base64Url.encode(derived), parts[3]);
    }
    // Legacy unsalted SHA-256.
    final inputHash = sha256.convert(utf8.encode(plainText)).toString();
    return inputHash == hash;
  }

  /// Produces a salted PBKDF2-HMAC-SHA256 password hash:
  /// `pbkdf2$<iterations>$<saltB64>$<hashB64>` (100k iterations).
  String _hashPassword(String plainText) {
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => _secureRandom.nextInt(256)),
    );
    const iterations = 100000;
    final derived = _pbkdf2Sha256(utf8.encode(plainText), salt, iterations, 32);
    return 'pbkdf2\$$iterations\$${base64Url.encode(salt)}\$${base64Url.encode(derived)}';
  }

  /// Minimal PBKDF2-HMAC-SHA256 (RFC 2898) built on package:crypto, so no
  /// extra dependency is needed. [dkLen] is the derived-key length in bytes.
  static Uint8List _pbkdf2Sha256(
    List<int> password,
    List<int> salt,
    int iterations,
    int dkLen,
  ) {
    final hmac = Hmac(sha256, password);
    final blockCount = (dkLen + 31) ~/ 32; // ceil(dkLen / hLen)
    final out = BytesBuilder();

    for (var block = 1; block <= blockCount; block++) {
      // U1 = PRF(password, salt || INT_32_BE(block))
      final msg = BytesBuilder()
        ..add(salt)
        ..add([
          (block >>> 24) & 0xff,
          (block >>> 16) & 0xff,
          (block >>> 8) & 0xff,
          block & 0xff,
        ]);
      var u = hmac.convert(msg.toBytes()).bytes;
      final t = Uint8List.fromList(u);
      // U2..Uc
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
    }

    return Uint8List.fromList(out.toBytes()).sublist(0, dkLen);
  }

  static final Random _secureRandom = Random.secure();

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Verifies a PIN against the `salt:hash` scheme the backend computes
  /// in AuthService.setOfflineAccessPin (salted SHA-256, matching this
  /// exact `$salt:$pin` concatenation so both sides agree byte-for-byte).
  bool _verifySaltedPin(String pin, String saltedHash) {
    final parts = saltedHash.split(':');
    if (parts.length != 2) return false;
    final salt = parts[0];
    final expectedHash = parts[1];
    final actualHash = sha256.convert(utf8.encode('$salt:$pin')).toString();
    return actualHash == expectedHash;
  }

  Future<void> _ensureServerUsersTable() async {
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS server_users ('
      '  id TEXT PRIMARY KEY NOT NULL, '
      '  email TEXT NOT NULL UNIQUE, '
      '  password_hash TEXT NOT NULL DEFAULT \'\', '
      '  pin_hash TEXT, '
      '  offline_pin_hash TEXT, '
      '  first_name TEXT NOT NULL DEFAULT \'\', '
      '  last_name TEXT NOT NULL DEFAULT \'\', '
      '  role TEXT NOT NULL DEFAULT \'CASHIER\', '
      '  tenant_id TEXT NOT NULL DEFAULT \'local\', '
      '  branch_id TEXT, '
      '  is_active INTEGER NOT NULL DEFAULT 1, '
      '  last_login_at TEXT, '
      '  permissions_json TEXT, '
      '  created_at TEXT NOT NULL, '
      '  updated_at TEXT NOT NULL'
      ')',
    );
    // Additive migration for tables created before these columns existed —
    // CREATE TABLE IF NOT EXISTS above is a no-op on an existing table, so
    // new columns have to be added separately. SQLite has no "ADD COLUMN
    // IF NOT EXISTS", so a duplicate-column error here just means an
    // earlier run already added it.
    for (final columnDef in [
      'permissions_json TEXT',
      'offline_pin_hash TEXT',
    ]) {
      try {
        await _db.customStatement('ALTER TABLE server_users ADD COLUMN $columnDef');
      } catch (_) {
        // Column already exists — expected on every run after the first.
      }
    }
  }

  Future<void> _ensureRefreshTokensTable() async {
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS server_refresh_tokens ('
      '  id TEXT PRIMARY KEY NOT NULL, '
      '  user_id TEXT NOT NULL, '
      '  token_hash TEXT NOT NULL UNIQUE, '
      '  expires_at TEXT NOT NULL, '
      '  created_at TEXT NOT NULL'
      ')',
    );
  }

  Map<String, dynamic> _rowToMap(QueryRow row) {
    final permissionsJson = row.readNullable<String>('permissions_json');
    return {
      'id': row.read<String>('id'),
      'email': row.read<String>('email'),
      'passwordHash': row.read<String>('password_hash'),
      'pinHash': row.readNullable<String>('pin_hash'),
      'offlinePinHash': row.readNullable<String>('offline_pin_hash'),
      'firstName': row.read<String>('first_name'),
      'lastName': row.read<String>('last_name'),
      'role': row.read<String>('role'),
      'tenantId': row.read<String>('tenant_id'),
      'branchId': row.readNullable<String>('branch_id'),
      'isActive': row.read<int>('is_active') == 1,
      'lastLoginAt': row.readNullable<String>('last_login_at'),
      'permissions': permissionsJson != null
          ? (jsonDecode(permissionsJson) as List<dynamic>).cast<String>()
          : <String>[],
    };
  }

  shelf.Response _error(int statusCode, String message) {
    return shelf.Response(
      statusCode,
      body: jsonEncode({'error': message}),
      headers: {'content-type': 'application/json'},
    );
  }
}
