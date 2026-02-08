import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/auth/app_roles.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final Widget child;

  const HomeScreen({super.key, required this.child});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  static const int maxVisibleTabs = 5;

  /// Build the nav items list based on the user's role permissions.
  List<_NavItem> _buildNavItems(RolePermissions perms) {
    final items = <_NavItem>[];

    // Dashboard — store manager+ (first item)
    if (perms.canSeeDashboard) {
      items.add(_NavItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard,
        label: 'Dashboard',
        path: '/dashboard',
      ));
    }

    // POS — everyone
    items.add(_NavItem(
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale,
      label: 'POS',
      path: '/',
    ));

    // Products — stock keeper+
    if (perms.canSeeProducts) {
      items.add(_NavItem(
        icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2,
        label: 'Products',
        path: '/products',
      ));
    }

    // Inventory — stock keeper+
    if (perms.canSeeInventory) {
      items.add(_NavItem(
        icon: Icons.warehouse_outlined,
        activeIcon: Icons.warehouse,
        label: 'Inventory',
        path: '/inventory',
      ));
    }

    // Reports — store manager+
    if (perms.canSeeReports) {
      items.add(_NavItem(
        icon: Icons.bar_chart_outlined,
        activeIcon: Icons.bar_chart,
        label: 'Reports',
        path: '/reports',
      ));
    }

    // Settings — everyone
    items.add(_NavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Settings',
      path: '/settings',
    ));

    return items;
  }

  void _showMoreSheet(List<_NavItem> moreItems) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'More',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            ...moreItems.map((item) => ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.icon, color: AppColors.primary),
                  ),
                  title: Text(item.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    context.go(item.path);
                    // Find index of this item in full nav list for proper highlighting
                    final allItems = _buildNavItems(ref.read(permissionsProvider));
                    final itemIndex = allItems.indexWhere((i) => i.path == item.path);
                    if (itemIndex != -1) {
                      setState(() {
                        _currentIndex = itemIndex;
                      });
                    }
                  },
                )),
            const SizedBox(height: 8),
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

    // If more than maxVisibleTabs, show first (maxVisibleTabs - 1) + "More"
    final hasMore = allNavItems.length > maxVisibleTabs;
    final visibleNavItems = hasMore
        ? allNavItems.take(maxVisibleTabs - 1).toList()
        : allNavItems;
    final moreItems = hasMore
        ? allNavItems.skip(maxVisibleTabs - 1).toList()
        : <_NavItem>[];

    return Scaffold(
      body: Column(
        children: [
          // Offline Banner
          StreamBuilder<ConnectionStatus>(
            stream: connectivity.statusStream,
            initialData: connectivity.currentStatus,
            builder: (context, snapshot) {
              final isOffline = snapshot.data == ConnectionStatus.offline;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: isOffline ? 32 : 0,
                color: AppColors.warning,
                child: isOffline
                    ? const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_off,
                              size: 16,
                              color: Colors.white,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Offline Mode - Changes will sync when online',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : null,
              );
            },
          ),

          // Main Content
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                // Visible nav items
                ...visibleNavItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final safeIndex = _currentIndex.clamp(0, allNavItems.length - 1);
                  final isSelected = safeIndex == index;

                  return Expanded(
                    child: _NavItemWidget(
                      item: item,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _currentIndex = index;
                        });
                        context.go(item.path);
                      },
                    ),
                  );
                }),

                // "More" button if needed
                if (hasMore)
                  Expanded(
                    child: _NavItemWidget(
                      item: _NavItem(
                        icon: Icons.apps_outlined,
                        activeIcon: Icons.apps,
                        label: 'More',
                        path: '/more',
                      ),
                      isSelected: _currentIndex >= maxVisibleTabs - 1,
                      onTap: () => _showMoreSheet(moreItems),
                    ),
                  ),
              ],
            ),
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

  _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.path,
  });
}

class _NavItemWidget extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItemWidget({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final inactiveColor = theme.textTheme.bodySmall?.color ?? AppColors.textTertiary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width < 380 ? 8 : 12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isSelected 
              ? primaryColor.withOpacity(0.1) 
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? item.activeIcon : item.icon,
              color: isSelected ? primaryColor : inactiveColor,
              size: MediaQuery.of(context).size.width < 380 ? 20 : 22,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width < 380 ? 9 : 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? primaryColor : inactiveColor,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
