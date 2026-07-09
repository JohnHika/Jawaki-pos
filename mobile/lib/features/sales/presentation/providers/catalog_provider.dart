import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/storage_service.dart';

// State providers for search/filter
final selectedCategoryProvider = StateProvider<String?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');

Future<Map<String, dynamic>> _productToPosMap(
  AppDatabase database,
  Product product,
) async {
  final stock = await database.getStockForProduct(product.id);
  final tiers = await database.getPricingTiersForProduct(product.id);

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
        .map((t) => {
              'unit': t.unit,
              'quantityPerUnit': t.quantityPerUnit,
              'price': t.price,
              'sortOrder': t.sortOrder,
            })
        .toList(),
    'imageUrl': product.imageUrl,
    'isActive': product.isActive,
    'trackInventory': product.trackInventory,
    'stock': stock?.quantity ?? 0,
    'minStock': product.minStock,
  };
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
    quantity: (currentStock as num).toInt(),
    updatedAt: DateTime.now(),
  );
}

Future<void> syncCatalogCacheFromApi() async {
  final connectivity = getIt<ConnectivityService>();
  if (!connectivity.isOnline) return;

  final apiClient = getIt<ApiClient>();
  final database = getIt<AppDatabase>();
  final storageService = getIt<StorageService>();

  final categoriesResponse = await apiClient.getCategories();
  final flatCategories = _flattenCategories(categoriesResponse);
  final categoryItems = flatCategories
      .map(_categoryToCompanion)
      .whereType<CategoriesCompanion>()
      .toList();
  await database.replaceCategories(categoryItems);

  final productsResponse = await apiClient.getProducts(limit: 500);
  final productMaps = productsResponse
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();

  final productItems = productMaps
      .map(_productToCompanion)
      .whereType<ProductsCompanion>()
      .toList();
  await database.replaceProducts(productItems);

  final tierItems = productMaps.expand(_pricingTiersToCompanions).toList();
  await database.replaceAllPricingTiers(tierItems);

  final branchId = storageService.getBranchId();
  if (branchId != null) {
    final stockItems = productMaps
        .map((p) => _stockToCompanion(p, branchId))
        .whereType<LocalStockCompanion>()
        .toList();
    if (stockItems.isNotEmpty) {
      await database.updateLocalStock(stockItems);
    }
  }
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
  final apiClient = getIt<ApiClient>();
  final connectivity = getIt<ConnectivityService>();
  if (connectivity.isOnline) {
    try {
      final categories = await apiClient.getCategories();
      final flatCategories = _flattenCategories(categories);
      await database.replaceCategories(
        flatCategories
            .map(_categoryToCompanion)
            .whereType<CategoriesCompanion>()
            .toList(),
      );
      return flatCategories.where((c) => c['isActive'] != false).toList();
    } catch (e) {
      // API unavailable
    }
  }

  final localCategories = await database.getAllCategories();
  if (localCategories.isNotEmpty) {
    return localCategories
        .where((c) => c.isActive)
        .map(
          (c) => {
            'id': c.id,
            'name': c.name,
            'description': c.description,
            'parentId': c.parentId,
            'imageUrl': c.imageUrl,
            'sortOrder': c.sortOrder,
            'isActive': c.isActive,
          },
        )
        .toList();
  }

  return [];
});

// Products provider
final productsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final database = getIt<AppDatabase>();
  final apiClient = getIt<ApiClient>();
  final connectivity = getIt<ConnectivityService>();
  if (connectivity.isOnline) {
    try {
      final products = await apiClient.getProducts(limit: 500);
      final productMaps = products
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      await database.replaceProducts(
        productMaps.map(_productToCompanion).whereType<ProductsCompanion>().toList(),
      );
      await database.replaceAllPricingTiers(
        productMaps.expand(_pricingTiersToCompanions).toList(),
      );
      final localProducts = await database.getAllProducts();
      final mapped = <Map<String, dynamic>>[];
      for (final product in localProducts.where((p) => p.isActive)) {
        mapped.add(await _productToPosMap(database, product));
      }
      if (mapped.isNotEmpty) return mapped;

      return productMaps;
    } catch (e) {
      // API unavailable
    }
  }

  final localProducts = await database.getAllProducts();
  if (localProducts.isNotEmpty) {
    final mapped = <Map<String, dynamic>>[];
    for (final product in localProducts.where((p) => p.isActive)) {
      mapped.add(await _productToPosMap(database, product));
    }
    return mapped;
  }

  return [];
});

// Filtered products provider
final filteredProductsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, FilterParams>((
      ref,
      params,
    ) async {
      final database = getIt<AppDatabase>();

      List<Product> products;

      if (params.searchQuery != null && params.searchQuery!.isNotEmpty) {
        products = await database.searchProducts(params.searchQuery!);
      } else if (params.categoryId != null) {
        products = await database.getProductsByCategory(params.categoryId!);
      } else {
        products = await database.getAllProducts();
      }

      final mapped = <Map<String, dynamic>>[];
      for (final product in products.where((p) => p.isActive)) {
        mapped.add(await _productToPosMap(database, product));
      }
      return mapped;
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

  final mapped = <Map<String, dynamic>>[];
  for (final product in favorites.where((p) => p.isActive)) {
    mapped.add(await _productToPosMap(database, product));
  }
  return mapped;
});
