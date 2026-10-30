import 'dart:convert';

import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/server/routes/desktop_link_routes.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/server/auth_token.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Router router;
  late List<Map<String, dynamic>> linkEvents;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    AuthToken.initSecret('test-secret');
    database = AppDatabase.forTesting(NativeDatabase.memory(), storage);
    // Same DDL AuthRoutes._ensureServerUsersTable creates.
    await database.customStatement(
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
    await database.customStatement(
      'INSERT INTO server_users '
      '(id, email, password_hash, pin_hash, first_name, last_name, role, '
      'tenant_id, is_active, permissions_json, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)',
      [
        'owner-1',
        'owner@shop.com',
        '',
        'abc123:def456', // salted pin hash; verified via helper below
        'Ada',
        'Obi',
        'ADMIN',
        'local',
        jsonEncode(['sales.view']),
        DateTime.now().toIso8601String(),
        DateTime.now().toIso8601String(),
      ],
    );
    linkEvents = [];
    router = Router();
    DesktopLinkRoutes(
      database,
      onRequest: linkEvents.add,
    ).addRoutes(router);
  });

  tearDown(() async => database.close());

  Future<shelf.Response> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic> user = const {
      'sub': 'owner-1',
      'tenantId': 'local',
      'role': 'ADMIN',
    },
  }) {
    return router.call(
      shelf.Request(method, Uri.parse('http://localhost$path')).change(
        context: {
          'body': body,
          'user': user,
        },
      ),
    );
  }

  /// Computes the salted PIN hash format AuthRoutes uses so approve-with-PIN
  /// can be exercised end to end.
  String saltedPinHash(String pin) {
    const salt = 'testsalt';
    final digest = sha256.convert(utf8.encode('$salt:$pin')).toString();
    return '$salt:$digest';
  }

  group('desktop link pairing', () {
    test('start creates a pending challenge with QR + code', () async {
      final res = await call('POST', '/api/v1/desktop-link/start',
          body: {'desktopName': 'Front Laptop'});
      expect(res.statusCode, 200);
      final data = jsonDecode(await res.readAsString()) as Map;
      expect(data['code'], matches(RegExp(r'^\d{6}$')));
      final qr = jsonDecode(data['qr'] as String) as Map;
      expect(qr['v'], 1);
      expect(qr['id'], data['linkId']);
      expect((qr['s'] as String).length, greaterThanOrEqualTo(32));
      expect(linkEvents, hasLength(1));
      expect(linkEvents.first['type'], 'desktop_link_request');
    });

    test('status starts pending then approves and claims', () async {
      final start = jsonDecode(
        await (await call('POST', '/api/v1/desktop-link/start',
                body: {'desktopName': 'Front Laptop'}))
            .readAsString(),
      ) as Map;

      final pending = jsonDecode(
        await (await call(
          'GET',
          '/api/v1/desktop-link/status?linkId=${start['linkId']}',
        )).readAsString(),
      ) as Map;
      expect(pending['status'], 'pending');

      final approve = await call('POST', '/api/v1/desktop-link/approve',
          body: {'code': start['code'], 'decision': 'approve'});
      expect(approve.statusCode, 200);

      final approved = jsonDecode(
        await (await call(
          'GET',
          '/api/v1/desktop-link/status?linkId=${start['linkId']}',
        )).readAsString(),
      ) as Map;
      expect(approved['status'], 'approved');
      expect(approved['account']['email'], 'owner@shop.com');

      final qr = jsonDecode(start['qr'] as String) as Map;
      final claim = await call('POST', '/api/v1/desktop-link/claim', body: {
        'linkId': start['linkId'],
        'secret': qr['s'],
      });
      expect(claim.statusCode, 200);
      final tokens = jsonDecode(await claim.readAsString()) as Map;
      expect(tokens['accessToken'], isNotEmpty);
      expect(tokens['refreshToken'], isNotEmpty);
      expect(tokens['user']['id'], 'owner-1');

      // Second claim must fail — one pairing, one session.
      final again = await call('POST', '/api/v1/desktop-link/claim', body: {
        'linkId': start['linkId'],
        'secret': qr['s'],
      });
      expect(again.statusCode, 410);
    });

    test('wrong claim secret burns an attempt but keeps the pairing',
        () async {
      final start = jsonDecode(
        await (await call('POST', '/api/v1/desktop-link/start', body: {}))
            .readAsString(),
      ) as Map;
      await call('POST', '/api/v1/desktop-link/approve',
          body: {'code': start['code']});

      final bad = await call('POST', '/api/v1/desktop-link/claim',
          body: {'linkId': start['linkId'], 'secret': 'wrong'});
      expect(bad.statusCode, 401);

      final qr = jsonDecode(start['qr'] as String) as Map;
      final good = await call('POST', '/api/v1/desktop-link/claim',
          body: {'linkId': start['linkId'], 'secret': qr['s']});
      expect(good.statusCode, 200);
    });

    test('deny blocks the desktop', () async {
      final start = jsonDecode(
        await (await call('POST', '/api/v1/desktop-link/start', body: {}))
            .readAsString(),
      ) as Map;
      await call('POST', '/api/v1/desktop-link/approve',
          body: {'code': start['code'], 'decision': 'deny'});

      final status = jsonDecode(
        await (await call(
          'GET',
          '/api/v1/desktop-link/status?linkId=${start['linkId']}',
        )).readAsString(),
      ) as Map;
      expect(status['status'], 'denied');

      final qr = jsonDecode(start['qr'] as String) as Map;
      final claim = await call('POST', '/api/v1/desktop-link/claim',
          body: {'linkId': start['linkId'], 'secret': qr['s']});
      expect(claim.statusCode, 409);
    });

    test('approve with the wrong code finds nothing', () async {
      final res = await call('POST', '/api/v1/desktop-link/approve',
          body: {'code': '000000'});
      expect(res.statusCode, 404);
    });

    test('approve in pin mode verifies the phone PIN', () async {
      final start = jsonDecode(
        await (await call('POST', '/api/v1/desktop-link/start', body: {}))
            .readAsString(),
      ) as Map;
      // Give the owner the known test PIN.
      await database.customStatement(
        'UPDATE server_users SET pin_hash = ? WHERE id = ?',
        [saltedPinHash('4321'), 'owner-1'],
      );

      final missing = await call('POST', '/api/v1/desktop-link/approve',
          body: {'code': start['code'], 'mode': 'pin'});
      expect(missing.statusCode, 400);

      final wrong = await call('POST', '/api/v1/desktop-link/approve',
          body: {'code': start['code'], 'mode': 'pin', 'pin': '0000'});
      expect(wrong.statusCode, 401);

      final right = await call('POST', '/api/v1/desktop-link/approve',
          body: {'code': start['code'], 'mode': 'pin', 'pin': '4321'});
      expect(right.statusCode, 200);

      final status = jsonDecode(
        await (await call(
          'GET',
          '/api/v1/desktop-link/status?linkId=${start['linkId']}',
        )).readAsString(),
      ) as Map;
      expect(status['status'], 'approved');
    });
  });
}
