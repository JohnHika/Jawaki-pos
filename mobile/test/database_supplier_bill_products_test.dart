import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
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

  Future<void> bill(String id, double quantity) async {
    await database.recordSupplierInvoice(
      invoiceId: id,
      branchId: 'branch-1',
      supplierName: 'Mwalimu Wholesalers',
      terms: 'credit',
      paidAmount: 0,
      items: [
        {'name': 'Rice 5kg', 'quantity': quantity, 'unitCost': 4500},
      ],
    );
  }

  test('a supplier bill leaves the product list readable', () async {
    await bill('inv-1', 2);

    final products = await database.select(database.products).get();
    final categories = await database.select(database.categories).get();
    final stock = await database.select(database.localStock).get();

    expect(products.single.name, 'Rice 5kg');
    expect(products.single.createdAt.year, DateTime.now().year);
    expect(categories.map((c) => c.name), contains('Supplier Receipts'));
    expect(stock.single.quantity, 2);
  });

  test('a second bill adds to stock a product already has', () async {
    await bill('inv-1', 2);
    // A product first stocked from Products has a different stock row id.
    await database
        .customStatement("UPDATE local_stock SET id = 'from-products'");

    await bill('inv-2', 3);

    final stock = await database.select(database.localStock).get();
    expect(stock.single.id, 'from-products');
    expect(stock.single.quantity, 5);
  });

  test('repairs text dates left by older supplier bills', () async {
    await bill('inv-1', 2);
    await database.customStatement(
      "UPDATE products SET created_at = '2026-11-08T16:33:12.123456', "
      "updated_at = '2026-11-08T16:33:12.123456'",
    );
    await database.customStatement(
      "UPDATE local_stock SET updated_at = '2026-11-08T16:33:12.123456'",
    );
    await expectLater(
        database.select(database.products).get(), throwsA(anything));

    await database.repairTextDatesForTesting();

    final product = (await database.select(database.products).get()).single;
    expect(product.createdAt, DateTime(2026, 11, 8, 16, 33, 12));
    final stock = (await database.select(database.localStock).get()).single;
    expect(stock.updatedAt, DateTime(2026, 11, 8, 16, 33, 12));
  });
}
