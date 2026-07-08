import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

/**
 * Seeds the granular permission system:
 *   1. Upserts the full ~128-key Permission catalog (idempotent).
 *   2. For every tenant, creates 4 system Roles (Cashier/Supervisor/
 *      Manager/Admin) bundled with exactly the permissions each level
 *      implies today, so the seeded roles reproduce current access
 *      exactly — nothing changes for existing users on migration day.
 *   3. Backfills a UserRole join row for every existing user, mapping
 *      their legacy `role` enum value to the matching seeded Role.
 *
 * Safe to re-run: every step is an upsert / conditional create.
 *
 * Usage: npx ts-node scripts/seed-permissions.ts
 */

interface PermissionDef {
  key: string;
  feature: string;
  action: string;
  label: string;
}

// Source of truth for the permission catalog. Derived 1:1 from the
// existing @Roles()-gated endpoints (backend/src/**/*.controller.ts) plus
// first-time coverage for previously-ungated modules (expenses, suppliers,
// ai, ai-billing, app-updates, payments, sync, uploads).
const PERMISSIONS: PermissionDef[] = [
  // ---- audit ----
  { key: 'audit.read', feature: 'audit', action: 'read', label: 'View audit logs' },

  // ---- auth / users ----
  { key: 'users.view', feature: 'users', action: 'view', label: 'View tenant users' },
  { key: 'users.create', feature: 'users', action: 'create', label: 'Register new users' },
  { key: 'users.update', feature: 'users', action: 'update', label: 'Edit user details' },
  { key: 'users.deactivate', feature: 'users', action: 'deactivate', label: 'Deactivate users' },
  { key: 'users.reset_credentials', feature: 'users', action: 'reset_credentials', label: "Reset a user's password or PIN" },

  // ---- roles & permissions admin ----
  { key: 'roles.view', feature: 'roles', action: 'view', label: 'View roles' },
  { key: 'roles.create', feature: 'roles', action: 'create', label: 'Create roles' },
  { key: 'roles.update', feature: 'roles', action: 'update', label: 'Edit role permission bundles' },
  { key: 'roles.delete', feature: 'roles', action: 'delete', label: 'Delete roles' },
  { key: 'permissions.view_catalog', feature: 'permissions', action: 'view_catalog', label: 'View the permission catalog' },
  { key: 'permissions.assign_role', feature: 'permissions', action: 'assign_role', label: 'Assign or remove roles from a user' },
  { key: 'permissions.override_user', feature: 'permissions', action: 'override_user', label: 'Grant or revoke individual permissions for a user' },

  // ---- branches & tenant ----
  { key: 'branches.tenant.create', feature: 'branches', action: 'tenant_create', label: 'Create a new tenant' },
  { key: 'branches.tenant.update', feature: 'branches', action: 'tenant_update', label: 'Update tenant settings' },
  { key: 'branches.view', feature: 'branches', action: 'view', label: 'View branches' },
  { key: 'branches.create', feature: 'branches', action: 'create', label: 'Create branches' },
  { key: 'branches.update', feature: 'branches', action: 'update', label: 'Update branches' },
  { key: 'branches.delete', feature: 'branches', action: 'delete', label: 'Delete branches' },
  { key: 'branches.bulk', feature: 'branches', action: 'bulk', label: 'Bulk create/update/delete branches' },

  // ---- devices ----
  { key: 'devices.view', feature: 'devices', action: 'view', label: 'View registered devices' },
  { key: 'devices.create', feature: 'devices', action: 'create', label: 'Register a device' },
  { key: 'devices.update', feature: 'devices', action: 'update', label: 'Update a device' },
  { key: 'devices.delete', feature: 'devices', action: 'delete', label: 'Deactivate a device' },

  // ---- categories ----
  { key: 'categories.view', feature: 'categories', action: 'view', label: 'View categories' },
  { key: 'categories.create', feature: 'categories', action: 'create', label: 'Create categories' },
  { key: 'categories.update', feature: 'categories', action: 'update', label: 'Update categories' },
  { key: 'categories.delete', feature: 'categories', action: 'delete', label: 'Delete categories' },

  // ---- products ----
  { key: 'products.view', feature: 'products', action: 'view', label: 'View products' },
  { key: 'products.create', feature: 'products', action: 'create', label: 'Create products' },
  { key: 'products.update', feature: 'products', action: 'update', label: 'Update products' },
  { key: 'products.delete', feature: 'products', action: 'delete', label: 'Delete products' },
  { key: 'products.favorite', feature: 'products', action: 'favorite', label: 'Favorite/unfavorite a product' },
  { key: 'products.bulk', feature: 'products', action: 'bulk', label: 'Bulk create/update/delete products' },
  { key: 'products.view_all', feature: 'products', action: 'view_all', label: 'View full product catalog' },

  // ---- pricing ----
  { key: 'pricing.view', feature: 'pricing', action: 'view', label: 'View branch price overrides' },
  { key: 'pricing.set', feature: 'pricing', action: 'set', label: 'Set branch-specific pricing' },
  { key: 'pricing.delete', feature: 'pricing', action: 'delete', label: 'Remove branch-specific pricing' },

  // ---- inventory: stock ----
  { key: 'inventory.stock.view', feature: 'inventory', action: 'stock_view', label: 'View stock levels' },
  { key: 'inventory.stock.adjust', feature: 'inventory', action: 'stock_adjust', label: 'Adjust stock levels' },

  // ---- inventory: movements ----
  { key: 'inventory.movements.view', feature: 'inventory', action: 'movements_view', label: 'View stock movement history' },

  // ---- inventory: transfers ----
  { key: 'inventory.transfers.view', feature: 'inventory', action: 'transfers_view', label: 'View stock transfers' },
  { key: 'inventory.transfers.create', feature: 'inventory', action: 'transfers_create', label: 'Create stock transfers' },
  { key: 'inventory.transfers.send', feature: 'inventory', action: 'transfers_send', label: 'Send a pending transfer' },
  { key: 'inventory.transfers.receive', feature: 'inventory', action: 'transfers_receive', label: 'Receive a transfer' },

  // ---- inventory: batches ----
  { key: 'inventory.batches.view', feature: 'inventory', action: 'batches_view', label: 'View batch details' },
  { key: 'inventory.batches.receive', feature: 'inventory', action: 'batches_receive', label: 'Receive stock with batch tracking' },
  { key: 'inventory.batches.update', feature: 'inventory', action: 'batches_update', label: 'Update batch details' },
  { key: 'inventory.batches.fefo_view', feature: 'inventory', action: 'batches_fefo_view', label: 'View FEFO batch allocation' },

  // ---- inventory: expiry ----
  { key: 'inventory.expiry.dashboard', feature: 'inventory', action: 'expiry_dashboard', label: 'View expiry dashboard' },
  { key: 'inventory.expiry.block_expired', feature: 'inventory', action: 'expiry_block_expired', label: 'Auto-block expired batches' },

  // ---- inventory: stock requests ----
  { key: 'inventory.stock_requests.view', feature: 'inventory', action: 'stock_requests_view', label: 'View stock requests' },
  { key: 'inventory.stock_requests.create', feature: 'inventory', action: 'stock_requests_create', label: 'Create a stock request' },
  { key: 'inventory.stock_requests.update', feature: 'inventory', action: 'stock_requests_update', label: 'Edit a stock request' },
  { key: 'inventory.stock_requests.resolve', feature: 'inventory', action: 'stock_requests_resolve', label: 'Approve/reject/fulfill a stock request' },
  { key: 'inventory.stock_requests.cancel', feature: 'inventory', action: 'stock_requests_cancel', label: 'Cancel a stock request' },

  // ---- inventory: restock suggestions ----
  { key: 'inventory.restock_suggestions.view', feature: 'inventory', action: 'restock_suggestions_view', label: 'View AI restock suggestions' },

  // ---- sales ----
  { key: 'sales.create', feature: 'sales', action: 'create', label: 'Create a sale' },
  { key: 'sales.view', feature: 'sales', action: 'view', label: 'View sales' },
  { key: 'sales.view_all', feature: 'sales', action: 'view_all', label: 'View all sales across users' },
  { key: 'sales.void', feature: 'sales', action: 'void', label: 'Void a sale' },
  { key: 'sales.refund', feature: 'sales', action: 'refund', label: 'Create a refund' },
  { key: 'sales.discount', feature: 'sales', action: 'discount', label: 'Apply a manual discount' },
  { key: 'sales.bulk_create', feature: 'sales', action: 'bulk_create', label: 'Bulk create sales (offline sync)' },
  { key: 'sales.bulk_void', feature: 'sales', action: 'bulk_void', label: 'Bulk void sales' },

  // ---- customers ----
  { key: 'customers.view', feature: 'customers', action: 'view', label: 'View customers' },
  { key: 'customers.create', feature: 'customers', action: 'create', label: 'Create a customer' },
  { key: 'customers.update', feature: 'customers', action: 'update', label: 'Update a customer' },
  { key: 'customers.credit_view', feature: 'customers', action: 'credit_view', label: 'View outstanding credit sales' },

  // ---- suppliers ----
  { key: 'suppliers.view', feature: 'suppliers', action: 'view', label: 'View suppliers' },
  { key: 'suppliers.create', feature: 'suppliers', action: 'create', label: 'Create/update a supplier' },
  { key: 'suppliers.debts_view', feature: 'suppliers', action: 'debts_view', label: 'View supplier balances owed' },
  { key: 'suppliers.invoices_view', feature: 'suppliers', action: 'invoices_view', label: 'View supplier invoices' },
  { key: 'suppliers.invoices_create', feature: 'suppliers', action: 'invoices_create', label: 'Record a supplier invoice' },
  { key: 'suppliers.payments_record', feature: 'suppliers', action: 'payments_record', label: 'Record a supplier payment' },

  // ---- expenses ----
  { key: 'expenses.view', feature: 'expenses', action: 'view', label: 'View expenses' },
  { key: 'expenses.create', feature: 'expenses', action: 'create', label: 'Create an expense' },
  { key: 'expenses.update', feature: 'expenses', action: 'update', label: 'Update an expense' },
  { key: 'expenses.approve', feature: 'expenses', action: 'approve', label: 'Approve an expense' },
  { key: 'expenses.reject', feature: 'expenses', action: 'reject', label: 'Reject an expense' },
  { key: 'expenses.mark_paid', feature: 'expenses', action: 'mark_paid', label: 'Mark an expense as paid' },
  { key: 'expenses.delete', feature: 'expenses', action: 'delete', label: 'Delete an expense' },

  // ---- cash flow ----
  { key: 'cash_flow.settings_view', feature: 'cash_flow', action: 'settings_view', label: 'View branch cash flow settings' },
  { key: 'cash_flow.settings_update', feature: 'cash_flow', action: 'settings_update', label: 'Update branch cash flow mode' },
  { key: 'cash_ledger.view', feature: 'cash_ledger', action: 'view', label: 'View the cash ledger' },
  { key: 'cash_reconciliation.view', feature: 'cash_reconciliation', action: 'view', label: 'View cash reconciliation history' },
  { key: 'cash_reconciliation.create', feature: 'cash_reconciliation', action: 'create', label: 'Record a cash reconciliation' },

  // ---- reporting ----
  { key: 'reporting.dashboard', feature: 'reporting', action: 'dashboard', label: 'View the dashboard summary' },
  { key: 'reporting.sales_summary', feature: 'reporting', action: 'sales_summary', label: 'View sales summary reports' },
  { key: 'reporting.sales_trend', feature: 'reporting', action: 'sales_trend', label: 'View sales trend reports' },
  { key: 'reporting.top_products', feature: 'reporting', action: 'top_products', label: 'View top-selling products' },
  { key: 'reporting.category_sales', feature: 'reporting', action: 'category_sales', label: 'View sales by category' },
  { key: 'reporting.cashier_performance', feature: 'reporting', action: 'cashier_performance', label: 'View cashier performance' },
  { key: 'reporting.payment_breakdown', feature: 'reporting', action: 'payment_breakdown', label: 'View payment method breakdown' },
  { key: 'reporting.branch_comparison', feature: 'reporting', action: 'branch_comparison', label: 'View branch comparison' },
  { key: 'reporting.inventory_report', feature: 'reporting', action: 'inventory_report', label: 'View inventory reports' },
  { key: 'reporting.profit_loss', feature: 'reporting', action: 'profit_loss', label: 'View profit & loss reports' },

  // ---- branches financial reports / audit trail (mobile-facing bundles) ----
  { key: 'reporting.financial', feature: 'reporting', action: 'financial', label: 'View financial reports' },
  { key: 'reporting.export', feature: 'reporting', action: 'export', label: 'Export report data' },

  // ---- ai ----
  { key: 'ai.chat', feature: 'ai', action: 'chat', label: 'Use AI chat' },
  { key: 'ai.chat_web_enhanced', feature: 'ai', action: 'chat_web_enhanced', label: 'Use web-enhanced AI chat' },
  { key: 'ai.cognitive_analyze', feature: 'ai', action: 'cognitive_analyze', label: 'Run cognitive business analysis' },
  { key: 'ai.cognitive_monitor', feature: 'ai', action: 'cognitive_monitor', label: 'Run proactive AI monitoring' },
  { key: 'ai.cognitive_advisor', feature: 'ai', action: 'cognitive_advisor', label: 'Use the AI business advisor' },
  { key: 'ai.set_model', feature: 'ai', action: 'set_model', label: 'Change the active AI model' },

  // ---- ai billing ----
  { key: 'ai_billing.view_status', feature: 'ai_billing', action: 'view_status', label: 'View AI subscription status' },
  { key: 'ai_billing.submit_payment', feature: 'ai_billing', action: 'submit_payment', label: 'Submit an AI subscription payment' },
  { key: 'ai_billing.admin_view', feature: 'ai_billing', action: 'admin_view', label: 'View all subscriptions (admin panel)' },
  { key: 'ai_billing.admin_manage', feature: 'ai_billing', action: 'admin_manage', label: 'Approve/reject AI subscription payments' },
  { key: 'ai_billing.admin_revenue', feature: 'ai_billing', action: 'admin_revenue', label: 'View AI billing revenue dashboard' },

  // ---- app updates ----
  { key: 'app_updates.check', feature: 'app_updates', action: 'check', label: 'Check for app updates' },
  { key: 'app_updates.publish', feature: 'app_updates', action: 'publish', label: 'Publish a new app update manifest' },

  // ---- payments ----
  { key: 'payments.view_methods', feature: 'payments', action: 'view_methods', label: 'View available payment methods' },
  { key: 'payments.mpesa_initiate', feature: 'payments', action: 'mpesa_initiate', label: 'Initiate an M-Pesa payment' },
  { key: 'payments.pesapal_initiate', feature: 'payments', action: 'pesapal_initiate', label: 'Initiate a Pesapal payment' },
  { key: 'payments.touristtap_initiate', feature: 'payments', action: 'touristtap_initiate', label: 'Initiate a TouristTap payment' },
  { key: 'payments.view_status', feature: 'payments', action: 'view_status', label: 'View a payment transaction status' },
  { key: 'payments.manual_approve', feature: 'payments', action: 'manual_approve', label: 'Approve a manual payment request' },

  // ---- sync ----
  { key: 'sync.push', feature: 'sync', action: 'push', label: 'Push offline events to the server' },
  { key: 'sync.pull', feature: 'sync', action: 'pull', label: 'Pull server changes for offline sync' },
  { key: 'sync.status', feature: 'sync', action: 'status', label: 'View device sync status' },
  { key: 'sync.resolve_conflicts', feature: 'sync', action: 'resolve_conflicts', label: 'Resolve sync conflicts' },

  // ---- uploads ----
  { key: 'uploads.image', feature: 'uploads', action: 'image', label: 'Upload an image' },

  // ---- settings (mobile-facing bundles) ----
  { key: 'settings.printer_configure', feature: 'settings', action: 'printer_configure', label: 'Configure the receipt printer' },
  { key: 'settings.sync_configure', feature: 'settings', action: 'sync_configure', label: 'Configure sync settings' },
  { key: 'settings.notifications_configure', feature: 'settings', action: 'notifications_configure', label: 'Configure notification settings' },
  { key: 'settings.security_configure', feature: 'settings', action: 'security_configure', label: 'Configure device security (biometric/PIN)' },
  { key: 'settings.system_security_configure', feature: 'settings', action: 'system_security_configure', label: 'Configure tenant-wide security settings' },

  // ---- data ----
  { key: 'data.export', feature: 'data', action: 'export', label: 'Export tenant data' },
  { key: 'data.audit_trail_view', feature: 'data', action: 'audit_trail_view', label: 'View the audit trail' },
];

