/// Typed views of the Counterbase platform-admin API. Every field is parsed
/// defensively: the API serialises Prisma Decimals as strings and omits
/// nulls inconsistently, and a console must never crash on a missing field.
library;

class J {
  J._();

  static String s(dynamic v, [String fallback = '']) => v == null ? fallback : v.toString();
  static String? sn(dynamic v) => v?.toString();

  /// Accepts numbers and numeric strings (Prisma Decimal -> "3200").
  static num n(dynamic v, [num fallback = 0]) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? fallback;
    return fallback;
  }

  static num? nn(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static int i(dynamic v, [int fallback = 0]) => n(v, fallback).toInt();

  static bool b(dynamic v, [bool fallback = false]) {
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return fallback;
  }

  static DateTime? d(dynamic v) => v is String ? DateTime.tryParse(v) : null;

  static List<Map<String, dynamic>> list(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  static List<String> strings(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];

  static Map<String, dynamic> map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
}

/// A page of results from a paginated endpoint.
class Paged<T> {
  Paged({required this.items, required this.total, required this.page, required this.pageSize, required this.totalPages});

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  bool get hasMore => page < totalPages;

  factory Paged.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) parse) => Paged(
        items: J.list(j['items']).map(parse).toList(),
        total: J.i(j['total']),
        page: J.i(j['page'], 1),
        pageSize: J.i(j['pageSize'], 20),
        totalPages: J.i(j['totalPages'], 1),
      );
}

// ------------------------------------------------------------------ staff

/// The signed-in staff member (and the base of every team list row).
class StaffProfile {
  StaffProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.phone,
    required this.role,
    required this.status,
    required this.permissions,
    required this.mustChangePassword,
    required this.twoFactorEnabled,
    required this.lastLoginAt,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String name;
  final String? phone;
  final String role;
  final String status;
  final List<String> permissions;
  final bool mustChangePassword;
  final bool twoFactorEnabled;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;

  bool get isActive => status == 'ACTIVE';
  bool can(String permission) => permissions.contains(permission);

  factory StaffProfile.fromJson(Map<String, dynamic> j) => StaffProfile(
        id: J.s(j['id']),
        email: J.s(j['email']),
        name: J.s(j['name']),
        phone: J.sn(j['phone']),
        role: J.s(j['role'], 'VIEWER'),
        status: J.s(j['status'], 'ACTIVE'),
        permissions: J.strings(j['permissions']),
        mustChangePassword: J.b(j['mustChangePassword']),
        twoFactorEnabled: J.b(j['twoFactorEnabled']),
        lastLoginAt: J.d(j['lastLoginAt']),
        createdAt: J.d(j['createdAt']),
      );
}

/// A row on the Team screen: profile + live security state.
class StaffMember extends StaffProfile {
  StaffMember({
    required super.id,
    required super.email,
    required super.name,
    required super.phone,
    required super.role,
    required super.status,
    required super.permissions,
    required super.mustChangePassword,
    required super.twoFactorEnabled,
    required super.lastLoginAt,
    required super.createdAt,
    required this.locked,
    required this.lockedUntil,
    required this.failedLoginAttempts,
    required this.lastLoginIp,
    required this.activeSessions,
    this.passwordChangedAt,
    this.recentActivity = const [],
  });

  final bool locked;
  final DateTime? lockedUntil;
  final int failedLoginAttempts;
  final String? lastLoginIp;
  final int activeSessions;

  /// Only on the detail endpoint.
  final DateTime? passwordChangedAt;
  final List<AuditEntry> recentActivity;

  factory StaffMember.fromJson(Map<String, dynamic> j) {
    final p = StaffProfile.fromJson(j);
    return StaffMember(
      id: p.id,
      email: p.email,
      name: p.name,
      phone: p.phone,
      role: p.role,
      status: p.status,
      permissions: p.permissions,
      mustChangePassword: p.mustChangePassword,
      twoFactorEnabled: p.twoFactorEnabled,
      lastLoginAt: p.lastLoginAt,
      createdAt: p.createdAt,
      locked: J.b(j['locked']),
      lockedUntil: J.d(j['lockedUntil']),
      failedLoginAttempts: J.i(j['failedLoginAttempts']),
      lastLoginIp: J.sn(j['lastLoginIp']),
      activeSessions: J.i(j['activeSessions']),
      passwordChangedAt: J.d(j['passwordChangedAt']),
      recentActivity: J.list(j['recentActivity']).map(AuditEntry.fromJson).toList(),
    );
  }
}

