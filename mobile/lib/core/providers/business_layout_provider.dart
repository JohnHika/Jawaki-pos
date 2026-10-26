import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/app_roles.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

/// A business layout is a tenant-wide preset for terminology, checkout,
/// product fields, dashboard focus and visible work areas. It never grants
/// permissions or changes sales, inventory, or billing rules.
class BusinessLayoutPreset {
  const BusinessLayoutPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.productSingular,
    required this.icon,
    required this.productsLabel,
    required this.productCodeLabel,
    required this.productCodeHint,
    required this.productNameHint,
    required this.catalogSearchHint,
    required this.posSearchHint,
    required this.priorityPaths,
    this.productFields = const [],
    this.customerSingular = 'Customer',
    this.customersLabel = 'Customers',
    this.defaultActionLabels = const {},
    this.defaultPosProductView = 'grid',
    this.defaultBaseUnit = 'piece',
    this.defaultAllowFractions = false,
    this.defaultTrackInventoryForNewProducts = true,
    this.defaultShowPosCategories = true,
    this.defaultShowPosFavorites = true,
    this.defaultShowPosCustomer = true,
    this.defaultPosQuickActions = _defaultPosQuickActions,
    this.defaultDashboardMetrics = _defaultDashboardMetrics,
    this.defaultDashboardSections = _defaultDashboardSections,
    this.defaultVisiblePaths = const [],
  });

  final String id;
  final String name;
  final String description;
  final String productSingular;
  final IconData icon;
  final String productsLabel;
  final String productCodeLabel;
  final String productCodeHint;
  final String productNameHint;
  final String defaultBaseUnit;
  final bool defaultAllowFractions;
  final bool defaultTrackInventoryForNewProducts;
  final String catalogSearchHint;
  final String posSearchHint;
  final List<String> priorityPaths;
  final List<BusinessLayoutProductField> productFields;
  final String customerSingular;
  final String customersLabel;
  final Map<String, String> defaultActionLabels;
  final String defaultPosProductView;
  final bool defaultShowPosCategories;
  final bool defaultShowPosFavorites;
  final bool defaultShowPosCustomer;
  final List<String> defaultPosQuickActions;
  final List<String> defaultDashboardMetrics;
  final List<String> defaultDashboardSections;

  /// Work areas that should be visible when this mode is first applied.
  /// An empty list preserves the full app (used by Custom layout).
  final List<String> defaultVisiblePaths;

  List<String> get defaultHiddenPaths {
    if (defaultVisiblePaths.isEmpty) return const [];
    final visible = defaultVisiblePaths.toSet();
    return businessLayoutActions
        .where((action) =>
            businessLayoutCanHideAction(action.path) &&
            !visible.contains(action.path))
        .map((action) => action.path)
        .toList(growable: false);
  }

  String actionLabel(String path, String fallback) =>
      defaultActionLabels[path] ??
      (path == '/products'
          ? productsLabel
          : path == '/customers'
              ? customersLabel
              : fallback);
}

/// Optional product details that adapt the catalog to a shop's trade.
/// Stored as metadata and kept separate from stock and pricing rules.
class BusinessLayoutProductField {
  const BusinessLayoutProductField({
    required this.key,
    required this.label,
    required this.hint,
  });

