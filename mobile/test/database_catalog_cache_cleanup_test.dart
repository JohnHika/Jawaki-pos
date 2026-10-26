import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logout clears catalog metadata but preserves offline work', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialize();
    await storage.saveTenantId('tenant-1');
    await storage.saveBranchId('branch-1');
    final database = AppDatabase.forTesting(NativeDatabase.memory(), storage);
    addTearDown(database.close);

    final now = DateTime.utc(2026, 10, 26);
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'category-1',
            name: 'Books',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.products).insert(
          ProductsCompanion.insert(
            id: 'product-1',
            sku: 'BOOK-1',
            name: 'Notebook',
            categoryId: 'category-1',
            price: 10,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.productPricingTiers).insert(
          ProductPricingTiersCompanion.insert(
            id: 'tier-1',
            productId: 'product-1',
            unit: 'dozen',
            quantityPerUnit: 12,
            price: 100,
          ),
        );
    await database.into(database.branchPrices).insert(
          BranchPricesCompanion.insert(
            id: 'branch-price-1',
            productId: 'product-1',
            branchId: 'branch-1',
            price: 9,
          ),
        );
    await database.into(database.localStock).insert(
          LocalStockCompanion.insert(
            id: 'stock-1',
            productId: 'product-1',
            branchId: 'branch-1',
            quantity: 20,
            updatedAt: now,
          ),
        );
    await database.into(database.favoriteProducts).insert(
          FavoriteProductsCompanion.insert(
            productId: 'product-1',
            addedAt: now,
          ),
        );
    await database.into(database.recentSearches).insert(
          RecentSearchesCompanion.insert(query: 'notebook', searchedAt: now),
        );

    await database.into(database.cartItems).insert(
          CartItemsCompanion.insert(
            productId: 'product-1',
            productName: 'Notebook',
            sku: 'BOOK-1',
            quantity: 1,
            unitPrice: 10,
            total: 10,
            addedAt: now,
          ),
        );
    await database.into(database.pendingSales).insert(
          PendingSalesCompanion.insert(
            id: 'offline-sale-1',
            receiptNumber: 'LOCAL-1',
            subtotal: 10,
            total: 10,
            paymentMethod: 'CASH',
            cashierId: 'cashier-1',
            branchId: 'branch-1',
            createdAt: now,
          ),
        );
    await database.into(database.syncQueue).insert(
          SyncQueueCompanion.insert(
            id: 'queue-1',
            entityTable: 'sales',
            recordId: 'offline-sale-1',
            action: 'create',
            eventType: 'SALE_CREATED',
            payload: '{}',
            deviceId: 'device-1',
            sequenceNumber: 1,
            createdAt: now,
          ),
        );

    await database.clearCatalogCache();

    expect(await database.select(database.products).get(), isEmpty);
    expect(await database.select(database.categories).get(), isEmpty);
    expect(await database.select(database.productPricingTiers).get(), isEmpty);
    expect(await database.select(database.branchPrices).get(), isEmpty);
    expect(await database.select(database.localStock).get(), isEmpty);
    expect(await database.select(database.favoriteProducts).get(), isEmpty);
    expect(await database.select(database.recentSearches).get(), isEmpty);
    expect(await database.select(database.cartItems).get(), hasLength(1));
    expect(await database.select(database.pendingSales).get(), hasLength(1));
    expect(await database.select(database.syncQueue).get(), hasLength(1));
  });
}
