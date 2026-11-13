import 'package:flutter/material.dart';

/// The sidebar's sections. A phone folds everything into one flat bar and a
/// "More" sheet; a computer has room to show where each place belongs.
enum DesktopNavGroup {
  workspace('Workspace'),
  stock('Stock'),
  money('Money'),
  people('People'),
  more('More');

  const DesktopNavGroup(this.label);
  final String label;
}

/// One place a person can go from the sidebar or the command palette.
@immutable
class DesktopNavItem {
  const DesktopNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.path,
    required this.group,
    this.keywords = const [],
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
  final DesktopNavGroup group;

  /// Extra words the command palette also matches ("sale" finds Sell).
  final List<String> keywords;

  /// True when [location] is this item's page or one of its sub-pages.
  bool matches(String location) {
    if (path == '/') return location == '/';
    return location == path || location.startsWith('$path/');
  }
}

/// Which sidebar section a route belongs to.
DesktopNavGroup desktopGroupFor(String path) {
  switch (path) {
    case '/dashboard':
    case '/':
    case '/ai':
      return DesktopNavGroup.workspace;
    case '/products':
    case '/inventory':
    case '/inventory/request-stock':
    case '/stock-counts':
    case '/containers':
    case '/price-list':
      return DesktopNavGroup.stock;
    case '/payments':
    case '/receipts':
    case '/finance':
    case '/expenses':
    case '/reports':
    case '/coupons':
    case '/mpesa-match':
    case '/cash-flow':
      return DesktopNavGroup.money;
    case '/customers':
    case '/partners':
    case '/statements/replies':
    case '/referrals':
      return DesktopNavGroup.people;
    default:
      return DesktopNavGroup.more;
  }
}

/// Extra search words for the command palette.
List<String> desktopKeywordsFor(String path) {
  switch (path) {
    case '/':
      return const ['sale', 'checkout', 'till', 'pos', 'cart'];
    case '/dashboard':
      return const ['overview', 'today', 'summary'];
    case '/ai':
      return const ['assistant', 'ask', 'chat'];
    case '/products':
      return const ['items', 'catalogue', 'catalog', 'barcode'];
    case '/inventory':
      return const ['stock', 'warehouse', 'receive'];
    case '/reports':
      return const ['analytics', 'sales report', 'profit'];
    case '/payments':
      return const ['mpesa', 'm-pesa', 'cash', 'card'];
    case '/receipts':
      return const ['invoice', 'refund', 'history'];
    case '/customers':
      return const ['debt', 'clients', 'buyers'];
    case '/finance':
      return const ['money', 'books', 'accounts'];
    case '/settings':
      return const ['preferences', 'team', 'printer', 'account', 'update'];
    default:
      return const [];
  }
}
