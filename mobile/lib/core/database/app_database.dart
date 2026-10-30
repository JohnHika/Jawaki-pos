import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:uuid/uuid.dart';
import '../services/storage_service.dart';
import '../utils/format.dart';

import 'secure_database.dart';

part 'app_database.g.dart';

class LocalSaleVoidConflict implements Exception {
  const LocalSaleVoidConflict(this.message);

  final String message;

  @override
  String toString() => message;
}

class CustomerInsertOutcome {
  const CustomerInsertOutcome({
    required this.id,
    required this.name,
    required this.created,
  });

  final String id;
  final String name;
  final bool created;
}

String _customerPhoneIdentity(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('254') && digits.length == 12) {
    return digits.substring(3);
  }
  if (digits.startsWith('0') && digits.length == 10) {
    return digits.substring(1);
  }
  return digits;
}

String _customerEmailIdentity(String? value) =>
    (value ?? '').trim().toLowerCase();

const double _maxSafeLocalSaleAmount = 90071992547409.9;

bool _sameLocalCurrencyAmount(double left, double right) =>
    left.isFinite &&
    right.isFinite &&
    left.abs() <= _maxSafeLocalSaleAmount &&
    right.abs() <= _maxSafeLocalSaleAmount &&
    (roundCurrency(left) * 100).round() == (roundCurrency(right) * 100).round();

