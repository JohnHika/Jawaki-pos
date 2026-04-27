import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _bounceAnimation = Tween<double>(begin: 0.0, end: 6.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  List<_NavItem> _buildNavItems(RolePermissions perms) {
    final items = <_NavItem>[];
    if (perms.canSeeDashboard) {
      items.add(_NavItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard_rounded,
        label: 'Dashboard',
        path: '/dashboard',
      ));
    }
    items.add(_NavItem(
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale_rounded,
      label: 'POS',
      path: '/',
    ));
    items.add(_NavItem(
      icon: Icons.people_outlined,
      activeIcon: Icons.people_rounded,
      label: 'Customers',
      path: '/customers',
    ));
    if (perms.canSeeProducts) {
      items.add(_NavItem(
        icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2_rounded,
        label: 'Products',
        path: '/products',
      ));
    }
    if (perms.canSeeInventory) {
      items.add(_NavItem(
        icon: Icons.warehouse_outlined,
        activeIcon: Icons.warehouse_rounded,
        label: 'Inventory',
        path: '/inventory',
      ));
    }
    if (perms.canSeeReports) {
      items.add(_NavItem(
        icon: Icons.analytics_outlined,
        activeIcon: Icons.analytics_rounded,
        label: 'Reports',
        path: '/reports',
      ));
    }
    items.add(_NavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments_rounded,
      label: 'Payments',
      path: '/payments',
    ));
    items.add(_NavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: 'Settings',
      path: '/settings',
    ));
    return items;
  }

  void _showMoreSheet(List<_NavItem> moreItems) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? DesignColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:isDark ? 0.5 : 0.08),
              blurRadius: 30,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 16),
              width: 48, height: 5,
              decoration: BoxDecoration(
                color: isDark
                    ? DesignColors.darkTextTertiary
                    : DesignColors.surfaceBorder,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [DesignColors.brand, DesignColors.brandDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: DesignColors.brand.withValues(alpha:0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.apps_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'More Options',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: DesignColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Access additional features',
                style: TextStyle(
                  fontSize: 13,
                  color: DesignColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: moreItems.length,
                itemBuilder: (context, index) {
                  final item = moreItems[index];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            DesignColors.brand,
                            DesignColors.brandDark,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: DesignColors.brand.withValues(alpha:0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        item.icon,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    title: Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: DesignColors.textPrimary,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: DesignColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: DesignColors.textSecondary,
                        size: 20,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      context.go(item.path);
                      final allItems = _buildNavItems(ref.read(permissionsProvider));
                      final itemIndex =
                          allItems.indexWhere((i) => i.path == item.path);
                      if (itemIndex != -1) {
                        setState(() => _currentIndex = itemIndex);
                      }
                    },
                  );
                },
              ),
            ),
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
    final hasMore = allNavItems.length > 5;
    final visibleNavItems = hasMore ? allNavItems.take(4).toList() : allNavItems;
    final moreItems =
        hasMore ? allNavItems.skip(4).toList() : <_NavItem>[];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          StreamBuilder<ConnectionStatus>(
            stream: connectivity.statusStream,
            initialData: connectivity.currentStatus,
            builder: (context, snapshot) {
              final isOffline = snapshot.data == ConnectionStatus.offline;
              return AnimatedCrossFade(
                duration: DesignAnimation.normal,
                crossFadeState: isOffline
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        DesignColors.warning,
                        DesignColors.warning.withValues(alpha:0.85),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: DesignColors.warning.withValues(alpha:0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.wifi_off_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Offline Mode',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Sales will sync when reconnected',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha:0.85),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sync_disabled,
                                  color: Colors.white, size: 12),
                              SizedBox(width: 4),
                              Text(
                                'Queued',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? DesignColors.darkSurface : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:isDark ? 0.3 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              children: [
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
                        setState(() => _currentIndex = index);
                        context.go(item.path);
                      },
                      isDark: isDark,
                    ),
                  );
                }),
                if (hasMore)
                  Expanded(
                    child: _NavItemWidget(
                      item: _NavItem(
                        icon: Icons.apps_outlined,
                        activeIcon: Icons.apps_rounded,
                        label: 'More',
                        path: '/more',
                      ),
                      isSelected: _currentIndex >= 4,
                      onTap: () => _showMoreSheet(moreItems),
                      isDark: isDark,
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
  final bool isDark;

  const _NavItemWidget({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: DesignAnimation.fast,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? DesignColors.brand.withValues(alpha:0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: DesignAnimation.fast,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? DesignColors.brand.withValues(alpha:0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSelected ? item.activeIcon : item.icon,
                color: isSelected
                    ? DesignColors.brand
                    : (isDark
                        ? DesignColors.darkTextTertiary
                        : DesignColors.textTertiary),
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? DesignColors.brand
                    : (isDark
                        ? DesignColors.darkTextTertiary
                        : DesignColors.textTertiary),
                letterSpacing: 0.1,
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