class RoleInfo {
  RoleInfo({
    required this.role,
    required this.rank,
    required this.description,
    required this.permissions,
    required this.assignable,
  });

  final String role;
  final int rank;
  final String description;
  final List<String> permissions;

  /// Whether the signed-in staff member may hand this role out.
  final bool assignable;

  factory RoleInfo.fromJson(Map<String, dynamic> j) => RoleInfo(
        role: J.s(j['role']),
        rank: J.i(j['rank']),
        description: J.s(j['description']),
        permissions: J.strings(j['permissions']),
        assignable: J.b(j['assignable']),
      );
}

/// Result of creating a staff member or resetting a password: shown once.
class TempCredential {
  TempCredential({required this.email, required this.temporaryPassword});
  final String email;
  final String temporaryPassword;
}

class SessionInfo {
  SessionInfo({
    required this.id,
    required this.deviceLabel,
    required this.userAgent,
    required this.ipAddress,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
    required this.current,
  });

  final String id;
  final String? deviceLabel;
  final String? userAgent;
  final String? ipAddress;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
  final bool current;

  factory SessionInfo.fromJson(Map<String, dynamic> j) => SessionInfo(
        id: J.s(j['id']),
        deviceLabel: J.sn(j['deviceLabel']),
        userAgent: J.sn(j['userAgent']),
        ipAddress: J.sn(j['ipAddress']),
        createdAt: J.d(j['createdAt']),
        lastUsedAt: J.d(j['lastUsedAt']),
        expiresAt: J.d(j['expiresAt']),
        current: J.b(j['current']),
      );
}

class TwoFactorSetup {
  TwoFactorSetup({required this.secret, required this.otpauthUri});
  final String secret;
  final String otpauthUri;

  factory TwoFactorSetup.fromJson(Map<String, dynamic> j) =>
      TwoFactorSetup(secret: J.s(j['secret']), otpauthUri: J.s(j['otpauthUri']));
}

// --------------------------------------------------------------- overview

class OverviewTenant {
  OverviewTenant({
    required this.id,
    required this.name,
    required this.plan,
    required this.subscriptionStatus,
    required this.currentPeriodEnd,
    required this.daysLeft,
  });

  final String id;
  final String name;
  final String plan;
  final String? subscriptionStatus;
  final DateTime? currentPeriodEnd;
  final int? daysLeft;

  factory OverviewTenant.fromJson(Map<String, dynamic> j) => OverviewTenant(
        id: J.s(j['id']),
        name: J.s(j['name']),
        plan: J.s(j['plan']),
        subscriptionStatus: J.sn(j['subscriptionStatus']),
        currentPeriodEnd: J.d(j['currentPeriodEnd']),
        daysLeft: J.nn(j['daysLeft'])?.toInt(),
      );
}

class MonthRevenue {
  MonthRevenue({required this.month, required this.amountKes});
  final String month; // "2026-10"
  final num amountKes;

  factory MonthRevenue.fromJson(Map<String, dynamic> j) =>
      MonthRevenue(month: J.s(j['month']), amountKes: J.n(j['amountKes']));
}

class PaymentRow {
  PaymentRow({
    required this.id,
    required this.tenantId,
    required this.tenantName,
    required this.plan,
    required this.amount,
    required this.paidAt,
    required this.provider,
    required this.reference,
  });

  final String id;
  final String tenantId;
  final String tenantName;
  final String plan;
  final num amount;
  final DateTime? paidAt;
  final String? provider;
  final String? reference;

  factory PaymentRow.fromJson(Map<String, dynamic> j) => PaymentRow(
        id: J.s(j['id']),
        tenantId: J.s(j['tenantId']),
        tenantName: J.s(j['tenantName']),
        plan: J.s(j['plan']),
        amount: J.n(j['amount']),
        paidAt: J.d(j['paidAt']),
        provider: J.sn(j['provider']),
        reference: J.sn(j['reference']),
      );
}

class Overview {
  Overview({
    required this.generatedAt,
    required this.tenantTotal,
    required this.newTenants30,
    required this.byStatus,
    required this.byActivation,
    required this.mrrKes,
    required this.arrKes,
    required this.collected30,
    required this.collectedPrev30,
    required this.monthly,
    required this.pendingInvoices,
    required this.overdueInvoices,
    required this.pendingClaims,
    required this.recentPayments,
    required this.expiringSoon,
    required this.needsAttention,
    required this.devices,
    required this.devicesActive24h,
    required this.appVersions,
  });

