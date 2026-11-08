import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    await storage.saveTenantId('tenant-1');
    await storage.saveBranchId('branch-1');
    database = AppDatabase.forTesting(NativeDatabase.memory(), storage);
  });

  tearDown(() async {
    await database.close();
  });

  test('customer purchase history reads real dates and receipt numbers',
      () async {
    final customer =
        await database.insertOrGetCustomerWithStatus('c1', 'Mama Njeri');
    final soldAt = DateTime(2026, 11, 8, 23, 55);
    await database.createPendingSale(
      PendingSalesCompanion.insert(
        id: 'sale-1',
        receiptNumber: 'RCP-1794171326809',
        subtotal: 185,
        total: 185,
        paymentMethod: 'CREDIT',
        customerId: Value(customer.id),
        cashierId: 'cashier-1',
        branchId: 'branch-1',
        status: const Value('COMPLETED'),
        createdAt: soldAt,
      ),
      const [],
    );

    final rows = await database.getSalesForCustomer(customer.id);

    expect(rows, hasLength(1));
    expect(rows.single.read<String>('receipt_number'), 'RCP-1794171326809');
    final createdAt =
        DateTime.parse(rows.single.read<String>('created_at')).toLocal();
    expect(createdAt, soldAt);
  });
}
