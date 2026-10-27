import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/utils/business_layout_search.dart';

// Products, POS, and Inventory can mount together during navigation or startup.
// Share one refresh per shop/branch/API so they don't all download and replace
// the same local catalog at once.
final Map<String, Future<void>> _catalogSyncsInFlight = {};

// State providers for search/filter
final selectedCategoryProvider =
    StateProvider.autoDispose<String?>((ref) => null);
final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

Future<List<Map<String, dynamic>>> _productsToPosMaps(
  AppDatabase database,
  Iterable<Product> products,
) async {
  final activeProducts = products.where((product) => product.isActive).toList();
  if (activeProducts.isEmpty) return [];

  final ids = activeProducts.map((product) => product.id).toList();
  final branchId = getIt<StorageService>().getBranchId();
  final metadata = await Future.wait<Object>([
    database.getPricingTiersForProducts(ids),
    branchId == null
        ? Future.value(<String, LocalStockData>{})
        : database.getStockForProducts(ids, branchId),
  ]);
  final tiersByProduct = metadata[0] as Map<String, List<ProductPricingTier>>;
  final stockByProduct = metadata[1] as Map<String, LocalStockData>;

  return activeProducts.map((product) {
    final tiers = tiersByProduct[product.id] ?? const <ProductPricingTier>[];
    final stock = stockByProduct[product.id];
    return {
      'id': product.id,
      'sku': product.sku,
      'name': product.name,
      'description': product.description,
      'metadata': _decodeProductMetadata(product.metadata),
      'categoryId': product.categoryId,
      'price': product.price,
      'costPrice': product.costPrice,
      'unit': product.unit,
      'pricingTiers': tiers
          .map((tier) => {
                'unit': tier.unit,
                'quantityPerUnit': tier.quantityPerUnit,
                'price': tier.price,
                'sortOrder': tier.sortOrder,
              })
          .toList(),
      'imageUrl': product.imageUrl,
      'isActive': product.isActive,
      'trackInventory': product.trackInventory,
      'allowFractions': product.allowFractions,
      'stock': stock?.quantity ?? 0,
      'minStock': product.minStock,
    };
  }).toList();
}

/// Parse timestamp from various formats (ISO string or milliseconds since epoch)
DateTime _parseTimestamp(dynamic value) {
  if (value == null) return DateTime.now();

  // If it's already a DateTime, return it
  if (value is DateTime) return value;

  // If it's a number (Unix timestamp in milliseconds)
  if (value is int || value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }

  // If it's a string
  if (value is String) {
    // Try to parse as ISO string first
    try {
      return DateTime.parse(value);
    } catch (_) {
      // If that fails, try parsing as milliseconds since epoch
      try {
        // Remove any non-numeric characters before parsing
        final cleanedValue = value.replaceAll(RegExp(r'[^0-9]'), '');
        final milliseconds = int.tryParse(cleanedValue);
        if (milliseconds != null) {
          return DateTime.fromMillisecondsSinceEpoch(milliseconds);
        }
        return DateTime.now();
      } catch (_) {
        return DateTime.now();
      }
    }
  }

  return DateTime.now();
}

List<Map<String, dynamic>> _flattenCategories(List<dynamic> categories) {
  final flattened = <Map<String, dynamic>>[];

  void walk(List<dynamic> nodes) {
    for (final node in nodes) {
      if (node is! Map) {
        throw const FormatException(
          'The category catalog contains an invalid item.',
        );
      }
      final category = Map<String, dynamic>.from(node);
      final id = category['id']?.toString().trim();
      final name = category['name']?.toString().trim();
      if (id == null || id.isEmpty || name == null || name.isEmpty) {
        throw const FormatException(
          'The category catalog contains an incomplete item.',
        );
      }
      final children = category.remove('children');
      flattened.add(category);
      if (children is List) {
        walk(children);
      } else if (children != null) {
        throw const FormatException(
          'The category catalog hierarchy is invalid.',
        );
      }
    }
  }

  walk(categories);
  return flattened;
}

