import 'dart:convert';

import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/server/routes/inventory_routes.dart';
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
  const branchId = 'branch-1';
  const staff = <String, dynamic>{
    'sub': 'staff-1',
    'role': 'CASHIER',
    'tenantId': 'tenant-1',
    'branchId': branchId,
  };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    database = AppDatabase.forTesting(NativeDatabase.memory(), storage);
    router = Router();
    InventoryRoutes(database).addRoutes(router);
  });

  tearDown(() async => database.close());

  Future<shelf.Response> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? user = staff,
  }) {
    final context = <String, Object?>{
      if (body != null) 'body': body,
      if (user != null) 'user': user,
    };
    return router.call(
      shelf.Request(method, Uri.parse('http://localhost$path'))
          .change(context: context),
    );
  }

  test('first list and stats load as empty after creating the local table',
      () async {
    final list = await call(
      'GET',
      '/api/v1/inventory/stock-requests?branchId=$branchId',
    );
    final listBody = jsonDecode(await list.readAsString()) as Map;
    expect(list.statusCode, 200);
    expect(listBody['items'], isEmpty);
    expect(listBody['total'], 0);

    final stats = await call(
      'GET',
      '/api/v1/inventory/stock-requests/stats/summary?branchId=$branchId',
    );
    final statsBody = jsonDecode(await stats.readAsString()) as Map;
    expect(stats.statusCode, 200);
    expect(statsBody['pending'], 0);
    expect(statsBody['urgent'], 0);
    expect(statsBody['total'], 0);
  });

  test('creation preserves fractional quantity and uses the signed-in user',
      () async {
    final created = await call(
      'POST',
      '/api/v1/inventory/stock-requests',
      body: {
        'branchId': branchId,
        'productId': 'product-1',
        'quantity': 1.25,
        'unit': 'kg',
        'requestedById': 'forged-user',
      },
    );
    expect(created.statusCode, 201);

    final list = await call(
      'GET',
      '/api/v1/inventory/stock-requests?branchId=$branchId',
    );
    final body = jsonDecode(await list.readAsString()) as Map;
    final item = (body['items'] as List).single as Map;
    expect(item['quantity'], 1.25);
    expect(item['requestedById'], 'staff-1');
  });

  test('staff can only edit and cancel their own pending requests', () async {
    final created = await call(
      'POST',
      '/api/v1/inventory/stock-requests',
      body: {
        'branchId': branchId,
        'productId': 'product-1',
        'quantity': 4,
      },
    );
    final createdBody = jsonDecode(await created.readAsString()) as Map;
    final id = createdBody['id'] as String;

    final otherStaff = await call(
      'PUT',
      '/api/v1/inventory/stock-requests/$id',
      body: {'quantity': 8},
      user: const {
        'sub': 'other-staff',
        'role': 'CASHIER',
        'tenantId': 'tenant-1',
        'branchId': branchId,
      },
    );
    expect(otherStaff.statusCode, 404);

    final updated = await call(
      'PUT',
      '/api/v1/inventory/stock-requests/$id',
      body: {'quantity': 2.5},
    );
    expect(updated.statusCode, 200);

    final resolvedByStaff = await call(
      'PUT',
      '/api/v1/inventory/stock-requests/$id/resolve',
      body: {'status': 'APPROVED'},
    );
    expect(resolvedByStaff.statusCode, 403);

    final cancelled = await call(
      'PUT',
      '/api/v1/inventory/stock-requests/$id/cancel',
    );
    expect(cancelled.statusCode, 200);
    final cancelAgain = await call(
      'PUT',
      '/api/v1/inventory/stock-requests/$id/cancel',
    );
    expect(cancelAgain.statusCode, 404);
  });

  test(
      'only a manager can resolve a request, and resolved requests stay closed',
      () async {
    final created = await call(
      'POST',
      '/api/v1/inventory/stock-requests',
      body: {
        'branchId': branchId,
        'productId': 'product-1',
        'quantity': 3,
      },
    );
    final createdBody = jsonDecode(await created.readAsString()) as Map;
    final id = createdBody['id'] as String;

    final invalidStatus = await call(
      'PUT',
      '/api/v1/inventory/stock-requests/$id/resolve',
      body: {'status': 'CANCELLED'},
      user: const {
        'sub': 'manager-1',
        'role': 'MANAGER',
        'tenantId': 'tenant-1',
        'branchId': branchId,
      },
    );
    expect(invalidStatus.statusCode, 400);

    final resolved = await call(
      'PUT',
      '/api/v1/inventory/stock-requests/$id/resolve',
      body: {'status': 'APPROVED'},
      user: const {
        'sub': 'manager-1',
        'role': 'MANAGER',
        'tenantId': 'tenant-1',
        'branchId': branchId,
      },
    );
    expect(resolved.statusCode, 200);

    final fulfilled = await call(
      'PUT',
      '/api/v1/inventory/stock-requests/$id/resolve',
      body: {'status': 'FULFILLED'},
      user: const {
        'sub': 'manager-1',
        'role': 'MANAGER',
        'tenantId': 'tenant-1',
        'branchId': branchId,
      },
    );
    expect(fulfilled.statusCode, 200);

    final secondResolution = await call(
      'PUT',
      '/api/v1/inventory/stock-requests/$id/resolve',
      body: {'status': 'REJECTED'},
      user: const {
        'sub': 'manager-1',
        'role': 'MANAGER',
        'tenantId': 'tenant-1',
        'branchId': branchId,
      },
    );
    expect(secondResolution.statusCode, 409);
  });

  test('database read failures are errors, never empty success responses',
      () async {
    await database.customStatement('CREATE TABLE stock_requests (id TEXT)');

    final list = await call('GET', '/api/v1/inventory/stock-requests');
    final listBody = jsonDecode(await list.readAsString()) as Map;
    expect(list.statusCode, 500);
    expect(listBody['error'], 'Could not load stock requests');

    final stats = await call(
      'GET',
      '/api/v1/inventory/stock-requests/stats/summary',
    );
    final statsBody = jsonDecode(await stats.readAsString()) as Map;
    expect(stats.statusCode, 500);
    expect(statsBody['error'], 'Could not load stock request statistics');
  });
}
