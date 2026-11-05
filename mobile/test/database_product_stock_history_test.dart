import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A product's page lists what happened to its stock: sales, deliveries and
/// count corrections, newest first. A correction keeps who, why and the old and
/// new numbers, so a count is never overwritten silently.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppDatabase> shop({bool tracked = true}) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    await storage.saveTenantId('tenant-1');
    await storage.saveBranchId('branch-1');
    final database = AppDatabase.forTesting(NativeDatabase.memory(), storage);
    addTearDown(database.close);
    final now = DateTime.now();
    await database.into(database.products).insert(
          ProductsCompanion.insert(
            id: 'unga',
            sku: 'UNGA-2KG',
            name: 'Unga Jogoo 2kg',
            categoryId: 'food',
            price: 195,
            trackInventory: Value(tracked),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return database;
  }

  Future<void> receive(AppDatabase database, double qty,
      {double? cost, String? supplier}) {
    return database.recordLocalStockReceipt(
      receiptId: 'r-${DateTime.now().microsecondsSinceEpoch}',
      productId: 'unga',
      branchId: 'branch-1',
      batches: [
        {
          'quantity': qty,
          'unit': 'piece',
          'unitsPerQuantity': 1.0,
          if (cost != null) 'costPrice': cost,
          if (supplier != null) 'supplierRef': supplier,
        },
      ],
      receivedAt: DateTime.now(),
    );
  }

  Future<void> sell(AppDatabase database, String id, double qty,
      {DateTime? at, bool voided = false}) async {
    await database.into(database.pendingSales).insert(
          PendingSalesCompanion.insert(
            id: id,
            receiptNumber: 'RCP-$id',
            subtotal: qty * 195,
            total: qty * 195,
            paymentMethod: 'CASH',
            cashierId: 'user-1',
            branchId: 'branch-1',
            status: const Value('COMPLETED'),
            createdAt: at ?? DateTime.now(),
            voidedAt: voided ? Value(DateTime.now()) : const Value.absent(),
          ),
        );
    await database.into(database.pendingSaleItems).insert(
          PendingSaleItemsCompanion.insert(
            saleId: id,
            productId: 'unga',
            productName: 'Unga Jogoo 2kg',
            sku: 'UNGA-2KG',
            quantity: qty,
            unitPrice: 195,
            total: qty * 195,
          ),
        );
  }

  test('history lists deliveries and sales, newest first, and skips voided sales',
      () async {
    final database = await shop();
    await receive(database, 24, cost: 160, supplier: 'Mama Njeri');
    await sell(database, 's1', 2, at: DateTime.now().add(const Duration(minutes: 1)));
    await sell(database, 's2', 5, voided: true);

    final history = await database.getLocalProductStockHistory('unga');

    expect(history.map((m) => m['kind']), ['sale', 'delivery']);
    expect(history.first['quantity'], -2.0);
    expect(history.last['quantity'], 24.0);
    expect(history.last['unitCost'], 160.0);
    expect(history.last['note'], 'Mama Njeri');
  });

  test('a correction sets the count and is kept with who and why', () async {
    final database = await shop();
    await receive(database, 24);

    await database.correctLocalStock(
      productId: 'unga',
      branchId: 'branch-1',
      countedQty: 20,
      reason: 'Torn bag',
      byName: 'John',
    );

    final stock = await database.getProductStock('unga', 'branch-1');
    expect(stock?.quantity, 20.0);
    final history = await database.getLocalProductStockHistory('unga');
    final correction = history.firstWhere((m) => m['kind'] == 'correction');
    expect(correction['quantity'], -4.0);
    expect(correction['note'], contains('John'));
    expect(correction['note'], contains('Torn bag'));
  });

  test('a correction to the same number leaves no record of a change', () async {
    final database = await shop();
    await receive(database, 10);
    await database.correctLocalStock(
      productId: 'unga',
      branchId: 'branch-1',
      countedQty: 10,
    );
    final history = await database.getLocalProductStockHistory('unga');
    expect(history.where((m) => m['kind'] == 'correction'), isEmpty);
  });

  test('a count below zero or for an uncounted product is refused', () async {
    final counted = await shop();
    expect(
      () => counted.correctLocalStock(
          productId: 'unga', branchId: 'branch-1', countedQty: -1),
      throwsArgumentError,
    );
    final uncounted = await shop(tracked: false);
    expect(
      () => uncounted.correctLocalStock(
          productId: 'unga', branchId: 'branch-1', countedQty: 3),
      throwsStateError,
    );
  });

  test('a buying price is remembered and can be cleared', () async {
    final database = await shop();
    await database.setProductCostPrice('unga', 160);
    expect((await database.getProduct('unga'))?.costPrice, 160.0);
    await database.setProductCostPrice('unga', null);
    expect((await database.getProduct('unga'))?.costPrice, isNull);
    expect(() => database.setProductCostPrice('unga', -1), throwsArgumentError);
  });
}
