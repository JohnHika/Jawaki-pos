import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v10 to v12 migration preserves stock and fractional precision',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    await storage.saveBranchId('branch-1');

    final executor = NativeDatabase.memory(
      setup: (database) {
        database.execute('''
          CREATE TABLE local_stock (
            id TEXT NOT NULL PRIMARY KEY,
            product_id TEXT NOT NULL,
            branch_id TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            min_quantity INTEGER NOT NULL DEFAULT 0,
            max_quantity INTEGER,
            updated_at INTEGER NOT NULL,
            UNIQUE(product_id, branch_id)
          )
        ''');
        database.execute('''
          INSERT INTO local_stock (
            id, product_id, branch_id, quantity, min_quantity, updated_at
          ) VALUES ('stock-1', 'product-1', 'branch-1', 240, 5, 0)
        ''');
        database.userVersion = 10;
      },
    );
    final database = AppDatabase.forTesting(executor, storage);
    addTearDown(database.close);

    final stock = await database.getProductStock('product-1', 'branch-1');
    expect(stock?.quantity, 240.0);
    expect(stock?.displayUnit, isNull);
    expect(stock?.displayQuantityPerUnit, isNull);
    expect(stock?.lastReceivedQuantity, isNull);
    expect(stock?.lastReceivedAt, isNull);

    final columns =
        await database.customSelect('PRAGMA table_info(local_stock)').get();
    final columnNames = columns.map((row) => row.read<String>('name')).toSet();
    expect(
      columnNames,
      containsAll(<String>{
        'display_unit',
        'display_quantity_per_unit',
        'last_received_quantity',
        'last_received_at',
      }),
    );

    await database.upsertAuthoritativeStock(
      productId: 'product-1',
      branchId: 'branch-1',
      quantity: 240.125,
      displayUnit: 'dozen',
      displayQuantityPerUnit: 12,
      lastReceivedQuantity: 20.010,
      lastReceivedAt: DateTime.utc(2026, 7, 30),
    );
    final watchedUpdate = database
        .watchStockForProduct('product-1')
        .firstWhere((stock) => stock?.quantity == 241.375);
    await database.upsertAuthoritativeStock(
      productId: 'product-1',
      branchId: 'branch-1',
      quantity: 241.375,
    );
    expect((await watchedUpdate)?.quantity, 241.375);

    final updated = await database.getProductStock('product-1', 'branch-1');
    expect(updated?.quantity, 241.375);
    expect(updated?.displayUnit, 'dozen');
    expect(updated?.displayQuantityPerUnit, 12);
    expect(updated?.lastReceivedQuantity, 20.010);
    expect(updated?.lastReceivedAt?.toUtc(), DateTime.utc(2026, 7, 30));

    await database.upsertCustomerById('customer-1', 'Same Name');
    await database.upsertCustomerById('customer-2', 'Same Name');
    await database.upsertCustomerById(
      'customer-1',
      'Renamed Customer',
      phone: '0712345678',
    );
    final customers = await database.getAllCustomers();
    expect(customers, hasLength(2));
    expect(
      customers.singleWhere((entry) => entry['id'] == 'customer-1'),
      containsPair('name', 'Renamed Customer'),
    );
    expect(
      customers.singleWhere((entry) => entry['id'] == 'customer-2'),
      containsPair('name', 'Same Name'),
    );
  });
}
