import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;
import 'package:uuid/uuid.dart';

import '../../../database/app_database.dart';
import '../auth_token.dart';
import '../middleware.dart';
import '../sql_helper.dart';


/// Desktop pairing routes for phone server mode.
///
/// A laptop joins the shop without typing a password: the desktop shows a
/// QR + 6-digit code, an approved phone user confirms the request (from the
/// in-app approval screen or its notification), and the desktop redeems
/// the pairing for the same tokens a normal phone login would mint.
///
/// Replaces the retired cloud flow:
///   POST /api/v1/desktop-link/start        (desktop → phone server)
///   GET  /api/v1/desktop-link/status       (desktop polls)
///   POST /api/v1/desktop-link/claim        (desktop redeems tokens)
///   POST /api/v1/desktop-link/approve      (phone, in-app: approve/deny)
///   POST /api/v1/desktop-link/pending      (phone, in-app: list waiting)
///
/// The claim secret lives only inside the QR payload + pending-row row on
/// the phone; nobody who can merely read the status endpoint can redeem.
class DesktopLinkRoutes {
  DesktopLinkRoutes(
    this._db, {
    void Function(Map<String, dynamic> event)? onRequest,
  }) : _onRequest = onRequest;

  final AppDatabase _db;
  final Uuid _uuid = const Uuid();
  static final Random _secureRandom = Random.secure();

  /// Notifies the running app (notification shade / approval screen) that
  /// a desktop is asking to pair.
  final void Function(Map<String, dynamic> event)? _onRequest;

  void addRoutes(Router r) {
    r.post('/api/v1/desktop-link/start', _handleStart);
    r.get('/api/v1/desktop-link/status', _handleStatus);
    r.post('/api/v1/desktop-link/claim', _handleClaim);
    // In-app, authenticated: the phone itself answers the request.
    r.post('/api/v1/desktop-link/approve', _handleApprove);
    r.get('/api/v1/desktop-link/pending', _handlePending);
  }

  /// POST /api/v1/desktop-link/start — desktop creates the challenge.
  Future<shelf.Response> _handleStart(shelf.Request request) async {
    final body = getRequestBody(request) ?? const {};
    final desktopName = (body['desktopName'] as String?)?.trim();
    final code = (100000 + _secureRandom.nextInt(900000)).toString();
    final secret = _randomSecret();
    final linkId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final expiresAt =
        DateTime.now().add(const Duration(minutes: 3)).toIso8601String();

    await _ensureTable();
    await _db.customStatement(
      'INSERT INTO desktop_link_challenges '
      '(id, code, claim_secret_hash, status, mode, desktop_name, ip, expires_at, created_at) '
      'VALUES (${Sql.str(linkId)}, ${Sql.str(code)}, ${Sql.str(_hashSecret(secret))}, '
      '${Sql.str('pending')}, ${Sql.str('approval')}, ${Sql.opt(desktopName)}, '
      '${Sql.str(request.headers['x-forwarded-for'] ?? 'local')}, '
      '${Sql.str(expiresAt)}, ${Sql.str(now)})',
    );

    _onRequest?.call({
      'type': 'desktop_link_request',
      'linkId': linkId,
      'code': code,
      'desktopName': desktopName ?? 'A computer',
    });

    return _ok({
      'linkId': linkId,
      'code': code,
      // QR content: compact JSON the phone scanner parses.
      'qr': jsonEncode({
        'v': 1,
        'id': linkId,
        'code': code,
        's': secret,
        'host': request.headers['host'] ?? '',
      }),
      'expiresAt': expiresAt,
    });
  }

