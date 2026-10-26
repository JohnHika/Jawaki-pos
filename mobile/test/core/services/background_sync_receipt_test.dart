import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/background_sync_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiClient {
  _FakeApi(this.response) : super(Dio());
  final Map<String, dynamic> response;

  @override
  Future<Map<String, dynamic>> pushSyncEvents(
    Map<String, dynamic> data, {
    String? expectedTenantId,
  }) async =>
      response;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a queued sale adopts the receipt number the server assigns', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    await storage.saveTenantId('tenant-1');
    await storage.saveBranchId('branch-1');
    final database =
        AppDatabase.forTesting(NativeDatabase.memory(), storage);
    addTearDown(database.close);

    await database.into(database.pendingSales).insert(
          PendingSalesCompanion.insert(
            id: 'local-sale-1',
            receiptNumber: 'RCP-OFFLINE-1',
            subtotal: 100,
            total: 100,
            paymentMethod: 'CASH',
            cashierId: 'user-1',
            branchId: 'branch-1',
            createdAt: DateTime.now(),
          ),
        );
    await database.addToSyncQueue(
      SyncQueueCompanion.insert(
        id: 'event-1',
        entityTable: 'sales',
        recordId: 'local-sale-1',
        action: 'create',
        eventType: 'SALE_CREATED',
        payload: '{"offlineId":"local-sale-1"}',
        deviceId: 'device-1',
        sequenceNumber: 1,
        createdAt: DateTime.now(),
      ),
    );

    final result = await BackgroundSyncService.processPendingQueue(
      database: database,
      apiClient: _FakeApi({
        'results': [
          {
            'eventId': 'event-1',
            'success': true,
            'serverId': 'server-sale-1',
            'receiptNumber': 'MAIN-20261016-0007',
          }
        ],
      }),
      expectedTenantId: 'tenant-1',
    );

    expect(result.successCount, 1);
    final sale = await (database.select(database.pendingSales)
          ..where((s) => s.id.equals('local-sale-1')))
        .getSingle();
    expect(sale.isSynced, isTrue);
    expect(sale.receiptNumber, 'MAIN-20261016-0007');
  });

  test('an older server without a receipt number keeps the local one',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    await storage.saveTenantId('tenant-1');
    await storage.saveBranchId('branch-1');
    final database =
        AppDatabase.forTesting(NativeDatabase.memory(), storage);
    addTearDown(database.close);

    await database.into(database.pendingSales).insert(
          PendingSalesCompanion.insert(
            id: 'local-sale-2',
            receiptNumber: 'RCP-OFFLINE-2',
            subtotal: 50,
            total: 50,
            paymentMethod: 'CASH',
            cashierId: 'user-1',
            branchId: 'branch-1',
            createdAt: DateTime.now(),
          ),
        );
    await database.addToSyncQueue(
      SyncQueueCompanion.insert(
        id: 'event-2',
        entityTable: 'sales',
        recordId: 'local-sale-2',
        action: 'create',
        eventType: 'SALE_CREATED',
        payload: '{"offlineId":"local-sale-2"}',
        deviceId: 'device-1',
        sequenceNumber: 2,
        createdAt: DateTime.now(),
      ),
    );

    await BackgroundSyncService.processPendingQueue(
      database: database,
      apiClient: _FakeApi({
        'results': [
          {'eventId': 'event-2', 'success': true, 'serverId': 'server-sale-2'}
        ],
      }),
      expectedTenantId: 'tenant-1',
    );

    final sale = await (database.select(database.pendingSales)
          ..where((s) => s.id.equals('local-sale-2')))
        .getSingle();
    expect(sale.isSynced, isTrue);
    expect(sale.receiptNumber, 'RCP-OFFLINE-2');
  });
}
