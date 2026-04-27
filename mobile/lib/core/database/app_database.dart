import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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
  TextColumn get secondaryUnit => text().nullable()();
  RealColumn get secondaryUnitQty => real().nullable()();
  TextColumn get tertiaryUnit => text().nullable()();
  RealColumn get tertiaryUnitQty => real().nullable()();
  TextColumn get imageUrl => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get trackInventory => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  
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
  TextColumn get entityTable => text()(); // e.g., 'sales', 'products', 'inventory'
  TextColumn get recordId => text()(); // ID of the record being synced
  TextColumn get action => text()(); // 'create', 'update', 'delete'
  TextColumn get eventType => text()(); // e.g., 'SALE_CREATED', 'PRODUCT_UPDATED'
  TextColumn get payload => text()(); // JSON data
  TextColumn get deviceId => text()();
  TextColumn get userId => text().withDefault(const Constant(''))();
  IntColumn get sequenceNumber => integer()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, synced, failed, conflict, resolved
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

@DriftDatabase(tables: [
  Categories,
  Products,
  BranchPrices,
  LocalStock,
  CartItems,
  PendingSales,
  PendingSaleItems,
  SyncQueue,
  FavoriteProducts,
  RecentSearches,
])
class AppDatabase extends _$AppDatabase {
  // Use encrypted database connection
  AppDatabase() : super(SecureDatabaseConnection.openSecureConnection());
  