// Role level shorthand: which permission keys each legacy role level
// grants, expressed cumulatively (MANAGER includes everything SUPERVISOR
// has, etc.) — mirrors today's @Roles(SUPERVISOR, MANAGER, ADMIN) style
// checks where higher roles are supersets of lower ones.
const CASHIER_KEYS = [
  'products.view', 'products.view_all', 'products.favorite',
  'categories.view',
  'pricing.view',
  'inventory.stock.view', 'inventory.movements.view',
  'inventory.stock_requests.view', 'inventory.stock_requests.create',
  'inventory.stock_requests.update', 'inventory.stock_requests.cancel',
  'inventory.batches.view', 'inventory.batches.fefo_view',
  'sales.create', 'sales.view', 'sales.view_all',
  'customers.view', 'customers.create', 'customers.update', 'customers.credit_view',
  'cash_flow.settings_view', 'cash_flow.settings_update',
  'cash_ledger.view', 'cash_reconciliation.view',
  'expenses.view', 'expenses.create',
  'suppliers.view', 'suppliers.debts_view', 'suppliers.invoices_view',
  'ai.chat', 'ai.chat_web_enhanced', 'ai.cognitive_analyze', 'ai.cognitive_monitor', 'ai.cognitive_advisor', 'ai.set_model',
  'ai_billing.view_status', 'ai_billing.submit_payment',
  'app_updates.check',
  'payments.view_methods', 'payments.view_status',
  'payments.mpesa_initiate', 'payments.pesapal_initiate', 'payments.touristtap_initiate',
  'sync.push', 'sync.pull', 'sync.status', 'sync.resolve_conflicts',
  'uploads.image',
  'settings.printer_configure', 'settings.sync_configure', 'settings.notifications_configure', 'settings.security_configure',
  'branches.view', 'devices.view',
];