  /// GET /api/v1/desktop-link/status?linkId=... — desktop polls.
  Future<shelf.Response> _handleStatus(shelf.Request request) async {
    final linkId = request.url.queryParameters['linkId'] ?? '';
    if (linkId.isEmpty) return _error(400, 'linkId is required');
    await _ensureTable();
    final rows = await _db.customSelect(
      'SELECT status, desktop_name, user_id, expires_at '
      'FROM desktop_link_challenges WHERE id = ${Sql.str(linkId)}',
    ).get();
    if (rows.isEmpty) return _error(404, 'Sign-in request not found');
    final row = rows.first;
    final status = row.read<String>('status');
    final expiresAt = row.read<String>('expires_at');
    final expired =
        status == 'pending' && DateTime.tryParse(expiresAt)?.isBefore(DateTime.now()) == true;
    final userId = row.readNullable<String>('user_id');
    Map<String, dynamic>? account;
    if (userId != null && status == 'approved') {
      account = await _accountSummary(userId);
    }
    return _ok({
      'status': expired ? 'expired' : status,
      if (account != null) 'account': account,
      'desktopName': row.readNullable<String>('desktop_name'),
      'expiresAt': expiresAt,
    });
  }

  /// POST /api/v1/desktop-link/claim — desktop redeems tokens.
  Future<shelf.Response> _handleClaim(shelf.Request request) async {
    final body = getRequestBody(request);
    final linkId = body?['linkId'] as String?;
    final secret = body?['secret'] as String?;
    if (linkId == null || secret == null || secret.isEmpty) {
      return _error(400, 'linkId and secret are required');
    }
    await _ensureTable();
    final rows = await _db.customSelect(
      'SELECT * FROM desktop_link_challenges WHERE id = ${Sql.str(linkId)}',
    ).get();
    if (rows.isEmpty) return _error(404, 'Sign-in request not found');
    final row = _challengeMap(rows.first);
    if ((row['attempts'] as int) >= 5) {
      return _error(403, 'Too many attempts — start a new sign-in');
    }
    if (!_constantTimeEquals(row['claimSecretHash'] as String, _hashSecret(secret))) {
      await _bumpAttempts(row['id'] as String);
      return _error(401, 'Invalid claim secret');
    }
    final status = row['status'] as String;
    if (status == 'claimed') {
      return _error(410, 'This sign-in was already used');
    }
    if (status != 'approved') {
      return _error(
        409,
        status == 'denied'
            ? 'The request was denied on the phone'
            : 'Not approved yet',
      );
    }

    final userId = row['userId'] as String?;
    final user = userId == null ? null : await _findUserById(userId);
    if (user == null || user['isActive'] != true) {
      return _error(401, 'Account is disabled');
    }

    // Mint exactly what a normal phone login returns so the rest of the
    // desktop app can treat this session like any other.
    final tokens = await _mintTokensForUser(user, row['desktopName'] as String?);

    // One challenge, one session: only flips while still approved.
    final claimed = await _db.customSelect(
      'UPDATE desktop_link_challenges SET status = \'claimed\', claimed_at = ${Sql.str(DateTime.now().toIso8601String())} '
      'WHERE id = ${Sql.str(row['id'] as String)} AND status = \'approved\' RETURNING id',
    ).get();
    if (claimed.isEmpty) {
      return _error(410, 'This sign-in was already used');
    }

    return _ok(tokens);
  }

  /// POST /api/v1/desktop-link/approve — phone user answers the request.
  Future<shelf.Response> _handleApprove(shelf.Request request) async {
    final user = getAuthUser(request);
    if (user == null) return _error(401, 'Sign in first');
    final body = getRequestBody(request);
    final code = (body?['code'] as String? ?? '').trim();
    final decision = body?['decision'] as String? ?? 'approve';
    final mode = body?['mode'] as String? ?? 'approval';

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      return _error(400, 'Enter the 6-digit code from the desktop');
    }
    if (decision != 'approve' && decision != 'deny') {
      return _error(400, 'decision must be approve or deny');
    }

    await _ensureTable();
    final rows = await _db.customSelect(
      'SELECT * FROM desktop_link_challenges '
      'WHERE code = ${Sql.str(code)} AND status = \'pending\' AND expires_at > ${Sql.str(DateTime.now().toIso8601String())}',
    ).get();
    if (rows.isEmpty) {
      return _error(
        404,
        'No waiting sign-in request matches that code — check the desktop screen',
      );
    }
    final row = _challengeMap(rows.first);