  @override
  int get schemaVersion => 4; // Increment version for sync retry scheduling

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // Drop old sync_queue table and recreate with new schema
        // Sync data is ephemeral, so it's safe to drop
        await m.drop(syncQueue);
        await m.createTable(syncQueue);
      }
      if (from < 3) {
        // Add multi-unit fields to products table
        await m.addColumn(products, products.secondaryUnit);
        await m.addColumn(products, products.secondaryUnitQty);
        await m.addColumn(products, products.tertiaryUnit);
        await m.addColumn(products, products.tertiaryUnitQty);
      }
      if (from < 4) {
        // Normalize status values
        await customStatement(
          "UPDATE sync_queue SET status = LOWER(status)",
        );
        await customStatement(
          "UPDATE sync_queue SET status = 'synced' WHERE status = 'processed'",
        );
      }
    },
  );
  
  // Categories
  Future<List<Category>> getAllCategories() => select(categories).get();
  
  Stream<List<Category>> watchAllCategories() => select(categories).watch();
  
  Future<void> insertCategories(List<CategoriesCompanion> items) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(categories, items);
    });
  }
  
  // Products
  Future<List<Product>> getAllProducts() => select(products).get();
  
  Future<List<Product>> getProductsByCategory(String categoryId) {
    return (select(products)..where((p) => p.categoryId.equals(categoryId))).get();
  }
  
  Future<List<Product>> searchProducts(String query) {
    return (select(products)
      ..where((p) => p.name.like('%$query%') | p.sku.like('%$query%')))
      .get();
  }
  
  Stream<List<Product>> watchAllProducts() => select(products).watch();
  
  Future<void> insertProducts(List<ProductsCompanion> items) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(products, items);
    });
  }
  
  Future<Product?> getProduct(String id) {
    return (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();
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
    return (select(pendingSales)
      ..where((s) => s.isSynced.equals(false)))
      .get();
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
            (q.nextRetryAt.isNull() | q.nextRetryAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(q) => OrderingTerm.asc(q.sequenceNumber)]))
      .get();
  }

  /// Get failed sync items that have exceeded max retries
  Future<List<SyncQueueData>> getFailedSyncQueue() {
    return (select(syncQueue)
      ..where((q) => q.status.equals('failed')))
      .get();
  }

  Future<List<SyncQueueData>> getConflictSyncQueue() {
    return (select(syncQueue)
      ..where((q) => q.status.equals('conflict')))
      .get();
  }

  /// Mark sync item as synced
  Future<void> markSyncQueueSynced(String id, String serverId, DateTime serverTimestamp) {
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
    final item = await (select(syncQueue)..where((q) => q.id.equals(id))).getSingleOrNull();
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
    return (delete(syncQueue)
      ..where((q) => 
        (q.status.equals('synced') | q.status.equals('resolved')) & 
        q.syncedAt.isSmallerThanValue(cutoffDate)))
      .go();
  }

  /// Get sync queue count by status
  Future<Map<String, int>> getSyncQueueStats() async {
    final pending = await (select(syncQueue)
      ..where((q) => q.status.equals('pending')))
      .get();
    
    final synced = await (select(syncQueue)
      ..where((q) => q.status.equals('synced')))
      .get();
    
    final failed = await (select(syncQueue)
      ..where((q) => q.status.equals('failed')))
      .get();

    final conflicts = await (select(syncQueue)
      ..where((q) => q.status.equals('conflict')))
      .get();

    final resolved = await (select(syncQueue)
      ..where((q) => q.status.equals('resolved')))
      .get();

    return {
      'pending': pending.length,
      'synced': synced.length,
      'failed': failed.length,
      'conflict': conflicts.length,
      'resolved': resolved.length,
      'total': pending.length + synced.length + failed.length + conflicts.length + resolved.length,
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
  
  Stream<List<FavoriteProduct>> watchFavorites() => select(favoriteProducts).watch();
  
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
    return (delete(favoriteProducts)
      ..where((f) => f.productId.equals(productId)))
      .go();
  }
  
  Future<bool> isFavorite(String productId) async {
    final result = await (select(favoriteProducts)
      ..where((f) => f.productId.equals(productId)))
      .getSingleOrNull();
    return result != null;
  }
  
  // Stock
  Future<void> updateLocalStock(List<LocalStockCompanion> items) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(localStock, items);
    });
  }
  
  Future<LocalStockData?> getProductStock(String productId, String branchId) {
    return (select(localStock)
      ..where((s) => s.productId.equals(productId) & s.branchId.equals(branchId)))
      .getSingleOrNull();
  }
  
  Future<void> decrementStock(String productId, String branchId, int quantity) async {
    final stock = await getProductStock(productId, branchId);
    if (stock != null) {
      await (update(localStock)
        ..where((s) => s.productId.equals(productId) & s.branchId.equals(branchId)))
        .write(LocalStockCompanion(
          quantity: Value(stock.quantity - quantity),
          updatedAt: Value(DateTime.now()),
        ));
    }
  }

  // Low Stock Alerts
  Future<List<Map<String, dynamic>>> getLowStockProducts({int threshold = 10}) async {
    final result = await customSelect(
      'SELECT p.id, p.name, p.sku, p.price, ls.quantity, ls.branch_id, '
      '(SELECT name FROM categories WHERE id = p.category_id) as category_name '
      'FROM products p '
      'LEFT JOIN local_stock ls ON ls.product_id = p.id '
      'WHERE p.is_active = 1 AND (ls.quantity IS NULL OR ls.quantity < ?) '
      'ORDER BY ls.quantity ASC, p.name ASC',
      variables: [Variable.withInt(threshold)],
    ).get();

    return result.map((r) => <String, dynamic>{
      'id': r.read<String>('id'),
      'name': r.read<String>('name'),
      'sku': r.read<String>('sku'),
      'price': r.read<double>('price'),
      'quantity': r.readNullable<int>('quantity') ?? 0,
      'branchId': r.readNullable<String>('branch_id') ?? '',
      'categoryName': r.readNullable<String>('category_name') ?? 'Uncategorized',
    }).toList();
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

    return result.map((r) => <String, dynamic>{
      'id': r.read<String>('id'),
      'name': r.read<String>('name'),
      'sku': r.read<String>('sku'),
      'quantity': r.readNullable<int>('quantity') ?? 0,
      'branchId': r.readNullable<String>('branch_id') ?? '',
      'categoryName': r.readNullable<String>('category_name') ?? 'Uncategorized',
    }).toList();
  }

  // ════════ REPORTS QUERIES ════════

  /// All sales within [from]..[to].
  Future<List<PendingSale>> getSalesByDateRange(DateTime from, DateTime to) {
    return (select(pendingSales)
      ..where((s) => s.createdAt.isBiggerOrEqualValue(from) & s.createdAt.isSmallerOrEqualValue(to))
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
      .get();
  }

  /// Stream of all sales (for real-time).
  Stream<List<PendingSale>> watchAllSales() => (select(pendingSales)
    ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
    .watch();

  /// Stream of today's sales.
  Stream<List<PendingSale>> watchTodaysSales() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return (select(pendingSales)
      ..where((s) => s.createdAt.isBiggerOrEqualValue(startOfDay) & s.createdAt.isSmallerThanValue(endOfDay))
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
      .watch();
  }

  /// Get sales items for a specific sale.
  Future<List<PendingSaleItem>> getSaleItems(String saleId) {
    return (select(pendingSaleItems)..where((i) => i.saleId.equals(saleId))).get();
  }

  /// Stream all sale items (for category / product reports).
  Stream<List<PendingSaleItem>> watchAllSaleItems() => select(pendingSaleItems).watch();

  /// Sales grouped by payment method for a date range.
  Future<List<Map<String, dynamic>>> getSalesByPaymentMethod(DateTime from, DateTime to) async {
    final result = await customSelect(
      'SELECT payment_method, COUNT(*) as count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ? '
      'GROUP BY payment_method '
      'ORDER BY total_amount DESC',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result.map((r) => {
      'paymentMethod': r.read<String>('payment_method'),
      'count': r.read<int>('count'),
      'totalAmount': r.read<double>('total_amount'),
    }).toList();
  }

  /// Sales grouped by cashier for a date range.
  Future<List<Map<String, dynamic>>> getSalesByCashier(DateTime from, DateTime to) async {
    final result = await customSelect(
      'SELECT cashier_id, COUNT(*) as count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ? '
      'GROUP BY cashier_id '
      'ORDER BY total_amount DESC',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result.map((r) => {
      'cashierId': r.read<String>('cashier_id'),
      'count': r.read<int>('count'),
      'totalAmount': r.read<double>('total_amount'),
    }).toList();
  }

  /// Top selling products by quantity within a date range.
  Future<List<Map<String, dynamic>>> getTopProducts(DateTime from, DateTime to, {int limit = 20}) async {
    final result = await customSelect(
      'SELECT psi.product_id, psi.product_name, SUM(psi.quantity) as total_qty, SUM(psi.total) as total_revenue '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ? '
      'GROUP BY psi.product_id, psi.product_name '
      'ORDER BY total_qty DESC '
      'LIMIT ?',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to), Variable.withInt(limit)],
    ).get();
    return result.map((r) => {
      'productId': r.read<String>('product_id'),
      'productName': r.read<String>('product_name'),
      'totalQty': r.read<int>('total_qty'),
      'totalRevenue': r.read<double>('total_revenue'),
    }).toList();
  }

  /// Sales grouped by category for a date range.
  Future<List<Map<String, dynamic>>> getSalesByCategory(DateTime from, DateTime to) async {
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
    return result.map((r) => {
      'categoryId': r.read<String>('category_id'),
      'categoryName': r.read<String>('category_name'),
      'totalQty': r.read<int>('total_qty'),
      'totalRevenue': r.read<double>('total_revenue'),
    }).toList();
  }

  /// Inventory summary with product names & stock levels.
  Future<List<Map<String, dynamic>>> getInventoryReport() async {
    final result = await customSelect(
      'SELECT p.id, p.name, p.sku, p.price, p.cost_price, '
      'COALESCE(ls.quantity, 0) as stock, COALESCE(ls.min_quantity, 0) as min_stock, '
      'c.name as category_name '
      'FROM products p '
      'LEFT JOIN local_stock ls ON ls.product_id = p.id '
      'LEFT JOIN categories c ON c.id = p.category_id '
      'WHERE p.is_active = 1 '
      'ORDER BY stock ASC',
    ).get();
    return result.map((r) => {
      'id': r.read<String>('id'),
      'name': r.read<String>('name'),
      'sku': r.read<String>('sku'),
      'price': r.read<double>('price'),
      'costPrice': r.readNullable<double>('cost_price') ?? 0.0,
      'stock': r.read<int>('stock'),
      'minStock': r.read<int>('min_stock'),
      'categoryName': r.readNullable<String>('category_name') ?? 'Uncategorised',
    }).toList();
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
      variables: [Variable.withDateTime(startOfDay), Variable.withDateTime(endOfDay)],
    ).getSingle();
    // Items sold today
    final itemsResult = await customSelect(
      'SELECT COALESCE(SUM(psi.quantity), 0) as items_sold '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at < ?',
      variables: [Variable.withDateTime(startOfDay), Variable.withDateTime(endOfDay)],
    ).getSingle();
    return {
      'transactionCount': result.read<int>('count'),
      'totalRevenue': result.read<double>('revenue'),
      'avgTicket': result.read<double>('avg_ticket'),
      'itemsSold': itemsResult.read<int>('items_sold'),
    };
  }

  /// Weekly summary for analytics dashboard.
  Future<Map<String, dynamic>> getWeeklySummary(DateTime from, DateTime to) async {
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
  Future<Map<String, dynamic>> getMonthlySummary(DateTime from, DateTime to) async {
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
  Future<List<Map<String, dynamic>>> getHourlySales(DateTime from, DateTime to) async {
    final result = await customSelect(
      'SELECT strftime(\'%H\', created_at) as hour, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ? '
      'GROUP BY strftime(\'%H\', created_at) '
      'ORDER BY hour',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result.map((r) => {
      'hour': r.read<String>('hour'),
      'transactionCount': r.read<int>('transaction_count'),
      'totalAmount': r.read<double>('total_amount'),
      'date': from.toIso8601String(),
    }).toList();
  }

  /// Daily sales breakdown for a date range.
  Future<List<Map<String, dynamic>>> getDailySales(DateTime from, DateTime to) async {
    final result = await customSelect(
      'SELECT date(created_at) as date, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ? '
      'GROUP BY date(created_at) '
      'ORDER BY date',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result.map((r) => {
      'date': r.read<String>('date'),
      'transactionCount': r.read<int>('transaction_count'),
      'totalAmount': r.read<double>('total_amount'),
    }).toList();
  }

  /// Payment summary for analytics.
  Future<Map<String, dynamic>> getPaymentSummary(DateTime from, DateTime to) async {
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
  Future<List<Map<String, dynamic>>> getPeakHours(DateTime from, DateTime to) async {
    final result = await customSelect(
      'SELECT strftime(\'%H\', created_at) as hour, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ? '
      'GROUP BY strftime(\'%H\', created_at) '
      'ORDER BY transaction_count DESC '
      'LIMIT 5',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
    ).get();
    return result.map((r) => {
      'hour': r.read<int>('hour'),
      'transactionCount': r.read<int>('transaction_count'),
      'totalAmount': r.read<double>('total_amount'),
    }).toList();
  }

  /// Slow moving products (products with low sales).
  Future<List<Map<String, dynamic>>> getSlowMovingProducts(DateTime from, DateTime to, {int limit = 10}) async {
    final result = await customSelect(
      'SELECT psi.product_id, psi.product_name, SUM(psi.quantity) as total_qty, SUM(psi.total) as total_revenue '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ? '
      'GROUP BY psi.product_id, psi.product_name '
      'HAVING total_qty < 5 '
      'ORDER BY total_qty ASC '
      'LIMIT ?',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to), Variable.withInt(limit)],
    ).get();
    return result.map((r) => {
      'productId': r.read<String>('product_id'),
      'productName': r.read<String>('product_name'),
      'totalQty': r.read<int>('total_qty'),
      'totalRevenue': r.read<double>('total_revenue'),
    }).toList();
  }

  // ════════ BRANCH MANAGEMENT ════════

  /// Get branches stored in a simple JSON table.
  Future<List<Map<String, dynamic>>> getBranches() async {
    try {
      final result = await customSelect(
        'SELECT * FROM branches ORDER BY created_at DESC',
      ).get();
      return result.map((r) => {
        'id': r.read<String>('id'),
        'name': r.read<String>('name'),
        'location': r.read<String>('location'),
        'phone': r.readNullable<String>('phone') ?? '',
        'isActive': r.read<int>('is_active') == 1,
        'createdAt': r.read<String>('created_at'),
      }).toList();
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

  Future<void> insertBranch(String id, String name, String location, String phone) async {
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
    await customStatement('DELETE FROM branches WHERE id = ?',
      [Variable.withString(id)]);
  }

  Future<void> updateBranch(String id, String name, String location, String phone) async {
    await customStatement(
      'UPDATE branches SET name = ?, location = ?, phone = ? WHERE id = ?',
      [Variable.withString(name), Variable.withString(location), Variable.withString(phone), Variable.withString(id)],
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
  }

  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    await createCustomersTable();
    final result = await customSelect(
      'SELECT * FROM customers WHERE name LIKE ? OR phone LIKE ? ORDER BY total_purchases DESC LIMIT 20',
      variables: [Variable.withString('%$query%'), Variable.withString('%$query%')],
    ).get();
    return result.map((r) => <String, dynamic>{
      'id': r.read<String>('id'),
      'name': r.read<String>('name'),
      'phone': r.readNullable<String>('phone') ?? '',
      'email': r.readNullable<String>('email') ?? '',
      'notes': r.readNullable<String>('notes') ?? '',
      'totalPurchases': r.read<int>('total_purchases'),
      'totalSpent': r.read<double>('total_spent'),
      'lastPurchaseAt': r.readNullable<String>('last_purchase_at'),
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    await createCustomersTable();
    final result = await customSelect(
      'SELECT * FROM customers ORDER BY name ASC',
    ).get();
    return result.map((r) => <String, dynamic>{
      'id': r.read<String>('id'),
      'name': r.read<String>('name'),
      'phone': r.readNullable<String>('phone') ?? '',
      'email': r.readNullable<String>('email') ?? '',
      'notes': r.readNullable<String>('notes') ?? '',
      'totalPurchases': r.read<int>('total_purchases'),
      'totalSpent': r.read<double>('total_spent'),
      'lastPurchaseAt': r.readNullable<String>('last_purchase_at'),
    }).toList();
  }

  Future<Map<String, dynamic>?> getCustomer(String id) async {
    await createCustomersTable();
    final result = await customSelect(
      'SELECT * FROM customers WHERE id = ?',
      variables: [Variable.withString(id)],
    ).get();
    if (result.isEmpty) return null;
    final r = result.first;
    return {
      'id': r.read<String>('id'),
      'name': r.read<String>('name'),
      'phone': r.readNullable<String>('phone') ?? '',
      'email': r.readNullable<String>('email') ?? '',
      'notes': r.readNullable<String>('notes') ?? '',
      'totalPurchases': r.read<int>('total_purchases'),
      'totalSpent': r.read<double>('total_spent'),
      'lastPurchaseAt': r.readNullable<String>('last_purchase_at'),
    };
  }

  Future<String> insertOrGetCustomer(String id, String name, {String? phone}) async {
    await createCustomersTable();
    // Check if customer exists by name (case-insensitive)
    final existing = await customSelect(
      'SELECT id FROM customers WHERE LOWER(name) = LOWER(?)',
      variables: [Variable.withString(name)],
    ).get();
    if (existing.isNotEmpty) {
      final existingId = existing.first.read<String>('id');
      // Update phone if provided
      if (phone != null && phone.isNotEmpty) {
        await customStatement(
          'UPDATE customers SET phone = ? WHERE id = ?',
          [Variable.withString(phone), Variable.withString(existingId)],
        );
      }
      return existingId;
    }
    // Insert new
    await customInsert(
      'INSERT INTO customers (id, name, phone, total_purchases, total_spent, created_at, balance, credit_limit, loyalty_points) VALUES (?, ?, ?, 0, 0, ?, 0, 0, 0)',
      variables: [
        Variable.withString(id),
        Variable.withString(name),
        Variable.withString(phone ?? ''),
        Variable.withString(DateTime.now().toIso8601String()),
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
    await customStatement(
      'UPDATE customers SET balance = ? WHERE id = ?',
      [Variable.withReal(amount), Variable.withString(customerId)],
    );
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
      [Variable.withInt(points), Variable.withString(customerId), Variable.withInt(points)],
    );
  }

  Future<List<Map<String, dynamic>>> getCustomersWithDebt() async {
    await createCustomersTable();
    final result = await customSelect(
      'SELECT * FROM customers WHERE balance > 0 ORDER BY balance DESC',
    ).get();
    return result.map((r) => <String, dynamic>{
      'id': r.read<String>('id'),
      'name': r.read<String>('name'),
      'phone': r.readNullable<String>('phone') ?? '',
      'balance': r.read<double>('balance'),
      'creditLimit': r.read<double>('credit_limit'),
      'loyaltyPoints': r.read<int>('loyalty_points'),
    }).toList();
  }

  Future<void> recordCustomerPurchase(String customerId, double amount) async {
    await createCustomersTable();
    await customStatement(
      'UPDATE customers SET total_purchases = total_purchases + 1, '
      'total_spent = total_spent + ?, last_purchase_at = ? WHERE id = ?',
      [Variable.withReal(amount), Variable.withString(DateTime.now().toIso8601String()), Variable.withString(customerId)],
    );
  }

  /// Get top products a specific customer buys (AI recommendation).
  Future<List<Map<String, dynamic>>> getCustomerTopProducts(String customerId) async {
    final result = await customSelect(
      'SELECT psi.product_id, psi.product_name, SUM(psi.quantity) as total_qty, COUNT(*) as times_bought '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.customer_id = ? '
      'GROUP BY psi.product_id, psi.product_name '
      'ORDER BY total_qty DESC LIMIT 10',
      variables: [Variable.withString(customerId)],
    ).get();
    return result.map((r) => <String, dynamic>{
      'productId': r.read<String>('product_id'),
      'productName': r.read<String>('product_name'),
      'totalQty': r.read<int>('total_qty'),
      'timesBought': r.read<int>('times_bought'),
    }).toList();
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
    return (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();
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
}

