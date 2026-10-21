import 'api_client.dart';
import 'models.dart';

/// The single place that knows the platform-admin endpoint paths. Screens call
/// these typed methods and never build URLs themselves.
///
/// Every method hits the live Counterbase API. Mutations throw [ApiException]
/// on failure (including 403 when the staff member's role forbids it).
class AcaRepository {
  AcaRepository(this._api);
  final AcaApi _api;

  /// Escape hatch for feature code that needs an endpoint not wrapped above.
  /// Prefer adding a typed method here; never hard-code a server URL elsewhere.
  AcaApi get api => _api;

  // ----------------------------------------------------------------- overview
  Future<Overview> overview() async => Overview.fromJson(await _api.getMap('/overview'));

  // ------------------------------------------------------------------ tenants
  Future<Paged<TenantSummary>> tenants({String? search, String? status, int page = 1, int pageSize = 20}) async {
    final j = await _api.getMap('/tenants', query: {
      'search': search,
      'status': status,
      'page': page,
      'pageSize': pageSize,
    });
    return Paged.fromJson(j, TenantSummary.fromJson);
  }

  Future<TenantDetail> tenant(String id) async => TenantDetail.fromJson(await _api.getMap('/tenants/$id'));

  /// Pushes the subscription end date forward by [days] (1–365). Returns the new end date.
  Future<DateTime?> extendTenant(String id, int days) async {
    final j = await _api.postMap('/tenants/$id/extend', body: {'days': days});
    return J.d(j['currentPeriodEnd']);
  }

  Future<void> suspendTenant(String id) => _api.post('/tenants/$id/suspend');
  Future<void> reactivateTenant(String id) => _api.post('/tenants/$id/reactivate');

  /// Goodwill credit; [amountKes] is positive (the API stores it as a negative paid invoice).
  Future<void> creditTenant(String id, {required num amountKes, required String reason}) =>
      _api.post('/tenants/$id/credit', body: {'amountKes': amountKes, 'reason': reason});

  /// Raw licence view (plan, enforcement, features, limits, key...). See backend `license.catalog.ts`.
  Future<Map<String, dynamic>> license(String id) => _api.getMap('/tenants/$id/license');