  final String key;
  final String label;
  final String hint;
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

class BusinessLayoutDashboardMetric {
  const BusinessLayoutDashboardMetric({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
}

/// Optional work sections shown on the shop dashboard. These settings only
/// change presentation; the underlying reports and records remain available.
class BusinessLayoutDashboardSection {
  const BusinessLayoutDashboardSection({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
}

/// One-tap starting points for common counter workflows. These only set
/// presentation defaults; the individual checkout controls remain editable.
class BusinessLayoutCheckoutStyle {
  const BusinessLayoutCheckoutStyle({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.productView,
    required this.showCategories,
    required this.showFavorites,
    required this.showCustomer,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final String productView;
  final bool showCategories;
  final bool showFavorites;
  final bool showCustomer;

  bool matches(BusinessLayoutConfig layout) =>
      layout.effectivePosProductView == productView &&
      layout.effectiveShowPosCategories == showCategories &&
      layout.effectiveShowPosFavorites == showFavorites &&
      layout.effectiveShowPosCustomer == showCustomer;
}

/// Existing POS toolbar actions that merchants can arrange for their counter.
/// This controls visibility/order only; each action keeps its existing
/// permission and transaction checks.
class BusinessLayoutPosAction {
  const BusinessLayoutPosAction({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    this.path,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;

  /// Existing work area to open. Actions without a path operate on the cart.
  final String? path;
}

/// A merchant-curated page of products for the POS catalog. Pages are stored
/// with the shop layout so the same counter shortcuts appear on each device.
class BusinessLayoutProductPage {
  const BusinessLayoutProductPage({
    required this.id,
    required this.name,
    required this.productIds,
  });

  final String id;
  final String name;
  final List<String> productIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'productIds': productIds,
      };
}

const _defaultPosQuickActions = <String>[
  'customer',
  'favorites',
  'cart',
  'held_sales',
  'hold_sale',
];

const businessLayoutPosActions = <BusinessLayoutPosAction>[
  BusinessLayoutPosAction(
    id: 'customer',
    label: 'Customer',
    description: 'Find or attach a customer to the current sale.',
    icon: Icons.person_add_alt_1_rounded,
  ),
  BusinessLayoutPosAction(
    id: 'favorites',
    label: 'Favorites',
    description: 'Show the products saved for fast repeat sales.',
    icon: Icons.favorite_rounded,
  ),
  BusinessLayoutPosAction(
    id: 'held_sales',
    label: 'Held sales',
    description: 'Resume a sale that was parked at this counter.',
    icon: Icons.inventory_2_outlined,
  ),
  BusinessLayoutPosAction(
    id: 'hold_sale',
    label: 'Hold sale',
    description: 'Park the current cart and serve the next customer.',
    icon: Icons.pause_rounded,
  ),
  BusinessLayoutPosAction(
    id: 'cart',
    label: 'Cart',
    description: 'Always available so the team can finish checkout.',
    icon: Icons.shopping_cart_outlined,
  ),
  BusinessLayoutPosAction(
    id: 'price_list',
    label: 'Price list',
    description: 'Look up product prices and share the shop price list.',
    icon: Icons.sell_outlined,
    path: '/price-list',
  ),
  BusinessLayoutPosAction(
    id: 'inventory',
    label: 'Stock control',
    description: 'Check stock and inventory activity.',
    icon: Icons.warehouse_outlined,
    path: '/inventory',
  ),
  BusinessLayoutPosAction(
    id: 'stock_counts',
    label: 'Stock counts',
    description: 'Open a stock count while serving at the counter.',
    icon: Icons.fact_check_outlined,
    path: '/stock-counts',
  ),
  BusinessLayoutPosAction(
    id: 'reports',
    label: 'Reports',
    description: 'Review shop performance and sales reports.',
    icon: Icons.analytics_outlined,
    path: '/reports',
  ),
  BusinessLayoutPosAction(
    id: 'payments',
    label: 'Payments',
    description: 'Review payment activity and payout setup.',
    icon: Icons.payments_outlined,
    path: '/payments',
  ),
  BusinessLayoutPosAction(
    id: 'receipts',
    label: 'Receipts',
    description: 'Find completed sales and receipts.',
    icon: Icons.receipt_long_outlined,
    path: '/receipts',
  ),
];

BusinessLayoutPosAction? businessLayoutPosAction(String id) {
  for (final action in businessLayoutPosActions) {
    if (action.id == id) return action;
  }
  return null;
}

const businessLayoutCheckoutStyles = <BusinessLayoutCheckoutStyle>[
  BusinessLayoutCheckoutStyle(
    id: 'quick_counter',
    name: 'Quick counter',
    description: 'Visual grid, categories and favourites.',
    icon: Icons.point_of_sale_rounded,
    productView: 'grid',
    showCategories: true,
    showFavorites: true,
    showCustomer: true,
  ),
  BusinessLayoutCheckoutStyle(
    id: 'catalogue_first',
    name: 'Catalogue first',
    description: 'Compact list for names and item codes.',
    icon: Icons.view_list_rounded,
    productView: 'list',
    showCategories: true,
    showFavorites: false,
    showCustomer: true,
  ),
  BusinessLayoutCheckoutStyle(
    id: 'simple_till',
    name: 'Simple till',
    description: 'A clean grid with fewer checkout shortcuts.',
    icon: Icons.grid_view_rounded,
    productView: 'grid',
    showCategories: false,
    showFavorites: false,
    showCustomer: false,
  ),
];

/// Dashboard figures that can be arranged around the way a shop runs.
const businessLayoutDashboardMetrics = <BusinessLayoutDashboardMetric>[
  BusinessLayoutDashboardMetric(
    id: 'revenue',
    label: "Today's revenue",
    description: 'Sales value recorded today.',
    icon: Icons.trending_up_rounded,
  ),
  BusinessLayoutDashboardMetric(
    id: 'transactions',
    label: 'Transactions',
    description: 'Number of completed sales.',
    icon: Icons.receipt_long_rounded,
  ),
  BusinessLayoutDashboardMetric(
    id: 'avgTicket',
    label: 'Average sale',
    description: 'Average value per sale.',
    icon: Icons.shopping_cart_rounded,
  ),
  BusinessLayoutDashboardMetric(
    id: 'itemsSold',
    label: 'Items sold',
    description: 'Quantity sold today.',
    icon: Icons.inventory_2_rounded,
  ),
];

const _defaultDashboardMetrics = [
  'revenue',
  'transactions',
  'avgTicket',
  'itemsSold',
];

const _defaultDashboardSections = [
  'summary_metrics',
  'end_of_day',
  'ai_brief',
  'cost_profit',
  'recent_sales',
];

const businessLayoutDashboardSections = <BusinessLayoutDashboardSection>[
  BusinessLayoutDashboardSection(
    id: 'summary_metrics',
    label: 'Daily figures',
    description: 'Revenue, transactions, average sale and items sold.',
    icon: Icons.insights_rounded,
  ),
  BusinessLayoutDashboardSection(
    id: 'end_of_day',
    label: 'End-of-day review',
    description: 'A quick route to review sales and count the till.',
    icon: Icons.event_available_rounded,
  ),
  BusinessLayoutDashboardSection(
    id: 'ai_brief',
    label: 'Business brief',
    description: 'AI summary and practical notes about today’s activity.',
    icon: Icons.auto_awesome_rounded,
  ),
  BusinessLayoutDashboardSection(
    id: 'cost_profit',
    label: 'Cost and profit',
    description: 'Compare sales and recorded product costs.',
    icon: Icons.account_balance_rounded,
  ),
  BusinessLayoutDashboardSection(
    id: 'recent_sales',
    label: 'Recent sales',
    description: 'Review today’s latest receipts and transactions.',
    icon: Icons.receipt_long_rounded,
  ),
];

/// Common units used by shop profiles and the product form.
const businessLayoutUnits = <String>[
  'piece',
  'copy',
  'pack',
  'box',
  'carton',
  'bottle',
  'tube',
  'bar',
  'roll',
  'jar',
  'pair',
  'set',
  'bundle',
  'tray',
  'crate',
  'bag',
  'sack',
  'ream',
  'half dozen',
  'dozen',
  'kg',
  'g',
  'litre',
  'ml',
  'metre',
  'cm',
  'portion',
  'cup',
  'service',
  'session',
  'hour',
  'day',
];

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

/// Familiar operating packs keep first-run navigation focused. Owners can
/// still reveal every area from Layout actions; permissions remain separate.
const _coreShopActionPaths = <String>[
  '/',
  '/dashboard',
  '/ai',
  '/products',
  '/inventory',
  '/customers',
  '/finance',
  '/reports',
  '/payments',
  '/receipts',
  '/settings',
  '/shop-alerts',
  '/stock-counts',
];
const _generalRetailActionPaths = <String>[
  ..._coreShopActionPaths,
  '/price-list',
  '/coupons',
  '/statements/replies',
];
const _bookshopActionPaths = <String>[
  ..._coreShopActionPaths,
  '/price-list',
  '/coupons',
  '/statements/replies',
];
const _kamkunjiActionPaths = <String>[
  ..._coreShopActionPaths,
  '/containers',
  '/price-list',
  '/statements/replies',
  '/partners',
];
const _groceryActionPaths = <String>[
  ..._coreShopActionPaths,
  '/containers',
  '/price-list',
  '/coupons',
  '/statements/replies',
];
const _hospitalityActionPaths = <String>[
  ..._coreShopActionPaths,
  '/containers',
  '/coupons',
];
const _marketTraderActionPaths = <String>[
  ..._coreShopActionPaths,
  '/price-list',
  '/coupons',
];
const _fashionActionPaths = <String>[
  ..._coreShopActionPaths,
  '/price-list',
  '/coupons',
];
const _electronicsActionPaths = <String>[
  ..._coreShopActionPaths,
  '/price-list',
  '/coupons',
  '/partners',
];
const _hardwareActionPaths = <String>[
  ..._coreShopActionPaths,
  '/containers',
  '/price-list',
  '/statements/replies',
  '/partners',
];
const _beautyActionPaths = <String>[
  ..._coreShopActionPaths,
  '/price-list',
  '/coupons',
];
const _wholesaleActionPaths = <String>[
  ..._coreShopActionPaths,
  '/containers',
  '/price-list',
  '/statements/replies',
  '/partners',
];
const _stationeryActionPaths = <String>[
  ..._coreShopActionPaths,
  '/price-list',
  '/coupons',
  '/statements/replies',
];
const _autoPartsActionPaths = <String>[
  ..._coreShopActionPaths,
  '/containers',
  '/price-list',
  '/partners',
];
const _pharmacyActionPaths = <String>[
  ..._coreShopActionPaths,
  '/price-list',
  '/statements/replies',
];
const _foodCounterActionPaths = <String>[
  ..._coreShopActionPaths,
  '/containers',
  '/coupons',
];
const _agrovetActionPaths = <String>[
  ..._coreShopActionPaths,
  '/containers',
  '/price-list',
  '/statements/replies',
  '/partners',
];
const _butcheryActionPaths = <String>[
  ..._coreShopActionPaths,
  '/containers',
  '/statements/replies',
];
const _beveragesActionPaths = <String>[
  ..._coreShopActionPaths,
  '/containers',
  '/price-list',
  '/coupons',
];
const _serviceCounterActionPaths = <String>[
  '/',
  '/dashboard',
  '/products',
  '/inventory',
  '/customers',
  '/finance',
  '/reports',
  '/payments',
  '/receipts',
  '/settings',
  '/shop-alerts',
  '/coupons',
];

const businessLayoutPresets = <BusinessLayoutPreset>[
  BusinessLayoutPreset(
    id: 'general_retail',
    name: 'General shop',
    description: 'A balanced setup for everyday retail.',
    productSingular: 'Product',
    icon: Icons.storefront_rounded,
    productsLabel: 'Products',
    productCodeLabel: 'SKU / barcode (optional)',
    productCodeHint: 'Leave blank to generate automatically',
    productNameHint: 'e.g. Panadol Extra (10 tablets)',
    catalogSearchHint: 'Search products by name...',
    posSearchHint: 'Search products or scan a barcode',
    priorityPaths: ['/dashboard', '/', '/products', '/inventory'],
    defaultVisiblePaths: _generalRetailActionPaths,
    productFields: [
      BusinessLayoutProductField(
          key: 'brand', label: 'Brand', hint: 'Product brand'),
      BusinessLayoutProductField(
          key: 'variant', label: 'Variant', hint: 'Colour, size or model'),
      BusinessLayoutProductField(
          key: 'origin', label: 'Origin', hint: 'Country or source'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'service_counter',
    name: 'Service counter',
    description:
        'Set up services, keep client records close and track daily sales.',
    productSingular: 'Service',
    icon: Icons.design_services_rounded,
    productsLabel: 'Services',
    productCodeLabel: 'Service code (optional)',
    productCodeHint: 'Enter a service code if you use one',
    productNameHint: 'e.g. Haircut and wash',
    defaultBaseUnit: 'service',
    defaultTrackInventoryForNewProducts: false,
    catalogSearchHint: 'Search services by name or code...',
    posSearchHint: 'Search services or scan a service code',
    priorityPaths: ['/', '/products', '/customers', '/dashboard', '/finance'],
    defaultVisiblePaths: _serviceCounterActionPaths,
    defaultActionLabels: {
      '/': 'Service counter',
      '/dashboard': 'Daily overview',
      '/products': 'Services',
      '/inventory': 'Supplies',
      '/customers': 'Clients',
      '/finance': 'Accounts',
      '/reports': 'Service reports',
    },
    customerSingular: 'Client',
    customersLabel: 'Clients',
    productFields: [
      BusinessLayoutProductField(
          key: 'serviceDuration', label: 'Duration', hint: 'e.g. 45 minutes'),
      BusinessLayoutProductField(
          key: 'serviceCategory',
          label: 'Service type',
          hint: 'e.g. Hair care'),
      BusinessLayoutProductField(
          key: 'serviceNotes',
          label: 'Service notes',
          hint: 'Optional details'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'bookshop',
    name: 'Bookshop',
    description: 'Put books, stock and repeat customers within easy reach.',
    productSingular: 'Book',
    icon: Icons.menu_book_rounded,
    productsLabel: 'Books',
    productCodeLabel: 'ISBN / barcode (optional)',
    productCodeHint: 'Enter the ISBN or scan code',
    productNameHint: 'e.g. A Grain of Wheat — Ngũgĩ wa Thiong’o',
    defaultBaseUnit: 'copy',
    catalogSearchHint: 'Search title, author, publisher or ISBN...',
    posSearchHint: 'Search by title, author, publisher or ISBN',
    priorityPaths: ['/dashboard', '/products', '/', '/inventory', '/customers'],
    defaultVisiblePaths: _bookshopActionPaths,
    defaultPosProductView: 'list',
    defaultPosQuickActions: [
      'favorites',
      'customer',
      'cart',
      'held_sales',
      'hold_sale',
      'price_list',
    ],
    defaultDashboardMetrics: [
      'itemsSold',
      'revenue',
      'transactions',
      'avgTicket',
    ],
    defaultActionLabels: {
      '/': 'Sell books',
      '/dashboard': 'Shop overview',
      '/products': 'Books',
      '/inventory': 'Book stock',
      '/customers': 'Readers',
      '/finance': 'Accounts & credit',
      '/reports': 'Sales reports',
    },
    customerSingular: 'Reader',
    customersLabel: 'Readers',
    productFields: [
      BusinessLayoutProductField(
          key: 'author', label: 'Author', hint: 'Book author'),
      BusinessLayoutProductField(
          key: 'publisher', label: 'Publisher', hint: 'Publishing house'),
      BusinessLayoutProductField(
          key: 'edition', label: 'Edition', hint: 'e.g. 3rd edition'),
      BusinessLayoutProductField(
          key: 'genre', label: 'Genre', hint: 'e.g. History'),
      BusinessLayoutProductField(
          key: 'language', label: 'Language', hint: 'Book language'),
      BusinessLayoutProductField(
          key: 'subject', label: 'Subject', hint: 'e.g. Mathematics'),
      BusinessLayoutProductField(
          key: 'schoolLevel',
          label: 'School level',
          hint: 'e.g. Grade 6 or Form 2'),
      BusinessLayoutProductField(
          key: 'series', label: 'Series', hint: 'Textbook or book series'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'kamukunji_counter',
    name: 'Kamukunji sales counter',
    description: 'Keep rapid counter sales, stock and cash flow close at hand.',
    productSingular: 'Item',
    icon: Icons.store_mall_directory_rounded,
    productsLabel: 'Stock items',
    productCodeLabel: 'Item code / barcode (optional)',
    productCodeHint: 'Enter the item code or scan a barcode',
    productNameHint: 'e.g. 12 mm PVC pipe — 3 metres',
    catalogSearchHint: 'Search stock items by name or code...',
    posSearchHint: 'Find an item by name, code or barcode',
    priorityPaths: ['/', '/dashboard', '/products', '/finance', '/inventory'],
    defaultVisiblePaths: _kamkunjiActionPaths,
    defaultPosProductView: 'list',
    defaultShowPosFavorites: false,
    defaultPosQuickActions: [
      'customer',
      'cart',
      'held_sales',
      'hold_sale',
      'price_list',
      'inventory',
    ],
    defaultDashboardMetrics: [
      'revenue',
      'transactions',
      'itemsSold',
      'avgTicket',
    ],
    defaultActionLabels: {
      '/': 'Sales counter',
      '/dashboard': 'Counter overview',
      '/products': 'Stock items',
      '/inventory': 'Stock control',
      '/finance': 'Cash & credit',
      '/reports': 'Daily sales',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'brand', label: 'Brand', hint: 'Item brand or maker'),
      BusinessLayoutProductField(
          key: 'grade', label: 'Grade / quality', hint: 'e.g. Grade A'),
      BusinessLayoutProductField(
          key: 'origin', label: 'Source', hint: 'Supplier or market'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'grocery',
    name: 'Grocery & mini market',
    description: 'Prioritise checkout, stock and daily sales.',
    productSingular: 'Product',
    icon: Icons.local_grocery_store_rounded,
    productsLabel: 'Products',
    productCodeLabel: 'SKU / barcode (optional)',
    productCodeHint: 'Enter the SKU or scan a barcode',
    productNameHint: 'e.g. Maize flour (2 kg)',
    catalogSearchHint: 'Search groceries by name or barcode...',
    posSearchHint: 'Search products or scan a barcode',
    priorityPaths: ['/', '/dashboard', '/inventory', '/products', '/reports'],
    defaultVisiblePaths: _groceryActionPaths,
    defaultActionLabels: {
      '/': 'Quick sale',
      '/dashboard': 'Today’s overview',
      '/products': 'Groceries',
      '/inventory': 'Stock control',
      '/finance': 'Cash & credit',
      '/reports': 'Daily sales',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'brand', label: 'Brand', hint: 'Product brand'),
      BusinessLayoutProductField(
          key: 'netQuantity', label: 'Net quantity', hint: 'e.g. 2 kg'),
      BusinessLayoutProductField(
          key: 'origin', label: 'Country of origin', hint: 'Where it is made'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'cafe_takeaway',
    name: 'Cafe & takeaway',
    description: 'A quick counter setup for menu items, checkout and stock.',
    productSingular: 'Menu item',
    icon: Icons.local_cafe_rounded,
    productsLabel: 'Menu',
    productCodeLabel: 'PLU / barcode (optional)',
    productCodeHint: 'Enter a PLU or scan a barcode',
    productNameHint: 'e.g. Masala tea — regular',
    defaultBaseUnit: 'portion',
    catalogSearchHint: 'Search menu items by name or code...',
    posSearchHint: 'Search menu items or scan a barcode',
    priorityPaths: ['/', '/products', '/inventory', '/reports', '/finance'],
    defaultVisiblePaths: _hospitalityActionPaths,
    defaultActionLabels: {
      '/': 'Counter',
      '/dashboard': 'Today’s overview',
      '/products': 'Menu',
      '/inventory': 'Stock',
      '/finance': 'Cash & accounts',
      '/reports': 'Sales reports',
    },
    customerSingular: 'Guest',
    customersLabel: 'Guests',
    productFields: [
      BusinessLayoutProductField(
          key: 'servingSize', label: 'Serving size', hint: 'e.g. Regular'),
      BusinessLayoutProductField(
          key: 'dietaryNotes', label: 'Dietary notes', hint: 'Optional notes'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'market_stall',
    name: 'Market stall & mobile trader',
    description:
        'Keep fast checkout, products and stock tools close for a busy stall.',
    productSingular: 'Item',
    icon: Icons.storefront_rounded,
    productsLabel: 'Items',
    productCodeLabel: 'Item code / barcode (optional)',
    productCodeHint: 'Enter an item code or scan a barcode',
    productNameHint: 'e.g. Fresh mango — each',
    catalogSearchHint: 'Search items by name or code...',
    posSearchHint: 'Find an item by name, code or barcode',
    priorityPaths: ['/', '/products', '/inventory', '/finance', '/dashboard'],
    defaultVisiblePaths: _marketTraderActionPaths,
    defaultActionLabels: {
      '/': 'Quick counter',
      '/dashboard': 'Today’s overview',
      '/products': 'Market items',
      '/inventory': 'Stock',
      '/finance': 'Cash & credit',
      '/reports': 'Daily sales',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'grade', label: 'Grade / quality', hint: 'e.g. Grade A'),
      BusinessLayoutProductField(
          key: 'origin', label: 'Source', hint: 'Farm or market'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'fashion',
    name: 'Fashion & apparel',
    description: 'Put the till, catalogue and customer history up front.',
    productSingular: 'Product',
    icon: Icons.checkroom_rounded,
    productsLabel: 'Products',
    productCodeLabel: 'SKU / barcode (optional)',
    productCodeHint: 'Enter the SKU or scan a barcode',
    productNameHint: 'e.g. Men’s Oxford shirt — blue, size L',
    catalogSearchHint: 'Search products by name or code...',
    posSearchHint: 'Search products, codes or barcode',
    priorityPaths: ['/', '/products', '/customers', '/dashboard', '/reports'],
    defaultVisiblePaths: _fashionActionPaths,
    defaultActionLabels: {
      '/': 'Checkout',
      '/dashboard': 'Shop overview',
      '/products': 'Clothing & accessories',
      '/inventory': 'Stock',
      '/customers': 'Clients',
      '/reports': 'Sales reports',
    },
    customerSingular: 'Client',
    customersLabel: 'Clients',
    productFields: [
      BusinessLayoutProductField(
          key: 'brand', label: 'Brand', hint: 'Clothing brand'),
      BusinessLayoutProductField(
          key: 'size', label: 'Size', hint: 'e.g. M, 32, EU 40'),
      BusinessLayoutProductField(
          key: 'colour', label: 'Colour', hint: 'e.g. Navy blue'),
      BusinessLayoutProductField(
          key: 'material', label: 'Material', hint: 'e.g. Cotton'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'electronics',
    name: 'Electronics & accessories',
    description: 'Keep sales, catalogue and stock control close together.',
    productSingular: 'Product',
    icon: Icons.devices_other_rounded,
    productsLabel: 'Products',
    productCodeLabel: 'Model / SKU / barcode (optional)',
    productCodeHint: 'Enter the model or scan a barcode',
    productNameHint: 'e.g. USB-C charger, 30 W',
    catalogSearchHint: 'Search products by name, model or code...',
    posSearchHint: 'Search products, model or barcode',
    priorityPaths: ['/', '/products', '/inventory', '/dashboard', '/finance'],
    defaultVisiblePaths: _electronicsActionPaths,
    defaultActionLabels: {
      '/': 'Electronics counter',
      '/dashboard': 'Shop overview',
      '/products': 'Electronics',
      '/inventory': 'Models & stock',
      '/finance': 'Accounts',
      '/reports': 'Sales reports',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'brand', label: 'Brand', hint: 'Manufacturer brand'),
      BusinessLayoutProductField(
          key: 'model', label: 'Model', hint: 'Product model'),
      BusinessLayoutProductField(
          key: 'warranty', label: 'Warranty', hint: 'e.g. 12 months'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'hardware',
    name: 'Hardware & building supplies',
    description: 'Prioritise counter sales, stock and business accounts.',
    productSingular: 'Item',
    icon: Icons.handyman_rounded,
    productsLabel: 'Stock items',
    productCodeLabel: 'Item code / barcode (optional)',
    productCodeHint: 'Enter the item code or scan a barcode',
    productNameHint: 'e.g. Galvanized roofing sheets — 3 m',
    catalogSearchHint: 'Search stock items by name or code...',
    posSearchHint: 'Search products, code or barcode',
    priorityPaths: ['/', '/inventory', '/products', '/finance', '/dashboard'],
    defaultVisiblePaths: _hardwareActionPaths,
    defaultActionLabels: {
      '/': 'Counter sale',
      '/dashboard': 'Counter overview',
      '/products': 'Building supplies',
      '/inventory': 'Stock control',
      '/finance': 'Accounts',
      '/reports': 'Sales reports',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'material', label: 'Material', hint: 'e.g. Galvanized steel'),
      BusinessLayoutProductField(
          key: 'dimensions', label: 'Dimensions', hint: 'e.g. 3 m × 1 m'),
      BusinessLayoutProductField(
          key: 'grade', label: 'Grade / specification', hint: 'Product grade'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'beauty',
    name: 'Beauty & personal care',
    description: 'Keep checkout, the catalogue and customer records nearby.',
    productSingular: 'Product',
    icon: Icons.spa_rounded,
    productsLabel: 'Products',
    productCodeLabel: 'SKU / barcode (optional)',
    productCodeHint: 'Enter the SKU or scan a barcode',
    productNameHint: 'e.g. Shea butter cream (250 ml)',
    catalogSearchHint: 'Search products by name or code...',
    posSearchHint: 'Search products by name, code or barcode',
    priorityPaths: ['/', '/products', '/customers', '/inventory', '/dashboard'],
    defaultVisiblePaths: _beautyActionPaths,
    defaultActionLabels: {
      '/': 'Checkout',
      '/dashboard': 'Shop overview',
      '/products': 'Beauty products',
      '/inventory': 'Stock',
      '/customers': 'Clients',
      '/reports': 'Sales reports',
    },
    customerSingular: 'Client',
    customersLabel: 'Clients',
    productFields: [
      BusinessLayoutProductField(
          key: 'brand', label: 'Brand', hint: 'Product brand'),
      BusinessLayoutProductField(
          key: 'shade', label: 'Shade', hint: 'e.g. Warm beige'),
      BusinessLayoutProductField(
          key: 'size', label: 'Size / volume', hint: 'e.g. 250 ml'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'wholesale',
    name: 'Wholesale & distribution',
    description: 'Bring stock movement, sales and business accounts forward.',
    productSingular: 'Item',
    icon: Icons.local_shipping_rounded,
    productsLabel: 'Stock items',
    productCodeLabel: 'Item code / barcode (optional)',
    productCodeHint: 'Enter the item code or scan a barcode',
    productNameHint: 'e.g. Cooking oil — 20 litre jerrycan',
    defaultBaseUnit: 'piece',
    catalogSearchHint: 'Search stock items by name or code...',
    posSearchHint: 'Search stock items by name, code or barcode',
    priorityPaths: ['/', '/inventory', '/finance', '/products', '/customers'],
    defaultVisiblePaths: _wholesaleActionPaths,
    defaultPosProductView: 'list',
    defaultPosQuickActions: [
      'customer',
      'cart',
      'held_sales',
      'hold_sale',
      'price_list',
      'inventory',
      'reports',
    ],
    defaultActionLabels: {
      '/': 'Wholesale sale',
      '/dashboard': 'Business overview',
      '/products': 'Stock items',
      '/inventory': 'Stock movement',
      '/finance': 'Accounts & credit',
      '/customers': 'Trade customers',
      '/reports': 'Sales reports',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'packSize', label: 'Pack / case size', hint: 'e.g. 12 bottles'),
      BusinessLayoutProductField(
          key: 'manufacturer', label: 'Manufacturer', hint: 'Supplier brand'),
      BusinessLayoutProductField(
          key: 'tradeCode', label: 'Trade code', hint: 'Optional code'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'stationery',
    name: 'Stationery & office supplies',
    description: 'Keep stationery, stock and repeat customers close.',
    productSingular: 'Item',
    icon: Icons.edit_note_rounded,
    productsLabel: 'Stationery',
    productCodeLabel: 'Item code / barcode (optional)',
    productCodeHint: 'Enter the item code or scan a barcode',
    productNameHint: 'e.g. A4 exercise book — 200 pages',
    catalogSearchHint: 'Search stationery by name or code...',
    posSearchHint: 'Search stationery by name, code or barcode',
    priorityPaths: ['/dashboard', '/products', '/', '/inventory', '/customers'],
    defaultVisiblePaths: _stationeryActionPaths,
    defaultPosProductView: 'list',
    defaultActionLabels: {
      '/': 'Counter sale',
      '/dashboard': 'Shop overview',
      '/products': 'Stationery',
      '/inventory': 'Stock',
      '/customers': 'Customers',
      '/reports': 'Sales reports',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'paperSize', label: 'Paper size', hint: 'e.g. A4'),
      BusinessLayoutProductField(
          key: 'pages', label: 'Pages / sheet count', hint: 'e.g. 200 pages'),
      BusinessLayoutProductField(
          key: 'brand', label: 'Brand', hint: 'Manufacturer brand'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'auto_parts',
    name: 'Motor parts & accessories',
    description: 'Put counter sales, part lookup and stock control first.',
    productSingular: 'Part',
    icon: Icons.car_repair_rounded,
    productsLabel: 'Parts & accessories',
    productCodeLabel: 'Part number / barcode (optional)',
    productCodeHint: 'Enter the part number or scan a barcode',
    productNameHint: 'e.g. Toyota Axio oil filter',
    catalogSearchHint: 'Search parts by name or part number...',
    posSearchHint: 'Search parts by name, part number or barcode',
    priorityPaths: ['/', '/products', '/inventory', '/customers', '/finance'],
    defaultVisiblePaths: _autoPartsActionPaths,
    defaultPosProductView: 'list',
    defaultActionLabels: {
      '/': 'Parts counter',
      '/dashboard': 'Parts overview',
      '/products': 'Parts & accessories',
      '/inventory': 'Parts stock',
      '/customers': 'Customers',
      '/finance': 'Accounts',
      '/reports': 'Sales reports',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'manufacturer', label: 'Manufacturer', hint: 'Part maker'),
      BusinessLayoutProductField(
          key: 'compatibleVehicles',
          label: 'Compatible vehicles',
          hint: 'e.g. Toyota Axio 2012–2018'),
      BusinessLayoutProductField(
          key: 'oemPartNumber',
          label: 'OEM part number',
          hint: 'OEM reference'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'pharmacy_retail',
    name: 'Pharmacy & health shop',
    description:
        'Keep product lookup, stock checks and customer accounts close at hand.',
    productSingular: 'Item',
    icon: Icons.medical_services_rounded,
    productsLabel: 'Health products',
    productCodeLabel: 'Product code / barcode (optional)',
    productCodeHint: 'Enter the product code or scan a barcode',
    productNameHint: 'e.g. Vitamin C tablets (100 mg)',
    defaultBaseUnit: 'pack',
    catalogSearchHint: 'Search health products by name or code...',
    posSearchHint: 'Search health products or scan a barcode',
    priorityPaths: ['/', '/products', '/inventory', '/customers', '/reports'],
    defaultVisiblePaths: _pharmacyActionPaths,
    defaultPosProductView: 'list',
    defaultActionLabels: {
      '/': 'Checkout',
      '/dashboard': 'Shop overview',
      '/products': 'Health products',
      '/inventory': 'Batches & stock',
      '/customers': 'Customers',
      '/finance': 'Accounts',
      '/reports': 'Sales reports',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'brand', label: 'Brand', hint: 'Manufacturer brand'),
      BusinessLayoutProductField(
          key: 'activeIngredient',
          label: 'Active ingredient',
          hint: 'From the product label'),
      BusinessLayoutProductField(
          key: 'strength', label: 'Strength', hint: 'e.g. 500 mg'),
      BusinessLayoutProductField(
          key: 'dosageForm',
          label: 'Dosage form',
          hint: 'e.g. tablets, syrup, cream'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'bakery_food_counter',
    name: 'Bakery & food counter',
    description:
        'Put quick checkout, menu items and daily stock within easy reach.',
    productSingular: 'Item',
    icon: Icons.bakery_dining_rounded,
    productsLabel: 'Menu & goods',
    productCodeLabel: 'PLU / barcode (optional)',
    productCodeHint: 'Enter a PLU or scan a barcode',
    productNameHint: 'e.g. Brown loaf — large',
    catalogSearchHint: 'Search menu items by name or code...',
    posSearchHint: 'Search menu items or scan a barcode',
    priorityPaths: ['/', '/products', '/inventory', '/reports', '/finance'],
    defaultVisiblePaths: _foodCounterActionPaths,
    defaultActionLabels: {
      '/': 'Counter',
      '/dashboard': 'Today’s overview',
      '/products': 'Menu & goods',
      '/inventory': 'Ingredients & stock',
      '/finance': 'Cash & accounts',
      '/reports': 'Daily sales',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'servingSize', label: 'Serving size', hint: 'e.g. 500 g loaf'),
      BusinessLayoutProductField(
          key: 'ingredients', label: 'Ingredients', hint: 'Optional notes'),
      BusinessLayoutProductField(
          key: 'dietaryNotes', label: 'Dietary notes', hint: 'Allergen notes'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'agrovet',
    name: 'Agrovet & farm supplies',
    description:
        'Find farm inputs quickly and keep batches, stock and farmer accounts close.',
    productSingular: 'Farm input',
    icon: Icons.agriculture_rounded,
    productsLabel: 'Farm supplies',
    productCodeLabel: 'Product code / barcode (optional)',
    productCodeHint: 'Enter the product code or scan a barcode',
    productNameHint: 'e.g. Dairy meal — 20 kg bag',
    defaultBaseUnit: 'pack',
    catalogSearchHint: 'Search farm supplies by name or code...',
    posSearchHint: 'Search farm supplies or scan a barcode',
    priorityPaths: ['/', '/inventory', '/products', '/customers', '/reports'],
    defaultVisiblePaths: _agrovetActionPaths,
    defaultPosProductView: 'list',
    customerSingular: 'Farmer',
    customersLabel: 'Farm customers',
    defaultActionLabels: {
      '/': 'Counter sale',
      '/dashboard': 'Farm shop overview',
      '/products': 'Farm supplies',
      '/inventory': 'Batches & stock',
      '/customers': 'Farm customers',
      '/finance': 'Accounts & credit',
      '/reports': 'Sales reports',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'cropOrAnimal',
          label: 'Crop / animal',
          hint: 'Intended use or species'),
      BusinessLayoutProductField(
          key: 'activeIngredient',
          label: 'Active ingredient',
          hint: 'From the product label'),
      BusinessLayoutProductField(
          key: 'packSize', label: 'Pack size', hint: 'e.g. 1 litre'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'butchery',
    name: 'Butchery & meat shop',
    description:
        'Make weight-based selling, fresh stock and daily sales easy to reach.',
    productSingular: 'Meat item',
    icon: Icons.kebab_dining_rounded,
    productsLabel: 'Meat & cuts',
    productCodeLabel: 'Item code / barcode (optional)',
    productCodeHint: 'Enter an item code or scan a barcode',
    productNameHint: 'e.g. Beef fillet — fresh',
    defaultBaseUnit: 'kg',
    defaultAllowFractions: true,
    catalogSearchHint: 'Search meat and cuts by name...',
    posSearchHint: 'Search cuts or scan a barcode',
    priorityPaths: ['/', '/products', '/inventory', '/reports', '/finance'],
    defaultVisiblePaths: _butcheryActionPaths,
    defaultActionLabels: {
      '/': 'Meat counter',
      '/dashboard': 'Shop overview',
      '/products': 'Meat & cuts',
      '/inventory': 'Fresh stock',
      '/customers': 'Customers',
      '/finance': 'Cash & credit',
      '/reports': 'Daily sales',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'cut', label: 'Cut', hint: 'e.g. Sirloin'),
      BusinessLayoutProductField(
          key: 'origin', label: 'Source', hint: 'Supplier or farm'),
      BusinessLayoutProductField(
          key: 'storageNotes', label: 'Storage notes', hint: 'Optional notes'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'beverages',
    name: 'Beverage & liquor shop',
    description:
        'Speed up bottle and crate sales with drinks, stock and cash flow close by.',
    productSingular: 'Beverage',
    icon: Icons.liquor_rounded,
    productsLabel: 'Drinks',
    productCodeLabel: 'SKU / barcode (optional)',
    productCodeHint: 'Enter the SKU or scan a barcode',
    productNameHint: 'e.g. Soda — 500 ml bottle',
    defaultBaseUnit: 'bottle',
    catalogSearchHint: 'Search drinks by name or barcode...',
    posSearchHint: 'Search drinks or scan a barcode',
    priorityPaths: ['/', '/products', '/inventory', '/finance', '/reports'],
    defaultVisiblePaths: _beveragesActionPaths,
    defaultActionLabels: {
      '/': 'Quick counter',
      '/dashboard': 'Shop overview',
      '/products': 'Drinks',
      '/inventory': 'Bottles & crates',
      '/customers': 'Customers',
      '/finance': 'Cash & credit',
      '/reports': 'Daily sales',
    },
    productFields: [
      BusinessLayoutProductField(
          key: 'brand', label: 'Brand', hint: 'Drink brand'),
      BusinessLayoutProductField(
          key: 'packSize', label: 'Container / pack size', hint: 'e.g. 500 ml'),
      BusinessLayoutProductField(
          key: 'alcoholContent',
          label: 'Alcohol content',
          hint: 'Leave blank when not applicable'),
    ],
  ),
  BusinessLayoutPreset(
    id: 'custom',
    name: 'Custom layout',
    description: 'Choose the work areas your team uses most.',
    productSingular: 'Product',
    icon: Icons.tune_rounded,
    productsLabel: 'Products',
    productCodeLabel: 'SKU / barcode (optional)',
    productCodeHint: 'Leave blank to generate automatically',
    productNameHint: 'Enter a clear product name',
    catalogSearchHint: 'Search products by name...',
    posSearchHint: 'Search products or scan a barcode',
    priorityPaths: [],
  ),
];

/// Search aliases cover the words a merchant is likely to use when choosing a
/// trade profile, including common regional terms and spelling variants.
/// Keep these separate from display names so the UI remains concise.
const Map<String, List<String>> _businessLayoutSearchAliases = {
  'general_retail': ['retail', 'store', 'shop', 'duka', 'kiosk', 'supermarket'],
  'service_counter': [
    'service',
    'services',
    'salon',
    'barber',
    'barbershop',
    'spa',
    'nail salon',
    'repair shop',
    'phone repair',
    'tailor',
    'mechanic',
    'service business',
  ],
  'bookshop': [
    'bookstore',
    'book store',
    'book shop',
    'books',
    'textbooks',
    'school books',
  ],
  'kamukunji_counter': [
    'kamkunji',
    'kamukunji',
    'open air market',
    'market trader',
    'wholesale market',
    'sales counter',
  ],
  'grocery': [
    'grocer',
    'grocery store',
    'mini market',
    'minimarket',
    'mini mart',
    'fresh produce',
    'duka la mboga',
  ],
  'cafe_takeaway': [
    'cafe',
    'café',
    'coffee shop',
    'restaurant',
    'takeaway',
    'fast food',
    'food service',
  ],
  'market_stall': [
    'market stall',
    'street vendor',
    'hawker',
    'mobile trader',
    'open air market',
  ],
  'fashion': [
    'clothing',
    'clothes',
    'apparel',
    'boutique',
    'shoes',
    'fashion shop',
  ],
  'electronics': ['phone shop', 'phones', 'gadgets', 'electronics shop'],
  'hardware': [
    'building materials',
    'construction supplies',
    'tools',
    'hardware store',
  ],
  'beauty': ['cosmetics', 'beauty shop', 'personal care', 'skin care'],
  'wholesale': ['wholesaler', 'bulk sales', 'distributor', 'distribution'],
  'stationery': [
    'stationary',
    'school supplies',
    'office supplies',
    'office stationery',
  ],
  'auto_parts': [
    'car parts',
    'spare parts',
    'motor spares',
    'automotive',
    'vehicle parts',
  ],
  'pharmacy_retail': [
    'pharmacy',
    'chemist',
    'drugstore',
    'medical supplies',
    'health shop',
  ],
  'bakery_food_counter': ['bakery', 'bread', 'pastries', 'food counter'],
  'agrovet': [
    'farm supplies',
    'agricultural supplies',
    'livestock supplies',
    'animal feed',
  ],
  'butchery': ['butcher', 'meat shop', 'meat counter'],
  'beverages': ['liquor', 'wine', 'spirits', 'beer shop', 'drinks shop'],
  'custom': ['other', 'other shop', 'custom shop', 'none of these'],
};

/// Matches display names, descriptions, stable profile IDs, or merchant
/// vocabulary. Both setup and settings use this helper to keep discovery
/// behavior consistent.
bool businessLayoutProfileMatchesSearch(
  BusinessLayoutPreset preset,
  String query,
) {
  final normalizedQuery = _normalizeBusinessLayoutSearch(query);
  if (normalizedQuery.isEmpty) return true;
  final searchableTerms = [
    preset.name,
    preset.description,
    preset.id,
    ...?_businessLayoutSearchAliases[preset.id],
  ];
  return searchableTerms.any((term) {
    final normalizedTerm = _normalizeBusinessLayoutSearch(term);
    return normalizedTerm.contains(normalizedQuery) ||
        normalizedQuery
            .split(' ')
            .every((word) => normalizedTerm.contains(word));
  });
}

String _normalizeBusinessLayoutSearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

class BusinessLayoutConfig {
  const BusinessLayoutConfig({
    required this.preset,
    required this.priorityPaths,
    this.additionalProfileIds = const [],
    this.hiddenPaths = const [],
    this.actionLabels = const {},
    this.terminologyOverrides = const {},
    this.baseUnitOverride,
    this.allowFractionsForNewProducts,
    this.trackInventoryForNewProducts,
    this.startPath,
    this.posProductView,
    this.showPosCategories,
    this.showPosFavorites,
    this.showPosCustomer,
    this.posQuickActions,
    this.posProductPages = const [],
    this.dashboardMetrics,
    this.dashboardSections,
    this.productFieldKeys,
    this.customProductFields = const [],
  });

  final BusinessLayoutPreset preset;
  final List<String> priorityPaths;

  /// Optional complementary trades. The primary profile keeps control of
  /// terminology and selling defaults; additional profiles add useful fields,
  /// areas and shortcuts for mixed-category shops.
  final List<String> additionalProfileIds;

  /// Work areas hidden from this tenant's navigation. This is presentation
  /// only: permissions and the underlying shop data are unchanged.
  final List<String> hiddenPaths;
  final Map<String, String> actionLabels;
  final Map<String, String> terminologyOverrides;
  final String? baseUnitOverride;
  final bool? allowFractionsForNewProducts;
  final bool? trackInventoryForNewProducts;
  final String? startPath;
  final String? posProductView;
  final bool? showPosCategories;
  final bool? showPosFavorites;
  final bool? showPosCustomer;
  final List<String>? posQuickActions;
  final List<BusinessLayoutProductPage> posProductPages;
  final List<String>? dashboardMetrics;
  final List<String>? dashboardSections;
  final List<String>? productFieldKeys;
  final List<BusinessLayoutProductField> customProductFields;

  String get profileId => preset.id;
  List<BusinessLayoutPreset> get additionalPresets =>
      businessLayoutAdditionalPresets(profileId, additionalProfileIds);

  String get profileSummary => [
        preset.name,
        ...additionalPresets.map((profile) => profile.name),
      ].join(' + ');
  String get productSingular =>
      _term('productSingular', preset.productSingular);
  String get productsLabel => _term('productsLabel', preset.productsLabel);
  String get catalogSearchHint =>
      _term('catalogSearchHint', preset.catalogSearchHint);
  String get posSearchHint => _term('posSearchHint', preset.posSearchHint);
  String get productCodeLabel =>
      _term('productCodeLabel', preset.productCodeLabel);
  String get productCodeHint =>
      _term('productCodeHint', preset.productCodeHint);
  String get productNameHint =>
      _term('productNameHint', preset.productNameHint);
  String get customerSingular =>
      _term('customerSingular', preset.customerSingular);
  String get customersLabel => _term('customersLabel', preset.customersLabel);
  String get defaultBaseUnit => businessLayoutUnits.contains(baseUnitOverride)
      ? baseUnitOverride!
      : preset.defaultBaseUnit;
  bool get effectiveAllowFractionsForNewProducts =>
      allowFractionsForNewProducts ?? preset.defaultAllowFractions;
  bool get effectiveTrackInventoryForNewProducts =>
      trackInventoryForNewProducts ??
      preset.defaultTrackInventoryForNewProducts;
  String get effectivePosProductView =>
      posProductView == 'grid' || posProductView == 'list'
          ? posProductView!
          : preset.defaultPosProductView;
  bool get effectiveShowPosCategories =>
      showPosCategories ?? preset.defaultShowPosCategories;
  bool get effectiveShowPosFavorites =>
      showPosFavorites ?? preset.defaultShowPosFavorites;
  bool get effectiveShowPosCustomer =>
      showPosCustomer ?? preset.defaultShowPosCustomer;
  List<String> get effectivePosQuickActions {
    final available =
        businessLayoutPosActions.map((action) => action.id).toSet();
    final configured = posQuickActions ??
        businessLayoutDefaultPosQuickActions(profileId, additionalProfileIds);
    final selected = configured
        .where(available.contains)
        .where((id) => id != 'favorites' || effectiveShowPosFavorites)
        .where((id) => id != 'customer' || effectiveShowPosCustomer)
        // Hidden work areas must not reappear as POS toolbar shortcuts.
        .where((id) {
          final path = businessLayoutPosAction(id)?.path;
          return path == null || isActionVisible(path);
        })
        .toSet()
        .toList(growable: false);
    if (selected.isNotEmpty) return selected;
    return const ['cart'];
  }

  bool isActionVisible(String path) =>
      !businessLayoutCanHideAction(path) || !hiddenPaths.contains(path);
  List<String> get effectiveDashboardMetrics {
    final available = businessLayoutDashboardMetrics.map((metric) => metric.id);
    final configured = dashboardMetrics ?? preset.defaultDashboardMetrics;
    final selected = configured
        .where((id) => available.contains(id))
        .toSet()
        .toList(growable: false);
    return selected.isEmpty ? preset.defaultDashboardMetrics : selected;
  }

  List<String> get effectiveDashboardSections {
    final available =
        businessLayoutDashboardSections.map((section) => section.id).toSet();
    final configured = dashboardSections ?? preset.defaultDashboardSections;
    final selected =
        configured.where(available.contains).toSet().toList(growable: false);
    return selected.isEmpty ? preset.defaultDashboardSections : selected;
  }

  bool showsDashboardSection(String id) =>
      effectiveDashboardSections.contains(id);

  List<BusinessLayoutProductField> get effectiveProductFields {
    final selectedKeys = productFieldKeys?.toSet();
    final profileFields = <BusinessLayoutProductField>[
      ...preset.productFields,
      for (final profile in additionalPresets) ...profile.productFields,
    ];
    final selectedPresetFields = profileFields.where(
      (field) => selectedKeys == null || selectedKeys.contains(field.key),
    );
    final fields = <BusinessLayoutProductField>[
      ...selectedPresetFields,
      ...customProductFields.where(
        (field) => selectedKeys == null || selectedKeys.contains(field.key),
      ),
    ];
    final seen = <String>{};
    return fields.where((field) => seen.add(field.key)).toList(growable: false);
  }

  String _term(String key, String fallback) {
    final value = terminologyOverrides[key]?.trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  String actionLabel(String path, String fallback) {
    final custom = actionLabels[path]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    if (!preset.defaultActionLabels.containsKey(path)) {
      for (final profile in additionalPresets) {
        if (profile.defaultActionLabels.containsKey(path)) {
          return profile.actionLabel(path, fallback);
        }
      }
    }
    return preset.actionLabel(path, fallback);
  }

  String homePathFor(RolePermissions permissions) {
    final candidates = <String>[
      if (startPath != null) startPath!,
      permissions.homePath,
      ...priorityPaths,
      '/',
      '/settings',
    ];
    for (final path in candidates) {
      if (isActionVisible(path) && _canOpenLayoutStartPath(permissions, path)) {
        return path;
      }
    }
    return permissions.homePath;
  }

  Map<String, dynamic> toJson() => {
        'version': 12,
        'profileId': profileId,
        'additionalProfileIds': additionalProfileIds,
        'priorityPaths': priorityPaths,
        'hiddenPaths': hiddenPaths,
        'actionLabels': actionLabels,
        'terminology': terminologyOverrides,
        'defaultBaseUnit': defaultBaseUnit,
        'allowFractionsForNewProducts': effectiveAllowFractionsForNewProducts,
        'trackInventoryForNewProducts': effectiveTrackInventoryForNewProducts,
        'posProductView': effectivePosProductView,
        'showPosCategories': effectiveShowPosCategories,
        'showPosFavorites': effectiveShowPosFavorites,
        'showPosCustomer': effectiveShowPosCustomer,
        'posQuickActions': effectivePosQuickActions,
        'posProductPages': posProductPages
            .map((page) => page.toJson())
            .toList(growable: false),
        'dashboardMetrics': effectiveDashboardMetrics,
        'dashboardSections': effectiveDashboardSections,
        if (productFieldKeys != null) 'productFieldKeys': productFieldKeys,
        if (customProductFields.isNotEmpty)
          'customProductFields': customProductFields
              .map((field) => {
                    'key': field.key,
                    'label': field.label,
                    'hint': field.hint,
                  })
              .toList(),
        if (startPath != null) 'startPath': startPath,
      };
}

/// Returns valid complementary trade profiles, preserving merchant order.
/// Custom layout is intentionally primary-only: it contributes no suggested
/// fields or navigation pack of its own.
List<BusinessLayoutPreset> businessLayoutAdditionalPresets(
  String? primaryProfileId,
  Iterable<String> additionalProfileIds,
) {
  final seen = <String>{if (primaryProfileId != null) primaryProfileId};
  final result = <BusinessLayoutPreset>[];
  for (final id in additionalProfileIds) {
    if (result.length >= 3 || id == 'custom' || !seen.add(id)) continue;
    final profile = businessLayoutPresets
        .where((candidate) => candidate.id == id)
        .firstOrNull;
    if (profile != null) result.add(profile);
  }
  return result;
}

/// Recommended navigation order for a primary profile and any selected
/// complementary trades. The primary profile always gets first placement.
List<String> businessLayoutDefaultPriorityPaths(
  String? primaryProfileId,
  Iterable<String> additionalProfileIds,
) {
  final primary = businessLayoutPreset(primaryProfileId);
  final paths = <String>{...primary.priorityPaths};
  for (final profile in businessLayoutAdditionalPresets(
      primaryProfileId, additionalProfileIds)) {
    paths.addAll(profile.priorityPaths);
  }
  return paths.toList(growable: false);
}

/// Returns the combined recommended visibility set. Custom layout keeps all
/// work areas available; named profiles combine their suggested work areas.
List<String> businessLayoutDefaultHiddenPaths(
  String? primaryProfileId,
  Iterable<String> additionalProfileIds,
) {
  final primary = businessLayoutPreset(primaryProfileId);
  if (primary.defaultVisiblePaths.isEmpty) return const [];
  final visible = <String>{...primary.defaultVisiblePaths};
  for (final profile in businessLayoutAdditionalPresets(
      primaryProfileId, additionalProfileIds)) {
    visible.addAll(profile.defaultVisiblePaths);
  }
  return businessLayoutActions
      .where((action) =>
          businessLayoutCanHideAction(action.path) &&
          !visible.contains(action.path))
      .map((action) => action.path)
      .toList(growable: false);
}

/// Recommended visible work areas for a primary profile and complementary
/// trades. POS and Settings stay visible for every profile.
List<String> businessLayoutDefaultVisiblePaths(
  String? primaryProfileId,
  Iterable<String> additionalProfileIds,
) {
  final hidden = businessLayoutDefaultHiddenPaths(
    primaryProfileId,
    additionalProfileIds,
  ).toSet();
  return businessLayoutActions
      .where((action) =>
          businessLayoutCanHideAction(action.path) &&
          !hidden.contains(action.path))
      .map((action) => action.path)
      .toList(growable: false);
}

List<String> businessLayoutDefaultProductFieldKeys(
  String? primaryProfileId,
  Iterable<String> additionalProfileIds, {
  Iterable<BusinessLayoutProductField> customFields = const [],
}) {
  final profiles = [
    businessLayoutPreset(primaryProfileId),
    ...businessLayoutAdditionalPresets(primaryProfileId, additionalProfileIds),
  ];
  return <String>{
    for (final profile in profiles)
      for (final field in profile.productFields) field.key,
    for (final field in customFields) field.key,
  }.toList(growable: false);
}

List<String> businessLayoutDefaultDashboardMetrics(
  String? primaryProfileId,
  Iterable<String> additionalProfileIds,
) {
  final profiles = [
    businessLayoutPreset(primaryProfileId),
    ...businessLayoutAdditionalPresets(primaryProfileId, additionalProfileIds),
  ];
  return <String>{
    for (final profile in profiles) ...profile.defaultDashboardMetrics,
  }.toList(growable: false);
}

/// Recommended POS actions for a primary profile and complementary trades.
/// Preserve the primary profile's order, then append only new actions from
/// each additional profile.
List<String> businessLayoutDefaultPosQuickActions(
  String? primaryProfileId,
  Iterable<String> additionalProfileIds,
) {
  final profiles = [
    businessLayoutPreset(primaryProfileId),
    ...businessLayoutAdditionalPresets(primaryProfileId, additionalProfileIds),
  ];
  return <String>{
    for (final profile in profiles) ...profile.defaultPosQuickActions,
  }.toList(growable: false);
}

List<String> businessLayoutDefaultDashboardSections(
  String? primaryProfileId,
  Iterable<String> additionalProfileIds,
) {
  final profiles = [
    businessLayoutPreset(primaryProfileId),
    ...businessLayoutAdditionalPresets(primaryProfileId, additionalProfileIds),
  ];
  return <String>{
    for (final profile in profiles) ...profile.defaultDashboardSections,
  }.toList(growable: false);
}

/// Reconciles a merchant's saved ordering when complementary profiles change.
///
/// Values recommended by both the old and new profile sets keep the merchant's
/// current enabled/disabled state and order. Recommendations that no longer
/// apply are removed, newly recommended values are appended, and unrelated
/// merchant additions stay in place. The serialized layout does not track
/// where each individual choice came from, so this is the least surprising
/// way to apply changed recommendations without resetting the whole layout.
List<String> businessLayoutReconcileRecommendations({
  required Iterable<String> current,
  required Iterable<String> previousRecommendations,
  required Iterable<String> nextRecommendations,
}) {
  final previousValues = previousRecommendations.toList(growable: false);
  final nextValues = nextRecommendations.toList(growable: false);
  final previous = previousValues.toSet();
  final next = nextValues.toSet();
  final result = <String>[];
  final seen = <String>{};

  for (final value in current) {
    if (previous.contains(value) && !next.contains(value)) continue;
    if (seen.add(value)) result.add(value);
  }

  for (final value in nextValues) {
    if (!previous.contains(value) && seen.add(value)) result.add(value);
  }

  return result;
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
  final rawAdditionalProfileIds = layout['additionalProfileIds'];
  final additionalProfileIds = rawAdditionalProfileIds is List
      ? businessLayoutAdditionalPresets(
              preset.id, rawAdditionalProfileIds.map((id) => id.toString()))
          .map((profile) => profile.id)
          .toList(growable: false)
      : const <String>[];
  final rawHiddenPaths = layout['hiddenPaths'];
  // Older app versions only stored shortcut order. Do not infer hidden areas
  // from a preset for those tenants: choosing a profile is an explicit action,
  // and silently hiding existing work areas during an upgrade is disruptive.
  final hiddenPaths = rawHiddenPaths is List
      ? rawHiddenPaths
          .map((path) => path.toString())
          .where((path) =>
              businessLayoutCanHideAction(path) &&
              businessLayoutActions.any((action) => action.path == path))
          .toSet()
          .toList(growable: false)
      : const <String>[];
  final rawPaths = layout['priorityPaths'];
  final defaultPaths = businessLayoutDefaultPriorityPaths(
    preset.id,
    additionalProfileIds,
  ).where((path) => !hiddenPaths.contains(path)).toList(growable: false);
  final paths = rawPaths is List
      ? rawPaths
          .map((path) => path.toString())
          .where((path) =>
              businessLayoutActions.any((action) => action.path == path) &&
              !hiddenPaths.contains(path))
          .toSet()
          .toList()
      : defaultPaths;
  final rawLabels = layout['actionLabels'];
  final actionLabels = <String, String>{};
  if (rawLabels is Map) {
    for (final entry in rawLabels.entries) {
      final path = entry.key.toString();
      final label = entry.value?.toString().trim() ?? '';
      if (businessLayoutActions.any((action) => action.path == path) &&
          label.isNotEmpty) {
        actionLabels[path] = label.length > 32 ? label.substring(0, 32) : label;
      }
    }
  }
  const terminologyKeys = {
    'productSingular',
    'productsLabel',
    'catalogSearchHint',
    'posSearchHint',
    'productCodeLabel',
    'productCodeHint',
    'productNameHint',
    'customerSingular',
    'customersLabel',
  };
  final terminologyOverrides = <String, String>{};
  final rawTerminology = layout['terminology'];
  if (rawTerminology is Map) {
    for (final entry in rawTerminology.entries) {
      final key = entry.key.toString();
      final value = entry.value?.toString().trim() ?? '';
      if (terminologyKeys.contains(key) && value.isNotEmpty) {
        terminologyOverrides[key] =
            value.length > 80 ? value.substring(0, 80) : value;
      }
    }
  }
  final rawBaseUnit = layout['defaultBaseUnit']?.toString();
  final rawDashboardMetrics = layout['dashboardMetrics'];
  final dashboardMetricIds =
      businessLayoutDashboardMetrics.map((metric) => metric.id).toSet();
  final dashboardMetrics = rawDashboardMetrics is List
      ? rawDashboardMetrics
          .map((id) => id.toString())
          .where(dashboardMetricIds.contains)
          .toSet()
          .toList(growable: false)
      : preset.defaultDashboardMetrics;
  final rawDashboardSections = layout['dashboardSections'];
  final availableDashboardSectionIds =
      businessLayoutDashboardSections.map((section) => section.id).toSet();
  final dashboardSections = rawDashboardSections is List
      ? rawDashboardSections
          .map((id) => id.toString())
          .where(availableDashboardSectionIds.contains)
          .toSet()
          .toList(growable: false)
      : preset.defaultDashboardSections;
  final availableProductFieldKeys = businessLayoutDefaultProductFieldKeys(
    preset.id,
    additionalProfileIds,
  ).toSet();
  final customProductFields = <BusinessLayoutProductField>[];
  final rawCustomProductFields = layout['customProductFields'];
  if (rawCustomProductFields is List) {
    final seenKeys = <String>{...availableProductFieldKeys};
    for (final rawField in rawCustomProductFields) {
      if (rawField is! Map) continue;
      final key = rawField['key']?.toString().trim() ?? '';
      final label = rawField['label']?.toString().trim() ?? '';
      final hint = rawField['hint']?.toString().trim() ?? '';
      if (!RegExp(r'^[a-z][a-zA-Z0-9_]{0,39}$').hasMatch(key) ||
          label.isEmpty ||
          label.length > 40 ||
          seenKeys.contains(key)) {
        continue;
      }
      seenKeys.add(key);
      customProductFields.add(BusinessLayoutProductField(
        key: key,
        label: label,
        hint: hint.length > 80 ? hint.substring(0, 80) : hint,
      ));
      if (customProductFields.length >= 20) break;
    }
  }
  final rawProductFieldKeys = layout['productFieldKeys'];
  final knownProductFieldKeys = {
    ...availableProductFieldKeys,
    ...customProductFields.map((field) => field.key),
  };
  final productFieldKeys = rawProductFieldKeys is List
      ? rawProductFieldKeys
          .map((key) => key.toString())
          .where(knownProductFieldKeys.contains)
          .toSet()
          .toList(growable: false)
      : null;
  final rawStartPath = layout['startPath']?.toString();
  final rawPosQuickActions = layout['posQuickActions'];
  final posActionIds =
      businessLayoutPosActions.map((action) => action.id).toSet();
  final posQuickActions = rawPosQuickActions is List
      ? rawPosQuickActions
          .map((id) => id.toString())
          .where(posActionIds.contains)
          .toSet()
          .toList(growable: false)
      : null;
  final rawPosProductPages = layout['posProductPages'];
  final posProductPages = <BusinessLayoutProductPage>[];
  if (rawPosProductPages is List) {
    final seenPageIds = <String>{};
    final seenPageNames = <String>{};
    for (final rawPage in rawPosProductPages) {
      if (rawPage is! Map || posProductPages.length >= 12) continue;
      final id = rawPage['id']?.toString().trim() ?? '';
      final name = rawPage['name']?.toString().trim() ?? '';
      final rawProductIds = rawPage['productIds'];
      if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id) ||
          name.isEmpty ||
          name.length > 28 ||
          rawProductIds is! List) {
        continue;
      }
      if (!seenPageIds.add(id) || !seenPageNames.add(name.toLowerCase())) {
        continue;
      }
      final productIds = rawProductIds
          .map((productId) => productId.toString().trim())
          .where((productId) => productId.isNotEmpty && productId.length <= 80)
          .toSet()
          .take(32)
          .toList(growable: false);
      if (productIds.isEmpty) continue;
      posProductPages.add(BusinessLayoutProductPage(
        id: id,
        name: name,
        productIds: productIds,
      ));
    }
  }
  final startPath = rawStartPath != null &&
          paths.contains(rawStartPath) &&
          !hiddenPaths.contains(rawStartPath)
      ? rawStartPath
      : null;
  return BusinessLayoutConfig(
    preset: preset,
    priorityPaths: paths,
    additionalProfileIds: additionalProfileIds,
    hiddenPaths: hiddenPaths,
    actionLabels: actionLabels,
    terminologyOverrides: terminologyOverrides,
    baseUnitOverride:
        businessLayoutUnits.contains(rawBaseUnit) ? rawBaseUnit : null,
    allowFractionsForNewProducts: layout['allowFractionsForNewProducts'] is bool
        ? layout['allowFractionsForNewProducts'] as bool
        : null,
    trackInventoryForNewProducts: layout['trackInventoryForNewProducts'] is bool
        ? layout['trackInventoryForNewProducts'] as bool
        : null,
    startPath: startPath,
    posProductView:
        layout['posProductView'] == 'list' || layout['posProductView'] == 'grid'
            ? layout['posProductView'] as String
            : null,
    showPosCategories: layout['showPosCategories'] is bool
        ? layout['showPosCategories'] as bool
        : null,
    showPosFavorites: layout['showPosFavorites'] is bool
        ? layout['showPosFavorites'] as bool
        : null,
    showPosCustomer: layout['showPosCustomer'] is bool
        ? layout['showPosCustomer'] as bool
        : null,
    posQuickActions: posQuickActions,
    posProductPages: posProductPages,
    dashboardMetrics: dashboardMetrics.isEmpty ? null : dashboardMetrics,
    dashboardSections: dashboardSections.isEmpty ? null : dashboardSections,
    productFieldKeys: productFieldKeys,
    customProductFields: customProductFields,
  );
}

/// Keep POS, AI and Settings discoverable so a shop can always trade, reach
/// its primary assistant, and undo a layout change. Other areas can be hidden
/// without changing permissions.
bool businessLayoutCanHideAction(String path) =>
    path != '/' && path != '/ai' && path != '/settings';

/// Whether the current staff member may open an existing app work area.
/// Layout shortcuts use this check so a shop profile never adds access.
bool businessLayoutCanOpenPath(RolePermissions permissions, String path) =>
    _canOpenLayoutStartPath(permissions, path);

bool _canOpenLayoutStartPath(RolePermissions permissions, String path) {
  return switch (path) {
    '/' => permissions.canSeePOS,
    '/dashboard' => permissions.canSeeDashboard,
    '/products' => permissions.canSeeProducts,
    '/inventory' => permissions.canSeeInventory,
    '/customers' => permissions.canSeeCustomers,
    '/finance' => permissions.canViewFinance,
    '/reports' => permissions.canSeeReports,
    '/payments' => permissions.canSeePayments,
    '/receipts' => permissions.canSeeReceipts,
    '/settings' => permissions.canSeeSettings,
    '/shop-alerts' => permissions.has('accountability.view'),
    '/stock-counts' => permissions.has('inventory.stocktake.view'),
    '/containers' => permissions.has('imports.view'),
    '/news' => permissions.has('news.view'),
    '/price-list' => permissions.has('products.view'),
    '/coupons' => permissions.has('coupons.view'),
    '/statements/replies' => permissions.has('statements.share'),
    '/referrals' => permissions.has('referrals.view'),
    '/partners' =>
      permissions.isAdmin || permissions.role == AppRole.storeManager,
    '/ai' => true,
    _ => false,
  };
}

final businessLayoutProvider = Provider<BusinessLayoutConfig>((ref) {
  return businessLayoutFromUser(ref.watch(currentUserProvider));
});
