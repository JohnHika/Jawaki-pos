import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A brand-new install builds its tables from the table definitions, not from
/// the upgrade steps. Saving stock relies on a unique (product, branch) pair, so
/// that pair has to be unique on a fresh install too. Receiving stock on a real
/// phone failed with "Could not receive stock" after the server had already
/// accepted it because the fresh table lacked that rule.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppDatabase> freshDatabase() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    await storage.saveBranchId('branch-1');
    final database =
        AppDatabase.forTesting(NativeDatabase.memory(), storage);
    addTearDown(database.close);
    return database;
  }

  test('saving stock twice on a fresh install updates the row', () async {
    final database = await freshDatabase();

    await database.upsertAuthoritativeStock(
      productId: 'product-1',
      branchId: 'branch-1',
      quantity: 20,
    );
    await database.upsertAuthoritativeStock(
      productId: 'product-1',
      branchId: 'branch-1',
      quantity: 40,
      lastReceivedQuantity: 20,
      lastReceivedAt: DateTime(2026, 10, 16),
    );

    final stock = await database.getProductStock('product-1', 'branch-1');
    expect(stock?.quantity, 40.0);
    expect(stock?.lastReceivedQuantity, 20.0);
  });

  test('adding to local stock on a fresh install accumulates', () async {
    final database = await freshDatabase();

    await database.incrementLocalStock(
      productId: 'product-1',
      branchId: 'branch-1',
      quantity: 5,
    );
    final total = await database.incrementLocalStock(
      productId: 'product-1',
      branchId: 'branch-1',
      quantity: 7,
    );

    expect(total, 12.0);
  });
}
