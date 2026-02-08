import 'package:dio/dio.dart';

class ApiClient {
  final Dio _dio;
  
  ApiClient(this._dio);
  
  // Auth endpoints
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? deviceId,
  }) async {
    final response = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
      if (deviceId != null) 'deviceId': deviceId,
    });
    return response.data;
  }
  
  Future<Map<String, dynamic>> loginWithPin({
    required String pin,
    required String deviceId,
  }) async {
    final response = await _dio.post('/auth/pin-login', data: {
      'pin': pin,
      'deviceId': deviceId,
    });
    return response.data;
  }
  
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final response = await _dio.post('/auth/refresh', data: {
      'refreshToken': refreshToken,
    });
    return response.data;
  }
  
  Future<void> logout() async {
    await _dio.post('/auth/logout');
  }
  
  // Catalog endpoints
  Future<List<dynamic>> getCategories() async {
    final response = await _dio.get('/catalog/categories');
    return response.data;
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
  
  // Payment endpoints
  Future<Map<String, dynamic>> initiateMpesaPayment(Map<String, dynamic> data) async {
    final response = await _dio.post('/payments/mpesa/stkpush', data: data);
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
}
