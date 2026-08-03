import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/di/injection.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/axon_ai_icon.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/auth/app_roles.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'home_nav_keys.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final Widget child;
  const HomeScreen({super.key, required this.child});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<_NavItem> _latestMoreItems = const [];
  bool _isMoreSheetOpen = false;

  @override
  void initState() {
    super.initState();
    HomeNavKeys.moreSheetOpenRequest.addListener(_handleMoreSheetRequest);
  }

  @override
  void dispose() {
    HomeNavKeys.moreSheetOpenRequest.removeListener(_handleMoreSheetRequest);
    super.dispose();
  }

  void _handleMoreSheetRequest() {
    final shouldOpen = HomeNavKeys.moreSheetOpenRequest.value;
    if (shouldOpen && !_isMoreSheetOpen) {
      _showMoreSheet(_latestMoreItems);
    } else if (!shouldOpen && _isMoreSheetOpen && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  List<_NavItem> _buildNavItems(RolePermissions perms) {
    final items = <_NavItem>[];
    // Dashboard is the shared business overview. Its cards and actions remain
    // role-aware inside the screen, but every signed-in user should be able
    // to see the same orientation point instead of losing the destination.
    items.add(_NavItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard_rounded,
        label: 'Dashboard',
        path: '/dashboard'));
    items.add(_NavItem(
        icon: Icons.point_of_sale_outlined,
        activeIcon: Icons.point_of_sale_rounded,
        label: 'POS',
        path: '/'));
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
    // AI is a supporting capability rather than the primary POS destination;
    // keep it available from More without displacing Dashboard or Payments.
    items.add(_NavItem(
        icon: Icons.auto_awesome_outlined,
        activeIcon: Icons.auto_awesome_rounded,
        label: 'AI',
        path: '/ai'));
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
    _isMoreSheetOpen = true;
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
              return KeyedSubtree(
                key: switch (item.path) {
                  '/inventory' => HomeNavKeys.moreSheetInventory,
                  '/reports' => HomeNavKeys.moreSheetReports,
                  '/settings' => HomeNavKeys.moreSheetSettings,
                  _ => null,
                },
                child: ListTile(
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
                ),
              );
            }),
          ],
        ),
      ),
    ).then((_) {
      _isMoreSheetOpen = false;
      if (HomeNavKeys.moreSheetOpenRequest.value) {
        HomeNavKeys.moreSheetOpenRequest.value = false;
      }
    });
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
    _latestMoreItems = moreItems;
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
          color: isDark ? DesignColors.darkBg : DesignColors.surface,
          border: Border(
            top: BorderSide(
              color:
                  isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...visibleNavItems.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final isSelected = currentIndex == idx;
                  return Expanded(
                      child: KeyedSubtree(
                    key: item.path == '/' ? HomeNavKeys.pos : null,
                    child: _NavItemWidget(
                        item: item,
                        isSelected: isSelected,
                        isPrimary: item.path == '/ai' && idx == 0,
                        onTap: () => context.go(item.path),
                        isDark: isDark),
                  ));
                }),
                if (hasMore)
                  Expanded(
                      child: KeyedSubtree(
                    key: HomeNavKeys.more,
                    child: _NavItemWidget(
                      item: _NavItem(
                          icon: Icons.apps_outlined,
                          activeIcon: Icons.apps_rounded,
                          label: 'More',
                          path: ''),
                      isSelected: currentIndex >= maxVisible,
                      isPrimary: false,
                      onTap: () => _showMoreSheet(moreItems),
                      isDark: isDark,
                    ),
                  )),
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
  _NavItem(
      {required this.icon,
      required this.activeIcon,
      required this.label,
      required this.path});
}

class _NavItemWidget extends ConsumerWidget {
  final _NavItem item;
  final bool isSelected;
  final bool isPrimary;
  final VoidCallback onTap;
  final bool isDark;

  const _NavItemWidget(
      {required this.item,
      required this.isSelected,
      required this.isPrimary,
      required this.onTap,
      required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inactiveColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;

    // The primary (AI) tab is a solid raised block that sits above the
    // rest of the row instead of matching their pill highlight — it is
    // meant to be found by shape alone, not just by color when active.
    if (isPrimary) {
      final tenantLogoUrl = ref.watch(tenantIdentityProvider).logoUrl;
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: -14,
              child: AnimatedContainer(
                duration: DesignAnimation.fast,
                curve: DesignAnimation.smooth,
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: isSelected
                      ? DesignColors.accent
                      : (isDark
                          ? DesignColors.darkSurfaceElevated
                          : DesignColors.surfaceMuted),
                  borderRadius: BorderRadius.circular(16),
                  border: isSelected
                      ? null
                      : Border.all(
                          color: isDark
                              ? DesignColors.darkBorder
                              : DesignColors.surfaceBorder,
                          width: 1.2,
                        ),
                ),
                child: Center(
                  child: AxonAiIcon(
                    tenantLogoUrl: tenantLogoUrl,
                    size: 28,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 42),
              child: Text(item.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: isSelected ? DesignColors.accent : inactiveColor,
                  )),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isSelected ? DesignColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? item.activeIcon : item.icon,
                color: isSelected
                    ? (isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary)
                    : inactiveColor,
                size: 22,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(item.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected
                          ? (isDark
                              ? DesignColors.darkTextPrimary
                              : DesignColors.textPrimary)
                          : inactiveColor,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
