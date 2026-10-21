/// Permission keys. These mirror `backend/src/platform-admin/rbac/platform-permissions.ts`;
/// the server is the authority (it enforces every call). The app only uses the
/// list returned by `/auth/me` to decide what to show.
class Perm {
  Perm._();

  static const dashboardView = 'dashboard.view';
  static const tenantsView = 'tenants.view';
  static const tenantsManage = 'tenants.manage'; // extend subscription, notes
  static const tenantsSuspend = 'tenants.suspend'; // suspend / reactivate
  static const tenantsLicense = 'tenants.license';
  static const tenantsUsers = 'tenants.users'; // company staff accounts + devices
  static const tenantsSecurity = 'tenants.security'; // lock users, force logout, lockout
  static const billingView = 'billing.view';
  static const billingManage = 'billing.manage'; // mark paid, credits
  static const teamView = 'team.view';
  static const teamManage = 'team.manage';
  static const securityView = 'security.view';
  static const securityManage = 'security.manage';
  static const auditView = 'audit.view';
}

class Roles {
  Roles._();

  static const all = ['OWNER', 'ADMIN', 'SECURITY', 'FINANCE', 'SUPPORT', 'VIEWER'];
}
