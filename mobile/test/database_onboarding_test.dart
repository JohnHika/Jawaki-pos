import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late AppDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialize();
    await storage.saveTenantId('tenant-1');
    await storage.saveBranchId('branch-1');
    database = AppDatabase.forTesting(NativeDatabase.memory(), storage);
  });

  tearDown(() async {
    await database.close();
  });

  test('notes the welcome tour for each person on their own', () async {
    expect(await database.hasSeenWelcome('owner-1'), isFalse);

    await database.noteWelcomeSeen('owner-1');

    expect(await database.hasSeenWelcome('owner-1'), isTrue);
    expect(await database.hasSeenWelcome('cashier-1'), isFalse);
  });

  test('keeps the welcome notes of one shop away from another', () async {
    await database.noteWelcomeSeen('owner-1');
    await storage.saveTenantId('tenant-2');

    expect(await database.hasSeenWelcome('owner-1'), isFalse);
  });

  test('a done step stays done and a skipped one can come back', () async {
    await database.noteSetupStep('receipt', notedBy: 'Owner');
    await database.noteSetupStep('receipt', status: 'SKIPPED');
    await database.noteSetupStep('logo', status: 'SKIPPED');

    expect(await database.getSetupNotes(),
        {'receipt': 'DONE', 'logo': 'SKIPPED'});

    await database.reopenSetupStep('logo');
    await database.reopenSetupStep('receipt');

    expect(await database.getSetupNotes(), {'receipt': 'DONE'});
  });

  test('a skipped step becomes done once it is done', () async {
    await database.noteSetupStep('staff', status: 'SKIPPED');
    await database.noteSetupStep('staff');

    expect(await database.getSetupNotes(), {'staff': 'DONE'});
  });

  test('refuses an unknown status', () async {
    expect(
      () => database.noteSetupStep('logo', status: 'MAYBE'),
      throwsArgumentError,
    );
  });

  test('counts completed sales in the shop only', () async {
    Future<void> sale(String id, String branch, String status) =>
        database.createPendingSale(
          PendingSalesCompanion.insert(
            id: id,
            receiptNumber: 'RCP-$id',
            subtotal: 100,
            total: 100,
            paymentMethod: 'CASH',
            cashierId: 'cashier-1',
            branchId: branch,
            status: Value(status),
            createdAt: DateTime.now(),
          ),
          const [],
        );

    expect(await database.getLocalCompletedSaleCount(), 0);
    await sale('s1', 'branch-1', 'COMPLETED');
    await sale('s2', 'branch-1', 'VOIDED');
    await sale('s3', 'branch-other', 'COMPLETED');

    expect(await database.getLocalCompletedSaleCount(), 1);
  });
}
