import 'dart:async';
import '../../../licence/presentation/licence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:axon_pos/core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/axon_ai_icon.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/auth/app_roles.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/providers/local_workspace_capabilities.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../billing/presentation/widgets/subscription_entitlement_host.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/responsive/device_class.dart';
import '../widgets/adaptive_nav.dart';
import '../../../../core/services/desktop_update_service.dart';
import '../desktop/desktop_command_palette.dart';
import '../desktop/desktop_nav.dart';
import '../desktop/desktop_shell.dart';
import 'home_nav_keys.dart';
import '../../../../core/desktop/adaptive_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final Widget child;
  const HomeScreen({super.key, required this.child});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const int _maxVisiblePrimaryItems = 4;

  /// Tabs on the phone bar before More.
  static const int _phoneBarTabs = 3;

  List<_NavItem> _latestMoreItems = const [];
  bool _isMoreSheetOpen = false;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    HomeNavKeys.moreSheetOpenRequest.addListener(_handleMoreSheetRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerNotifications());
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerWelcome());
    _loadVersion();
    _checkLicence();
    _licenceTimer =
        Timer.periodic(const Duration(minutes: 30), (_) => _checkLicence());
  }

  Timer? _licenceTimer;

  /// The running version, for the desktop status bar.
  Future<void> _loadVersion() async {
    if (!DesktopLayout.isDesktopPlatform) return;
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {
      // The status bar simply omits the version.
    }
  }

  /// Keeps the shop's payment standing fresh. Does nothing until licences are
  /// switched on.
  void _checkLicence() {
    if (!getIt<AuthService>().isLocalWorkspace) return;
    unawaited(licenceService().refresh().then((_) {
      if (mounted) ref.invalidate(licenceViewProvider);
    }));
  }

  /// The first time each person opens a shop kept on this phone, show the
  /// welcome tour. The shop's database notes who has seen it.
  Future<void> _offerWelcome() async {
    final auth = getIt<AuthService>();
    if (!auth.isLocalWorkspace) return;
    final userId = auth.currentUser?['id']?.toString() ?? '';
    if (userId.isEmpty) return;
    try {
      if (await getIt<AppDatabase>().hasSeenWelcome(userId)) return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final router = GoRouter.of(context);
    final path = router.routerDelegate.currentConfiguration.uri.path;
    if (path == '/welcome' || path == '/setup') return;
    unawaited(router.push('/welcome'));
  }

  /// First time a signed-in user lands in the app, explain what alerts are
  /// for and ask for the OS permission in context — instead of leaving it
  /// buried behind a Settings toggle most people never find. Asked once.
  Future<void> _offerNotifications() async {
    if (getIt<AuthService>().isLocalWorkspace) return;
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
    _licenceTimer?.cancel();
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

  List<_NavItem> _buildNavItems(
      RolePermissions perms, BusinessLayoutConfig businessLayout) {
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final items = <_NavItem>[];
    if (perms.canSeeDashboard) {
      items.add(_NavItem(
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
          label: 'Home',
          path: '/dashboard'));
    }
    if (perms.canSeePOS) {
      items.add(_NavItem(
          icon: Icons.point_of_sale_outlined,
          activeIcon: Icons.point_of_sale_rounded,
          label: 'Sell',
          path: '/'));
    }
    // AI is a primary work surface for accounts whose role permits it.
    // Device-local staff use scoped roles, so the owner-only Gateway
    // credential is never exposed as a general staff capability.
    if (perms.has('ai.chat')) {
      items.add(_NavItem(
          icon: Icons.auto_awesome_outlined,
          activeIcon: Icons.auto_awesome_rounded,
          label: 'AI',
          path: '/ai'));
    }
    if (perms.canSeeProducts) {
      items.add(_NavItem(
          icon: Icons.inventory_2_outlined,
          activeIcon: Icons.inventory_2_rounded,
          label: businessLayout.actionLabel(
              '/products', businessLayout.productsLabel),
          path: '/products'));
    }
    if (isLocalWorkspace) {
      // A shop kept on the phone finds its stock in Products, under Stock.
      // Only a role that cannot open Products still gets Inventory here.
      // Stock requests need a connected shop, so they are not offered.
      if (perms.canSeeInventory && !perms.canSeeProducts) {
        items.add(_NavItem(
            icon: Icons.warehouse_outlined,
            activeIcon: Icons.warehouse_rounded,
            label: businessLayout.actionLabel('/inventory', 'Inventory'),
            path: '/inventory'));
      }
    } else if (perms.canSeeInventory) {
      items.add(_NavItem(
          icon: Icons.warehouse_outlined,
          activeIcon: Icons.warehouse_rounded,
          label: businessLayout.actionLabel('/inventory', 'Inventory'),
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
    if (perms.canSeePayments) {
      items.add(_NavItem(
          icon: Icons.payments_outlined,
          activeIcon: Icons.payments_rounded,
          label: 'Payments',
          path: '/payments'));
    }
    if (perms.canSeeReceipts) {
      items.add(_NavItem(
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long_rounded,
          label: 'Receipts',
          path: '/receipts'));
    }
    // Settings is always pinned into the bottom bar by the build step in
    // build(); do not add it to the overflow list.
    // Finance has its own backend permission, separate from reporting.
    if (perms.canViewFinance) {
      items.add(_NavItem(
          icon: Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          label: 'Finance',
          path: '/finance'));
      // Expenses are kept on the device only.
      if (isLocalWorkspace) {
        items.add(_NavItem(
            icon: Icons.request_quote_outlined,
            activeIcon: Icons.request_quote_rounded,
            label: 'Expenses',
            path: '/expenses'));
      }
    }
    // Customer profiles are an important workflow, but should not displace
    // Dashboard, POS, AI, or Products from the four primary slots.
    if (perms.canSeeCustomers) {
      items.add(_NavItem(
          icon: Icons.people_outlined,
          activeIcon: Icons.people_rounded,
          label: 'Customers',
          path: '/customers'));
    }
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
          label: 'Stock counts',
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
    items.removeWhere((item) =>
        (isLocalWorkspace &&
            !LocalWorkspaceCapabilities.supportsPath(item.path)) ||
        !businessLayout.isActionVisible(
          item.path == '/inventory/request-stock' ? '/inventory' : item.path,
        ));
    late final List<_NavItem> orderedItems;
    if (businessLayout.priorityPaths.isEmpty) {
      orderedItems = [...items];
    } else {
      final itemsByPath = {for (final item in items) item.path: item};
      final prioritizedPaths =
          businessLayout.priorityPaths.where(itemsByPath.containsKey).toSet();
      orderedItems = [
        for (final path in businessLayout.priorityPaths)
          if (itemsByPath.containsKey(path)) itemsByPath[path]!,
        ...items.where((item) => !prioritizedPaths.contains(item.path)),
      ];
    }
    // A shop may pin several areas ahead of AI. Keep their order in front,
    // but reserve the last visible primary slot for AI so the custom layout
    // never hides a core destination inside More.
    final aiIndex = orderedItems.indexWhere((item) => item.path == '/ai');
    if (aiIndex >= _maxVisiblePrimaryItems &&
        orderedItems.length >= _maxVisiblePrimaryItems) {
      final aiItem = orderedItems.removeAt(aiIndex);
      orderedItems.insert(_maxVisiblePrimaryItems - 1, aiItem);
    }
    return orderedItems
        .map((item) => item.withLabel(
              businessLayout.actionLabel(item.path, item.label),
            ))
        .toList(growable: false);
  }

  /// Finds which nav item matches the router's current location, so the
  /// bottom nav highlight always reflects where the user actually is —
  /// instead of a locally-tracked index that only moved on nav taps and
  /// stayed stuck on the first item (usually "Dashboard") after any other
  /// navigation, e.g. opening straight into POS or a deep link.
  int _resolveCurrentIndex(List<_NavItem> items) {
    var location = GoRouterState.of(context).uri.toString();
    // In a device-only shop Stock lives inside Products, so receiving a
    // delivery keeps Products lit instead of More (where /inventory sits).
    if (getIt<AuthService>().isLocalWorkspace &&
        location.startsWith('/inventory/receive')) {
      location = '/products';
    }
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    showAdaptiveModalSheet(
      useRootNavigator: true,
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // Keep the sheet below the status bar/cutout rather than full-bleed.
      useSafeArea: true,
      builder: (context) => _MoreGrid(
        items: moreItems,
        bottomPadding: bottomPadding,
        onPick: (path) {
          Navigator.pop(context);
          this.context.go(path);
        },
      ),
    ).then((_) {
      _isMoreSheetOpen = false;
      if (HomeNavKeys.moreSheetOpenRequest.value) {
        HomeNavKeys.moreSheetOpenRequest.value = false;
      }
    });
  }

  /// The computer layout: permanent sidebar, top bar, page on a sheet. Pages
  /// are the same routed screens the phone shows.
  Widget _buildDesktopShell({
    required List<_NavItem> navItems,
    required _NavItem settingsItem,
    required bool isLocalWorkspace,
    required ConnectivityService connectivity,
  }) {
    DesktopNavItem map(_NavItem item) => DesktopNavItem(
          icon: item.icon,
          activeIcon: item.activeIcon,
          label: item.label,
          path: item.path,
          group: desktopGroupFor(item.path),
          keywords: desktopKeywordsFor(item.path),
        );

    final tenant = ref.watch(tenantIdentityProvider);
    final DesktopUpdateService? updates =
        getIt.isRegistered<DesktopUpdateService>() &&
                getIt<DesktopUpdateService>().supported
            ? getIt<DesktopUpdateService>()
            : null;

    return StreamBuilder<ConnectionStatus>(
      stream: connectivity.statusStream,
      initialData: connectivity.currentStatus,
      builder: (context, snapshot) {
        final offline = snapshot.data == ConnectionStatus.offline;
        return DesktopShell(
          items: [
            for (final item in navItems)
              if (item.path != settingsItem.path) map(item),
          ],
          settingsItem: map(settingsItem),
          location: GoRouterState.of(context).uri.toString(),
          onNavigate: (path) => context.go(path),
          companyName: tenant.companyName,
          userName: tenant.userFullName,
          role: tenant.role,
          connection: isLocalWorkspace
              ? DesktopConnection.localOnly
              : offline
                  ? DesktopConnection.offline
                  : DesktopConnection.online,
          version: _appVersion,
          onLock: () => unawaited(getIt<AuthService>().lockSession()),
          statusWidgets: [
            if (updates != null) _UpdateReadyChip(service: updates),
          ],
          extraCommands: [
            if (updates != null)
              DesktopCommand(
                label: 'Check for updates',
                icon: Icons.system_update_alt_rounded,
                section: 'Action',
                keywords: const ['version', 'upgrade', 'new version'],
                run: () => updates.openOverlay(recheck: true),
              ),
          ],
          child: SubscriptionEntitlementHost(child: widget.child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = getIt<ConnectivityService>();
    final perms = ref.watch(permissionsProvider);
    final businessLayout = ref.watch(businessLayoutProvider);
    var allNavItems = _buildNavItems(perms, businessLayout);
    // Settings is the item users hunt for most; keep it pinned in the bar
    // instead of letting it fall into the More sheet. _buildNavItems never
    // emits a '/settings' item, so the pinned copy is appended once below.
    final settingsItem = _NavItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
        label: 'Settings',
        path: '/settings');
    final pinnedItems = [...allNavItems, settingsItem];
    final tablet = context.deviceClass == DeviceClass.tablet;
    // Tablet and desktop keep the full rail. The phone bar is Home, Sell,
    // Products and More: the AI assistant and Settings are used less than the
    // daily work surfaces, so they lead the More grid instead of taking bar
    // slots (the AI mark no longer sits raised in the middle).
    final bool hasMore;
    final List<_NavItem> visibleNavItems;
    final List<_NavItem> moreItems;
    if (tablet) {
      hasMore = pinnedItems.length > _maxVisiblePrimaryItems + 1;
      visibleNavItems = pinnedItems.length <= _maxVisiblePrimaryItems + 1
          ? pinnedItems
          : [...pinnedItems.take(_maxVisiblePrimaryItems), settingsItem];
      moreItems = hasMore
          ? pinnedItems
              .skip(_maxVisiblePrimaryItems)
              .where((item) => item.path != '/settings')
              .toList()
          : <_NavItem>[];
    } else {
      final work = allNavItems.where((item) => item.path != '/ai').toList();
      visibleNavItems = work.take(_phoneBarTabs).toList();
      moreItems = [
        for (final item in allNavItems)
          if (item.path == '/ai') item.withLabel('AI assistant'),
        settingsItem,
        ...work.skip(_phoneBarTabs),
      ];
      hasMore = true;
    }
    _latestMoreItems = moreItems;
    // Selection is worked out against what the bar actually shows, so Settings
    // lights its own tab. More lights only for a page that lives inside it.
    final currentIndex = _resolveCurrentIndex(visibleNavItems);
    final moreSelected =
        hasMore && currentIndex < 0 && _resolveCurrentIndex(moreItems) >= 0;
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final homePath = isLocalWorkspace
        ? LocalWorkspaceCapabilities.homePathFor(perms, businessLayout)
        : businessLayout.homePathFor(perms);
    final atHome = GoRouterState.of(context).uri.path == homePath;

    // Phone: floating bottom bar. Tablet / till terminal (600 and up, computer
    // window narrower than the shell): side rail with every destination.
    final logoUrl = ref.watch(tenantIdentityProvider).logoUrl;
    NavDestination destinationFor(_NavItem item) {
      final isAi = item.path == '/ai';
      return NavDestination(
        icon: item.icon,
        activeIcon: item.activeIcon,
        label: item.label,
        path: item.path,
        primary: false,
        semanticLabel: isAi ? 'AI assistant' : null,
        iconBuilder: isAi
            ? (_) => AxonAiIcon(tenantLogoUrl: logoUrl, size: tablet ? 26 : 28)
            : null,
        itemKey: item.path == '/' ? HomeNavKeys.pos : null,
      );
    }

    Widget withRail(Widget content) {
      if (!tablet) return content;
      final railItems = [
        for (final item in pinnedItems)
          if (item.path != settingsItem.path) item,
      ];
      final railIndex = _resolveCurrentIndex(railItems);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SideNavRail(
            items: [for (final item in railItems) destinationFor(item)],
            selectedIndex: railIndex,
            onSelect: (i) {
              if (i != railIndex) HapticService().selection();
              context.go(railItems[i].path);
            },
            settings: destinationFor(settingsItem),
            settingsSelected: _resolveCurrentIndex([settingsItem]) == 0,
            onSettings: () {
              HapticService().selection();
              context.go(settingsItem.path);
            },
          ),
          Expanded(child: content),
        ],
      );
    }

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
        child: DesktopLayout.wantsShell(context)
            ? _buildDesktopShell(
                navItems: pinnedItems,
                settingsItem: settingsItem,
                isLocalWorkspace: isLocalWorkspace,
                connectivity: connectivity,
              )
            : Scaffold(
          // Always distinguish device-local workspaces from cloud
          // workspaces. Internet connectivity does not enable syncing in
          // the standalone edition.
          body: withRail(StreamBuilder<ConnectionStatus>(
            stream: connectivity.statusStream,
            initialData: connectivity.currentStatus,
            builder: (context, snapshot) {
              final isOffline = snapshot.data == ConnectionStatus.offline;
              final showStrip = isLocalWorkspace || isOffline;
              final statusColor =
                  isLocalWorkspace ? DesignColors.info : DesignColors.warning;
              return Column(
                children: [
                  if (!showStrip)
                    const SizedBox.shrink()
                  else
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.only(
                          top: MediaQuery.of(context).padding.top,
                          bottom: DesignSpacing.sm),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        border: Border(
                            bottom: BorderSide(
                                color: statusColor.withValues(alpha: 0.2))),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: DesignSpacing.sm - 2),
                            Text(
                                isLocalWorkspace
                                    ? 'Local only'
                                    : 'Offline mode',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor)),
                            const SizedBox(width: DesignSpacing.sm),
                            Flexible(
                              child: Text(
                                isLocalWorkspace
                                    ? 'Records stay on this device'
                                    : 'Sales will sync when connected',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: statusColor.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          ]),
                    ),
                  // Subscription restricted-mode / expiry reminder banner
                  // (watches the entitlement provider; passive, never blocks
                  // navigation). The routed Scaffold/scroll views need a finite
                  // remaining height, whether the subscription host shows a
                  // banner or only the child.
                  Expanded(
                    // The strip already sits below the status bar; without this
                    // every tab pads for the status bar a second time and opens
                    // with an empty band under the strip.
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: showStrip,
                      child: TabletContent(
                        child: SubscriptionEntitlementHost(child: widget.child),
                      ),
                    ),
                  ),
                ],
              );
            },
          )),
          // Phone only: the tablet has its side rail instead. A floating bar
          // with a light that slides to the chosen tab.
          bottomNavigationBar: tablet
              ? null
              : FloatingNavBar(
                  items: [for (final item in visibleNavItems) destinationFor(item)],
                  selectedIndex: currentIndex,
                  onSelect: (i) {
                    if (i != currentIndex) HapticService().selection();
                    context.go(visibleNavItems[i].path);
                  },
                  moreKey: HomeNavKeys.more,
                  moreSelected: moreSelected,
                  onMore: hasMore
                      ? () {
                          HapticService().selection();
                          _showMoreSheet(moreItems);
                        }
                      : null,
                ),
        ));
  }
}

