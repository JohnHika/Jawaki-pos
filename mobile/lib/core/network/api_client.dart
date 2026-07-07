import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

class ApiClient {
  final Dio _dio;

  ApiClient(this._dio);

  /// Update the base URL at runtime (used when switching to a phone server).
  void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }

  /// Get the current base URL.
  String get baseUrl => _dio.options.baseUrl;
  
  // Auth endpoints
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? tenantSlug,
    String? deviceId,
  }) async {
    final response = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
      if (tenantSlug != null) 'tenantSlug': tenantSlug,
      if (deviceId != null) 'deviceId': deviceId,
    });
    return response.data;
  }
  
  Future<Map<String, dynamic>> loginWithPin({
    required String pin,
    required String deviceId,
    String? branchId,
  }) async {
    final response = await _dio.post('/auth/login/pin', data: {
      'pin': pin,
      'deviceId': deviceId,
      if (branchId != null) 'branchId': branchId,
    });
    return response.data;
  }
  
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final response = await _dio.post('/auth/refresh', data: {
      'refreshToken': refreshToken,
    });
    return response.data;
  }
  
  Future<void> logout({
    String? refreshToken,
    bool allDevices = false,
  }) async {
    await _dio.post('/auth/logout', data: {
      if (refreshToken != null) 'refreshToken': refreshToken,
      if (allDevices) 'allDevices': true,
    });
  }

  /// Register a new company with admin user and branch.
  /// Used during first-time setup flow.
  Future<Map<String, dynamic>> registerCompany({
    required String companyName,
    required String adminEmail,
    required String adminPassword,
    required String adminFirstName,
    required String adminLastName,
    required String branchName,
    required String branchCode,
    String? branchAddress,
    String? branchPhone,
    String? deviceId,
  }) async {
    final response = await _dio.post('/auth/register-company', data: {
      'companyName': companyName,
      if (deviceId != null) 'deviceId': deviceId,
      'admin': {
        'email': adminEmail,
        'password': adminPassword,
        'firstName': adminFirstName,
        'lastName': adminLastName,
      },
      'branch': {
        'name': branchName,
        'code': branchCode,
        if (branchAddress != null) 'address': branchAddress,
        if (branchPhone != null) 'phone': branchPhone,
      },
    });
    return response.data;
  }

  Future<Map<String, dynamic>> updateCurrentTenant({
    String? name,
    String? logo,
    String? logoPublicId,
    double? taxRatePercent,
    bool? showTaxOnReceipt,
  }) async {
    final response = await _dio.patch('/branches/tenants/current', data: {
      if (name != null) 'name': name,
      if (logo != null) 'logo': logo,
      if (logoPublicId != null) 'logoPublicId': logoPublicId,
      if (taxRatePercent != null) 'taxRatePercent': taxRatePercent,
      if (showTaxOnReceipt != null) 'showTaxOnReceipt': showTaxOnReceipt,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getProfile() async {
    final response = await _dio.get('/auth/profile');
    return response.data as Map<String, dynamic>;
  }

  /// Fetch company name and logo by tenant slug (public, no auth required).
  /// Returns null if slug is empty or company not found.
  Future<Map<String, dynamic>?> getCompanyInfo(String slug) async {
    if (slug.isEmpty) return null;
    try {
      final response = await _dio.get(
        '/auth/company-info',
        queryParameters: {'slug': slug},
      );
      return response.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getLatestAndroidUpdate() async {
    final response = await _dio.get('/app-updates/android/latest');
    return response.data as Map<String, dynamic>;
  }

  // Catalog endpoints
  Future<List<dynamic>> getCategories() async {
    final response = await _dio.get('/catalog/categories');
    return response.data;
  }

  Future<Map<String, dynamic>> createCategory({
    required String name,
    String? description,
    String? image,
    String? imagePublicId,
  }) async {
    final response = await _dio.post('/catalog/categories', data: {
      'name': name,
      if (description != null) 'description': description,
      if (image != null) 'image': image,
      if (imagePublicId != null) 'imagePublicId': imagePublicId,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateCategory(
    String id, {
    String? name,
    String? description,
    String? image,
    String? imagePublicId,
    bool clearImage = false,
  }) async {
    final response = await _dio.patch('/catalog/categories/$id', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (clearImage) 'image': null,
      if (clearImage) 'imagePublicId': null,
      if (!clearImage && image != null) 'image': image,
      if (!clearImage && imagePublicId != null) 'imagePublicId': imagePublicId,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteCategory(String id) async {
    await _dio.delete('/catalog/categories/$id');
  }
  
  Future<List<dynamic>> getProducts({
    String? categoryId,
    String? search,
    int? page,
    int? limit,
  }) async {
    final response = await _dio.get('/catalog/products', queryParameters: {
      if (categoryId != null) 'categoryId': categoryId,
      if (search != null) 'search': search,
      if (page != null) 'page': page,
      if (limit != null) 'limit': limit,
    });
    return response.data['items'];
  }

  Future<Map<String, dynamic>> createProduct({
    required String name,
    required double basePrice,
    required List<String> categoryIds,
    String? description,
    String? image,
    String? imagePublicId,
    String? unit,
    String? secondaryUnit,
    double? secondaryUnitQty,
    double? secondaryUnitPrice,
    String? tertiaryUnit,
    double? tertiaryUnitQty,
    double? tertiaryUnitPrice,
  }) async {
    final metadata = <String, dynamic>{};
    if (secondaryUnitPrice != null) metadata['secondaryUnitPrice'] = secondaryUnitPrice;
    if (tertiaryUnitPrice != null) metadata['tertiaryUnitPrice'] = tertiaryUnitPrice;

    final response = await _dio.post('/catalog/products', data: {
      'name': name,
      'basePrice': basePrice,
      'categoryIds': categoryIds,
      if (description != null) 'description': description,
      if (image != null) 'image': image,
      if (imagePublicId != null) 'imagePublicId': imagePublicId,
      if (unit != null) 'unit': unit,
      if (secondaryUnit != null) 'secondaryUnit': secondaryUnit,
      if (secondaryUnitQty != null) 'secondaryUnitQty': secondaryUnitQty,
      if (tertiaryUnit != null) 'tertiaryUnit': tertiaryUnit,
      if (tertiaryUnitQty != null) 'tertiaryUnitQty': tertiaryUnitQty,
      if (metadata.isNotEmpty) 'metadata': metadata,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProduct(
    String id, {
    String? name,
    double? basePrice,
    List<String>? categoryIds,
    String? description,
    String? image,
    String? imagePublicId,
    String? unit,
    String? secondaryUnit,
    double? secondaryUnitQty,
    double? secondaryUnitPrice,
    String? tertiaryUnit,
    double? tertiaryUnitQty,
    double? tertiaryUnitPrice,
    bool clearImage = false,
  }) async {
    final metadata = <String, dynamic>{};
    if (secondaryUnitPrice != null) metadata['secondaryUnitPrice'] = secondaryUnitPrice;
    if (tertiaryUnitPrice != null) metadata['tertiaryUnitPrice'] = tertiaryUnitPrice;

    final response = await _dio.patch('/catalog/products/$id', data: {
      if (name != null) 'name': name,
      if (basePrice != null) 'basePrice': basePrice,
      if (categoryIds != null) 'categoryIds': categoryIds,
      if (description != null) 'description': description,
      if (unit != null) 'unit': unit,
      if (secondaryUnit != null) 'secondaryUnit': secondaryUnit,
      if (secondaryUnitQty != null) 'secondaryUnitQty': secondaryUnitQty,
      if (tertiaryUnit != null) 'tertiaryUnit': tertiaryUnit,
      if (tertiaryUnitQty != null) 'tertiaryUnitQty': tertiaryUnitQty,
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (clearImage) 'image': null,
      if (clearImage) 'imagePublicId': null,
      if (!clearImage && image != null) 'image': image,
      if (!clearImage && imagePublicId != null) 'imagePublicId': imagePublicId,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteProduct(String id) async {
    await _dio.delete('/catalog/products/$id');
  }
  
  Future<Map<String, dynamic>> getProduct(String id) async {
    final response = await _dio.get('/catalog/products/$id');
    return response.data;
  }
  
  Future<List<dynamic>> getPriceOverrides() async {
    final response = await _dio.get('/catalog/prices');
    return response.data;
  }
  
  // Sales endpoints
  Future<Map<String, dynamic>> createSale(Map<String, dynamic> data) async {
    final response = await _dio.post('/sales', data: data);
    return response.data;
  }
  
  Future<List<dynamic>> getSales({
    String? startDate,
    String? endDate,
    int? page,
    int? limit,
  }) async {
    final response = await _dio.get('/sales', queryParameters: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (page != null) 'page': page,
      if (limit != null) 'limit': limit,
    });
    return response.data['items'];
  }
  
  Future<Map<String, dynamic>> getSale(String id) async {
    final response = await _dio.get('/sales/$id');
    return response.data;
  }
  
  Future<Map<String, dynamic>> getReceipt(String saleId) async {
    final response = await _dio.get('/sales/$saleId/receipt');
    return response.data;
  }
  
  Future<Map<String, dynamic>> getDailySummary() async {
    final response = await _dio.get('/sales/daily-summary');
    return response.data;
  }
  
  // Inventory endpoints
  Future<List<dynamic>> getStock({String? branchId}) async {
    final response = await _dio.get('/inventory/stock', queryParameters: {
      if (branchId != null) 'branchId': branchId,
    });
    return response.data;
  }
  
  Future<List<dynamic>> getLowStockItems() async {
    final response = await _dio.get('/inventory/low-stock');
    return response.data;
  }
  
  Future<Map<String, dynamic>> receiveBatches(Map<String, dynamic> data) async {
    final response = await _dio.post('/inventory/batches/receive', data: data);
    return response.data;
  }
  
  // Stock Request endpoints
  Future<Map<String, dynamic>> createStockRequest(Map<String, dynamic> data) async {
    final response = await _dio.post('/inventory/stock-requests', data: data);
    return response.data;
  }
  
  Future<List<dynamic>> getStockRequests({
    String? branchId,
    String? status,
    String? priority,
    int? page,
    int? limit,
  }) async {
    final response = await _dio.get('/inventory/stock-requests', queryParameters: {
      if (branchId != null) 'branchId': branchId,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (page != null) 'page': page,
      if (limit != null) 'limit': limit,
    });
    return response.data;
  }
  
  Future<Map<String, dynamic>> getStockRequest(String id) async {
    final response = await _dio.get('/inventory/stock-requests/$id');
    return response.data;
  }
  
  Future<Map<String, dynamic>> updateStockRequest(String id, Map<String, dynamic> data) async {
    final response = await _dio.put('/inventory/stock-requests/$id', data: data);
    return response.data;
  }
  
  Future<Map<String, dynamic>> resolveStockRequest(String id, Map<String, dynamic> data) async {
    final response = await _dio.put('/inventory/stock-requests/$id/resolve', data: data);
    return response.data;
  }
  
  Future<Map<String, dynamic>> cancelStockRequest(String id, Map<String, dynamic> data) async {
    final response = await _dio.put('/inventory/stock-requests/$id/cancel', data: data);
    return response.data;
  }
  
  Future<Map<String, dynamic>> getStockRequestStats({String? branchId}) async {
    final response = await _dio.get('/inventory/stock-requests/stats/summary', queryParameters: {
      if (branchId != null) 'branchId': branchId,
    });
    return response.data;
  }
  
  // Payment endpoints
  Future<Map<String, dynamic>> initiateMpesaPayment(Map<String, dynamic> data) async {
    final response = await _dio.post('/payments/mpesa/initiate', data: data);
    return response.data;
  }
  
  Future<Map<String, dynamic>> checkMpesaPaymentStatus(String checkoutRequestId) async {
    final response = await _dio.get('/payments/mpesa/status/$checkoutRequestId');
    return response.data;
  }
  
  Future<Map<String, dynamic>> initiatePesaPalPayment(Map<String, dynamic> data) async {
    final response = await _dio.post('/payments/pesapal/initiate', data: data);
    return response.data;
  }
  
  Future<Map<String, dynamic>> initiateTouristTapPayment(Map<String, dynamic> data) async {
    final response = await _dio.post('/payments/touristtap/initiate', data: data);
    return response.data;
  }
  
  // Sync endpoints
  Future<Map<String, dynamic>> pushSyncEvents(Map<String, dynamic> data) async {
    final response = await _dio.post('/sync/push', data: data);
    return response.data;
  }
  
  Future<Map<String, dynamic>> pullSyncEvents({String? since}) async {
    final response = await _dio.post('/sync/pull', data: {
      if (since != null) 'since': since,
    });
    return response.data;
  }

  Future<List<dynamic>> resolveSyncConflicts(
    List<Map<String, dynamic>> conflicts,
  ) async {
    final response = await _dio.post('/sync/conflicts/resolve', data: conflicts);
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getFailedSyncEvents() async {
    final response = await _dio.get('/sync/failed');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> retryFailedSyncEvents() async {
    final response = await _dio.post('/sync/retry');
    return response.data;
  }
  
  Future<void> sendHeartbeat() async {
    await _dio.post('/sync/heartbeat');
  }
  
  // Reports endpoints
  Future<Map<String, dynamic>> getDashboard({
    String? period,
    String? branchId,
  }) async {
    final response = await _dio.get('/reports/dashboard', queryParameters: {
      if (period != null) 'period': period,
      if (branchId != null) 'branchId': branchId,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> getDailyProfitLoss(String branchId, String date) async {
    final response = await _dio.get('/reports/profit-loss/$branchId/$date');
    return response.data;
  }

  /// Upload an image file to Cloudinary via the backend.
  /// [type] must be one of: 'logo', 'category', 'product'
  /// Returns { url, publicId, width, height, format, bytes }
  Future<Map<String, dynamic>> uploadImage({
    required String filePath,
    required String fileName,
    required String type,
  }) async {
    final contentType = _imageContentType(fileName);
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: contentType,
      ),
    });
    final response = await _dio.post(
      '/uploads/image',
      queryParameters: {'type': type},
      data: formData,
    );
    return response.data as Map<String, dynamic>;
  }

  MediaType _imageContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }
}
