/// Device-local role templates for standalone workspaces.
///
/// These roles are intentionally least-privileged and exclude every user,
/// role, permission, payment-routing, and system-security administration key.
/// They gate local app surfaces; no claim is made that a local profile is a
/// cloud account or can be invited to another device.
class LocalStaffRoles {
  const LocalStaffRoles._();

  static const List<String> names = ['Cashier', 'Stock keeper', 'Manager'];

  static const List<String> _cashier = [
    'products.view',
    'categories.view',
    'pricing.view',
    'inventory.stock.view',
    'sales.create',
    'sales.view',
    'customers.view',
    'customers.create',
    'customers.update',
    'payments.view_methods',
    'payments.view_status',
  ];

  static const List<String> _stockKeeper = [
    'products.view',
    'inventory.stock.view',
    'inventory.stock.adjust',
    'inventory.movements.view',
    'inventory.stocktake.view',
    'inventory.stocktake.count',
  ];

  static const List<String> _manager = [
    ..._cashier,
    ..._stockKeeper,
    'sales.view_all',
    'sales.void',
    'sales.discount',
    'reporting.dashboard',
    'reporting.sales_summary',
    'reporting.inventory_report',
    'finance.view',
    'expenses.view',
  ];

  static List<String>? permissionsFor(String role) => switch (role) {
        'Cashier' => _cashier,
        'Stock keeper' => _stockKeeper,
        'Manager' => _manager,
        _ => null,
      };

  static String descriptionFor(String role) => switch (role) {
        'Cashier' => 'Ring up sales and help customers',
        'Stock keeper' => 'Receive, count, and adjust stock',
        'Manager' => 'Oversee sales, stock, and daily reports',
        _ => 'Choose a role',
      };
}
