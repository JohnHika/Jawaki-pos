import 'package:flutter/material.dart';

import '../../../core/auth/app_roles.dart';
import '../../../core/providers/business_layout_provider.dart';
import '../../../core/providers/local_workspace_capabilities.dart';
import '../../../core/theme/design_system.dart';

/// One shortcut on the phone Home page.
class HomeQuickAction {
  const HomeQuickAction({
    required this.path,
    required this.label,
    required this.icon,
  });

  final String path;
  final String label;
  final IconData icon;
}

/// Where a shop's accent comes from: its profile, else the app orange.
Color homeAccentFor(BusinessLayoutConfig layout) =>
    layout.preset.accent ?? DesignColors.accent;

const _icons = <String, IconData>{
  '/products': Icons.inventory_2_rounded,
  '/inventory': Icons.warehouse_rounded,
  '/customers': Icons.people_rounded,
  '/finance': Icons.account_balance_wallet_rounded,
  '/reports': Icons.analytics_rounded,
  '/payments': Icons.payments_rounded,
  '/receipts': Icons.receipt_long_rounded,
};

const _labels = <String, String>{
  '/products': 'Products',
  '/inventory': 'Stock',
  '/customers': 'Customers',
  '/finance': 'Finance',
  '/reports': 'Reports',
  '/payments': 'Payments',
  '/receipts': 'Receipts',
};

/// Shown after the profile's own order when a shop has fewer than [max] areas.
const _fallbackOrder = <String>[
  '/receipts',
  '/products',
  '/customers',
  '/reports',
  '/finance',
];

/// The 3 or 4 shortcuts under Start a sale.
///
/// They follow the shop's layout: the profile's `priorityPaths` come first, so
/// a Kamukunji counter leads with products and stock while a bookshop leads with
/// customers. Sell and Home themselves are left out (the page already has the
/// Start a sale button). Only areas this person may open, that the shop has not
/// hidden and that a device-only shop supports are offered. A layout can only
/// reorder shortcuts, never add access.
List<HomeQuickAction> homeQuickActions({
  required BusinessLayoutConfig layout,
  required RolePermissions permissions,
  required bool localWorkspace,
  int max = 4,
}) {
  bool allowed(String path) =>
      _icons.containsKey(path) &&
      layout.isActionVisible(path) &&
      businessLayoutCanOpenPath(permissions, path) &&
      (!localWorkspace || LocalWorkspaceCapabilities.supportsPath(path));

  final picked = <String>[];
  for (final path in [...layout.priorityPaths, ..._fallbackOrder]) {
    if (picked.length >= max) break;
    if (picked.contains(path) || !allowed(path)) continue;
    picked.add(path);
  }
  return [
    for (final path in picked)
      HomeQuickAction(
        path: path,
        label: layout.actionLabel(path, _labels[path]!),
        icon: _icons[path]!,
      ),
  ];
}
