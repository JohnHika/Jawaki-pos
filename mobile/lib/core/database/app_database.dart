import 'package:drift/drift.dart';
import '../services/storage_service.dart';

import 'secure_database.dart';

part 'app_database.g.dart';

// Categories table
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get parentId => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// Products table
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get sku => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get categoryId => text()();
  RealColumn get price => real()();
  RealColumn get costPrice => real().nullable()();
  TextColumn get unit => text().withDefault(const Constant('piece'))();
  TextColumn get imageUrl => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get trackInventory =>
      boolean().withDefault(const Constant(true))();
  IntColumn get minStock => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// Bulk-selling tiers beyond a product's base unit (e.g. dozen, carton,
// pallet) — any number per product, each with a real price and how many
// base units it represents. Replaces the old fixed secondary/tertiary
// columns, which capped every product at exactly 2 extra tiers.
class ProductPricingTiers extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get unit => text()();
  RealColumn get quantityPerUnit => real()();
  RealColumn get price => real()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// Branch price overrides
class BranchPrices extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get branchId => text()();
  RealColumn get price => real()();
  DateTimeColumn get effectiveFrom => dateTime().nullable()();
  DateTimeColumn get effectiveTo => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Local stock cache
class LocalStock extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get branchId => text()();
  IntColumn get quantity => integer()();
  IntColumn get minQuantity => integer().withDefault(const Constant(0))();
  IntColumn get maxQuantity => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// Daily purchases for simplified profit calculation
class DailyPurchases extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  RealColumn get amount => real()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get purchaseDate => dateTime()();
  BoolColumn get isManual => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// Cart items (current session)
class CartItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get productId => text()();
  TextColumn get productName => text()();
  TextColumn get sku => text()();
  IntColumn get quantity => integer()();
  RealColumn get unitPrice => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get addedAt => dateTime()();
}

// Pending sales (offline sales not yet synced)
class PendingSales extends Table {
  TextColumn get id => text()(); // UUID generated offline
  TextColumn get receiptNumber => text()();
  RealColumn get subtotal => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
  TextColumn get paymentMethod => text()();
  TextColumn get paymentReference => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get cashierId => text()();
  TextColumn get branchId => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('PENDING'))();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Pending sale items
class PendingSaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get saleId => text()();
  TextColumn get productId => text()();
  TextColumn get productName => text()();
  TextColumn get sku => text()();
  IntColumn get quantity => integer()();
  RealColumn get unitPrice => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
}

// Sync Queue (enhanced for offline->online sync with robust retry)
class SyncQueue extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get entityTable =>
      text()(); // e.g., 'sales', 'products', 'inventory'
  TextColumn get recordId => text()(); // ID of the record being synced
  TextColumn get action => text()(); // 'create', 'update', 'delete'
  TextColumn get eventType =>
      text()(); // e.g., 'SALE_CREATED', 'PRODUCT_UPDATED'
  TextColumn get payload => text()(); // JSON data
  TextColumn get deviceId => text()();
  TextColumn get userId => text().withDefault(const Constant(''))();
  IntColumn get sequenceNumber => integer()();
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending, synced, failed, conflict, resolved
  TextColumn get errorMessage => text().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  IntColumn get maxRetries => integer().withDefault(const Constant(3))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  TextColumn get serverId => text().nullable()(); // Server-side ID after sync
  DateTimeColumn get serverTimestamp => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Favorite products
class FavoriteProducts extends Table {
  TextColumn get productId => text()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {productId};
}

// Recent searches
class RecentSearches extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get query => text()();
  DateTimeColumn get searchedAt => dateTime()();
}

// Suppliers table
class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get contactName => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// Supplier payment records
class SupplierPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get supplierId => text()();
  RealColumn get amount => real()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get paymentDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  // Auto-increment ID is automatically the primary key
  // No need to override primaryKey when using autoIncrement()
}

@DriftDatabase(
  tables: [
    Categories,
    Products,
    ProductPricingTiers,
    BranchPrices,
    LocalStock,
    DailyPurchases,
    CartItems,
    PendingSales,
    PendingSaleItems,
    SyncQueue,
    FavoriteProducts,
    RecentSearches,
  ],
)
class AppDatabase extends _$AppDatabase {
  final StorageService _storage;

  // Use encrypted database connection
  AppDatabase(this._storage)
    : super(SecureDatabaseConnection.openSecureConnection());

