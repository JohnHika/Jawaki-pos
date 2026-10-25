import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
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
@TableIndex(
    name: 'idx_products_category_active', columns: {#categoryId, #isActive})
@TableIndex(name: 'idx_products_name', columns: {#name})
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
  BoolColumn get allowFractions =>
      boolean().withDefault(const Constant(false))();
  IntColumn get minStock => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  // Catalog grid filters/lookups: category browse + active filter, name search.
}

// Bulk-selling tiers beyond a product's base unit (e.g. dozen, carton,
// pallet) — any number per product, each with a real price and how many
// base units it represents. Replaces the old fixed secondary/tertiary
// columns, which capped every product at exactly 2 extra tiers.
@TableIndex(name: 'idx_pricing_tiers_product', columns: {#productId})
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
@TableIndex(
    name: 'idx_local_stock_product_branch', columns: {#productId, #branchId})
class LocalStock extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get branchId => text()();
  RealColumn get quantity => real()();
  IntColumn get minQuantity => integer().withDefault(const Constant(0))();
  IntColumn get maxQuantity => integer().nullable()();
  TextColumn get displayUnit => text().nullable()();
  RealColumn get displayQuantityPerUnit => real().nullable()();
  RealColumn get lastReceivedQuantity => real().nullable()();
  DateTimeColumn get lastReceivedAt => dateTime().nullable()();
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
  RealColumn get quantity => real()();
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
  // Soft-void tracking (v10): a voided sale is kept, not deleted, so the
  // receipt can show a VOIDED banner + reason and the void is auditable.
  TextColumn get voidReason => text().nullable()();
  TextColumn get voidedBy => text().nullable()();
  DateTimeColumn get voidedAt => dateTime().nullable()();

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
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
  // The tier/unit this line was actually sold at (v10), so the receipt can
  // show "1 box @ 1,200 (12 pcs @ 100/pc)". `unit` is the sold unit label
  // (piece/box/pack/…); `quantityPerUnit` is how many base units one sold
  // unit contains (1 for the base unit). Nullable for pre-v10 rows.
  TextColumn get unit => text().nullable()();
  RealColumn get quantityPerUnit => real().nullable()();
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

  String? get _customerTenantId {
    final tenantId = _storage.getTenantId()?.trim();
    return tenantId == null || tenantId.isEmpty ? null : tenantId;
  }

  String _requireCustomerTenantId() {
    final tenantId = _customerTenantId;
    if (tenantId == null) {
      throw StateError('Sign in to a shop before accessing its customers');
    }
    return tenantId;
  }

  Set<String> _activeBranchIds() {
    final branchIds = <String>{};
    final activeBranchId = _storage.getBranchId()?.trim();
    if (activeBranchId != null && activeBranchId.isNotEmpty) {
      branchIds.add(activeBranchId);
    }
    try {
      final branches = _storage.getUser()?['branches'];
      if (branches is List) {
        for (final branch in branches.whereType<Map>()) {
          final id = branch['id']?.toString().trim() ?? '';
          if (id.isNotEmpty) branchIds.add(id);
        }
      }
    } catch (_) {
      // Keep the active branch fallback if the saved profile is malformed.
    }
    return branchIds;
  }

  ({String clause, List<Variable> variables}) _salesBranchScope(
    String alias, {
    String? onlyBranchId,
  }) {
    final branchIds = _activeBranchIds();
    if (onlyBranchId != null) {
      if (!branchIds.contains(onlyBranchId)) {
        return (clause: ' AND 1 = 0', variables: const <Variable>[]);
      }
      branchIds
        ..clear()
        ..add(onlyBranchId);
    }
    final scopedBranchIds = branchIds.toList()..sort();
    if (_customerTenantId == null || scopedBranchIds.isEmpty) {
      return (clause: ' AND 1 = 0', variables: const <Variable>[]);
    }
    final placeholders = List.filled(scopedBranchIds.length, '?').join(', ');
    return (
      clause: ' AND $alias.branch_id IN ($placeholders)',
      variables: scopedBranchIds.map(Variable.withString).toList(),
    );
  }

  bool _syncItemBelongsToActiveTenant(SyncQueueData item) {
    final tenantId = _customerTenantId;
    if (tenantId == null) return false;

    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(jsonDecode(item.payload) as Map);
    } catch (_) {
      return false;
    }

    final taggedTenantId = payload['_localTenantId']?.toString();
    if (taggedTenantId != null && taggedTenantId.isNotEmpty) {
      return taggedTenantId == tenantId;
    }

    // Older queue rows predate local tenant tags. They may be resumed only
    // when their creator or branch is verifiably part of this signed-in
    // workspace; ambiguous rows remain queued for their original workspace.
    final currentUserId = _storage.getUser()?['id']?.toString();
    if (currentUserId != null &&
        currentUserId.isNotEmpty &&
        item.userId == currentUserId) {
      return true;
    }

    final branchIds = _activeBranchIds();
    final candidateBranchIds = <String>{
      for (final key in [
        'branchId',
        'fromBranchId',
        'toBranchId',
        'sourceBranchId',
        'destinationBranchId',
      ])
        if (payload[key] != null) payload[key].toString(),
    };
    return candidateBranchIds.any(branchIds.contains);
  }

  // Use encrypted database connection
  AppDatabase(this._storage)
      : super(SecureDatabaseConnection.openSecureConnection());

  @visibleForTesting
  AppDatabase.forTesting(super.executor, this._storage);

  @override
  int get schemaVersion =>
      14; // v14: fractional POS quantities and product setting

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
            await customStatement(
                "UPDATE sync_queue SET status = LOWER(status)");
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
          if (from < 10) {
            // Soft-void tracking + the tier a line was sold at. Additive
            // nullable columns — pending sales are real local data, so add
            // columns rather than dropping the tables.
            await m.addColumn(pendingSales, pendingSales.voidReason);
            await m.addColumn(pendingSales, pendingSales.voidedBy);
            await m.addColumn(pendingSales, pendingSales.voidedAt);
            await m.addColumn(pendingSaleItems, pendingSaleItems.unit);
            await m.addColumn(
                pendingSaleItems, pendingSaleItems.quantityPerUnit);
          }
          if (from < 11) {
            // Preserve how stock was last received (e.g. 20 dozen) while the
            // authoritative quantity remains stored in base units for sales.
            await m.addColumn(localStock, localStock.displayUnit);
            await m.addColumn(
              localStock,
              localStock.displayQuantityPerUnit,
            );
            await m.addColumn(localStock, localStock.lastReceivedQuantity);
            await m.addColumn(localStock, localStock.lastReceivedAt);
          }
          if (from < 12) {
            // Backend stock is Decimal(10,3). SQLite cannot alter a column's
            // affinity in place, so rebuild the cache table while preserving
            // every existing row and the v11 receipt metadata.
            await customStatement(
              'ALTER TABLE local_stock RENAME TO local_stock_before_v12',
            );
            await customStatement('''
              CREATE TABLE local_stock (
                id TEXT NOT NULL PRIMARY KEY,
                product_id TEXT NOT NULL,
                branch_id TEXT NOT NULL,
                quantity REAL NOT NULL,
                min_quantity INTEGER NOT NULL DEFAULT 0,
                max_quantity INTEGER,
                display_unit TEXT,
                display_quantity_per_unit REAL,
                last_received_quantity REAL,
                last_received_at INTEGER,
                updated_at INTEGER NOT NULL,
                UNIQUE(product_id, branch_id)
              )
            ''');
            await customStatement('''
              INSERT INTO local_stock (
                id, product_id, branch_id, quantity, min_quantity,
                max_quantity, display_unit, display_quantity_per_unit,
                last_received_quantity, last_received_at, updated_at
              )
              SELECT id, product_id, branch_id, CAST(quantity AS REAL),
                min_quantity, max_quantity, display_unit,
                display_quantity_per_unit, last_received_quantity,
                last_received_at, updated_at
              FROM local_stock_before_v12
            ''');
            await customStatement('DROP TABLE local_stock_before_v12');
          }
          if (from < 13) {
            // v13: performance indexes. The @TableIndex annotations only
            // apply on createAll() (new installs), so existing databases
            // add the same indexes explicitly here. Catalog reads run
            // per-product tier/stock lookups and category/name filters on
            // every render — without these they full-scan the local tables.
            //
            // NEVER let this block fail the upgrade: indexes are a pure
            // optimization, and a thrown error here aborts onUpgrade, which
            // fails database open, which leaves the app with an empty
            // catalog (the exact "POS shows no products" symptom). Each
            // CREATE INDEX is wrapped and guarded against both pre-v13
            // tables that may not exist (e.g. product_pricing_tiers only
            // exists from v9, products may be absent if catalog sync never
            // ran) and duplicate-index races.
            Future<void> safeCreateIndex(String name, String sql) async {
              try {
                await customStatement(sql);
              } catch (e) {
                debugPrint('[DB] skip index $name: $e');
              }
            }

            await safeCreateIndex(
              'idx_products_category_active',
              'CREATE INDEX IF NOT EXISTS idx_products_category_active ON products (category_id, is_active)',
            );
            await safeCreateIndex(
              'idx_products_name',
              'CREATE INDEX IF NOT EXISTS idx_products_name ON products (name)',
            );
            await safeCreateIndex(
              'idx_pricing_tiers_product',
              'CREATE INDEX IF NOT EXISTS idx_pricing_tiers_product ON product_pricing_tiers (product_id)',
            );
            await safeCreateIndex(
              'idx_local_stock_product_branch',
              'CREATE INDEX IF NOT EXISTS idx_local_stock_product_branch ON local_stock (product_id, branch_id)',
            );
          }
          if (from >= 9 && from < 14) {
            // SQLite's dynamic typing safely preserves old integer quantities
            // in REAL-affinity columns; this migration adds the product flag.
            // Existing products remain whole-unit only until an owner opts in.
            final productTable = await customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type = 'table' AND name = 'products'",
            ).getSingleOrNull();
            if (productTable != null) {
              await m.addColumn(products, products.allowFractions);
            }
          }
        },
        beforeOpen: (details) async {
          await _ensureLocalStockUniqueKey();
        },
      );

  /// Saving stock relies on one row per (product, branch). Databases that went
  /// through the v12 upgrade have that rule, but a fresh install builds the
  /// table from its definition, which only had a plain index, so every stock
  /// save failed ("ON CONFLICT clause does not match"). Check on every open and
  /// repair, keeping the newest row if a pair was ever duplicated.
  Future<void> _ensureLocalStockUniqueKey() async {
    try {
      final indexes =
          await customSelect("PRAGMA index_list('local_stock')").get();
      for (final index in indexes) {
        if (index.read<int>('unique') != 1) continue;
        final name = index.read<String>('name');
        final columns = await customSelect("PRAGMA index_info('$name')").get();
        final names = columns.map((c) => c.read<String>('name')).toSet();
        if (names.length == 2 &&
            names.contains('product_id') &&
            names.contains('branch_id')) {
          return;
        }
      }
      await customStatement(
        'DELETE FROM local_stock WHERE rowid NOT IN '
        '(SELECT MAX(rowid) FROM local_stock GROUP BY product_id, branch_id)',
      );
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_local_stock_product_branch '
        'ON local_stock (product_id, branch_id)',
      );
    } catch (e) {
      debugPrint('[DB] could not ensure the local stock unique key: $e');
    }
  }

  Future<void> _createSupplierFinanceTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT NOT NULL PRIMARY KEY,
        tenant_id TEXT,
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
    try {
      await customStatement('ALTER TABLE suppliers ADD COLUMN tenant_id TEXT');
    } catch (_) {
      // The tenant column already exists on upgraded installations.
    }
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_tenant_active ON suppliers (tenant_id, is_active)',
    );
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
    )..where((p) => p.categoryId.equals(categoryId)))
        .get();
  }

  Future<List<Product>> searchProducts(String query) {
    return (select(
      products,
    )..where((p) => p.name.like('%$query%') | p.sku.like('%$query%')))
        .get();
  }

  /// Live, bounded suggestions for the POS search field. This keeps typing
  /// responsive and avoids starting another full catalog download just to
  /// show a handful of matching names.
  Stream<List<Product>> watchProductSuggestions(String query, {int limit = 5}) {
    final normalized = query.trim();
    if (normalized.isEmpty) return Stream.value(const <Product>[]);
    final safeLimit = limit.clamp(1, 20).toInt();
    return (select(products)
          ..where((product) =>
              product.isActive.equals(true) &
              (product.name.like('%$normalized%') |
                  product.sku.like('%$normalized%')))
          ..orderBy([(product) => OrderingTerm.asc(product.name)])
          ..limit(safeLimit))
        .watch();
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

  /// Loads pricing tiers for a catalog page in one database query instead of
  /// issuing a separate query for every product card.
  Future<Map<String, List<ProductPricingTier>>> getPricingTiersForProducts(
    Iterable<String> productIds,
  ) async {
    final ids = productIds.toSet().toList();
    if (ids.isEmpty) return {};

    // Catalog sync is capped at 500 products, within SQLite's bind-variable
    // limit. Chunk anyway so this remains safe if that page size is raised.
    final result = <String, List<ProductPricingTier>>{};
    for (var offset = 0; offset < ids.length; offset += 400) {
      final chunk = ids.skip(offset).take(400).toList();
      final rows = await (select(productPricingTiers)
            ..where((tier) => tier.productId.isIn(chunk))
            ..orderBy([(tier) => OrderingTerm.asc(tier.sortOrder)]))
          .get();
      for (final tier in rows) {
        result.putIfAbsent(tier.productId, () => []).add(tier);
      }
    }
    return result;
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
    List<PendingSaleItemsCompanion> items, {
    double customerBalanceDelta = 0,
    bool decrementLocalStock = false,
  }) async {
    await transaction(() async {
      await into(pendingSales).insert(sale);
      await batch((batch) {
        batch.insertAll(pendingSaleItems, items);
      });

      // A local sale, its stock deductions, and any new customer debt must
      // commit together. Otherwise an error between these writes can leave a
      // receipt without matching stock or debt, and a retry can double-charge.
      if (customerBalanceDelta != 0) {
        final customerId =
            sale.customerId.present ? sale.customerId.value : null;
        if (customerId == null || customerId.isEmpty) {
          throw StateError('A customer is required for a debt sale');
        }
        await createCustomersTable();
        final tenantId = _requireCustomerTenantId();
        final updatedCustomers = await customUpdate(
          'UPDATE customers SET balance = balance + ? WHERE id = ? AND tenant_id = ?',
          variables: [
            Variable.withReal(customerBalanceDelta),
            Variable.withString(customerId),
            Variable.withString(tenantId),
          ],
        );
        if (updatedCustomers != 1) {
          throw StateError('The selected customer could not be found');
        }
      }

      if (decrementLocalStock) {
        if (!sale.branchId.present || sale.branchId.value.isEmpty) {
          throw StateError('A branch is required to update local stock');
        }
        final branchId = sale.branchId.value;
        for (final item in items) {
          if (!item.productId.present || !item.quantity.present) continue;
          await decrementStock(
            item.productId.value,
            branchId,
            item.quantity.value,
          );
        }
      }
    });
  }

  Future<List<PendingSale>> getUnsyncedSales() {
    final branchIds = _activeBranchIds();
    if (_customerTenantId == null || branchIds.isEmpty) {
      return Future.value(const <PendingSale>[]);
    }
    return (select(pendingSales)
          ..where((s) => s.isSynced.equals(false) & s.branchId.isIn(branchIds)))
        .get();
  }

  Future<void> updateSaleReceiptNumber(String id, String receiptNumber) {
    final branchIds = _activeBranchIds();
    if (_customerTenantId == null || branchIds.isEmpty) return Future.value();
    return (update(pendingSales)
          ..where((s) => s.id.equals(id) & s.branchId.isIn(branchIds)))
        .write(
      PendingSalesCompanion(receiptNumber: Value(receiptNumber)),
    );
  }

  Future<void> markSaleAsSynced(String id) {
    final branchIds = _activeBranchIds();
    if (_customerTenantId == null || branchIds.isEmpty) return Future.value();
    return (update(pendingSales)
          ..where((s) => s.id.equals(id) & s.branchId.isIn(branchIds)))
        .write(
      PendingSalesCompanion(
        isSynced: const Value(true),
        syncedAt: Value(DateTime.now()),
      ),
    );
  }

  // Sync Events (Backwards compatibility - uses SyncQueue table)
  Future<void> addSyncEvent(SyncQueueCompanion event) {
    return addToSyncQueue(event);
  }

  Future<List<SyncQueueData>> getPendingSyncEvents() async {
    final items = await (select(syncQueue)
          ..where((e) => e.status.equals('pending'))
          ..orderBy([(e) => OrderingTerm.asc(e.sequenceNumber)]))
        .get();
    return items.where(_syncItemBelongsToActiveTenant).toList();
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
  Future<void> addToSyncQueue(SyncQueueCompanion item) async {
    final tenantId = _customerTenantId;
    if (tenantId != null && item.payload.present) {
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(item.payload.value) as Map,
        );
        payload.putIfAbsent('_localTenantId', () => tenantId);
        item = item.copyWith(payload: Value(jsonEncode(payload)));
      } catch (_) {
        // Malformed items will not be sent by the tenant-scoped queue reader.
      }
    }
    await into(syncQueue).insert(item, mode: InsertMode.insertOrIgnore);
  }

  Future<SyncQueueData?> getSyncQueueItem(String id) async {
    final item = await (select(syncQueue)..where((q) => q.id.equals(id)))
        .getSingleOrNull();
    if (item == null || !_syncItemBelongsToActiveTenant(item)) return null;
    return item;
  }

  /// Get all pending sync items (not synced, not exceeding max retries)
  Future<List<SyncQueueData>> getPendingSyncQueue() async {
    final now = DateTime.now();
    final items = await (select(syncQueue)
          ..where(
            (q) =>
                q.status.equals('pending') &
                q.retryCount.isSmallerThan(q.maxRetries) &
                (q.nextRetryAt.isNull() |
                    q.nextRetryAt.isSmallerOrEqualValue(now)),
          )
          ..orderBy([(q) => OrderingTerm.asc(q.sequenceNumber)]))
        .get();
    return items.where(_syncItemBelongsToActiveTenant).toList();
  }

  /// Get failed sync items that have exceeded max retries
  Future<List<SyncQueueData>> getFailedSyncQueue() async {
    final items = await (select(syncQueue)
          ..where((q) => q.status.equals('failed')))
        .get();
    return items.where(_syncItemBelongsToActiveTenant).toList();
  }

  Future<List<SyncQueueData>> getConflictSyncQueue() async {
    final items = await (select(syncQueue)
          ..where((q) => q.status.equals('conflict')))
        .get();
    return items.where(_syncItemBelongsToActiveTenant).toList();
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
    )..where((q) => q.id.equals(id)))
        .getSingleOrNull();
    if (item == null) return;

    final newRetryCount = item.retryCount + 1;
    final hasRetriesRemaining = newRetryCount < item.maxRetries;

    await (update(syncQueue)..where((q) => q.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(hasRetriesRemaining ? 'pending' : 'failed'),
        errorMessage: Value(errorMessage),
        retryCount: Value(newRetryCount),
        lastAttemptAt: Value(DateTime.now()),
        nextRetryAt: Value(DateTime.now().add(delay)),
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
          ..where(
            (q) =>
                (q.status.equals('synced') | q.status.equals('resolved')) &
                q.syncedAt.isSmallerThanValue(cutoffDate),
          ))
        .go();
  }

  /// Get sync queue count by status
  Future<Map<String, int>> getSyncQueueStats() async {
    final scopedItems = (await select(syncQueue).get())
        .where(_syncItemBelongsToActiveTenant)
        .toList();
    int count(String status) =>
        scopedItems.where((item) => item.status == status).length;
    final pending = count('pending');
    final synced = count('synced');
    final failed = count('failed');
    final conflicts = count('conflict');
    final resolved = count('resolved');

    return {
      'pending': pending,
      'synced': synced,
      'failed': failed,
      'conflict': conflicts,
      'resolved': resolved,
      'total': pending + synced + failed + conflicts + resolved,
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
    )..where((f) => f.productId.equals(productId)))
        .go();
  }

  Future<bool> isFavorite(String productId) async {
    final result = await (select(
      favoriteProducts,
    )..where((f) => f.productId.equals(productId)))
        .getSingleOrNull();
    return result != null;
  }

  // Stock
  Future<void> updateLocalStock(List<LocalStockCompanion> items) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(localStock, items);
    });
  }

  /// Reconcile a server stock snapshot without erasing deductions from sales
  /// that are still waiting to sync. The server snapshot cannot include those
  /// sales yet, so write its canonical quantity minus the local pending sale
  /// quantities in one transaction. Once a sale syncs, the next snapshot uses
  /// the server's already-decremented quantity and no longer subtracts it.
  Future<void> reconcileLocalStockWithPendingSales({
    required String branchId,
    required List<LocalStockCompanion> serverStock,
  }) async {
    if (_customerTenantId == null ||
        !_activeBranchIds().contains(branchId) ||
        serverStock.isEmpty) {
      return;
    }

    await transaction(() async {
      final pendingSalesForBranch = await (select(pendingSales)
            ..where((sale) =>
                sale.branchId.equals(branchId) &
                sale.status.equals('COMPLETED') &
                sale.isSynced.equals(false)))
          .get();
      final pendingSaleIds =
          pendingSalesForBranch.map((sale) => sale.id).toList();
      final pendingQuantityByProduct = <String, double>{};
      if (pendingSaleIds.isNotEmpty) {
        final pendingItems = await (select(pendingSaleItems)
              ..where((item) => item.saleId.isIn(pendingSaleIds)))
            .get();
        for (final item in pendingItems) {
          pendingQuantityByProduct.update(
            item.productId,
            (quantity) => quantity + item.quantity,
            ifAbsent: () => item.quantity,
          );
        }
      }

      final now = DateTime.now();
      final reconciledStock = serverStock.map((item) {
        final productId = item.productId.value;
        final serverQuantity = item.quantity.value;
        final pendingQuantity = pendingQuantityByProduct[productId] ?? 0;
        return item.copyWith(
          quantity: Value(serverQuantity - pendingQuantity),
          updatedAt: Value(now),
        );
      }).toList();

      await batch((batch) {
        batch.insertAllOnConflictUpdate(localStock, reconciledStock);
      });
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

    await (delete(dailyPurchases)
          ..where(
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
    final rows = await (select(localStock)
          ..where(
            (s) => s.productId.equals(productId) & s.branchId.equals(branchId),
          ))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Loads the current branch's stock for multiple product cards in one query.
  Future<Map<String, LocalStockData>> getStockForProducts(
    Iterable<String> productIds,
    String branchId,
  ) async {
    final ids = productIds.toSet().toList();
    if (ids.isEmpty) return {};

    final result = <String, LocalStockData>{};
    for (var offset = 0; offset < ids.length; offset += 400) {
      final chunk = ids.skip(offset).take(400).toList();
      final rows = await (select(localStock)
            ..where((stock) =>
                stock.branchId.equals(branchId) & stock.productId.isIn(chunk)))
          .get();
      for (final stock in rows) {
        final previous = result[stock.productId];
        if (previous == null || stock.updatedAt.isAfter(previous.updatedAt)) {
          result[stock.productId] = stock;
        }
      }
    }
    return result;
  }

  // Get stock for product using current branch
  Future<LocalStockData?> getStockForProduct(String productId) async {
    final branchId = _storage.getBranchId();
    if (branchId == null) {
      return null;
    }
    return getProductStock(productId, branchId);
  }

  /// Live stream counterpart to [getStockForProduct] — emits again whenever
  /// this product's local stock row changes (e.g. after a catalog sync
  /// writes a fresh quantity following a stock receive), instead of a
  /// one-shot read that a UI provider could otherwise cache forever.
  Stream<LocalStockData?> watchStockForProduct(String productId) {
    final branchId = _storage.getBranchId();
    if (branchId == null) {
      return Stream.value(null);
    }
    return (select(localStock)
          ..where(
            (s) => s.productId.equals(productId) & s.branchId.equals(branchId),
          ))
        .watchSingleOrNull();
  }

  Stream<List<LocalStockData>> watchAllStock() => select(localStock).watch();

  Future<void> upsertAuthoritativeStock({
    required String productId,
    required String branchId,
    required double quantity,
    String? displayUnit,
    double? displayQuantityPerUnit,
    double? lastReceivedQuantity,
    DateTime? lastReceivedAt,
  }) async {
    final now = DateTime.now();
    await customInsert(
      '''
        INSERT INTO local_stock (
          id, product_id, branch_id, quantity, display_unit,
          display_quantity_per_unit, last_received_quantity,
          last_received_at, updated_at
        ) VALUES (
          ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, -1),
          NULLIF(?, -1), NULLIF(?, 0), ?
        )
        ON CONFLICT(product_id, branch_id) DO UPDATE SET
          quantity = excluded.quantity,
          display_unit = COALESCE(excluded.display_unit, local_stock.display_unit),
          display_quantity_per_unit = COALESCE(
            excluded.display_quantity_per_unit,
            local_stock.display_quantity_per_unit
          ),
          last_received_quantity = COALESCE(
            excluded.last_received_quantity,
            local_stock.last_received_quantity
          ),
          last_received_at = COALESCE(
            excluded.last_received_at,
            local_stock.last_received_at
          ),
          updated_at = excluded.updated_at
      ''',
      variables: [
        Variable.withString('stock-$branchId-$productId'),
        Variable.withString(productId),
        Variable.withString(branchId),
        Variable.withReal(quantity),
        Variable.withString(displayUnit ?? ''),
        Variable.withReal(displayQuantityPerUnit ?? -1),
        Variable.withReal(lastReceivedQuantity ?? -1),
        Variable.withInt(
          lastReceivedAt == null
              ? 0
              : lastReceivedAt.millisecondsSinceEpoch ~/ 1000,
        ),
        Variable.withDateTime(now),
      ],
      updates: {localStock},
    );
  }

  Future<double> incrementLocalStock({
    required String productId,
    required String branchId,
    required double quantity,
  }) async {
    final row = await customSelect(
      '''
        INSERT INTO local_stock (
          id, product_id, branch_id, quantity, updated_at
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(product_id, branch_id) DO UPDATE SET
          quantity = local_stock.quantity + excluded.quantity,
          updated_at = excluded.updated_at
        RETURNING quantity
      ''',
      variables: [
        Variable.withString('stock-$branchId-$productId'),
        Variable.withString(productId),
        Variable.withString(branchId),
        Variable.withReal(quantity),
        Variable.withDateTime(DateTime.now()),
      ],
      readsFrom: {localStock},
    ).getSingle();
    notifyUpdates({TableUpdate.onTable(localStock)});
    return row.read<double>('quantity');
  }

  Future<void> decrementStock(
    String productId,
    String branchId,
    num quantity,
  ) async {
    final amount = quantity.toDouble();
    final stock = await getProductStock(productId, branchId);
    if (stock != null) {
      await (update(localStock)
            ..where(
              (s) =>
                  s.productId.equals(productId) & s.branchId.equals(branchId),
            ))
          .write(
        LocalStockCompanion(
          quantity: Value(stock.quantity - amount),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      // No local stock row yet for this product+branch — previously this
      // silently did nothing, so the first sale of a product never showed
      // any deduction. Create the row so the sale is reflected; catalog
      // reconciliation preserves the deduction until the sale syncs.
      final start = -amount;
      await into(localStock).insert(
        LocalStockCompanion.insert(
          id: 'stock-$branchId-$productId',
          productId: productId,
          branchId: branchId,
          quantity: start.toDouble(),
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
      await (update(localStock)
            ..where(
              (s) =>
                  s.productId.equals(productId) &
                  s.branchId.equals(fromBranchId),
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
            quantity: quantity.toDouble(),
            updatedAt: now,
          ),
        );
      } else {
        await (update(localStock)
              ..where(
                (s) =>
                    s.productId.equals(productId) &
                    s.branchId.equals(toBranchId),
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
      'ls.quantity, ls.branch_id, ls.display_unit, '
      'ls.display_quantity_per_unit, ls.last_received_quantity, '
      'ls.last_received_at, '
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
            'displayUnit': r.readNullable<String>('display_unit'),
            'displayQuantityPerUnit':
                r.readNullable<double>('display_quantity_per_unit'),
            'lastReceivedQuantity':
                r.readNullable<double>('last_received_quantity'),
            'lastReceivedAt': r.readNullable<DateTime>('last_received_at'),
            'quantity': r.readNullable<double>('quantity') ?? 0.0,
            'branchId': r.readNullable<String>('branch_id') ?? '',
            'categoryName':
                r.readNullable<String>('category_name') ?? 'Uncategorized',
          },
        )
        .toList();

    // Attach pricing tiers in one bulk query instead of one database roundtrip
    // per low-stock product.
    final tiersByProduct = await getPricingTiersForProducts(
      rows.map((row) => row['id'] as String),
    );
    for (final row in rows) {
      final tiers = tiersByProduct[row['id']] ?? const <ProductPricingTier>[];
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
            'quantity': r.readNullable<double>('quantity') ?? 0.0,
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
    final branchIds = _activeBranchIds();
    if (_customerTenantId == null || branchIds.isEmpty) {
      return Future.value(const <PendingSale>[]);
    }
    return (select(pendingSales)
          ..where(
            (s) =>
                s.createdAt.isBiggerOrEqualValue(from) &
                s.createdAt.isSmallerOrEqualValue(to) &
                s.branchId.isIn(branchIds),
          )
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .get();
  }

  /// Stream of all sales (for real-time).
  Stream<List<PendingSale>> watchAllSales() {
    final branchIds = _activeBranchIds();
    if (_customerTenantId == null || branchIds.isEmpty) {
      return Stream.value(const <PendingSale>[]);
    }
    return (select(pendingSales)
          ..where((s) => s.branchId.isIn(branchIds))
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .watch();
  }

  /// Stream of today's sales.
  Stream<List<PendingSale>> watchTodaysSales() {
    final branchIds = _activeBranchIds();
    if (_customerTenantId == null || branchIds.isEmpty) {
      return Stream.value(const <PendingSale>[]);
    }
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return (select(pendingSales)
          ..where(
            (s) =>
                s.createdAt.isBiggerOrEqualValue(startOfDay) &
                s.createdAt.isSmallerThanValue(endOfDay) &
                s.branchId.isIn(branchIds),
          )
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .watch();
  }

  /// Stream of completed sales for one branch today. Payment summaries use
  /// this view so pending prompts, failed attempts, and sales from another
  /// branch cannot inflate the local total.
  Stream<List<PendingSale>> watchCompletedSalesForBranchToday(
    String branchId, {
    DateTime? now,
  }) {
    if (_customerTenantId == null || !_activeBranchIds().contains(branchId)) {
      return Stream.value(const <PendingSale>[]);
    }
    final current = now ?? DateTime.now();
    final startOfDay = DateTime(current.year, current.month, current.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return (select(pendingSales)
          ..where(
            (sale) =>
                sale.branchId.equals(branchId) &
                sale.status.equals('COMPLETED') &
                sale.createdAt.isBiggerOrEqualValue(startOfDay) &
                sale.createdAt.isSmallerThanValue(endOfDay),
          )
          ..orderBy([(sale) => OrderingTerm.desc(sale.createdAt)]))
        .watch();
  }

  /// Get sales items for a specific sale.
  Future<List<PendingSaleItem>> getSaleItems(String saleId) async {
    final sale = await getPendingSaleById(saleId);
    if (sale == null) return const <PendingSaleItem>[];
    return (select(
      pendingSaleItems,
    )..where((i) => i.saleId.equals(saleId)))
        .get();
  }

  Future<PendingSale?> getPendingSaleById(String saleId) {
    final branchIds = _activeBranchIds();
    if (_customerTenantId == null || branchIds.isEmpty) {
      return Future.value(null);
    }
    return (select(pendingSales)
          ..where((s) => s.id.equals(saleId) & s.branchId.isIn(branchIds)))
        .getSingleOrNull();
  }

  /// Finds a locally cached, provider-verified M-Pesa sale by its immutable
  /// payment reference. The server uses `paystack-<reference>` as its
  /// offline id, while older app builds used a random local sale id.
  Future<PendingSale?> getMerchantMpesaSaleByReference(String reference) async {
    final branchIds = _activeBranchIds();
    if (_customerTenantId == null || branchIds.isEmpty) return null;
    final matches = await (select(pendingSales)
          ..where((s) =>
              s.paymentMethod.equals('MPESA') &
              s.paymentReference.equals(reference) &
              s.branchId.isIn(branchIds))
          ..orderBy([(s) => OrderingTerm.asc(s.createdAt)])
          ..limit(1))
        .get();
    return matches.isEmpty ? null : matches.first;
  }

  /// Soft-voids a local sale: marks it VOIDED with a reason/who/when and
  /// returns its stock to the local cache — instead of the old hard DELETE,
  /// which left no trace. The backend performs the authoritative void +
  /// stock restore; this keeps the offline/local view consistent.
  Future<void> voidPendingSale(
    String saleId, {
    required String reason,
    String? voidedBy,
  }) async {
    await transaction(() async {
      final sale = await getPendingSaleById(saleId);
      if (sale == null || sale.status == 'VOIDED') return;

      final branchIds = _activeBranchIds();
      if (branchIds.isEmpty || _customerTenantId == null) return;

      // Credit and split sales add their debt to the local customer balance
      // when the receipt is committed. Reverse that exact sale contribution
      // in the same transaction as the void so offline customer lists do not
      // keep showing a debt after the receipt was cancelled.
      final debtAmount = _pendingSaleDebtAmount(sale);
      if (debtAmount > 0) {
        final customerId = sale.customerId;
        if (customerId == null || customerId.isEmpty) {
          throw StateError('This debt sale has no customer to adjust');
        }
        final tenantId = _requireCustomerTenantId();
        final updatedCustomers = await customUpdate(
          'UPDATE customers SET balance = CASE WHEN balance > ? '
          'THEN balance - ? ELSE 0 END WHERE id = ? AND tenant_id = ?',
          variables: [
            Variable.withReal(debtAmount),
            Variable.withReal(debtAmount),
            Variable.withString(customerId),
            Variable.withString(tenantId),
          ],
        );
        if (updatedCustomers != 1) {
          throw StateError('The debt customer could not be found');
        }
      }

      await (update(pendingSales)
            ..where((s) => s.id.equals(saleId) & s.branchId.isIn(branchIds)))
          .write(
        PendingSalesCompanion(
          status: const Value('VOIDED'),
          voidReason: Value(reason),
          voidedBy: Value(voidedBy),
          voidedAt: Value(DateTime.now()),
        ),
      );

      // Return each line's quantity to the local stock cache.
      final items = await getSaleItems(saleId);
      for (final item in items) {
        final stock = await getStockForProduct(item.productId);
        if (stock != null) {
          await (update(localStock)..where((s) => s.id.equals(stock.id))).write(
            LocalStockCompanion(
              quantity: Value(stock.quantity + item.quantity),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }
    });
  }

  double _pendingSaleDebtAmount(PendingSale sale) {
    switch (sale.paymentMethod.toUpperCase()) {
      case 'CREDIT':
        return sale.total;
      case 'SPLIT':
        final reference = sale.paymentReference;
        if (reference == null || reference.isEmpty) {
          throw StateError('This split sale has no saved tender breakdown');
        }
        final decoded = jsonDecode(reference);
        if (decoded is! List) {
          throw StateError('This split sale has an invalid tender breakdown');
        }
        var creditAmount = 0.0;
        var hasCreditTender = false;
        for (final row in decoded.whereType<Map>()) {
          if (row['method']?.toString().toUpperCase() != 'CREDIT') continue;
          hasCreditTender = true;
          final rawAmount = row['amount'];
          final amount = rawAmount is num
              ? rawAmount.toDouble()
              : double.tryParse(rawAmount?.toString() ?? '');
          if (amount == null || !amount.isFinite || amount <= 0) {
            throw StateError('This split sale has an invalid debt amount');
          }
          creditAmount += amount;
        }
        if (!hasCreditTender || !creditAmount.isFinite || creditAmount <= 0) {
          throw StateError('This split sale has no valid debt portion');
        }
        return creditAmount;
      default:
        return 0;
    }
  }

  /// Stream all sale items (for category / product reports).
  Stream<List<PendingSaleItem>> watchAllSaleItems() {
    final branchIds = _activeBranchIds();
    if (_customerTenantId == null || branchIds.isEmpty) {
      return Stream.value(const <PendingSaleItem>[]);
    }
    final saleIds = selectOnly(pendingSales)
      ..addColumns([pendingSales.id])
      ..where(pendingSales.branchId.isIn(branchIds));
    return (select(pendingSaleItems)
          ..where((item) => item.saleId.isInQuery(saleIds)))
        .watch();
  }

  /// Sales grouped by payment method for a date range.
  Future<List<Map<String, dynamic>>> getSalesByPaymentMethod(
    DateTime from,
    DateTime to,
  ) async {
    final scope = _salesBranchScope('pending_sales');
    final result = await customSelect(
      'SELECT payment_method, COUNT(*) as count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ?${scope.clause} '
      'GROUP BY payment_method '
      'ORDER BY total_amount DESC',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
      ],
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
    final scope = _salesBranchScope('pending_sales');
    final result = await customSelect(
      'SELECT cashier_id, COUNT(*) as count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ?${scope.clause} '
      'GROUP BY cashier_id '
      'ORDER BY total_amount DESC',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
      ],
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
    final scope = _salesBranchScope('ps');
    final result = await customSelect(
      'SELECT psi.product_id, psi.product_name, SUM(psi.quantity) as total_qty, SUM(psi.total) as total_revenue '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ?${scope.clause} '
      'GROUP BY psi.product_id, psi.product_name '
      'ORDER BY total_qty DESC '
      'LIMIT ?',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
        Variable.withInt(limit),
      ],
    ).get();
    return result
        .map(
          (r) => {
            'productId': r.read<String>('product_id'),
            'productName': r.read<String>('product_name'),
            'totalQty': (r.data['total_qty'] as num? ?? 0).toDouble(),
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
    final scope = _salesBranchScope('ps');
    final result = await customSelect(
      'SELECT c.id as category_id, c.name as category_name, '
      'COALESCE(SUM(CASE WHEN ps.id IS NOT NULL THEN psi.quantity ELSE 0 END), 0) as total_qty, '
      'COALESCE(SUM(CASE WHEN ps.id IS NOT NULL THEN psi.total ELSE 0 END), 0) as total_revenue '
      'FROM categories c '
      'LEFT JOIN products p ON p.category_id = c.id '
      'LEFT JOIN pending_sale_items psi ON psi.product_id = p.id '
      'LEFT JOIN pending_sales ps ON ps.id = psi.sale_id AND ps.created_at >= ? AND ps.created_at <= ?${scope.clause} '
      'GROUP BY c.id, c.name '
      'ORDER BY total_revenue DESC',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
      ],
    ).get();
    return result
        .map(
          (r) => {
            'categoryId': r.read<String>('category_id'),
            'categoryName': r.read<String>('category_name'),
            'totalQty': (r.data['total_qty'] as num? ?? 0).toDouble(),
            'totalRevenue': r.read<double>('total_revenue'),
          },
        )
        .toList();
  }

  /// Inventory summary with product names & stock levels.
  Future<List<Map<String, dynamic>>> getInventoryReport() async {
    final branchId = _storage.getBranchId();
    final result = await customSelect(
      'SELECT p.id, p.name, p.sku, p.price, p.cost_price, p.unit, '
      'COALESCE(ls.quantity, 0) as stock, p.min_stock as min_stock, '
      'ls.display_unit, ls.display_quantity_per_unit, '
      'ls.last_received_quantity, ls.last_received_at, '
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
            'stock': r.read<double>('stock'),
            'minStock': r.read<int>('min_stock'),
            'unit': r.read<String>('unit'),
            'displayUnit': r.readNullable<String>('display_unit'),
            'displayQuantityPerUnit':
                r.readNullable<double>('display_quantity_per_unit'),
            'lastReceivedQuantity':
                r.readNullable<double>('last_received_quantity'),
            'lastReceivedAt': r.readNullable<DateTime>('last_received_at'),
            'categoryName':
                r.readNullable<String>('category_name') ?? 'Uncategorised',
          },
        )
        .toList();
  }

  /// Dashboard summary: total sales, revenue, avg ticket for today.
  Future<Map<String, dynamic>> getDashboardSummary({String? branchId}) async {
    final scope = _salesBranchScope('pending_sales', onlyBranchId: branchId);
    final itemScope = _salesBranchScope('ps', onlyBranchId: branchId);
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final result = await customSelect(
      'SELECT COALESCE(COUNT(*), 0) as count, COALESCE(SUM(total), 0) as revenue, '
      'COALESCE(AVG(total), 0) as avg_ticket, '
      'COALESCE(SUM(CASE WHEN is_synced = 0 AND UPPER(payment_method) <> \'MPESA\' THEN 1 ELSE 0 END), 0) as unsynced_count, '
      'COALESCE(SUM(CASE WHEN is_synced = 0 AND UPPER(payment_method) <> \'MPESA\' THEN total ELSE 0 END), 0) as unsynced_revenue '
      'FROM pending_sales WHERE created_at >= ? AND created_at < ?${scope.clause} '
      "AND UPPER(status) = 'COMPLETED'",
      variables: [
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
        ...scope.variables,
      ],
    ).getSingle();
    // Items sold today
    final itemsResult = await customSelect(
      'SELECT COALESCE(SUM(psi.quantity), 0) as items_sold, '
      'COALESCE(SUM(CASE WHEN ps.is_synced = 0 AND UPPER(ps.payment_method) <> \'MPESA\' THEN psi.quantity ELSE 0 END), 0) as unsynced_items_sold '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at < ?${itemScope.clause} '
      "AND UPPER(ps.status) = 'COMPLETED'",
      variables: [
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
        ...itemScope.variables,
      ],
    ).getSingle();
    return {
      'transactionCount': result.read<int>('count'),
      'totalRevenue': result.read<double>('revenue'),
      'avgTicket': result.read<double>('avg_ticket'),
      'itemsSold': (itemsResult.data['items_sold'] as num? ?? 0).toDouble(),
      'unsyncedTransactionCount': result.read<int>('unsynced_count'),
      'unsyncedRevenue': result.read<double>('unsynced_revenue'),
      'unsyncedItemsSold':
          (itemsResult.data['unsynced_items_sold'] as num? ?? 0).toDouble(),
    };
  }

  /// Completed sales totals for one branch and local business date.
  /// Mirrors the cloud End of Day summary response for phone-server mode.
  Future<Map<String, dynamic>> getDailySalesSummary(
    String branchId,
    DateTime date,
  ) async {
    if (_customerTenantId == null || !_activeBranchIds().contains(branchId)) {
      return {
        'date':
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'totalSales': 0.0,
        'totalTransactions': 0,
        'totalTax': 0.0,
        'totalDiscount': 0.0,
        'cashSales': 0.0,
        'mpesaSales': 0.0,
        'cardSales': 0.0,
        'creditSales': 0.0,
        'outstandingBalance': 0.0,
      };
    }
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final row = await customSelect(
      'SELECT '
      'COUNT(*) AS total_transactions, '
      'COALESCE(SUM(total), 0) AS total_sales, '
      'COALESCE(SUM(tax), 0) AS total_tax, '
      'COALESCE(SUM(discount), 0) AS total_discount, '
      "COALESCE(SUM(CASE WHEN UPPER(payment_method) = 'CASH' THEN total ELSE 0 END), 0) AS cash_sales, "
      "COALESCE(SUM(CASE WHEN UPPER(payment_method) = 'MPESA' THEN total ELSE 0 END), 0) AS mpesa_sales, "
      "COALESCE(SUM(CASE WHEN UPPER(payment_method) = 'CREDIT' THEN total ELSE 0 END), 0) AS credit_sales "
      'FROM pending_sales '
      'WHERE branch_id = ? AND created_at >= ? AND created_at < ? '
      "AND UPPER(status) = 'COMPLETED'",
      variables: [
        Variable.withString(branchId),
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
      ],
    ).getSingle();

    return {
      'date':
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'totalSales': row.read<double>('total_sales'),
      'totalTransactions': row.read<int>('total_transactions'),
      'totalTax': row.read<double>('total_tax'),
      'totalDiscount': row.read<double>('total_discount'),
      'cashSales': row.read<double>('cash_sales'),
      'mpesaSales': row.read<double>('mpesa_sales'),
      'cardSales': 0.0,
      'creditSales': row.read<double>('credit_sales'),
      'outstandingBalance': 0.0,
    };
  }

  /// Weekly summary for analytics dashboard.
  Future<Map<String, dynamic>> getWeeklySummary(
    DateTime from,
    DateTime to,
  ) async {
    final scope = _salesBranchScope('pending_sales');
    final itemScope = _salesBranchScope('ps');
    final result = await customSelect(
      'SELECT COALESCE(COUNT(*), 0) as count, COALESCE(SUM(total), 0) as revenue, '
      'COALESCE(AVG(total), 0) as avg_ticket '
      'FROM pending_sales WHERE created_at >= ? AND created_at <= ?${scope.clause} '
      "AND UPPER(status) NOT IN ('VOIDED', 'REFUNDED', 'FAILED') "
      "AND UPPER(payment_method) <> 'MPESA'",
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
      ],
    ).getSingle();
    final itemsResult = await customSelect(
      'SELECT COALESCE(SUM(psi.quantity), 0) as items_sold '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ?${itemScope.clause} '
      "AND UPPER(ps.status) NOT IN ('VOIDED', 'REFUNDED', 'FAILED') "
      "AND UPPER(ps.payment_method) <> 'MPESA'",
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...itemScope.variables,
      ],
    ).getSingle();
    return {
      'transactionCount': result.read<int>('count'),
      'totalRevenue': result.read<double>('revenue'),
      'avgTicket': result.read<double>('avg_ticket'),
      'itemsSold': (itemsResult.data['items_sold'] as num? ?? 0).toDouble(),
    };
  }

  /// Monthly summary for analytics dashboard.
  Future<Map<String, dynamic>> getMonthlySummary(
    DateTime from,
    DateTime to,
  ) async {
    final scope = _salesBranchScope('pending_sales');
    final itemScope = _salesBranchScope('ps');
    final result = await customSelect(
      'SELECT COALESCE(COUNT(*), 0) as count, COALESCE(SUM(total), 0) as revenue, '
      'COALESCE(AVG(total), 0) as avg_ticket '
      'FROM pending_sales WHERE created_at >= ? AND created_at <= ?${scope.clause} '
      "AND UPPER(status) NOT IN ('VOIDED', 'REFUNDED', 'FAILED') "
      "AND UPPER(payment_method) <> 'MPESA'",
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
      ],
    ).getSingle();
    final itemsResult = await customSelect(
      'SELECT COALESCE(SUM(psi.quantity), 0) as items_sold '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ?${itemScope.clause} '
      "AND UPPER(ps.status) NOT IN ('VOIDED', 'REFUNDED', 'FAILED') "
      "AND UPPER(ps.payment_method) <> 'MPESA'",
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...itemScope.variables,
      ],
    ).getSingle();
    return {
      'transactionCount': result.read<int>('count'),
      'totalRevenue': result.read<double>('revenue'),
      'avgTicket': result.read<double>('avg_ticket'),
      'itemsSold': (itemsResult.data['items_sold'] as num? ?? 0).toDouble(),
    };
  }

  /// Hourly sales breakdown for a date range.
  Future<List<Map<String, dynamic>>> getHourlySales(
    DateTime from,
    DateTime to,
  ) async {
    final scope = _salesBranchScope('pending_sales');
    final result = await customSelect(
      'SELECT strftime(\'%H\', created_at) as hour, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ?${scope.clause} '
      'GROUP BY strftime(\'%H\', created_at) '
      'ORDER BY hour',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
      ],
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
    final scope = _salesBranchScope('pending_sales');
    final result = await customSelect(
      'SELECT date(created_at) as date, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ?${scope.clause} '
      'GROUP BY date(created_at) '
      'ORDER BY date',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
      ],
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
    final scope = _salesBranchScope('ps');
    final result = await customSelect(
      'SELECT date(ps.created_at) as date, COALESCE(SUM(psi.quantity), 0) as items_sold '
      'FROM pending_sales ps '
      'INNER JOIN pending_sale_items psi ON psi.sale_id = ps.id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ?${scope.clause} '
      'GROUP BY date(ps.created_at) '
      'ORDER BY date',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
      ],
    ).get();
    return result
        .map(
          (r) => {
            'date': r.read<String>('date'),
            'itemsSold': (r.data['items_sold'] as num? ?? 0).toDouble(),
          },
        )
        .toList();
  }

  /// Payment summary for analytics.
  Future<Map<String, dynamic>> getPaymentSummary(
    DateTime from,
    DateTime to,
  ) async {
    final scope = _salesBranchScope('pending_sales');
    final result = await customSelect(
      'SELECT '
      'COALESCE(COUNT(*), 0) as transaction_count, '
      'COALESCE(SUM(total), 0.0) as total_amount, '
      'COALESCE(AVG(total), 0.0) as avg_payment, '
      'COALESCE(SUM(CASE WHEN payment_method = \'cash\' THEN 1 ELSE 0 END), 0) as cash_count, '
      'COALESCE(SUM(CASE WHEN payment_method LIKE \'%card%\' OR payment_method LIKE \'%credit%\' THEN 1 ELSE 0 END), 0) as card_count, '
      'COALESCE(SUM(CASE WHEN payment_method LIKE \'%mpesa%\' OR payment_method LIKE \'%pesapal%\' OR payment_method LIKE \'%touristtap%\' THEN 1 ELSE 0 END), 0) as digital_count '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ?${scope.clause}',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
      ],
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
    final scope = _salesBranchScope('pending_sales');
    final result = await customSelect(
      'SELECT strftime(\'%H\', created_at) as hour, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ?${scope.clause} '
      'GROUP BY strftime(\'%H\', created_at) '
      'ORDER BY transaction_count DESC '
      'LIMIT 5',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
      ],
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
    final scope = _salesBranchScope('ps');
    final result = await customSelect(
      'SELECT psi.product_id, psi.product_name, SUM(psi.quantity) as total_qty, SUM(psi.total) as total_revenue '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ?${scope.clause} '
      'GROUP BY psi.product_id, psi.product_name '
      'HAVING total_qty < 5 '
      'ORDER BY total_qty ASC '
      'LIMIT ?',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        ...scope.variables,
        Variable.withInt(limit),
      ],
    ).get();
    return result
        .map(
          (r) => {
            'productId': r.read<String>('product_id'),
            'productName': r.read<String>('product_name'),
            'totalQty': (r.data['total_qty'] as num? ?? 0).toDouble(),
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
    await customStatement('DELETE FROM branches WHERE id = ?', [id]);
  }

  Future<void> updateBranch(
    String id,
    String name,
    String location,
    String phone,
  ) async {
    await customStatement(
      'UPDATE branches SET name = ?, location = ?, phone = ? WHERE id = ?',
      [name, location, phone, id],
    );
  }

  // ════════ CUSTOMERS ════════

  Future<void> createCustomersTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS customers ('
      '  id TEXT PRIMARY KEY NOT NULL, '
      '  tenant_id TEXT, '
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
    try {
      await customStatement('ALTER TABLE customers ADD COLUMN tenant_id TEXT');
    } catch (_) {
      // column already exists
    }
    // Existing rows stay unassigned. Guessing their tenant after a prior
    // account switch could expose one shop's customer data to another shop.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_customers_tenant_name '
      'ON customers (tenant_id, name)',
    );
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
      '  tenant_id TEXT, '
      '  customer_id TEXT NOT NULL, '
      '  amount REAL NOT NULL, '
      '  due_date TEXT NOT NULL, '
      '  note TEXT, '
      '  status TEXT NOT NULL DEFAULT \'pending\', ' // pending, paid, overdue
      '  created_at TEXT NOT NULL, '
      '  paid_at TEXT, '
      '  collection_allocations TEXT'
      ')',
    );
    final columns = await customSelect(
      'PRAGMA table_info(customer_installments)',
    ).get();
    if (!columns
        .any((row) => row.read<String>('name') == 'collection_allocations')) {
      await customStatement(
        'ALTER TABLE customer_installments ADD COLUMN collection_allocations TEXT',
      );
    }
    if (!columns.any((row) => row.read<String>('name') == 'tenant_id')) {
      await customStatement(
        'ALTER TABLE customer_installments ADD COLUMN tenant_id TEXT',
      );
    }
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_customer_installments_tenant_due '
      'ON customer_installments (tenant_id, customer_id, due_date)',
    );
  }

  Future<String> addCustomerInstallment(
    String customerId,
    double amount,
    DateTime dueDate, {
    String? note,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be a positive amount');
    }
    await createCustomerInstallmentsTable();
    final tenantId = _requireCustomerTenantId();
    final customer = await customSelect(
      'SELECT id FROM customers WHERE id = ? AND tenant_id = ?',
      variables: [
        Variable.withString(customerId),
        Variable.withString(tenantId),
      ],
    ).getSingleOrNull();
    if (customer == null) throw StateError('Customer was not found');
    final id = 'inst-${DateTime.now().microsecondsSinceEpoch}';
    await customInsert(
      'INSERT INTO customer_installments (id, tenant_id, customer_id, amount, due_date, note, status, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, \'pending\', ?)',
      variables: [
        Variable.withString(id),
        Variable.withString(tenantId),
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
    final tenantId = _customerTenantId;
    if (tenantId == null) return const [];
    final result = await customSelect(
      'SELECT * FROM customer_installments WHERE customer_id = ? AND tenant_id = ? ORDER BY due_date ASC',
      variables: [
        Variable.withString(customerId),
        Variable.withString(tenantId),
      ],
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
            'collectionAllocations':
                r.readNullable<String>('collection_allocations'),
          },
        )
        .toList();
  }

  /// Persist the exact receivable split before sending a cash collection. If
  /// the server accepts it and the phone loses its reply, retry with the same
  /// allocations and idempotency key instead of collecting the cash twice.
  Future<String> prepareInstallmentCollection(
    String installmentId,
    String allocationsJson,
  ) async {
    await createCustomerInstallmentsTable();
    final tenantId = _requireCustomerTenantId();
    return transaction(() async {
      final current = await customSelect(
        'SELECT status, collection_allocations FROM customer_installments WHERE id = ? AND tenant_id = ?',
        variables: [
          Variable.withString(installmentId),
          Variable.withString(tenantId),
        ],
      ).getSingleOrNull();
      if (current == null) throw StateError('Payment schedule was not found');
      final status = current.read<String>('status').toLowerCase();
      if (status != 'pending' && status != 'overdue') {
        throw StateError('This payment schedule is already complete');
      }
      final existing = current.readNullable<String>('collection_allocations');
      if (existing != null && existing.isNotEmpty) return existing;

      final changed = await customUpdate(
        'UPDATE customer_installments SET collection_allocations = ? '
        'WHERE id = ? AND tenant_id = ? AND status IN (\'pending\', \'overdue\') '
        'AND collection_allocations IS NULL',
        variables: [
          Variable.withString(allocationsJson),
          Variable.withString(installmentId),
          Variable.withString(tenantId),
        ],
      );
      if (changed == 1) return allocationsJson;

      final latest = await customSelect(
        'SELECT collection_allocations FROM customer_installments WHERE id = ? AND tenant_id = ?',
        variables: [
          Variable.withString(installmentId),
          Variable.withString(tenantId),
        ],
      ).getSingleOrNull();
      final saved = latest?.readNullable<String>('collection_allocations');
      if (saved != null && saved.isNotEmpty) return saved;
      throw StateError('Could not prepare this payment. Refresh and retry.');
    });
  }

  Future<bool> markInstallmentPaid(String installmentId) async {
    await createCustomerInstallmentsTable();
    await createCustomersTable();
    final tenantId = _customerTenantId;
    if (tenantId == null) return false;
    return transaction(() async {
      final installment = await customSelect(
        'SELECT customer_id, amount, status FROM customer_installments WHERE id = ? AND tenant_id = ?',
        variables: [
          Variable.withString(installmentId),
          Variable.withString(tenantId),
        ],
      ).getSingleOrNull();
      final status = installment?.read<String>('status').toLowerCase();
      if (installment == null || (status != 'pending' && status != 'overdue')) {
        return false;
      }

      final customerId = installment.read<String>('customer_id');
      final amount = installment.read<double>('amount');
      final paidAt = DateTime.now().toIso8601String();
      final updatedInstallments = await customUpdate(
        'UPDATE customer_installments SET status = \'paid\', paid_at = ? '
        'WHERE id = ? AND tenant_id = ? AND status IN (\'pending\', \'overdue\')',
        variables: [
          Variable.withString(paidAt),
          Variable.withString(installmentId),
          Variable.withString(tenantId),
        ],
      );
      if (updatedInstallments != 1) return false;

      // A stale screen must not let a scheduled amount push the account below
      // zero. If the outstanding balance changed, roll back the paid marker as
      // part of this transaction and ask the caller to refresh.
      final updatedCustomers = await customUpdate(
        'UPDATE customers SET balance = balance - ? '
        'WHERE id = ? AND tenant_id = ? AND balance >= ? - 0.005',
        variables: [
          Variable.withReal(amount),
          Variable.withString(customerId),
          Variable.withString(tenantId),
          Variable.withReal(amount),
        ],
      );
      if (updatedCustomers != 1) {
        throw StateError(
          'The outstanding balance changed. Refresh the customer and try again.',
        );
      }
      return true;
    });
  }

  /// Installments past their due date and still unpaid, across all
  /// customers — used to surface who needs a follow-up call today.
  Future<List<Map<String, dynamic>>> getOverdueInstallments() async {
    await createCustomerInstallmentsTable();
    await createCustomersTable();
    final tenantId = _customerTenantId;
    if (tenantId == null) return const [];
    final result = await customSelect(
      'SELECT ci.*, c.name as customer_name, c.phone as customer_phone '
      'FROM customer_installments ci '
      'JOIN customers c ON c.id = ci.customer_id AND c.tenant_id = ci.tenant_id '
      'WHERE ci.tenant_id = ? AND ci.status = \'pending\' AND ci.due_date < ? '
      'ORDER BY ci.due_date ASC',
      variables: [
        Variable.withString(tenantId),
        Variable.withString(DateTime.now().toIso8601String()),
      ],
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
    final tenantId = _customerTenantId;
    if (tenantId == null) return const [];
    final result = await customSelect(
      'SELECT * FROM customers WHERE tenant_id = ? AND (name LIKE ? OR phone LIKE ?) ORDER BY total_purchases DESC LIMIT 20',
      variables: [
        Variable.withString(tenantId),
        Variable.withString('%$query%'),
        Variable.withString('%$query%'),
      ],
    ).get();
    return result.map(_customerRowToMap).toList();
  }

  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    await createCustomersTable();
    final tenantId = _customerTenantId;
    if (tenantId == null) return const [];
    final result = await customSelect(
      'SELECT * FROM customers WHERE tenant_id = ? ORDER BY name ASC',
      variables: [Variable.withString(tenantId)],
    ).get();
    return result.map(_customerRowToMap).toList();
  }

  Future<Map<String, dynamic>?> getCustomer(String id) async {
    await createCustomersTable();
    final tenantId = _customerTenantId;
    if (tenantId == null) return null;
    final result = await customSelect(
      'SELECT * FROM customers WHERE id = ? AND tenant_id = ?',
      variables: [Variable.withString(id), Variable.withString(tenantId)],
    ).get();
    if (result.isEmpty) return null;
    return _customerRowToMap(result.first);
  }

  /// Debt portions on local credit/split sales that have not reached the
  /// server yet. Callers merge these into cloud receivables so offline sales
  /// stay visible without trusting stale local balances after online payments.
  Future<List<Map<String, dynamic>>> getUnsyncedCustomerDebtSales({
    String? branchId,
  }) async {
    await createCustomersTable();
    final tenantId = _customerTenantId;
    if (tenantId == null ||
        branchId == null ||
        branchId.isEmpty ||
        !_activeBranchIds().contains(branchId)) {
      return const [];
    }
    final rows = await customSelect(
      "SELECT id, customer_id, receipt_number, total, payment_method, "
      "payment_reference FROM pending_sales "
      "WHERE is_synced = 0 AND customer_id IS NOT NULL "
      "AND UPPER(status) NOT IN ('VOIDED', 'REFUNDED', 'FAILED', 'CANCELLED') "
      "AND UPPER(payment_method) IN ('CREDIT', 'SPLIT')"
      ' AND branch_id = ?',
      variables: [Variable.withString(branchId)],
    ).get();
    final debtSales = <Map<String, dynamic>>[];
    for (final row in rows) {
      final method = row.read<String>('payment_method').toUpperCase();
      var amount = 0.0;
      if (method == 'CREDIT') {
        amount = row.read<double>('total');
      } else {
        final reference = row.readNullable<String>('payment_reference');
        if (reference == null || reference.isEmpty) continue;
        try {
          final tenders = jsonDecode(reference);
          if (tenders is! List) continue;
          amount = tenders.whereType<Map>().where((tender) {
            return (tender['method'] ?? '').toString().toUpperCase() ==
                'CREDIT';
          }).fold<double>(0, (sum, tender) {
            final value = tender['amount'];
            final parsed =
                value is num ? value.toDouble() : double.tryParse('$value');
            return sum + (parsed != null && parsed.isFinite ? parsed : 0);
          });
        } catch (_) {
          // An unreadable split record must not take down the customer profile.
          continue;
        }
      }
      if (!amount.isFinite || amount <= 0.005) continue;
      debtSales.add({
        'id': row.read<String>('id'),
        'customerId': row.read<String>('customer_id'),
        'receiptNumber': row.read<String>('receipt_number'),
        'amount': amount,
      });
    }
    return debtSales;
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
    final tenantId = _requireCustomerTenantId();
    // Check if customer exists by name (case-insensitive)
    final existing = await customSelect(
      'SELECT id FROM customers WHERE tenant_id = ? AND LOWER(name) = LOWER(?)',
      variables: [Variable.withString(tenantId), Variable.withString(name)],
    ).get();
    if (existing.isNotEmpty) {
      final existingId = existing.first.read<String>('id');
      // Update contact/location details if provided
      if (phone != null && phone.isNotEmpty) {
        await customStatement(
          'UPDATE customers SET phone = ? WHERE id = ? AND tenant_id = ?',
          [phone, existingId, tenantId],
        );
      }
      if (location != null && location.isNotEmpty) {
        await customStatement(
          'UPDATE customers SET location = ? WHERE id = ? AND tenant_id = ?',
          [location, existingId, tenantId],
        );
      }
      return existingId;
    }
    // Insert new
    await customInsert(
      'INSERT INTO customers (id, tenant_id, name, phone, email, location, notes, total_purchases, total_spent, created_at, balance, credit_limit, loyalty_points) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?, 0)',
      variables: [
        Variable.withString(id),
        Variable.withString(tenantId),
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

  Future<void> upsertCustomerById(
    String id,
    String name, {
    String? phone,
    String? location,
    String? email,
    String? expectedTenantId,
  }) async {
    await upsertCustomersById([
      {
        'id': id,
        'name': name,
        'phone': phone,
        'location': location,
        'email': email,
      },
    ], expectedTenantId: expectedTenantId);
  }

  /// Cache server-confirmed customers under the active tenant. This also
  /// restores the usable directory after upgrading from the older unscoped
  /// local customer cache.
  Future<void> upsertCustomersById(Iterable<Map<String, dynamic>> customers,
      {String? expectedTenantId}) async {
    final records = customers.where((customer) {
      final id = customer['id']?.toString().trim() ?? '';
      return id.isNotEmpty;
    }).toList();
    if (records.isEmpty) return;

    await createCustomersTable();
    final tenantId = _requireCustomerTenantId();
    if (expectedTenantId != null && expectedTenantId != tenantId) return;
    await transaction(() async {
      if (_customerTenantId != tenantId) return;
      for (final customer in records) {
        final id = customer['id'].toString().trim();
        final name = customer['name']?.toString().trim() ?? '';
        await customStatement(
          '''
        INSERT INTO customers (
          id, tenant_id, name, phone, email, location, notes,
          total_purchases, total_spent, created_at,
          balance, credit_limit, loyalty_points
        ) VALUES (?, ?, ?, ?, ?, ?, '', 0, 0, ?, 0, 0, 0)
        ON CONFLICT(id) DO UPDATE SET
          tenant_id = excluded.tenant_id,
          name = excluded.name,
          phone = excluded.phone,
          email = excluded.email,
          location = excluded.location
        WHERE customers.tenant_id = excluded.tenant_id
           OR customers.tenant_id IS NULL
          ''',
          [
            id,
            tenantId,
            name,
            customer['phone']?.toString() ?? '',
            customer['email']?.toString() ?? '',
            (customer['location'] ?? customer['address'])?.toString() ?? '',
            DateTime.now().toIso8601String(),
          ],
        );
        // A server-confirmed customer may have a pre-upgrade local schedule.
        // Claim it only when the current tenant's server sent this same ID.
        await customStatement(
          'UPDATE customer_installments SET tenant_id = ? '
          'WHERE customer_id = ? AND tenant_id IS NULL '
          'AND EXISTS (SELECT 1 FROM customers WHERE id = ? AND tenant_id = ?)',
          [tenantId, id, id, tenantId],
        );
      }
    });
  }

  // Customer Debt/Balance Management
  // NOTE: customStatement takes a positional List of RAW values, not
  // Variable wrappers (those belong to customSelect/customInsert's named
  // `variables:` argument). Passing Variable objects here throws
  // "Allowed parameters must either be null or bool, int, num, String...".
  Future<void> updateCustomerBalance(String customerId, double amount) async {
    await createCustomersTable();
    final tenantId = _requireCustomerTenantId();
    await customStatement(
      'UPDATE customers SET balance = balance + ? WHERE id = ? AND tenant_id = ?',
      [amount, customerId, tenantId],
    );
  }

  Future<void> setCustomerBalance(String customerId, double amount) async {
    await createCustomersTable();
    final tenantId = _requireCustomerTenantId();
    await customStatement(
      'UPDATE customers SET balance = ? WHERE id = ? AND tenant_id = ?',
      [amount, customerId, tenantId],
    );
  }

  Future<void> setCustomerCreditLimit(String customerId, double limit) async {
    await createCustomersTable();
    final tenantId = _requireCustomerTenantId();
    await customStatement(
      'UPDATE customers SET credit_limit = ? WHERE id = ? AND tenant_id = ?',
      [limit, customerId, tenantId],
    );
  }

  Future<void> addLoyaltyPoints(String customerId, int points) async {
    await createCustomersTable();
    final tenantId = _requireCustomerTenantId();
    await customStatement(
      'UPDATE customers SET loyalty_points = loyalty_points + ? WHERE id = ? AND tenant_id = ?',
      [points, customerId, tenantId],
    );
  }

  Future<void> redeemLoyaltyPoints(String customerId, int points) async {
    await createCustomersTable();
    final tenantId = _requireCustomerTenantId();
    await customStatement(
      'UPDATE customers SET loyalty_points = loyalty_points - ? WHERE id = ? AND tenant_id = ? AND loyalty_points >= ?',
      [points, customerId, tenantId, points],
    );
  }

  Future<List<Map<String, dynamic>>> getCustomersWithDebt() async {
    await createCustomersTable();
    final tenantId = _customerTenantId;
    if (tenantId == null) return const [];
    final result = await customSelect(
      'SELECT * FROM customers WHERE tenant_id = ? AND balance > 0 ORDER BY balance DESC',
      variables: [Variable.withString(tenantId)],
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
    final tenantId = _requireCustomerTenantId();
    await customStatement(
      'UPDATE customers SET total_purchases = total_purchases + 1, '
      'total_spent = total_spent + ?, last_purchase_at = ? WHERE id = ? AND tenant_id = ?',
      [
        amount,
        DateTime.now().toIso8601String(),
        customerId,
        tenantId,
      ],
    );
  }

  /// Get top products a specific customer buys (AI recommendation).
  Future<List<Map<String, dynamic>>> getCustomerTopProducts(
    String customerId,
  ) async {
    final tenantId = _customerTenantId;
    final scope = _salesBranchScope('ps');
    if (tenantId == null || _activeBranchIds().isEmpty) return const [];
    await createCustomersTable();
    final result = await customSelect(
      'SELECT psi.product_id, psi.product_name, SUM(psi.quantity) as total_qty, COUNT(*) as times_bought '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'INNER JOIN customers c ON c.id = ps.customer_id '
      'WHERE ps.customer_id = ? AND c.tenant_id = ?${scope.clause} '
      'GROUP BY psi.product_id, psi.product_name '
      'ORDER BY total_qty DESC LIMIT 10',
      variables: [
        Variable.withString(customerId),
        Variable.withString(tenantId),
        ...scope.variables,
      ],
    ).get();
    return result
        .map(
          (r) => <String, dynamic>{
            'productId': r.read<String>('product_id'),
            'productName': r.read<String>('product_name'),
            'totalQty': (r.data['total_qty'] as num? ?? 0).toDouble(),
            'timesBought': r.read<int>('times_bought'),
          },
        )
        .toList();
  }

  /// Customer sale history constrained by both the current workspace and its
  /// active branches. Screens must not query pending_sales directly because
  /// this device can retain rows from a previous shop.
  Future<List<QueryRow>> getSalesForCustomer(String customerId) async {
    final tenantId = _customerTenantId;
    final scope = _salesBranchScope('ps');
    if (tenantId == null || _activeBranchIds().isEmpty) return const [];
    await createCustomersTable();
    return customSelect(
      'SELECT ps.* FROM pending_sales ps '
      'INNER JOIN customers c ON c.id = ps.customer_id '
      'WHERE ps.customer_id = ? AND c.tenant_id = ?${scope.clause} '
      'ORDER BY ps.created_at DESC',
      variables: [
        Variable.withString(customerId),
        Variable.withString(tenantId),
        ...scope.variables,
      ],
    ).get();
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
    )..where((c) => c.id.equals(id)))
        .getSingleOrNull();
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

  Future<void> deleteProductCacheReferences(String productId) async {
    await transaction(() async {
      await (delete(productPricingTiers)
            ..where((t) => t.productId.equals(productId)))
          .go();
      await (delete(localStock)..where((s) => s.productId.equals(productId)))
          .go();
      await (delete(favoriteProducts)
            ..where((f) => f.productId.equals(productId)))
          .go();
      await deleteProduct(productId);
    });
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
    final tenantId = _requireCustomerTenantId();
    final existing = await customSelect(
      'SELECT id FROM suppliers WHERE tenant_id = ? AND (name = ? OR phone = ?)',
      variables: [
        Variable.withString(tenantId),
        Variable.withString(name),
        Variable.withString(phone ?? ''),
      ],
    ).getSingleOrNull();

    if (existing != null) return existing.read<String>('id');

    final now = DateTime.now().toIso8601String();
    await customStatement(
      'INSERT OR IGNORE INTO suppliers (id, tenant_id, name, phone, email, is_active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 1, ?, ?)',
      [id, tenantId, name, phone, email, now, now],
    );
    return id;
  }

  /// Get all suppliers with their debt balances
  Future<List<Map<String, dynamic>>> getSupplierDebts() async {
    await _createSupplierFinanceTables();
    final tenantId = _customerTenantId;
    if (tenantId == null) return const [];
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
      WHERE s.is_active = 1 AND s.tenant_id = ?
      GROUP BY s.id
      ORDER BY s.name ASC
    ''', variables: [Variable.withString(tenantId)]).get();

    return result
        .map(
          (row) => {
            'id': row.read<String>('id'),
            'name': row.read<String>('name'),
            'phone': row.read<String?>('phone') ?? '',
            'email': row.read<String?>('email') ?? '',
            'totalInvoiced': row.read<double?>('total_invoiced') ?? 0,
            'totalOwed': ((row.read<double?>('total_invoiced') ?? 0) -
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
    final tenantId = _requireCustomerTenantId();
    final supplier = await customSelect(
      'SELECT id FROM suppliers WHERE id = ? AND tenant_id = ?',
      variables: [
        Variable.withString(supplierId),
        Variable.withString(tenantId),
      ],
    ).getSingleOrNull();
    if (supplier == null) throw StateError('Supplier not found in this shop');
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
    final tenantId = _customerTenantId;
    if (tenantId == null) return const [];
    final result = await customSelect(
      'SELECT sp.id, sp.amount, sp.notes, sp.payment_date '
      'FROM supplier_payments sp INNER JOIN suppliers s ON s.id = sp.supplier_id '
      'WHERE sp.supplier_id = ? AND s.tenant_id = ? ORDER BY sp.payment_date DESC',
      variables: [
        Variable.withString(supplierId),
        Variable.withString(tenantId),
      ],
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
    final tenantId = _customerTenantId;
    if (tenantId == null) return const [];
    final suppliers = await customSelect(
      'SELECT * FROM suppliers WHERE tenant_id = ?',
      variables: [Variable.withString(tenantId)],
    ).get();
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
    final tenantId = _customerTenantId;
    if (tenantId == null) return const [];
    final result = await customSelect(
      'SELECT si.* FROM supplier_invoices si '
      'INNER JOIN suppliers s ON s.id = si.supplier_id '
      'WHERE si.supplier_id = ? AND s.tenant_id = ? ORDER BY si.created_at DESC',
      variables: [
        Variable.withString(supplierId),
        Variable.withString(tenantId),
      ],
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
    String? invoiceId,
    String? branchId,
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
    final stableInvoiceId = invoiceId?.trim();
    if (stableInvoiceId != null && stableInvoiceId.isNotEmpty) {
      final existing = await customSelect(
        'SELECT id FROM supplier_invoices WHERE id = ?',
        variables: [Variable.withString(stableInvoiceId)],
      ).getSingleOrNull();
      if (existing != null) return stableInvoiceId;
    }
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final supplierId = await insertOrGetSupplier(
      'supplier-${now.microsecondsSinceEpoch}',
      supplierName,
      phone: phone,
      email: email,
    );
    final invoiceRecordId = stableInvoiceId == null || stableInvoiceId.isEmpty
        ? 'supplier-invoice-${now.microsecondsSinceEpoch}'
        : stableInvoiceId;
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
          invoiceRecordId,
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

      final targetBranchId =
          branchId ?? _storage.getBranchId() ?? 'branch-main';
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
          branchId: targetBranchId,
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
            invoiceRecordId,
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
          notes:
              'Initial payment for invoice ${invoiceNumber ?? invoiceRecordId}',
        );
      }
    });

    return invoiceRecordId;
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
    final productId = existing?.read<String>('id') ??
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
        quantity,
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
    final prefix =
        cleaned.isEmpty ? 'ITEM' : cleaned.split('-').take(3).join('-');
    return 'SUP-$prefix';
  }
}