/// Parses a complete API page before caching it. Silently dropping a malformed
/// row is unsafe because the final refresh replaces the full local catalog;
/// an incomplete payload could otherwise make valid saved products disappear.
List<Map<String, dynamic>> _validatedProductMaps(List<dynamic> items) {
  final products = <Map<String, dynamic>>[];
  for (final item in items) {
    if (item is! Map) {
      throw const FormatException(
        'The product catalog contains an invalid item.',
      );
    }

    try {
      final product = Map<String, dynamic>.from(item);
      if (_productToCompanion(product) == null) {
        throw const FormatException(
          'The product catalog contains an incomplete item.',
        );
      }
      products.add(product);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'The product catalog contains an invalid item.',
      );
    }
  }
  return products;
}

CategoriesCompanion? _categoryToCompanion(Map<String, dynamic> category) {
  final id = category['id']?.toString();
  final name = category['name']?.toString();
  if (id == null || name == null || id.isEmpty || name.isEmpty) {
    return null;
  }

  return CategoriesCompanion.insert(
    id: id,
    name: name,
    description: Value(category['description']?.toString()),
    parentId: Value(category['parentId']?.toString()),
    imageUrl: Value((category['imageUrl'] ?? category['image'])?.toString()),
    sortOrder: Value((category['sortOrder'] as num?)?.toInt() ?? 0),
    isActive: Value(category['isActive'] as bool? ?? true),
    createdAt: _parseTimestamp(category['createdAt']),
    updatedAt: _parseTimestamp(category['updatedAt']),
  );
}

/// Extracts a product's real pricing tiers (any number) from the API
/// response into local companions ready to insert. `sortOrder` defaults to
/// list position when the server didn't send one.
List<ProductPricingTiersCompanion> _pricingTiersToCompanions(
  Map<String, dynamic> product,
) {
  final productId = product['id']?.toString();
  final rawTiers = product['pricingTiers'];
  if (productId == null || rawTiers is! List) return [];

  final companions = <ProductPricingTiersCompanion>[];
  for (var i = 0; i < rawTiers.length; i++) {
    final tier = rawTiers[i];
    if (tier is! Map) continue;
    final unit = tier['unit']?.toString();
    final quantityPerUnit = tier['quantityPerUnit'];
    final price = tier['price'];
    if (unit == null || quantityPerUnit == null || price == null) continue;

    companions.add(
      ProductPricingTiersCompanion.insert(
        id: tier['id']?.toString() ?? '$productId-tier-$i',
        productId: productId,
        unit: unit,
        quantityPerUnit: (quantityPerUnit as num).toDouble(),
        price: (price as num).toDouble(),
        sortOrder: Value((tier['sortOrder'] as num?)?.toInt() ?? i + 1),
      ),
    );
  }
  return companions;
}

ProductsCompanion? _productToCompanion(Map<String, dynamic> product) {
  final id = product['id']?.toString();
  final name = product['name']?.toString();
  final sku = product['sku']?.toString();
  // Products are allowed to have no category. Keep them in the local cache
  // with an empty sentinel so POS and the catalogue don't silently drop them.
  final categoryId = product['categoryId']?.toString().trim() ?? '';
  final priceValue =
      product['price'] ?? product['currentPrice'] ?? product['basePrice'];

  if (id == null || name == null || sku == null || priceValue == null) {
    return null;
  }

  return ProductsCompanion.insert(
    id: id,
    sku: sku,
    name: name,
    description: Value(product['description']?.toString()),
    metadata: Value(_encodeProductMetadata(product['metadata'])),
    categoryId: categoryId,
    price: (priceValue as num).toDouble(),
    costPrice: Value(
      product['costPrice'] != null
          ? (product['costPrice'] as num).toDouble()
          : null,
    ),
    unit: Value(product['unit']?.toString() ?? 'piece'),
    imageUrl: Value(product['imageUrl']?.toString()),
    isActive: Value(product['isActive'] as bool? ?? true),
    trackInventory: Value(product['trackInventory'] as bool? ?? true),
    allowFractions: Value(product['allowFractions'] as bool? ?? false),
    minStock: Value((product['minStock'] as num?)?.toInt() ?? 0),
    createdAt: _parseTimestamp(product['createdAt']),
    updatedAt: _parseTimestamp(product['updatedAt']),
  );
}