const SUPERVISOR_EXTRA_KEYS = [
  'inventory.stock.adjust',
  'inventory.transfers.view', 'inventory.transfers.create', 'inventory.transfers.send', 'inventory.transfers.receive',
  'inventory.batches.receive', 'inventory.batches.update',
  'inventory.stock_requests.resolve',
  'inventory.restock_suggestions.view',
  'sales.void', 'sales.refund', 'sales.discount', 'sales.bulk_create', 'sales.bulk_void',
  'reporting.sales_summary', 'reporting.sales_trend', 'reporting.top_products', 'reporting.category_sales',
  'reporting.payment_breakdown', 'reporting.inventory_report',
  'cash_reconciliation.create',
  'suppliers.invoices_create', 'suppliers.payments_record',
];

const MANAGER_EXTRA_KEYS = [
  'branches.create', 'branches.update', 'branches.bulk',
  'devices.create', 'devices.update', 'devices.delete',
  'categories.create', 'categories.update', 'categories.delete',
  'products.create', 'products.update', 'products.bulk',
  'pricing.set', 'pricing.delete',
  'inventory.expiry.dashboard',
  'reporting.dashboard', 'reporting.cashier_performance', 'reporting.branch_comparison', 'reporting.profit_loss',
  'reporting.financial', 'reporting.export',
  'users.create', 'users.view', 'users.update',
  'expenses.update', 'expenses.approve', 'expenses.reject', 'expenses.mark_paid',
  'suppliers.create',
];

