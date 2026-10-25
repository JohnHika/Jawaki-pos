import 'dart:convert';

import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/server/routes/sync_routes.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Router router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    database = AppDatabase.forTesting(NativeDatabase.memory(), storage);
    router = Router();
    SyncRoutes(database).addRoutes(router);
  });

  tearDown(() async => database.close());

  Future<shelf.Response> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) {
    return router.call(
      shelf.Request(method, Uri.parse('http://localhost$path')).change(
        context: {if (body != null) 'body': body},
      ),
    );
  }

  test('empty sync queue reports real empty results', () async {
    final failed = await call('GET', '/api/v1/sync/failed');
    expect(failed.statusCode, 200);
    expect(jsonDecode(await failed.readAsString()), isEmpty);

    final retry = await call('POST', '/api/v1/sync/retry');
    expect(retry.statusCode, 200);
    expect((jsonDecode(await retry.readAsString()) as Map)['count'], 0);

    final pull = await call('POST', '/api/v1/sync/pull');
    expect(pull.statusCode, 200);
    expect((jsonDecode(await pull.readAsString()) as Map)['events'], isEmpty);
  });

  test('queue database failures are returned as errors, not empty success',
      () async {
    await database.customSelect('SELECT id FROM sync_queue LIMIT 0').get();
    await database.customStatement('DROP TABLE sync_queue');

    final failed = await call('GET', '/api/v1/sync/failed');
    expect(failed.statusCode, 500);
    expect(
      (jsonDecode(await failed.readAsString()) as Map)['error'],
      'Could not load failed sync items',
    );

    final retry = await call('POST', '/api/v1/sync/retry');
    expect(retry.statusCode, 500);
    expect(
      (jsonDecode(await retry.readAsString()) as Map)['error'],
      'Could not restart failed sync items',
    );

    final pull = await call(
      'POST',
      '/api/v1/sync/pull',
      body: {'since': DateTime(2026, 10, 1).toIso8601String()},
    );
    expect(pull.statusCode, 500);
    expect(
      (jsonDecode(await pull.readAsString()) as Map)['error'],
      'Could not load sync updates',
    );
  });

  test('pull rejects malformed timestamps rather than returning no changes',
      () async {
    final response = await call(
      'POST',
      '/api/v1/sync/pull',
      body: {'since': 'not-a-date'},
    );
    expect(response.statusCode, 400);
    expect(
      (jsonDecode(await response.readAsString()) as Map)['error'],
      'Sync timestamp must be a valid date',
    );
  });
}
