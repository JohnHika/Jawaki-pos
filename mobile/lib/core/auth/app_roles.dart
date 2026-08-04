/// Role-based access control for Axon POS.
///
/// The backend is the real enforcement point: it computes each user's
/// effective permission set (union of assigned roles' permissions, plus
/// personal grants, minus personal revokes — see PermissionsService on the
/// backend) and returns it as `permissions: string[]` on login. This file
/// is a thin mobile-side reflection of that decision, not a second source
/// of truth — every getter here just checks membership in that set.
///
/// [AppRole] is kept only as a display concept (e.g. a "primary role" chip
/// in the UI) computed from the user's highest-privilege assigned role; it
/// no longer drives any access decision on its own.
library;

enum AppRole {
  seller,
  stockKeeper,
  storeManager,
  admin;

  /// Display label.
  String get label => switch (this) {
    AppRole.seller       => 'Seller',
    AppRole.stockKeeper  => 'Stock Keeper',
    AppRole.storeManager => 'Store Manager',
    AppRole.admin        => 'Admin',
  };

  /// Best-effort display role derived from a granular permission set —
  /// used only for a UI chip, never for gating. Highest tier wins.
  static AppRole fromPermissions(Set<String> permissions) {
    if (permissions.contains('roles.update') || permissions.contains('audit.read')) {
      return AppRole.admin;
    }
    if (permissions.contains('reporting.dashboard') || permissions.contains('products.create')) {
      return AppRole.storeManager;
    }
    if (permissions.contains('inventory.stock.adjust')) {
      return AppRole.stockKeeper;
    }
    return AppRole.seller;
  }

  /// Legacy string parse, kept for any code still passing the old
  /// LegacyUserRole string (e.g. before permissions are fetched).
  static AppRole fromString(String? value) => switch (value?.toLowerCase()) {
    'admin'         => AppRole.admin,
    'manager' || 'store_manager' || 'storemanager' => AppRole.storeManager,
    'supervisor' || 'stock_keeper' || 'stockkeeper' => AppRole.stockKeeper,
    _               => AppRole.seller,
  };
}

/// Thin reflector over the backend-computed effective permission set.
/// Getter names are preserved from the pre-granular-permissions version so
/// existing call sites across the app don't all need touching at once.
class RolePermissions {
  final Set<String> _permissions;
  final AppRole role;

  RolePermissions(List<dynamic>? permissions)
      : _permissions = (permissions ?? const []).map((e) => e.toString()).toSet(),
        role = AppRole.fromPermissions(
          (permissions ?? const []).map((e) => e.toString()).toSet(),
        );

  /// Escape hatch for raw key checks — used by the role editor / user
  /// permission override screens, which need every one of the ~130 keys,
  /// not just the fixed getters below.
  bool has(String key) => _permissions.contains(key);

  bool _any(List<String> keys) => keys.any(_permissions.contains);

  // ── Bottom-nav tabs ──────────────────────────
  bool get canSeePOS        => true; // everyone
  bool get canSeeDashboard  => has('reporting.dashboard');
  bool get canSeeProducts   => has('products.view');
  bool get canSeeInventory  => has('inventory.stock.view');
  bool get canSeeReports    => _any(['reporting.sales_summary', 'reporting.dashboard']);
  bool get canSeeSettings   => true; // everyone, but content differs

  // ── Product capabilities ─────────────────────
  bool get canViewProducts  => has('products.view');
  bool get canEditProducts  => has('products.update');

  // ── Inventory ────────────────────────────────
  bool get canManageStock   => has('inventory.stock.adjust');

  // ── Sales ────────────────────────────────────
  bool get canMakeSales     => has('sales.create');
  bool get canViewAllSales  => has('sales.view_all');
  bool get canVoidSales     => has('sales.void');
  bool get canApplyDiscount => has('sales.discount');

  // ── Settings sections ────────────────────────
  bool get canConfigurePrinter       => has('settings.printer_configure');
  bool get canConfigureSync          => has('settings.sync_configure');
  bool get canConfigureNotifications => has('settings.notifications_configure');
  bool get canChangePin              => true;
  bool get canConfigureSecurity      => has('settings.security_configure');
  bool get canSeeHelpSupport         => true;
  bool get canSeeAbout               => true;
  bool get canSeeAppearance          => true;

  // ── Admin-only ───────────────────────────────
  bool get canManageUsers             => has('users.view');
  bool get canManageBranches          => has('branches.create');
  bool get canSeeFinancialReports     => has('reporting.financial');
  bool get canSeeAuditTrail           => has('audit.read');
  bool get canExportData              => has('data.export');
  bool get canConfigureSystemSecurity => has('settings.system_security_configure');

  // ── Cash flow & restocking ───────────────────
  bool get canViewCashFlow   => has('cash_flow.settings_view');
  bool get canRecordRestock  => has('suppliers.invoices_create');
  bool get canReconcileCash  => has('cash_reconciliation.create');
  bool get canCloseEndOfDay  => has('sales.close_end_of_day');

  // ── Roles & permissions admin (new) ──────────
  bool get canManageRoles            => has('roles.view');
  bool get canAssignRoles            => has('permissions.assign_role');
  bool get canOverrideUserPermissions => has('permissions.override_user');
}