  final DateTime? generatedAt;
  final int tenantTotal;
  final int newTenants30;
  final Map<String, int> byStatus; // ACTIVE, TRIAL, PAST_DUE, SUSPENDED, CANCELLED
  final Map<String, int> byActivation; // PAID, PENDING, ...
  final num mrrKes;
  final num arrKes;
  final num collected30;
  final num collectedPrev30;
  final List<MonthRevenue> monthly;
  final int pendingInvoices;
  final int overdueInvoices;
  final int pendingClaims;
  final List<PaymentRow> recentPayments;
  final List<OverviewTenant> expiringSoon;
  final List<OverviewTenant> needsAttention;
  final int devices;
  final int devicesActive24h;
  final Map<String, int> appVersions;

  /// Change vs the previous 30 days as a percentage; null when there is no baseline.
  double? get collectedChangePct =>
      collectedPrev30 > 0 ? ((collected30 - collectedPrev30) / collectedPrev30) * 100 : null;

  static Map<String, int> _counts(dynamic v) =>
      J.map(v).map((k, val) => MapEntry(k, J.i(val)));

  factory Overview.fromJson(Map<String, dynamic> j) {
    final tenants = J.map(j['tenants']);
    final revenue = J.map(j['revenue']);
    final billing = J.map(j['billing']);
    final fleet = J.map(j['fleet']);
    return Overview(
      generatedAt: J.d(j['generatedAt']),
      tenantTotal: J.i(tenants['total']),
      newTenants30: J.i(tenants['newLast30Days']),
      byStatus: _counts(tenants['byStatus']),
      byActivation: _counts(tenants['byActivation']),
      mrrKes: J.n(revenue['mrrKes']),
      arrKes: J.n(revenue['arrKes']),
      collected30: J.n(revenue['collectedLast30DaysKes']),
      collectedPrev30: J.n(revenue['collectedPrevious30DaysKes']),
      monthly: J.list(revenue['monthly']).map(MonthRevenue.fromJson).toList(),
      pendingInvoices: J.i(billing['pendingInvoices']),
      overdueInvoices: J.i(billing['overdueInvoices']),
      pendingClaims: J.i(billing['pendingClaims']),
      recentPayments: J.list(billing['recentPayments']).map(PaymentRow.fromJson).toList(),
      expiringSoon: J.list(j['expiringSoon']).map(OverviewTenant.fromJson).toList(),
      needsAttention: J.list(j['needsAttention']).map(OverviewTenant.fromJson).toList(),
      devices: J.i(fleet['devices']),
      devicesActive24h: J.i(fleet['activeLast24h']),
      appVersions: {
        for (final v in J.list(fleet['appVersions'])) J.s(v['version'], 'unknown'): J.i(v['devices']),
      },
    );
  }
}

// ---------------------------------------------------------------- tenants

class TenantSummary {
  TenantSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.plan,
    required this.subscriptionStatus,
    required this.currentPeriodEnd,
    required this.createdAt,
    required this.invoiceCount,
    required this.userCount,
    required this.branchCount,
    required this.isActive,
    required this.activationStatus,
  });

  final String id;
  final String name;
  final String slug;
  final String plan;
  final String? subscriptionStatus;
  final DateTime? currentPeriodEnd;
  final DateTime? createdAt;
  final int invoiceCount;
  final int userCount;
  final int branchCount;

  /// False when the company has been locked out (emergency kill switch).
  final bool isActive;
  final String? activationStatus;

  factory TenantSummary.fromJson(Map<String, dynamic> j) => TenantSummary(
        id: J.s(j['id']),
        name: J.s(j['name']),
        slug: J.s(j['slug']),
        plan: J.s(j['plan']),
        subscriptionStatus: J.sn(j['subscriptionStatus']),
        currentPeriodEnd: J.d(j['currentPeriodEnd']),
        createdAt: J.d(j['createdAt']),
        invoiceCount: J.i(j['invoiceCount']),
        userCount: J.i(j['userCount']),
        branchCount: J.i(j['branchCount']),
        isActive: J.b(j['isActive'], true),
        activationStatus: J.sn(j['activationStatus']),
      );
}

