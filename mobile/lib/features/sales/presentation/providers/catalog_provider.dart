import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/connectivity_service.dart';

// State providers for search/filter
final selectedCategoryProvider = StateProvider<String?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');

Future<Map<String, dynamic>> _productToPosMap(
  AppDatabase database,
  Product product,
) async {
  final stock = await database.getStockForProduct(product.id);

  return {
    'id': product.id,
    'sku': product.sku,
    'name': product.name,
    'description': product.description,
    'categoryId': product.categoryId,
    'price': product.price,
    'costPrice': product.costPrice,
    'unit': product.unit,
    'secondaryUnit': product.secondaryUnit,
    'secondaryUnitQty': product.secondaryUnitQty,
    'secondaryUnitPrice': product.secondaryUnitPrice,
    'tertiaryUnit': product.tertiaryUnit,
    'tertiaryUnitQty': product.tertiaryUnitQty,
    'tertiaryUnitPrice': product.tertiaryUnitPrice,
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

/// Extracts a unit price from the product's metadata JSON.
/// [tier] is either 'secondary' or 'tertiary'.
double? _parseMetadataPrice(Map<String, dynamic> product, String tier) {
  final metadata = product['metadata'];
  if (metadata is Map) {
    final key = '${tier}UnitPrice';
    final val = metadata[key];
    if (val != null) return (val as num).toDouble();
  }
  return null;
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
    secondaryUnit: Value(product['secondaryUnit']?.toString()),
    secondaryUnitQty: Value(
      product['secondaryUnitQty'] != null
          ? (product['secondaryUnitQty'] as num).toDouble()
          : null,
    ),
    secondaryUnitPrice: Value(
      product['secondaryUnitPrice'] != null
          ? (product['secondaryUnitPrice'] as num).toDouble()
          : _parseMetadataPrice(product, 'secondary'),
    ),
    tertiaryUnit: Value(product['tertiaryUnit']?.toString()),
    tertiaryUnitQty: Value(
      product['tertiaryUnitQty'] != null
          ? (product['tertiaryUnitQty'] as num).toDouble()
          : null,
    ),
    tertiaryUnitPrice: Value(
      product['tertiaryUnitPrice'] != null
          ? (product['tertiaryUnitPrice'] as num).toDouble()
          : _parseMetadataPrice(product, 'tertiary'),
    ),
    imageUrl: Value(product['imageUrl']?.toString()),
    isActive: Value(product['isActive'] as bool? ?? true),
    trackInventory: Value(product['trackInventory'] as bool? ?? true),
    minStock: Value((product['minStock'] as num?)?.toInt() ?? 0),
    createdAt: _parseTimestamp(product['createdAt']),
    updatedAt: _parseTimestamp(product['updatedAt']),
  );
}

Future<void> syncCatalogCacheFromApi() async {
  final connectivity = getIt<ConnectivityService>();
  if (!connectivity.isOnline) return;

  final apiClient = getIt<ApiClient>();
  final database = getIt<AppDatabase>();

  final categoriesResponse = await apiClient.getCategories();
  final flatCategories = _flattenCategories(categoriesResponse);
  final categoryItems = flatCategories
      .map(_categoryToCompanion)
      .whereType<CategoriesCompanion>()
      .toList();
  await database.replaceCategories(categoryItems);

  final productsResponse = await apiClient.getProducts(limit: 500);
  final productItems = productsResponse
      .whereType<Map>()
      .map((item) => _productToCompanion(Map<String, dynamic>.from(item)))
      .whereType<ProductsCompanion>()
      .toList();
  await database.replaceProducts(productItems);
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
      await database.replaceProducts(
        products
            .whereType<Map>()
            .map((item) => _productToCompanion(Map<String, dynamic>.from(item)))
            .whereType<ProductsCompanion>()
            .toList(),
      );
      final localProducts = await database.getAllProducts();
      final mapped = <Map<String, dynamic>>[];
      for (final product in localProducts.where((p) => p.isActive)) {
        mapped.add(await _productToPosMap(database, product));
      }
      if (mapped.isNotEmpty) return mapped;

      return products
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
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