/// The More sheet: every extra area as a plain tile in a three-column grid,
/// so nothing hides below a long list and nothing wears an orange badge.
class _MoreGrid extends StatelessWidget {
  const _MoreGrid({
    required this.items,
    required this.bottomPadding,
    required this.onPick,
  });

  final List<_NavItem> items;
  final double bottomPadding;
  final ValueChanged<String> onPick;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheet = isDark ? DesignColors.darkSurface : Colors.white;
    final tile = isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceSubtle;
    final edge = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;
    final ink = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final icon = isDark ? DesignColors.brand : DesignColors.accent;

    return Material(
      color: sheet,
      borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DesignSpacing.radiusXxl)),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: bottomPadding > 0 ? 0 : DesignSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: DesignSpacing.md),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: edge,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('More',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: LayoutBuilder(builder: (context, box) {
                  final width = (box.maxWidth - _gap * 2) / 3;
                  return Wrap(
                    spacing: _gap,
                    runSpacing: _gap,
                    children: [
                      for (final item in items)
                        KeyedSubtree(
                          key: switch (item.path) {
                            '/inventory' => HomeNavKeys.moreSheetInventory,
                            '/reports' => HomeNavKeys.moreSheetReports,
                            '/settings' => HomeNavKeys.moreSheetSettings,
                            _ => null,
                          },
                          child: SizedBox(
                            width: width,
                            child: Semantics(
                              button: true,
                              label: item.label,
                              excludeSemantics: true,
                              child: Material(
                                color: tile,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => onPick(item.path),
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(minHeight: 96),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: edge),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        item.path == '/ai'
                                            ? const SizedBox(
                                                width: 40,
                                                height: 26,
                                                child: Center(
                                                  child: AxonAiIcon(
                                                    size: 26,
                                                    showAiTag: true,
                                                  ),
                                                ),
                                              )
                                            : Icon(item.icon, size: 26, color: icon),
                                        const SizedBox(height: 8),
                                        Text(
                                          item.label,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              height: 1.2,
                                              fontWeight: FontWeight.w600,
                                              color: ink),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ],
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

  _NavItem withLabel(String value) => _NavItem(
        icon: icon,
        activeIcon: activeIcon,
        label: value,
        path: path,
      );
}

/// "Update ready" chip in the desktop top bar. Opens the update window.
class _UpdateReadyChip extends StatelessWidget {
  const _UpdateReadyChip({required this.service});

  final DesktopUpdateService service;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final info = service.available;
        if (info == null) return const SizedBox.shrink();
        return Tooltip(
          message: 'Version ${info.version} is ready to install',
          child: InkWell(
            onTap: () => service.openOverlay(),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: DesignColors.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_circle_up_rounded,
                      size: 15, color: DesignColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Update ready',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? DesignColors.darkTextPrimary
                          : DesignColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
