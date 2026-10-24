import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/di/injection.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion_kit.dart';
import '../../../../core/theme/axon_ai_icon.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/auth/app_roles.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../billing/presentation/widgets/subscription_entitlement_host.dart';
import '../../../../core/services/haptic_service.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerNotifications());
  }

  /// First time a signed-in user lands in the app, explain what alerts are
  /// for and ask for the OS permission in context — instead of leaving it
  /// buried behind a Settings toggle most people never find. Asked once.
  Future<void> _offerNotifications() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    try {
      final service = getIt<NotificationService>();
      if (await service.hasBeenPrompted() || await service.hasPermission()) {
        return;
      }
      if (!mounted) return;
      await service.markPrompted();
      if (!mounted) return;
      final accept = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.notifications_active_rounded,
              color: DesignColors.accent, size: 32),
          title: const Text('Stay in the loop'),
          content: const Text(
            'Turn on alerts to hear about low stock, stock request decisions, '
            'and messages from the businesses you trade with — even when the '
            'app is closed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Turn on alerts'),
            ),
          ],
        ),
      );
      if (accept == true) await service.requestPermission();
    } catch (_) {
      // Notifications unavailable (e.g. debug build without Firebase) —
      // the app works fine without them.
    }
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
    // AI is a primary working surface, not an add-on hidden in More.
    // Keep the first four tabs focused on daily work. Customers is available
    // from More so it never displaces AI in the compact bottom bar.
    items.add(_NavItem(
        icon: Icons.auto_awesome_outlined,
        activeIcon: Icons.auto_awesome_rounded,
        label: 'AI',
        path: '/ai'));
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
    } else if (perms.canMakeSales || perms.canManageStock) {
      // Sellers may request stock without permission to browse the inventory
      // management screen, so keep the request form reachable from More.
      items.add(_NavItem(
          icon: Icons.add_shopping_cart_outlined,
          activeIcon: Icons.add_shopping_cart_rounded,
          label: 'Request Stock',
          path: '/inventory/request-stock'));
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
    // Finance has its own backend permission, separate from reporting.
    if (perms.canViewFinance) {
      items.add(_NavItem(
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          label: 'Finance',
          path: '/finance'));
    }
    // Customer profiles are an important workflow, but should not displace
    // Dashboard, POS, AI, or Products from the four primary slots.
    items.add(_NavItem(
        icon: Icons.people_outlined,
        activeIcon: Icons.people_rounded,
        label: 'Customers',
        path: '/customers'));
    // Shop control. Each entry follows the backend permission of the same
    // name, so a screen that would only 403 is never offered.
    if (perms.has('accountability.view')) {
      items.add(_NavItem(
          icon: Icons.shield_outlined,
          activeIcon: Icons.shield_rounded,
          label: 'Shop Alerts',
          path: '/shop-alerts'));
    }
    if (perms.has('inventory.stocktake.view')) {
      items.add(_NavItem(
          icon: Icons.fact_check_outlined,
          activeIcon: Icons.fact_check_rounded,
          label: 'Stock Counts',
          path: '/stock-counts'));
    }
    if (perms.has('imports.view')) {
      items.add(_NavItem(
          icon: Icons.local_shipping_outlined,
          activeIcon: Icons.local_shipping_rounded,
          label: 'Containers',
          path: '/containers'));
    }
    if (perms.has('news.view')) {
      items.add(_NavItem(
          icon: Icons.newspaper_outlined,
          activeIcon: Icons.newspaper_rounded,
          label: 'Business News',
          path: '/news'));
    }
    // Growth and collections. Same rule: only what the user may actually open.
    if (perms.has('products.view')) {
      items.add(_NavItem(
          icon: Icons.sell_outlined,
          activeIcon: Icons.sell_rounded,
          label: 'Price List',
          path: '/price-list'));
    }
    if (perms.has('coupons.view')) {
      items.add(_NavItem(
          icon: Icons.confirmation_number_outlined,
          activeIcon: Icons.confirmation_number_rounded,
          label: 'Coupons',
          path: '/coupons'));
    }
    if (perms.has('statements.share')) {
      items.add(_NavItem(
          icon: Icons.mark_chat_read_outlined,
          activeIcon: Icons.mark_chat_read_rounded,
          label: 'Debt Replies',
          path: '/statements/replies'));
    }
    if (perms.has('mpesa.reconcile')) {
      items.add(_NavItem(
          icon: Icons.rule_rounded,
          activeIcon: Icons.rule_rounded,
          label: 'M-Pesa verification',
          path: '/mpesa-match'));
    }
    if (perms.has('referrals.view')) {
      items.add(_NavItem(
          icon: Icons.redeem_outlined,
          activeIcon: Icons.redeem_rounded,
          label: 'Invite Shops',
          path: '/referrals'));
    }
    // Trade partners are restricted by the backend to business owners and
    // managers, so keep the entry hidden for other legacy account roles.
    final legacyRole = ref.watch(userRoleProvider)?.toUpperCase();
    if (legacyRole == 'ADMIN' || legacyRole == 'MANAGER') {
      // Businesses this shop trades with: connect by company code and chat.
      items.add(_NavItem(
          icon: Icons.handshake_outlined,
          activeIcon: Icons.handshake_rounded,
          label: 'Trade Partners',
          path: '/partners'));
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
    _isMoreSheetOpen = true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // Keep the sheet below the status bar/cutout rather than full-bleed.
      useSafeArea: true,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: bottomPadding > 0
              ? bottomPadding + DesignSpacing.sm
              : DesignSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: isDark ? DesignColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(DesignSpacing.radiusXxl)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 28,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        // Material ancestor so ListTiles paint their ink on it — a bare
        // decorated Container trips the "ListTile background color or ink
        // splashes may be invisible" assertion on Flutter 3.44+.
        child: Material(
          color: isDark ? DesignColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(DesignSpacing.radiusXxl)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: DesignSpacing.md),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: isDark
                        ? DesignColors.darkTextTertiary
                        : DesignColors.textTertiary,
                    borderRadius:
                        BorderRadius.circular(DesignSpacing.radiusSm - 6)),
              ),
              const SizedBox(height: DesignSpacing.lg),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: DesignSpacing.xl),
                child: Row(children: [
                  Container(
                      padding: const EdgeInsets.all(DesignSpacing.sm),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            DesignColors.accent,
                            DesignColors.accentLight
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusLg - 6),
                      ),
                      child: const Icon(Icons.apps_rounded,
                          color: Colors.white, size: 20)),
                  const SizedBox(width: DesignSpacing.lg - 4),
                  Text('More Options',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? DesignColors.darkTextPrimary
                              : DesignColors.textPrimary)),
                ]),
              ),
              const SizedBox(height: DesignSpacing.md),
              // The list outgrows the screen once every module is enabled;
              // scroll it instead of overflowing under the system bars.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                            // ListTile paints ink on its nearest Material ancestor; the
                            // sheet Container's BoxDecoration alone triggers the
                            // "background color or ink splashes may be invisible"
                            // assertion on newer Flutter versions.
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: DesignSpacing.xl, vertical: 2),
                            // Keep every row at the 44px+ touch minimum.
                            minTileHeight: 48,
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                  color: isDark
                                      ? DesignColors.brandSubtle
                                      : DesignColors.accent
                                          .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(
                                      DesignSpacing.radiusLg - 6)),
                              child: Icon(item.icon,
                                  color: isDark
                                      ? DesignColors.brand
                                      : DesignColors.accent,
                                  size: 20),
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
              ),
            ],
          ),
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
    final homePath = perms.canSeeDashboard ? '/dashboard' : '/';
    final atHome = GoRouterState.of(context).uri.path == homePath;

    // Tabs are reached with context.go, so the stack holds a single page and
    // the system Back would close the app from every screen (go_router skips
    // PopScope on a one-page stack). Send Back to the user's first permitted
    // work surface; Back there itself still leaves the app.
    return BackButtonListener(
        onBackButtonPressed: () async {
          // A sheet or dialog is on top of the shell: Back closes it instead of
          // jumping to the Dashboard.
          if (ModalRoute.of(context)?.isCurrent == false) {
            // go_router would pop the shell's own page first, leaving the sheet
            // open over the wrong screen — close the top modal explicitly.
            await Navigator.of(context, rootNavigator: true).maybePop();
            return true;
          }
          // A screen was pushed on top of a tab (Settings -> Plan & Billing):
          // let Back pop just that one step, like any app.
          if (GoRouter.of(context).canPop()) return false;
          if (atHome) return false;
          context.go(homePath);
          return true;
        },
        child: Scaffold(
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
                        top: MediaQuery.of(context).padding.top,
                        bottom: DesignSpacing.sm),
                    decoration: BoxDecoration(
                      color: DesignColors.warning.withValues(alpha: 0.12),
                      border: Border(
                          bottom: BorderSide(
                              color:
                                  DesignColors.warning.withValues(alpha: 0.2))),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                  color: DesignColors.warning,
                                  shape: BoxShape.circle)),
                          const SizedBox(width: DesignSpacing.sm - 2),
                          const Text('Offline Mode',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: DesignColors.warning)),
                          const SizedBox(width: DesignSpacing.sm),
                          Text('Sales will sync',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: DesignColors.warning
                                      .withValues(alpha: 0.7))),
                        ]),
                  );
                },
              ),
              // Subscription restricted-mode / expiry reminder banner (watches
              // the entitlement provider; passive, never blocks navigation).
              // The routed Scaffold/scroll views need a finite remaining height,
              // whether the subscription host shows a banner or only the child.
              Expanded(
                child: SubscriptionEntitlementHost(child: widget.child),
              ),
            ],
          ),
          // Floating pill bar: the active tab is an orange chip that springs in,
          // the bar itself hovers above the page on a soft warm shadow.
          bottomNavigationBar: Container(
            color: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 10),
              child: Container(
                height: 66,
                decoration: BoxDecoration(
                  color: isDark ? DesignColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: isDark
                        ? DesignColors.darkBorder
                        : DesignColors.surfaceBorderLight,
                  ),
                  boxShadow: DesignShadows.soft(isDark),
                ),
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
                            isPrimary: item.path == '/ai',
                            onTap: () {
                              if (!isSelected) HapticService().selection();
                              context.go(item.path);
                            },
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
                          onTap: () {
                            HapticService().selection();
                            _showMoreSheet(moreItems);
                          },
                          isDark: isDark,
                        ),
                      )),
                  ],
                ),
              ),
            ),
          ),
        ));
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
      return Semantics(
        button: true,
        label: 'AI assistant',
        selected: isSelected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: -14,
                  child: BreathingGlow(
                      radius: 18,
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
                                  : Colors.white),
                          borderRadius: BorderRadius.circular(18),
                          border: isSelected
                              ? null
                              : Border.all(
                                  color: isDark
                                      ? DesignColors.darkBorder
                                      : DesignColors.surfaceBorder,
                                  width: 1.2,
                                ),
                          boxShadow: [
                            BoxShadow(
                              color: DesignColors.accent
                                  .withValues(alpha: isSelected ? 0.35 : 0.0),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                            if (!isDark && !isSelected)
                              const BoxShadow(
                                color: Color(0x228A6B45),
                                blurRadius: 14,
                                offset: Offset(0, 5),
                              ),
                          ],
                        ),
                        child: Center(
                          child: AxonAiIcon(
                            tenantLogoUrl: tenantLogoUrl,
                            size: 28,
                          ),
                        ),
                      )),
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
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlowOnSelect(
                selected: isSelected,
                radius: 16,
                child: AnimatedContainer(
                  duration: DesignAnimation.normal,
                  curve: Curves.easeOutBack,
                  width: isSelected ? 54 : 38,
                  height: 30,
                  decoration: BoxDecoration(
                    color:
                        isSelected ? DesignColors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: SpringIcon(
                      icon: isSelected ? item.activeIcon : item.icon,
                      color: isSelected ? Colors.white : inactiveColor,
                      size: 21,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: DesignAnimation.fast,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? DesignColors.accent : inactiveColor,
                  ),
                  child: Text(item.label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
