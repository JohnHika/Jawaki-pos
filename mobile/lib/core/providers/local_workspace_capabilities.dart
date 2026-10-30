import 'package:flutter/material.dart';

import '../auth/app_roles.dart';
import 'business_layout_provider.dart';

/// Work areas that are usable without the retired online POS service.
/// Keep navigation and route access aligned with the local database-backed
/// flows so stale links cannot open cloud-only screens.
class LocalWorkspaceCapabilities {
  const LocalWorkspaceCapabilities._();

  static bool supportsPath(String path) {
    if (path == '/' ||
        path == '/cart' ||
        path == '/payment' ||
        path == '/receipts' ||
        path == '/products' ||
        path == '/price-list' ||
        path == '/inventory' ||
        path == '/inventory/receive-batch' ||
        path == '/inventory/batch-receive' ||
        path == '/stock-counts' ||
        path == '/customers' ||
        path == '/reports' ||
        path == '/reports/analytics' ||
        path == '/reports/inventory-forecast' ||
        path == '/payment-analytics' ||
        path == '/dashboard' ||
        path == '/dashboard/profit-adjustment' ||
        path == '/payments' ||
        path == '/finance' ||
        path == '/mpesa-match' ||
        path == '/settings' ||
        path == '/settings/business-layout' ||
        path == '/settings/ai-gateway' ||
        path == '/settings/archive-history' ||
        path == '/users' ||
        path == '/workspace/unavailable' ||
        path == '/user-guide' ||
        path == '/legal' ||
        path == '/ai/memory' ||
        path == '/cash-flow/end-of-day' ||
        path == '/cash-flow' ||
        path == '/cash-flow/reconciliation' ||
        path == '/ai') {
      return true;
    }

    return path.startsWith('/legal/') ||
        path == '/staff-tour' ||
        path.startsWith('/receipt/') ||
        path.startsWith('/settings/archive-history/') ||
        path.startsWith('/stock-counts/') ||
        path.startsWith('/products/') ||
        path.startsWith('/customers/') ||
        path.startsWith('/dashboard/day/');
  }

  static String unavailableFeatureFor(String path) {
    if (path == '/billing' ||
        path == '/plan-selection' ||
        path == '/settings/subscription' ||
        path == '/activation') {
      return 'Subscriptions and online billing';
    }
    if (path.startsWith('/payments/setup')) return 'Merchant payouts';
    if (path == '/invite-staff' ||
        path == '/accept-invite' ||
        path == '/set-password-after-invite' ||
        path == '/users/invitations') {
      return 'Cross-device staff invitations';
    }
    if (path == '/users/roles' ||
        path.startsWith('/users/roles/') ||
        (path.startsWith('/users/') && path != '/users/invitations')) {
      return 'Shared role templates and permission overrides';
    }
    if (path.startsWith('/partners')) return 'Shop-to-shop connections';
    if (path == '/statements/replies') {
      return 'Customer replies require a hosted statement link';
    }
    if (path.startsWith('/statements')) return 'Online debt statements';
    if (path == '/inventory/request-stock' ||
        path == '/inventory/stock-requests') {
      return 'Staff stock requests need a connected shop workspace';
    }
    if (path == '/inventory/restock-suggestions') {
      return 'Cloud restock suggestions need a connected shop workspace';
    }
    if (path.startsWith('/containers')) {
      return 'Supplier imports and containers';
    }
    if (path == '/coupons') return 'Server-managed coupons';
    if (path == '/referrals') return 'Shop referral codes and invitations';
    if (path == '/settings/operating-hours') {
      return 'Branch operating hours need a connected shop workspace';
    }
    if (path == '/settings/report-bug') return 'Hosted problem reports';
    if (path == '/ai/upgrade') return 'AI plan management';
    if (path.startsWith('/news')) return 'Business news';
    if (path.startsWith('/notifications')) return 'Server notifications';
    if (path.startsWith('/shop-alerts')) return 'Shared shop alerts';
    return 'This feature';
  }

  /// Offer the nearest local workflow when a stale link points at a hosted
  /// action. Alternatives never grant access: the normal route permission
  /// guard still runs after navigation.
  static LocalWorkspaceAlternative? alternativeFor(
    String path,
    RolePermissions permissions, {
    required bool isWorkspaceOwner,
  }) {
    if ((path.startsWith('/users') ||
            path == '/invite-staff' ||
            path == '/accept-invite' ||
            path == '/set-password-after-invite') &&
        isWorkspaceOwner &&
        permissions.canManageUsers) {
      return const LocalWorkspaceAlternative(
        path: '/users',
        label: 'Manage staff on this device',
        icon: Icons.people_alt_rounded,
      );
    }
    if ((path == '/inventory/request-stock' ||
            path == '/inventory/stock-requests' ||
            path == '/inventory/restock-suggestions') &&
        permissions.canSeeInventory) {
      return const LocalWorkspaceAlternative(
        path: '/inventory',
        label: 'Open local inventory',
        icon: Icons.inventory_2_rounded,
      );
    }
    if (path.startsWith('/payments/setup') && permissions.canSeePayments) {
      return const LocalWorkspaceAlternative(
        path: '/payments',
        label: 'View local payment records',
        icon: Icons.payments_rounded,
      );
    }
    if (path == '/statements/replies' && permissions.canSeeCustomers) {
      return const LocalWorkspaceAlternative(
        path: '/customers',
        label: 'Open customer accounts',
        icon: Icons.people_alt_rounded,
      );
    }
    if (path.startsWith('/containers') && permissions.canViewFinance) {
      return const LocalWorkspaceAlternative(
        path: '/finance',
        label: 'Open local supplier records',
        icon: Icons.account_balance_wallet_rounded,
      );
    }
    return null;
  }

  static String homePathFor(
    RolePermissions permissions,
    BusinessLayoutConfig layout,
  ) {
    final candidates = <String>[
      layout.homePathFor(permissions),
      permissions.homePath,
      ...layout.priorityPaths,
      '/dashboard',
      '/',
      '/products',
      '/inventory',
      '/customers',
      '/reports',
      '/payments',
      '/receipts',
      '/ai',
      '/settings',
    ];
    for (final path in candidates) {
      if (path == '/workspace/unavailable' ||
          !supportsPath(path) ||
          !layout.isActionVisible(path) ||
          !businessLayoutCanOpenPath(permissions, path)) {
        continue;
      }
      return path;
    }
    return '/settings';
  }
}

class LocalWorkspaceAlternative {
  const LocalWorkspaceAlternative({
    required this.path,
    required this.label,
    required this.icon,
  });

  final String path;
  final String label;
  final IconData icon;
}
