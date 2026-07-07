import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/di/injection.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/auth/app_roles.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final Widget child;
  const HomeScreen({super.key, required this.child});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<_NavItem> _buildNavItems(RolePermissions perms) {
    final items = <_NavItem>[];
    if (perms.canSeeDashboard) {
      items.add(_NavItem(
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
          label: 'Dashboard',
          path: '/dashboard'));
    }
    items.add(_NavItem(
        icon: Icons.point_of_sale_outlined,
        activeIcon: Icons.point_of_sale_rounded,
        label: 'POS',
        path: '/'));
    // AI Assistant — available to all users
    items.add(_NavItem(
        icon: Icons.auto_awesome_outlined,
        activeIcon: Icons.auto_awesome_rounded,
        label: 'AI',
        path: '/ai'));
    items.add(_NavItem(
        icon: Icons.people_outlined,
        activeIcon: Icons.people_rounded,
        label: 'Customers',
        path: '/customers'));
    if (perms.canSeeProducts) {
      items.add(_NavItem(
          icon: Icons.inventory_2_outlined,
          activeIcon: Icons.inventory_2_rounded,
          label: 'Products',
          path: '/products'));
    }
    if (perms.canSeeInventory) {
      items.add(_NavItem(
          icon: Icons.warehouse_outlined,
          activeIcon: Icons.warehouse_rounded,
          label: 'Inventory',
          path: '/inventory'));
    }
    if (perms.canSeeReports) {
      items.add(_NavItem(
          icon: Icons.analytics_outlined,
          activeIcon: Icons.analytics_rounded,
          label: 'Reports',
          path: '/reports'));
    }
    items.add(_NavItem(
        icon: Icons.payments_outlined,
        activeIcon: Icons.payments_rounded,
        label: 'Payments',
        path: '/payments'));
    items.add(_NavItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
        label: 'Settings',
        path: '/settings'));
    // Finance
    if (perms.canSeeReports) {
      items.add(_NavItem(
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          label: 'Finance',
          path: '/finance'));
    }
    return items;
  }

  /// Finds which nav item matches the router's current location, so the
  /// bottom nav highlight always reflects where the user actually is —
  /// instead of a locally-tracked index that only moved on nav taps and
  /// stayed stuck on the first item (usually "Dashboard") after any other
  /// navigation, e.g. opening straight into POS or a deep link.
  int _resolveCurrentIndex(List<_NavItem> items) {
    final location = GoRouterState.of(context).uri.toString();
    var bestMatchIndex = -1;
    var bestMatchLength = -1;
    for (var i = 0; i < items.length; i++) {
      final path = items[i].path;
      if (path.isEmpty) continue;
      final matches = path == '/'
          ? location == '/'
          : location == path || location.startsWith('$path/');
      if (matches && path.length > bestMatchLength) {
        bestMatchIndex = i;
        bestMatchLength = path.length;
      }
    }
    return bestMatchIndex;
  }

  void _showMoreSheet(List<_NavItem> moreItems) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding:
            EdgeInsets.only(bottom: bottomPadding > 0 ? bottomPadding + 8 : 16),
        decoration: BoxDecoration(
          color: isDark ? DesignColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 28,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: isDark
                      ? DesignColors.darkTextTertiary
                      : DesignColors.textTertiary,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: DesignGradients.brand,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.apps_rounded,
                        color: Colors.white, size: 20)),
                const SizedBox(width: 10),
                Text('More Options',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary)),
              ]),
            ),
            const SizedBox(height: 12),
            ...moreItems.asMap().entries.map((entry) {
              final item = entry.value;
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: DesignColors.brandSubtle,
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(item.icon, color: DesignColors.brand, size: 20),
                ),
                title: Text(item.label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  context.go(item.path);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = getIt<ConnectivityService>();
    final perms = ref.watch(permissionsProvider);
    final allNavItems = _buildNavItems(perms);
    const maxVisible = 4;
    final hasMore = allNavItems.length > maxVisible;
    final visibleNavItems =
        hasMore ? allNavItems.take(maxVisible).toList() : allNavItems;
    final moreItems =
        hasMore ? allNavItems.skip(maxVisible).toList() : <_NavItem>[];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIndex = _resolveCurrentIndex(allNavItems);

    return Scaffold(
      body: Column(
        children: [
          // Offline Banner
          StreamBuilder<ConnectionStatus>(
            stream: connectivity.statusStream,
            initialData: connectivity.currentStatus,
            builder: (context, snapshot) {
              final isOffline = snapshot.data == ConnectionStatus.offline;
              if (!isOffline) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top, bottom: 8),
                decoration: BoxDecoration(
                  color: DesignColors.warning.withValues(alpha: 0.12),
                  border: Border(
                      bottom: BorderSide(
                          color: DesignColors.warning.withValues(alpha: 0.2))),
                ),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: DesignColors.warning, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  const Text('Offline Mode',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: DesignColors.warning)),
                  const SizedBox(width: 8),
                  Text('Sales will sync',
                      style: TextStyle(
                          fontSize: 10,
                          color: DesignColors.warning.withValues(alpha: 0.7))),
                ]),
              );
            },
          ),
          // Expanded chart is now the primary content
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.darkSurface.withValues(alpha: 0.96)
              : Colors.white.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color:
                isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
            width: 0.75,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              ...visibleNavItems.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                final isSelected = currentIndex == idx;
                return Expanded(
                    child: _NavItemWidget(
                        item: item,
                        isSelected: isSelected,
                        onTap: () => context.go(item.path),
                        isDark: isDark));
              }),
              if (hasMore)
                Expanded(
                    child: _NavItemWidget(
                      item: _NavItem(
                          icon: Icons.apps_outlined,
                          activeIcon: Icons.apps_rounded,
                          label: 'More',
                          path: ''),
                      isSelected: currentIndex >= maxVisible,
                      onTap: () => _showMoreSheet(moreItems),
                      isDark: isDark,
                    )),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
  _NavItem(
      {required this.icon,
      required this.activeIcon,
      required this.label,
      required this.path});
}

class _NavItemWidget extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const _NavItemWidget(
      {required this.item,
      required this.isSelected,
      required this.onTap,
      required this.isDark});

  @override
  Widget build(BuildContext context) {
    final inactiveColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: DesignAnimation.fast,
          curve: DesignAnimation.smooth,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? DesignColors.brand.withValues(alpha: isDark ? 0.22 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              isSelected ? item.activeIcon : item.icon,
              color: isSelected ? DesignColors.brand : inactiveColor,
              size: 23,
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(item.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? DesignColors.brand : inactiveColor,
                  )),
            ),
          ]),
        ),
      ),
    );
  }
}