String _encodeProductMetadata(Object? value) {
  if (value is Map) {
    return jsonEncode(Map<String, dynamic>.from(value));
  }
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return jsonEncode(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Older API responses may not contain JSON metadata.
    }
  }
  return '{}';
}

Map<String, dynamic> _decodeProductMetadata(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    // Malformed old cache rows are treated as having no extra details.
  }
  return const {};
}

/// The catalog endpoint embeds each product's current stock for the
/// caller's branch (`currentStock`), but that number previously never made
/// it past this function — it was read off the response and discarded,
/// since `_productToCompanion`/`replaceProducts` only touch the `Products`
/// table. The actual on-device stock number (checked by the POS screen
/// before allowing a sale) lives in the separate `LocalStock` table, which
/// is otherwise only written by sync-pull `STOCK_ADJUSTED` events — a path
/// nothing in the app currently triggers. So a stock change made anywhere
/// else (another device, a direct DB correction) would fetch correctly
/// here but never reach `LocalStock`, leaving the POS screen stuck showing
/// stale/zero stock. Writing it here, on every catalog refresh, closes
/// that gap without needing the unused pull-sync trigger to exist.
LocalStockCompanion? _stockToCompanion(
  Map<String, dynamic> product,
  String branchId,
) {
  final productId = product['id']?.toString();
  final currentStock = product['currentStock'];
  if (productId == null || currentStock == null) return null;

  return LocalStockCompanion.insert(
    id: 'stock-$branchId-$productId',
    productId: productId,
    branchId: branchId,
    quantity: (currentStock as num).toDouble(),
    updatedAt: DateTime.now(),
  );
}

Future<void> syncCatalogCacheFromApi(
    {void Function()? onProductsCached}) async {
  final connectivity = getIt<ConnectivityService>();
  // Connectivity is initialized before the app is shown. Reuse a confirmed
  // online state immediately; only repeat the platform check when the cached
  // state says offline (which can happen after a transient startup timeout).
  if (!connectivity.isOnline) {
    final status = await connectivity.checkCurrentStatus();
    if (status != ConnectionStatus.online) {
      debugPrint('[CatalogSync] Skipped: connectivity check reported offline');
      throw StateError(
          'The product catalog has not been checked while offline.');
    }
  }

  final apiClient = getIt<ApiClient>();
  final database = getIt<AppDatabase>();
  final storageService = getIt<StorageService>();
  final tenantId = storageService.getTenantId();
  final branchId = storageService.getBranchId();
  final apiBaseUrl = apiClient.baseUrl;
  // These values are local identifiers, not credentials. NUL separators avoid
  // accidental key collisions if an identifier contains punctuation.
  final scopeKey = '${tenantId ?? ''}\u0000${branchId ?? ''}\u0000$apiBaseUrl';

  final existingSync = _catalogSyncsInFlight[scopeKey];
  if (existingSync != null) {
    await existingSync;
    onProductsCached?.call();
    return;
  }

  final sync = _performCatalogSync(
    apiClient: apiClient,
    database: database,
    storageService: storageService,
    tenantId: tenantId,
    branchId: branchId,
    apiBaseUrl: apiBaseUrl,
    onProductsCached: onProductsCached,
  );
  _catalogSyncsInFlight[scopeKey] = sync;
  try {
    await sync;
  } finally {
    if (identical(_catalogSyncsInFlight[scopeKey], sync)) {
      _catalogSyncsInFlight.remove(scopeKey);
    }
  }
}