  /// PATCH-style update; send only the fields that change. See `UpdateTenantLicenseDto`.
  Future<Map<String, dynamic>> updateLicense(String id, Map<String, dynamic> patch) async {
    final r = await _api.put('/tenants/$id/license', body: patch);
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  Future<List<TenantUser>> tenantUsers(String id) async =>
      J.list((await _api.getMap('/tenants/$id/users'))['items']).map(TenantUser.fromJson).toList();

  Future<void> setTenantUserActive(String tenantId, String userId, {required bool active}) =>
      _api.post('/tenants/$tenantId/users/$userId/${active ? 'activate' : 'deactivate'}');

  /// Signs one company user out of every device. Returns how many sessions ended.
  Future<int> revokeTenantUserSessions(String tenantId, String userId) async =>
      J.i((await _api.postMap('/tenants/$tenantId/users/$userId/revoke-sessions'))['revoked']);

  /// Signs every user of the company out. Returns how many sessions ended.
  Future<int> forceTenantLogout(String tenantId) async =>
      J.i((await _api.postMap('/tenants/$tenantId/force-logout'))['revoked']);

  /// Emergency kill switch: blocks all sign-ins for the company and ends sessions.
  Future<void> lockTenantOut(String tenantId, {String? reason}) =>
      _api.post('/tenants/$tenantId/lockout', body: {if (reason != null && reason.isNotEmpty) 'reason': reason});

  Future<void> liftTenantLockout(String tenantId, {String? reason}) => _api
      .post('/tenants/$tenantId/lockout/lift', body: {if (reason != null && reason.isNotEmpty) 'reason': reason});

  Future<List<TenantDevice>> tenantDevices(String id) async =>
      J.list((await _api.getMap('/tenants/$id/devices'))['items']).map(TenantDevice.fromJson).toList();

  Future<List<TenantNote>> tenantNotes(String id) async =>
      J.list((await _api.getMap('/tenants/$id/notes'))['items']).map(TenantNote.fromJson).toList();

  Future<TenantNote> addTenantNote(String id, String body, {bool pinned = false}) async =>
      TenantNote.fromJson(await _api.postMap('/tenants/$id/notes', body: {'body': body, 'pinned': pinned}));

  Future<void> deleteTenantNote(String tenantId, String noteId) => _api.delete('/tenants/$tenantId/notes/$noteId');

  // ------------------------------------------------------------------ billing
  Future<Paged<Invoice>> invoices({String? status, String? tenantId, int page = 1, int pageSize = 20}) async {
    final j = await _api.getMap('/invoices', query: {
      'status': status,
      'tenantId': tenantId,
      'page': page,
      'pageSize': pageSize,
    });
    return Paged.fromJson(j, Invoice.fromJson);
  }

  /// Manual M-Pesa payment claims awaiting reconciliation, across all companies.
  Future<List<Claim>> pendingClaims() async =>
      J.list((await _api.getMap('/claims'))['items']).map(Claim.fromJson).toList();

  /// Marks a PENDING invoice PAID. Passing an M-Pesa code also reactivates a
  /// PAST_DUE/SUSPENDED company.
  Future<void> markInvoicePaid(String invoiceId, {String? mpesaCode}) => _api.post(
        '/invoices/$invoiceId/mark-paid',
        body: {if (mpesaCode != null && mpesaCode.trim().isNotEmpty) 'mpesaCode': mpesaCode.trim()},
      );

  // --------------------------------------------------------------------- team
  Future<List<StaffMember>> team() async =>
      J.list((await _api.getMap('/team'))['items']).map(StaffMember.fromJson).toList();

  Future<StaffMember> staff(String id) async => StaffMember.fromJson(await _api.getMap('/team/$id'));

  Future<List<RoleInfo>> roles() async =>
      J.list((await _api.getMap('/team/roles'))['roles']).map(RoleInfo.fromJson).toList();

  /// Adds a staff member. The returned temporary password is shown ONCE; they must change it on first sign-in.
  Future<TempCredential> createStaff({
    required String email,
    required String name,
    required String role,
    String? phone,
  }) async {
    final j = await _api.postMap('/team', body: {
      'email': email,
      'name': name,
      'role': role,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    });
    return TempCredential(email: email, temporaryPassword: J.s(j['temporaryPassword']));
  }

  Future<void> updateStaff(String id, {String? name, String? role, String? status, String? phone}) => _api.patch(
        '/team/$id',
        body: {
          'name': ?name,
          'role': ?role,
          'status': ?status,
          'phone': ?phone,
        },
      );

  /// New one-time temporary password; also unlocks the account and signs it out everywhere.
  Future<TempCredential> resetStaffPassword(String id, {required String email}) async {
    final j = await _api.postMap('/team/$id/reset-password');
    return TempCredential(email: email, temporaryPassword: J.s(j['temporaryPassword']));
  }

  Future<void> unlockStaff(String id) => _api.post('/team/$id/unlock');

  Future<List<SessionInfo>> staffSessions(String id) async =>
      J.list((await _api.getMap('/team/$id/sessions'))['items']).map(SessionInfo.fromJson).toList();

  Future<int> revokeStaffSessions(String id) async =>
      J.i((await _api.postMap('/team/$id/revoke-sessions'))['revoked']);

  // ----------------------------------------------------------------- security
  Future<SecurityOverview> securityOverview() async =>
      SecurityOverview.fromJson(await _api.getMap('/security/overview'));

  Future<Paged<AuditEntry>> audit({
    String? category,
    String? severity,
    String? actorId,
    String? tenantId,
    String? search,
    String? since,
    int page = 1,
    int pageSize = 30,
  }) async {
    final j = await _api.getMap('/audit', query: {
      'category': category,
      'severity': severity,
      'actorId': actorId,
      'tenantId': tenantId,
      'search': search,
      'since': since,
      'page': page,
      'pageSize': pageSize,
    });
    return Paged.fromJson(j, AuditEntry.fromJson);
  }

  // ------------------------------------------------------------------ account
  Future<List<SessionInfo>> mySessions() async =>
      J.list((await _api.getMap('/auth/sessions'))['items']).map(SessionInfo.fromJson).toList();

  Future<void> revokeMySession(String sessionId) => _api.delete('/auth/sessions/$sessionId');

  /// Signs out every other device. Returns how many were signed out.
  Future<int> revokeMyOtherSessions() async =>
      J.i((await _api.postMap('/auth/sessions/revoke-others'))['revoked']);

  Future<void> changePassword({required String currentPassword, required String newPassword}) =>
      _api.post('/auth/change-password', body: {'currentPassword': currentPassword, 'newPassword': newPassword});

  Future<TwoFactorSetup> startTwoFactorSetup() async => TwoFactorSetup.fromJson(await _api.postMap('/auth/2fa/setup'));

  /// Confirms the first code; returns the one-time backup codes (shown once).
  Future<List<String>> enableTwoFactor(String code) async =>
      J.strings((await _api.postMap('/auth/2fa/enable', body: {'code': code}))['backupCodes']);

  Future<void> disableTwoFactor({required String password, required String code}) =>
      _api.post('/auth/2fa/disable', body: {'password': password, 'code': code});
}
