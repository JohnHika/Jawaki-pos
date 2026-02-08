/// Role-based access control for Jawaki Adventures POS.
///
/// Hierarchy (higher inherits all lower permissions):
///   ADMIN > STORE_MANAGER > STOCK_KEEPER > SELLER
///
/// Seller         — POS, own sales, basic settings
/// Stock Keeper   — + Inventory, Products (view only), stock alerts
/// Store Manager  — + Products CRUD, reports, all sales, discounts, printer/sync/notif settings
/// Admin          — + User management, branches, financial reports, audit, data export, system settings

enum AppRole {
  seller,
  stockKeeper,
  storeManager,
  admin;

  /// The hierarchy level (higher = more permissions).
  int get level => switch (this) {
    AppRole.seller       => 0,
    AppRole.stockKeeper  => 1,
    AppRole.storeManager => 2,
    AppRole.admin        => 3,
  };

  /// Display label.
  String get label => switch (this) {
    AppRole.seller       => 'Seller',
    AppRole.stockKeeper  => 'Stock Keeper',
    AppRole.storeManager => 'Store Manager',
    AppRole.admin        => 'Admin',
  };

  /// Parse from the string stored in user map / database.
  static AppRole fromString(String? value) => switch (value?.toLowerCase()) {
    'admin'         => AppRole.admin,
    'store_manager' || 'storemanager' || 'manager' => AppRole.storeManager,
    'stock_keeper'  || 'stockkeeper'               => AppRole.stockKeeper,
    _               => AppRole.seller,
  };

  /// Returns true if this role is at least [other] in the hierarchy.
  bool isAtLeast(AppRole other) => level >= other.level;
}

/// Central permission definitions tied to roles.
class RolePermissions {
  final AppRole role;
  const RolePermissions(this.role);

  // ── Bottom-nav tabs ──────────────────────────
  bool get canSeePOS        => true; // everyone
  bool get canSeeDashboard  => role.isAtLeast(AppRole.storeManager);
  bool get canSeeProducts   => role.isAtLeast(AppRole.stockKeeper);
  bool get canSeeInventory  => role.isAtLeast(AppRole.stockKeeper);
  bool get canSeeReports    => role.isAtLeast(AppRole.storeManager);
  bool get canSeeSettings   => true; // everyone, but content differs

  // ── Product capabilities ─────────────────────
  /// Stock keepers can browse; managers+ can create/edit/delete.
  bool get canViewProducts  => role.isAtLeast(AppRole.stockKeeper);
  bool get canEditProducts  => role.isAtLeast(AppRole.storeManager);

  // ── Inventory ────────────────────────────────
  bool get canManageStock   => role.isAtLeast(AppRole.stockKeeper);

  // ── Sales ────────────────────────────────────
  bool get canMakeSales     => true;
  bool get canViewAllSales  => role.isAtLeast(AppRole.storeManager);
  bool get canVoidSales     => role.isAtLeast(AppRole.storeManager);
  bool get canApplyDiscount => role.isAtLeast(AppRole.storeManager);

  // ── Settings sections ────────────────────────
  bool get canConfigurePrinter      => role.isAtLeast(AppRole.storeManager);
  bool get canConfigureSync         => role.isAtLeast(AppRole.storeManager);
  bool get canConfigureNotifications => role.isAtLeast(AppRole.storeManager);
  bool get canChangePin             => true;
  bool get canConfigureSecurity     => true;
  bool get canSeeHelpSupport        => true;
  bool get canSeeAbout              => true;
  bool get canSeeAppearance         => true;

  // ── Admin-only ───────────────────────────────
  bool get canManageUsers           => role.isAtLeast(AppRole.admin);
  bool get canManageBranches        => role.isAtLeast(AppRole.admin);
  bool get canSeeFinancialReports   => role.isAtLeast(AppRole.admin);
  bool get canSeeAuditTrail         => role.isAtLeast(AppRole.admin);
  bool get canExportData            => role.isAtLeast(AppRole.admin);
  bool get canConfigureSystemSecurity => role.isAtLeast(AppRole.admin);
}
