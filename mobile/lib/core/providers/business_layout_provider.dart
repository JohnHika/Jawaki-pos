import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';

/// A business layout is a tenant-wide starting point for terminology and the
/// order of the app's existing work areas. It never grants permissions or
/// changes sales, inventory, or billing rules.
class BusinessLayoutPreset {
  const BusinessLayoutPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.productsLabel,
    required this.posSearchHint,
    required this.priorityPaths,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final String productsLabel;
  final String posSearchHint;
  final List<String> priorityPaths;
}

class BusinessLayoutAction {
  const BusinessLayoutAction({
    required this.path,
    required this.label,
    required this.icon,
  });

  final String path;
  final String label;
  final IconData icon;
}

/// Existing app work areas that a shop owner can bring forward in navigation.
/// Access still comes from the user's permission set at runtime.
const businessLayoutActions = <BusinessLayoutAction>[
  BusinessLayoutAction(
      path: '/', label: 'POS', icon: Icons.point_of_sale_rounded),
  BusinessLayoutAction(
      path: '/dashboard', label: 'Dashboard', icon: Icons.dashboard_rounded),
  BusinessLayoutAction(
      path: '/products', label: 'Products', icon: Icons.inventory_2_rounded),
  BusinessLayoutAction(
      path: '/inventory', label: 'Inventory', icon: Icons.warehouse_rounded),
  BusinessLayoutAction(
      path: '/customers', label: 'Customers', icon: Icons.people_rounded),
  BusinessLayoutAction(
      path: '/finance', label: 'Finance', icon: Icons.account_balance_wallet),
  BusinessLayoutAction(
      path: '/reports', label: 'Reports', icon: Icons.analytics_rounded),
  BusinessLayoutAction(
      path: '/payments', label: 'Payments', icon: Icons.payments_rounded),
  BusinessLayoutAction(
      path: '/receipts', label: 'Receipts', icon: Icons.receipt_long_rounded),
  BusinessLayoutAction(
      path: '/ai', label: 'AI assistant', icon: Icons.auto_awesome_rounded),
  BusinessLayoutAction(
      path: '/settings', label: 'Settings', icon: Icons.settings_rounded),
  BusinessLayoutAction(
      path: '/shop-alerts', label: 'Shop Alerts', icon: Icons.shield_rounded),
  BusinessLayoutAction(
      path: '/stock-counts', label: 'Stock Counts', icon: Icons.fact_check),
  BusinessLayoutAction(
      path: '/containers', label: 'Containers', icon: Icons.local_shipping),
  BusinessLayoutAction(
      path: '/news', label: 'Business News', icon: Icons.newspaper_rounded),
  BusinessLayoutAction(
      path: '/price-list', label: 'Price List', icon: Icons.sell_rounded),
  BusinessLayoutAction(
      path: '/coupons', label: 'Coupons', icon: Icons.confirmation_number),
  BusinessLayoutAction(
      path: '/statements/replies',
      label: 'Debt Replies',
      icon: Icons.mark_chat_read_rounded),
  BusinessLayoutAction(
      path: '/referrals', label: 'Invite Shops', icon: Icons.redeem_rounded),
  BusinessLayoutAction(
      path: '/partners', label: 'Trade Partners', icon: Icons.handshake),
];

