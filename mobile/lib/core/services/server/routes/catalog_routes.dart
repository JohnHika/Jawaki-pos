import 'dart:convert';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;
import '../../../database/app_database.dart';

/// Catalog routes for phone server mode.
class CatalogRoutes {
  final AppDatabase _db;

  CatalogRoutes(this._db);

  void addRoutes(Router r) {
    r.get('/api/v1/catalog/categories', _handleGetCategories);
    r.get('/api/v1/catalog/products', _handleGetProducts);
    r.get('/api/v1/catalog/products/favorites', _handleGetFavorites);
    r.get('/api/v1/catalog/products/<id>', _handleGetProduct);
    r.get('/api/v1/catalog/prices', _handleGetPriceOverrides);
  }

  /// GET /api/v1/catalog/categories
  Future<shelf.Response> _handleGetCategories(shelf.Request request) async {
    final categories = await _db.getAllCategories();
    return shelf.Response.ok(
      jsonEncode(categories.map((c) => {
        'id': c.id,
        'name': c.name,
        'description': c.description,
        'parentId': c.parentId,
        'imageUrl': c.imageUrl,
        'sortOrder': c.sortOrder,
        'isActive': c.isActive,
      }).toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/v1/catalog/products?categoryId=&search=&page=&limit=
  Future<shelf.Response> _handleGetProducts(shelf.Request request) async {
    final params = request.url.queryParameters;
    final categoryId = params['categoryId'];
    final search = params['search'];
    final page = int.tryParse(params['page'] ?? '1') ?? 1;
    final limit = int.tryParse(params['limit'] ?? '50') ?? 50;

    List<Product> products;
    if (search != null && search.isNotEmpty) {
      products = await _db.searchProducts(search);
    } else if (categoryId != null && categoryId.isNotEmpty) {
      products = await _db.getProductsByCategory(categoryId);
    } else {
      products = await _db.getAllProducts();
    }

    final total = products.length;
    final start = (page - 1) * limit;
    final paged = products.skip(start).take(limit).toList();

    return shelf.Response.ok(
      jsonEncode({
        'items': paged.map((p) => _productToMap(p)).toList(),
        'total': total,
        'page': page,
        'limit': limit,
        'totalPages': (total / limit).ceil(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/v1/catalog/products/<id>
  Future<shelf.Response> _handleGetProduct(shelf.Request request, String id) async {
    final product = await _db.getProduct(id);
    if (product == null) {
      return shelf.Response.notFound(
        jsonEncode({'error': 'Product not found'}),
        headers: {'content-type': 'application/json'},
      );
    }
    return shelf.Response.ok(
      jsonEncode(_productToMap(product)),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/v1/catalog/products/favorites?branchId=
  Future<shelf.Response> _handleGetFavorites(shelf.Request request) async {
    final favorites = await _db.getFavoriteProducts();
    return shelf.Response.ok(
      jsonEncode(favorites.map((p) => _productToMap(p)).toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/v1/catalog/prices
  Future<shelf.Response> _handleGetPriceOverrides(shelf.Request request) async {
    final prices = await _db.select(_db.branchPrices).get();
    return shelf.Response.ok(
      jsonEncode(prices.map((p) => {
        'id': p.id,
        'productId': p.productId,
        'branchId': p.branchId,
        'price': p.price,
      }).toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  Map<String, dynamic> _productToMap(Product p) {
    return {
      'id': p.id,
      'sku': p.sku,
      'name': p.name,
      'description': p.description,
      'imageUrl': p.imageUrl,
      'basePrice': p.price,
      'currentPrice': p.price,
      'costPrice': p.costPrice,
      'unit': p.unit,
      'secondaryUnit': p.secondaryUnit,
      'secondaryUnitQty': p.secondaryUnitQty,
      'tertiaryUnit': p.tertiaryUnit,
      'tertiaryUnitQty': p.tertiaryUnitQty,
      'isActive': p.isActive,
      'trackInventory': p.trackInventory,
      'categoryId': p.categoryId,
      'categories': [], // Filled in by caller if needed
      'currentStock': 0, // Filled in by caller if needed
    };
  }
}