class TenantOwner {
  TenantOwner({required this.id, required this.email, required this.firstName, required this.lastName});
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  String get fullName => '$firstName $lastName'.trim();

  factory TenantOwner.fromJson(Map<String, dynamic> j) => TenantOwner(
        id: J.s(j['id']),
        email: J.s(j['email']),
        firstName: J.s(j['firstName']),
        lastName: J.s(j['lastName']),
      );
}

class TenantDetail {
  TenantDetail({
    required this.id,
    required this.name,
    required this.slug,
    required this.plan,
    required this.subscriptionStatus,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.maxBranches,
    required this.maxUsers,
    required this.autoRenewEnabled,
    required this.billingPhone,
    required this.activationStatus,
    required this.activationPaidAt,
    required this.setupFeePaidAt,
    required this.isActive,
    required this.subscriptionProvider,
    required this.createdAt,
    required this.owner,
    required this.branchCount,
    required this.userCount,
    required this.invoiceCount,
    required this.recentInvoices,
    required this.claims,
  });

  final String id;
  final String name;
  final String slug;
  final String plan;
  final String? subscriptionStatus;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final int maxBranches;
  final int maxUsers;
  final bool autoRenewEnabled;
  final String? billingPhone;
  final String? activationStatus;
  final DateTime? activationPaidAt;
  final DateTime? setupFeePaidAt;
  final bool isActive;
  final String? subscriptionProvider;
  final DateTime? createdAt;
  final TenantOwner? owner;
  final int branchCount;
  final int userCount;
  final int invoiceCount;
  final List<Invoice> recentInvoices;
  final List<Claim> claims;

  factory TenantDetail.fromJson(Map<String, dynamic> j) {
    final counts = J.map(j['counts']);
    final owner = j['owner'];
    return TenantDetail(
      id: J.s(j['id']),
      name: J.s(j['name']),
      slug: J.s(j['slug']),
      plan: J.s(j['plan']),
      subscriptionStatus: J.sn(j['subscriptionStatus']),
      currentPeriodStart: J.d(j['currentPeriodStart']),
      currentPeriodEnd: J.d(j['currentPeriodEnd']),
      maxBranches: J.i(j['maxBranches']),
      maxUsers: J.i(j['maxUsers']),
      autoRenewEnabled: J.b(j['autoRenewEnabled']),
      billingPhone: J.sn(j['billingPhone']),
      activationStatus: J.sn(j['activationStatus']),
      activationPaidAt: J.d(j['activationPaidAt']),
      setupFeePaidAt: J.d(j['setupFeePaidAt']),
      isActive: J.b(j['isActive'], true),
      subscriptionProvider: J.sn(j['subscriptionProvider']),
      createdAt: J.d(j['createdAt']),
      owner: owner is Map ? TenantOwner.fromJson(Map<String, dynamic>.from(owner)) : null,
      branchCount: J.i(counts['branches']),
      userCount: J.i(counts['users']),
      invoiceCount: J.i(counts['invoices']),
      recentInvoices: J.list(j['last5Invoices']).map(Invoice.fromJson).toList(),
      claims: J.list(j['claims']).map(Claim.fromJson).toList(),
    );
  }
}

class TenantUser {
  TenantUser({
    required this.id,
    required this.email,
    required this.phone,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.isActive,
    required this.lastLoginAt,
    required this.createdAt,
    required this.activeSessions,
  });

  final String id;
  final String email;
  final String? phone;
  final String firstName;
  final String lastName;
  final String role; // company role: ADMIN, MANAGER, SUPERVISOR, CASHIER
  final bool isActive;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
  final int activeSessions;
  String get fullName => '$firstName $lastName'.trim();

  factory TenantUser.fromJson(Map<String, dynamic> j) => TenantUser(
        id: J.s(j['id']),
        email: J.s(j['email']),
        phone: J.sn(j['phone']),
        firstName: J.s(j['firstName']),
        lastName: J.s(j['lastName']),
        role: J.s(j['role']),
        isActive: J.b(j['isActive'], true),
        lastLoginAt: J.d(j['lastLoginAt']),
        createdAt: J.d(j['createdAt']),
        activeSessions: J.i(j['activeSessions']),
      );
}

class TenantDevice {
  TenantDevice({
    required this.id,
    required this.name,
    required this.model,
    required this.osVersion,
    required this.appVersion,
    required this.lastSyncAt,
    required this.lastActiveAt,
    required this.isActive,
    required this.registeredAt,
    required this.branchId,
    required this.branchName,
  });