const businessLayoutPresets = <BusinessLayoutPreset>[
  BusinessLayoutPreset(
    id: 'general_retail',
    name: 'General shop',
    description: 'A balanced setup for everyday retail.',
    icon: Icons.storefront_rounded,
    productsLabel: 'Products',
    posSearchHint: 'Search products or scan a barcode',
    priorityPaths: ['/dashboard', '/', '/products', '/inventory'],
  ),
  BusinessLayoutPreset(
    id: 'bookshop',
    name: 'Bookshop',
    description: 'Put books, stock and repeat customers within easy reach.',
    icon: Icons.menu_book_rounded,
    productsLabel: 'Books',
    posSearchHint: 'Search book titles or ISBN/SKU',
    priorityPaths: ['/dashboard', '/products', '/', '/inventory', '/customers'],
  ),
  BusinessLayoutPreset(
    id: 'kamukunji_counter',
    name: 'Kamukunji counter',
    description: 'Keep fast sales, products and cash flow close at hand.',
    icon: Icons.store_mall_directory_rounded,
    productsLabel: 'Products',
    posSearchHint: 'Find a product by name, code or barcode',
    priorityPaths: ['/', '/dashboard', '/products', '/finance', '/inventory'],
  ),
  BusinessLayoutPreset(
    id: 'grocery',
    name: 'Grocery & mini market',
    description: 'Prioritise checkout, stock and daily sales.',
    icon: Icons.local_grocery_store_rounded,
    productsLabel: 'Products',
    posSearchHint: 'Search products or scan a barcode',
    priorityPaths: ['/', '/dashboard', '/inventory', '/products', '/reports'],
  ),
  BusinessLayoutPreset(
    id: 'fashion',
    name: 'Fashion & apparel',
    description: 'Put the till, catalogue and customer history up front.',
    icon: Icons.checkroom_rounded,
    productsLabel: 'Products',
    posSearchHint: 'Search products, codes or barcode',
    priorityPaths: ['/', '/products', '/customers', '/dashboard', '/reports'],
  ),
  BusinessLayoutPreset(
    id: 'electronics',
    name: 'Electronics & accessories',
    description: 'Keep sales, catalogue and stock control close together.',
    icon: Icons.devices_other_rounded,
    productsLabel: 'Products',
    posSearchHint: 'Search products, model or barcode',
    priorityPaths: ['/', '/products', '/inventory', '/dashboard', '/finance'],
  ),
  BusinessLayoutPreset(
    id: 'hardware',
    name: 'Hardware & building supplies',
    description: 'Prioritise counter sales, stock and business accounts.',
    icon: Icons.handyman_rounded,
    productsLabel: 'Products',
    posSearchHint: 'Search products, code or barcode',
    priorityPaths: ['/', '/inventory', '/products', '/finance', '/dashboard'],
  ),
  BusinessLayoutPreset(
    id: 'beauty',
    name: 'Beauty & personal care',
    description: 'Keep checkout, the catalogue and customer records nearby.',
    icon: Icons.spa_rounded,
    productsLabel: 'Products',
    posSearchHint: 'Search products, shade or barcode',
    priorityPaths: ['/', '/products', '/customers', '/inventory', '/dashboard'],
  ),
  BusinessLayoutPreset(
    id: 'custom',
    name: 'Custom layout',
    description: 'Choose the work areas your team uses most.',
    icon: Icons.tune_rounded,
    productsLabel: 'Products',
    posSearchHint: 'Search products or scan a barcode',
    priorityPaths: [],
  ),
];

class BusinessLayoutConfig {
  const BusinessLayoutConfig({
    required this.preset,
    required this.priorityPaths,
  });

  final BusinessLayoutPreset preset;
  final List<String> priorityPaths;

  String get profileId => preset.id;
  String get productSingular => preset.id == 'bookshop' ? 'Book' : 'Product';
  String get productsLabel => preset.productsLabel;
  String get catalogSearchHint => preset.id == 'bookshop'
      ? 'Search book title or ISBN/SKU...'
      : 'Search products by name...';
  String get productCodeLabel => preset.id == 'bookshop'
      ? 'ISBN / barcode (optional)'
      : 'SKU / barcode (optional)';

  Map<String, dynamic> toJson() => {
        'profileId': profileId,
        'priorityPaths': priorityPaths,
      };
}

BusinessLayoutPreset businessLayoutPreset(String? id) {
  return businessLayoutPresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => businessLayoutPresets.first,
  );
}

BusinessLayoutConfig businessLayoutFromUser(Map<String, dynamic>? user) {
  final tenant = user?['tenant'];
  final settings = tenant is Map ? tenant['settings'] : null;
  final rawLayout = settings is Map ? settings['businessLayout'] : null;
  final layout = rawLayout is Map ? rawLayout : const <String, dynamic>{};
  final preset = businessLayoutPreset(layout['profileId']?.toString());
  final rawPaths = layout['priorityPaths'];
  final paths = rawPaths is List
      ? rawPaths
          .map((path) => path.toString())
          .where((path) =>
              businessLayoutActions.any((action) => action.path == path))
          .toSet()
          .toList()
      : preset.priorityPaths;
  return BusinessLayoutConfig(
    preset: preset,
    priorityPaths: paths,
  );
}

final businessLayoutProvider = Provider<BusinessLayoutConfig>((ref) {
  return businessLayoutFromUser(ref.watch(currentUserProvider));
});