    if (decision == 'approve' && mode == 'pin') {
      final pin = body?['pin'] as String?;
      if (pin == null || RegExp(r'^\d{4,8}$').hasMatch(pin) == false) {
        return _error(400, 'Enter your 4–8 digit PIN to approve');
      }
      // Load fresh: the token context may not carry pinHash.
      final approver = await _findUserById(user['sub'] as String);
      final pinHash = approver?['pinHash'] as String?;
      if (approver == null || approver['isActive'] != true) {
        return _error(401, 'Account is disabled');
      }
      if (pinHash == null) {
        return _error(400, 'No PIN is set for this account — use approval mode');
      }
      if (!_verifySaltedPin(pin, pinHash)) {
        await _bumpAttempts(row['id'] as String);
        return _error(401, 'Incorrect PIN');
      }
    }

    final updated = await _db.customSelect(
      'UPDATE desktop_link_challenges '
      'SET status = ${Sql.str(decision == 'deny' ? 'denied' : 'approved')}, '
      'user_id = ${Sql.str(user['sub'] as String)}, '
      'approved_at = ${Sql.str(DateTime.now().toIso8601String())} '
      'WHERE id = ${Sql.str(row['id'] as String)} AND status = \'pending\' RETURNING id',
    ).get();
    if (updated.isEmpty) {
      return _error(409, 'This sign-in was already answered');
    }