  final String id;
  final String name;
  final String? model;
  final String? osVersion;
  final String? appVersion;
  final DateTime? lastSyncAt;
  final DateTime? lastActiveAt;
  final bool isActive;
  final DateTime? registeredAt;
  final String branchId;
  final String branchName;

  factory TenantDevice.fromJson(Map<String, dynamic> j) => TenantDevice(
        id: J.s(j['id']),
        name: J.s(j['name']),
        model: J.sn(j['model']),
        osVersion: J.sn(j['osVersion']),
        appVersion: J.sn(j['appVersion']),
        lastSyncAt: J.d(j['lastSyncAt']),
        lastActiveAt: J.d(j['lastActiveAt']),
        isActive: J.b(j['isActive'], true),
        registeredAt: J.d(j['registeredAt']),
        branchId: J.s(j['branchId']),
        branchName: J.s(j['branchName']),
      );
}

class TenantNote {
  TenantNote({
    required this.id,
    required this.tenantId,
    required this.authorEmail,
    required this.body,
    required this.pinned,
    required this.createdAt,
  });

  final String id;
  final String tenantId;
  final String authorEmail;
  final String body;
  final bool pinned;
  final DateTime? createdAt;

  factory TenantNote.fromJson(Map<String, dynamic> j) => TenantNote(
        id: J.s(j['id']),
        tenantId: J.s(j['tenantId']),
        authorEmail: J.s(j['authorEmail']),
        body: J.s(j['body']),
        pinned: J.b(j['pinned']),
        createdAt: J.d(j['createdAt']),
      );
}

// ---------------------------------------------------------------- billing

class Invoice {
  Invoice({
    required this.id,
    required this.tenantId,
    required this.tenantName,
    required this.plan,
    required this.amount,
    required this.currency,
    required this.status,
    required this.provider,
    required this.reference,
    required this.periodStart,
    required this.periodEnd,
    required this.paidAt,
    required this.createdAt,
  });

  final String id;
  final String tenantId;
  final String? tenantName; // present on the cross-company list only
  final String plan;
  final num amount; // negative = goodwill credit
  final String currency;
  final String status; // PENDING | PAID
  final String? provider;
  final String? reference;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? paidAt;
  final DateTime? createdAt;

  bool get isPaid => status == 'PAID';
  bool get isCredit => amount < 0 || provider == 'CREDIT';

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: J.s(j['id']),
        tenantId: J.s(j['tenantId']),
        tenantName: J.sn(j['tenantName']),
        plan: J.s(j['plan']),
        amount: J.n(j['amount']),
        currency: J.s(j['currency'], 'KES'),
        status: J.s(j['status']),
        provider: J.sn(j['provider']),
        reference: J.sn(j['reference']),
        periodStart: J.d(j['periodStart']),
        periodEnd: J.d(j['periodEnd']),
        paidAt: J.d(j['paidAt']),
        createdAt: J.d(j['createdAt']),
      );
}

class Claim {
  Claim({
    required this.id,
    required this.tenantId,
    required this.tenantName,
    required this.invoiceId,
    required this.invoiceStatus,
    required this.plan,
    required this.mpesaCode,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
    required this.decidedAt,
  });

  final String id;
  final String tenantId;
  final String? tenantName; // list endpoint only
  final String invoiceId;
  final String? invoiceStatus; // list endpoint only
  final String? plan;
  final String mpesaCode;
  final num amount;
  final String currency;
  final String status; // PENDING | APPROVED | REJECTED
  final DateTime? createdAt;
  final DateTime? decidedAt;

  factory Claim.fromJson(Map<String, dynamic> j) => Claim(
        id: J.s(j['id']),
        tenantId: J.s(j['tenantId']),
        tenantName: J.sn(j['tenantName']),
        invoiceId: J.s(j['invoiceId']),
        invoiceStatus: J.sn(j['invoiceStatus']),
        plan: J.sn(j['plan']),
        mpesaCode: J.s(j['mpesaCode']),
        amount: J.n(j['amount']),
        currency: J.s(j['currency'], 'KES'),
        status: J.s(j['status'], 'PENDING'),
        createdAt: J.d(j['createdAt']),
        decidedAt: J.d(j['decidedAt']),
      );
}

// --------------------------------------------------------------- security