bool _hasValidLocalSplitTenders({
  required String? reference,
  required double total,
  required double debtAmount,
}) {
  if (reference == null || reference.isEmpty) return false;
  try {
    final decoded = jsonDecode(reference);
    if (decoded is! List || decoded.length != 2) return false;

    double? cashAmount;
    double? creditAmount;
    for (final row in decoded) {
      if (row is! Map) return false;
      final method = row['method']?.toString().trim().toUpperCase();
      final rawAmount = row['amount'];
      if (rawAmount is! num) return false;
      final amount = rawAmount.toDouble();
      if (!amount.isFinite || amount <= 0 || amount > _maxSafeLocalSaleAmount) {
        return false;
      }
      if (method == 'CASH' && cashAmount == null) {
        cashAmount = amount;
      } else if (method == 'CREDIT' && creditAmount == null) {
        creditAmount = amount;
      } else {
        return false;
      }
    }

    return cashAmount != null &&
        creditAmount != null &&
        _sameLocalCurrencyAmount(cashAmount + creditAmount, total) &&
        _sameLocalCurrencyAmount(creditAmount, debtAmount);
  } catch (_) {
    return false;
  }
}

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
  TextColumn get metadata => text().withDefault(const Constant('{}'))();
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

  /// Active workspace identity for callers that need to pin an async sync
  /// batch to the session that selected its local records.
  String? get activeTenantId => _customerTenantId;

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
      16; // v16: branch/date index for responsive local sales summaries

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          try {
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_pending_sales_branch_created '
              'ON pending_sales (branch_id, created_at)',
            );
          } catch (e) {
            debugPrint('[DB] skip pending sales index: $e');
          }
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
          if (from >= 9 && from < 15) {
            // Products are a rebuildable API cache, but retain the catalog
            // during this additive upgrade and make metadata available offline.
            final productTable = await customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type = 'table' AND name = 'products'",
            ).getSingleOrNull();
            if (productTable != null) {
              await m.addColumn(products, products.metadata);
            }
          }
          if (from < 16) {
            // This is a pure performance index. A damaged or unusual legacy
            // file must still open so the owner can use their existing data.
            try {
              await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_pending_sales_branch_created '
                'ON pending_sales (branch_id, created_at)',
              );
            } catch (e) {
              debugPrint('[DB] skip pending sales index: $e');
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

  Future<void> _ensureLocalAiMemoriesTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_ai_memories (
        id TEXT NOT NULL PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        type TEXT NOT NULL,
        title TEXT,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_ai_memories_tenant_created '
      'ON local_ai_memories (tenant_id, created_at DESC)',
    );
  }

  /// Lists private, device-local AI notes for the active shop. These notes are
  /// never included in Axon Gateway requests automatically.
  Future<List<Map<String, dynamic>>> getLocalAiMemories() async {
    final tenantId = _requireCustomerTenantId();
    await _ensureLocalAiMemoriesTable();
    final rows = await customSelect(
      'SELECT id, type, title, content, created_at AS createdAt '
      'FROM local_ai_memories WHERE tenant_id = ? '
      'ORDER BY created_at DESC, id',
      variables: [Variable.withString(tenantId)],
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  Future<String> addLocalAiMemory({
    required String type,
    String? title,
    required String content,
  }) async {
    final tenantId = _requireCustomerTenantId();
    final normalizedContent = content.trim();
    final normalizedTitle = title?.trim();
    if (!const {'fact', 'preference', 'customer', 'policy'}.contains(type) ||
        normalizedContent.isEmpty ||
        normalizedContent.length > 2000 ||
        (normalizedTitle?.length ?? 0) > 60) {
      throw const FormatException('Check the memory details and try again.');
    }
    await _ensureLocalAiMemoriesTable();
    final id = const Uuid().v4();
    await customStatement(
      'INSERT INTO local_ai_memories '
      '(id, tenant_id, type, title, content, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        id,
        tenantId,
        type,
        normalizedTitle == null || normalizedTitle.isEmpty
            ? null
            : normalizedTitle,
        normalizedContent,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    return id;
  }

  Future<bool> deleteLocalAiMemory(String id) async {
    final tenantId = _requireCustomerTenantId();
    await _ensureLocalAiMemoriesTable();
    final deleted = await customUpdate(
      'DELETE FROM local_ai_memories WHERE id = ? AND tenant_id = ?',
      variables: [
        Variable.withString(id),
        Variable.withString(tenantId),
      ],
    );
    return deleted > 0;
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
        branch_id TEXT,
        amount REAL NOT NULL,
        notes TEXT,
        payment_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        invoice_id TEXT,
        request_id TEXT,
        funding_source TEXT NOT NULL DEFAULT 'CASH_TILL',
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
      )
    ''');
    final paymentColumns = await customSelect(
      'PRAGMA table_info(supplier_payments)',
    ).get();
    if (!paymentColumns
        .any((row) => row.read<String>('name') == 'invoice_id')) {
      try {
        await customStatement(
          'ALTER TABLE supplier_payments ADD COLUMN invoice_id TEXT',
        );
      } catch (_) {
        // Another concurrent Finance read may have applied this upgrade.
      }
    }
    if (!paymentColumns
        .any((row) => row.read<String>('name') == 'request_id')) {
      try {
        await customStatement(
          'ALTER TABLE supplier_payments ADD COLUMN request_id TEXT',
        );
      } catch (_) {
        // Another concurrent Finance read may have applied this upgrade.
      }
    }
    if (!paymentColumns
        .any((row) => row.read<String>('name') == 'funding_source')) {
      try {
        await customStatement(
          "ALTER TABLE supplier_payments ADD COLUMN funding_source TEXT NOT NULL DEFAULT 'CASH_TILL'",
        );
      } catch (_) {
        // Another concurrent Finance read may have applied this upgrade.
      }
    }
    if (!paymentColumns.any((row) => row.read<String>('name') == 'branch_id')) {
      try {
        await customStatement(
          'ALTER TABLE supplier_payments ADD COLUMN branch_id TEXT',
        );
      } catch (_) {
        // Another concurrent Finance read may have applied this upgrade.
      }
    }
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_supplier_payment_request ON supplier_payments(request_id) WHERE request_id IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_supplier_payment_branch_date ON supplier_payments (branch_id, payment_date)',
    );
    final activeBranches = _activeBranchIds();
    final tenantId = _customerTenantId;
    if (activeBranches.length == 1 && tenantId != null) {
      // Older single-branch standalone payments had no branch column. It is
      // safe to attribute those to the only branch in the local workspace;
      // multi-branch history stays unassigned rather than inflating a till.
      await customStatement(
        'UPDATE supplier_payments SET branch_id = ? '
        'WHERE branch_id IS NULL AND supplier_id IN '
        '(SELECT id FROM suppliers WHERE tenant_id = ?)',
        [activeBranches.single, tenantId],
      );
    }
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
        funding_source TEXT NOT NULL DEFAULT 'CASH_TILL',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
      )
    ''');
    final invoiceColumns = await customSelect(
      'PRAGMA table_info(supplier_invoices)',
    ).get();
    if (!invoiceColumns
        .any((row) => row.read<String>('name') == 'funding_source')) {
      try {
        await customStatement(
          "ALTER TABLE supplier_invoices ADD COLUMN funding_source TEXT NOT NULL DEFAULT 'CASH_TILL'",
        );
      } catch (_) {
        // Another concurrent Finance read may have applied this upgrade.
      }
    }
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

  Future<void> ensureLocalSupplierFinanceSchema() =>
      _createSupplierFinanceTables();

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

  /// Clears the locally cached catalog and its dependent metadata on logout.
  /// This prevents stale data from appearing after a different tenant logs
  /// in. Cart, pending sales, and the sync queue survive because they may
  /// hold unsynced offline data.
  Future<void> clearCatalogCache() async {
    await transaction(() async {
      await delete(productPricingTiers).go();
      await delete(branchPrices).go();
      await delete(localStock).go();
      await delete(favoriteProducts).go();
      await delete(recentSearches).go();
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

  /// Reads only sellable catalog rows for the POS. Archived products remain
  /// available to product management and the local server, but should not be
  /// materialized (or trigger pricing/stock lookups) during checkout.
  Future<List<Product>> getActivePosProducts({
    String? categoryId,
    String? searchQuery,
    Iterable<String>? productIds,
    int? limit,
    int offset = 0,
  }) async {
    final normalizedSearch = searchQuery?.trim();
    final hasSearch = normalizedSearch != null && normalizedSearch.isNotEmpty;
    final ids = productIds
        ?.map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (ids == null) {
      final query = select(products)..where((p) => p.isActive.equals(true));
      if (categoryId != null && categoryId.isNotEmpty) {
        query.where((p) => p.categoryId.equals(categoryId));
      }
      if (hasSearch) {
        final like = '%$normalizedSearch%';
        query.where((p) =>
            p.name.like(like) | p.sku.like(like) | p.metadata.like(like));
      }
      query.orderBy([
        (p) => OrderingTerm.asc(p.name),
        (p) => OrderingTerm.asc(p.id),
      ]);
      if (limit != null) {
        query.limit(limit, offset: offset.clamp(0, 0x7fffffff));
      } else if (offset > 0) {
        query.limit(0x7fffffff, offset: offset.clamp(0, 0x7fffffff));
      }
      return query.get();
    }
    if (ids.isEmpty) return const <Product>[];

    // SQLite limits the number of bound variables per statement. Keep page
    // ids chunked and restore the configured page order after the query.
    final productsById = <String, Product>{};
    for (var offset = 0; offset < ids.length; offset += 400) {
      final chunk = ids.skip(offset).take(400).toList(growable: false);
      final query = select(products)
        ..where((p) => p.isActive.equals(true) & p.id.isIn(chunk));
      if (categoryId != null && categoryId.isNotEmpty) {
        query.where((p) => p.categoryId.equals(categoryId));
      }
      if (hasSearch) {
        final like = '%$normalizedSearch%';
        query.where((p) =>
            p.name.like(like) | p.sku.like(like) | p.metadata.like(like));
      }
      for (final product in await query.get()) {
        productsById[product.id] = product;
      }
    }
    return ids
        .map((id) => productsById[id])
        .whereType<Product>()
        .toList(growable: false);
  }

  /// Loads only products assigned to a POS quick page. Large shops can have
  /// thousands of catalog rows while each quick page contains a small set;
  /// querying that set directly avoids mapping every product and fetching
  /// pricing and stock metadata for products that cannot appear on the page.
  Future<List<Product>> getProductsByIds(Iterable<String> productIds) async {
    final ids = productIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <Product>[];

    final productsById = <String, Product>{};
    for (var offset = 0; offset < ids.length; offset += 400) {
      final chunk = ids.skip(offset).take(400).toList(growable: false);
      final rows =
          await (select(products)..where((p) => p.id.isIn(chunk))).get();
      for (final product in rows) {
        productsById[product.id] = product;
      }
    }

    return ids
        .map((id) => productsById[id])
        .whereType<Product>()
        .toList(growable: false);
  }

  Future<List<Product>> searchProducts(String query) {
    return (select(
      products,
    )..where((p) =>
            p.name.like('%$query%') |
            p.sku.like('%$query%') |
            p.metadata.like('%$query%')))
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
                  product.sku.like('%$normalized%') |
                  product.metadata.like('%$normalized%')))
          ..orderBy([(product) => OrderingTerm.asc(product.name)])
          ..limit(safeLimit))
        .watch();
  }

  Stream<List<Product>> watchAllProducts() => select(products).watch();

  /// Watches only the rows the catalogue can currently show. Filtering the
  /// active/archive state, category, and broad search candidates in SQLite
  /// avoids loading the entire shop catalog into Dart on every query change.
  /// The screen still applies its business-layout-aware matcher so metadata
  /// fields that are hidden for a shop can never create visible false matches.
  Stream<List<Product>> watchCatalogProducts({
    required bool isActive,
    String? categoryId,
    String? searchQuery,
  }) {
    final query = select(products)
      ..where((product) => product.isActive.equals(isActive));
    if (categoryId != null) {
      query.where((product) => product.categoryId.equals(categoryId));
    }
    final normalizedSearch = searchQuery?.trim();
    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      final candidate = '%$normalizedSearch%';
      query.where((product) =>
          product.name.like(candidate) |
          product.sku.like(candidate) |
          product.metadata.like(candidate));
    }
    query.orderBy([
      (product) => OrderingTerm.asc(product.name),
      (product) => OrderingTerm.asc(product.id),
    ]);
    return query.watch();
  }

  Future<void> insertProducts(List<ProductsCompanion> items) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(products, items);
    });
  }

  /// Publishes one remote catalog page locally while the remaining pages are
  /// still downloading. The page's products, pricing tiers and stock commit
  /// together so the POS never sees a product without its current sale data.
  /// Unsynced local sales are subtracted before stock is exposed to checkout.
  Future<void> cacheCatalogPage({
    required List<ProductsCompanion> items,
    required List<ProductPricingTiersCompanion> tierItems,
    required List<LocalStockCompanion> stockItems,
    required String? branchId,
  }) async {
    final productIds = items
        .map((item) => item.id.value)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (productIds.isEmpty) return;

    await transaction(() async {
      await batch((batch) {
        batch.insertAllOnConflictUpdate(products, items);
      });

      await (delete(productPricingTiers)
            ..where((tier) => tier.productId.isIn(productIds)))
          .go();
      if (tierItems.isNotEmpty) {
        await batch((batch) {
          batch.insertAllOnConflictUpdate(productPricingTiers, tierItems);
        });
      }

      if (branchId == null ||
          stockItems.isEmpty ||
          _customerTenantId == null ||
          !_activeBranchIds().contains(branchId)) {
        return;
      }

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
              ..where((item) =>
                  item.saleId.isIn(pendingSaleIds) &
                  item.productId.isIn(productIds)))
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
      final reconciledStock = stockItems.map((item) {
        final productId = item.productId.value;
        return item.copyWith(
          quantity: Value(
              item.quantity.value - (pendingQuantityByProduct[productId] ?? 0)),
          updatedAt: Value(now),
        );
      }).toList(growable: false);
      await batch((batch) {
        batch.insertAllOnConflictUpdate(localStock, reconciledStock);
      });
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
    bool recordLocalCustomerPurchase = false,
  }) async {
    await transaction(() async {
      if (decrementLocalStock) {
        final subtotal = sale.subtotal.value;
        final discount = sale.discount.present ? sale.discount.value : 0.0;
        final tax = sale.tax.present ? sale.tax.value : 0.0;
        final total = sale.total.value;
        var lineSubtotal = 0.0;
        if (items.isEmpty ||
            !subtotal.isFinite ||
            subtotal <= 0 ||
            subtotal > _maxSafeLocalSaleAmount ||
            !discount.isFinite ||
            discount < 0 ||
            discount > subtotal + 0.005 ||
            !tax.isFinite ||
            tax < 0 ||
            tax > _maxSafeLocalSaleAmount ||
            !total.isFinite ||
            total <= 0 ||
            total > _maxSafeLocalSaleAmount) {
          throw StateError('Check the sale amounts and try again.');
        }
        for (final item in items) {
          if (!item.quantity.present ||
              !item.unitPrice.present ||
              !item.total.present) {
            throw StateError(
                'A sale item is incomplete. Refresh the cart and try again.');
          }
          final quantity = item.quantity.value;
          final unitPrice = item.unitPrice.value;
          final itemDiscount =
              item.discount.present ? item.discount.value : 0.0;
          final lineTotal = item.total.value;
          final gross = quantity * unitPrice;
          if (!quantity.isFinite ||
              quantity <= 0 ||
              !unitPrice.isFinite ||
              unitPrice < 0 ||
              !itemDiscount.isFinite ||
              itemDiscount < 0 ||
              !gross.isFinite ||
              gross > _maxSafeLocalSaleAmount ||
              itemDiscount > gross + 0.005 ||
              !lineTotal.isFinite ||
              lineTotal < 0 ||
              !_sameLocalCurrencyAmount(lineTotal, gross - itemDiscount)) {
            throw StateError(
                'A sale item price changed. Refresh the cart and try again.');
          }
          lineSubtotal += lineTotal;
          if (!lineSubtotal.isFinite ||
              lineSubtotal > _maxSafeLocalSaleAmount) {
            throw StateError('The sale amount is too large to record.');
          }
        }
        if (!_sameLocalCurrencyAmount(subtotal, lineSubtotal) ||
            !_sameLocalCurrencyAmount(
              total,
              roundCurrency(subtotal - discount + tax),
            )) {
          throw StateError(
              'The sale total no longer matches its items and tax. Refresh the cart and try again.');
        }
        if (!customerBalanceDelta.isFinite ||
            customerBalanceDelta < 0 ||
            customerBalanceDelta > total + 0.005) {
          throw StateError('Check the customer balance for this sale.');
        }
        final method = sale.paymentMethod.value.trim().toUpperCase();
        final paymentReference =
            sale.paymentReference.present ? sale.paymentReference.value : null;
        if ((method == 'CREDIT' &&
                !_sameLocalCurrencyAmount(customerBalanceDelta, total)) ||
            (method == 'SPLIT' &&
                !_hasValidLocalSplitTenders(
                  reference: paymentReference,
                  total: total,
                  debtAmount: customerBalanceDelta,
                )) ||
            (method != 'CREDIT' &&
                method != 'SPLIT' &&
                customerBalanceDelta != 0)) {
          throw StateError(
              'The recorded payment does not match the sale tender.');
        }
      }
      await into(pendingSales).insert(sale);
      await batch((batch) {
        batch.insertAll(pendingSaleItems, items);
      });

      // A local sale, its stock deductions, customer aggregates, and any new
      // customer debt must commit together. Otherwise an error between these
      // writes can leave a receipt without matching records and a retry can
      // double-charge.
      if (customerBalanceDelta != 0) {
        final customerId =
            sale.customerId.present ? sale.customerId.value : null;
        if (customerId == null || customerId.isEmpty) {
          throw StateError('A customer is required for a debt sale');
        }
        await createCustomersTable();
        final tenantId = _requireCustomerTenantId();
        final updatedCustomers = await customUpdate(
          'UPDATE customers SET balance = balance + ? '
          'WHERE id = ? AND tenant_id = ? '
          'AND (credit_limit <= 0 OR balance + ? <= credit_limit + 0.005)',
          variables: [
            Variable.withReal(customerBalanceDelta),
            Variable.withString(customerId),
            Variable.withString(tenantId),
            Variable.withReal(customerBalanceDelta),
          ],
        );
        if (updatedCustomers != 1) {
          final customer = await customSelect(
            'SELECT balance, credit_limit FROM customers '
            'WHERE id = ? AND tenant_id = ?',
            variables: [
              Variable.withString(customerId),
              Variable.withString(tenantId),
            ],
          ).getSingleOrNull();
          if (customer == null) {
            throw StateError('The selected customer could not be found');
          }
          final balance = customer.read<double>('balance');
          final creditLimit = customer.read<double>('credit_limit');
          if (customerBalanceDelta > 0 &&
              creditLimit > 0 &&
              balance + customerBalanceDelta > creditLimit + 0.005) {
            throw StateError(
              'This sale would exceed the customer’s saved credit limit. Choose cash or collect part of the balance first.',
            );
          }
          throw StateError('The selected customer could not be updated');
        }
      }

      // In standalone mode, the sale and customer lifetime totals are one
      // local operation. Do not leave a committed receipt with stale customer
      // purchase totals if the app closes during checkout.
      if (recordLocalCustomerPurchase &&
          sale.status.present &&
          sale.status.value.toUpperCase() == 'COMPLETED') {
        final customerId =
            sale.customerId.present ? sale.customerId.value : null;
        if (customerId == null || customerId.isEmpty) {
          // Anonymous sales do not have customer purchase totals to update.
        } else {
          final tenantId = _requireCustomerTenantId();
          await createCustomersTable();
          final purchaseTotal = sale.total.value;
          if (!purchaseTotal.isFinite || purchaseTotal < 0) {
            throw StateError('Check the customer purchase amount.');
          }
          final changed = await customUpdate(
            'UPDATE customers SET total_purchases = total_purchases + 1, '
            'total_spent = total_spent + ?, last_purchase_at = ? '
            'WHERE id = ? AND tenant_id = ?',
            variables: [
              Variable.withReal(purchaseTotal),
              Variable.withString(
                sale.createdAt.present
                    ? sale.createdAt.value.toUtc().toIso8601String()
                    : DateTime.now().toUtc().toIso8601String(),
              ),
              Variable.withString(customerId),
              Variable.withString(tenantId),
            ],
          );
          if (changed != 1) {
            throw StateError('The selected customer could not be updated');
          }
        }
      }

      if (decrementLocalStock) {
        if (!sale.branchId.present || sale.branchId.value.isEmpty) {
          throw StateError('A branch is required to update local stock');
        }
        final branchId = sale.branchId.value;

        // Cart checks can become stale while the payment sheet is open, or
        // when another till on the local network sells the same item. Check
        // the combined quantity for every tracked product inside this sale
        // transaction before committing either the receipt or stock changes.
        final requiredByProduct = <String, double>{};
        for (final item in items) {
          if (!item.productId.present ||
              item.productId.value.isEmpty ||
              !item.quantity.present) {
            throw StateError(
              'A product changed while this sale was open. Refresh the cart and try again.',
            );
          }
          final quantity = item.quantity.value;
          if (!quantity.isFinite || quantity <= 0) {
            throw StateError('Sale quantities must be greater than zero.');
          }
          requiredByProduct.update(
            item.productId.value,
            (current) => current + quantity,
            ifAbsent: () => quantity,
          );
        }

        for (final entry in requiredByProduct.entries) {
          final product = await (select(products)
                ..where((product) => product.id.equals(entry.key)))
              .getSingleOrNull();
          if (product == null || !product.isActive) {
            throw StateError(
              'A product is no longer available. Refresh the cart and try again.',
            );
          }
          if (!product.trackInventory) continue;
          final stock = await getProductStock(entry.key, branchId);
          if (stock == null ||
              !stock.quantity.isFinite ||
              stock.quantity + 0.000001 < entry.value) {
            throw StateError(
              'Stock changed while this sale was open. Refresh the cart and try again.',
            );
          }
        }

        for (final item in items) {
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

  /// IDs with an existing sale-create queue row in this workspace. Terminally
  /// failed rows remain here so orphan recovery does not bypass the retry cap
  /// by generating a new event on every sync cycle.
  Future<Set<String>> getUnresolvedSaleCreateSyncRecordIds() async {
    final items = await (select(syncQueue)
          ..where((item) =>
              item.eventType.equals('SALE_CREATED') &
              item.status.isIn(['pending', 'conflict', 'failed'])))
        .get();
    return items
        .where(_syncItemBelongsToActiveTenant)
        .map((item) => item.recordId)
        .toSet();
  }

  /// Customer creates that are not confirmed remotely yet. A failed create
  /// must also block dependent sales until a user retries or resolves it.
  Future<Set<String>> getUnresolvedCustomerCreateSyncRecordIds() async {
    final items = await (select(syncQueue)
          ..where((item) =>
              item.eventType.equals('CUSTOMER_CREATED') &
              item.status.isIn(['pending', 'conflict', 'failed'])))
        .get();
    return items
        .where(_syncItemBelongsToActiveTenant)
        .map((item) => item.recordId)
        .toSet();
  }

  /// Atomically recover a missing customer-create event before replaying an
  /// offline sale that refers to the customer. Replaying an already-synced
  /// create is safe on the server, but avoiding it while the event row exists
  /// keeps the queue small.
  Future<bool> enqueueRecoveredCustomerIfMissing(
    SyncQueueCompanion item, {
    required String expectedTenantId,
  }) async {
    if (!item.recordId.present ||
        !item.eventType.present ||
        item.eventType.value != 'CUSTOMER_CREATED') {
      throw ArgumentError(
        'Recovery queue items must be CUSTOMER_CREATED events.',
      );
    }
    if (_customerTenantId != expectedTenantId) return false;

    return transaction(() async {
      if (_customerTenantId != expectedTenantId) return false;
      final existing = await (select(syncQueue)
            ..where((queue) =>
                queue.recordId.equals(item.recordId.value) &
                queue.eventType.equals('CUSTOMER_CREATED')))
          .get();
      if (existing.any((event) =>
              _syncItemBelongsToActiveTenant(event) &&
              ['pending', 'conflict', 'failed', 'synced', 'resolved']
                  .contains(event.status)) ||
          _customerTenantId != expectedTenantId) {
        return false;
      }

      final sequenceNumber = await getNextSyncSequenceNumber();
      await into(syncQueue).insert(
        item.copyWith(sequenceNumber: Value(sequenceNumber)),
      );
      return true;
    });
  }

  /// Atomically recover one orphaned sale. Foreground sync and Android's
  /// background worker can run at the same time, so checking for a live row
  /// before enqueueing in the service would allow both workers to create a
  /// separate SALE_CREATED event for the same sale.
  Future<bool> enqueueRecoveredSaleIfMissing(
    SyncQueueCompanion item, {
    required String expectedTenantId,
  }) async {
    if (!item.recordId.present ||
        !item.eventType.present ||
        item.eventType.value != 'SALE_CREATED') {
      throw ArgumentError('Recovery queue items must be SALE_CREATED events.');
    }
    if (_customerTenantId != expectedTenantId) return false;

    return transaction(() async {
      if (_customerTenantId != expectedTenantId) return false;
      final existing = await (select(syncQueue)
            ..where((queue) =>
                queue.recordId.equals(item.recordId.value) &
                queue.eventType.equals('SALE_CREATED') &
                queue.status.isIn(['pending', 'conflict', 'failed'])))
          .get();
      if (existing.any(_syncItemBelongsToActiveTenant) ||
          _customerTenantId != expectedTenantId) {
        return false;
      }

      final sequenceNumber = await getNextSyncSequenceNumber();
      await into(syncQueue).insert(
        item.copyWith(sequenceNumber: Value(sequenceNumber)),
      );
      return true;
    });
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

  /// Records an offline stock receipt and applies its quantities as one
  /// transaction. The receipt id makes a retry safe if the device is
  /// interrupted after SQLite commits but before the screen can close.
  Future<Map<String, Object>> recordLocalStockReceipt({
    required String receiptId,
    required String productId,
    required String branchId,
    required List<Map<String, dynamic>> batches,
    required DateTime receivedAt,
  }) async {
    final tenantId = _requireCustomerTenantId();
    final normalizedReceiptId = receiptId.trim();
    if (normalizedReceiptId.isEmpty || productId.trim().isEmpty) {
      throw ArgumentError('A receipt and product are required.');
    }
    if (!_activeBranchIds().contains(branchId)) {
      throw StateError('This device cannot receive stock for that branch.');
    }
    if (await getProduct(productId) == null) {
      throw StateError('This product is not available in the local catalog.');
    }
    if (batches.isEmpty) {
      throw ArgumentError('Add at least one stock batch.');
    }

    final rows = <Map<String, Object?>>[];
    var totalBaseQuantity = 0.0;
    for (var index = 0; index < batches.length; index++) {
      final batch = batches[index];
      final quantity = (batch['quantity'] as num?)?.toDouble();
      final factor = (batch['unitsPerQuantity'] as num?)?.toDouble() ?? 1.0;
      final unit = batch['unit']?.toString().trim() ?? '';
      final costPrice = (batch['costPrice'] as num?)?.toDouble();
      if (quantity == null || !quantity.isFinite || quantity <= 0) {
        throw ArgumentError('Each batch needs a quantity greater than zero.');
      }
      if (!factor.isFinite || factor <= 0 || unit.isEmpty) {
        throw ArgumentError('Each batch needs a valid unit.');
      }
      if (costPrice != null && (!costPrice.isFinite || costPrice < 0)) {
        throw ArgumentError('A batch cost cannot be negative.');
      }
      final baseQuantity = quantity * factor;
      if (!baseQuantity.isFinite || baseQuantity <= 0) {
        throw ArgumentError('The converted stock quantity is invalid.');
      }
      totalBaseQuantity += baseQuantity;
      rows.add({
        'lineIndex': index,
        'quantity': quantity,
        'unit': unit,
        'unitsPerQuantity': factor,
        'baseQuantity': baseQuantity,
        'costPrice': costPrice,
        'supplierRef': _optionalReceiptText(batch['supplierRef']),
        'notes': _optionalReceiptText(batch['notes']),
        'expiryDate': _optionalReceiptText(batch['expiryDate']),
        'manufactureDate': _optionalReceiptText(batch['manufactureDate']),
      });
    }
    if (!totalBaseQuantity.isFinite || totalBaseQuantity <= 0) {
      throw ArgumentError('The total received stock is invalid.');
    }
    final hasCompleteCosts = rows.every((row) => row['costPrice'] != null);
    double? totalCost;
    if (hasCompleteCosts) {
      totalCost = rows.fold<double>(
        0,
        (sum, row) =>
            sum +
            (row['costPrice'] as double) * (row['baseQuantity'] as double),
      );
      if (!totalCost.isFinite || totalCost < 0) {
        throw ArgumentError('The total purchase cost is invalid.');
      }
    }

    await _ensureLocalStockReceiptsTable();
    final timestamp = receivedAt.toUtc().toIso8601String();
    return transaction(() async {
      final priorLines = await customSelect(
        'SELECT line_index, branch_id, product_id, quantity, unit, '
        'units_per_quantity, base_quantity, cost_price, supplier_ref, notes, '
        'expiry_date, manufacture_date '
        'FROM local_stock_receipts WHERE tenant_id = ? AND receipt_id = ? '
        'ORDER BY line_index',
        variables: [
          Variable.withString(tenantId),
          Variable.withString(normalizedReceiptId),
        ],
      ).get();
      if (priorLines.isNotEmpty) {
        if (priorLines.length != rows.length) {
          throw StateError(
            'This receipt was already used for different stock details.',
          );
        }
        for (var index = 0; index < rows.length; index++) {
          final prior = priorLines[index];
          final requested = rows[index];
          final sameLine =
              prior.read<int>('line_index') == requested['lineIndex'] &&
                  prior.read<String>('branch_id') == branchId &&
                  prior.read<String>('product_id') == productId &&
                  prior.read<double>('quantity') == requested['quantity'] &&
                  prior.read<String>('unit') == requested['unit'] &&
                  prior.read<double>('units_per_quantity') ==
                      requested['unitsPerQuantity'] &&
                  prior.read<double>('base_quantity') ==
                      requested['baseQuantity'] &&
                  prior.readNullable<double>('cost_price') ==
                      requested['costPrice'] &&
                  prior.readNullable<String>('supplier_ref') ==
                      requested['supplierRef'] &&
                  prior.readNullable<String>('notes') == requested['notes'] &&
                  prior.readNullable<String>('expiry_date') ==
                      requested['expiryDate'] &&
                  prior.readNullable<String>('manufacture_date') ==
                      requested['manufactureDate'];
          if (!sameLine) {
            throw StateError(
              'This receipt was already used for different stock details.',
            );
          }
        }
        final existingStock = await getProductStock(productId, branchId);
        final recordedPurchase = await customSelect(
          'SELECT 1 AS found FROM daily_purchases WHERE id = ? LIMIT 1',
          variables: [
            Variable.withString('purchase-$normalizedReceiptId'),
          ],
        ).getSingleOrNull();
        return {
          'totalQuantity': priorLines.fold<double>(
            0,
            (sum, line) => sum + line.read<double>('base_quantity'),
          ),
          'currentQuantity': existingStock?.quantity.toDouble() ?? 0.0,
          'purchaseCostRecorded': recordedPurchase != null,
        };
      }

      final existingStock = await getProductStock(productId, branchId);
      final currentQuantity =
          (existingStock?.quantity ?? 0).toDouble() + totalBaseQuantity;
      if (!currentQuantity.isFinite || currentQuantity < 0) {
        throw ArgumentError('The resulting stock quantity is invalid.');
      }
      final lastBatch = rows.last;
      await upsertAuthoritativeStock(
        productId: productId,
        branchId: branchId,
        quantity: currentQuantity,
        displayUnit: lastBatch['unit'] as String,
        displayQuantityPerUnit: lastBatch['unitsPerQuantity'] as double,
        lastReceivedQuantity: lastBatch['quantity'] as double,
        lastReceivedAt: receivedAt,
      );

      for (final row in rows) {
        final lineIndex = row['lineIndex'] as int;
        await customStatement(
          'INSERT INTO local_stock_receipts '
          '(id, receipt_id, line_index, tenant_id, branch_id, product_id, '
          'quantity, unit, units_per_quantity, base_quantity, cost_price, '
          'supplier_ref, notes, expiry_date, manufacture_date, received_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            Variable.withString('$normalizedReceiptId-$lineIndex'),
            Variable.withString(normalizedReceiptId),
            Variable.withInt(lineIndex),
            Variable.withString(tenantId),
            Variable.withString(branchId),
            Variable.withString(productId),
            Variable.withReal(row['quantity'] as double),
            Variable.withString(row['unit'] as String),
            Variable.withReal(row['unitsPerQuantity'] as double),
            Variable.withReal(row['baseQuantity'] as double),
            row['costPrice'] == null
                ? const Variable<double>(null)
                : Variable.withReal(row['costPrice'] as double),
            row['supplierRef'] == null
                ? const Variable<String>(null)
                : Variable.withString(row['supplierRef'] as String),
            row['notes'] == null
                ? const Variable<String>(null)
                : Variable.withString(row['notes'] as String),
            row['expiryDate'] == null
                ? const Variable<String>(null)
                : Variable.withString(row['expiryDate'] as String),
            row['manufactureDate'] == null
                ? const Variable<String>(null)
                : Variable.withString(row['manufactureDate'] as String),
            Variable.withString(timestamp),
          ],
        );
      }

      if (hasCompleteCosts) {
        await into(dailyPurchases).insert(
          DailyPurchasesCompanion.insert(
            id: 'purchase-$normalizedReceiptId',
            branchId: branchId,
            amount: totalCost!,
            description: const Value('Stock receipt'),
            purchaseDate: receivedAt,
            isManual: const Value(false),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
      return {
        'totalQuantity': totalBaseQuantity,
        'currentQuantity': currentQuantity,
        'purchaseCostRecorded': hasCompleteCosts,
      };
    });
  }

  String? _optionalReceiptText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  Future<void> _ensureLocalStockReceiptsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_stock_receipts (
        id TEXT NOT NULL PRIMARY KEY,
        receipt_id TEXT NOT NULL,
        line_index INTEGER NOT NULL,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        units_per_quantity REAL NOT NULL,
        base_quantity REAL NOT NULL,
        cost_price REAL,
        supplier_ref TEXT,
        notes TEXT,
        expiry_date TEXT,
        manufacture_date TEXT,
        received_at TEXT NOT NULL,
        UNIQUE (tenant_id, receipt_id, line_index)
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_local_stock_receipts_scope
      ON local_stock_receipts (tenant_id, branch_id, received_at)
    ''');
  }

  Future<void> _ensureLocalStockCountTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_stock_counts (
        id TEXT NOT NULL PRIMARY KEY,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        title TEXT,
        blind INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'IN_PROGRESS',
        created_by_name TEXT,
        submitted_by_name TEXT,
        approved_by_name TEXT,
        created_at TEXT NOT NULL,
        submitted_at TEXT,
        approved_at TEXT,
        cancelled_at TEXT
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_stock_count_lines (
        id TEXT NOT NULL PRIMARY KEY,
        count_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        sku TEXT,
        unit TEXT NOT NULL DEFAULT 'piece',
        allow_fractions INTEGER NOT NULL DEFAULT 0,
        expected_qty REAL NOT NULL,
        expected_stock_updated_at INTEGER,
        counted_qty REAL,
        cost_price REAL NOT NULL DEFAULT 0,
        counted_by_name TEXT,
        UNIQUE (count_id, product_id)
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_local_stock_counts_scope
      ON local_stock_counts (tenant_id, branch_id, created_at)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_local_stock_count_lines_count
      ON local_stock_count_lines (count_id, product_name)
    ''');
    final lineColumns = await customSelect(
      'PRAGMA table_info(local_stock_count_lines)',
    ).get();
    if (!lineColumns.any(
      (column) => column.read<String>('name') == 'expected_stock_updated_at',
    )) {
      await customStatement(
        'ALTER TABLE local_stock_count_lines '
        'ADD COLUMN expected_stock_updated_at INTEGER',
      );
    }
  }

  /// Starts a count from the active branch's inventory snapshot. Products and
  /// expected quantities are copied into the count so later catalog edits do
  /// not rewrite the audit record.
  Future<String> startLocalStockCount({
    required String branchId,
    required bool blind,
    String? title,
    String? createdByName,
  }) async {
    final tenantId = _requireCustomerTenantId();
    if (!_activeBranchIds().contains(branchId)) {
      throw StateError(
          'Select an active branch before starting a stock count.');
    }
    await _ensureLocalStockCountTables();
    final normalizedTitle = _optionalReceiptText(title);
    final normalizedCreator = _optionalReceiptText(createdByName);
    final countId = const Uuid().v4();
    final createdAt = DateTime.now().toUtc().toIso8601String();

    await transaction(() async {
      final products = await customSelect(
        'SELECT p.id, p.name, p.sku, p.unit, p.allow_fractions, '
        'COALESCE(p.cost_price, 0) AS cost_price, '
        'COALESCE(s.quantity, 0) AS expected_qty, '
        's.updated_at AS expected_stock_updated_at '
        'FROM products p LEFT JOIN local_stock s '
        'ON s.product_id = p.id AND s.branch_id = ? '
        'WHERE p.is_active = 1 AND p.track_inventory = 1 '
        'ORDER BY p.name COLLATE NOCASE, p.id',
        variables: [Variable.withString(branchId)],
      ).get();
      if (products.isEmpty) {
        throw StateError(
          'There are no active inventory-tracked products to count in this branch.',
        );
      }
      await customStatement(
        'INSERT INTO local_stock_counts '
        '(id, tenant_id, branch_id, title, blind, status, created_by_name, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          Variable.withString(countId),
          Variable.withString(tenantId),
          Variable.withString(branchId),
          normalizedTitle == null
              ? const Variable<String>(null)
              : Variable.withString(normalizedTitle),
          Variable.withInt(blind ? 1 : 0),
          Variable.withString('IN_PROGRESS'),
          normalizedCreator == null
              ? const Variable<String>(null)
              : Variable.withString(normalizedCreator),
          Variable.withString(createdAt),
        ],
      );
      for (var offset = 0; offset < products.length; offset += 90) {
        final batch = products.sublist(
          offset,
          offset + 90 > products.length ? products.length : offset + 90,
        );
        final placeholders =
            List.filled(batch.length, '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
                .join(', ');
        final variables = <dynamic>[];
        for (var index = 0; index < batch.length; index++) {
          final product = batch[index];
          final productId = product.read<String>('id');
          variables.addAll([
            Variable.withString('$countId-${offset + index}'),
            Variable.withString(countId),
            Variable.withString(productId),
            Variable.withString(product.read<String>('name')),
            Variable.withString(product.read<String>('sku')),
            Variable.withString(product.read<String>('unit')),
            Variable.withInt(product.read<int>('allow_fractions') == 1 ? 1 : 0),
            Variable.withReal(product.read<double>('expected_qty')),
            product.readNullable<int>('expected_stock_updated_at') == null
                ? const Variable<int>(null)
                : Variable.withInt(
                    product.read<int>('expected_stock_updated_at')),
            Variable.withReal(product.read<double>('cost_price')),
          ]);
        }
        await customStatement(
          'INSERT INTO local_stock_count_lines '
          '(id, count_id, product_id, product_name, sku, unit, allow_fractions, '
          'expected_qty, expected_stock_updated_at, cost_price) '
          'VALUES $placeholders',
          variables,
        );
      }
    });
    return countId;
  }

  Future<List<Map<String, dynamic>>> getLocalStockCounts(
      {int limit = 100}) async {
    final tenantId = _customerTenantId;
    final branchIds = _activeBranchIds().toList()..sort();
    if (tenantId == null || branchIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    await _ensureLocalStockCountTables();
    final placeholders = List.filled(branchIds.length, '?').join(', ');
    final rows = await customSelect(
      'SELECT c.id, c.title, c.status, c.blind, c.created_at, '
      'c.created_by_name, COUNT(l.product_id) AS item_count, '
      'SUM(CASE WHEN l.counted_qty IS NOT NULL THEN 1 ELSE 0 END) AS counted_lines, '
      'SUM(CASE WHEN l.counted_qty IS NOT NULL '
      'THEN (l.counted_qty - l.expected_qty) * l.cost_price ELSE 0 END) AS net_value '
      'FROM local_stock_counts c LEFT JOIN local_stock_count_lines l '
      'ON l.count_id = c.id WHERE c.tenant_id = ? '
      'AND c.branch_id IN ($placeholders) '
      'GROUP BY c.id ORDER BY c.created_at DESC LIMIT ?',
      variables: [
        Variable.withString(tenantId),
        ...branchIds.map(Variable.withString),
        Variable.withInt(limit.clamp(1, 250).toInt()),
      ],
    ).get();
    return rows.map((row) {
      final blindInProgress = row.read<int>('blind') == 1 &&
          row.read<String>('status') == 'IN_PROGRESS';
      return <String, dynamic>{
        'id': row.read<String>('id'),
        'title': row.readNullable<String>('title'),
        'status': row.read<String>('status'),
        'itemCount': row.read<int>('item_count'),
        'createdAt': row.read<String>('created_at'),
        'createdByName': row.readNullable<String>('created_by_name'),
        'totalVarianceValue':
            blindInProgress ? null : row.read<double>('net_value'),
      };
    }).toList(growable: false);
  }

  Future<Map<String, dynamic>> getLocalStockCount(String countId) async {
    final tenantId = _requireCustomerTenantId();
    final branchIds = _activeBranchIds().toList()..sort();
    if (branchIds.isEmpty) throw StateError('Select an active branch first.');
    await _ensureLocalStockCountTables();
    final count = await customSelect(
      'SELECT * FROM local_stock_counts WHERE id = ? AND tenant_id = ? '
      'AND branch_id IN (${List.filled(branchIds.length, '?').join(', ')})',
      variables: [
        Variable.withString(countId),
        Variable.withString(tenantId),
        ...branchIds.map(Variable.withString),
      ],
    ).getSingleOrNull();
    if (count == null) {
      throw StateError('This stock count is not available here.');
    }
    final status = count.read<String>('status');
    final blind = count.read<int>('blind') == 1;
    final expectedHidden = blind && status == 'IN_PROGRESS';
    final lines = await customSelect(
      'SELECT * FROM local_stock_count_lines WHERE count_id = ? '
      'ORDER BY product_name COLLATE NOCASE, product_id',
      variables: [Variable.withString(countId)],
    ).get();
    final items = <Map<String, dynamic>>[];
    var countedLines = 0;
    var lossValue = 0.0;
    var gainValue = 0.0;
    var shortLines = 0;
    var overLines = 0;
    for (final line in lines) {
      final expected = line.read<double>('expected_qty');
      final counted = line.readNullable<double>('counted_qty');
      final cost = line.read<double>('cost_price');
      final variance = counted == null ? null : counted - expected;
      final varianceValue = variance == null ? null : variance * cost;
      if (counted != null) countedLines++;
      if (variance != null && variance < -0.000001) {
        shortLines++;
        lossValue += variance.abs() * cost;
      } else if (variance != null && variance > 0.000001) {
        overLines++;
        gainValue += variance * cost;
      }
      items.add({
        'productId': line.read<String>('product_id'),
        'productName': line.read<String>('product_name'),
        'sku': line.read<String>('sku'),
        'unit': line.read<String>('unit'),
        'expectedQty': expectedHidden ? null : expected,
        'countedQty': counted,
        'varianceQty': expectedHidden ? null : variance,
        'varianceValue': expectedHidden ? null : varianceValue,
        'countedByName': line.readNullable<String>('counted_by_name'),
      });
    }
    final totalLines = lines.length;
    return {
      'id': countId,
      'status': status,
      'blind': blind,
      'expectedHidden': expectedHidden,
      'title': count.readNullable<String>('title'),
      'createdByName': count.readNullable<String>('created_by_name'),
      'submittedByName': count.readNullable<String>('submitted_by_name'),
      'approvedByName': count.readNullable<String>('approved_by_name'),
      'items': items,
      'summary': {
        'totalLines': totalLines,
        'countedLines': countedLines,
        'completionPercent':
            totalLines == 0 ? 0 : (countedLines * 100 / totalLines).round(),
        'lossValue': lossValue,
        'gainValue': gainValue,
        'netValue': gainValue - lossValue,
        'shortLines': shortLines,
        'overLines': overLines,
      },
    };
  }

  Future<void> recordLocalStockCountEntries({
    required String countId,
    required List<Map<String, dynamic>> entries,
    String? countedByName,
  }) async {
    final tenantId = _requireCustomerTenantId();
    final branchIds = _activeBranchIds().toList()..sort();
    if (branchIds.isEmpty) throw StateError('Select an active branch first.');
    final normalizedCounter = _optionalReceiptText(countedByName);
    await _ensureLocalStockCountTables();
    await transaction(() async {
      final count = await customSelect(
        'SELECT id FROM local_stock_counts WHERE id = ? AND tenant_id = ? '
        'AND branch_id IN (${List.filled(branchIds.length, '?').join(', ')}) '
        "AND status = 'IN_PROGRESS'",
        variables: [
          Variable.withString(countId),
          Variable.withString(tenantId),
          ...branchIds.map(Variable.withString),
        ],
      ).getSingleOrNull();
      if (count == null) {
        throw StateError('This count is no longer open. Refresh it.');
      }
      for (final entry in entries) {
        final productId = entry['productId']?.toString().trim() ?? '';
        final rawQuantity = entry['countedQty'];
        if (productId.isEmpty || (rawQuantity != null && rawQuantity is! num)) {
          throw ArgumentError('Enter a valid quantity for every product.');
        }
        final line = await customSelect(
          'SELECT allow_fractions FROM local_stock_count_lines '
          'WHERE count_id = ? AND product_id = ?',
          variables: [
            Variable.withString(countId),
            Variable.withString(productId),
          ],
        ).getSingleOrNull();
        if (line == null) {
          throw StateError('A counted product is not in this count.');
        }
        if (rawQuantity == null) {
          await customStatement(
            'UPDATE local_stock_count_lines SET counted_qty = NULL, counted_by_name = NULL '
            'WHERE count_id = ? AND product_id = ?',
            [Variable.withString(countId), Variable.withString(productId)],
          );
          continue;
        }
        final quantity = (rawQuantity as num).toDouble();
        if (!quantity.isFinite || quantity < 0 || quantity > 1000000000) {
          throw ArgumentError('Counted quantities must be zero or greater.');
        }
        if (line.read<int>('allow_fractions') == 0 &&
            (quantity - quantity.round()).abs() > 0.000001) {
          throw ArgumentError('This product is counted in whole units.');
        }
        await customStatement(
          'UPDATE local_stock_count_lines SET counted_qty = ?, counted_by_name = ? '
          'WHERE count_id = ? AND product_id = ?',
          [
            Variable.withReal(quantity),
            normalizedCounter == null
                ? const Variable<String>(null)
                : Variable.withString(normalizedCounter),
            Variable.withString(countId),
            Variable.withString(productId),
          ],
        );
      }
    });
  }

  Future<void> submitLocalStockCount({
    required String countId,
    String? submittedByName,
  }) async {
    final tenantId = _requireCustomerTenantId();
    await _ensureLocalStockCountTables();
    final currentBranches = _activeBranchIds();
    if (currentBranches.isEmpty) {
      throw StateError('Select an active branch first.');
    }
    await transaction(() async {
      final state = await customSelect(
        'SELECT status FROM local_stock_counts WHERE id = ? AND tenant_id = ? '
        'AND branch_id IN (${List.filled(currentBranches.length, '?').join(', ')})',
        variables: [
          Variable.withString(countId),
          Variable.withString(tenantId),
          ...currentBranches.map(Variable.withString),
        ],
      ).getSingleOrNull();
      if (state == null) {
        throw StateError('This stock count is not available here.');
      }
      final status = state.read<String>('status');
      if (status == 'SUBMITTED' || status == 'APPROVED') return;
      if (status != 'IN_PROGRESS') {
        throw StateError('This stock count is closed.');
      }
      final count = await customSelect(
        'SELECT COUNT(*) AS total FROM local_stock_count_lines '
        'WHERE count_id = ? AND counted_qty IS NOT NULL',
        variables: [Variable.withString(countId)],
      ).getSingle();
      if (count.read<int>('total') == 0) {
        throw StateError(
            'Count at least one product before handing in the count.');
      }
      await customStatement(
        "UPDATE local_stock_counts SET status = 'SUBMITTED', submitted_by_name = ?, submitted_at = ? WHERE id = ? AND status = 'IN_PROGRESS'",
        [
          submittedByName == null
              ? const Variable<String>(null)
              : Variable.withString(submittedByName.trim()),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(countId),
        ],
      );
    });
  }

  Future<void> approveLocalStockCount({
    required String countId,
    String? approvedByName,
  }) async {
    final tenantId = _requireCustomerTenantId();
    await _ensureLocalStockCountTables();
    final currentBranches = _activeBranchIds();
    if (currentBranches.isEmpty) {
      throw StateError('Select an active branch first.');
    }
    await transaction(() async {
      final count = await customSelect(
        'SELECT branch_id, status FROM local_stock_counts WHERE id = ? AND tenant_id = ? '
        'AND branch_id IN (${List.filled(currentBranches.length, '?').join(', ')})',
        variables: [
          Variable.withString(countId),
          Variable.withString(tenantId),
          ...currentBranches.map(Variable.withString),
        ],
      ).getSingleOrNull();
      if (count == null) {
        throw StateError('This stock count is not available here.');
      }
      if (count.read<String>('status') == 'APPROVED') return;
      if (count.read<String>('status') != 'SUBMITTED') {
        throw StateError('Hand in the count before adjusting stock.');
      }
      final branchId = count.read<String>('branch_id');
      final lines = await customSelect(
        'SELECT l.product_id, l.product_name, l.counted_qty, l.expected_qty, '
        'l.expected_stock_updated_at, '
        'p.track_inventory AS product_track_inventory, '
        'p.is_active AS product_is_active, '
        's.updated_at AS current_stock_updated_at, '
        's.quantity AS current_stock_quantity '
        'FROM local_stock_count_lines l '
        'LEFT JOIN products p ON p.id = l.product_id '
        'LEFT JOIN local_stock s ON s.product_id = l.product_id AND s.branch_id = ? '
        'WHERE l.count_id = ? AND l.counted_qty IS NOT NULL',
        variables: [
          Variable.withString(branchId),
          Variable.withString(countId),
        ],
      ).get();
      if (lines.isEmpty) {
        throw StateError('There are no counted products to apply.');
      }
      for (final line in lines) {
        final productName = line.read<String>('product_name');
        if (line.readNullable<int>('product_track_inventory') != 1 ||
            line.readNullable<int>('product_is_active') != 1) {
          throw StateError(
            '$productName is no longer an active inventory item. Reopen it or cancel and restart the count before adjusting stock.',
          );
        }
        final expectedUpdatedAt =
            line.readNullable<int>('expected_stock_updated_at');
        final currentUpdatedAt =
            line.readNullable<int>('current_stock_updated_at');
        final expectedQuantity = line.read<double>('expected_qty');
        final currentQuantity =
            line.readNullable<double>('current_stock_quantity') ?? 0;
        if (expectedUpdatedAt != currentUpdatedAt ||
            (expectedQuantity - currentQuantity).abs() > 0.000001) {
          throw StateError(
            'Stock for $productName changed after this count began. Cancel this count and start a fresh one before adjusting stock.',
          );
        }
      }
      final updatedAt = DateTime.now();
      for (var offset = 0; offset < lines.length; offset += 100) {
        final batch = lines.sublist(
          offset,
          offset + 100 > lines.length ? lines.length : offset + 100,
        );
        final placeholders =
            List.filled(batch.length, '(?, ?, ?, ?, ?)').join(', ');
        final variables = <dynamic>[];
        for (final line in batch) {
          final productId = line.read<String>('product_id');
          variables.addAll([
            Variable.withString('stock-$branchId-$productId'),
            Variable.withString(productId),
            Variable.withString(branchId),
            Variable.withReal(line.read<double>('counted_qty')),
            Variable.withDateTime(updatedAt),
          ]);
        }
        await customStatement(
          'INSERT INTO local_stock '
          '(id, product_id, branch_id, quantity, updated_at) '
          'VALUES $placeholders '
          'ON CONFLICT(product_id, branch_id) DO UPDATE SET '
          'quantity = excluded.quantity, updated_at = excluded.updated_at',
          variables,
        );
      }
      await customStatement(
        "UPDATE local_stock_counts SET status = 'APPROVED', approved_by_name = ?, approved_at = ? WHERE id = ? AND status = 'SUBMITTED'",
        [
          approvedByName == null
              ? const Variable<String>(null)
              : Variable.withString(approvedByName.trim()),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(countId),
        ],
      );
    });
  }

  Future<void> cancelLocalStockCount(String countId) async {
    final tenantId = _requireCustomerTenantId();
    await _ensureLocalStockCountTables();
    final currentBranches = _activeBranchIds();
    if (currentBranches.isEmpty) {
      throw StateError('Select an active branch first.');
    }
    final changed = await customUpdate(
      "UPDATE local_stock_counts SET status = 'CANCELLED', cancelled_at = ? "
      "WHERE id = ? AND tenant_id = ? AND branch_id IN (${List.filled(currentBranches.length, '?').join(', ')}) "
      "AND status IN ('IN_PROGRESS', 'SUBMITTED')",
      variables: [
        Variable.withString(DateTime.now().toUtc().toIso8601String()),
        Variable.withString(countId),
        Variable.withString(tenantId),
        ...currentBranches.map(Variable.withString),
      ],
    );
    if (changed > 0) return;
    final existing = await customSelect(
      'SELECT status FROM local_stock_counts WHERE id = ? AND tenant_id = ? '
      'AND branch_id IN (${List.filled(currentBranches.length, '?').join(', ')})',
      variables: [
        Variable.withString(countId),
        Variable.withString(tenantId),
        ...currentBranches.map(Variable.withString),
      ],
    ).getSingleOrNull();
    if (existing == null) {
      throw StateError('This stock count is not available here.');
    }
    if (existing.read<String>('status') == 'CANCELLED') return;
    throw StateError('Only an open or submitted count can be cancelled.');
  }

  Future<List<Map<String, dynamic>>> getLocalStockReceiptHistory({
    int limit = 100,
  }) async {
    final tenantId = _customerTenantId;
    final branchIds = _activeBranchIds().toList()..sort();
    if (tenantId == null || branchIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    await _ensureLocalStockReceiptsTable();
    final placeholders = List.filled(branchIds.length, '?').join(', ');
    final safeLimit = limit.clamp(1, 250);
    final rows = await customSelect(
      '''
        SELECT r.receipt_id, r.product_id,
          COALESCE(p.name, 'Removed product') AS product_name,
          COALESCE(p.unit, 'unit') AS base_unit,
          r.branch_id, r.received_at,
          SUM(r.base_quantity) AS total_quantity,
          COUNT(*) AS batch_count,
          SUM(CASE WHEN r.cost_price IS NULL THEN 1 ELSE 0 END) AS missing_cost_count,
          COALESCE(SUM(r.cost_price * r.base_quantity), 0) AS total_cost,
          GROUP_CONCAT(DISTINCT r.supplier_ref) AS supplier_references
        FROM local_stock_receipts r
        LEFT JOIN products p ON p.id = r.product_id
        WHERE r.tenant_id = ? AND r.branch_id IN ($placeholders)
        GROUP BY r.tenant_id, r.receipt_id, r.product_id, r.branch_id,
          r.received_at, p.name, p.unit
        ORDER BY r.received_at DESC, r.receipt_id DESC
        LIMIT ?
      ''',
      variables: [
        Variable.withString(tenantId),
        ...branchIds.map(Variable.withString),
        Variable.withInt(safeLimit),
      ],
    ).get();
    return rows
        .map((row) => <String, dynamic>{
              'receiptId': row.read<String>('receipt_id'),
              'productId': row.read<String>('product_id'),
              'productName': row.read<String>('product_name'),
              'unit': row.read<String>('base_unit'),
              'branchId': row.read<String>('branch_id'),
              'receivedAt': row.read<String>('received_at'),
              'totalQuantity': row.read<double>('total_quantity'),
              'batchCount': row.read<int>('batch_count'),
              'costComplete': row.read<int>('missing_cost_count') == 0,
              'totalCost': row.read<double>('total_cost'),
              'supplierReferences':
                  row.readNullable<String>('supplier_references'),
            })
        .toList(growable: false);
  }

  Future<void> decrementStock(
    String productId,
    String branchId,
    num quantity,
  ) async {
    final amount = quantity.toDouble();
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Stock deduction must be a positive quantity');
    }
    final product = await (select(products)
          ..where((p) => p.id.equals(productId)))
        .getSingleOrNull();
    if (product == null || !product.trackInventory) return;

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
  Future<List<Map<String, dynamic>>> getLowStockProducts(
      {String? branchId}) async {
    final requestedBranch = branchId?.trim();
    final effectiveBranchId = requestedBranch == null || requestedBranch.isEmpty
        ? _storage.getBranchId()
        : requestedBranch;
    final result = await customSelect(
      'SELECT p.id, p.name, p.sku, p.price, p.min_stock, p.unit, '
      'ls.quantity, ls.branch_id, ls.display_unit, '
      'ls.display_quantity_per_unit, ls.last_received_quantity, '
      'ls.last_received_at, '
      '(SELECT name FROM categories WHERE id = p.category_id) as category_name '
      'FROM products p '
      'LEFT JOIN local_stock ls ON ls.product_id = p.id '
      "${effectiveBranchId == null ? '' : 'AND ls.branch_id = ? '}"
      'WHERE p.is_active = 1 AND p.track_inventory = 1 '
      'AND COALESCE(ls.quantity, 0) <= p.min_stock '
      'ORDER BY (p.min_stock - COALESCE(ls.quantity, 0)) DESC, p.name ASC',
      variables: effectiveBranchId == null
          ? const []
          : [Variable.withString(effectiveBranchId)],
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

  /// Sales for one selected branch within [from]..[to]. Unlike the general
  /// workspace query above, this is for branch-specific reports and must not
  /// combine receipts from other active branches into the selected branch's
  /// totals.
  Future<List<PendingSale>> getSalesByDateRangeForBranch(
    String branchId,
    DateTime from,
    DateTime to,
  ) async {
    if (_customerTenantId == null) {
      throw StateError('Sign in to a local shop before viewing sales.');
    }
    if (!_activeBranchIds().contains(branchId)) {
      throw StateError(
        'The selected branch is not available on this device. Choose an active branch and refresh.',
      );
    }
    return (select(pendingSales)
          ..where(
            (sale) =>
                sale.branchId.equals(branchId) &
                sale.createdAt.isBiggerOrEqualValue(from) &
                sale.createdAt.isSmallerOrEqualValue(to),
          )
          ..orderBy([(sale) => OrderingTerm.desc(sale.createdAt)]))
        .get();
  }

  /// Checks whether a sale was added or voided after a local till close.
  /// Uses an indexed existence query rather than loading every sale and item
  /// into Dart, and treats [to] as the exclusive end of the business day.
  Future<bool> hasSalesActivityAfterClose({
    required String branchId,
    required DateTime from,
    required DateTime to,
    required DateTime closedAt,
  }) async {
    if (_customerTenantId == null || !_activeBranchIds().contains(branchId)) {
      throw Exception(
        'The selected branch is not available on this device. Choose an active branch and refresh.',
      );
    }

    final result = await customSelect(
      'SELECT EXISTS('
      'SELECT 1 FROM pending_sales '
      'WHERE branch_id = ? AND created_at >= ? AND created_at < ? '
      'AND (created_at > ? OR voided_at > ?)'
      ') AS has_activity',
      variables: [
        Variable.withString(branchId),
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        Variable.withDateTime(closedAt),
        Variable.withDateTime(closedAt),
      ],
    ).getSingle();
    return result.read<int>('has_activity') != 0;
  }

  /// A cash-funded supplier payment after a till close changes expected cash
  /// just like a sale or customer collection and therefore needs a re-count.
  Future<bool> hasLocalCashPayoutsAfterClose({
    required String branchId,
    required DateTime from,
    required DateTime to,
    required DateTime closedAt,
  }) async {
    if (_customerTenantId == null || !_activeBranchIds().contains(branchId)) {
      throw Exception(
        'The selected branch is not available on this device. Choose an active branch and refresh.',
      );
    }
    await _createSupplierFinanceTables();
    final result = await customSelect(
      'SELECT EXISTS('
      'SELECT 1 FROM supplier_payments sp '
      'JOIN suppliers s ON s.id = sp.supplier_id '
      'WHERE s.tenant_id = ? AND sp.branch_id = ? '
      'AND UPPER(TRIM(sp.funding_source)) = \'CASH_TILL\' '
      'AND sp.payment_date >= ? AND sp.payment_date < ? '
      'AND sp.payment_date > ?'
      ') AS has_activity',
      variables: [
        Variable.withString(_customerTenantId!),
        Variable.withString(branchId),
        Variable.withString(from.toUtc().toIso8601String()),
        Variable.withString(to.toUtc().toIso8601String()),
        Variable.withString(closedAt.toUtc().toIso8601String()),
      ],
    ).getSingle();
    return result.read<int>('has_activity') != 0;
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

  /// Watches one receipt so a locally printed receipt can update when its
  /// cloud sync replaces the temporary receipt number or confirms delivery.
  Stream<PendingSale?> watchPendingSaleById(String saleId) {
    final branchIds = _activeBranchIds();
    if (_customerTenantId == null || branchIds.isEmpty) {
      return Stream.value(null);
    }
    return (select(pendingSales)
          ..where(
              (sale) => sale.id.equals(saleId) & sale.branchId.isIn(branchIds)))
        .watchSingleOrNull();
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
    bool guardUnallocatedCollections = false,
    bool recordCashRefund = false,
  }) async {
    if (guardUnallocatedCollections) {
      await _ensureLocalCashCollectionsTable();
      await createCustomerInstallmentsTable();
    }
    if (recordCashRefund) await _ensureLocalCashRefundsTable();
    await transaction(() async {
      final sale = await getPendingSaleById(saleId);
      if (sale == null || sale.status == 'VOIDED') return;
      if (guardUnallocatedCollections && sale.status != 'COMPLETED') {
        throw const LocalSaleVoidConflict(
          'This sale is not marked complete, so its payment and stock changes cannot be safely reversed here. Verify the payment first; no records were changed.',
        );
      }

      final branchIds = _activeBranchIds();
      if (branchIds.isEmpty || _customerTenantId == null) return;

      if (recordCashRefund) {
        final refundCents = _pendingSaleCashTenderCents(sale);
        if (refundCents <= 0) {
          throw const LocalSaleVoidConflict(
            'This receipt has no verified cash tender to refund from the till. The sale was left unchanged.',
          );
        }
        final now = DateTime.now().toUtc();
        await customStatement(
          'INSERT INTO local_cash_refunds '
          '(id, tenant_id, branch_id, sale_id, amount, refunded_at, recorded_by, reason) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            Variable.withString('cash-refund-$saleId'),
            Variable.withString(_customerTenantId!),
            Variable.withString(sale.branchId),
            Variable.withString(saleId),
            Variable.withReal(refundCents / 100),
            Variable.withString(now.toIso8601String()),
            voidedBy == null
                ? const Variable<String>(null)
                : Variable.withString(voidedBy),
            Variable.withString(reason.trim()),
          ],
        );
      }

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
        if (guardUnallocatedCollections) {
          final saleCreatedAt = sale.createdAt.toUtc().toIso8601String();
          final laterCollection = await customSelect(
            'SELECT 1 AS found FROM local_cash_collections '
            'WHERE tenant_id = ? AND customer_id = ? AND collected_at >= ? '
            'LIMIT 1',
            variables: [
              Variable.withString(tenantId),
              Variable.withString(customerId),
              Variable.withString(saleCreatedAt),
            ],
          ).getSingleOrNull();
          if (laterCollection != null) {
            throw const LocalSaleVoidConflict(
              'This credit sale can’t be voided safely because a customer payment was recorded after it. Customer payments are account-level and are not linked to individual sales. The sale, balance, and stock were left unchanged.',
            );
          }

          final customer = await customSelect(
            'SELECT balance FROM customers WHERE id = ? AND tenant_id = ?',
            variables: [
              Variable.withString(customerId),
              Variable.withString(tenantId),
            ],
          ).getSingleOrNull();
          if (customer == null) {
            throw StateError('The debt customer could not be found');
          }
          if (customer.read<double>('balance') + 0.005 < debtAmount) {
            throw const LocalSaleVoidConflict(
              'This credit sale can’t be voided safely because the customer’s current balance is lower than the sale’s debt. The sale, balance, and stock were left unchanged.',
            );
          }
          final remainingBalance =
              (customer.read<double>('balance') - debtAmount)
                  .clamp(0, double.infinity)
                  .toDouble();
          final scheduled = await customSelect(
            'SELECT COALESCE(SUM(amount - COALESCE(paid_amount, 0)), 0) AS amount_due '
            'FROM customer_installments WHERE tenant_id = ? AND customer_id = ? '
            'AND status IN (\'pending\', \'overdue\')',
            variables: [
              Variable.withString(tenantId),
              Variable.withString(customerId),
            ],
          ).getSingle();
          final scheduledBalance = scheduled.read<double>('amount_due');
          if (!scheduledBalance.isFinite ||
              scheduledBalance > remainingBalance + 0.005) {
            throw const LocalSaleVoidConflict(
              'This credit sale can’t be voided safely because active payment schedules would exceed the customer’s remaining balance. Cancel or adjust the affected due dates, refresh, and try again. The sale, balance, and stock were left unchanged.',
            );
          }
        }
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

      // A voided receipt is not a completed customer purchase. Reverse its
      // aggregate contribution in the same transaction and move the last-
      // purchase date back to the most recent completed receipt, if any.
      final customerId = sale.customerId;
      final tenantId = _customerTenantId;
      if (sale.status.toUpperCase() == 'COMPLETED' &&
          customerId != null &&
          customerId.isNotEmpty &&
          tenantId != null) {
        final purchaseScope = _salesBranchScope('ps');
        final lastPurchase = await customSelect(
          'SELECT strftime(\'%Y-%m-%dT%H:%M:%fZ\', MAX(ps.created_at), \'unixepoch\') AS last_purchase_at '
          'FROM pending_sales ps '
          'INNER JOIN customers c ON c.id = ps.customer_id '
          'WHERE ps.customer_id = ? AND c.tenant_id = ? AND ps.id <> ? '
          "AND UPPER(ps.status) = 'COMPLETED'${purchaseScope.clause}",
          variables: [
            Variable.withString(customerId),
            Variable.withString(tenantId),
            Variable.withString(saleId),
            ...purchaseScope.variables,
          ],
        ).getSingle();
        final lastPurchaseAt =
            lastPurchase.readNullable<String>('last_purchase_at');
        await customUpdate(
          'UPDATE customers SET '
          'total_purchases = MAX(total_purchases - 1, 0), '
          'total_spent = MAX(total_spent - ?, 0), '
          'last_purchase_at = ? '
          'WHERE id = ? AND tenant_id = ?',
          variables: [
            Variable.withReal(sale.total),
            lastPurchaseAt == null
                ? const Variable<String>(null)
                : Variable.withString(lastPurchaseAt),
            Variable.withString(customerId),
            Variable.withString(tenantId),
          ],
        );
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
        final product = await (select(products)
              ..where((p) => p.id.equals(item.productId)))
            .getSingleOrNull();
        if (product == null || !product.trackInventory) continue;

        // Restore inventory to the branch where the sale happened, even if
        // the owner switched branches before opening this receipt.
        final stock = await getProductStock(item.productId, sale.branchId);
        if (stock != null) {
          await (update(localStock)..where((s) => s.id.equals(stock.id))).write(
            LocalStockCompanion(
              quantity: Value(stock.quantity + item.quantity),
              updatedAt: Value(DateTime.now()),
            ),
          );
        } else {
          // A local stock row may have been removed after the sale. Restore
          // the sale quantity so a void cannot silently discard inventory.
          await into(localStock).insert(
            LocalStockCompanion.insert(
              id: 'stock-${sale.branchId}-${item.productId}',
              productId: item.productId,
              branchId: sale.branchId,
              quantity: item.quantity,
              updatedAt: DateTime.now(),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
    });
  }

  int _pendingSaleCashTenderCents(PendingSale sale) {
    final totalCents = _amountToCents(sale.total);
    switch (sale.paymentMethod.trim().toUpperCase()) {
      case 'CASH':
        return totalCents;
      case 'SPLIT':
        return _splitTenderCents(
              sale.paymentReference,
              expectedTotalCents: totalCents,
            )['CASH'] ??
            0;
      default:
        return 0;
    }
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
      "AND UPPER(status) = 'COMPLETED' "
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
      "AND UPPER(status) = 'COMPLETED' "
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
      "AND UPPER(ps.status) = 'COMPLETED' "
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
      'LEFT JOIN pending_sales ps ON ps.id = psi.sale_id AND ps.created_at >= ? AND ps.created_at <= ?${scope.clause} AND UPPER(ps.status) = \'COMPLETED\' '
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
      'SELECT p.id, p.name, p.sku, p.metadata, p.price, p.cost_price, p.unit, '
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
            'metadata': r.read<String>('metadata'),
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

  /// Counts stock alerts for one branch without loading its product catalog.
  /// Used by compact dashboard insights that only need totals, not item data.
  Future<Map<String, int>> getInventoryAlertCounts(String branchId) async {
    final normalizedBranchId = branchId.trim();
    if (normalizedBranchId.isEmpty) {
      throw ArgumentError('A branch is required to count stock alerts.');
    }
    final row = await customSelect(
      'SELECT '
      'COALESCE(SUM(CASE WHEN COALESCE(ls.quantity, 0) <= 0 THEN 1 ELSE 0 END), 0) AS out_of_stock, '
      'COALESCE(SUM(CASE WHEN p.min_stock > 0 AND COALESCE(ls.quantity, 0) > 0 AND COALESCE(ls.quantity, 0) <= p.min_stock THEN 1 ELSE 0 END), 0) AS low_stock '
      'FROM products p '
      'LEFT JOIN local_stock ls ON ls.product_id = p.id AND ls.branch_id = ? '
      'WHERE p.is_active = 1 AND p.track_inventory = 1',
      variables: [Variable.withString(normalizedBranchId)],
      readsFrom: {products, localStock},
    ).getSingle();
    return {
      'outOfStock': row.read<int>('out_of_stock'),
      'lowStock': row.read<int>('low_stock'),
    };
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
    if (_customerTenantId == null) {
      throw Exception('Sign in to a local shop before viewing sales totals.');
    }
    if (!_activeBranchIds().contains(branchId)) {
      // Do not turn a stale or mismatched branch selection into a convincing
      // zero-sales report. This is especially important on End of Day, where
      // the owner may otherwise close a till against figures from no branch.
      throw Exception(
        'The selected branch is not available on this device. Choose an active branch and refresh.',
      );
    }
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final row = await customSelect(
      'SELECT '
      'COUNT(*) AS total_transactions, '
      'COALESCE(SUM(total), 0) AS total_sales, '
      'COALESCE(SUM(tax), 0) AS total_tax, '
      'COALESCE(SUM(discount), 0) AS total_discount '
      'FROM pending_sales '
      'WHERE branch_id = ? AND created_at >= ? AND created_at < ? '
      "AND UPPER(status) = 'COMPLETED'",
      variables: [
        Variable.withString(branchId),
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
      ],
    ).getSingle();

    // A split sale is stored locally as one SPLIT row with its CASH/CREDIT
    // tenders in payment_reference. Counting only rows whose payment method
    // is exactly CASH or CREDIT silently dropped both parts from offline End
    // of Day totals. Load the day's methods in one query and reconcile every
    // split against its sale total before including its tender breakdown.
    final paymentRows = await customSelect(
      'SELECT payment_method, total, payment_reference FROM pending_sales '
      'WHERE branch_id = ? AND created_at >= ? AND created_at < ? '
      "AND UPPER(status) = 'COMPLETED'",
      variables: [
        Variable.withString(branchId),
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
      ],
    ).get();
    var cashSalesCents = 0;
    var mpesaSalesCents = 0;
    var cardSalesCents = 0;
    var creditSalesCents = 0;
    var otherSalesCents = 0;
    final otherPaymentMethodsCents = <String, int>{};
    for (final sale in paymentRows) {
      final method = sale.read<String>('payment_method').trim().toUpperCase();
      final totalCents = _amountToCents(sale.read<double>('total'));
      switch (method) {
        case 'CASH':
          cashSalesCents += totalCents;
        case 'MPESA':
          mpesaSalesCents += totalCents;
        case 'CREDIT':
          creditSalesCents += totalCents;
        case 'PESAPAL':
        case 'TOURISTTAP':
        case 'CARD':
          cardSalesCents += totalCents;
        case 'SPLIT':
          try {
            final split = _splitTenderCents(
              sale.readNullable<String>('payment_reference'),
              expectedTotalCents: totalCents,
            );
            cashSalesCents += split['CASH'] ?? 0;
            creditSalesCents += split['CREDIT'] ?? 0;
          } on FormatException {
            // Preserve the report if a legacy split lacks its tender detail.
            // The screen surfaces this amount as unreconciled and does not
            // silently fold it into cash or credit.
            otherSalesCents += totalCents;
            otherPaymentMethodsCents.update(
              'SPLIT (UNRECONCILED)',
              (amount) => amount + totalCents,
              ifAbsent: () => totalCents,
            );
          }
        default:
          // A legacy/imported method should not make the whole End of Day
          // screen fail. Keep its value in the overall sales total and show
          // it separately; never silently treat an unknown method as cash.
          final label = method.isEmpty ? 'UNSPECIFIED' : method;
          otherSalesCents += totalCents;
          otherPaymentMethodsCents.update(
            label,
            (amount) => amount + totalCents,
            ifAbsent: () => totalCents,
          );
      }
    }

    // A completed cash tender remains a physical till inflow after its sale
    // is voided. Keep it out of sales revenue, but include the tender here so
    // the till stays balanced until a separate cash refund is actually paid.
    final voidedPaymentRows = await customSelect(
      'SELECT payment_method, total, payment_reference FROM pending_sales '
      'WHERE branch_id = ? AND created_at >= ? AND created_at < ? '
      "AND UPPER(status) = 'VOIDED'",
      variables: [
        Variable.withString(branchId),
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
      ],
    ).get();
    var voidedCashReceivedCents = 0;
    for (final sale in voidedPaymentRows) {
      final method = sale.read<String>('payment_method').trim().toUpperCase();
      final totalCents = _amountToCents(sale.read<double>('total'));
      if (method == 'CASH') {
        voidedCashReceivedCents += totalCents;
      } else if (method == 'SPLIT') {
        try {
          final split = _splitTenderCents(
            sale.readNullable<String>('payment_reference'),
            expectedTotalCents: totalCents,
          );
          voidedCashReceivedCents += split['CASH'] ?? 0;
        } on FormatException {
          // Malformed legacy split details are not guessed as cash.
        }
      }
    }

    final cashCollections = await _sumLocalCashCollections(
      branchId: branchId,
      date: date,
    );
    final cashRefunds = await _sumLocalCashRefunds(
      branchId: branchId,
      date: date,
    );
    final cashPayouts = await _sumLocalCashSupplierPayments(
      branchId: branchId,
      date: date,
    );

    return {
      'date':
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'totalSales': row.read<double>('total_sales'),
      'totalTransactions': row.read<int>('total_transactions'),
      'totalTax': row.read<double>('total_tax'),
      'totalDiscount': row.read<double>('total_discount'),
      'cashSales': cashSalesCents / 100,
      'cashCollections': cashCollections,
      'cashPayouts': cashPayouts,
      'cashRefunds': cashRefunds,
      'voidedCashReceived': voidedCashReceivedCents / 100,
      'mpesaSales': mpesaSalesCents / 100,
      'cardSales': cardSalesCents / 100,
      'creditSales': creditSalesCents / 100,
      'otherSales': otherSalesCents / 100,
      'otherPaymentMethods': otherPaymentMethodsCents.entries
          .map((entry) => {
                'method': entry.key,
                'amount': entry.value / 100,
              })
          .toList(),
      'outstandingBalance': 0.0,
    };
  }

  Future<void> _ensureLocalDailyClosesTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_daily_closes (
        id TEXT PRIMARY KEY NOT NULL,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        business_date TEXT NOT NULL,
        opening_float REAL NOT NULL,
        cash_sales REAL NOT NULL,
        cash_collections REAL NOT NULL,
        cash_payouts REAL NOT NULL DEFAULT 0,
        cash_refunds REAL NOT NULL DEFAULT 0,
        voided_cash_received REAL NOT NULL DEFAULT 0,
        net_cash_movement REAL NOT NULL,
        expected_cash REAL NOT NULL,
        counted_cash REAL NOT NULL,
        discrepancy REAL NOT NULL,
        notes TEXT,
        closed_by TEXT NOT NULL,
        closed_at TEXT NOT NULL
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_local_daily_closes_scope
      ON local_daily_closes (tenant_id, branch_id, business_date, closed_at)
    ''');
    // Devices may already have the first local-close schema from an earlier
    // build. Add the later reconciliation field without discarding close
    // records or requiring a cloud migration.
    final columns =
        await customSelect('PRAGMA table_info(local_daily_closes)').get();
    if (!columns
        .any((column) => column.read<String>('name') == 'cash_collections')) {
      await customStatement(
        'ALTER TABLE local_daily_closes '
        'ADD COLUMN cash_collections REAL NOT NULL DEFAULT 0',
      );
    }
    if (!columns
        .any((column) => column.read<String>('name') == 'cash_payouts')) {
      await customStatement(
        'ALTER TABLE local_daily_closes '
        'ADD COLUMN cash_payouts REAL NOT NULL DEFAULT 0',
      );
    }
    if (!columns
        .any((column) => column.read<String>('name') == 'cash_refunds')) {
      await customStatement(
        'ALTER TABLE local_daily_closes '
        'ADD COLUMN cash_refunds REAL NOT NULL DEFAULT 0',
      );
    }
    if (!columns.any(
        (column) => column.read<String>('name') == 'voided_cash_received')) {
      await customStatement(
        'ALTER TABLE local_daily_closes '
        'ADD COLUMN voided_cash_received REAL NOT NULL DEFAULT 0',
      );
    }
  }

  /// Saves a local till close as an auditable event. Re-closing a day inserts
  /// another event so the previous count and discrepancy remain available.
  Future<void> saveLocalDailyClose({
    required String branchId,
    required String businessDate,
    required double openingFloat,
    required double cashSales,
    required double cashCollections,
    required double cashPayouts,
    required double cashRefunds,
    required double voidedCashReceived,
    required double netCashMovement,
    required double countedCash,
    required String closedBy,
    String? notes,
  }) async {
    final tenantId = _requireCustomerTenantId();
    if (!_activeBranchIds().contains(branchId)) {
      throw StateError('This branch is not part of the active workspace.');
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(businessDate)) {
      throw ArgumentError.value(businessDate, 'businessDate');
    }
    final openingCents = _amountToCents(openingFloat);
    final salesCents = _amountToCents(cashSales);
    final collectionCents = _amountToCents(cashCollections);
    final payoutCents = _amountToCents(cashPayouts);
    final refundCents = _amountToCents(cashRefunds);
    final voidedReceivedCents = _amountToCents(voidedCashReceived);
    final movementCents = netCashMovement.isFinite
        ? (netCashMovement * 100).round()
        : throw ArgumentError.value(netCashMovement, 'netCashMovement');
    final countedCents = _amountToCents(countedCash);
    if (openingCents < 0 || countedCents < 0) {
      throw ArgumentError('Opening float and counted cash cannot be negative.');
    }
    final expectedCents = openingCents +
        salesCents +
        collectionCents -
        payoutCents +
        voidedReceivedCents -
        refundCents +
        movementCents;
    if (expectedCents < 0) {
      throw ArgumentError('Net cash movements cannot exceed available cash.');
    }
    final notesMissing = notes?.trim().isEmpty ?? true;
    if (movementCents != 0 && notesMissing) {
      throw StateError(
        'Explain other cash added or removed before closing.',
      );
    }
    if (countedCents != expectedCents && notesMissing) {
      throw StateError('Explain the cash discrepancy before closing.');
    }
    await _ensureLocalDailyClosesTable();
    await transaction(() async {
      // The user may have left the count sheet open while another staff
      // member records a sale, debt collection, refund, or supplier payment.
      // Re-read every till-affecting total inside the same transaction as the
      // close insert so we never certify a stale count as the final close.
      final current = await getDailySalesSummary(
        branchId,
        DateTime.parse(businessDate),
      );
      final currentAmounts = <String, double>{
        'cash sales': (current['cashSales'] as num).toDouble(),
        'cash collections': (current['cashCollections'] as num).toDouble(),
        'cash supplier payments': (current['cashPayouts'] as num).toDouble(),
        'cash refunds': (current['cashRefunds'] as num).toDouble(),
        'cash received on voided sales':
            (current['voidedCashReceived'] as num).toDouble(),
      };
      final savedAmounts = <String, double>{
        'cash sales': cashSales,
        'cash collections': cashCollections,
        'cash supplier payments': cashPayouts,
        'cash refunds': cashRefunds,
        'cash received on voided sales': voidedCashReceived,
      };
      final changedAmounts = currentAmounts.entries
          .where((entry) =>
              _amountToCents(entry.value) !=
              _amountToCents(savedAmounts[entry.key]!))
          .map((entry) => entry.key)
          .toList(growable: false);
      if (changedAmounts.isNotEmpty) {
        throw StateError(
          'Till activity changed while you were counting. Refresh the figures and count again.',
        );
      }

      final now = DateTime.now().toUtc();
      final closeId = '$branchId-$businessDate-${now.microsecondsSinceEpoch}';
      await customStatement(
        'INSERT INTO local_daily_closes ('
        'id, tenant_id, branch_id, business_date, opening_float, cash_sales, '
        'cash_collections, cash_payouts, cash_refunds, voided_cash_received, '
        'net_cash_movement, expected_cash, '
        'counted_cash, discrepancy, notes, closed_by, closed_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          Variable.withString(closeId),
          Variable.withString(tenantId),
          Variable.withString(branchId),
          Variable.withString(businessDate),
          Variable.withReal(openingCents / 100),
          Variable.withReal(salesCents / 100),
          Variable.withReal(collectionCents / 100),
          Variable.withReal(payoutCents / 100),
          Variable.withReal(refundCents / 100),
          Variable.withReal(voidedReceivedCents / 100),
          Variable.withReal(movementCents / 100),
          Variable.withReal(expectedCents / 100),
          Variable.withReal(countedCents / 100),
          Variable.withReal((countedCents - expectedCents) / 100),
          notes == null
              ? const Variable<String>(null)
              : Variable.withString(notes),
          Variable.withString(closedBy),
          Variable.withString(now.toIso8601String()),
        ],
      );
    });
  }

  Future<Map<String, dynamic>?> getLatestLocalDailyClose({
    required String branchId,
    required String businessDate,
  }) async {
    final tenantId = _customerTenantId;
    if (tenantId == null || !_activeBranchIds().contains(branchId)) return null;
    await _ensureLocalDailyClosesTable();
    final rows = await customSelect(
      'SELECT * FROM local_daily_closes '
      'WHERE tenant_id = ? AND branch_id = ? AND business_date = ? '
      'ORDER BY closed_at DESC LIMIT 1',
      variables: [
        Variable.withString(tenantId),
        Variable.withString(branchId),
        Variable.withString(businessDate),
      ],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'id': row.read<String>('id'),
      'branchId': row.read<String>('branch_id'),
      'businessDate': row.read<String>('business_date'),
      'openingFloat': row.read<double>('opening_float'),
      'cashSales': row.read<double>('cash_sales'),
      'cashCollections': row.read<double>('cash_collections'),
      'cashPayouts': row.read<double>('cash_payouts'),
      'cashRefunds': row.read<double>('cash_refunds'),
      'voidedCashReceived': row.read<double>('voided_cash_received'),
      'netCashMovement': row.read<double>('net_cash_movement'),
      'expectedCash': row.read<double>('expected_cash'),
      'countedCash': row.read<double>('counted_cash'),
      'cashDiscrepancy': row.read<double>('discrepancy'),
      'notes': row.readNullable<String>('notes'),
      'closedByName': row.read<String>('closed_by'),
      'closedAt': row.read<String>('closed_at'),
    };
  }

  /// Returns recent local till-close events for the active shop and branch.
  /// Each close is retained as an audit event, including when a day is
  /// reopened and closed again after new activity.
  Future<List<Map<String, dynamic>>> getLocalDailyCloseHistory({
    required String branchId,
    int limit = 20,
  }) async {
    final tenantId = _customerTenantId;
    if (tenantId == null || !_activeBranchIds().contains(branchId)) {
      return const <Map<String, dynamic>>[];
    }
    final safeLimit = limit.clamp(1, 100);
    await _ensureLocalDailyClosesTable();
    final rows = await customSelect(
      'SELECT * FROM local_daily_closes '
      'WHERE tenant_id = ? AND branch_id = ? '
      'ORDER BY closed_at DESC LIMIT ?',
      variables: [
        Variable.withString(tenantId),
        Variable.withString(branchId),
        Variable.withInt(safeLimit),
      ],
    ).get();
    return rows
        .map((row) => <String, dynamic>{
              'id': row.read<String>('id'),
              'branchId': row.read<String>('branch_id'),
              'businessDate': row.read<String>('business_date'),
              'openingFloat': row.read<double>('opening_float'),
              'cashSales': row.read<double>('cash_sales'),
              'cashCollections': row.read<double>('cash_collections'),
              'cashPayouts': row.read<double>('cash_payouts'),
              'cashRefunds': row.read<double>('cash_refunds'),
              'voidedCashReceived': row.read<double>('voided_cash_received'),
              'netCashMovement': row.read<double>('net_cash_movement'),
              'expectedCash': row.read<double>('expected_cash'),
              'countedCash': row.read<double>('counted_cash'),
              'discrepancy': row.read<double>('discrepancy'),
              'notes': row.readNullable<String>('notes'),
              'closedByName': row.read<String>('closed_by'),
              'closedAt': row.read<String>('closed_at'),
              // Aliases keep the shared reconciliation card reusable across
              // server and local close records.
              'createdAt': row.read<String>('closed_at'),
            })
        .toList(growable: false);
  }

  Future<void> _ensureLocalCashCollectionsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_cash_collections (
        id TEXT PRIMARY KEY NOT NULL,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        amount REAL NOT NULL,
        collected_at TEXT NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        reference TEXT
      )
    ''');
    final columns = await customSelect(
      'PRAGMA table_info(local_cash_collections)',
    ).get();
    if (!columns.any((row) => row.read<String>('name') == 'payment_method')) {
      try {
        await customStatement(
          "ALTER TABLE local_cash_collections ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'CASH'",
        );
      } catch (_) {
        // Another concurrent Finance read may have applied this upgrade.
      }
    }
    if (!columns.any((row) => row.read<String>('name') == 'reference')) {
      try {
        await customStatement(
          'ALTER TABLE local_cash_collections ADD COLUMN reference TEXT',
        );
      } catch (_) {
        // Another concurrent Finance read may have applied this upgrade.
      }
    }
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_local_cash_collections_scope
      ON local_cash_collections (tenant_id, branch_id, collected_at)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_local_cash_collections_customer_date
      ON local_cash_collections (tenant_id, customer_id, collected_at)
    ''');
  }

  Future<void> _ensureLocalCashRefundsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_cash_refunds (
        id TEXT PRIMARY KEY NOT NULL,
        tenant_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        sale_id TEXT NOT NULL UNIQUE,
        amount REAL NOT NULL CHECK (amount > 0),
        refunded_at TEXT NOT NULL,
        recorded_by TEXT,
        reason TEXT NOT NULL
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_local_cash_refunds_scope
      ON local_cash_refunds (tenant_id, branch_id, refunded_at)
    ''');
  }

  Future<double> _sumLocalCashRefunds({
    required String branchId,
    required DateTime date,
  }) async {
    await _ensureLocalCashRefundsTable();
    final tenantId = _customerTenantId;
    if (tenantId == null || !_activeBranchIds().contains(branchId)) return 0;
    final start =
        DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
    final end = DateTime(date.year, date.month, date.day)
        .add(const Duration(days: 1))
        .toUtc()
        .toIso8601String();
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM local_cash_refunds '
      'WHERE tenant_id = ? AND branch_id = ? '
      'AND refunded_at >= ? AND refunded_at < ?',
      variables: [
        Variable.withString(tenantId),
        Variable.withString(branchId),
        Variable.withString(start),
        Variable.withString(end),
      ],
    ).getSingle();
    return row.read<double>('total');
  }

  Future<void> ensureLocalCashCollectionsSchema() =>
      _ensureLocalCashCollectionsTable();

  Future<double> _sumLocalCashCollections({
    required String branchId,
    required DateTime date,
  }) async {
    await _ensureLocalCashCollectionsTable();
    final tenantId = _customerTenantId;
    if (tenantId == null || !_activeBranchIds().contains(branchId)) return 0;
    final start =
        DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
    final end = DateTime(date.year, date.month, date.day)
        .add(const Duration(days: 1))
        .toUtc()
        .toIso8601String();
    final row = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM local_cash_collections '
      'WHERE tenant_id = ? AND branch_id = ? '
      'AND UPPER(TRIM(payment_method)) = \'CASH\' '
      'AND collected_at >= ? AND collected_at < ?',
      variables: [
        Variable.withString(tenantId),
        Variable.withString(branchId),
        Variable.withString(start),
        Variable.withString(end),
      ],
    ).getSingle();
    return row.read<double>('total');
  }

  Future<double> _sumLocalCashSupplierPayments({
    required String branchId,
    required DateTime date,
  }) async {
    await _createSupplierFinanceTables();
    final tenantId = _customerTenantId;
    if (tenantId == null || !_activeBranchIds().contains(branchId)) return 0;
    final start =
        DateTime(date.year, date.month, date.day).toUtc().toIso8601String();
    final end = DateTime(date.year, date.month, date.day)
        .add(const Duration(days: 1))
        .toUtc()
        .toIso8601String();
    final row = await customSelect(
      'SELECT COALESCE(SUM(sp.amount), 0) AS total '
      'FROM supplier_payments sp '
      'JOIN suppliers s ON s.id = sp.supplier_id '
      'WHERE s.tenant_id = ? AND sp.branch_id = ? '
      'AND UPPER(TRIM(sp.funding_source)) = \'CASH_TILL\' '
      'AND sp.payment_date >= ? AND sp.payment_date < ?',
      variables: [
        Variable.withString(tenantId),
        Variable.withString(branchId),
        Variable.withString(start),
        Variable.withString(end),
      ],
    ).getSingle();
    return row.read<double>('total');
  }

  int _amountToCents(double amount) {
    if (!amount.isFinite || amount < 0) {
      throw const FormatException('A local sale has an invalid amount.');
    }
    return (amount * 100).round();
  }

  Map<String, int> _splitTenderCents(
    String? rawReference, {
    required int expectedTotalCents,
  }) {
    if (rawReference == null || rawReference.trim().isEmpty) {
      throw const FormatException(
        'A local split sale is missing its payment breakdown.',
      );
    }

    final decoded = jsonDecode(rawReference);
    if (decoded is! List || decoded.isEmpty) {
      throw const FormatException(
        'A local split sale has an invalid payment breakdown.',
      );
    }

    final result = <String, int>{};
    var tenderTotalCents = 0;
    for (final entry in decoded) {
      if (entry is! Map) {
        throw const FormatException(
          'A local split sale has an invalid tender.',
        );
      }
      final method = entry['method']?.toString().trim().toUpperCase() ?? '';
      if (method != 'CASH' && method != 'CREDIT') {
        throw const FormatException(
          'A local split sale has an unsupported tender method.',
        );
      }
      final rawAmount = entry['amount'];
      final amount = rawAmount is num
          ? rawAmount.toDouble()
          : double.tryParse(rawAmount?.toString() ?? '');
      if (amount == null || !amount.isFinite || amount <= 0) {
        throw const FormatException(
          'A local split sale has an invalid tender amount.',
        );
      }
      final cents = _amountToCents(amount);
      if (cents <= 0) {
        throw const FormatException(
          'A local split sale has a tender below one cent.',
        );
      }
      result.update(method, (value) => value + cents, ifAbsent: () => cents);
      tenderTotalCents += cents;
    }

    if (tenderTotalCents != expectedTotalCents) {
      throw const FormatException(
        'A local split sale does not balance to its recorded total.',
      );
    }
    return result;
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
      "AND UPPER(status) = 'COMPLETED'",
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
      "AND UPPER(ps.status) = 'COMPLETED'",
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
      "AND UPPER(status) = 'COMPLETED'",
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
      "AND UPPER(ps.status) = 'COMPLETED'",
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
      // Drift stores DateTime columns as Unix seconds. Interpret them
      // explicitly and group by the device's local business hour; passing the
      // integer directly to strftime treats it as a Julian day and returns
      // NULL, which used to break local payment analytics.
      'SELECT strftime(\'%H\', created_at, \'unixepoch\', \'localtime\') as hour, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ?${scope.clause} '
      "AND UPPER(status) = 'COMPLETED' "
      'GROUP BY strftime(\'%H\', created_at, \'unixepoch\', \'localtime\') '
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
      'SELECT date(created_at, \'unixepoch\', \'localtime\') as date, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ?${scope.clause} '
      "AND UPPER(status) = 'COMPLETED' "
      'GROUP BY date(created_at, \'unixepoch\', \'localtime\') '
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
      'SELECT date(ps.created_at, \'unixepoch\', \'localtime\') as date, COALESCE(SUM(psi.quantity), 0) as items_sold '
      'FROM pending_sales ps '
      'INNER JOIN pending_sale_items psi ON psi.sale_id = ps.id '
      'WHERE ps.created_at >= ? AND ps.created_at <= ?${scope.clause} '
      "AND UPPER(ps.status) = 'COMPLETED' "
      'GROUP BY date(ps.created_at, \'unixepoch\', \'localtime\') '
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
      'COALESCE(SUM(CASE WHEN UPPER(payment_method) = \'CASH\' THEN 1 ELSE 0 END), 0) as cash_count, '
      'COALESCE(SUM(CASE WHEN UPPER(payment_method) LIKE \'%CARD%\' OR UPPER(payment_method) LIKE \'%CREDIT%\' THEN 1 ELSE 0 END), 0) as card_count, '
      'COALESCE(SUM(CASE WHEN UPPER(payment_method) LIKE \'%MPESA%\' OR UPPER(payment_method) LIKE \'%PESAPAL%\' OR UPPER(payment_method) LIKE \'%TOURISTTAP%\' THEN 1 ELSE 0 END), 0) as digital_count '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ?${scope.clause} '
      "AND UPPER(status) = 'COMPLETED'",
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
      'SELECT strftime(\'%H\', created_at, \'unixepoch\', \'localtime\') as hour, COUNT(*) as transaction_count, SUM(total) as total_amount '
      'FROM pending_sales '
      'WHERE created_at >= ? AND created_at <= ?${scope.clause} '
      "AND UPPER(status) = 'COMPLETED' "
      'GROUP BY strftime(\'%H\', created_at, \'unixepoch\', \'localtime\') '
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
      "AND UPPER(ps.status) = 'COMPLETED' "
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

  /// Ensures an already-known cloud branch is present in the local branch
  /// index without replacing its existing metadata. Used when an authenticated
  /// workspace is adopted by the downloadable, device-only edition.
  Future<void> ensureLocalBranch({
    required String id,
    required String name,
    required String location,
    required String phone,
  }) async {
    await createBranchesTable();
    await customInsert(
      'INSERT OR IGNORE INTO branches '
      '(id, name, location, phone, is_active, created_at) '
      'VALUES (?, ?, ?, ?, 1, ?)',
      variables: [
        Variable.withString(id),
        Variable.withString(name),
        Variable.withString(location),
        Variable.withString(phone),
        Variable.withString(DateTime.now().toUtc().toIso8601String()),
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
      '  collection_allocations TEXT, '
      '  paid_amount REAL NOT NULL DEFAULT 0, '
      '  cancelled_at TEXT, '
      '  cancelled_by TEXT, '
      '  cancel_reason TEXT'
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
    if (!columns.any((row) => row.read<String>('name') == 'paid_amount')) {
      try {
        await customStatement(
          'ALTER TABLE customer_installments ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0',
        );
      } catch (_) {
        // Another concurrent Finance or Customer read may have applied it.
      }
    }
    if (!columns.any((row) => row.read<String>('name') == 'cancelled_at')) {
      try {
        await customStatement(
          'ALTER TABLE customer_installments ADD COLUMN cancelled_at TEXT',
        );
      } catch (_) {
        // Another concurrent customer/Finance read may have applied it.
      }
    }
    if (!columns.any((row) => row.read<String>('name') == 'cancelled_by')) {
      try {
        await customStatement(
          'ALTER TABLE customer_installments ADD COLUMN cancelled_by TEXT',
        );
      } catch (_) {
        // Another concurrent customer/Finance read may have applied it.
      }
    }
    if (!columns.any((row) => row.read<String>('name') == 'cancel_reason')) {
      try {
        await customStatement(
          'ALTER TABLE customer_installments ADD COLUMN cancel_reason TEXT',
        );
      } catch (_) {
        // Another concurrent customer/Finance read may have applied it.
      }
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
    final id = 'inst-${DateTime.now().microsecondsSinceEpoch}';
    await transaction(() async {
      final customer = await customSelect(
        'SELECT balance FROM customers WHERE id = ? AND tenant_id = ?',
        variables: [
          Variable.withString(customerId),
          Variable.withString(tenantId),
        ],
      ).getSingleOrNull();
      if (customer == null) throw StateError('Customer was not found');

      final balance = customer.read<double>('balance');
      final scheduled = await customSelect(
        'SELECT COALESCE(SUM(amount - COALESCE(paid_amount, 0)), 0) AS total '
        'FROM customer_installments WHERE customer_id = ? AND tenant_id = ? '
        'AND status IN (\'pending\', \'overdue\')',
        variables: [
          Variable.withString(customerId),
          Variable.withString(tenantId),
        ],
      ).getSingle();
      final alreadyScheduled = scheduled.read<double>('total');
      final available =
          (balance - alreadyScheduled).clamp(0, double.infinity).toDouble();
      if (!balance.isFinite || amount > available + 0.005) {
        throw StateError(
          'This amount exceeds the customer balance still available to schedule.',
        );
      }

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
    });
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
    return result.map((r) {
      final scheduledAmount = r.read<double>('amount');
      final paidAmount = r.readNullable<double>('paid_amount') ?? 0;
      final status = r.read<String>('status');
      final remainingAmount =
          (scheduledAmount - paidAmount).clamp(0, double.infinity).toDouble();
      return <String, dynamic>{
        'id': r.read<String>('id'),
        'customerId': r.read<String>('customer_id'),
        'amount':
            status.toLowerCase() == 'paid' ? scheduledAmount : remainingAmount,
        'scheduledAmount': scheduledAmount,
        'paidAmount': paidAmount,
        'dueDate': r.read<String>('due_date'),
        'note': r.readNullable<String>('note') ?? '',
        'status': status,
        'createdAt': r.read<String>('created_at'),
        'paidAt': r.readNullable<String>('paid_at'),
        'cancelledAt': r.readNullable<String>('cancelled_at'),
        'cancelledBy': r.readNullable<String>('cancelled_by'),
        'cancelReason': r.readNullable<String>('cancel_reason'),
        'collectionAllocations':
            r.readNullable<String>('collection_allocations'),
      };
    }).toList(growable: false);
  }

  /// Recent customer sales for a locally generated account statement. Keep
  /// this query tenant- and branch-scoped and bounded so a long customer
  /// history cannot stall sharing from the profile screen.
  Future<List<Map<String, dynamic>>> getRecentCustomerSales(
    String customerId, {
    int limit = 8,
  }) async {
    final tenantId = _customerTenantId;
    final scope = _salesBranchScope('ps');
    if (tenantId == null || _activeBranchIds().isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final safeLimit = limit.clamp(1, 50).toInt();
    final rows = await customSelect(
      // Drift stores this generated DateTime column as Unix seconds. Format
      // it in SQLite before reading a string for the shareable statement.
      "SELECT ps.id, ps.receipt_number, ps.total, ps.payment_method, "
      "strftime('%Y-%m-%dT%H:%M:%fZ', ps.created_at, 'unixepoch') AS created_at "
      "FROM pending_sales ps "
      "INNER JOIN customers c ON c.id = ps.customer_id "
      "WHERE ps.customer_id = ? AND c.tenant_id = ? "
      // A pending M-Pesa/card record is not proof that the customer paid.
      "AND UPPER(ps.status) = 'COMPLETED'"
      '${scope.clause} ORDER BY ps.created_at DESC LIMIT ?',
      variables: [
        Variable.withString(customerId),
        Variable.withString(tenantId),
        ...scope.variables,
        Variable.withInt(safeLimit),
      ],
    ).get();
    return rows
        .map((row) => <String, dynamic>{
              'id': row.read<String>('id'),
              'receiptNumber': row.readNullable<String>('receipt_number'),
              'total': row.read<double>('total'),
              'paymentMethod': row.read<String>('payment_method'),
              'createdAt': row.read<String>('created_at'),
            })
        .toList(growable: false);
  }

  /// Recent debt collections recorded on this device, for local statements.
  Future<List<Map<String, dynamic>>> getRecentCustomerCollections(
    String customerId, {
    int limit = 8,
  }) async {
    await createCustomersTable();
    await _ensureLocalCashCollectionsTable();
    final tenantId = _customerTenantId;
    if (tenantId == null) return const <Map<String, dynamic>>[];
    final safeLimit = limit.clamp(1, 50).toInt();
    final rows = await customSelect(
      'SELECT id, amount, payment_method, reference, collected_at '
      'FROM local_cash_collections '
      'WHERE customer_id = ? AND tenant_id = ? '
      'ORDER BY collected_at DESC LIMIT ?',
      variables: [
        Variable.withString(customerId),
        Variable.withString(tenantId),
        Variable.withInt(safeLimit),
      ],
    ).get();
    return rows
        .map((row) => <String, dynamic>{
              'id': row.read<String>('id'),
              'amount': row.read<double>('amount'),
              'paymentMethod': row.read<String>('payment_method'),
              'reference': row.readNullable<String>('reference'),
              'collectedAt': row.read<String>('collected_at'),
            })
        .toList(growable: false);
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

  Future<bool> markInstallmentPaid(
    String installmentId, {
    bool recordLocalCashCollection = false,
  }) async {
    await createCustomerInstallmentsTable();
    await createCustomersTable();
    final tenantId = _customerTenantId;
    if (tenantId == null) return false;
    final branchId = recordLocalCashCollection ? _storage.getBranchId() : null;
    if (recordLocalCashCollection &&
        (branchId == null || !_activeBranchIds().contains(branchId))) {
      throw StateError(
          'Select a branch before recording this cash collection.');
    }
    if (recordLocalCashCollection) await _ensureLocalCashCollectionsTable();
    return transaction(() async {
      final installment = await customSelect(
        'SELECT customer_id, amount, paid_amount, status FROM customer_installments WHERE id = ? AND tenant_id = ?',
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
      final scheduledAmount = installment.read<double>('amount');
      final alreadyPaid = installment.read<double>('paid_amount');
      final amount =
          (scheduledAmount - alreadyPaid).clamp(0, double.infinity).toDouble();
      if (amount <= 0.005) return false;
      final paidAt = DateTime.now().toIso8601String();
      final updatedInstallments = await customUpdate(
        'UPDATE customer_installments SET status = \'paid\', paid_at = ?, paid_amount = amount '
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
        'UPDATE customers SET balance = MAX(balance - ?, 0) '
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
      if (recordLocalCashCollection) {
        await customStatement(
          'INSERT INTO local_cash_collections '
          '(id, tenant_id, branch_id, customer_id, amount, collected_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            Variable.withString(installmentId),
            Variable.withString(tenantId),
            Variable.withString(branchId!),
            Variable.withString(customerId),
            Variable.withReal(amount),
            Variable.withString(DateTime.now().toUtc().toIso8601String()),
          ],
        );
      }
      return true;
    });
  }

  /// Cancels a customer payment reminder without forgiving or changing the
  /// customer's debt. The cancellation remains in the schedule history.
  Future<bool> cancelCustomerInstallment(
    String installmentId, {
    String? cancelledBy,
    String? reason,
  }) async {
    await createCustomerInstallmentsTable();
    final tenantId = _requireCustomerTenantId();
    final cleanReason = reason?.trim();
    final cleanActor = cancelledBy?.trim();
    final changed = await customUpdate(
      'UPDATE customer_installments SET status = \'cancelled\', cancelled_at = ?, '
      'cancelled_by = ?, cancel_reason = ? '
      'WHERE id = ? AND tenant_id = ? AND status IN (\'pending\', \'overdue\')',
      variables: [
        Variable.withString(DateTime.now().toUtc().toIso8601String()),
        cleanActor == null || cleanActor.isEmpty
            ? const Variable<String>(null)
            : Variable.withString(cleanActor),
        cleanReason == null || cleanReason.isEmpty
            ? const Variable<String>(null)
            : Variable.withString(cleanReason),
        Variable.withString(installmentId),
        Variable.withString(tenantId),
      ],
    );
    return changed == 1;
  }

  /// Installments past their due date and still unpaid, across all
  /// customers — used to surface who needs a follow-up call today.
  Future<List<Map<String, dynamic>>> getOverdueInstallments() async {
    await createCustomerInstallmentsTable();
    await createCustomersTable();
    final tenantId = _customerTenantId;
    if (tenantId == null) return const [];
    final result = await customSelect(
      'SELECT ci.id, ci.customer_id, ci.amount - COALESCE(ci.paid_amount, 0) AS amount, '
      'ci.due_date, ci.note, c.name as customer_name, c.phone as customer_phone '
      'FROM customer_installments ci '
      'JOIN customers c ON c.id = ci.customer_id AND c.tenant_id = ci.tenant_id '
      'WHERE ci.tenant_id = ? AND ci.status IN (\'pending\', \'overdue\') '
      'AND date(ci.due_date) < date(\'now\', \'localtime\') '
      'ORDER BY ci.due_date ASC',
      variables: [Variable.withString(tenantId)],
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
  }) async =>
      (await insertOrGetCustomerWithStatus(
        id,
        name,
        phone: phone,
        location: location,
        email: email,
        notes: notes,
        initialBalance: initialBalance,
        creditLimit: creditLimit,
      ))
          .id;

  /// Finds a customer by name plus a supplied phone/email identity, or creates
  /// a separate record when the same name belongs to another person. A name
  /// alone is never enough to overwrite an existing customer's contact data.
  Future<CustomerInsertOutcome> insertOrGetCustomerWithStatus(
    String id,
    String name, {
    String? phone,
    String? location,
    String? email,
    String? notes,
    double initialBalance = 0,
    double creditLimit = 0,
  }) async {
    final nameValue = name.trim();
    if (nameValue.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty');
    }
    if (!initialBalance.isFinite || initialBalance < 0) {
      throw ArgumentError.value(
        initialBalance,
        'initialBalance',
        'Must be a non-negative amount',
      );
    }
    if (!creditLimit.isFinite || creditLimit < 0) {
      throw ArgumentError.value(
        creditLimit,
        'creditLimit',
        'Must be a non-negative amount',
      );
    }
    await createCustomersTable();
    final tenantId = _requireCustomerTenantId();
    final phoneValue = phone?.trim() ?? '';
    final emailValue = email?.trim() ?? '';
    final phoneKey = _customerPhoneIdentity(phoneValue);
    final emailKey = _customerEmailIdentity(emailValue);
    if (phoneValue.isNotEmpty && phoneKey.isEmpty) {
      throw ArgumentError.value(phone, 'phone', 'Must contain digits');
    }

    return transaction(() async {
      final sameName = await customSelect(
        'SELECT id, name, phone, email FROM customers '
        'WHERE tenant_id = ? AND LOWER(name) = LOWER(?) ORDER BY created_at, id',
        variables: [
          Variable.withString(tenantId),
          Variable.withString(nameValue),
        ],
      ).get();

      if (phoneKey.isEmpty && emailKey.isEmpty && sameName.isNotEmpty) {
        throw StateError(
          'A customer with this name is already saved. Choose the existing customer or add a phone number to identify a different person.',
        );
      }

      List<QueryRow> identityMatches = const [];
      if (phoneKey.isNotEmpty) {
        identityMatches = sameName
            .where((row) =>
                _customerPhoneIdentity(row.readNullable<String>('phone')) ==
                phoneKey)
            .toList();
      } else if (emailKey.isNotEmpty) {
        identityMatches = sameName
            .where((row) =>
                _customerEmailIdentity(row.readNullable<String>('email')) ==
                emailKey)
            .toList();
      }

      if (identityMatches.length > 1) {
        throw StateError(
          'More than one saved customer matches these details. Select the correct customer from the list before continuing.',
        );
      }
      final existing = identityMatches.isEmpty ? null : identityMatches.single;
      if (existing != null) {
        final existingId = existing.read<String>('id');
        final existingPhone = existing.readNullable<String>('phone') ?? '';
        final existingEmail = existing.readNullable<String>('email') ?? '';
        if (phoneValue.isNotEmpty && existingPhone.trim().isEmpty) {
          await customStatement(
            'UPDATE customers SET phone = ? WHERE id = ? AND tenant_id = ?',
            [phoneValue, existingId, tenantId],
          );
        }
        if (emailValue.isNotEmpty && existingEmail.trim().isEmpty) {
          await customStatement(
            'UPDATE customers SET email = ? WHERE id = ? AND tenant_id = ?',
            [emailValue, existingId, tenantId],
          );
        }
        if (location != null && location.trim().isNotEmpty) {
          await customStatement(
            'UPDATE customers SET location = ? WHERE id = ? AND tenant_id = ?',
            [location.trim(), existingId, tenantId],
          );
        }
        return CustomerInsertOutcome(
          id: existingId,
          name: existing.read<String>('name'),
          created: false,
        );
      }

      await customInsert(
        'INSERT INTO customers (id, tenant_id, name, phone, email, location, notes, total_purchases, total_spent, created_at, balance, credit_limit, loyalty_points) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?, 0)',
        variables: [
          Variable.withString(id),
          Variable.withString(tenantId),
          Variable.withString(nameValue),
          Variable.withString(phoneValue),
          Variable.withString(emailValue),
          Variable.withString(location?.trim() ?? ''),
          Variable.withString(notes?.trim() ?? ''),
          Variable.withString(DateTime.now().toIso8601String()),
          Variable.withReal(initialBalance),
          Variable.withReal(creditLimit),
        ],
      );
      return CustomerInsertOutcome(id: id, name: nameValue, created: true);
    });
  }

  /// Creates a new customer and their opening credit schedule as one local
  /// operation. A failed schedule insert must not leave behind a customer with
  /// an opening balance that the form reported as unsaved.
  Future<String> createCustomerWithInitialCredit({
    required String id,
    required String name,
    required String phone,
    required String location,
    required String notes,
    required double amount,
    required DateTime dueDate,
  }) async {
    final nameValue = name.trim();
    final phoneValue = phone.trim();
    final phoneKey = _customerPhoneIdentity(phoneValue);
    if (nameValue.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty');
    }
    if (phoneKey.isEmpty) {
      throw ArgumentError.value(phone, 'phone', 'Must contain a phone number');
    }
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be a positive amount');
    }
    await createCustomersTable();
    await createCustomerInstallmentsTable();
    final tenantId = _requireCustomerTenantId();
    final installmentId = 'inst-${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();

    return transaction(() async {
      final sameName = await customSelect(
        'SELECT id, phone FROM customers '
        'WHERE tenant_id = ? AND LOWER(name) = LOWER(?)',
        variables: [
          Variable.withString(tenantId),
          Variable.withString(nameValue),
        ],
      ).get();
      final existingIdentity = sameName.any((row) {
        if (phoneKey.isEmpty) return true;
        final savedPhone = _customerPhoneIdentity(
          row.readNullable<String>('phone'),
        );
        return savedPhone.isNotEmpty && savedPhone == phoneKey;
      });
      if (existingIdentity) {
        throw StateError(
          phoneKey.isEmpty
              ? 'A customer with this name is already saved. Add a phone number to identify a different person, or open the saved profile to record additional credit.'
              : 'A customer with this name and phone number is already saved. Open their profile to record additional credit.',
        );
      }

      await customInsert(
        'INSERT INTO customers (id, tenant_id, name, phone, email, location, notes, total_purchases, total_spent, created_at, balance, credit_limit, loyalty_points) '
        'VALUES (?, ?, ?, ?, \'\', ?, ?, 0, 0, ?, ?, 0, 0)',
        variables: [
          Variable.withString(id),
          Variable.withString(tenantId),
          Variable.withString(nameValue),
          Variable.withString(phoneValue),
          Variable.withString(location),
          Variable.withString(notes),
          Variable.withString(now),
          Variable.withReal(amount),
        ],
      );
      await customInsert(
        'INSERT INTO customer_installments (id, tenant_id, customer_id, amount, due_date, note, status, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, \'pending\', ?)',
        variables: [
          Variable.withString(installmentId),
          Variable.withString(tenantId),
          Variable.withString(id),
          Variable.withReal(amount),
          Variable.withString(dueDate.toIso8601String()),
          Variable.withString('Initial credit sale'),
          Variable.withString(now),
        ],
      );
      return id;
    });
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
    if (!limit.isFinite || limit < 0) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Credit limit must be a finite amount of zero or more.',
      );
    }
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
      'SELECT psi.product_id, psi.product_name, SUM(psi.quantity) as total_qty, COUNT(DISTINCT ps.id) as times_bought '
      'FROM pending_sale_items psi '
      'INNER JOIN pending_sales ps ON ps.id = psi.sale_id '
      'INNER JOIN customers c ON c.id = ps.customer_id '
      "WHERE ps.customer_id = ? AND c.tenant_id = ? AND UPPER(ps.status) = 'COMPLETED'${scope.clause} "
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
      "WHERE ps.customer_id = ? AND c.tenant_id = ? AND UPPER(ps.status) = 'COMPLETED'${scope.clause} "
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

  /// Gives a new local workspace a stable category so products can be sold
  /// immediately even when the merchant skips category setup.
  Future<String> ensureLocalDefaultCategory() async {
    const id = 'local-default-category';
    if (await getCategory(id) == null) {
      final now = DateTime.now();
      await insertCategory(CategoriesCompanion.insert(
        id: id,
        name: 'General',
        description: const Value('Default local product category'),
        sortOrder: const Value(0),
        isActive: const Value(true),
        createdAt: now,
        updatedAt: now,
      ));
    }
    return id;
  }

  /// Atomically stores a local catalog item, its selling tiers, and its
  /// initial branch stock row. A partially saved product would otherwise
  /// appear in the POS without its prices or stock state.
  Future<void> saveLocalProduct({
    required ProductsCompanion product,
    required String productId,
    required List<ProductPricingTiersCompanion> tiers,
    required String branchId,
  }) async {
    await transaction(() async {
      final savedId = product.id.present ? product.id.value.trim() : '';
      final sku = product.sku.present ? product.sku.value.trim() : '';
      final name = product.name.present ? product.name.value.trim() : '';
      final categoryId =
          product.categoryId.present ? product.categoryId.value.trim() : '';
      final price = product.price.present ? product.price.value : double.nan;
      final minStock = product.minStock.present ? product.minStock.value : -1;
      if (productId.trim().isEmpty ||
          branchId.trim().isEmpty ||
          savedId.isEmpty ||
          savedId != productId ||
          sku.isEmpty ||
          name.isEmpty ||
          categoryId.isEmpty ||
          !price.isFinite ||
          price < 0 ||
          minStock < 0 ||
          minStock > 2147483647) {
        throw StateError(
            'Check the product name, item code, price, and stock.');
      }

      if (product.costPrice.present) {
        final costPrice = product.costPrice.value;
        if (costPrice != null && (!costPrice.isFinite || costPrice < 0)) {
          throw StateError('Enter a valid product cost.');
        }
      }

      final category = await (select(categories)
            ..where((row) => row.id.equals(categoryId)))
          .getSingleOrNull();
      if (category == null) {
        throw StateError('Choose a category that is available on this device.');
      }

      final duplicateSku = await customSelect(
        'SELECT id FROM products WHERE sku = ? AND id <> ? LIMIT 1',
        variables: [
          Variable.withString(sku),
          Variable.withString(savedId),
        ],
      ).getSingleOrNull();
      if (duplicateSku != null) {
        throw StateError('That item code is already used by another product.');
      }

      final seenUnits = <String>{};
      final seenTierIds = <String>{};
      for (final tier in tiers) {
        final tierId = tier.id.present ? tier.id.value.trim() : '';
        final tierProductId =
            tier.productId.present ? tier.productId.value.trim() : '';
        final unit = tier.unit.present ? tier.unit.value.trim() : '';
        final quantity = tier.quantityPerUnit.present
            ? tier.quantityPerUnit.value
            : double.nan;
        final tierPrice = tier.price.present ? tier.price.value : double.nan;
        if (tierId.isEmpty ||
            !seenTierIds.add(tierId) ||
            tierProductId != savedId ||
            unit.isEmpty ||
            !seenUnits.add(unit.toLowerCase()) ||
            !quantity.isFinite ||
            quantity <= 0 ||
            !tierPrice.isFinite ||
            tierPrice < 0) {
          throw StateError(
              'Check the unit, quantity, and price for each tier.');
        }
      }

      final existingProduct = await (select(products)
            ..where((row) => row.id.equals(savedId)))
          .getSingleOrNull();
      if (existingProduct == null) {
        await into(products).insert(product);
      } else {
        // Update the row in place. SQLite REPLACE deletes and reinserts a row,
        // which can break references from receipts and stock history.
        await (update(products)..where((row) => row.id.equals(savedId)))
            .write(product);
      }
      await (delete(productPricingTiers)
            ..where((tier) => tier.productId.equals(savedId)))
          .go();
      if (tiers.isNotEmpty) {
        await batch((batch) {
          batch.insertAllOnConflictUpdate(productPricingTiers, tiers);
        });
      }

      final existingStock = await (select(localStock)
            ..where((stock) =>
                stock.productId.equals(savedId) &
                stock.branchId.equals(branchId)))
          .getSingleOrNull();
      if (existingStock == null) {
        await into(localStock).insert(LocalStockCompanion.insert(
          id: 'stock-$branchId-$savedId',
          productId: savedId,
          branchId: branchId,
          quantity: 0,
          updatedAt: DateTime.now(),
        ));
      }
    });
  }

  /// Archives/restores a local category without rewriting product or sales
  /// history. Archived categories stay available to reports and can be
  /// restored from category management.
  Future<void> setLocalCategoryActive(
    String categoryId, {
    required bool isActive,
  }) async {
    final category = await getCategory(categoryId);
    if (category == null) throw StateError('Category was not found.');
    if (!isActive && categoryId == 'local-default-category') {
      throw StateError('The General category cannot be archived.');
    }
    await updateCategory(
      categoryId,
      CategoriesCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now()),
      ),
    );
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

  /// Hides a local product from the POS while preserving its sales, stock,
  /// supplier, and reporting references. Archived products can be restored.
  Future<void> setLocalProductActive(
    String productId, {
    required bool isActive,
  }) async {
    await transaction(() async {
      final product = await getProduct(productId);
      if (product == null) throw StateError('Product was not found.');
      await updateProduct(
        productId,
        ProductsCompanion(
          isActive: Value(isActive),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (!isActive) {
        await (delete(favoriteProducts)
              ..where((favorite) => favorite.productId.equals(productId)))
            .go();
      }
    });
  }

  Future<int> getProductCount() async {
    final result = await customSelect(
      'SELECT COUNT(*) as count FROM products WHERE is_active = 1',
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

  /// Returns one invoice per supplier payable for the standalone Finance
  /// workspace, including payment history recorded on this device.
  Future<List<Map<String, dynamic>>> getLocalFinanceSupplierInvoices() async {
    await _createSupplierFinanceTables();
    final tenantId = _customerTenantId;
    if (tenantId == null) return const <Map<String, dynamic>>[];
    final invoices = await customSelect(
      'SELECT si.*, s.id AS supplier_record_id, s.name AS supplier_name, s.phone AS supplier_phone FROM supplier_invoices si JOIN suppliers s ON s.id = si.supplier_id WHERE s.tenant_id = ? ORDER BY si.created_at DESC',
      variables: [Variable.withString(tenantId)],
    ).get();
    final paymentRows = await customSelect(
      'SELECT sp.invoice_id, sp.id, sp.amount, sp.notes, sp.payment_date, sp.funding_source FROM supplier_payments sp JOIN supplier_invoices si ON si.id = sp.invoice_id JOIN suppliers s ON s.id = si.supplier_id WHERE s.tenant_id = ? ORDER BY sp.payment_date DESC',
      variables: [Variable.withString(tenantId)],
    ).get();
    final paymentsByInvoice = <String, List<QueryRow>>{};
    for (final row in paymentRows) {
      final invoiceId = row.read<String>('invoice_id');
      paymentsByInvoice.putIfAbsent(invoiceId, () => <QueryRow>[]).add(row);
    }
    final result = <Map<String, dynamic>>[];
    for (final invoice in invoices) {
      final invoiceId = invoice.read<String>('id');
      final payments = paymentsByInvoice[invoiceId] ?? const <QueryRow>[];
      result.add(<String, dynamic>{
        'id': invoiceId,
        'supplierId': invoice.read<String>('supplier_record_id'),
        'supplierName': invoice.read<String>('supplier_name'),
        'supplierPhone': invoice.readNullable<String>('supplier_phone'),
        'invoiceNumber': invoice.readNullable<String>('invoice_number'),
        'totalAmount': invoice.read<double>('total_amount'),
        'paidAmount': invoice.read<double>('paid_amount'),
        'outstandingAmount': invoice.read<double>('due_amount'),
        'dueDate': invoice.readNullable<String>('due_date'),
        'status': invoice.read<String>('status'),
        'createdAt': invoice.read<String>('created_at'),
        'payments': payments
            .map((payment) => <String, dynamic>{
                  'id': 'local-supplier-payment-${payment.read<int>('id')}',
                  'amount': payment.read<double>('amount'),
                  'fundingSource': payment.read<String>('funding_source'),
                  'paidAt': payment.read<String>('payment_date'),
                  'notes': payment.readNullable<String>('notes'),
                })
            .toList(growable: false),
      });
    }
    return result;
  }

  /// Records money actually received against local customer balances. A
  /// stable request ID makes repeated taps/retries idempotent.
  Future<void> recordLocalCustomerCollections({
    required String branchId,
    required List<Map<String, dynamic>> allocations,
    required String requestId,
    String? reference,
  }) async {
    await createCustomersTable();
    await _ensureLocalCashCollectionsTable();
    final tenantId = _requireCustomerTenantId();
    final normalizedBranch = branchId.trim();
    final normalizedRequest = requestId.trim();
    final normalizedReference =
        reference?.trim().isNotEmpty == true ? reference!.trim() : null;
    if (normalizedBranch.isEmpty ||
        !_activeBranchIds().contains(normalizedBranch)) {
      throw StateError('Select a valid branch before recording a collection.');
    }
    if (normalizedRequest.isEmpty ||
        allocations.isEmpty ||
        allocations.length > 50) {
      throw ArgumentError('Select up to 50 customer balances to collect.');
    }

    final normalized = <({String customerId, double amount})>[];
    final seen = <String>{};
    for (final allocation in allocations) {
      final rawId = allocation['receivableId']?.toString() ?? '';
      const prefix = 'local-customer:';
      if (!rawId.startsWith(prefix)) {
        throw ArgumentError('This customer balance is not stored locally.');
      }
      final customerId = rawId.substring(prefix.length);
      final amount = (allocation['amount'] as num?)?.toDouble();
      if (customerId.isEmpty ||
          !seen.add(customerId) ||
          amount == null ||
          !amount.isFinite ||
          amount <= 0) {
        throw ArgumentError('Check the customer collection amount.');
      }
      normalized.add((customerId: customerId, amount: amount));
    }

    await transaction(() async {
      final recordIds = normalized
          .map((allocation) => '$normalizedRequest:${allocation.customerId}')
          .toList(growable: false);
      final existing = await customSelect(
        'SELECT id, customer_id, branch_id, amount, reference FROM local_cash_collections WHERE tenant_id = ? AND id IN (${List.filled(recordIds.length, '?').join(',')})',
        variables: [
          Variable.withString(tenantId),
          ...recordIds.map((id) => Variable.withString(id)),
        ],
      ).get();
      if (existing.length == recordIds.length) {
        final savedById = <String,
            ({
          String customerId,
          String branchId,
          double amount,
          String? reference
        })>{
          for (final row in existing)
            row.read<String>('id'): (
              customerId: row.read<String>('customer_id'),
              branchId: row.read<String>('branch_id'),
              amount: row.read<double>('amount'),
              reference: row.readNullable<String>('reference'),
            ),
        };
        final matches = normalized.asMap().entries.every((entry) {
          final saved = savedById[recordIds[entry.key]];
          return saved != null &&
              saved.customerId == entry.value.customerId &&
              saved.branchId == normalizedBranch &&
              saved.reference == normalizedReference &&
              (saved.amount - entry.value.amount).abs() < 0.005;
        });
        if (!matches) {
          throw StateError(
              'This collection ID was already used for a different payment. Refresh before retrying.');
        }
        return;
      }
      if (existing.isNotEmpty) {
        throw StateError(
            'This collection was only partly recorded. Refresh before retrying.');
      }

      final collectedAt = DateTime.now().toUtc().toIso8601String();
      for (var index = 0; index < normalized.length; index++) {
        final allocation = normalized[index];
        final updated = await customUpdate(
          'UPDATE customers SET balance = MAX(balance - ?, 0) WHERE id = ? AND tenant_id = ? AND balance >= ? - 0.005',
          variables: [
            Variable.withReal(allocation.amount),
            Variable.withString(allocation.customerId),
            Variable.withString(tenantId),
            Variable.withReal(allocation.amount),
          ],
        );
        if (updated != 1) {
          throw StateError(
              'A customer balance changed. Refresh and try again.');
        }
        await customStatement(
          'INSERT INTO local_cash_collections (id, tenant_id, branch_id, customer_id, amount, collected_at, payment_method, reference) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            recordIds[index],
            tenantId,
            normalizedBranch,
            allocation.customerId,
            allocation.amount,
            collectedAt,
            'CASH',
            normalizedReference,
          ],
        );
        await _applyLocalCollectionToInstallments(
          tenantId: tenantId,
          customerId: allocation.customerId,
          amount: allocation.amount,
          collectedAt: collectedAt,
        );
      }
    });
  }

  /// A general customer collection also pays scheduled dues oldest-first.
  /// Keeping the schedule in step with the balance prevents a later reminder
  /// or collection from asking for money that has already been received.
  Future<void> _applyLocalCollectionToInstallments({
    required String tenantId,
    required String customerId,
    required double amount,
    required String collectedAt,
  }) async {
    var remaining = amount;
    final installments = await customSelect(
      'SELECT id, amount - COALESCE(paid_amount, 0) AS amount_due '
      'FROM customer_installments '
      'WHERE tenant_id = ? AND customer_id = ? '
      'AND status IN (\'pending\', \'overdue\') '
      'ORDER BY due_date ASC, created_at ASC, id ASC',
      variables: [
        Variable.withString(tenantId),
        Variable.withString(customerId),
      ],
    ).get();

    for (final installment in installments) {
      if (remaining <= 0.005) break;
      final due = installment.read<double>('amount_due');
      if (!due.isFinite || due <= 0) continue;
      final applied = remaining < due ? remaining : due;
      final nextDue = due - applied;
      final id = installment.read<String>('id');
      final changed = nextDue <= 0.005
          ? await customUpdate(
              'UPDATE customer_installments SET status = \'paid\', paid_at = ?, paid_amount = amount '
              'WHERE id = ? AND tenant_id = ? AND status IN (\'pending\', \'overdue\')',
              variables: [
                Variable.withString(collectedAt),
                Variable.withString(id),
                Variable.withString(tenantId),
              ],
            )
          : await customUpdate(
              'UPDATE customer_installments SET paid_amount = COALESCE(paid_amount, 0) + ? '
              'WHERE id = ? AND tenant_id = ? AND status IN (\'pending\', \'overdue\')',
              variables: [
                Variable.withReal(applied),
                Variable.withString(id),
                Variable.withString(tenantId),
              ],
            );
      if (changed != 1) {
        throw StateError(
          'A scheduled customer payment changed. Refresh and try again.',
        );
      }
      remaining -= applied;
    }
  }

  /// Customers with a current balance and the cash collections recorded on
  /// this device. The balance remains the source of truth for what is owed.
  Future<List<Map<String, dynamic>>>
      getLocalFinanceCustomerReceivables() async {
    await createCustomersTable();
    await createCustomerInstallmentsTable();
    await _ensureLocalCashCollectionsTable();
    final tenantId = _customerTenantId;
    if (tenantId == null) return const <Map<String, dynamic>>[];
    final customers = await customSelect(
      'SELECT id, name, balance, created_at FROM customers WHERE tenant_id = ? AND (balance > 0.005 OR EXISTS (SELECT 1 FROM local_cash_collections lcc WHERE lcc.tenant_id = customers.tenant_id AND lcc.customer_id = customers.id)) ORDER BY balance DESC, name ASC',
      variables: [Variable.withString(tenantId)],
    ).get();
    final collectionRows = await customSelect(
      'SELECT customer_id, id, amount, payment_method, reference, collected_at FROM local_cash_collections WHERE tenant_id = ? ORDER BY collected_at DESC',
      variables: [Variable.withString(tenantId)],
    ).get();
    final collectionsByCustomer = <String, List<QueryRow>>{};
    for (final row in collectionRows) {
      collectionsByCustomer
          .putIfAbsent(row.read<String>('customer_id'), () => <QueryRow>[])
          .add(row);
    }
    final dueRows = await customSelect(
      "SELECT customer_id, MIN(due_date) AS due_date FROM customer_installments WHERE tenant_id = ? AND status IN ('pending', 'overdue') GROUP BY customer_id",
      variables: [Variable.withString(tenantId)],
    ).get();
    final dueByCustomer = <String, String?>{
      for (final row in dueRows)
        row.read<String>('customer_id'): row.readNullable<String>('due_date'),
    };
    final result = <Map<String, dynamic>>[];
    for (final customer in customers) {
      final customerId = customer.read<String>('id');
      final rows = collectionsByCustomer[customerId] ?? const <QueryRow>[];
      final payments = rows
          .map((row) => <String, dynamic>{
                'id': row.read<String>('id'),
                'amount': row.read<double>('amount'),
                'method': row.read<String>('payment_method'),
                'reference': row.readNullable<String>('reference'),
                'paidAt': row.read<String>('collected_at'),
                'createdAt': row.read<String>('collected_at'),
              })
          .toList(growable: false);
      final balance = customer.read<double>('balance');
      final collected = rows.fold<double>(
        0,
        (sum, row) => sum + row.read<double>('amount'),
      );
      result.add(<String, dynamic>{
        'id': customerId,
        'name': customer.read<String>('name'),
        'balance': balance,
        'originalAmount': balance + collected,
        'createdAt': customer.read<String>('created_at'),
        'dueDate': dueByCustomer[customerId],
        'payments': payments,
      });
    }
    return result;
  }

  /// Records a supplier payment against one invoice, with an optimistic
  /// balance check and request-level idempotency.
  Future<void> recordLocalSupplierInvoicePayment({
    required String invoiceId,
    required String branchId,
    required double amount,
    required String fundingSource,
    required String requestId,
    String? notes,
  }) async {
    await _createSupplierFinanceTables();
    final tenantId = _requireCustomerTenantId();
    final normalizedRequest = requestId.trim();
    if (!amount.isFinite || amount <= 0 || normalizedRequest.isEmpty) {
      throw ArgumentError('Enter a valid supplier payment.');
    }
    if (branchId.trim().isEmpty || !_activeBranchIds().contains(branchId)) {
      throw StateError('Select an active branch before recording payment.');
    }
    final normalizedSource = fundingSource.trim().toUpperCase();
    if (normalizedSource != 'CASH_TILL' &&
        normalizedSource != 'BANK_OR_MPESA') {
      throw ArgumentError('Choose a valid payment source.');
    }
    await transaction(() async {
      final duplicate = await customSelect(
        'SELECT id, invoice_id, amount, branch_id, funding_source FROM supplier_payments WHERE request_id = ? LIMIT 1',
        variables: [Variable.withString(normalizedRequest)],
      ).getSingleOrNull();
      if (duplicate != null) {
        if (duplicate.readNullable<String>('invoice_id') == invoiceId &&
            duplicate.readNullable<String>('branch_id') == branchId &&
            duplicate.read<String>('funding_source') == normalizedSource &&
            (duplicate.read<double>('amount') - amount).abs() < 0.005) {
          return;
        }
        throw StateError('This payment request ID was already used.');
      }
      final invoice = await customSelect(
        'SELECT si.supplier_id, si.total_amount, si.paid_amount FROM supplier_invoices si JOIN suppliers s ON s.id = si.supplier_id WHERE si.id = ? AND s.tenant_id = ?',
        variables: [
          Variable.withString(invoiceId),
          Variable.withString(tenantId),
        ],
      ).getSingleOrNull();
      if (invoice == null) throw StateError('Supplier invoice not found.');
      final total = invoice.read<double>('total_amount');
      final paid = invoice.read<double>('paid_amount');
      final outstanding = (total - paid).clamp(0, double.infinity).toDouble();
      if (amount > outstanding + 0.005) {
        throw StateError(
            'Payment exceeds the invoice balance. Refresh and try again.');
      }
      final newPaid = (paid + amount).clamp(0, total).toDouble();
      final newDue = (total - newPaid).clamp(0, double.infinity).toDouble();
      final now = DateTime.now().toUtc().toIso8601String();
      final updated = await customUpdate(
        'UPDATE supplier_invoices SET paid_amount = ?, due_amount = ?, status = ?, updated_at = ? WHERE id = ? AND paid_amount = ?',
        variables: [
          Variable.withReal(newPaid),
          Variable.withReal(newDue),
          Variable.withString(newDue <= 0.005 ? 'paid' : 'partial'),
          Variable.withString(now),
          Variable.withString(invoiceId),
          Variable.withReal(paid),
        ],
      );
      if (updated != 1) {
        throw StateError('Invoice balance changed. Refresh and try again.');
      }
      final cleanNotes = notes?.trim();
      await customStatement(
        'INSERT INTO supplier_payments (supplier_id, branch_id, amount, notes, payment_date, created_at, invoice_id, request_id, funding_source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          invoice.read<String>('supplier_id'),
          branchId,
          amount,
          cleanNotes == null || cleanNotes.isEmpty ? null : cleanNotes,
          now,
          now,
          invoiceId,
          normalizedRequest,
          normalizedSource,
        ],
      );
    });
  }

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
            AND date(si3.due_date) < date('now', 'localtime')) as overdue_count
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
    String? invoiceId,
    String? branchId,
    String fundingSource = 'CASH_TILL',
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
      'INSERT INTO supplier_payments (supplier_id, branch_id, amount, notes, payment_date, created_at, invoice_id, funding_source) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [supplierId, branchId, amount, notes, now, now, invoiceId, fundingSource],
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
    final targetBranchId = branchId ?? _storage.getBranchId() ?? 'branch-main';
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
          invoiceId: invoiceRecordId,
          branchId: targetBranchId,
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

  static const _portableMetadataTable = 'counterbase_transfer_metadata';
  static const _portableAssetsTable = 'counterbase_transfer_assets';
  static const _portableFormat = 'counterbase-mobile-workspace';
  static const _maxPortableAssetBytes = 128 * 1024 * 1024;
  static const _maxPortableAssetFileBytes = 16 * 1024 * 1024;

  /// Shop images referenced by local catalog, profile, and supplier-invoice
  /// records. These paths are device-specific and are rebased on restore.
  Future<List<String>> getPortableImageReferences() async {
    await _createSupplierFinanceTables();
    final rows = await customSelect('''
      SELECT image_url FROM products WHERE image_url IS NOT NULL AND image_url != ''
      UNION
      SELECT image_url FROM categories WHERE image_url IS NOT NULL AND image_url != ''
      UNION
      SELECT receipt_image_path FROM supplier_invoices
        WHERE receipt_image_path IS NOT NULL AND receipt_image_path != ''
    ''').get();
    return rows
        .map((row) => row.read<String>('image_url'))
        .toSet()
        .toList(growable: false);
  }

  /// Writes a consistent, password-encrypted snapshot of the full local
  /// database. SQLCipher copies the live connection into a separately keyed
  /// attached database, so the export includes committed WAL data without
  /// copying the device's private database key.
  Future<void> createPortableBackup({
    required String path,
    required String passphrase,
    required Map<String, dynamic> metadata,
    Map<String, Uint8List?> transferImages = const <String, Uint8List?>{},
  }) async {
    _validatePortablePassphrase(passphrase);
    await _ensurePortableRestoreSchema();
    final attach = _portableAttachSql(path, passphrase);
    var attached = false;
    try {
      await customStatement(attach);
      attached = true;
      await customSelect("SELECT sqlcipher_export('portable')").get();
      await customStatement('PRAGMA portable.user_version = $schemaVersion');
      await customStatement('''
        CREATE TABLE portable.$_portableMetadataTable (
          payload TEXT NOT NULL
        )
      ''');
      final payload = <String, dynamic>{
        ...metadata,
        'format': _portableFormat,
        'formatVersion': 2,
        'schemaVersion': schemaVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      await customStatement(
        'INSERT INTO portable.$_portableMetadataTable (payload) VALUES (${_portableSqlString(jsonEncode(payload))})',
      );
      await customStatement('''
        CREATE TABLE portable.$_portableAssetsTable (
          original_path TEXT PRIMARY KEY NOT NULL,
          contents BLOB
        )
      ''');
      for (final entry in transferImages.entries) {
        await customStatement(
          'INSERT INTO portable.$_portableAssetsTable (original_path, contents) VALUES (?, ?)',
          [
            Variable.withString(entry.key),
            entry.value == null
                ? const Variable<Uint8List>(null)
                : Variable.withBlob(entry.value!),
          ],
        );
      }
      await _validatePortableDatabase();
    } catch (_) {
      // The SQLCipher ATTACH statement contains the backup passphrase. Never
      // include its native exception text in logs, where SQL may be echoed.
      debugPrint('[DB] Portable backup export failed.');
      rethrow;
    } finally {
      if (attached) {
        await customStatement('DETACH DATABASE portable');
      }
    }
  }

  /// Opens and validates a transfer backup without changing the live shop.
  /// The returned profile contains only owner/shop identity fields; callers
  /// must show it to the owner before replacing local data.
  Future<Map<String, dynamic>> inspectPortableBackup({
    required String path,
    required String passphrase,
  }) async {
    _validatePortablePassphrase(passphrase);
    final attach = _portableAttachSql(path, passphrase);
    var attached = false;
    try {
      await customStatement(attach);
      attached = true;
      return await _readPortablePreview();
    } catch (error) {
      debugPrint('[DB] Portable backup inspection failed.');
      if (error is FormatException) rethrow;
      throw const FormatException(
        'Counterbase could not unlock that backup. Check the password and file.',
      );
    } finally {
      if (attached) {
        await customStatement('DETACH DATABASE portable');
      }
    }
  }

  /// Returns image assets from a validated mobile backup. A null value means
  /// the source catalog referenced that local image but its file was already
  /// missing when the backup was created.
  Future<Map<String, Uint8List?>> readPortableImageAssets({
    required String path,
    required String passphrase,
  }) async {
    _validatePortablePassphrase(passphrase);
    final attach = _portableAttachSql(path, passphrase);
    var attached = false;
    try {
      await customStatement(attach);
      attached = true;
      await _readPortablePreview();
      final table = await customSelect(
        'SELECT 1 FROM portable.sqlite_master WHERE type = ? AND name = ? LIMIT 1',
        variables: [
          const Variable<String>('table'),
          Variable.withString(_portableAssetsTable),
        ],
      ).getSingleOrNull();
      if (table == null) return const <String, Uint8List?>{};
      final rows = await customSelect(
        'SELECT original_path, contents FROM portable.$_portableAssetsTable',
      ).get();
      return {
        for (final row in rows)
          row.read<String>('original_path'): row.readNullable<Uint8List>(
            'contents',
          ),
      };
    } catch (_) {
      debugPrint('[DB] Portable image extraction failed.');
      rethrow;
    } finally {
      if (attached) await customStatement('DETACH DATABASE portable');
    }
  }

  /// Replaces this install's local business rows from a verified transfer
  /// backup in one SQLite transaction. Secure device credentials are not
  /// copied; the recipient keeps its own PIN and Gateway key.
  Future<Map<String, dynamic>> restorePortableBackup({
    required String path,
    required String passphrase,
    required StorageService storage,
    Map<String, String?> assetPathRemap = const <String, String?>{},
    void Function()? validateOwner,
  }) async {
    _validatePortablePassphrase(passphrase);
    final preview = await inspectPortableBackup(
      path: path,
      passphrase: passphrase,
    );
    final payload = _remapPortableAssetPaths(
      preview['payload'] as Map<String, dynamic>,
      assetPathRemap,
    );
    final workspace = Map<String, dynamic>.from(
      payload['workspace'] as Map,
    );
    final user = Map<String, dynamic>.from(payload['user'] as Map);
    final tenant = Map<String, dynamic>.from(payload['tenant'] as Map);
    final branch = Map<String, dynamic>.from(payload['branch'] as Map);
    final tenantId = payload['tenantId'].toString();
    final tenantSlug = payload['tenantSlug'].toString();
    final branchId = payload['branchId'].toString();
    if (tenantId.isEmpty ||
        tenantSlug.isEmpty ||
        branchId.isEmpty ||
        user['id']?.toString().isEmpty != false ||
        user['authMode'] != 'local' ||
        user['tenantId']?.toString() != tenantId ||
        user['tenantSlug']?.toString() != tenantSlug ||
        user['branchId']?.toString() != branchId ||
        tenant['id']?.toString() != tenantId ||
        branch['id']?.toString() != branchId ||
        (workspace['tenant'] is! Map) ||
        (workspace['branch'] is! Map) ||
        (workspace['user'] is! Map) ||
        (workspace['tenant'] as Map)['id']?.toString() != tenantId ||
        (workspace['branch'] as Map)['id']?.toString() != branchId ||
        (workspace['user'] as Map)['id']?.toString() !=
            user['id']?.toString()) {
      throw const FormatException(
        'This backup is missing the local shop profile needed for restore.',
      );
    }

    final previousWorkspace = storage.getLocalWorkspace();
    final previousUser = storage.getUser();
    final previousTenantId = storage.getTenantId();
    final previousTenantSlug = storage.getTenantSlug();
    final previousBranchId = storage.getBranchId();
    if (previousWorkspace == null ||
        previousUser == null ||
        previousTenantId == null ||
        previousTenantSlug == null ||
        previousBranchId == null) {
      throw StateError(
        'Set up or unlock a local workspace before restoring a transfer backup.',
      );
    }
    final previousTargetHeldSales = await storage.getSecureHeldSalesSnapshot(
      tenantId: tenantId,
      branchId: branchId,
    );

    final attach = _portableAttachSql(path, passphrase);
    var attached = false;
    var foreignKeysDisabled = false;
    try {
      await customStatement(attach);
      attached = true;
      final sourceTables = await _portableTableNames('portable');
      await _ensurePortableRestoreSchema();
      final liveTables = await _portableTableNames('main');
      final sourceTableSet = sourceTables.toSet();
      final liveTableSet = liveTables.toSet();
      final missingFromBackup = liveTableSet.difference(sourceTableSet);
      final unknownInBackup = sourceTableSet.difference(liveTableSet);
      // Backups created before private AI notes existed remain restorable;
      // the new table stays empty. Unknown/newer tables still fail closed.
      if (unknownInBackup.isNotEmpty ||
          !const {'local_ai_memories'}.containsAll(missingFromBackup)) {
        throw const FormatException(
          'This backup was made by a different Counterbase database version. Update both apps and try again.',
        );
      }
      for (final table in sourceTables) {
        final liveColumns = await _portableColumnNames('main', table);
        final backupColumns = await _portableColumnNames('portable', table);
        if (liveColumns.length != backupColumns.length ||
            !liveColumns.toSet().containsAll(backupColumns)) {
          throw const FormatException(
            'This backup does not match the database version on this device.',
          );
        }
      }

      validateOwner?.call();
      await customStatement('PRAGMA foreign_keys = OFF');
      foreignKeysDisabled = true;
      await transaction(() async {
        validateOwner?.call();
        for (final table in liveTables.reversed) {
          await customStatement(
              'DELETE FROM main.${_portableIdentifier(table)}');
        }
        final hasSequence = liveTables.contains('sqlite_sequence');
        if (hasSequence) {
          await customStatement('DELETE FROM main.sqlite_sequence');
        }
        for (final table in sourceTables) {
          await customStatement('''
            INSERT INTO main.${_portableIdentifier(table)}
            SELECT * FROM portable.${_portableIdentifier(table)}
          ''');
        }
        if (assetPathRemap.isNotEmpty) {
          const assetColumns = <String, List<String>>{
            'products': ['image_url'],
            'categories': ['image_url'],
            'supplier_invoices': ['receipt_image_path'],
          };
          for (final entry in assetColumns.entries) {
            if (!sourceTableSet.contains(entry.key)) continue;
            for (final column in entry.value) {
              for (final pathEntry in assetPathRemap.entries) {
                final identifier = _portableIdentifier(column);
                await customStatement(
                  'UPDATE main.${_portableIdentifier(entry.key)} '
                  'SET $identifier = ? WHERE $identifier = ?',
                  [
                    pathEntry.value == null
                        ? const Variable<String>(null)
                        : Variable.withString(pathEntry.value!),
                    Variable.withString(pathEntry.key),
                  ],
                );
              }
            }
          }
        }
        await _restorePortableSequences();
        await _validatePortableDatabase(schema: 'main');
        final foreignKeyErrors = await customSelect(
          'PRAGMA main.foreign_key_check',
        ).get();
        if (foreignKeyErrors.isNotEmpty) {
          throw StateError(
            'This backup has related records that do not match.',
          );
        }

        validateOwner?.call();
        await storage.saveLocalWorkspace(workspace);
        await storage.saveUser(user);
        await storage.saveTenantId(tenantId);
        await storage.saveTenantSlug(tenantSlug);
        await storage.saveBranchId(branchId);
        await storage.clearSecureHeldSalesSnapshot(
          tenantId: tenantId,
          branchId: branchId,
        );
        final heldSales = payload['heldSales']?.toString();
        if (heldSales != null && heldSales.isNotEmpty) {
          await storage.saveSecureHeldSalesSnapshot(
            tenantId: tenantId,
            branchId: branchId,
            snapshot: heldSales,
          );
        }
      });
    } catch (_) {
      // Preferences and SQLite cannot share a transaction. Restore the prior
      // identity if any preference write failed; the database transaction
      // rolls back independently.
      try {
        await storage.saveLocalWorkspace(previousWorkspace);
        await storage.saveUser(previousUser);
        await storage.saveTenantId(previousTenantId);
        await storage.saveTenantSlug(previousTenantSlug);
        await storage.saveBranchId(previousBranchId);
        if (previousTargetHeldSales == null) {
          await storage.clearSecureHeldSalesSnapshot(
            tenantId: tenantId,
            branchId: branchId,
          );
        } else {
          await storage.saveSecureHeldSalesSnapshot(
            tenantId: tenantId,
            branchId: branchId,
            snapshot: previousTargetHeldSales,
          );
        }
      } catch (_) {
        debugPrint('[DB] Portable profile rollback failed.');
      }
      debugPrint('[DB] Portable restore failed.');
      rethrow;
    } finally {
      if (foreignKeysDisabled) {
        await customStatement('PRAGMA foreign_keys = ON');
      }
      if (attached) {
        await customStatement('DETACH DATABASE portable');
      }
    }
    return preview;
  }

  Future<Map<String, dynamic>> _readPortablePreview() async {
    final metadataRows = await customSelect(
      'SELECT payload FROM portable.$_portableMetadataTable LIMIT 2',
    ).get();
    if (metadataRows.length != 1) {
      throw const FormatException('This is not a Counterbase transfer backup.');
    }
    final decoded = jsonDecode(metadataRows.single.read<String>('payload'));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != _portableFormat ||
        !const {1, 2}.contains(decoded['formatVersion']) ||
        decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException(
        'This backup is for a different Counterbase database version.',
      );
    }
    final tenantId = decoded['tenantId']?.toString() ?? '';
    final tenantSlug = decoded['tenantSlug']?.toString() ?? '';
    final branchId = decoded['branchId']?.toString() ?? '';
    final tenant = decoded['tenant'];
    final branch = decoded['branch'];
    final user = decoded['user'];
    final workspace = decoded['workspace'];
    if (tenantId.isEmpty ||
        tenantSlug.isEmpty ||
        branchId.isEmpty ||
        tenant is! Map ||
        branch is! Map ||
        user is! Map ||
        workspace is! Map ||
        workspace['tenant'] is! Map ||
        workspace['branch'] is! Map ||
        workspace['user'] is! Map ||
        tenant['id']?.toString() != tenantId ||
        branch['id']?.toString() != branchId ||
        user['authMode'] != 'local' ||
        user['tenantId']?.toString() != tenantId ||
        user['tenantSlug']?.toString() != tenantSlug ||
        user['branchId']?.toString() != branchId ||
        (workspace['tenant'] as Map)['id']?.toString() != tenantId ||
        (workspace['branch'] as Map)['id']?.toString() != branchId ||
        (workspace['user'] as Map)['id']?.toString() !=
            user['id']?.toString()) {
      throw const FormatException(
        'This backup is missing a complete local shop profile.',
      );
    }
    await _validatePortableDatabase(schema: 'portable');
    final foreignKeyErrors = await customSelect(
      'PRAGMA portable.foreign_key_check',
    ).get();
    if (foreignKeyErrors.isNotEmpty) {
      throw const FormatException(
        'This backup contains damaged or incomplete related records.',
      );
    }
    final tables = await _portableTableNames('portable');
    final formatVersion = decoded['formatVersion'] as int;
    var imageCount = 0;
    if (formatVersion >= 2) {
      if (await _portableTableNamesIncludingAssets('portable') == false) {
        throw const FormatException(
          'This backup is missing its local image manifest.',
        );
      }
      final imageRows = await customSelect('''
        SELECT COUNT(*) AS total,
          COALESCE(SUM(length(contents)), 0) AS bytes,
          COALESCE(MAX(length(contents)), 0) AS largest
        FROM portable.$_portableAssetsTable WHERE contents IS NOT NULL
      ''').get();
      final imageStats = imageRows.single;
      imageCount = imageStats.read<int>('total');
      if (imageStats.read<int>('bytes') > _maxPortableAssetBytes ||
          imageStats.read<int>('largest') > _maxPortableAssetFileBytes) {
        throw const FormatException(
          'This backup contains photos that exceed the supported transfer size.',
        );
      }
    }
    final counts = <String, int>{};
    for (final table in const ['products', 'customers', 'sales', 'branches']) {
      if (!tables.contains(table)) {
        counts[table] = 0;
        continue;
      }
      final rows = await customSelect(
        'SELECT COUNT(*) AS total FROM portable.${_portableIdentifier(table)}',
      ).get();
      counts[table] = rows.single.read<int>('total');
    }
    final createdAt = DateTime.tryParse(decoded['createdAt']?.toString() ?? '');
    if (createdAt == null) {
      throw const FormatException('This backup has an invalid creation date.');
    }
    return {
      'payload': decoded,
      'tenantName': tenant['name']?.toString() ?? 'Your shop',
      'ownerName': user['name']?.toString() ?? '',
      'createdAt': createdAt,
      'counts': counts,
      'imageCount': imageCount,
      'totalCount': counts.values.fold<int>(0, (sum, value) => sum + value),
    };
  }

  Future<void> _validatePortableDatabase({String schema = 'portable'}) async {
    final rows = await customSelect('PRAGMA $schema.integrity_check').get();
    if (rows.length != 1 || rows.single.data.values.first != 'ok') {
      throw const FormatException(
        'The encrypted workspace backup did not pass its integrity check.',
      );
    }
  }

  Future<List<String>> _portableTableNames(String schema) async {
    final rows = await customSelect('''
      SELECT name FROM $schema.sqlite_master
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        AND name != '$_portableMetadataTable'
        AND name != '$_portableAssetsTable'
      ORDER BY name
    ''').get();
    return rows.map((row) => row.read<String>('name')).toList();
  }

  Future<bool> _portableTableNamesIncludingAssets(String schema) async {
    final rows = await customSelect('''
      SELECT 1 FROM $schema.sqlite_master
      WHERE type = 'table' AND name = '$_portableAssetsTable'
      LIMIT 1
    ''').get();
    return rows.isNotEmpty;
  }

  Future<List<String>> _portableColumnNames(String schema, String table) async {
    final rows = await customSelect(
      'PRAGMA $schema.table_info(${_portableIdentifier(table)})',
    ).get();
    return rows.map((row) => row.read<String>('name')).toList();
  }

  Future<void> _restorePortableSequences() async {
    final hasSequence = await customSelect('''
      SELECT 1 FROM portable.sqlite_master
      WHERE type = 'table' AND name = 'sqlite_sequence'
      LIMIT 1
    ''').getSingleOrNull();
    if (hasSequence == null) return;
    await customStatement('DELETE FROM main.sqlite_sequence');
    await customStatement('''
      INSERT INTO main.sqlite_sequence(name, seq)
      SELECT name, seq FROM portable.sqlite_sequence
    ''');
  }

  /// A few long-standing local tables are created lazily when their feature
  /// is first used rather than by Drift migrations. Create the current schema
  /// before comparing a transfer backup so restoring into a fresh local shop
  /// still preserves receipts, closes, collections, supplier history, private
  /// AI notes, and prior archive-import metadata.
  Future<void> _ensurePortableRestoreSchema() async {
    await _createSupplierFinanceTables();
    await _ensureLocalAiMemoriesTable();
    await _ensureLocalStockReceiptsTable();
    await _ensureLocalDailyClosesTable();
    await _ensureLocalCashCollectionsTable();
    await _ensureLocalCashRefundsTable();
    await createBranchesTable();
    await createCustomersTable();
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_import_archives (
        archive_id TEXT PRIMARY KEY NOT NULL,
        tenant_id TEXT NOT NULL,
        tenant_name TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        payload_json TEXT NOT NULL
      )
    ''');
  }

  String _portableAttachSql(String path, String passphrase) =>
      'ATTACH DATABASE ${_portableSqlString(path)} AS portable KEY ${_portableSqlString(passphrase)}';

  String _portableSqlString(String value) => "'${value.replaceAll("'", "''")}'";

  Map<String, dynamic> _remapPortableAssetPaths(
    Map<String, dynamic> value,
    Map<String, String?> remap,
  ) =>
      _remapPortableAssetValue(value, remap) as Map<String, dynamic>;

  Object? _remapPortableAssetValue(
    Object? value,
    Map<String, String?> remap,
  ) {
    if (value is String && remap.containsKey(value)) return remap[value];
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _remapPortableAssetValue(entry.value, remap),
      };
    }
    if (value is Iterable) {
      return value
          .map((item) => _remapPortableAssetValue(item, remap))
          .toList(growable: false);
    }
    return value;
  }

  String _portableIdentifier(String value) =>
      '"${value.replaceAll('"', '""')}"';

  void _validatePortablePassphrase(String passphrase) {
    if (passphrase.length < 12 ||
        passphrase.length > 1024 ||
        passphrase.contains('\u0000')) {
      throw const FormatException(
        'Use a backup password between 12 and 1024 characters.',
      );
    }
  }
}