const ADMIN_EXTRA_KEYS = [
  'audit.read',
  'branches.tenant.create', 'branches.tenant.update', 'branches.delete',
  'products.delete', 'categories.delete',
  'inventory.expiry.block_expired',
  'users.deactivate', 'users.reset_credentials',
  'roles.view', 'roles.create', 'roles.update', 'roles.delete',
  'permissions.view_catalog', 'permissions.assign_role', 'permissions.override_user',
  'expenses.delete',
  'data.export', 'data.audit_trail_view',
  'settings.system_security_configure',
  'app_updates.publish',
  'ai_billing.admin_view', 'ai_billing.admin_manage', 'ai_billing.admin_revenue',
  'payments.manual_approve',
];

const SUPERVISOR_KEYS = [...CASHIER_KEYS, ...SUPERVISOR_EXTRA_KEYS];
const MANAGER_KEYS = [...SUPERVISOR_KEYS, ...MANAGER_EXTRA_KEYS];
const ADMIN_KEYS = [...MANAGER_KEYS, ...ADMIN_EXTRA_KEYS];

const ROLE_BUNDLES: Record<string, string[]> = {
  Cashier: CASHIER_KEYS,
  Supervisor: SUPERVISOR_KEYS,
  Manager: MANAGER_KEYS,
  Admin: ADMIN_KEYS,
};