    return _ok({
      'status': decision == 'deny' ? 'denied' : 'approved',
      'linkId': row['id'],
    });
  }

  /// GET /api/v1/desktop-link/pending — phone approval screen feed.
  Future<shelf.Response> _handlePending(shelf.Request request) async {
    getAuthUser(request); // authenticated, but any signed-in user may look
    await _ensureTable();
    final rows = await _db.customSelect(
      'SELECT id, code, desktop_name, created_at FROM desktop_link_challenges '
      'WHERE status = \'pending\' AND expires_at > ${Sql.str(DateTime.now().toIso8601String())} '
      'ORDER BY created_at DESC LIMIT 5',
    ).get();
    return _ok([
      for (final row in rows)
        {
          'id': row.read<String>('id'),
          'code': row.read<String>('code'),
          'desktopName': row.readNullable<String>('desktop_name'),
          'createdAt': row.read<String>('created_at'),
        },
    ]);
  }

  // ─── Internal helpers ───

  Future<Map<String, dynamic>?> _accountSummary(String userId) async {
    final user = await _findUserById(userId);
    if (user == null) return null;
    return {
      'firstName': user['firstName'],
      'lastName': user['lastName'],
      'email': user['email'],
      'role': user['role'],
    };
  }

  Future<Map<String, dynamic>?> _findUserById(String userId) async {
    await _ensureServerUsersTable();
    final rows = await _db.customSelect(
      'SELECT * FROM server_users WHERE id = ${Sql.str(userId)}',
    ).get();
    if (rows.isEmpty) return null;
    return _userMap(rows.first);
  }

  /// Mints the same token pair (and response shape) as a phone login.
  Future<Map<String, dynamic>> _mintTokensForUser(
    Map<String, dynamic> user,
    String? desktopName,
  ) async {
    final userId = user['id'] as String;
    final role = (user['role'] as String?) ?? 'CASHIER';
    final tenantId = (user['tenantId'] as String?) ?? 'local';
    final branchId = user['branchId'] as String?;
    final permissions = (user['permissions'] as List<dynamic>?) ?? const [];

    final accessToken = AuthToken.generate(
      userId: userId,
      role: role,
      tenantId: tenantId,
      branchId: branchId,
    );
    final refreshToken = AuthToken.generateRefreshToken();
    final refreshTokenHash = AuthToken.hashRefreshToken(refreshToken);

    await _ensureRefreshTokensTable();
    await _db.customStatement(
      'INSERT INTO server_refresh_tokens (id, user_id, token_hash, expires_at, created_at) '
      'VALUES (${Sql.str(_uuid.v4())}, ${Sql.str(userId)}, ${Sql.str(refreshTokenHash)}, '
      '${Sql.str(DateTime.now().add(const Duration(days: 7)).toIso8601String())}, '
      '${Sql.str(DateTime.now().toIso8601String())})',
    );

    await _db.customStatement(
      'UPDATE server_users SET last_login_at = ${Sql.str(DateTime.now().toIso8601String())} WHERE id = ${Sql.str(userId)}',
    );

    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresIn': 28800,
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
    };
  }

  Future<void> _bumpAttempts(String id) async {
    await _db.customStatement(
      'UPDATE desktop_link_challenges SET attempts = attempts + 1 WHERE id = ${Sql.str(id)}',
    );
  }

  Future<void> _ensureTable() async {
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS desktop_link_challenges ('
      '  id TEXT PRIMARY KEY NOT NULL, '
      '  code TEXT NOT NULL UNIQUE, '
      '  claim_secret_hash TEXT NOT NULL, '
      '  status TEXT NOT NULL DEFAULT \'pending\', '
      '  mode TEXT NOT NULL DEFAULT \'approval\', '
      '  desktop_name TEXT, '
      '  user_id TEXT, '
      '  ip TEXT, '
      '  attempts INTEGER NOT NULL DEFAULT 0, '
      '  expires_at TEXT NOT NULL, '
      '  approved_at TEXT, '
      '  claimed_at TEXT, '
      '  created_at TEXT NOT NULL'
      ')',
    );
    // Additive migrations for tables created by earlier builds.
    for (final columnDef in const <String>[]) {
      try {
        await _db.customStatement('ALTER TABLE desktop_link_challenges ADD COLUMN $columnDef');
      } catch (_) {
        // Column already exists — expected after the first run.
      }
    }
  }

  Future<void> _ensureServerUsersTable() async {
    // Matches the table AuthRoutes._ensureServerUsersTable creates, so both
    // route classes share the same shape.
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

  Map<String, dynamic> _challengeMap(QueryRow row) {
    return {
      'id': row.read<String>('id'),
      'code': row.read<String>('code'),
      'claimSecretHash': row.read<String>('claim_secret_hash'),
      'status': row.read<String>('status'),
      'mode': row.read<String>('mode'),
      'desktopName': row.readNullable<String>('desktop_name'),
      'userId': row.readNullable<String>('user_id'),
      'attempts': row.read<int>('attempts'),
      'expiresAt': row.read<String>('expires_at'),
    };
  }

  Map<String, dynamic> _userMap(QueryRow row) {
    final permissionsJson = row.readNullable<String>('permissions_json');
    return {
      'id': row.read<String>('id'),
      'email': row.read<String>('email'),
      'firstName': row.read<String>('first_name'),
      'lastName': row.read<String>('last_name'),
      'role': row.read<String>('role'),
      'tenantId': row.read<String>('tenant_id'),
      'branchId': row.readNullable<String>('branch_id'),
      'isActive': row.read<int>('is_active') == 1,
      'pinHash': row.readNullable<String>('pin_hash'),
      'permissions': permissionsJson != null
          ? (jsonDecode(permissionsJson) as List<dynamic>).cast<String>()
          : <String>[],
    };
  }

  /// Salted SHA-256 `salt:hash` — the same scheme the backend uses for
  /// offline access PINs so the phone verifies with its existing helper.
  bool _verifySaltedPin(String pin, String saltedHash) {
    final parts = saltedHash.split(':');
    if (parts.length != 2) return false;
    final salt = parts[0];
    final expectedHash = parts[1];
    final actualHash = sha256.convert(utf8.encode('$salt:$pin')).toString();
    return _constantTimeEquals(actualHash, expectedHash);
  }

  static String _hashSecret(String secret) =>
      sha256.convert(utf8.encode(secret)).toString();

  static String _randomSecret() {
    final bytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
    return base64Url.encode(bytes);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  shelf.Response _ok(Object payload) => shelf.Response.ok(
        jsonEncode(payload),
        headers: {'content-type': 'application/json'},
      );

  shelf.Response _error(int statusCode, String message) => shelf.Response(
        statusCode,
        body: jsonEncode({'message': message}),
        headers: {'content-type': 'application/json'},
      );
}
