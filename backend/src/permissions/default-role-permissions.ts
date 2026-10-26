/**
 * Default tenant roles shared by workspace creation and permission seeding.
 * Keep the cashier bundle least-privileged: supervisors own voiding,
 * refunds, and viewing sales across staff.
 */
const CASHIER_KEYS = [
  'products.view', 'products.view_all', 'products.favorite',
  'categories.view', 'pricing.view',
  'inventory.stock.view', 'inventory.movements.view',
  'inventory.stock_requests.view', 'inventory.stock_requests.create',
  'inventory.stock_requests.update', 'inventory.stock_requests.cancel',
  'inventory.batches.view', 'inventory.batches.fefo_view',
  'sales.create', 'sales.view',
  'news.view',
  'inventory.stocktake.view', 'inventory.stocktake.count',
  'customers.view', 'customers.create', 'customers.update', 'customers.credit_view',
  'cash_flow.settings_view', 'cash_flow.settings_update',
  'cash_ledger.view', 'cash_reconciliation.view',
  'expenses.view', 'expenses.create',
  'suppliers.view', 'suppliers.debts_view', 'suppliers.invoices_view',
  'finance.view',
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
  'inventory.stock_requests.resolve', 'inventory.restock_suggestions.view',
  'sales.view_all', 'sales.void', 'sales.refund', 'sales.discount', 'sales.bulk_create', 'sales.bulk_void', 'sales.price_override',
  'inventory.stocktake.create', 'statements.share',
  'reporting.sales_summary', 'reporting.sales_trend', 'reporting.top_products', 'reporting.category_sales',
  'reporting.payment_breakdown', 'reporting.inventory_report',
  'cash_reconciliation.create',
  'suppliers.invoices_create', 'suppliers.payments_record',
  'finance.manage_payables', 'finance.manage_receivables',
];

const MANAGER_EXTRA_KEYS = [
  'branches.create', 'branches.update', 'branches.bulk',
  'devices.create', 'devices.update', 'devices.delete',
  'categories.create', 'categories.update', 'categories.delete',
  'products.create', 'products.update', 'products.bulk',
  'pricing.set', 'pricing.delete', 'inventory.expiry.dashboard',
  'reporting.dashboard', 'reporting.cashier_performance', 'reporting.branch_comparison', 'reporting.profit_loss',
  'reporting.financial', 'reporting.export',
  'users.create', 'users.view', 'users.update',
  'expenses.update', 'expenses.approve', 'expenses.reject', 'expenses.mark_paid',
  'suppliers.create', 'sales.close_end_of_day', 'sales.credit_override',
  'accountability.view', 'inventory.stocktake.approve',
  'imports.view', 'imports.manage', 'imports.receive', 'imports.payments',
  'coupons.view', 'coupons.manage', 'statements.manage', 'mpesa.reconcile',
];

const ADMIN_EXTRA_KEYS = [
  'audit.read', 'branches.tenant.create', 'branches.tenant.update', 'branches.delete',
  'products.delete', 'categories.delete', 'inventory.expiry.block_expired',
  'users.deactivate', 'users.reset_credentials',
  'roles.view', 'roles.create', 'roles.update', 'roles.delete',
  'permissions.view_catalog', 'permissions.assign_role', 'permissions.override_user',
  'expenses.delete', 'data.export', 'data.audit_trail_view',
  'settings.system_security_configure', 'app_updates.publish',
  'ai_billing.admin_view', 'ai_billing.admin_manage', 'ai_billing.admin_revenue',
  'payments.manual_approve', 'payments.manage_payout',
  'accountability.manage', 'news.manage', 'referrals.view',
];

const SUPERVISOR_KEYS = [...CASHIER_KEYS, ...SUPERVISOR_EXTRA_KEYS];
const MANAGER_KEYS = [...SUPERVISOR_KEYS, ...MANAGER_EXTRA_KEYS];
const ADMIN_KEYS = [...MANAGER_KEYS, ...ADMIN_EXTRA_KEYS];

export const DEFAULT_ROLE_PERMISSIONS: Record<string, string[]> = {
  Cashier: CASHIER_KEYS,
  Supervisor: SUPERVISOR_KEYS,
  Manager: MANAGER_KEYS,
  Admin: ADMIN_KEYS,
};