Future<void> _performCatalogSync({
  required ApiClient apiClient,
  required AppDatabase database,
  required StorageService storageService,
  required String? tenantId,
  required String? branchId,
  required String apiBaseUrl,
  void Function()? onProductsCached,
}) async {
  bool isSameCatalogScope() =>
      storageService.getTenantId() == tenantId &&
      storageService.getBranchId() == branchId &&
      apiClient.baseUrl == apiBaseUrl;

  try {
    debugPrint('[CatalogSync] Fetching categories and products...');
    await syncCatalogSources(
      syncCategories: () async {
        final categoriesResponse = await apiClient.getCategories();
        final flatCategories = _flattenCategories(categoriesResponse);
        final categoryItems = flatCategories
            .map(_categoryToCompanion)
            .whereType<CategoriesCompanion>()
            .toList();
        if (categoryItems.length != flatCategories.length) {
          throw const FormatException(
            'The category catalog contains an incomplete item.',
          );
        }

        // Logout or switching shops while requests are in flight must not
        // repopulate the shared local tables with the previous shop's data.
        if (!isSameCatalogScope()) {
          debugPrint(
              '[CatalogSync] Skipped category cache write: shop changed');
          return;
        }
        await database.replaceCategories(categoryItems);
        debugPrint('[CatalogSync] Stored ${categoryItems.length} categories');
      },
      syncProducts: () async {
        var publishedInitialCatalogPage = false;
        var cachedPagesSincePublish = 0;
        final productsResponse = await apiClient.getAllProducts(
          branchId: branchId,
          onPageFetched: (page) async {
            final pageMaps = _validatedProductMaps(page);
            final pageProducts = pageMaps
                .map(_productToCompanion)
                .whereType<ProductsCompanion>()
                .toList(growable: false);
            final pageProductIds =
                pageProducts.map((product) => product.id.value).toSet();
            if (pageProducts.isEmpty || !isSameCatalogScope()) return;

            final pageTiers = pageMaps
                .expand(_pricingTiersToCompanions)
                .where((tier) => pageProductIds.contains(tier.productId.value))
                .toList(growable: false);
            final pageStock = branchId == null
                ? const <LocalStockCompanion>[]
                : pageMaps
                    .where((product) =>
                        pageProductIds.contains(product['id']?.toString()))
                    .map((product) => _stockToCompanion(product, branchId))
                    .whereType<LocalStockCompanion>()
                    .toList(growable: false);

            await database.cacheCatalogPage(
              items: pageProducts,
              tierItems: pageTiers,
              stockItems: pageStock,
              branchId: branchId,
            );
            cachedPagesSincePublish++;
            // Publish the first page immediately, then expose further pages
            // in small batches. Re-querying the entire product list after
            // every page repeats tier and stock lookups while the sync is
            // still downloading; waiting until the full catalog finishes
            // hides newly cached products for large shops.
            if ((!publishedInitialCatalogPage ||
                    cachedPagesSincePublish >= 4) &&
                isSameCatalogScope()) {
              publishedInitialCatalogPage = true;
              cachedPagesSincePublish = 0;
              onProductsCached?.call();
            }
          },
        );
        final productMaps = _validatedProductMaps(productsResponse);

        final productItems = productMaps
            .map((product) => _productToCompanion(product)!)
            .toList(growable: false);
        if (!isSameCatalogScope()) {
          debugPrint('[CatalogSync] Skipped product cache write: shop changed');
          return;
        }
        // Publish product rows to the local stream immediately. Category
        // refresh is independent and must not delay the catalog screen.
        await database.replaceProducts(productItems);
        debugPrint('[CatalogSync] Stored ${productItems.length} products');

        final tierItems =
            productMaps.expand(_pricingTiersToCompanions).toList();
        if (!isSameCatalogScope()) {
          debugPrint('[CatalogSync] Skipped pricing cache write: shop changed');
          return;
        }
        await database.replaceAllPricingTiers(tierItems);

        if (branchId != null) {
          final stockItems = productMaps
              .map((p) => _stockToCompanion(p, branchId))
              .whereType<LocalStockCompanion>()
              .toList();
          if (stockItems.isNotEmpty && isSameCatalogScope()) {
            await database.reconcileLocalStockWithPendingSales(
              branchId: branchId,
              serverStock: stockItems,
            );
          }
        }
      },
    );
    debugPrint('[CatalogSync] Sync complete');
  } catch (e, st) {
    debugPrint('[CatalogSync] FAILED: $e');
    debugPrint('[CatalogSync] Stack: $st');
    rethrow;
  }
}