class AuditEntry {
  AuditEntry({
    required this.id,
    required this.actorId,
    required this.actorEmail,
    required this.actorRole,
    required this.action,
    required this.category,
    required this.severity,
    required this.targetType,
    required this.targetId,
    required this.tenantId,
    required this.summary,
    required this.metadata,
    required this.ipAddress,
    required this.userAgent,
    required this.createdAt,
  });

  final String id;
  final String? actorId;
  final String? actorEmail;
  final String? actorRole;
  final String action;
  final String category; // AUTH | TEAM | TENANT | BILLING | LICENSE | SECURITY
  final String severity; // INFO | WARN | CRITICAL
  final String? targetType;
  final String? targetId;
  final String? tenantId;
  final String? summary;
  final Map<String, dynamic> metadata;
  final String? ipAddress;
  final String? userAgent;
  final DateTime? createdAt;

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: J.s(j['id']),
        actorId: J.sn(j['actorId']),
        actorEmail: J.sn(j['actorEmail']),
        actorRole: J.sn(j['actorRole']),
        action: J.s(j['action']),
        category: J.s(j['category']),
        severity: J.s(j['severity'], 'INFO'),
        targetType: J.sn(j['targetType']),
        targetId: J.sn(j['targetId']),
        tenantId: J.sn(j['tenantId']),
        summary: J.sn(j['summary']),
        metadata: J.map(j['metadata']),
        ipAddress: J.sn(j['ipAddress']),
        userAgent: J.sn(j['userAgent']),
        createdAt: J.d(j['createdAt']),
      );
}

class LockedAccount {
  LockedAccount({required this.id, required this.email, required this.name, required this.role, required this.lockedUntil});
  final String id;
  final String email;
  final String name;
  final String role;
  final DateTime? lockedUntil;

  factory LockedAccount.fromJson(Map<String, dynamic> j) => LockedAccount(
        id: J.s(j['id']),
        email: J.s(j['email']),
        name: J.s(j['name']),
        role: J.s(j['role']),
        lockedUntil: J.d(j['lockedUntil']),
      );
}

class StaffRef {
  StaffRef({required this.id, required this.email, required this.name, required this.role});
  final String id;
  final String email;
  final String name;
  final String role;

  factory StaffRef.fromJson(Map<String, dynamic> j) => StaffRef(
        id: J.s(j['id']),
        email: J.s(j['email']),
        name: J.s(j['name']),
        role: J.s(j['role']),
      );
}

class SecurityOverview {
  SecurityOverview({
    required this.failedLogins24h,
    required this.successfulLogins24h,
    required this.critical7d,
    required this.warn7d,
    required this.activeSessions,
    required this.lockedAccounts,
    required this.activeStaff,
    required this.disabledStaff,
    required this.twoFactorCoveragePercent,
    required this.withoutTwoFactor,
    required this.topFailedIps,
    required this.recentEvents,
  });

  final int failedLogins24h;
  final int successfulLogins24h;
  final int critical7d;
  final int warn7d;
  final int activeSessions;
  final List<LockedAccount> lockedAccounts;
  final int activeStaff;
  final int disabledStaff;
  final int twoFactorCoveragePercent;
  final List<StaffRef> withoutTwoFactor;
  final Map<String, int> topFailedIps; // ip -> attempts
  final List<AuditEntry> recentEvents; // WARN + CRITICAL only

  factory SecurityOverview.fromJson(Map<String, dynamic> j) {
    final staff = J.map(j['staff']);
    return SecurityOverview(
      failedLogins24h: J.i(j['failedLogins24h']),
      successfulLogins24h: J.i(j['successfulLogins24h']),
      critical7d: J.i(j['critical7d']),
      warn7d: J.i(j['warn7d']),
      activeSessions: J.i(j['activeSessions']),
      lockedAccounts: J.list(j['lockedAccounts']).map(LockedAccount.fromJson).toList(),
      activeStaff: J.i(staff['active']),
      disabledStaff: J.i(staff['disabled']),
      twoFactorCoveragePercent: J.i(staff['twoFactorCoveragePercent']),
      withoutTwoFactor: J.list(staff['withoutTwoFactor']).map(StaffRef.fromJson).toList(),
      topFailedIps: {for (final r in J.list(j['topFailedIps'])) J.s(r['ip'], '?'): J.i(r['attempts'])},
      recentEvents: J.list(j['recentEvents']).map(AuditEntry.fromJson).toList(),
    );
  }
}
