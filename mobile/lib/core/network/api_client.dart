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

  /// Logs in against a phone-server using the offline-access PIN, not the
  /// online quick-login PIN — only meaningful when [baseUrl] points at a
  /// local server, since that's the only place `offline-pin-login` is
  /// implemented (see AuthRoutes._handleOfflinePinLogin on the phone-server
  /// side). Requires email because, unlike the online quick-login PIN
  /// (unique per device), multiple synced users could pick colliding PINs.
  Future<Map<String, dynamic>> loginWithOfflinePin({
    required String email,
    required String pin,
  }) async {
    final response = await _dio.post('/auth/offline-pin-login', data: {
      'email': email,
      'pin': pin,
    });
    return response.data;
  }

  /// Sets/updates the account's server-side PIN, so [loginWithPin] can
  /// authenticate this user even on a device that has never stored a
  /// local PIN hash (e.g. after a reinstall, or on a brand-new device).
  Future<void> setPin(String pin) async {
    await _dio.post('/auth/set-pin', data: {'pin': pin});
  }

  /// Sets/updates this user's offline-access PIN — authorizes logging
  /// into any phone acting as a local server (fully offline mode) as this
  /// user. Distinct from [setPin]'s online quick-login PIN.
  Future<void> setOfflineAccessPin(String pin) async {
    await _dio.post('/auth/offline-access-pin', data: {'pin': pin});
  }

  /// Pulled once (while online) by a device about to become a phone
  /// server, so it can authorize other users' logins entirely offline
  /// afterward. Only includes users who have set an offline-access PIN.
  Future<List<dynamic>> getOfflineUserDirectory() async {
    final response = await _dio.get('/users/offline-directory');
    return response.data as List<dynamic>;
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

  /// Re-pulls this user's effective permissions mid-session, so a role or
  /// override edit an admin makes takes effect without forcing a re-login.
  Future<List<String>> getMyPermissions() async {
    final response = await _dio.get('/permissions/me');
    final list = (response.data['permissions'] as List<dynamic>?) ?? [];
    return list.cast<String>();
  }

  Future<List<dynamic>> getPermissionCatalog() async {
    final response = await _dio.get('/permissions');
    return response.data as List<dynamic>;
  }

  // Roles endpoints
  Future<List<dynamic>> getRoles() async {
    final response = await _dio.get('/roles');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getRole(String id) async {
    final response = await _dio.get('/roles/$id');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createRole({
    required String name,
    String? description,
    List<String>? permissionKeys,
  }) async {
    final response = await _dio.post('/roles', data: {
      'name': name,
      if (description != null) 'description': description,
      if (permissionKeys != null) 'permissionKeys': permissionKeys,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateRole(
    String id, {
    String? name,
    String? description,
    List<String>? permissionKeys,
  }) async {
    final response = await _dio.patch('/roles/$id', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (permissionKeys != null) 'permissionKeys': permissionKeys,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteRole(String id) async {
    await _dio.delete('/roles/$id');
  }

  // User management endpoints (distinct from /auth/users; this surface
  // additionally carries each user's assigned roles for admin UI use)
  Future<List<dynamic>> getManagedUsers() async {
    final response = await _dio.get('/users');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getUserPermissionBreakdown(String userId) async {
    final response = await _dio.get('/users/$userId/permissions');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> assignUserRole(String userId, String roleId) async {
    final response = await _dio.post('/users/$userId/roles', data: {'roleId': roleId});
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> removeUserRole(String userId, String roleId) async {
    final response = await _dio.delete('/users/$userId/roles/$roleId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setUserPermissionOverride(
    String userId, {
    required String permissionKey,
    required bool grant,
    String? reason,
  }) async {
    final response = await _dio.post('/users/$userId/permission-overrides', data: {
      'permissionKey': permissionKey,
      'grant': grant,
      if (reason != null) 'reason': reason,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> clearUserPermissionOverride(
    String userId,
    String permissionKey,
  ) async {
    final response = await _dio.delete('/users/$userId/permission-overrides/$permissionKey');
    return response.data as Map<String, dynamic>;
  }

  // Branch endpoints
  Future<List<dynamic>> getBranches() async {
    final response = await _dio.get('/branches');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createBranch({
    required String name,
    required String code,
    String? address,
    String? phone,
    String? email,
  }) async {
    final response = await _dio.post('/branches', data: {
      'name': name,
      'code': code,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateBranch(
    String id, {
    String? name,
    String? code,
    String? address,
    String? phone,
    String? email,
    bool? isActive,
    Map<String, dynamic>? settings,
  }) async {
    final response = await _dio.patch('/branches/$id', data: {
      if (name != null) 'name': name,
      if (code != null) 'code': code,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (isActive != null) 'isActive': isActive,
      // Backend merges settings onto the existing blob, so sending only
      // { operatingHours: ... } preserves tax and other settings.
      if (settings != null) 'settings': settings,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Fetches a single branch (includes its `settings` JSON — operating
  /// hours, tax config, etc.).
  Future<Map<String, dynamic>> getBranch(String id) async {
    final response = await _dio.get('/branches/$id');
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteBranch(String id) async {
    await _dio.delete('/branches/$id');
  }

  /// Registers (or re-registers) this device against a branch. Only
  /// ADMIN/MANAGER accounts are authorized server-side — a 403 here just
  /// means this login can't self-register the device, which is expected
  /// for cashier/seller accounts and not an error worth surfacing.
  Future<Map<String, dynamic>> registerDevice({
    required String branchId,
    required String deviceUuid,
    required String name,
    String? appVersion,
  }) async {
    final response = await _dio.post('/branches/$branchId/devices', data: {
      'deviceUuid': deviceUuid,
      'name': name,
      'branchId': branchId,
      if (appVersion != null) 'appVersion': appVersion,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Admin-only. Returns recent tenant activity (logins, branch/PIN
  /// changes, etc.) — the actual data behind the Settings > Audit Trail
  /// screen.
  Future<Map<String, dynamic>> getAuditLog({int page = 1, int limit = 50}) async {
    final response = await _dio.get('/audit-log', queryParameters: {
      'page': page,
      'limit': limit,
    });
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
    String? branchId,
  }) async {
    final response = await _dio.get('/catalog/products', queryParameters: {
      if (categoryId != null) 'categoryId': categoryId,
      if (search != null) 'search': search,
      if (page != null) 'page': page,
      if (limit != null) 'limit': limit,
      if (branchId != null) 'branchId': branchId,
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
    List<Map<String, dynamic>>? pricingTiers,
    int? minStock,
  }) async {
    final response = await _dio.post('/catalog/products', data: {
      'name': name,
      'basePrice': basePrice,
      'categoryIds': categoryIds,
      if (description != null) 'description': description,
      if (image != null) 'image': image,
      if (imagePublicId != null) 'imagePublicId': imagePublicId,
      if (unit != null) 'unit': unit,
      if (pricingTiers != null) 'pricingTiers': pricingTiers,
      if (minStock != null) 'minStock': minStock,
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
    List<Map<String, dynamic>>? pricingTiers,
    int? minStock,
    bool clearImage = false,
  }) async {
    final response = await _dio.patch('/catalog/products/$id', data: {
      if (name != null) 'name': name,
      if (basePrice != null) 'basePrice': basePrice,
      if (categoryIds != null) 'categoryIds': categoryIds,
      if (description != null) 'description': description,
      if (unit != null) 'unit': unit,
      if (pricingTiers != null) 'pricingTiers': pricingTiers,
      if (minStock != null) 'minStock': minStock,
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

  /// Soft-voids a sale on the backend (status=VOIDED, records the reason +
  /// who/when, restores stock). Requires the sales.void permission.
  Future<Map<String, dynamic>> voidSale(String saleId, {required String reason}) async {
    final response = await _dio.post('/sales/$saleId/void', data: {'reason': reason});
    return response.data as Map<String, dynamic>;
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

  // Supplier endpoints
  Future<List<dynamic>> getSuppliers() async {
    final response = await _dio.get('/suppliers');
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getSupplierDebts() async {
    final response = await _dio.get('/suppliers/debts');
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getSupplierInvoices(String supplierId) async {
    final response = await _dio.get('/suppliers/$supplierId/invoices');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createSupplierInvoice(Map<String, dynamic> data) async {
    final response = await _dio.post('/suppliers/invoices', data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> recordSupplierPayment(
    String invoiceId,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.post('/suppliers/invoices/$invoiceId/payments', data: data);
    return response.data as Map<String, dynamic>;
  }

  // Cash flow endpoints
  Future<Map<String, dynamic>> getCashFlowSettings(String branchId) async {
    final response = await _dio.get('/cash-flow/settings/$branchId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateCashFlowSettings(String branchId, String mode) async {
    final response = await _dio.put('/cash-flow/settings/$branchId', data: {'mode': mode});
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getAvailableCash(String branchId) async {
    final response = await _dio.get('/cash-flow/available/$branchId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCashLedger(
    String branchId, {
    int? page,
    int? limit,
  }) async {
    final response = await _dio.get('/cash-flow/ledger/$branchId', queryParameters: {
      if (page != null) 'page': page,
      if (limit != null) 'limit': limit,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Records a physical cash count against the system's expected cash
  /// figure. SUPERVISOR+ only on the backend — a plain cashier cannot
  /// self-certify their own till count.
  Future<Map<String, dynamic>> createCashReconciliation(
    String branchId, {
    required double countedCash,
    String? notes,
  }) async {
    final response = await _dio.post('/cash-flow/reconciliations/$branchId', data: {
      'countedCash': countedCash,
      if (notes != null) 'notes': notes,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCashReconciliations(
    String branchId, {
    int? page,
    int? limit,
  }) async {
    final response = await _dio.get('/cash-flow/reconciliations/$branchId', queryParameters: {
      if (page != null) 'page': page,
      if (limit != null) 'limit': limit,
    });
    return response.data as Map<String, dynamic>;
  }

  // ── End-of-day close (Z-report + cash count) ──

  /// The day's sales summary for a branch (total, transactions, payment
  /// split) — shown before closing so the user reviews the figures.
  Future<Map<String, dynamic>> getSalesDailySummary(String branchId, String date) async {
    final response = await _dio.get('/sales/summary/$branchId/$date');
    return response.data as Map<String, dynamic>;
  }

  /// The close for a day (or today if [date] omitted); null if not yet closed.
  Future<Map<String, dynamic>?> getDailyClose(String branchId, {String? date}) async {
    final response = await _dio.get('/sales/daily-close/$branchId', queryParameters: {
      if (date != null) 'date': date,
    });
    return response.data == null ? null : (response.data as Map<String, dynamic>);
  }

  /// Closes the end of day: finalizes the Z-report and books the cash count.
  /// Requires the sales.close_end_of_day permission on the backend.
  Future<Map<String, dynamic>> closeEndOfDay(
    String branchId, {
    required double countedCash,
    String? date,
    String? notes,
  }) async {
    final response = await _dio.post('/sales/daily-close/$branchId', data: {
      'countedCash': countedCash,
      if (date != null) 'date': date,
      if (notes != null) 'notes': notes,
    });
    return response.data as Map<String, dynamic>;
  }

  // Restock suggestions
  Future<Map<String, dynamic>> getRestockSuggestions(String branchId) async {
    final response = await _dio.get('/inventory/restock-suggestions/$branchId');
    return response.data as Map<String, dynamic>;
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

  /// Upload an image and trace it into a scalable SVG logo (deterministic
  /// vectorization on the backend). Returns { rasterUrl, svgUrl, publicId }.
  Future<Map<String, dynamic>> vectorizeLogo({
    required String filePath,
    required String fileName,
    int? colors,
    int? detail,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: _imageContentType(fileName),
      ),
    });
    final response = await _dio.post(
      '/uploads/logo/vectorize',
      queryParameters: {
        if (colors != null) 'colors': colors,
        if (detail != null) 'detail': detail,
      },
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

  // Push notification token registration
  Future<void> registerPushToken({
    required String token,
    String? deviceUuid,
    String platform = 'android',
  }) async {
    await _dio.post('/notifications/tokens', data: {
      'token': token,
      if (deviceUuid != null) 'deviceUuid': deviceUuid,
      'platform': platform,
    });
  }

  Future<void> unregisterPushToken(String token) async {
    await _dio.delete('/notifications/tokens', data: {'token': token});
  }

  /// Vision-parses an already-uploaded receipt/invoice photo. Returns the
  /// backend's ParsedReceiptResult shape, including isReceipt: false with a
  /// rejectionReason when the image doesn't look like a receipt at all.
  Future<Map<String, dynamic>> scanReceiptImage({
    required String imageUrl,
    String? branchId,
  }) async {
    final response = await _dio.post('/ai/receipts/scan', data: {
      'imageUrl': imageUrl,
      if (branchId != null) 'branchId': branchId,
    });
    return (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  }

  /// General-purpose "what's in this photo" analysis — used when the AI
  /// chat's Camera/Photos attach finds no on-device OCR text (a product
  /// photo, damaged item, scene, etc. rather than a document). Sends the
  /// image inline as base64 (no upload/storage step) to the POS's own
  /// isolated vision model. Returns {reply, model}.
  Future<Map<String, dynamic>> analyzeImage({
    required String imageBase64,
    required String prompt,
    String? branchId,
  }) async {
    final response = await _dio.post('/ai/vision', data: {
      'imageBase64': imageBase64,
      'prompt': prompt,
      if (branchId != null) 'branchId': branchId,
    });
    return (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  }

  /// Durable shop memories the AI recalls across sessions (owner
  /// preferences, policies, customer notes) — tenant-wide, shared by every
  /// staff member the same way the chat thread itself is shared. Backend
  /// only supports create/list/delete (no edit-in-place).
  Future<List<Map<String, dynamic>>> getAiMemories({required String branchId}) async {
    final response = await _dio.get('/ai/memory', queryParameters: {'branchId': branchId});
    final data = (response.data as Map<String, dynamic>)['data'] as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> saveAiMemory({
    required String content,
    required String branchId,
    String? type,
    String? title,
  }) async {
    final response = await _dio.post('/ai/memory', data: {
      'content': content,
      'branchId': branchId,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
    });
    return (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  }

  Future<void> deleteAiMemory({required String id, required String branchId}) async {
    await _dio.post('/ai/memory/delete', data: {'id': id, 'branchId': branchId});
  }

  // ─── Shared-printer print queue ───────────────────────────────────────
  // Bluetooth Classic only allows one active connection, so when several
  // devices share one thermal printer, only the device designated as the
  // printer's holder actually connects/prints — every other device just
  // enqueues a job here and polls its own status. See PrintQueueService.

  Future<Map<String, dynamic>> enqueuePrintJob({
    required String deviceId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _dio.post('/printing/jobs', data: {
      'deviceId': deviceId,
      'payload': payload,
    });
    return (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  }

  /// Called only by the device designated as the printer holder — claims
  /// and returns any pending jobs (oldest first) for this branch so it can
  /// print them one at a time.
  Future<List<Map<String, dynamic>>> claimPrintJobs({required String deviceId}) async {
    final response = await _dio.post('/printing/jobs/claim', data: {'deviceId': deviceId});
    final data = (response.data as Map<String, dynamic>)['data'] as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> completePrintJob({
    required String jobId,
    required String deviceId,
    required String status,
    String? errorMessage,
  }) async {
    await _dio.put('/printing/jobs/$jobId/complete', data: {
      'deviceId': deviceId,
      'status': status,
      if (errorMessage != null) 'errorMessage': errorMessage,
    });
  }

  /// Lets the requesting device show "queued" -> "printed"/"failed" for
  /// jobs it raised itself, without needing to be the printer holder.
  Future<List<Map<String, dynamic>>> getMyPrintJobs({required String deviceId}) async {
    final response = await _dio.get('/printing/jobs/mine', queryParameters: {'deviceId': deviceId});
    final data = (response.data as Map<String, dynamic>)['data'] as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<String?> getPrinterDevice() async {
    final response = await _dio.get('/printing/printer-device');
    final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return data['printerDeviceId'] as String?;
  }

  Future<void> setPrinterDevice(String? deviceId) async {
    await _dio.put('/printing/printer-device', data: {'deviceId': deviceId});
  }
}
