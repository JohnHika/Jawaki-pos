import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/storage_service.dart';

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
      if (node is! Map) continue;
      final category = Map<String, dynamic>.from(node);
      final children = category.remove('children');
      flattened.add(category);
      if (children is List) {
        walk(children);
      }
    }
  }

  walk(categories);
  return flattened;
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
  final categoryId = product['categoryId']?.toString();
  final priceValue =
      product['price'] ?? product['currentPrice'] ?? product['basePrice'];

  if (id == null ||
      name == null ||
      sku == null ||
      categoryId == null ||
      priceValue == null) {
    return null;
  }

  return ProductsCompanion.insert(
    id: id,
    sku: sku,
    name: name,
    description: Value(product['description']?.toString()),
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

Future<void> syncCatalogCacheFromApi() async {
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
    return;
  }

  final sync = _performCatalogSync(
    apiClient: apiClient,
    database: database,
    storageService: storageService,
    tenantId: tenantId,
    branchId: branchId,
    apiBaseUrl: apiBaseUrl,
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
}) async {
  bool isSameCatalogScope() =>
      storageService.getTenantId() == tenantId &&
      storageService.getBranchId() == branchId &&
      apiClient.baseUrl == apiBaseUrl;

  try {
    debugPrint('[CatalogSync] Fetching categories and products...');
    final responses = await Future.wait<Object>([
      apiClient.getCategories(),
      apiClient.getAllProducts(branchId: branchId),
    ]);
    final categoriesResponse = responses[0] as List<dynamic>;
    final flatCategories = _flattenCategories(categoriesResponse);
    final categoryItems = flatCategories
        .map(_categoryToCompanion)
        .whereType<CategoriesCompanion>()
        .toList();

    // Logout or switching shops while the requests were in flight must not
    // repopulate the shared local tables with the previous shop's catalog.
    if (!isSameCatalogScope()) {
      debugPrint('[CatalogSync] Skipped cache write: active shop changed');
      return;
    }
    await database.replaceCategories(categoryItems);
    debugPrint('[CatalogSync] Stored ${categoryItems.length} categories');

    final productsResponse = responses[1] as List<dynamic>;
    final productMaps = productsResponse
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final productItems = productMaps
        .map(_productToCompanion)
        .whereType<ProductsCompanion>()
        .toList();
    if (!isSameCatalogScope()) {
      debugPrint(
          '[CatalogSync] Skipped remaining cache writes: active shop changed');
      return;
    }
    await database.replaceProducts(productItems);
    debugPrint('[CatalogSync] Stored ${productItems.length} products');

    final tierItems = productMaps.expand(_pricingTiersToCompanions).toList();
    if (!isSameCatalogScope()) {
      debugPrint(
          '[CatalogSync] Skipped pricing cache write: active shop changed');
      return;
    }
    await database.replaceAllPricingTiers(tierItems);

    if (branchId != null) {
      final stockItems = productMaps
          .map((p) => _stockToCompanion(p, branchId))
          .whereType<LocalStockCompanion>()
          .toList();
      if (stockItems.isNotEmpty && isSameCatalogScope()) {
        await database.updateLocalStock(stockItems);
      }
    }
    debugPrint('[CatalogSync] Sync complete');
  } catch (e, st) {
    debugPrint('[CatalogSync] FAILED: $e');
    debugPrint('[CatalogSync] Stack: $st');
    rethrow;
  }
}

/// Stores a single product returned by a successful create/update response in
/// the local catalog cache without making an immediate follow-up catalog GET.
Future<void> upsertProductCacheFromApi(Map<String, dynamic> product) async {
  final database = getIt<AppDatabase>();
  final storageService = getIt<StorageService>();
  final item = _productToCompanion(product);
  if (item == null) {
    debugPrint(
      '[CatalogSync] Skipped single-product cache upsert: invalid API product',
    );
    return;
  }

  await database.insertProduct(item);
  final productId = product['id']?.toString();
  if (productId != null) {
    await database.replacePricingTiersForProduct(
      productId,
      _pricingTiersToCompanions(product),
    );
  }

  final branchId = storageService.getBranchId();
  if (branchId != null) {
    final stockItem = _stockToCompanion(product, branchId);
    if (stockItem != null) {
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
  return getIt<AppDatabase>().watchProductSuggestions(query);
});

// Filtered products provider
final filteredProductsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, FilterParams>((
  ref,
  params,
) async {
  final database = getIt<AppDatabase>();
  final searchQuery = params.searchQuery?.trim();

  List<Product> products;

  if (searchQuery != null && searchQuery.isNotEmpty) {
    products = await database.searchProducts(searchQuery);
  } else if (params.categoryId != null) {
    products = await database.getProductsByCategory(params.categoryId!);
  } else {
    products = await database.getAllProducts();
  }

  return _productsToPosMaps(database, products);
});

// Favorites provider
class FavoritesNotifier extends StateNotifier<Set<String>> {
  final AppDatabase _database;

  FavoritesNotifier(this._database) : super({}) {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favorites = await _database
        .customSelect('SELECT product_id FROM favorite_products')
        .get();
    state = favorites.map((f) => f.read<String>('product_id')).toSet();
  }

  Future<void> toggle(String productId) async {
    if (state.contains(productId)) {
      await _database.removeFavorite(productId);
      state = {...state}..remove(productId);
    } else {
      await _database.addFavorite(productId);
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