class _CatalogSyncTaskResult {
  const _CatalogSyncTaskResult.success()
      : error = null,
        stackTrace = null;

  const _CatalogSyncTaskResult.failure(this.error, this.stackTrace);

  final Object? error;
  final StackTrace? stackTrace;
}

Future<_CatalogSyncTaskResult> _captureCatalogSyncTask(
  Future<void> Function() task,
) async {
  try {
    await task();
    return const _CatalogSyncTaskResult.success();
  } catch (error, stackTrace) {
    return _CatalogSyncTaskResult.failure(error, stackTrace);
  }
}

/// Refreshes independent catalog sources concurrently. Product data is the
/// primary screen content, so category failures retain the previous category
/// cache but do not hold fresh products back. Product failures still reach the
/// screen's normal retry state.
@visibleForTesting
Future<void> syncCatalogSources({
  required Future<void> Function() syncCategories,
  required Future<void> Function() syncProducts,
}) async {
  final results = await Future.wait([
    _captureCatalogSyncTask(syncCategories),
    _captureCatalogSyncTask(syncProducts),
  ]);

  final categories = results[0];
  if (categories.error != null) {
    debugPrint(
      '[CatalogSync] Category refresh failed; keeping saved categories: ${categories.error}',
    );
  }

  final products = results[1];
  if (products.error != null) {
    Error.throwWithStackTrace(products.error!, products.stackTrace!);
  }
}

/// Stores a single product returned by a successful create/update response in
/// the local catalog cache without making an immediate follow-up catalog GET.
Future<void> upsertProductCacheFromApi(
  Map<String, dynamic> product, {
  required String? expectedTenantId,
  required String? expectedBranchId,
  required String expectedApiBaseUrl,
}) async {
  final database = getIt<AppDatabase>();
  final storageService = getIt<StorageService>();
  final apiClient = getIt<ApiClient>();
  bool requestScopeIsCurrent() =>
      expectedTenantId != null &&
      storageService.getTenantId() == expectedTenantId &&
      storageService.getBranchId() == expectedBranchId &&
      apiClient.baseUrl == expectedApiBaseUrl;

  if (!requestScopeIsCurrent()) {
    debugPrint(
      '[CatalogSync] Skipped single-product cache upsert: workspace changed',
    );
    return;
  }

  final item = _productToCompanion(product);
  if (item == null) {
    debugPrint(
      '[CatalogSync] Skipped single-product cache upsert: invalid API product',
    );
    return;
  }

  await database.insertProduct(item);
  if (!requestScopeIsCurrent()) return;

  final productId = product['id']?.toString();
  if (productId != null) {
    await database.replacePricingTiersForProduct(
      productId,
      _pricingTiersToCompanions(product),
    );
    if (!requestScopeIsCurrent()) return;
  }

  final branchId = expectedBranchId;
  if (branchId != null) {
    final stockItem = _stockToCompanion(product, branchId);
    if (stockItem != null && requestScopeIsCurrent()) {
      await database.updateLocalStock([stockItem]);
    }
  }
}

Future<void> upsertCategoryCacheFromApi(Map<String, dynamic> category) async {
  final item = _categoryToCompanion(category);
  if (item == null) {
    debugPrint(
      '[CatalogSync] Skipped single-category cache upsert: invalid API category',
    );
    return;
  }
  await getIt<AppDatabase>().insertCategory(item);
}

Future<void> deleteProductFromCache(String productId) async {
  await getIt<AppDatabase>().deleteProductCacheReferences(productId);
}