  @override
  int get schemaVersion => 9; // v9: unlimited pricing tiers table, replaces fixed secondary/tertiary columns

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createSupplierFinanceTables();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // Drop old sync_queue table and recreate with new schema
        // Sync data is ephemeral, so it's safe to drop
        await m.drop(syncQueue);
        await m.createTable(syncQueue);
      }
      // (from < 3 used to add secondary/tertiary unit columns here — those
      // columns and their v7 price counterparts no longer exist; the v9
      // step below drops and recreates `products` unconditionally for any
      // pre-v9 database, so those intermediate column additions are moot.)
      if (from < 4) {
        // Normalize status values
        await customStatement("UPDATE sync_queue SET status = LOWER(status)");
        await customStatement(
          "UPDATE sync_queue SET status = 'synced' WHERE status = 'processed'",
        );
      }
      if (from < 5) {
        await _createSupplierFinanceTables();
      }
      if (from < 6) {
        await _createSupplierFinanceTables();
      }
      // (from < 7 used to add secondary/tertiary price columns here — see
      // note above; superseded by the v9 drop-and-recreate step.)
      if (from < 8) {
        // Add minStock so low-stock detection can use the real per-product
        // reorder threshold instead of a hardcoded fallback
        await m.addColumn(products, products.minStock);
      }
      if (from < 9) {
        // Replace the fixed secondary/tertiary pricing columns with a
        // proper pricing-tiers table (any number of tiers per product).
        // Products is purely a cache rebuilt from the API on every catalog
        // sync, so there's no local data to preserve -- drop and recreate
        // instead of a fragile per-column migration.
        await m.drop(products);
        await m.createTable(products);
        await m.createTable(productPricingTiers);
      }
    },
  );

  Future<void> _createSupplierFinanceTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        contact_name TEXT,
        email TEXT,
        phone TEXT,
        address TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS supplier_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id TEXT NOT NULL,
        amount REAL NOT NULL,
        notes TEXT,
        payment_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS supplier_invoices (
        id TEXT NOT NULL PRIMARY KEY,
        supplier_id TEXT NOT NULL,
        invoice_number TEXT,
        receipt_image_path TEXT,
        ocr_text TEXT,
        summary TEXT,
        terms TEXT NOT NULL DEFAULT 'pay_later',
        subtotal REAL NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        due_amount REAL NOT NULL DEFAULT 0,
        due_date TEXT,
        status TEXT NOT NULL DEFAULT 'open',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS supplier_invoice_items (
        id TEXT NOT NULL PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        product_id TEXT,
        product_name TEXT NOT NULL,
        sku TEXT,
        quantity REAL NOT NULL DEFAULT 1,
        unit TEXT NOT NULL DEFAULT 'piece',
        unit_cost REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        confidence REAL NOT NULL DEFAULT 0,
        raw_text TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES supplier_invoices(id)
      )
    ''');
  }

  // Categories
  Future<List<Category>> getAllCategories() => select(categories).get();

  Stream<List<Category>> watchAllCategories() => select(categories).watch();

  Future<void> insertCategories(List<CategoriesCompanion> items) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(categories, items);
    });
  }

  Future<void> replaceCategories(List<CategoriesCompanion> items) async {
    await transaction(() async {
      await delete(categories).go();
      if (items.isNotEmpty) {
        await batch((batch) {
          batch.insertAllOnConflictUpdate(categories, items);
        });
      }
    });
  }

  /// Wipes the locally cached product catalog and categories. Call this on
  /// logout so a different tenant/org logging in on the same device never
  /// sees a stale catalog left over from the previous session — the sync
  /// that repopulates these tables only runs once per app process, so
  /// without this the old tenant's products (or an empty cache from a
  /// failed sync) would otherwise persist indefinitely across a re-login.
  /// Deliberately scoped to products/categories only — cart, pending
  /// sales, and the sync queue must survive a logout since they may hold
  /// unsynced offline data.
  Future<void> clearCatalogCache() async {
    await transaction(() async {
      await delete(products).go();
      await delete(categories).go();
    });
  }

  // Products
  Future<List<Product>> getAllProducts() => select(products).get();

  Future<List<Product>> getProductsByCategory(String categoryId) {
    return (select(
      products,
    )..where((p) => p.categoryId.equals(categoryId))).get();
  }

  Future<List<Product>> searchProducts(String query) {
    return (select(
      products,
    )..where((p) => p.name.like('%$query%') | p.sku.like('%$query%'))).get();
  }

  Stream<List<Product>> watchAllProducts() => select(products).watch();

  Future<void> insertProducts(List<ProductsCompanion> items) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(products, items);
    });
  }

  Future<void> replaceProducts(List<ProductsCompanion> items) async {
    await transaction(() async {
      await delete(products).go();
      if (items.isNotEmpty) {
        await batch((batch) {
          batch.insertAllOnConflictUpdate(products, items);
        });
      }
    });
  }

  Future<Product?> getProduct(String id) {
    return (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  // Pricing tiers — any number of bulk-selling units beyond a product's
  // base unit (e.g. dozen, carton, pallet), each with a real price.
  Future<List<ProductPricingTier>> getPricingTiersForProduct(
    String productId,
  ) {
    return (select(productPricingTiers)
          ..where((t) => t.productId.equals(productId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Future<void> replacePricingTiersForProduct(
    String productId,
    List<ProductPricingTiersCompanion> tiers,
  ) async {
    await transaction(() async {
      await (delete(productPricingTiers)
            ..where((t) => t.productId.equals(productId)))
          .go();
      if (tiers.isNotEmpty) {
        await batch((batch) {
          batch.insertAllOnConflictUpdate(productPricingTiers, tiers);
        });
      }
    });
  }

  /// Replaces the entire local pricing-tiers cache in one pass — mirrors
  /// [replaceProducts]'s full delete+reinsert pattern, used during
  /// [syncCatalogCacheFromApi] since every product's tiers are refetched
  /// together, not one product at a time.
  Future<void> replaceAllPricingTiers(
    List<ProductPricingTiersCompanion> items,
  ) async {
    await transaction(() async {
      await delete(productPricingTiers).go();
      if (items.isNotEmpty) {
        await batch((batch) {
          batch.insertAllOnConflictUpdate(productPricingTiers, items);
        });
      }
    });
  }

  // Cart
  Future<List<CartItem>> getCartItems() => select(cartItems).get();

  Stream<List<CartItem>> watchCartItems() => select(cartItems).watch();

  Future<int> addToCart(CartItemsCompanion item) {
    return into(cartItems).insert(item);
  }

  Future<void> updateCartItem(int id, CartItemsCompanion item) {
    return (update(cartItems)..where((c) => c.id.equals(id))).write(item);
  }

  Future<void> removeFromCart(int id) {
    return (delete(cartItems)..where((c) => c.id.equals(id))).go();
  }

  Future<void> clearCart() {
    return delete(cartItems).go();
  }

  // Pending Sales
  Future<void> createPendingSale(
    PendingSalesCompanion sale,
    List<PendingSaleItemsCompanion> items,
  ) async {
    await transaction(() async {
      await into(pendingSales).insert(sale);
      await batch((batch) {
        batch.insertAll(pendingSaleItems, items);
      });
    });
  }

  Future<List<PendingSale>> getUnsyncedSales() {
    return (select(pendingSales)..where((s) => s.isSynced.equals(false))).get();
  }

  Future<void> markSaleAsSynced(String id) {
    return (update(pendingSales)..where((s) => s.id.equals(id))).write(
      PendingSalesCompanion(
        isSynced: const Value(true),
        syncedAt: Value(DateTime.now()),
      ),
    );
  }

  // Sync Events (Backwards compatibility - uses SyncQueue table)
  Future<void> addSyncEvent(SyncQueueCompanion event) {
    return into(syncQueue).insert(event);
  }

  Future<List<SyncQueueData>> getPendingSyncEvents() {
    return (select(syncQueue)
          ..where((e) => e.status.equals('pending'))
          ..orderBy([(e) => OrderingTerm.asc(e.sequenceNumber)]))
        .get();
  }

  Future<void> markSyncEventProcessed(String id) {
    return (update(syncQueue)..where((e) => e.id.equals(id))).write(
      SyncQueueCompanion(
        status: const Value('synced'),
        syncedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markSyncEventFailed(String id, String error) {
    return (update(syncQueue)..where((e) => e.id.equals(id))).write(
      SyncQueueCompanion(
        status: const Value('failed'),
        errorMessage: Value(error),
        retryCount: const Value(0),
      ),
    );
  }

  Future<int> getNextSequenceNumber() async {
    final result = await customSelect(
      'SELECT COALESCE(MAX(sequence_number), 0) + 1 as next FROM sync_queue',
    ).getSingle();
    return result.read<int>('next');
  }

  // ════════ SYNC QUEUE (Enhanced) ════════

  /// Add item to sync queue
  Future<void> addToSyncQueue(SyncQueueCompanion item) {
    return into(syncQueue).insert(item, mode: InsertMode.insertOrIgnore);
  }

  Future<SyncQueueData?> getSyncQueueItem(String id) {
    return (select(syncQueue)..where((q) => q.id.equals(id))).getSingleOrNull();
  }

  /// Get all pending sync items (not synced, not exceeding max retries)
  Future<List<SyncQueueData>> getPendingSyncQueue() {
    final now = DateTime.now();
    return (select(syncQueue)
          ..where(
            (q) =>
                q.status.equals('pending') &
                q.retryCount.isSmallerThan(q.maxRetries) &
                (q.nextRetryAt.isNull() |
                    q.nextRetryAt.isSmallerOrEqualValue(now)),
          )
          ..orderBy([(q) => OrderingTerm.asc(q.sequenceNumber)]))
        .get();
  }

  /// Get failed sync items that have exceeded max retries
  Future<List<SyncQueueData>> getFailedSyncQueue() {
    return (select(syncQueue)..where((q) => q.status.equals('failed'))).get();
  }

  Future<List<SyncQueueData>> getConflictSyncQueue() {
    return (select(syncQueue)..where((q) => q.status.equals('conflict'))).get();
  }

  /// Mark sync item as synced
  Future<void> markSyncQueueSynced(
    String id,
    String serverId,
    DateTime serverTimestamp,
  ) {
    return (update(syncQueue)..where((q) => q.id.equals(id))).write(
      SyncQueueCompanion(
        status: const Value('synced'),
        errorMessage: const Value(null),
        lastAttemptAt: Value(DateTime.now()),
        serverId: Value(serverId),
        serverTimestamp: Value(serverTimestamp),
        syncedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Schedule a retry for a sync item with exponential backoff.
  Future<void> scheduleSyncQueueRetry(
    String id,
    String errorMessage,
    Duration delay,
  ) async {
    final item = await (select(
      syncQueue,
    )..where((q) => q.id.equals(id))).getSingleOrNull();
    if (item == null) return;

    final newRetryCount = item.retryCount + 1;
    final hasRetriesRemaining = newRetryCount < item.maxRetries;

    await (update(syncQueue)..where((q) => q.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(hasRetriesRemaining ? 'pending' : 'failed'),
        errorMessage: Value(errorMessage),
        retryCount: Value(newRetryCount),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark sync item as terminally failed.
  Future<void> markSyncQueueFailed(String id, String errorMessage) {
    return (update(syncQueue)..where((q) => q.id.equals(id))).write(
      SyncQueueCompanion(
        status: const Value('failed'),
        errorMessage: Value(errorMessage),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark sync item as blocked by a data conflict.
  Future<void> markSyncQueueConflict(String id, String errorMessage) {
    return (update(syncQueue)..where((q) => q.id.equals(id))).write(
      SyncQueueCompanion(
        status: const Value('conflict'),
        errorMessage: Value(errorMessage),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark sync item as conflict-resolved.
  Future<void> markSyncQueueResolved(String id, {String? resolution}) {
    return (update(syncQueue)..where((q) => q.id.equals(id))).write(
      SyncQueueCompanion(
        status: const Value('resolved'),
        errorMessage: Value(resolution),
        lastAttemptAt: Value(DateTime.now()),
        syncedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Reset failed item for retry
  Future<void> resetSyncQueueItem(String id) {
    return (update(syncQueue)..where((q) => q.id.equals(id))).write(
      const SyncQueueCompanion(
        status: Value('pending'),
        retryCount: Value(0),
        errorMessage: Value(null),
      ),
    );
  }

  /// Delete synced items older than X days
  Future<int> cleanupSyncQueue({int olderThanDays = 30}) {
    final cutoffDate = DateTime.now().subtract(Duration(days: olderThanDays));
    return (delete(syncQueue)..where(
          (q) =>
              (q.status.equals('synced') | q.status.equals('resolved')) &
              q.syncedAt.isSmallerThanValue(cutoffDate),
        ))
        .go();
  }

  /// Get sync queue count by status
  Future<Map<String, int>> getSyncQueueStats() async {
    final pending = await (select(
      syncQueue,
    )..where((q) => q.status.equals('pending'))).get();

    final synced = await (select(
      syncQueue,
    )..where((q) => q.status.equals('synced'))).get();

    final failed = await (select(
      syncQueue,
    )..where((q) => q.status.equals('failed'))).get();

    final conflicts = await (select(
      syncQueue,
    )..where((q) => q.status.equals('conflict'))).get();

    final resolved = await (select(
      syncQueue,
    )..where((q) => q.status.equals('resolved'))).get();

    return {
      'pending': pending.length,
      'synced': synced.length,
      'failed': failed.length,
      'conflict': conflicts.length,
      'resolved': resolved.length,
      'total':
          pending.length +
          synced.length +
          failed.length +
          conflicts.length +
          resolved.length,
    };
  }

  /// Get next sequence number for sync queue
  Future<int> getNextSyncSequenceNumber() async {
    final result = await customSelect(
      'SELECT COALESCE(MAX(sequence_number), 0) + 1 as next FROM sync_queue',
    ).getSingle();
    return result.read<int>('next');
  }

  // Favorites
  Future<List<Product>> getFavoriteProducts() async {
    final favorites = await select(favoriteProducts).get();
    final productIds = favorites.map((f) => f.productId).toList();
    return (select(products)..where((p) => p.id.isIn(productIds))).get();
  }

  Stream<List<FavoriteProduct>> watchFavorites() =>
      select(favoriteProducts).watch();

  Future<void> addFavorite(String productId) {
    return into(favoriteProducts).insert(
      FavoriteProductsCompanion(
        productId: Value(productId),
        addedAt: Value(DateTime.now()),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> removeFavorite(String productId) {
    return (delete(
      favoriteProducts,
    )..where((f) => f.productId.equals(productId))).go();
  }

  Future<bool> isFavorite(String productId) async {
    final result = await (select(
      favoriteProducts,
    )..where((f) => f.productId.equals(productId))).getSingleOrNull();
    return result != null;
  }

  // Stock
  Future<void> updateLocalStock(List<LocalStockCompanion> items) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(localStock, items);
    });
  }

  // ===== DAILY PURCHASES (for simplified profit calculation) =====

  Future<void> addDailyPurchase({
    required String branchId,
    required double amount,
    String? description,
    bool isManual = false,
  }) async {
    await into(dailyPurchases).insert(
      DailyPurchasesCompanion.insert(
        id: 'purchase-${DateTime.now().millisecondsSinceEpoch}',
        branchId: branchId,
        amount: amount,
        description: Value(description),
        purchaseDate: DateTime.now(),
        isManual: Value(isManual),
      ),
    );
  }

  Future<List<DailyPurchase>> getTodaysPurchases(String branchId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

    return await (select(dailyPurchases)
          ..where(
            (p) =>
                p.branchId.equals(branchId) &
                p.purchaseDate.isBetweenValues(startOfDay, endOfDay),
          )
          ..orderBy([(p) => OrderingTerm.asc(p.purchaseDate)]))
        .get();
  }

  Future<double> getTodaysTotalPurchases(String branchId) async {
    final purchases = await getTodaysPurchases(branchId);
    double total = 0.0;
    for (final purchase in purchases) {
      total += purchase.amount;
    }
    return total;
  }

  Future<void> clearTodaysPurchases(String branchId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

    await (delete(dailyPurchases)..where(
          (p) =>
              p.branchId.equals(branchId) &
              p.purchaseDate.isBetweenValues(startOfDay, endOfDay),
        ))
        .go();
  }

  Future<void> setManualPurchaseAdjustment({
    required String branchId,
    required double amount,
    String? reason,
  }) async {
    await addDailyPurchase(
      branchId: branchId,
      amount: amount,
      description: 'Manual adjustment: ${reason ?? 'user override'}',
      isManual: true,
    );
  }

  // ===== END DAILY PURCHASES =====

  Future<LocalStockData?> getProductStock(
    String productId,
    String branchId,
  ) async {
    final rows =
        await (select(localStock)..where(
              (s) =>
                  s.productId.equals(productId) & s.branchId.equals(branchId),
            ))
            .get();
    return rows.isEmpty ? null : rows.first;
  }

  // Get stock for product using current branch
  Future<LocalStockData?> getStockForProduct(String productId) async {
    final branchId = _storage.getBranchId();
    if (branchId == null) {
      return null;
    }
    return getProductStock(productId, branchId);
  }

  Future<void> decrementStock(
    String productId,
    String branchId,
    int quantity,
  ) async {
    final stock = await getProductStock(productId, branchId);
    if (stock != null) {
      await (update(localStock)..where(
            (s) => s.productId.equals(productId) & s.branchId.equals(branchId),
          ))
          .write(
            LocalStockCompanion(
              quantity: Value(stock.quantity - quantity),
              updatedAt: Value(DateTime.now()),
            ),
          );
    } else {
      // No local stock row yet for this product+branch — previously this
      // silently did nothing, so the first sale of a product never showed
      // any deduction. Create the row so the sale is reflected; the next
      // catalog sync corrects it to the server's (now-decremented) value.
      final start = (0 - quantity);
      await into(localStock).insert(
        LocalStockCompanion.insert(
          id: 'stock-$branchId-$productId',
          productId: productId,
          branchId: branchId,
          quantity: start,
          updatedAt: DateTime.now(),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> transferStock({
    required String productId,
    required String fromBranchId,
    required String toBranchId,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Quantity must be greater than zero');
    }
    if (fromBranchId == toBranchId) {
      throw ArgumentError('Choose a different destination branch');
    }

    await transaction(() async {
      final fromStock = await getProductStock(productId, fromBranchId);
      final available = fromStock?.quantity ?? 0;
      if (available < quantity) {
        throw StateError('Only $available items available to transfer');
      }

      final now = DateTime.now();
      await (update(localStock)..where(
            (s) =>
                s.productId.equals(productId) & s.branchId.equals(fromBranchId),
          ))
          .write(
            LocalStockCompanion(
              quantity: Value(available - quantity),
              updatedAt: Value(now),
            ),
          );

      final toStock = await getProductStock(productId, toBranchId);
      if (toStock == null) {
        await into(localStock).insert(
          LocalStockCompanion.insert(
            id: 'stock-$toBranchId-$productId',
            productId: productId,
            branchId: toBranchId,
            quantity: quantity,
            updatedAt: now,
          ),
        );
      } else {
        await (update(localStock)..where(
              (s) =>
                  s.productId.equals(productId) & s.branchId.equals(toBranchId),
            ))
            .write(
              LocalStockCompanion(
                quantity: Value(toStock.quantity + quantity),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  // Low Stock Alerts — uses each product's real minStock (reorder threshold),
  // matching the backend's getLowStockAlerts() semantics (quantity <= minStock),
  // instead of a flat hardcoded threshold.
  Future<List<Map<String, dynamic>>> getLowStockProducts() async {
    final result = await customSelect(
      'SELECT p.id, p.name, p.sku, p.price, p.min_stock, p.unit, '
      'ls.quantity, ls.branch_id, '
      '(SELECT name FROM categories WHERE id = p.category_id) as category_name '
      'FROM products p '
      'LEFT JOIN local_stock ls ON ls.product_id = p.id '
      'WHERE p.is_active = 1 AND COALESCE(ls.quantity, 0) <= p.min_stock '
      'ORDER BY (p.min_stock - COALESCE(ls.quantity, 0)) DESC, p.name ASC',
    ).get();

    final rows = result
        .map(
          (r) => <String, dynamic>{
            'id': r.read<String>('id'),
            'name': r.read<String>('name'),
            'sku': r.read<String>('sku'),
            'price': r.read<double>('price'),
            'minStock': r.read<int>('min_stock'),
            'unit': r.read<String>('unit'),
            'quantity': r.readNullable<int>('quantity') ?? 0,
            'branchId': r.readNullable<String>('branch_id') ?? '',
            'categoryName':
                r.readNullable<String>('category_name') ?? 'Uncategorized',
          },
        )
        .toList();

    // Attach each product's real pricing tiers (any number) instead of the
    // old hardcoded secondary-only fields.
    for (final row in rows) {
      final tiers = await getPricingTiersForProduct(row['id'] as String);
      row['pricingTiers'] = tiers
          .map((t) => {
                'unit': t.unit,
                'quantityPerUnit': t.quantityPerUnit,
                'price': t.price,
              })
          .toList();
    }

    return rows;
  }

  Future<List<Map<String, dynamic>>> getOutOfStockProducts() async {
    final result = await customSelect(
      'SELECT p.id, p.name, p.sku, ls.quantity, ls.branch_id, '
      '(SELECT name FROM categories WHERE id = p.category_id) as category_name '
      'FROM products p '
      'LEFT JOIN local_stock ls ON ls.product_id = p.id '
      'WHERE p.is_active = 1 AND (ls.quantity IS NULL OR ls.quantity = 0) '
      'ORDER BY p.name ASC',
    ).get();

    return result
        .map(
          (r) => <String, dynamic>{
            'id': r.read<String>('id'),
            'name': r.read<String>('name'),
            'sku': r.read<String>('sku'),
            'quantity': r.readNullable<int>('quantity') ?? 0,
            'branchId': r.readNullable<String>('branch_id') ?? '',
            'categoryName':
                r.readNullable<String>('category_name') ?? 'Uncategorized',
          },
        )
        .toList();
  }

  // ════════ REPORTS QUERIES ════════

  /// All sales within [from]..[to].
  Future<List<PendingSale>> getSalesByDateRange(DateTime from, DateTime to) {
    return (select(pendingSales)
          ..where(
            (s) =>
                s.createdAt.isBiggerOrEqualValue(from) &
                s.createdAt.isSmallerOrEqualValue(to),
          )
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .get();
  }

  /// Stream of all sales (for real-time).
  Stream<List<PendingSale>> watchAllSales() => (select(
    pendingSales,
  )..orderBy([(s) => OrderingTerm.desc(s.createdAt)])).watch();

  /// Stream of today's sales.
  Stream<List<PendingSale>> watchTodaysSales() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return (select(pendingSales)
          ..where(
            (s) =>
                s.createdAt.isBiggerOrEqualValue(startOfDay) &
                s.createdAt.isSmallerThanValue(endOfDay),
          )
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .watch();
  }

  /// Get sales items for a specific sale.
  Future<List<PendingSaleItem>> getSaleItems(String saleId) {
    return (select(
      pendingSaleItems,
    )..where((i) => i.saleId.equals(saleId))).get();
  }

  Future<PendingSale?> getPendingSaleById(String saleId) {
    return (select(pendingSales)..where((s) => s.id.equals(saleId)))
        .getSingleOrNull();
  }

  /// Stream all sale items (for category / product reports).
  Stream<List<PendingSaleItem>> watchAllSaleItems() =>
      select(pendingSaleItems).watch();

  /// Sales grouped by payment method for a date range.
  Future<List<Map<String, dynamic>>> getSalesByPaymentMethod(
    DateTime from,
    DateTime to,
  ) async {
    final result = await customSelect(
      'SELECT payment_method, COUNT(*) as count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ? '
      'GROUP BY payment_method '
      'ORDER BY total_amount DESC',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result
        .map(
          (r) => {
            'paymentMethod': r.read<String>('payment_method'),
            'count': r.read<int>('count'),
            'totalAmount': r.read<double>('total_amount'),
          },
        )
        .toList();
  }

  /// Sales grouped by cashier for a date range.
  Future<List<Map<String, dynamic>>> getSalesByCashier(
    DateTime from,
    DateTime to,
  ) async {
    final result = await customSelect(
      'SELECT cashier_id, COUNT(*) as count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ? '
      'GROUP BY cashier_id '
      'ORDER BY total_amount DESC',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result
        .map(
          (r) => {
            'cashierId': r.read<String>('cashier_id'),
            'count': r.read<int>('count'),
            'totalAmount': r.read<double>('total_amount'),
          },
        )
        .toList();
  }

  /// Top selling products by quantity within a date range.
  Future<List<Map<String, dynamic>>> getTopProducts(
    DateTime from,
    DateTime to, {
    int limit = 20,
  }) async {
    final result = await customSelect(
      'SELECT psi.product_id, psi.product_name, SUM(psi.quantity) as total_qty, SUM(psi.total) as total_revenue '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ? '
      'GROUP BY psi.product_id, psi.product_name '
      'ORDER BY total_qty DESC '
      'LIMIT ?',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        Variable.withInt(limit),
      ],
    ).get();
    return result
        .map(
          (r) => {
            'productId': r.read<String>('product_id'),
            'productName': r.read<String>('product_name'),
            'totalQty': r.read<int>('total_qty'),
            'totalRevenue': r.read<double>('total_revenue'),
          },
        )
        .toList();
  }

  /// Sales grouped by category for a date range.
  Future<List<Map<String, dynamic>>> getSalesByCategory(
    DateTime from,
    DateTime to,
  ) async {
    final result = await customSelect(
      'SELECT c.id as category_id, c.name as category_name, '
      'COALESCE(SUM(psi.quantity), 0) as total_qty, COALESCE(SUM(psi.total), 0) as total_revenue '
      'FROM categories c '
      'LEFT JOIN products p ON p.category_id = c.id '
      'LEFT JOIN pending_sale_items psi ON psi.product_id = p.id '
      'LEFT JOIN pending_sales ps ON ps.id = psi.sale_id AND ps.created_at >= ? AND ps.created_at <= ? '
      'GROUP BY c.id, c.name '
      'ORDER BY total_revenue DESC',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result
        .map(
          (r) => {
            'categoryId': r.read<String>('category_id'),
            'categoryName': r.read<String>('category_name'),
            'totalQty': r.read<int>('total_qty'),
            'totalRevenue': r.read<double>('total_revenue'),
          },
        )
        .toList();
  }

  /// Inventory summary with product names & stock levels.
  Future<List<Map<String, dynamic>>> getInventoryReport() async {
    final branchId = _storage.getBranchId();
    final result = await customSelect(
      'SELECT p.id, p.name, p.sku, p.price, p.cost_price, '
      'COALESCE(ls.quantity, 0) as stock, p.min_stock as min_stock, '
      'c.name as category_name '
      'FROM products p '
      'LEFT JOIN local_stock ls ON ls.product_id = p.id '
      "${branchId == null ? '' : 'AND ls.branch_id = ? '}"
      'LEFT JOIN categories c ON c.id = p.category_id '
      'WHERE p.is_active = 1 '
      'ORDER BY stock ASC',
      variables: branchId == null ? [] : [Variable.withString(branchId)],
    ).get();
    return result
        .map(
          (r) => {
            'id': r.read<String>('id'),
            'name': r.read<String>('name'),
            'sku': r.read<String>('sku'),
            'price': r.read<double>('price'),
            'costPrice': r.readNullable<double>('cost_price') ?? 0.0,
            'stock': r.read<int>('stock'),
            'minStock': r.read<int>('min_stock'),
            'categoryName':
                r.readNullable<String>('category_name') ?? 'Uncategorised',
          },
        )
        .toList();
  }

  /// Dashboard summary: total sales, revenue, avg ticket for today.
  Future<Map<String, dynamic>> getDashboardSummary() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final result = await customSelect(
      'SELECT COALESCE(COUNT(*), 0) as count, COALESCE(SUM(total), 0) as revenue, '
      'COALESCE(AVG(total), 0) as avg_ticket '
      'FROM pending_sales WHERE created_at >= ? AND created_at < ?',
      variables: [
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
      ],
    ).getSingle();
    // Items sold today
    final itemsResult = await customSelect(
      'SELECT COALESCE(SUM(psi.quantity), 0) as items_sold '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at < ?',
      variables: [
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
      ],
    ).getSingle();
    return {
      'transactionCount': result.read<int>('count'),
      'totalRevenue': result.read<double>('revenue'),
      'avgTicket': result.read<double>('avg_ticket'),
      'itemsSold': itemsResult.read<int>('items_sold'),
    };
  }

  /// Weekly summary for analytics dashboard.
  Future<Map<String, dynamic>> getWeeklySummary(
    DateTime from,
    DateTime to,
  ) async {
    final result = await customSelect(
      'SELECT COALESCE(COUNT(*), 0) as count, COALESCE(SUM(total), 0) as revenue, '
      'COALESCE(AVG(total), 0) as avg_ticket '
      'FROM pending_sales WHERE created_at >= ? AND created_at <= ?',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).getSingle();
    final itemsResult = await customSelect(
      'SELECT COALESCE(SUM(psi.quantity), 0) as items_sold '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ?',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).getSingle();
    return {
      'transactionCount': result.read<int>('count'),
      'totalRevenue': result.read<double>('revenue'),
      'avgTicket': result.read<double>('avg_ticket'),
      'itemsSold': itemsResult.read<int>('items_sold'),
    };
  }

  /// Monthly summary for analytics dashboard.
  Future<Map<String, dynamic>> getMonthlySummary(
    DateTime from,
    DateTime to,
  ) async {
    final result = await customSelect(
      'SELECT COALESCE(COUNT(*), 0) as count, COALESCE(SUM(total), 0) as revenue, '
      'COALESCE(AVG(total), 0) as avg_ticket '
      'FROM pending_sales WHERE created_at >= ? AND created_at <= ?',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).getSingle();
    final itemsResult = await customSelect(
      'SELECT COALESCE(SUM(psi.quantity), 0) as items_sold '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ?',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).getSingle();
    return {
      'transactionCount': result.read<int>('count'),
      'totalRevenue': result.read<double>('revenue'),
      'avgTicket': result.read<double>('avg_ticket'),
      'itemsSold': itemsResult.read<int>('items_sold'),
    };
  }

  /// Hourly sales breakdown for a date range.
  Future<List<Map<String, dynamic>>> getHourlySales(
    DateTime from,
    DateTime to,
  ) async {
    final result = await customSelect(
      'SELECT strftime(\'%H\', created_at) as hour, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ? '
      'GROUP BY strftime(\'%H\', created_at) '
      'ORDER BY hour',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result
        .map(
          (r) => {
            'hour': r.read<String>('hour'),
            'transactionCount': r.read<int>('transaction_count'),
            'totalAmount': r.read<double>('total_amount'),
            'date': from.toIso8601String(),
          },
        )
        .toList();
  }

  /// Daily sales breakdown for a date range.
  Future<List<Map<String, dynamic>>> getDailySales(
    DateTime from,
    DateTime to,
  ) async {
    final result = await customSelect(
      'SELECT date(created_at) as date, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ? '
      'GROUP BY date(created_at) '
      'ORDER BY date',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result
        .map(
          (r) => {
            'date': r.read<String>('date'),
            'transactionCount': r.read<int>('transaction_count'),
            'totalAmount': r.read<double>('total_amount'),
          },
        )
        .toList();
  }

  /// Total items sold per day for a date range — used to derive a real
  /// sell-through rate (units/day) instead of a static estimate.
  Future<List<Map<String, dynamic>>> getDailyItemsSold(
    DateTime from,
    DateTime to,
  ) async {
    final result = await customSelect(
      'SELECT date(ps.created_at) as date, COALESCE(SUM(psi.quantity), 0) as items_sold '
      'FROM pending_sales ps '
      'INNER JOIN pending_sale_items psi ON psi.sale_id = ps.id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ? '
      'GROUP BY date(ps.created_at) '
      'ORDER BY date',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result
        .map(
          (r) => {
            'date': r.read<String>('date'),
            'itemsSold': r.read<int>('items_sold'),
          },
        )
        .toList();
  }

  /// Payment summary for analytics.
  Future<Map<String, dynamic>> getPaymentSummary(
    DateTime from,
    DateTime to,
  ) async {
    final result = await customSelect(
      'SELECT '
      'COUNT(*) as transaction_count, '
      'SUM(total) as total_amount, '
      'AVG(total) as avg_payment, '
      'SUM(CASE WHEN payment_method = \'cash\' THEN 1 ELSE 0 END) as cash_count, '
      'SUM(CASE WHEN payment_method LIKE \'%card%\' OR payment_method LIKE \'%credit%\' THEN 1 ELSE 0 END) as card_count, '
      'SUM(CASE WHEN payment_method LIKE \'%mpesa%\' OR payment_method LIKE \'%pesapal%\' OR payment_method LIKE \'%touristtap%\' THEN 1 ELSE 0 END) as digital_count '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ?',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).getSingle();
    return {
      'transactionCount': result.read<int>('transaction_count'),
      'totalAmount': result.read<double>('total_amount'),
      'avgPayment': result.read<double>('avg_payment'),
      'cashCount': result.read<int>('cash_count'),
      'cardCount': result.read<int>('card_count'),
      'digitalCount': result.read<int>('digital_count'),
    };
  }

  /// Peak hours analysis.
  Future<List<Map<String, dynamic>>> getPeakHours(
    DateTime from,
    DateTime to,
  ) async {
    final result = await customSelect(
      'SELECT strftime(\'%H\', created_at) as hour, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ? '
      'GROUP BY strftime(\'%H\', created_at) '
      'ORDER BY transaction_count DESC '
      'LIMIT 5',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result
        .map(
          (r) => {
            // strftime('%H', ...) returns a zero-padded string (e.g. "09"),
            // not an int — matches getHourlySales()'s read type above.
            'hour': int.parse(r.read<String>('hour')),
            'transactionCount': r.read<int>('transaction_count'),
            'totalAmount': r.read<double>('total_amount'),
          },
        )
        .toList();
  }

  /// Slow moving products (products with low sales).
  Future<List<Map<String, dynamic>>> getSlowMovingProducts(
    DateTime from,
    DateTime to, {
    int limit = 10,
  }) async {
    final result = await customSelect(
      'SELECT psi.product_id, psi.product_name, SUM(psi.quantity) as total_qty, SUM(psi.total) as total_revenue '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ? '
      'GROUP BY psi.product_id, psi.product_name '
      'HAVING total_qty < 5 '
      'ORDER BY total_qty ASC '
      'LIMIT ?',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        Variable.withInt(limit),
      ],
    ).get();
    return result
        .map(
          (r) => {
            'productId': r.read<String>('product_id'),
            'productName': r.read<String>('product_name'),
            'totalQty': r.read<int>('total_qty'),
            'totalRevenue': r.read<double>('total_revenue'),
          },
        )
        .toList();
  }

  // ════════ BRANCH MANAGEMENT ════════

  /// Get branches stored in a simple JSON table.
  Future<List<Map<String, dynamic>>> getBranches() async {
    try {
      final result = await customSelect(
        'SELECT * FROM branches ORDER BY created_at DESC',
      ).get();
      return result
          .map(
            (r) => {
              'id': r.read<String>('id'),
              'name': r.read<String>('name'),
              'location': r.read<String>('location'),
              'phone': r.readNullable<String>('phone') ?? '',
              'isActive': r.read<int>('is_active') == 1,
              'createdAt': r.read<String>('created_at'),
            },
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> createBranchesTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS branches ('
      '  id TEXT PRIMARY KEY NOT NULL, '
      '  name TEXT NOT NULL, '
      '  location TEXT NOT NULL, '
      '  phone TEXT, '
      '  is_active INTEGER NOT NULL DEFAULT 1, '
      '  created_at TEXT NOT NULL'
      ')',
    );
  }

  Future<void> insertBranch(
    String id,
    String name,
    String location,
    String phone,
  ) async {
    await createBranchesTable();
    await customInsert(
      'INSERT INTO branches (id, name, location, phone, is_active, created_at) '
      'VALUES (?, ?, ?, ?, 1, ?)',
      variables: [
        Variable.withString(id),
        Variable.withString(name),
        Variable.withString(location),
        Variable.withString(phone),
        Variable.withString(DateTime.now().toIso8601String()),
      ],
    );
  }

  Future<void> deleteBranch(String id) async {
    await customStatement('DELETE FROM branches WHERE id = ?', [
      Variable.withString(id),
    ]);
  }

  Future<void> updateBranch(
    String id,
    String name,
    String location,
    String phone,
  ) async {
    await customStatement(
      'UPDATE branches SET name = ?, location = ?, phone = ? WHERE id = ?',
      [
        Variable.withString(name),
        Variable.withString(location),
        Variable.withString(phone),
        Variable.withString(id),
      ],
    );
  }

  // ════════ CUSTOMERS ════════

  Future<void> createCustomersTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS customers ('
      '  id TEXT PRIMARY KEY NOT NULL, '
      '  name TEXT NOT NULL, '
      '  phone TEXT, '
      '  email TEXT, '
      '  location TEXT, '
      '  notes TEXT, '
      '  total_purchases INTEGER NOT NULL DEFAULT 0, '
      '  total_spent REAL NOT NULL DEFAULT 0, '
      '  last_purchase_at TEXT, '
      '  created_at TEXT NOT NULL, '
      '  balance REAL NOT NULL DEFAULT 0, '
      '  credit_limit REAL NOT NULL DEFAULT 0, '
      '  loyalty_points INTEGER NOT NULL DEFAULT 0'
      ')',
    );
    // customers existed before the `location` column was added — SQLite has
    // no ADD COLUMN IF NOT EXISTS, so add it defensively and ignore the
    // "duplicate column" error on installs that already have it.
    try {
      await customStatement('ALTER TABLE customers ADD COLUMN location TEXT');
    } catch (_) {
      // column already exists
    }
    await createCustomerInstallmentsTable();
  }

  /// Scheduled installment payments for a customer's credit balance, e.g.
  /// "KES 10,000 due tomorrow, KES 2,000 due in 2 days" after a bulk
  /// on-credit sale. Distinct from `balance` (the running total owed) so
  /// staff can see and follow up on each promised payment individually.
  Future<void> createCustomerInstallmentsTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS customer_installments ('
      '  id TEXT PRIMARY KEY NOT NULL, '
      '  customer_id TEXT NOT NULL, '
      '  amount REAL NOT NULL, '
      '  due_date TEXT NOT NULL, '
      '  note TEXT, '
      '  status TEXT NOT NULL DEFAULT \'pending\', ' // pending, paid, overdue
      '  created_at TEXT NOT NULL, '
      '  paid_at TEXT'
      ')',
    );
  }

  Future<String> addCustomerInstallment(
    String customerId,
    double amount,
    DateTime dueDate, {
    String? note,
  }) async {
    await createCustomerInstallmentsTable();
    final id = 'inst-${DateTime.now().microsecondsSinceEpoch}';
    await customInsert(
      'INSERT INTO customer_installments (id, customer_id, amount, due_date, note, status, created_at) '
      'VALUES (?, ?, ?, ?, ?, \'pending\', ?)',
      variables: [
        Variable.withString(id),
        Variable.withString(customerId),
        Variable.withReal(amount),
        Variable.withString(dueDate.toIso8601String()),
        Variable.withString(note ?? ''),
        Variable.withString(DateTime.now().toIso8601String()),
      ],
    );
    return id;
  }

  Future<List<Map<String, dynamic>>> getCustomerInstallments(
    String customerId,
  ) async {
    await createCustomerInstallmentsTable();
    final result = await customSelect(
      'SELECT * FROM customer_installments WHERE customer_id = ? ORDER BY due_date ASC',
      variables: [Variable.withString(customerId)],
    ).get();
    return result
        .map(
          (r) => <String, dynamic>{
            'id': r.read<String>('id'),
            'customerId': r.read<String>('customer_id'),
            'amount': r.read<double>('amount'),
            'dueDate': r.read<String>('due_date'),
            'note': r.readNullable<String>('note') ?? '',
            'status': r.read<String>('status'),
            'createdAt': r.read<String>('created_at'),
            'paidAt': r.readNullable<String>('paid_at'),
          },
        )
        .toList();
  }

  Future<void> markInstallmentPaid(String installmentId) async {
    await createCustomerInstallmentsTable();
    await customStatement(
      'UPDATE customer_installments SET status = \'paid\', paid_at = ? WHERE id = ?',
      [
        Variable.withString(DateTime.now().toIso8601String()),
        Variable.withString(installmentId),
      ],
    );
  }

  /// Installments past their due date and still unpaid, across all
  /// customers — used to surface who needs a follow-up call today.
  Future<List<Map<String, dynamic>>> getOverdueInstallments() async {
    await createCustomerInstallmentsTable();
    await createCustomersTable();
    final result = await customSelect(
      'SELECT ci.*, c.name as customer_name, c.phone as customer_phone '
      'FROM customer_installments ci '
      'JOIN customers c ON c.id = ci.customer_id '
      'WHERE ci.status = \'pending\' AND ci.due_date < ? '
      'ORDER BY ci.due_date ASC',
      variables: [Variable.withString(DateTime.now().toIso8601String())],
    ).get();
    return result
        .map(
          (r) => <String, dynamic>{
            'id': r.read<String>('id'),
            'customerId': r.read<String>('customer_id'),
            'customerName': r.read<String>('customer_name'),
            'customerPhone': r.readNullable<String>('customer_phone') ?? '',
            'amount': r.read<double>('amount'),
            'dueDate': r.read<String>('due_date'),
            'note': r.readNullable<String>('note') ?? '',
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    await createCustomersTable();
    final result = await customSelect(
      'SELECT * FROM customers WHERE name LIKE ? OR phone LIKE ? ORDER BY total_purchases DESC LIMIT 20',
      variables: [
        Variable.withString('%$query%'),
        Variable.withString('%$query%'),
      ],
    ).get();
    return result.map(_customerRowToMap).toList();
  }

  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    await createCustomersTable();
    final result = await customSelect(
      'SELECT * FROM customers ORDER BY name ASC',
    ).get();
    return result.map(_customerRowToMap).toList();
  }

  Future<Map<String, dynamic>?> getCustomer(String id) async {
    await createCustomersTable();
    final result = await customSelect(
      'SELECT * FROM customers WHERE id = ?',
      variables: [Variable.withString(id)],
    ).get();
    if (result.isEmpty) return null;
    return _customerRowToMap(result.first);
  }

  Map<String, dynamic> _customerRowToMap(QueryRow r) {
    return {
      'id': r.read<String>('id'),
      'name': r.read<String>('name'),
      'phone': r.readNullable<String>('phone') ?? '',
      'email': r.readNullable<String>('email') ?? '',
      'location': r.readNullable<String>('location') ?? '',
      'notes': r.readNullable<String>('notes') ?? '',
      'totalPurchases': r.read<int>('total_purchases'),
      'totalSpent': r.read<double>('total_spent'),
      'lastPurchaseAt': r.readNullable<String>('last_purchase_at'),
      'balance': r.read<double>('balance'),
      'creditLimit': r.read<double>('credit_limit'),
      'loyaltyPoints': r.read<int>('loyalty_points'),
    };
  }

  Future<String> insertOrGetCustomer(
    String id,
    String name, {
    String? phone,
    String? location,
    String? email,
    String? notes,
    double initialBalance = 0,
    double creditLimit = 0,
  }) async {
    await createCustomersTable();
    // Check if customer exists by name (case-insensitive)
    final existing = await customSelect(
      'SELECT id FROM customers WHERE LOWER(name) = LOWER(?)',
      variables: [Variable.withString(name)],
    ).get();
    if (existing.isNotEmpty) {
      final existingId = existing.first.read<String>('id');
      // Update contact/location details if provided
      if (phone != null && phone.isNotEmpty) {
        await customStatement('UPDATE customers SET phone = ? WHERE id = ?', [
          Variable.withString(phone),
          Variable.withString(existingId),
        ]);
      }
      if (location != null && location.isNotEmpty) {
        await customStatement(
          'UPDATE customers SET location = ? WHERE id = ?',
          [Variable.withString(location), Variable.withString(existingId)],
        );
      }
      return existingId;
    }
    // Insert new
    await customInsert(
      'INSERT INTO customers (id, name, phone, email, location, notes, total_purchases, total_spent, created_at, balance, credit_limit, loyalty_points) '
      'VALUES (?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?, 0)',
      variables: [
        Variable.withString(id),
        Variable.withString(name),
        Variable.withString(phone ?? ''),
        Variable.withString(email ?? ''),
        Variable.withString(location ?? ''),
        Variable.withString(notes ?? ''),
        Variable.withString(DateTime.now().toIso8601String()),
        Variable.withReal(initialBalance),
        Variable.withReal(creditLimit),
      ],
    );
    return id;
  }

  // Customer Debt/Balance Management
  Future<void> updateCustomerBalance(String customerId, double amount) async {
    await createCustomersTable();
    await customStatement(
      'UPDATE customers SET balance = balance + ? WHERE id = ?',
      [Variable.withReal(amount), Variable.withString(customerId)],
    );
  }

  Future<void> setCustomerBalance(String customerId, double amount) async {
    await createCustomersTable();
    await customStatement('UPDATE customers SET balance = ? WHERE id = ?', [
      Variable.withReal(amount),
      Variable.withString(customerId),
    ]);
  }

  Future<void> setCustomerCreditLimit(String customerId, double limit) async {
    await createCustomersTable();
    await customStatement(
      'UPDATE customers SET credit_limit = ? WHERE id = ?',
      [Variable.withReal(limit), Variable.withString(customerId)],
    );
  }

  Future<void> addLoyaltyPoints(String customerId, int points) async {
    await createCustomersTable();
    await customStatement(
      'UPDATE customers SET loyalty_points = loyalty_points + ? WHERE id = ?',
      [Variable.withInt(points), Variable.withString(customerId)],
    );
  }

  Future<void> redeemLoyaltyPoints(String customerId, int points) async {
    await createCustomersTable();
    await customStatement(
      'UPDATE customers SET loyalty_points = loyalty_points - ? WHERE id = ? AND loyalty_points >= ?',
      [
        Variable.withInt(points),
        Variable.withString(customerId),
        Variable.withInt(points),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getCustomersWithDebt() async {
    await createCustomersTable();
    final result = await customSelect(
      'SELECT * FROM customers WHERE balance > 0 ORDER BY balance DESC',
    ).get();
    return result
        .map(
          (r) => <String, dynamic>{
            'id': r.read<String>('id'),
            'name': r.read<String>('name'),
            'phone': r.readNullable<String>('phone') ?? '',
            'balance': r.read<double>('balance'),
            'creditLimit': r.read<double>('credit_limit'),
            'loyaltyPoints': r.read<int>('loyalty_points'),
          },
        )
        .toList();
  }

  Future<void> recordCustomerPurchase(String customerId, double amount) async {
    await createCustomersTable();
    await customStatement(
      'UPDATE customers SET total_purchases = total_purchases + 1, '
      'total_spent = total_spent + ?, last_purchase_at = ? WHERE id = ?',
      [
        Variable.withReal(amount),
        Variable.withString(DateTime.now().toIso8601String()),
        Variable.withString(customerId),
      ],
    );
  }

  /// Get top products a specific customer buys (AI recommendation).
  Future<List<Map<String, dynamic>>> getCustomerTopProducts(
    String customerId,
  ) async {
    final result = await customSelect(
      'SELECT psi.product_id, psi.product_name, SUM(psi.quantity) as total_qty, COUNT(*) as times_bought '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.customer_id = ? '
      'GROUP BY psi.product_id, psi.product_name '
      'ORDER BY total_qty DESC LIMIT 10',
      variables: [Variable.withString(customerId)],
    ).get();
    return result
        .map(
          (r) => <String, dynamic>{
            'productId': r.read<String>('product_id'),
            'productName': r.read<String>('product_name'),
            'totalQty': r.read<int>('total_qty'),
            'timesBought': r.read<int>('times_bought'),
          },
        )
        .toList();
  }

  // Single insert/update helpers
  Future<void> insertCategory(CategoriesCompanion item) {
    return into(categories).insert(item, mode: InsertMode.insertOrReplace);
  }

  Future<void> updateCategory(String id, CategoriesCompanion item) {
    return (update(categories)..where((c) => c.id.equals(id))).write(item);
  }

  Future<void> deleteCategory(String id) {
    return (delete(categories)..where((c) => c.id.equals(id))).go();
  }

  Future<Category?> getCategory(String id) {
    return (select(
      categories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertProduct(ProductsCompanion item) {
    return into(products).insert(item, mode: InsertMode.insertOrReplace);
  }

  Future<void> updateProduct(String id, ProductsCompanion item) {
    return (update(products)..where((p) => p.id.equals(id))).write(item);
  }

  Future<void> deleteProduct(String id) {
    return (delete(products)..where((p) => p.id.equals(id))).go();
  }

  Future<int> getProductCount() async {
    final result = await customSelect(
      'SELECT COUNT(*) as count FROM products',
    ).getSingle();
    return result.read<int>('count');
  }

  Future<int> getCategoryCount() async {
    final result = await customSelect(
      'SELECT COUNT(*) as count FROM categories',
    ).getSingle();
    return result.read<int>('count');
  }

  // ── Supplier Finance Tracking ──

  /// Add or update a supplier record
  Future<String> insertOrGetSupplier(
    String id,
    String name, {
    String? phone,
    String? email,
  }) async {
    final existing = await customSelect(
      'SELECT id FROM suppliers WHERE name = ? OR phone = ?',
      variables: [Variable.withString(name), Variable.withString(phone ?? '')],
    ).getSingleOrNull();

    if (existing != null) return existing.read<String>('id');

    final now = DateTime.now().toIso8601String();
    await customStatement(
      'INSERT OR IGNORE INTO suppliers (id, name, phone, email, is_active, created_at, updated_at) VALUES (?, ?, ?, ?, 1, ?, ?)',
      [id, name, phone, email, now, now],
    );
    return id;
  }

  /// Get all suppliers with their debt balances
  Future<List<Map<String, dynamic>>> getSupplierDebts() async {
    await _createSupplierFinanceTables();
    final result = await customSelect('''
      SELECT
        s.id, s.name, s.phone, s.email,
        COALESCE((SELECT SUM(si.total_amount) FROM supplier_invoices si WHERE si.supplier_id = s.id), 0) as total_invoiced,
        COALESCE((SELECT SUM(sp.amount) FROM supplier_payments sp WHERE sp.supplier_id = s.id), 0) as total_paid,
        (SELECT MAX(sp2.payment_date) FROM supplier_payments sp2 WHERE sp2.supplier_id = s.id) as last_payment_date,
        (SELECT COUNT(*) FROM supplier_invoices si2 WHERE si2.supplier_id = s.id) as invoice_count,
        (SELECT COUNT(*) FROM supplier_invoices si3
          WHERE si3.supplier_id = s.id
            AND si3.status != 'paid'
            AND si3.due_date IS NOT NULL
            AND si3.due_date < datetime('now')) as overdue_count
      FROM suppliers s
      WHERE s.is_active = 1
      GROUP BY s.id
      ORDER BY s.name ASC
    ''').get();

    return result
        .map(
          (row) => {
            'id': row.read<String>('id'),
            'name': row.read<String>('name'),
            'phone': row.read<String?>('phone') ?? '',
            'email': row.read<String?>('email') ?? '',
            'totalInvoiced': row.read<double?>('total_invoiced') ?? 0,
            'totalOwed':
                ((row.read<double?>('total_invoiced') ?? 0) -
                        (row.read<double?>('total_paid') ?? 0))
                    .clamp(0, double.infinity),
            'totalPaid': (row.read<double?>('total_paid') ?? 0),
            'lastPaymentDate': row.read<String?>('last_payment_date'),
            'invoiceCount': row.read<int?>('invoice_count') ?? 0,
            'overdueCount': row.read<int?>('overdue_count') ?? 0,
          },
        )
        .toList();
  }

  /// Record a payment to a supplier
  Future<void> recordSupplierPayment(
    String supplierId,
    double amount, {
    String? notes,
  }) async {
    await _createSupplierFinanceTables();
    final now = DateTime.now().toIso8601String();
    await customStatement(
      'INSERT INTO supplier_payments (supplier_id, amount, notes, payment_date, created_at) VALUES (?, ?, ?, ?, ?)',
      [supplierId, amount, notes, now, now],
    );
  }

  /// Get payment history for a supplier
  Future<List<Map<String, dynamic>>> getSupplierPaymentHistory(
    String supplierId,
  ) async {
    await _createSupplierFinanceTables();
    final result = await customSelect(
      'SELECT id, amount, notes, payment_date FROM supplier_payments WHERE supplier_id = ? ORDER BY payment_date DESC',
      variables: [Variable.withString(supplierId)],
    ).get();

    return result
        .map(
          (row) => {
            'id': row.read<int>('id'),
            'amount': row.read<double>('amount'),
            'notes': row.read<String?>('notes') ?? '',
            'paymentDate': row.read<String>('payment_date'),
          },
        )
        .toList();
  }

  /// Full snapshot of every locally-stored supplier + invoice (with line
  /// items) + payment, used once by the local-to-backend migration so
  /// pre-existing device-local debt records aren't silently dropped when
  /// the Finance screen switches to reading/writing through the API.
  Future<List<Map<String, dynamic>>> getAllLocalSupplierData() async {
    await _createSupplierFinanceTables();

    final suppliers = await customSelect('SELECT * FROM suppliers').get();
    final result = <Map<String, dynamic>>[];

    for (final supplierRow in suppliers) {
      final supplierId = supplierRow.read<String>('id');

      final invoiceRows = await customSelect(
        'SELECT * FROM supplier_invoices WHERE supplier_id = ?',
        variables: [Variable.withString(supplierId)],
      ).get();

      final invoices = <Map<String, dynamic>>[];
      for (final invoiceRow in invoiceRows) {
        final invoiceId = invoiceRow.read<String>('id');
        final itemRows = await customSelect(
          'SELECT * FROM supplier_invoice_items WHERE invoice_id = ?',
          variables: [Variable.withString(invoiceId)],
        ).get();

        invoices.add({
          'id': invoiceId,
          'invoiceNumber': invoiceRow.read<String?>('invoice_number'),
          'paidAmount': invoiceRow.read<double>('paid_amount'),
          'dueDate': invoiceRow.read<String?>('due_date'),
          'createdAt': invoiceRow.read<String>('created_at'),
          'items': itemRows
              .map((item) => {
                    'productName': item.read<String>('product_name'),
                    'quantity': item.read<double>('quantity'),
                    'unit': item.read<String>('unit'),
                    'unitCost': item.read<double>('unit_cost'),
                  })
              .toList(),
        });
      }

      final paymentRows = await customSelect(
        'SELECT * FROM supplier_payments WHERE supplier_id = ?',
        variables: [Variable.withString(supplierId)],
      ).get();

      result.add({
        'supplierName': supplierRow.read<String>('name'),
        'supplierPhone': supplierRow.read<String?>('phone'),
        'invoices': invoices,
        'payments': paymentRows
            .map((p) => {
                  'amount': p.read<double>('amount'),
                  'notes': p.read<String?>('notes'),
                })
            .toList(),
      });
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> getSupplierInvoices(
    String supplierId,
  ) async {
    await _createSupplierFinanceTables();
    final result = await customSelect(
      'SELECT * FROM supplier_invoices WHERE supplier_id = ? ORDER BY created_at DESC',
      variables: [Variable.withString(supplierId)],
    ).get();

    return result
        .map(
          (row) => {
            'id': row.read<String>('id'),
            'invoiceNumber': row.read<String?>('invoice_number') ?? '',
            'summary': row.read<String?>('summary') ?? '',
            'terms': row.read<String>('terms'),
            'totalAmount': row.read<double>('total_amount'),
            'dueAmount': row.read<double>('due_amount'),
            'paidAmount': row.read<double>('paid_amount'),
            'dueDate': row.read<String?>('due_date'),
            'status': row.read<String>('status'),
            'createdAt': row.read<String>('created_at'),
            'receiptImagePath': row.read<String?>('receipt_image_path'),
          },
        )
        .toList();
  }

  Future<String> recordSupplierInvoice({
    required String supplierName,
    String? phone,
    String? email,
    String? invoiceNumber,
    String? receiptImagePath,
    String? ocrText,
    String? summary,
    required String terms,
    required double paidAmount,
    DateTime? dueDate,
    required List<Map<String, dynamic>> items,
  }) async {
    await _createSupplierFinanceTables();
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final supplierId = await insertOrGetSupplier(
      'supplier-${now.microsecondsSinceEpoch}',
      supplierName,
      phone: phone,
      email: email,
    );
    final invoiceId = 'supplier-invoice-${now.microsecondsSinceEpoch}';
    final subtotal = items.fold<double>(
      0,
      (sum, item) => sum + ((item['lineTotal'] as num?)?.toDouble() ?? 0),
    );
    final total = subtotal;
    final due = (total - paidAmount).clamp(0, double.infinity).toDouble();
    final status = due <= 0 ? 'paid' : (paidAmount > 0 ? 'partial' : 'open');

    await transaction(() async {
      await customStatement(
        '''
        INSERT INTO supplier_invoices (
          id, supplier_id, invoice_number, receipt_image_path, ocr_text, summary,
          terms, subtotal, paid_amount, total_amount, due_amount, due_date,
          status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          invoiceId,
          supplierId,
          invoiceNumber,
          receiptImagePath,
          ocrText,
          summary,
          terms,
          subtotal,
          paidAmount,
          total,
          due,
          dueDate?.toIso8601String(),
          status,
          nowIso,
          nowIso,
        ],
      );

      final branchId = _storage.getBranchId() ?? 'branch-main';
      for (final item in items) {
        final name = ((item['name'] as String?) ?? '').trim();
        if (name.isEmpty) continue;
        final quantity = ((item['quantity'] as num?)?.toDouble() ?? 1)
            .clamp(0.001, double.infinity)
            .toDouble();
        final unitCost = ((item['unitCost'] as num?)?.toDouble() ?? 0)
            .clamp(0, double.infinity)
            .toDouble();
        final lineTotal =
            ((item['lineTotal'] as num?)?.toDouble() ?? (quantity * unitCost))
                .clamp(0, double.infinity)
                .toDouble();
        final sku = ((item['sku'] as String?)?.trim().isNotEmpty ?? false)
            ? (item['sku'] as String).trim()
            : _skuFromName(name);
        final productId = await _upsertProductFromSupplierItem(
          name: name,
          sku: sku,
          unitCost: unitCost,
          branchId: branchId,
          quantity: quantity,
          nowIso: nowIso,
        );

        await customStatement(
          '''
          INSERT INTO supplier_invoice_items (
            id, invoice_id, product_id, product_name, sku, quantity, unit,
            unit_cost, line_total, confidence, raw_text, created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            'supplier-invoice-item-${DateTime.now().microsecondsSinceEpoch}-${name.hashCode.abs()}',
            invoiceId,
            productId,
            name,
            sku,
            quantity,
            (item['unit'] as String?) ?? 'piece',
            unitCost,
            lineTotal,
            ((item['confidence'] as num?)?.toDouble() ?? 0),
            item['rawText'] as String?,
            nowIso,
          ],
        );
      }

      if (paidAmount > 0) {
        await recordSupplierPayment(
          supplierId,
          paidAmount,
          notes: 'Initial payment for invoice ${invoiceNumber ?? invoiceId}',
        );
      }
    });

    return invoiceId;
  }

  Future<String> _upsertProductFromSupplierItem({
    required String name,
    required String sku,
    required double unitCost,
    required String branchId,
    required double quantity,
    required String nowIso,
  }) async {
    final existing = await customSelect(
      'SELECT id FROM products WHERE LOWER(name) = LOWER(?) OR sku = ? LIMIT 1',
      variables: [Variable.withString(name), Variable.withString(sku)],
    ).getSingleOrNull();
    final productId =
        existing?.read<String>('id') ??
        'product-${DateTime.now().microsecondsSinceEpoch}-${sku.hashCode.abs()}';
    final categoryId = await _ensureDefaultCategory(nowIso);

    if (existing == null) {
      await customStatement(
        '''
        INSERT INTO products (
          id, sku, name, description, category_id, price, cost_price, unit,
          image_url, is_active, track_inventory, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'piece', NULL, 1, 1, ?, ?)
        ''',
        [
          productId,
          sku,
          name,
          'Created from supplier receipt scan',
          categoryId,
          unitCost,
          unitCost,
          nowIso,
          nowIso,
        ],
      );
    } else {
      await customStatement(
        'UPDATE products SET cost_price = ?, updated_at = ? WHERE id = ?',
        [unitCost, nowIso, productId],
      );
    }

    await customStatement(
      '''
      INSERT INTO local_stock (id, product_id, branch_id, quantity, min_quantity, updated_at)
      VALUES (?, ?, ?, ?, 0, ?)
      ON CONFLICT(id) DO UPDATE SET quantity = quantity + excluded.quantity, updated_at = excluded.updated_at
      ''',
      [
        'stock-$branchId-$productId',
        productId,
        branchId,
        quantity.round(),
        nowIso,
      ],
    );

    return productId;
  }

  Future<String> _ensureDefaultCategory(String nowIso) async {
    const id = 'category-supplier-receipts';
    await customStatement(
      '''
      INSERT OR IGNORE INTO categories (id, name, description, parent_id, image_url, sort_order, is_active, created_at, updated_at)
      VALUES (?, 'Supplier Receipts', 'Products created from scanned supplier receipts', NULL, NULL, 999, 1, ?, ?)
      ''',
      [id, nowIso, nowIso],
    );
    return id;
  }

  String _skuFromName(String name) {
    final cleaned = name
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final prefix = cleaned.isEmpty
        ? 'ITEM'
        : cleaned.split('-').take(3).join('-');
    return 'SUP-$prefix';
  }
}
