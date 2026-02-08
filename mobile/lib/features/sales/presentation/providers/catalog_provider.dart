import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/connectivity_service.dart';

// State providers for search/filter
final selectedCategoryProvider = StateProvider<String?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');

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
final categoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final database = getIt<AppDatabase>();
  
  // Always load from local DB first (offline-first)
  final localCategories = await database.getAllCategories();
  if (localCategories.isNotEmpty) {
    return localCategories.where((c) => c.isActive).map((c) => {
      'id': c.id,
      'name': c.name,
      'description': c.description,
      'parentId': c.parentId,
      'imageUrl': c.imageUrl,
      'sortOrder': c.sortOrder,
      'isActive': c.isActive,
    }).toList();
  }

  // Try API only if local is empty
  final apiClient = getIt<ApiClient>();
  final connectivity = getIt<ConnectivityService>();
  if (connectivity.isOnline) {
    try {
      final categories = await apiClient.getCategories();
      await database.insertCategories(
        categories.map((c) => CategoriesCompanion.insert(
          id: c['id'],
          name: c['name'],
          description: Value(c['description']),
          parentId: Value(c['parentId']),
          imageUrl: Value(c['imageUrl']),
          sortOrder: Value(c['sortOrder'] ?? 0),
          isActive: Value(c['isActive'] ?? true),
          createdAt: DateTime.parse(c['createdAt']),
          updatedAt: DateTime.parse(c['updatedAt']),
        )).toList(),
      );
      return categories.cast<Map<String, dynamic>>();
    } catch (e) {
      // API unavailable
    }
  }

  return [];
});

// Products provider
final productsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final database = getIt<AppDatabase>();
  
  // Always load from local DB first (offline-first)
  final localProducts = await database.getAllProducts();
  if (localProducts.isNotEmpty) {
    return localProducts.where((p) => p.isActive).map((p) => {
      'id': p.id,
      'sku': p.sku,
      'name': p.name,
      'description': p.description,
      'categoryId': p.categoryId,
      'price': p.price,
      'costPrice': p.costPrice,
      'unit': p.unit,
      'imageUrl': p.imageUrl,
      'isActive': p.isActive,
      'trackInventory': p.trackInventory,
    }).toList();
  }

  // Try API only if local is empty
  final apiClient = getIt<ApiClient>();
  final connectivity = getIt<ConnectivityService>();
  if (connectivity.isOnline) {
    try {
      final products = await apiClient.getProducts();
      await database.insertProducts(
        products.map((p) => ProductsCompanion.insert(
          id: p['id'],
          sku: p['sku'],
          name: p['name'],
          description: Value(p['description']),
          categoryId: p['categoryId'],
          price: (p['price'] as num).toDouble(),
          costPrice: Value(p['costPrice'] != null ? (p['costPrice'] as num).toDouble() : null),
          unit: Value(p['unit'] ?? 'piece'),
          imageUrl: Value(p['imageUrl']),
          isActive: Value(p['isActive'] ?? true),
          trackInventory: Value(p['trackInventory'] ?? true),
          createdAt: DateTime.parse(p['createdAt']),
          updatedAt: DateTime.parse(p['updatedAt']),
        )).toList(),
      );
      return products.cast<Map<String, dynamic>>();
    } catch (e) {
      // API unavailable
    }
  }

  return [];
});

// Filtered products provider
final filteredProductsProvider = FutureProvider.family<List<Map<String, dynamic>>, FilterParams>((ref, params) async {
  final database = getIt<AppDatabase>();
  
  List<Product> products;
  
  if (params.searchQuery != null && params.searchQuery!.isNotEmpty) {
    products = await database.searchProducts(params.searchQuery!);
  } else if (params.categoryId != null) {
    products = await database.getProductsByCategory(params.categoryId!);
  } else {
    products = await database.getAllProducts();
  }
  
  return products.where((p) => p.isActive).map((p) => {
    'id': p.id,
    'sku': p.sku,
    'name': p.name,
    'description': p.description,
    'categoryId': p.categoryId,
    'price': p.price,
    'costPrice': p.costPrice,
    'unit': p.unit,
    'imageUrl': p.imageUrl,
    'isActive': p.isActive,
  }).toList();
});

// Favorites provider
class FavoritesNotifier extends StateNotifier<Set<String>> {
  final AppDatabase _database;
  
  FavoritesNotifier(this._database) : super({}) {
    _loadFavorites();
  }
  
  Future<void> _loadFavorites() async {
    final favorites = await _database.customSelect(
      'SELECT product_id FROM favorite_products',
    ).get();
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

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  return FavoritesNotifier(getIt<AppDatabase>());
});

// Favorite products provider
final favoriteProductsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final database = getIt<AppDatabase>();
  final favorites = await database.getFavoriteProducts();
  
  return favorites.map((p) => {
    'id': p.id,
    'sku': p.sku,
    'name': p.name,
    'description': p.description,
    'categoryId': p.categoryId,
    'price': p.price,
    'imageUrl': p.imageUrl,
  }).toList();
});