Future<void> deleteCategoryFromCache(String categoryId) async {
  await getIt<AppDatabase>().deleteCategory(categoryId);
}

// Filter params
class FilterParams {
  final String? categoryId;
  final String? searchQuery;

  FilterParams({this.categoryId, this.searchQuery});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FilterParams &&
        other.categoryId == categoryId &&
        other.searchQuery == searchQuery;
  }

  @override
  int get hashCode => categoryId.hashCode ^ searchQuery.hashCode;
}

// Categories provider
final categoriesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final database = getIt<AppDatabase>();
  final localCategories = await database.getAllCategories();
  return localCategories
      .where((category) => category.isActive)
      .map(
        (category) => {
          'id': category.id,
          'name': category.name,
          'description': category.description,
          'parentId': category.parentId,
          'imageUrl': category.imageUrl,
          'sortOrder': category.sortOrder,
          'isActive': category.isActive,
        },
      )
      .toList();
});

final productSuggestionsProvider =
    StreamProvider.autoDispose.family<List<Product>, String>((ref, query) {
  final layout = ref.watch(businessLayoutProvider);
  return getIt<AppDatabase>()
      .watchProductSuggestions(query)
      .map((products) => products
          .where((product) => businessLayoutProductMatchesSearch(
                name: product.name,
                code: product.sku,
                metadata: product.metadata,
                layout: layout,
                query: query,
              ))
          .toList(growable: false));
});

// Filtered products provider
// Search text is part of FilterParams, so each keystroke can create another
// family instance. Dispose inactive results instead of retaining every prior
// search's product, tier, and stock maps for the life of the app.
final filteredProductsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, FilterParams>((
  ref,
  params,
) async {
  final database = getIt<AppDatabase>();
  final layout = ref.watch(businessLayoutProvider);
  final searchQuery = params.searchQuery?.trim();

  List<Product> products;

  if (searchQuery != null && searchQuery.isNotEmpty) {
    final candidates = await database.searchProducts(searchQuery);
    products = candidates
        .where((product) => businessLayoutProductMatchesSearch(
              name: product.name,
              code: product.sku,
              metadata: product.metadata,
              layout: layout,
              query: searchQuery,
            ))
        .toList(growable: false);
  } else if (params.categoryId != null) {
    products = await database.getProductsByCategory(params.categoryId!);
  } else {
    products = await database.getAllProducts();
  }

  return _productsToPosMaps(database, products);
});

// Favorites provider
class FavoritesNotifier extends StateNotifier<Set<String>> {
  final AppDatabase? _database;

  FavoritesNotifier(AppDatabase database)
      : _database = database,
        super({}) {
    _loadFavorites();
  }

  /// Empty, in-memory implementation for widgets that don't need persisted
  /// favourites (for example POS card interaction tests).
  FavoritesNotifier.emptyForTesting()
      : _database = null,
        super({});

  Future<void> _loadFavorites() async {
    final database = _database;
    if (database == null) return;
    final favorites = await database
        .customSelect('SELECT product_id FROM favorite_products')
        .get();
    state = favorites.map((f) => f.read<String>('product_id')).toSet();
  }

  Future<void> toggle(String productId) async {
    final database = _database;
    if (database == null) {
      if (state.contains(productId)) {
        final updated = {...state}..remove(productId);
        state = updated;
      } else {
        state = {...state, productId};
      }
      return;
    }
    if (state.contains(productId)) {
      await database.removeFavorite(productId);
      state = {...state}..remove(productId);
    } else {
      await database.addFavorite(productId);
      state = {...state, productId};
    }
  }

  bool isFavorite(String productId) => state.contains(productId);
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, Set<String>>(
  (ref) {
    return FavoritesNotifier(getIt<AppDatabase>());
  },
);

// Favorite products provider
final favoriteProductsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final database = getIt<AppDatabase>();
  final favorites = await database.getFavoriteProducts();

  return _productsToPosMaps(database, favorites);
});
