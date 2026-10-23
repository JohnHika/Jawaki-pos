import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../../features/finance/domain/finance_models.dart';

/// Verified workspace fields shared by the Google and email-OTP flows.
/// This deliberately has no password field: the server creates owners only
/// after it verifies an identity token or email ownership code.
class WorkspaceCreationRequest {
  const WorkspaceCreationRequest({
    required this.companyName,
    required this.firstName,
    required this.lastName,
    required this.branch,
    required this.acceptedPolicyTypes,
    this.companySlug,
    this.logo,
    this.logoPublicId,
    this.settings,
    this.deviceId,
  });

  final String companyName;
  final String firstName;
  final String lastName;
  final WorkspaceBranchDetails branch;
  final List<String> acceptedPolicyTypes;
  final String? companySlug;
  final String? logo;
  final String? logoPublicId;
  final Map<String, dynamic>? settings;
  final String? deviceId;

  Map<String, dynamic> toJson() => {
        'companyName': companyName,
        'firstName': firstName,
        'lastName': lastName,
        'acceptedPolicyTypes': acceptedPolicyTypes,
        if (companySlug != null && companySlug!.isNotEmpty)
          'companySlug': companySlug,
        if (logo != null && logo!.isNotEmpty) 'logo': logo,
        if (logoPublicId != null && logoPublicId!.isNotEmpty)
          'logoPublicId': logoPublicId,
        if (settings != null) 'settings': settings,
        if (deviceId != null && deviceId!.isNotEmpty) 'deviceId': deviceId,
        'branch': branch.toJson(),
      };
}

class WorkspaceBranchDetails {
  const WorkspaceBranchDetails({
    required this.name,
    this.code,
    this.address,
    this.phone,
    this.email,
  });

  final String name;
  final String? code;
  final String? address;
  final String? phone;
  final String? email;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (code != null && code!.isNotEmpty) 'code': code,
        if (address != null && address!.isNotEmpty) 'address': address,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        if (email != null && email!.isNotEmpty) 'email': email,
      };
}

class ApiClient {
  final Dio _dio;
  final String _defaultBaseUrl;

  ApiClient(this._dio) : _defaultBaseUrl = _dio.options.baseUrl;