const LEGACY_TO_ROLE_NAME: Record<string, string> = {
  CASHIER: 'Cashier',
  SUPERVISOR: 'Supervisor',
  MANAGER: 'Manager',
  ADMIN: 'Admin',
};

async function seedPermissionCatalog() {
  const allKeys = new Set(PERMISSIONS.map((p) => p.key));
  // Sanity check: every key referenced by a role bundle must exist in the catalog.
  for (const [roleName, keys] of Object.entries(ROLE_BUNDLES)) {
    for (const key of keys) {
      if (!allKeys.has(key)) {
        throw new Error(`Role bundle "${roleName}" references unknown permission key "${key}"`);
      }
    }
  }

  for (const perm of PERMISSIONS) {
    await prisma.permission.upsert({
      where: { key: perm.key },
      update: { feature: perm.feature, action: perm.action, label: perm.label },
      create: perm,
    });
  }
  console.log(`Permission catalog seeded: ${PERMISSIONS.length} keys.`);
}

async function seedRolesForTenant(tenantId: string, tenantName: string) {
  const roleIdByName: Record<string, string> = {};

  for (const [roleName, keys] of Object.entries(ROLE_BUNDLES)) {
    const role = await prisma.role.upsert({
      where: { tenantId_name: { tenantId, name: roleName } },
      update: {},
      create: {
        tenantId,
        name: roleName,
        description: `Default ${roleName} role (system-seeded)`,
        isSystem: true,
      },
    });
    roleIdByName[roleName] = role.id;

    const uniqueKeys = Array.from(new Set(keys));
    for (const permissionKey of uniqueKeys) {
      await prisma.rolePermission.upsert({
        where: { roleId_permissionKey: { roleId: role.id, permissionKey } },
        update: {},
        create: { roleId: role.id, permissionKey },
      });
    }
  }

  console.log(`  Tenant "${tenantName}": 4 system roles seeded.`);
  return roleIdByName;
}

async function backfillUserRoles(tenantId: string, roleIdByName: Record<string, string>) {
  const users = await prisma.user.findMany({
    where: { tenantId },
    select: { id: true, role: true, email: true },
  });

  let backfilled = 0;
  for (const user of users) {
    const roleName = LEGACY_TO_ROLE_NAME[user.role];
    const roleId = roleIdByName[roleName];
    if (!roleId) continue;

    await prisma.userRole.upsert({
      where: { userId_roleId: { userId: user.id, roleId } },
      update: {},
      create: { userId: user.id, roleId },
    });
    backfilled++;
  }

  console.log(`  Backfilled UserRole for ${backfilled}/${users.length} users.`);
}

async function main() {
  console.log('Seeding granular permission system...\n');

  await seedPermissionCatalog();

  const tenants = await prisma.tenant.findMany({ select: { id: true, name: true } });
  console.log(`\nSeeding roles for ${tenants.length} tenant(s)...`);

  for (const tenant of tenants) {
    const roleIdByName = await seedRolesForTenant(tenant.id, tenant.name);
    await backfillUserRoles(tenant.id, roleIdByName);
  }

  console.log('\nDone.');
}

main()
  .catch((e) => {
    console.error('seed-permissions failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