  /// Update the base URL at runtime (used when switching to a phone server).
  void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }

  /// Restore the URL configured when the Dio client was created. This keeps
  /// the app's compile-time API_URL (or the production default) authoritative
  /// after a user clears a custom backend override.
  void resetBaseUrl() {
    _dio.options.baseUrl = _defaultBaseUrl;
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

  Future<Map<String, dynamic>> loginWithGoogle({
    required String idToken,
    required String tenantSlug,
    String? deviceId,
    String? branchId,
  }) async {
    final response = await _dio.post('/auth/login/google', data: {
      'idToken': idToken,
      'tenantSlug': tenantSlug,
      if (deviceId != null) 'deviceId': deviceId,
      if (branchId != null) 'branchId': branchId,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> createWorkspaceWithGoogle({
    required String idToken,
    required WorkspaceCreationRequest workspace,
  }) async {
    final response = await _dio.post('/auth/workspaces/google', data: {
      ...workspace.toJson(),
      'idToken': idToken,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> requestWorkspaceEmailOtp({
    required String email,
  }) async {
    final response = await _dio.post('/auth/workspaces/email-otp', data: {
      'email': email,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createWorkspaceWithEmailOtp({
    required String email,
    required String challengeId,
    required String code,
    required WorkspaceCreationRequest workspace,
  }) async {
    final response = await _dio.post('/auth/workspaces/email', data: {
      ...workspace.toJson(),
      'email': email,
      'challengeId': challengeId,
      'code': code,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getTenantOnboarding() async {
    final response = await _dio.get('/tenant-onboarding');
    return response.data as Map<String, dynamic>;
  }

  /// Record an owner acceptance for the current version of a Counterbase policy.
  /// The server rejects unknown or stale versions.
  Future<Map<String, dynamic>> acceptLegalPolicy({
    required String policyType,
    required String policyVersion,
  }) async {
    final response = await _dio.post('/legal/acceptances', data: {
      'policyType': policyType,
      'policyVersion': policyVersion,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateTenantOnboardingStep({
    required String key,
    required String status,
  }) async {
    final response = await _dio.patch('/tenant-onboarding/steps/$key', data: {
      'status': status,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getStaffInvitations() async {
    final response = await _dio.get('/tenant-onboarding/staff-invitations');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createStaffInvitation({
    required String email,
    required String firstName,
    required String lastName,
    required String roleId,
    required String branchId,
  }) async {
    final response =
        await _dio.post('/tenant-onboarding/staff-invitations', data: {
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'roleId': roleId,
      'branchId': branchId,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> completeStaffInvitationCredentials({
    required String invitationId,
    required String setupToken,
    required String password,
    required String pin,
  }) async {
    final response = await _dio.post(
      '/tenant-onboarding/staff-invitations/$invitationId/complete-credentials',
      data: {
        'setupToken': setupToken,
        'password': password,
        'pin': pin,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> acceptStaffInvitation({
    required String invitationId,
    required String challengeId,
    required String code,
  }) async {
    final response = await _dio.post(
      '/tenant-onboarding/staff-invitations/$invitationId/accept',
      data: {
        'challengeId': challengeId,
        'code': code,
      },
    );
    return response.data as Map<String, dynamic>;
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

  Future<Map<String, dynamic>> getTenantActivationStatus() async {
    final response = await _dio.get('/tenant-activation/status');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> initializeTenantActivationPayment() async {
    final response = await _dio.post('/tenant-activation/paystack/initialize');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyTenantActivationPayment(
    String reference,
  ) async {
    final response = await _dio.get(
      '/tenant-activation/paystack/verify/${Uri.encodeComponent(reference)}',
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> initializePaystackSubscriptionPayment() async {
    final response = await _dio.post('/billing/paystack/initialize');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyPaystackSubscriptionPayment(
    String reference,
  ) async {
    final response = await _dio.get(
      '/billing/paystack/verify/${Uri.encodeComponent(reference)}',
    );
    return response.data as Map<String, dynamic>;
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

  Future<Map<String, dynamic>> assignUserRole(
      String userId, String roleId) async {
    final response =
        await _dio.post('/users/$userId/roles', data: {'roleId': roleId});
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> removeUserRole(
      String userId, String roleId) async {
    final response = await _dio.delete('/users/$userId/roles/$roleId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setUserPermissionOverride(
    String userId, {
    required String permissionKey,
    required bool grant,
    String? reason,
  }) async {
    final response =
        await _dio.post('/users/$userId/permission-overrides', data: {
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
    final response =
        await _dio.delete('/users/$userId/permission-overrides/$permissionKey');
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
  Future<Map<String, dynamic>> getAuditLog(
      {int page = 1, int limit = 50}) async {
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
    double? minPrice,
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
      if (minPrice != null) 'minPrice': minPrice,
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
    double? minPrice,
    bool clearMinPrice = false,
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
      if (clearMinPrice) 'minPrice': null else if (minPrice != null) 'minPrice': minPrice,
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
  Future<Map<String, dynamic>> voidSale(String saleId,
      {required String reason}) async {
    final response =
        await _dio.post('/sales/$saleId/void', data: {'reason': reason});
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
  Future<Map<String, dynamic>> createStockRequest(
      Map<String, dynamic> data) async {
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
    final response =
        await _dio.get('/inventory/stock-requests', queryParameters: {
      if (branchId != null) 'branchId': branchId,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (page != null) 'page': page,
      if (limit != null) 'limit': limit,
    });
    // The server answers with a paged envelope ({items, total, page, ...});
    // older builds returned a bare list. Accept both so the list never
    // fails with a type error.
    final data = response.data;
    if (data is List) return data;
    if (data is Map && data['items'] is List) {
      return List<dynamic>.from(data['items'] as List);
    }
    return const [];
  }

  Future<Map<String, dynamic>> getStockRequest(String id) async {
    final response = await _dio.get('/inventory/stock-requests/$id');
    return response.data;
  }

  Future<Map<String, dynamic>> updateStockRequest(
      String id, Map<String, dynamic> data) async {
    final response =
        await _dio.put('/inventory/stock-requests/$id', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> resolveStockRequest(
      String id, Map<String, dynamic> data) async {
    final response =
        await _dio.put('/inventory/stock-requests/$id/resolve', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> cancelStockRequest(
      String id, Map<String, dynamic> data) async {
    final response =
        await _dio.put('/inventory/stock-requests/$id/cancel', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> getStockRequestStats({String? branchId}) async {
    final response = await _dio
        .get('/inventory/stock-requests/stats/summary', queryParameters: {
      if (branchId != null) 'branchId': branchId,
    });
    return response.data;
  }

  // Payment endpoints
  Future<Map<String, dynamic>> getMerchantPayoutAccount() async {
    final response = await _dio.get('/merchant-payments/account');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> getMerchantPayoutBanks() async {
    final response = await _dio.get('/merchant-payments/banks');
    return (response.data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> configureMerchantPayout(
      Map<String, dynamic> data) async {
    final response = await _dio.post('/merchant-payments/account', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> startMerchantMpesaPayment(
      Map<String, dynamic> data) async {
    final response = await _dio.post('/merchant-payments/mpesa', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getMerchantMpesaStatus(String reference) async {
    final response = await _dio.get('/merchant-payments/mpesa/$reference');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> startMerchantReceivableMpesaPayment(
      Map<String, dynamic> data) async {
    final response =
        await _dio.post('/merchant-payments/receivables/mpesa', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> getRecentMerchantCharges() async {
    final response = await _dio.get('/merchant-payments/charges');
    return (response.data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> initiatePesaPalPayment(
      Map<String, dynamic> data) async {
    final response = await _dio.post('/payments/pesapal/initiate', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> initiateTouristTapPayment(
      Map<String, dynamic> data) async {
    final response =
        await _dio.post('/payments/touristtap/initiate', data: data);
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

  // Customer endpoints (cross-device sync)
  Future<Map<String, dynamic>> createCustomer(Map<String, dynamic> data) async {
    final response = await _dio.post('/customers', data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getCustomers() async {
    final response = await _dio.get('/customers');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> updateCustomer(
      String id, Map<String, dynamic> data) async {
    final response = await _dio.patch('/customers/$id', data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteCustomer(String id) async {
    await _dio.delete('/customers/$id');
  }

  Future<List<dynamic>> resolveSyncConflicts(
    List<Map<String, dynamic>> conflicts,
  ) async {
    final response =
        await _dio.post('/sync/conflicts/resolve', data: conflicts);
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

  Future<Map<String, dynamic>> getDailyProfitLoss(
      String branchId, String date) async {
    final response = await _dio.get('/reports/profit-loss/$branchId/$date');
    return response.data;
  }

  /// Shared query params for the reporting endpoints below: an explicit
  /// [startDate]/[endDate] pair takes precedence; otherwise falls back to
  /// backend-side [period] resolution (TODAY/THIS_WEEK/etc).
  Map<String, dynamic> _reportFilterParams({
    String? startDate,
    String? endDate,
    String? period,
    String? branchId,
  }) =>
      {
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        if (period != null) 'period': period,
        if (branchId != null) 'branchId': branchId,
      };

  /// `GET /reports/sales/trend` — one row per hour/day/week in the range.
  Future<List<dynamic>> getSalesTrendReport({
    String? startDate,
    String? endDate,
    String? period,
    String? branchId,
    String groupBy = 'DAY',
  }) async {
    final response = await _dio.get('/reports/sales/trend', queryParameters: {
      ..._reportFilterParams(
          startDate: startDate,
          endDate: endDate,
          period: period,
          branchId: branchId),
      'groupBy': groupBy,
    });
    return response.data as List<dynamic>;
  }

  /// `GET /reports/sales/summary` — totals for the range.
  Future<Map<String, dynamic>> getSalesSummaryReport({
    String? startDate,
    String? endDate,
    String? period,
    String? branchId,
  }) async {
    final response = await _dio.get('/reports/sales/summary',
        queryParameters: _reportFilterParams(
            startDate: startDate,
            endDate: endDate,
            period: period,
            branchId: branchId));
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> getCategorySalesReport({
    String? startDate,
    String? endDate,
    String? period,
    String? branchId,
  }) async {
    final response = await _dio.get('/reports/categories',
        queryParameters: _reportFilterParams(
            startDate: startDate,
            endDate: endDate,
            period: period,
            branchId: branchId));
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getCashierPerformanceReport({
    String? startDate,
    String? endDate,
    String? period,
    String? branchId,
  }) async {
    final response = await _dio.get('/reports/cashiers',
        queryParameters: _reportFilterParams(
            startDate: startDate,
            endDate: endDate,
            period: period,
            branchId: branchId));
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getPaymentMethodReport({
    String? startDate,
    String? endDate,
    String? period,
    String? branchId,
  }) async {
    final response = await _dio.get('/reports/payments',
        queryParameters: _reportFilterParams(
            startDate: startDate,
            endDate: endDate,
            period: period,
            branchId: branchId));
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getTopProductsReport({
    String? startDate,
    String? endDate,
    String? period,
    String? branchId,
    int? limit,
  }) async {
    final response = await _dio.get('/reports/products/top', queryParameters: {
      ..._reportFilterParams(
          startDate: startDate,
          endDate: endDate,
          period: period,
          branchId: branchId),
      if (limit != null) 'limit': limit,
    });
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getInventoryReportSummary({
    String? branchId,
  }) async {
    final response = await _dio.get('/reports/inventory', queryParameters: {
      if (branchId != null) 'branchId': branchId,
    });
    return response.data as Map<String, dynamic>;
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

  Future<Map<String, dynamic>> createSupplierInvoice(
      Map<String, dynamic> data) async {
    final response = await _dio.post('/suppliers/invoices', data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> recordSupplierPayment(
    String invoiceId,
    Map<String, dynamic> data,
  ) async {
    final response =
        await _dio.post('/suppliers/invoices/$invoiceId/payments', data: data);
    return response.data as Map<String, dynamic>;
  }

  // Finance endpoints
  Future<FinanceSnapshot> getFinanceOverview(String branchId) async {
    final response = await _dio.get(
      '/finance/overview',
      queryParameters: <String, dynamic>{'branchId': branchId},
    );
    return FinanceSnapshot.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<List<FinancePayable>> getFinancePayables(
    String branchId, {
    String? status,
  }) async {
    final response = await _dio.get(
      '/finance/payables',
      queryParameters: <String, dynamic>{
        'branchId': branchId,
        if (status != null) 'status': status,
      },
    );
    return (response.data as List)
        .map((value) =>
            FinancePayable.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  Future<List<RetailReceivable>> getRetailReceivables(
    String branchId, {
    String? status,
  }) async {
    final response = await _dio.get(
      '/finance/retail-receivables',
      queryParameters: <String, dynamic>{
        'branchId': branchId,
        if (status != null) 'status': status,
      },
    );
    return (response.data as List)
        .map((value) =>
            RetailReceivable.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  Future<ReceivablePayment> recordRetailReceivablePayment({
    required String receivableId,
    required String branchId,
    required double amount,
    required String method,
    String? reference,
    String? notes,
    String? offlineId,
  }) async {
    final response = await _dio.post(
      '/finance/retail-receivables/$receivableId/payments',
      data: <String, dynamic>{
        'branchId': branchId,
        'amount': amount,
        'method': method,
        if (reference != null) 'reference': reference,
        if (notes != null) 'notes': notes,
        if (offlineId != null) 'offlineId': offlineId,
      },
    );
    return ReceivablePayment.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  /// Splits one collection across several retail receivables in a single
  /// all-or-nothing request. [offlineId] makes retries idempotent.
  Future<void> recordRetailBulkPayment({
    required String branchId,
    required String method,
    required List<Map<String, dynamic>> allocations,
    String? reference,
    String? notes,
    String? offlineId,
  }) async {
    await _dio.post(
      '/finance/retail-receivables/bulk-payments',
      data: <String, dynamic>{
        'branchId': branchId,
        'method': method,
        'allocations': allocations,
        if (reference != null) 'reference': reference,
        if (notes != null) 'notes': notes,
        if (offlineId != null) 'offlineId': offlineId,
      },
    );
  }

  /// Splits one instalment from another shop across its open debts in a
  /// single all-or-nothing request. [offlineId] makes retries idempotent.
  Future<void> recordPeerBulkPayment({
    required String branchId,
    required String method,
    required List<Map<String, dynamic>> allocations,
    String? reference,
    String? notes,
    String? offlineId,
  }) async {
    await _dio.post(
      '/finance/peer-receivables/bulk-payments',
      data: <String, dynamic>{
        'branchId': branchId,
        'method': method,
        'allocations': allocations,
        if (reference != null) 'reference': reference,
        if (notes != null) 'notes': notes,
        if (offlineId != null) 'offlineId': offlineId,
      },
    );
  }

  Future<List<PeerDebtor>> getPeerDebtors() async {
    final response = await _dio.get('/finance/peer-debtors');
    return (response.data as List)
        .map((value) =>
            PeerDebtor.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  Future<PeerDebtor> createPeerDebtor({
    required String name,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) async {
    final response =
        await _dio.post('/finance/peer-debtors', data: <String, dynamic>{
      'name': name,
      if (contactName != null) 'contactName': contactName,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (address != null) 'address': address,
      if (notes != null) 'notes': notes,
    });
    return PeerDebtor.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<List<PeerReceivable>> getPeerReceivables(
    String branchId, {
    String? status,
  }) async {
    final response = await _dio.get(
      '/finance/peer-receivables',
      queryParameters: <String, dynamic>{
        'branchId': branchId,
        if (status != null) 'status': status,
      },
    );
    return (response.data as List)
        .map((value) =>
            PeerReceivable.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  Future<PeerReceivable> createPeerReceivable({
    required String branchId,
    required String debtorId,
    required String description,
    required double amount,
    String? dueDate,
    String? reference,
    String? offlineId,
  }) async {
    final response =
        await _dio.post('/finance/peer-receivables', data: <String, dynamic>{
      'branchId': branchId,
      'debtorId': debtorId,
      'description': description,
      'amount': amount,
      if (dueDate != null) 'dueDate': dueDate,
      if (reference != null) 'reference': reference,
      if (offlineId != null) 'offlineId': offlineId,
    });
    return PeerReceivable.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<ReceivablePayment> recordPeerReceivablePayment({
    required String receivableId,
    required String branchId,
    required double amount,
    required String method,
    String? reference,
    String? notes,
    String? offlineId,
  }) async {
    final response = await _dio.post(
      '/finance/peer-receivables/$receivableId/payments',
      data: <String, dynamic>{
        'branchId': branchId,
        'amount': amount,
        'method': method,
        if (reference != null) 'reference': reference,
        if (notes != null) 'notes': notes,
        if (offlineId != null) 'offlineId': offlineId,
      },
    );
    return ReceivablePayment.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  // Cash flow endpoints
  Future<Map<String, dynamic>> getCashFlowSettings(String branchId) async {
    final response = await _dio.get('/cash-flow/settings/$branchId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateCashFlowSettings(
      String branchId, String mode) async {
    final response =
        await _dio.put('/cash-flow/settings/$branchId', data: {'mode': mode});
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
    final response =
        await _dio.get('/cash-flow/ledger/$branchId', queryParameters: {
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
    final response =
        await _dio.post('/cash-flow/reconciliations/$branchId', data: {
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
    final response = await _dio
        .get('/cash-flow/reconciliations/$branchId', queryParameters: {
      if (page != null) 'page': page,
      if (limit != null) 'limit': limit,
    });
    return response.data as Map<String, dynamic>;
  }

  // ── End-of-day close (Z-report + cash count) ──

  /// The day's sales summary for a branch (total, transactions, payment
  /// split) — shown before closing so the user reviews the figures.
  Future<Map<String, dynamic>> getSalesDailySummary(
      String branchId, String date) async {
    final response = await _dio.get('/sales/summary/$branchId/$date');
    return response.data as Map<String, dynamic>;
  }

  /// The close for a day (or today if [date] omitted); null if not yet closed.
  Future<Map<String, dynamic>?> getDailyClose(String branchId,
      {String? date}) async {
    final response =
        await _dio.get('/sales/daily-close/$branchId', queryParameters: {
      if (date != null) 'date': date,
    });
    return response.data == null
        ? null
        : (response.data as Map<String, dynamic>);
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
    String? imageUrl,
    String? imageBase64,
    String? branchId,
  }) async {
    assert(imageUrl != null || imageBase64 != null);
    final response = await _dio.post(
      '/ai/receipts/scan',
      data: {
        if (imageBase64 != null) 'imageBase64': imageBase64,
        if (imageBase64 == null && imageUrl != null) 'imageUrl': imageUrl,
        if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
      },
      // Vision models take a while to read a long invoice.
      options: Options(receiveTimeout: const Duration(seconds: 90)),
    );
    return (response.data as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
  }

  // ── Notification inbox ────────────────────────────────────────────────

  /// The signed-in user's saved notifications, newest first, plus how many
  /// are still unread. `before` pages backwards (ISO date of the oldest
  /// item already loaded).
  Future<Map<String, dynamic>> getNotifications({
    int limit = 50,
    String? before,
  }) async {
    final response = await _dio.get('/notifications', queryParameters: {
      'limit': limit,
      if (before != null) 'before': before,
    });
    return (response.data as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
  }

  Future<void> markNotificationRead(String id) async {
    await _dio.post('/notifications/$id/read');
  }

  Future<void> markAllNotificationsRead() async {
    await _dio.post('/notifications/read-all');
  }

  // ── Trade partners (business-to-business) ─────────────────────────────

  Future<List<Map<String, dynamic>>> getTradePartners() async {
    final response = await _dio.get('/partners');
    final data =
        (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return ((data['partners'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> requestTradePartner({
    required String companyCode,
    String? message,
  }) async {
    final response = await _dio.post('/partners/requests', data: {
      'companyCode': companyCode,
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
    });
    return ((response.data as Map<String, dynamic>)['data'] as Map?)
            ?.cast<String, dynamic>() ??
        const {};
  }

  Future<void> acceptTradePartner(String id) async {
    await _dio.post('/partners/$id/accept');
  }

  Future<void> declineTradePartner(String id) async {
    await _dio.post('/partners/$id/decline');
  }

  Future<void> removeTradePartner(String id) async {
    await _dio.delete('/partners/$id');
  }

  Future<List<Map<String, dynamic>>> getPartnerMessages(
    String id, {
    String? after,
    int limit = 50,
  }) async {
    final response = await _dio.get('/partners/$id/messages', queryParameters: {
      'limit': limit,
      if (after != null) 'after': after,
    });
    final data =
        (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return ((data['messages'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> sendPartnerMessage(
      String id, String body) async {
    final response =
        await _dio.post('/partners/$id/messages', data: {'body': body});
    return ((response.data as Map<String, dynamic>)['data'] as Map)
        .cast<String, dynamic>();
  }

  /// Identifies a retail product from a photo (name, brand, category, size,
  /// barcode) so "Add product" can be pre-filled. Returns the backend's
  /// IdentifiedProduct shape; `identified: false` when it isn't a product.
  Future<Map<String, dynamic>> identifyProductImage({
    required String imageBase64,
    String? branchId,
  }) async {
    final response = await _dio.post(
      '/ai/products/identify',
      data: {
        'imageBase64': imageBase64,
        if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
      },
      options: Options(receiveTimeout: const Duration(seconds: 60)),
    );
    return (response.data as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
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
    return (response.data as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
  }

  /// Durable shop memories the AI recalls across sessions (owner
  /// preferences, policies, customer notes) — tenant-wide, shared by every
  /// staff member the same way the chat thread itself is shared. Backend
  /// only supports create/list/delete (no edit-in-place).
  Future<List<Map<String, dynamic>>> getAiMemories(
      {required String branchId}) async {
    final response =
        await _dio.get('/ai/memory', queryParameters: {'branchId': branchId});
    final data =
        (response.data as Map<String, dynamic>)['data'] as List<dynamic>;
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
    return (response.data as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
  }

  Future<void> deleteAiMemory(
      {required String id, required String branchId}) async {
    await _dio
        .post('/ai/memory/delete', data: {'id': id, 'branchId': branchId});
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
    return (response.data as Map<String, dynamic>)['data']
        as Map<String, dynamic>;
  }

  /// Called only by the device designated as the printer holder — claims
  /// and returns any pending jobs (oldest first) for this branch so it can
  /// print them one at a time.
  Future<List<Map<String, dynamic>>> claimPrintJobs(
      {required String deviceId}) async {
    final response =
        await _dio.post('/printing/jobs/claim', data: {'deviceId': deviceId});
    final data =
        (response.data as Map<String, dynamic>)['data'] as List<dynamic>;
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
  Future<List<Map<String, dynamic>>> getMyPrintJobs(
      {required String deviceId}) async {
    final response = await _dio
        .get('/printing/jobs/mine', queryParameters: {'deviceId': deviceId});
    final data =
        (response.data as Map<String, dynamic>)['data'] as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  Future<String?> getPrinterDevice() async {
    final response = await _dio.get('/printing/printer-device');
    final data =
        (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    return data['printerDeviceId'] as String?;
  }

  Future<void> setPrinterDevice(String? deviceId) async {
    await _dio.put('/printing/printer-device', data: {'deviceId': deviceId});
  }

  // ── Subscription endpoints ──────────────────────────────────────────

  /// Fetch the current subscription plan details.
  /// GET /api/v1/subscription/plan
  Future<Map<String, dynamic>> getSubscriptionPlan() async {
    final response = await _dio.get('/subscription/plan');
    return response.data as Map<String, dynamic>;
  }

  /// Change the subscription plan (upgrade/downgrade).
  ///
  /// The plan id is sent under BOTH `plan` and `planId` keys: the backend
  /// controller reads `@Body('plan')` while other callers historically sent
  /// `planId`, so sending both works regardless of which key is read.
  /// Ids must be uppercase (TRIAL/CORE/BUSINESS/ENTERPRISE) — the backend
  /// validates against `VALID_PLANS` without case normalization.
  /// POST /api/v1/subscription/change-plan
  Future<Map<String, dynamic>> changeSubscriptionPlan({
    required String planId,
  }) async {
    final response = await _dio.post('/subscription/change-plan', data: {
      'plan': planId,
      'planId': planId,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Fetch invoice history for the current tenant.
  /// GET /api/v1/subscription/invoices
  Future<List<dynamic>> getSubscriptionInvoices() async {
    final response = await _dio.get('/subscription/invoices');
    return response.data as List<dynamic>;
  }

  // ── Billing (recurring subscription billing) ───────────────────────

  /// Owner-level billing settings: auto-renew toggle and billing phone.
  /// GET /api/v1/billing/settings
  Future<Map<String, dynamic>> getBillingSettings() async {
    final response = await _dio.get('/billing/settings');
    return response.data as Map<String, dynamic>;
  }

  /// ADMIN: update auto-renew and/or the STK-pushed billing phone.
  /// PUT /api/v1/billing/settings
  Future<Map<String, dynamic>> updateBillingSettings({
    bool? autoRenewEnabled,
    String? billingPhone,
    String? autoRenewAuthorizationVersion,
  }) async {
    final response = await _dio.put('/billing/settings', data: {
      if (autoRenewEnabled != null) 'autoRenewEnabled': autoRenewEnabled,
      if (billingPhone != null) 'billingPhone': billingPhone,
      if (autoRenewAuthorizationVersion != null)
        'autoRenewAuthorizationVersion': autoRenewAuthorizationVersion,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Subscription invoice history for the current tenant.
  /// GET /api/v1/billing/invoices
  Future<List<dynamic>> getBillingInvoices() async {
    final response = await _dio.get('/billing/invoices');
    return response.data as List<dynamic>;
  }

  /// Signed, tenant-wide subscription entitlement snapshot (plan, status,
  /// paidUntil, daysRemaining, graceUntil, features, restrictedMode).
  /// GET /api/v1/billing/entitlement
  Future<Map<String, dynamic>> getBillingEntitlement() async {
    final response = await _dio.get('/billing/entitlement');
    return response.data as Map<String, dynamic>;
  }

  /// Signed offline token: base64url(payload).base64url(hmac-sha256).
  /// Cached by EntitlementService so the app can resolve its own status
  /// (ACTIVE / GRACE / RESTRICTED) with no network at all.
  /// GET /api/v1/billing/entitlement/offline
  Future<String> getBillingEntitlementOffline() async {
    final response = await _dio.get('/billing/entitlement/offline');
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return (data['token'] ?? data['entitlement'])?.toString() ?? '';
    }
    return data?.toString() ?? '';
  }

  // ── Bug Report ────────────────────────────────────────────────────

  /// Submit a bug report that creates a Huly issue.
  /// POST /api/v1/bug-report (multipart/form-data for file attachments).
  Future<Map<String, dynamic>> submitBugReport({
    required String title,
    required String description,
    required String severity,
    String? component,
    File? attachment,
  }) async {
    final formData = FormData();
    formData.fields.addAll([
      MapEntry('title', title),
      MapEntry('description', description),
      MapEntry('severity', severity),
      if (component != null) MapEntry('component', component),
    ]);
    if (attachment != null) {
      final fileName = attachment.path.split('/').last;
      final mime = _mimeTypeForFile(fileName);
      formData.files.add(
        MapEntry(
          'attachment',
          await MultipartFile.fromFile(attachment.path,
              filename: fileName, contentType: DioMediaType.parse(mime)),
        ),
      );
    }
    final response = await _dio.post('/bug-report', data: formData);
    return response.data as Map<String, dynamic>;
  }

  // ── Shop control: accountability, stock counts, containers, news ──────

  /// The API wraps payloads as {success, data}; older responses are bare.
  Map<String, dynamic> _payload(Response<dynamic> response) {
    final body = response.data;
    if (body is Map && body['data'] is Map) {
      return (body['data'] as Map).cast<String, dynamic>();
    }
    if (body is Map) return body.cast<String, dynamic>();
    return const {};
  }

  List<Map<String, dynamic>> _payloadList(Response<dynamic> response) {
    final body = response.data;
    final raw = body is Map && body['data'] is List
        ? body['data'] as List
        : body is List
            ? body
            : const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> getTillRules() async =>
      _payload(await _dio.get('/accountability/till-rules'));

  Future<Map<String, dynamic>> getAccountabilitySettings() async =>
      _payload(await _dio.get('/accountability/settings'));

  Future<Map<String, dynamic>> updateAccountabilitySettings(
          Map<String, dynamic> patch) async =>
      _payload(await _dio.put('/accountability/settings', data: patch));

  Future<Map<String, dynamic>> getAccountabilityAlerts({
    bool openOnly = false,
    String? severity,
    int page = 1,
    int limit = 30,
  }) async =>
      _payload(await _dio.get('/accountability/alerts', queryParameters: {
        if (openOnly) 'open': true,
        if (severity != null) 'severity': severity,
        'page': page,
        'limit': limit,
      }));

  Future<void> acknowledgeAccountabilityAlerts(
      {List<String>? ids, bool all = false}) async {
    await _dio.post('/accountability/alerts/acknowledge', data: {
      if (all) 'all': true else 'ids': ids ?? const <String>[],
    });
  }

  Future<Map<String, dynamic>> getBranchDaySummary(String branchId,
          {String? date}) async =>
      _payload(await _dio.get('/accountability/summary', queryParameters: {
        'branchId': branchId,
        if (date != null) 'date': date,
      }));

  Future<Map<String, dynamic>> getCustomerCredit(String customerId) async =>
      _payload(await _dio.get('/customers/$customerId/credit'));

  // Stock counts
  Future<List<Map<String, dynamic>>> getStockCounts({String? branchId}) async =>
      _payloadList(await _dio.get('/stocktake', queryParameters: {
        if (branchId != null) 'branchId': branchId,
      }));

  Future<Map<String, dynamic>> startStockCount({
    required String branchId,
    String? title,
    bool blind = true,
    String? categoryId,
  }) async =>
      _payload(await _dio.post('/stocktake', data: {
        'branchId': branchId,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        'blind': blind,
        if (categoryId != null) 'categoryId': categoryId,
      }));

  Future<Map<String, dynamic>> getStockCount(String id) async =>
      _payload(await _dio.get('/stocktake/$id'));

  Future<Map<String, dynamic>> getStockCountReport(String id) async =>
      _payload(await _dio.get('/stocktake/$id/report'));

  Future<void> recordStockCounts(
      String id, List<Map<String, dynamic>> entries) async {
    await _dio.post('/stocktake/$id/counts', data: {'entries': entries});
  }

  Future<Map<String, dynamic>> submitStockCount(String id) async =>
      _payload(await _dio.post('/stocktake/$id/submit'));

  Future<Map<String, dynamic>> approveStockCount(String id,
          {String? notes}) async =>
      _payload(await _dio.post('/stocktake/$id/approve',
          data: {if (notes != null && notes.isNotEmpty) 'notes': notes}));

  Future<void> cancelStockCount(String id) async {
    await _dio.post('/stocktake/$id/cancel');
  }

  // Containers / imports
  Future<List<Map<String, dynamic>>> getImports() async =>
      _payloadList(await _dio.get('/imports'));

  Future<Map<String, dynamic>> getImport(String id) async =>
      _payload(await _dio.get('/imports/$id'));

  Future<Map<String, dynamic>> createImport(Map<String, dynamic> body) async =>
      _payload(await _dio.post('/imports', data: body));

  Future<Map<String, dynamic>> updateImport(
          String id, Map<String, dynamic> body) async =>
      _payload(await _dio.patch('/imports/$id', data: body));

  Future<Map<String, dynamic>> addImportParticipant(
          String id, Map<String, dynamic> body) async =>
      _payload(await _dio.post('/imports/$id/participants', data: body));

  Future<Map<String, dynamic>> removeImportParticipant(
          String id, String participantId) async =>
      _payload(await _dio.delete('/imports/$id/participants/$participantId'));

  Future<Map<String, dynamic>> addImportItem(
          String id, Map<String, dynamic> body) async =>
      _payload(await _dio.post('/imports/$id/items', data: body));

  Future<Map<String, dynamic>> removeImportItem(
          String id, String itemId) async =>
      _payload(await _dio.delete('/imports/$id/items/$itemId'));

  Future<Map<String, dynamic>> addImportCost(
          String id, Map<String, dynamic> body) async =>
      _payload(await _dio.post('/imports/$id/costs', data: body));

  Future<Map<String, dynamic>> removeImportCost(
          String id, String costId) async =>
      _payload(await _dio.delete('/imports/$id/costs/$costId'));

  Future<Map<String, dynamic>> recordImportPayment(
          String id, Map<String, dynamic> body) async =>
      _payload(await _dio.post('/imports/$id/payments', data: body));

  Future<Map<String, dynamic>> removeImportPayment(
          String id, String paymentId) async =>
      _payload(await _dio.delete('/imports/$id/payments/$paymentId'));

  Future<Map<String, dynamic>> receiveImport(String id,
          {List<Map<String, dynamic>>? items}) async =>
      _payload(await _dio.post('/imports/$id/receive',
          data: {if (items != null) 'items': items}));

  // Market: news and exchange rates
  Future<Map<String, dynamic>> getBusinessNews({
    String? category,
    String? impact,
    String? query,
    int page = 1,
    int limit = 20,
  }) async =>
      _payload(await _dio.get('/market/news', queryParameters: {
        if (category != null) 'category': category,
        if (impact != null) 'impact': impact,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'page': page,
        'limit': limit,
      }));

  Future<Map<String, dynamic>> getBusinessNewsDigest() async =>
      _payload(await _dio.get('/market/news/digest'));

  Future<Map<String, dynamic>> getBusinessNewsSources() async =>
      _payload(await _dio.get('/market/news/sources'));

  Future<Map<String, dynamic>> getExchangeRates() async =>
      _payload(await _dio.get('/market/rates'));

  // ── Coupons, referrals, statements, M-Pesa matching ───────────────────

  Future<Map<String, dynamic>> getTillCoupons() async =>
      _payload(await _dio.get('/coupons/till'));

  Future<List<Map<String, dynamic>>> getCoupons() async =>
      _payloadList(await _dio.get('/coupons'));

  Future<Map<String, dynamic>> getCouponReport({int days = 30}) async =>
      _payload(await _dio.get('/coupons/report', queryParameters: {'days': days}));

  Future<Map<String, dynamic>> createCoupon(Map<String, dynamic> body) async =>
      _payload(await _dio.post('/coupons', data: body));

  Future<Map<String, dynamic>> updateCoupon(
          String id, Map<String, dynamic> body) async =>
      _payload(await _dio.patch('/coupons/$id', data: body));

  Future<Map<String, dynamic>> deleteCoupon(String id) async =>
      _payload(await _dio.delete('/coupons/$id'));

  Future<Map<String, dynamic>> getReferralSummary() async =>
      _payload(await _dio.get('/referrals/me'));

  Future<Map<String, dynamic>> redeemCode(String code) async =>
      _payload(await _dio.post('/referrals/redeem', data: {'code': code}));

  Future<Map<String, dynamic>> getStatementSettings() async =>
      _payload(await _dio.get('/statements/settings'));

  Future<Map<String, dynamic>> updateStatementSettings(
          Map<String, dynamic> body) async =>
      _payload(await _dio.put('/statements/settings', data: body));

  Future<Map<String, dynamic>> previewStatement(
          {String? customerId, String? debtorId}) async =>
      _payload(await _dio.get('/statements/preview', queryParameters: {
        if (customerId != null) 'customerId': customerId,
        if (debtorId != null) 'debtorId': debtorId,
      }));

  Future<Map<String, dynamic>> createStatementLink({
    String? customerId,
    String? debtorId,
    String? message,
    int? days,
  }) async =>
      _payload(await _dio.post('/statements/links', data: {
        if (customerId != null) 'customerId': customerId,
        if (debtorId != null) 'debtorId': debtorId,
        if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
        if (days != null) 'days': days,
      }));

  Future<List<Map<String, dynamic>>> getStatementLinks(
          {String? customerId, String? debtorId}) async =>
      _payloadList(await _dio.get('/statements/links', queryParameters: {
        if (customerId != null) 'customerId': customerId,
        if (debtorId != null) 'debtorId': debtorId,
      }));

  Future<void> revokeStatementLink(String id) async {
    await _dio.post('/statements/links/$id/revoke');
  }

  Future<List<Map<String, dynamic>>> getStatementClaims({String? status}) async =>
      _payloadList(await _dio.get('/statements/claims', queryParameters: {
        if (status != null) 'status': status,
      }));

  Future<Map<String, dynamic>> decideStatementClaim(String id,
          {required bool confirm, double? amount}) async =>
      _payload(await _dio.post('/statements/claims/$id/decide', data: {
        'action': confirm ? 'CONFIRM' : 'REJECT',
        if (amount != null) 'amount': amount,
      }));

  /// The server's address without the /api/v1 part: public pages such as the
  /// statement link live there (https://host/s/TOKEN), outside the API prefix.
  String absoluteUrl(String path) {
    final base = baseUrl;
    final apiAt = base.indexOf('/api/');
    final origin = (apiAt > 0 ? base.substring(0, apiAt) : base)
        .replaceAll(RegExp(r'/+$'), '');
    return '$origin$path';
  }

  /// Downloads a statement PDF from its public link. No sign-in needed.
  Future<List<int>> downloadStatementPdf(String path, {String lang = 'en'}) async {
    final response = await _dio.get<List<int>>(
      absoluteUrl('$path/pdf'),
      queryParameters: {'lang': lang},
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  }

  Future<Map<String, dynamic>> parseMpesaMessages(String text) async =>
      _payload(await _dio.post('/mpesa/parse', data: {'text': text}));

  Future<Map<String, dynamic>> applyMpesaPayments(
          List<Map<String, dynamic>> items) async =>
      _payload(await _dio.post('/mpesa/apply', data: {'items': items}));

  Future<Map<String, dynamic>> ignoreMpesaPayments(
          List<Map<String, dynamic>> items) async =>
      _payload(await _dio.post('/mpesa/ignore', data: {'items': items}));

  Future<List<Map<String, dynamic>>> getMpesaHistory() async =>
      _payloadList(await _dio.get('/mpesa/history'));

  String _mimeTypeForFile(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    return 'application/octet-stream';
  }
}
