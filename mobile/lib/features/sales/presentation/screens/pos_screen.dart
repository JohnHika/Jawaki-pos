import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/widgets/motion_kit_extras.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
import '../widgets/category_chips.dart';
import '../widgets/product_grid.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/cart_summary_bar.dart';
import '../../../../core/utils/format.dart';
import '../../../accountability/data/till_guard_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../coupons/data/coupon_service.dart';

class POSScreen extends ConsumerStatefulWidget {
  const POSScreen({super.key});

  @override
  ConsumerState<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends ConsumerState<POSScreen> {
  bool _showFavorites = false;
  bool _catalogRefreshing = true;
  bool _catalogSyncFailed = false;
  bool _isOffline = false;
  String? _selectedProductPageId;
  String? _resumingHeldSaleId;
  Completer<void>? _catalogRefreshCompleter;
  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    final connectivity = getIt<ConnectivityService>();
    _isOffline = connectivity.currentStatus == ConnectionStatus.offline;
    _connectivitySubscription = connectivity.statusStream.listen((status) {
      if (!mounted) return;
      final isOffline = status == ConnectionStatus.offline;
      if (_isOffline != isOffline) setState(() => _isOffline = isOffline);
    });
    // Filters belong to one POS visit. A previous query (for example
    // "tessi") must not silently filter a newly mounted product grid.
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(selectedCategoryProvider.notifier).state = null;
    // Fetch the shop's price and credit rules so the till can apply them
    // even if the signal drops later. Fire-and-forget; it never throws.
    TillGuardService.instance.refreshIfStale();
    // The same for the shop's coupon codes.
    CouponService.instance.refreshIfStale();
    // The grid renders instantly from the local cache via
    // filteredProductsProvider, which never talks to the API on its own —
    // nothing else refreshes stock/prices for a cashier who lands here
    // straight from login without ever visiting the Products screen. Kick
    // off a background refresh so stock changes made elsewhere (other
    // devices, admin corrections) show up without requiring a detour
    // through Products first.
    Future.microtask(_refreshCatalog);
  }

  @override
  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    super.dispose();
  }

  Future<void> _refreshCatalog() async {
    if (!mounted) return;
    final inFlight = _catalogRefreshCompleter;
    if (inFlight != null) {
      await inFlight.future;
      return;
    }
    final completer = Completer<void>();
    _catalogRefreshCompleter = completer;
    setState(() {
      _catalogRefreshing = true;
      _catalogSyncFailed = false;
    });

    var failed = false;
    try {
      await syncCatalogCacheFromApi(onProductsCached: () {
        if (!mounted) return;
        // First catalog pages are committed with their prices and reconciled
        // stock while later pages continue downloading. Refresh the visible
        // POS query now so a new device can start selling before the full
        // catalog sync has to finish.
        ref.invalidate(filteredProductsProvider);
        ref.invalidate(favoriteProductsProvider);
      });
    } catch (_) {
      failed = true;
    } finally {
      if (mounted) {
        ref.invalidate(categoriesProvider);
        ref.invalidate(filteredProductsProvider);
        ref.invalidate(favoriteProductsProvider);
        setState(() {
          _catalogRefreshing = false;
          _catalogSyncFailed = failed;
        });
      }
      if (identical(_catalogRefreshCompleter, completer)) {
        _catalogRefreshCompleter = null;
      }
      if (!completer.isCompleted) completer.complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final parkedSales = ref.watch(parkedSalesProvider);
    final businessLayout = ref.watch(businessLayoutProvider);
    ref.listen<BusinessLayoutConfig>(businessLayoutProvider, (_, next) {
      if (!next.effectiveShowPosCategories &&
          ref.read(selectedCategoryProvider) != null) {
        ref.read(selectedCategoryProvider.notifier).state = null;
      }
      if (!next.effectiveShowPosFavorites && _showFavorites && mounted) {
        setState(() => _showFavorites = false);
      }
      if (_selectedProductPageId != null &&
          !next.posProductPages
              .any((page) => page.id == _selectedProductPageId) &&
          mounted) {
        setState(() => _selectedProductPageId = null);
      }
    });
    final showFavorites =
        businessLayout.effectiveShowPosFavorites && _showFavorites;
    final selectedProductPage = businessLayout.posProductPages
        .where((page) => page.id == _selectedProductPageId)
        .firstOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final configuredPosActions = businessLayout.effectivePosQuickActions
        .map((id) => MapEntry(
              id,
              _buildPosQuickAction(
                context,
                id,
                businessLayout: businessLayout,
                cart: cart,
                parkedSales: parkedSales,
                showFavorites: showFavorites,
                isDark: isDark,
              ),
            ))
        .where((entry) => entry.value != null)
        .toList(growable: false);
    // Keep the toolbar calm on phones even when the owner enables many
    // counter actions. The rest stay one tap away in the overflow menu.
    final visiblePosActions = configuredPosActions.take(3).toList();
    final overflowPosActions = configuredPosActions.skip(3).toList();

    return Scaffold(
      appBar: BrandedAppBar(
        title: businessLayout.actionLabel('/', 'POS'),
        showBackButton: false,
        actions: [
          ...visiblePosActions.map((entry) => entry.value!),
          if (overflowPosActions.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'More POS actions',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (id) => _activatePosQuickAction(context, id),
              itemBuilder: (menuContext) => overflowPosActions.map((entry) {
                final action = businessLayoutPosAction(entry.key);
                final label = entry.key == 'held_sales'
                    ? 'Held sales (${parkedSales.length})'
                    : action == null
                        ? entry.key
                        : businessLayout.actionLabel(
                            action.path ?? '', action.label);
                return PopupMenuItem<String>(
                  value: entry.key,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(action?.icon ?? Icons.bolt_rounded),
                    title: Text(label),
                  ),
                );
              }).toList(growable: false),
            ),
          const SizedBox(width: DesignSpacing.xs),
        ],
      ),
      body: Column(
        children: [
          // ── Compact Top Bar ──
          if (_isOffline)
            Container(
              width: double.infinity,
              // Sits below the AppBar, which already consumes the top system
              // inset, so no extra status-bar padding is needed.
              padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
              decoration: BoxDecoration(
                color: DesignColors.warning.withValues(alpha: 0.12),
                border: Border(
                  bottom: BorderSide(
                    color: DesignColors.warning.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: DesignSpacing.xs,
                    height: DesignSpacing.xs,
                    decoration: BoxDecoration(
                      color: DesignColors.warning,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: DesignColors.warning.withValues(alpha: 0.6),
                          blurRadius: DesignSpacing.xs,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DesignSpacing.sm - 2),
                  const Text(
                    'Offline Mode — sales will sync when reconnected',
                    style: TextStyle(
                      fontSize: DesignType.chatMeta,
                      fontWeight: FontWeight.w600,
                      color: DesignColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          // ── Main top bar (simplified) ──
          if (cart.customerName != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: DesignSpacing.lg, vertical: DesignSpacing.sm - 2),
              color: DesignColors.success.withValues(alpha: 0.08),
              child: Row(
                children: [
                  const Icon(Icons.person_outline_rounded,
                      size: 15, color: DesignColors.success),
                  const SizedBox(width: DesignSpacing.sm - 2),
                  Expanded(
                    child: Text(
                      cart.customerName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: DesignType.chatMeta,
                        color: DesignColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text('${businessLayout.customerSingular} selected',
                      style: const TextStyle(
                          fontSize: 10,
                          color: DesignColors.success,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                DesignSpacing.sm, DesignSpacing.lg, DesignSpacing.sm - 3),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(DesignSpacing.sm - 1),
                  decoration: BoxDecoration(
                    color: DesignColors.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DesignSpacing.sm + 1),
                  ),
                  child: const Icon(Icons.point_of_sale_rounded,
                      size: 17, color: DesignColors.brand),
                ),
                const SizedBox(width: DesignSpacing.sm + 1),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        showFavorites
                            ? 'Favorites'
                            : selectedProductPage?.name ?? 'Sell',
                        style: TextStyle(
                          fontSize: DesignType.chatBody + 1,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? DesignColors.darkTextPrimary
                              : DesignColors.textPrimary,
                        ),
                      ),
                      Text(
                        showFavorites
                            ? 'Saved ${businessLayout.productsLabel.toLowerCase()}'
                            : selectedProductPage != null
                                ? '${selectedProductPage.productIds.length} quick items'
                                : 'Choose ${businessLayout.productsLabel.toLowerCase()} to start a sale',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? DesignColors.darkTextSecondary
                              : DesignColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (cart.itemCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.md - 2,
                        vertical: DesignSpacing.sm - 3),
                    decoration: BoxDecoration(
                      color: DesignColors.success.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusFull),
                      border: Border.all(
                          color: DesignColors.success.withValues(alpha: 0.24)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shopping_bag_rounded,
                            size: 14, color: DesignColors.success),
                        const SizedBox(width: DesignSpacing.sm - 2),
                        Text(
                          '${cart.itemCount} Cart',
                          style: const TextStyle(
                            fontSize: DesignType.chatMeta,
                            fontWeight: FontWeight.w700,
                            color: DesignColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // ── Body ──
          const SearchBarWidget(),
          if (!showFavorites && businessLayout.effectiveShowPosCategories)
            const CategoryChips(),
          if (!showFavorites && businessLayout.posProductPages.isNotEmpty)
            _productPagePicker(businessLayout),
          Expanded(
            child: showFavorites
                ? Consumer(
                    builder: (context, ref, child) {
                      final favorites = ref.watch(favoriteProductsProvider);
                      return favorites.when(
                        data: (products) => products.isEmpty
                            ? const EmptyState(
                                icon: Icons.favorite_border_rounded,
                                title: 'No favorites',
                                subtitle: 'Tap heart on products to add')
                            : ProductGrid(productsOverride: products),
                        loading: () => const Center(
                            child: CircularProgressIndicator(
                                color: DesignColors.accent)),
                        error: (e, _) => EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: 'Error loading favorites',
                          subtitle: apiErrorMessage(e),
                          iconColor: DesignColors.error,
                          actionLabel: 'Retry',
                          onAction: () => ref.refresh(favoriteProductsProvider),
                        ),
                      );
                    },
                  )
                : ProductGrid(
                    productPageIds: selectedProductPage?.productIds,
                    catalogRefreshing: _catalogRefreshing,
                    catalogSyncFailed: _catalogSyncFailed,
                    isOffline: _isOffline,
                    onRetryCatalog: _refreshCatalog,
                  ),
          ),
          if (cart.itemCount > 0) const CartSummaryBar(),
        ],
      ),
    );
  }

  Widget _productPagePicker(BusinessLayoutConfig layout) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          ChoiceChip(
            label: Text('All ${layout.productsLabel.toLowerCase()}'),
            selected: _selectedProductPageId == null,
            onSelected: (_) => setState(() {
              _selectedProductPageId = null;
              ref.read(selectedCategoryProvider.notifier).state = null;
            }),
          ),
          ...layout.posProductPages.map((page) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: Text(page.name),
                  selected: _selectedProductPageId == page.id,
                  selectedColor:
                      DesignColors.accent.withValues(alpha: isDark ? .22 : .14),
                  onSelected: (_) => setState(() {
                    _selectedProductPageId = page.id;
                    ref.read(selectedCategoryProvider.notifier).state = null;
                  }),
                ),
              )),
        ],
      ),
    );
  }

  Widget _topAction(
      IconData icon, String tooltip, VoidCallback onTap, bool isDark,
      {bool active = false}) {
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignSpacing.md - 2),
        onTap: onTap,
        child: Container(
          // App-bar action: 40px box + 8px outer vertical hit slop through the
          // standard 8px toolbar padding keeps the effective target at the
          // 48px Material tap-target size (sub-44 raw box was the violation).
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: const EdgeInsets.all(DesignSpacing.sm),
          decoration: BoxDecoration(
            color: active
                ? DesignColors.error.withValues(alpha: 0.1)
                : DesignColors.accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(DesignSpacing.md - 2),
          ),
          child: Icon(icon,
              color: active ? DesignColors.error : secondaryColor, size: 20),
        ),
      ),
    );
  }

  Widget? _buildPosQuickAction(
    BuildContext context,
    String id, {
    required BusinessLayoutConfig businessLayout,
    required CartState cart,
    required List<ParkedSale> parkedSales,
    required bool showFavorites,
    required bool isDark,
  }) {
    final destination = businessLayoutPosAction(id);
    final path = destination?.path;
    if (path != null) {
      final permissions = ref.read(permissionsProvider);
      if (!businessLayout.isActionVisible(path) ||
          !businessLayoutCanOpenPath(permissions, path)) {
        return null;
      }
      return _topAction(
        destination!.icon,
        businessLayout.actionLabel(path, destination.label),
        () => context.push(path),
        isDark,
      );
    }

    switch (id) {
      case 'customer':
        if (!businessLayout.effectiveShowPosCustomer) return null;
        return _topAction(
          Icons.person_add_alt_1_rounded,
          businessLayout.customerSingular,
          () => _showCustomerDialog(context),
          isDark,
        );
      case 'favorites':
        if (!businessLayout.effectiveShowPosFavorites) return null;
        return _topAction(
          showFavorites
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          'Favorites',
          () {
            setState(() {
              _showFavorites = !_showFavorites;
              if (_showFavorites) _selectedProductPageId = null;
              if (_showFavorites) {
                ref.read(selectedCategoryProvider.notifier).state = null;
              }
            });
          },
          isDark,
          active: showFavorites,
        );
      case 'held_sales':
        if (parkedSales.isEmpty) return null;
        return _topAction(
          Icons.inventory_2_outlined,
          'Held (${parkedSales.length})',
          () => _showParkedSalesSheet(context),
          isDark,
        );
      case 'hold_sale':
        if (cart.items.isEmpty) return null;
        return _topAction(
          Icons.pause_rounded,
          'Hold Sale',
          () => _parkCurrentSale(context),
          isDark,
        );
      case 'cart':
        return Stack(
          children: [
            _topAction(Icons.shopping_cart_outlined, 'Cart',
                () => context.push('/cart'), isDark),
            if (cart.itemCount > 0)
              Positioned(
                right: 2,
                top: 0,
                child: BumpOnChange(
                  trigger: cart.itemCount,
                  scale: 1.45,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    constraints:
                        const BoxConstraints(minWidth: 15, minHeight: 15),
                    decoration: const BoxDecoration(
                      color: DesignColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${cart.itemCount}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      default:
        return null;
    }
  }

  void _activatePosQuickAction(BuildContext context, String id) {
    switch (id) {
      case 'customer':
        _showCustomerDialog(context);
      case 'favorites':
        setState(() {
          _showFavorites = !_showFavorites;
          if (_showFavorites) _selectedProductPageId = null;
          if (_showFavorites) {
            ref.read(selectedCategoryProvider.notifier).state = null;
          }
        });
      case 'held_sales':
        _showParkedSalesSheet(context);
      case 'hold_sale':
        _parkCurrentSale(context);
      case 'cart':
        context.push('/cart');
      default:
        final path = businessLayoutPosAction(id)?.path;
        if (path != null &&
            ref.read(businessLayoutProvider).isActionVisible(path) &&
            businessLayoutCanOpenPath(ref.read(permissionsProvider), path)) {
          context.push(path);
        }
    }
  }

  void _showCustomerDialog(BuildContext context) {
    final cart = ref.read(cartProvider);
    final businessLayout = ref.read(businessLayoutProvider);
    final customerSingular = businessLayout.customerSingular;
    final nameCtrl = TextEditingController(text: cart.customerName ?? '');
    final phoneCtrl = TextEditingController();
    final db = getIt<AppDatabase>();
    if (cart.customerId != null) {
      db.getCustomer(cart.customerId!).then((c) {
        if (c != null) phoneCtrl.text = c['phone'] as String? ?? '';
      });
    }

    GlassBottomSheet.show(context, scrollable: true, child: StatefulBuilder(
      builder: (ctx, setSheet) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final secondaryColor = isDark
            ? DesignColors.darkTextSecondary
            : DesignColors.textSecondary;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            DesignSpacing.xl,
            0,
            DesignSpacing.xl,
            DesignSpacing.xl + MediaQuery.of(ctx).padding.bottom,
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: DesignSpacing.sm),
                Text(
                  'Search ${businessLayout.customersLabel.toLowerCase()} or create a new ${customerSingular.toLowerCase()}',
                  style: TextStyle(
                      fontSize: DesignType.chatBody - 1, color: secondaryColor),
                ),
                const SizedBox(height: DesignSpacing.md + 2),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: '$customerSingular or shop name',
                    hintText: 'Start typing a name',
                    prefixIcon:
                        const Icon(Icons.person_outline_rounded, size: 20),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                    ),
                    filled: true,
                  ),
                  onChanged: (_) => setSheet(() {}),
                ),
                const SizedBox(height: DesignSpacing.md - 2),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone number (optional)',
                    hintText: '07xx xxx xxx',
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                    ),
                    filled: true,
                  ),
                  onChanged: (_) => setSheet(() {}),
                ),
                if (nameCtrl.text.trim().length >= 2)
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: db.searchCustomers(nameCtrl.text.trim()),
                    builder: (_, snap) {
                      final customers = snap.data ?? [];
                      if (customers.isEmpty) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(top: DesignSpacing.sm),
                        padding: const EdgeInsets.symmetric(
                            vertical: DesignSpacing.xs),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).brightness == Brightness.dark
                              ? DesignColors.darkSurfaceElevated
                              : DesignColors.surfaceSubtle,
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusMd),
                          border: Border.all(
                            color: Theme.of(ctx).brightness == Brightness.dark
                                ? DesignColors.darkBorder
                                : DesignColors.surfaceBorder,
                          ),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          primary: false,
                          itemCount: customers.length,
                          itemBuilder: (_, i) => ListTile(
                            minTileHeight: 52,
                            leading: CircleAvatar(
                                backgroundColor:
                                    DesignColors.accent.withValues(alpha: 0.12),
                                child: Text((customers[i]['name'] as String)[0]
                                    .toUpperCase())),
                            title: Text(customers[i]['name'] as String),
                            subtitle: Text(
                                '${customers[i]['totalPurchases']} purchases'),
                            onTap: () {
                              ref.read(cartProvider.notifier).setCustomer(
                                  customers[i]['id'] as String,
                                  customerName: customers[i]['name'] as String);
                              Navigator.pop(ctx);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: DesignSpacing.md + 2),
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () {
                            ref
                                .read(cartProvider.notifier)
                                .setCustomer(null, customerName: null);
                            Navigator.pop(ctx);
                          },
                          child:
                              Text('Clear ${customerSingular.toLowerCase()}'))),
                  const SizedBox(width: DesignSpacing.md - 2),
                  Expanded(
                      flex: 2,
                      child: GradientButton(
                          label: 'Create & select',
                          onPressed: nameCtrl.text.trim().isEmpty
                              ? null
                              : () async {
                                  final id = await db.insertOrGetCustomer(
                                      const Uuid().v4(), nameCtrl.text.trim(),
                                      phone: phoneCtrl.text.trim());
                                  // Queue for cross-device sync
                                  try {
                                    final syncService = getIt<SyncService>();
                                    final storage = getIt<StorageService>();
                                    final auth = getIt<AuthService>();
                                    await syncService.queueSyncItem(
                                      tableName: 'customers',
                                      recordId: id,
                                      action: SyncAction.create,
                                      eventType: SyncEventType.customerCreated,
                                      data: {
                                        'id': id,
                                        'name': nameCtrl.text.trim(),
                                        'phone': phoneCtrl.text.trim(),
                                      },
                                      deviceId: storage.getDeviceId() ?? '',
                                      userId: auth.userId ?? '',
                                    );
                                  } catch (_) {}
                                  ref.read(cartProvider.notifier).setCustomer(
                                      id,
                                      customerName: nameCtrl.text.trim());
                                  if (context.mounted) Navigator.pop(context);
                                },
                          height: 44,
                          borderRadius: 12)),
                ]),
              ]),
        );
      },
    ));
  }

  Future<void> _parkCurrentSale(BuildContext context) async {
    final cart = ref.read(cartProvider);
    if (cart.items.isEmpty) return;
    try {
      await ref.read(parkedSalesProvider.notifier).park(cart);
    } catch (error) {
      if (mounted && context.mounted) {
        showGlassSnackBar(
          context,
          'Could not save the held sale. Your cart is still here. ${apiErrorMessage(error)}',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
      return;
    }
    if (!mounted || !context.mounted) return;
    final currentCart = ref.read(cartProvider);
    if (!identical(currentCart, cart)) {
      if (currentCart.items.isEmpty) return;
      showGlassSnackBar(
        context,
        'Sale saved. Your cart changed while it was saving, so the updated cart is still open.',
        icon: Icons.info_outline_rounded,
        color: DesignColors.warning,
      );
      return;
    }
    ref.read(cartProvider.notifier).clear();
    showGlassSnackBar(context, 'Sale held',
        icon: Icons.pause_circle_filled_rounded, color: DesignColors.warning);
  }

  void _showParkedSalesSheet(BuildContext context) {
    GlassBottomSheet.show(context, initialSize: 0.55, maxSize: 0.85,
        child: Consumer(
      builder: (ctx, ref, _) {
        final parked = ref.watch(parkedSalesProvider);
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              DesignSpacing.xl,
              DesignSpacing.sm,
              DesignSpacing.xl,
              DesignSpacing.lg + MediaQuery.of(ctx).padding.bottom),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                      padding: const EdgeInsets.all(DesignSpacing.sm),
                      decoration: BoxDecoration(
                          color: DesignColors.warning.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.md - 2)),
                      child: const Icon(Icons.pause_circle_filled_rounded,
                          color: DesignColors.warning, size: 22)),
                  const SizedBox(width: DesignSpacing.md - 2),
                  Text('Held Sales (${parked.length})',
                      style: TextStyle(
                          fontSize: DesignSpacing.md + 6,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? DesignColors.darkTextPrimary
                              : DesignColors.textPrimary)),
                ]),
                if (parked.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: DesignSpacing.xxl + 16),
                      child: Center(
                          child: Text('No parked sales',
                              style: TextStyle(
                                  color: isDark
                                      ? DesignColors.darkTextTertiary
                                      : DesignColors.textTertiary))))
                else
                  ...parked.map((s) {
                    final elapsed = DateTime.now().difference(s.parkedAt);
                    return Padding(
                        padding: const EdgeInsets.only(top: DesignSpacing.sm),
                        child: ListCard(
                          leading: Container(
                              width: DesignSpacing.md + 28,
                              height: DesignSpacing.md + 28,
                              decoration: BoxDecoration(
                                  color: DesignColors.warning
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(
                                      DesignSpacing.md - 2)),
                              child: Center(
                                  child: Text('${s.cart.itemCount}',
                                      style: const TextStyle(
                                          color: DesignColors.warning,
                                          fontWeight: FontWeight.bold)))),
                          title: s.label,
                          subtitle:
                              '${formatMoney(s.cart.total)} \u00b7 ${elapsed.inMinutes}m ago',
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                tooltip: 'Resume held sale',
                                icon: const Icon(Icons.play_arrow_rounded,
                                    color: DesignColors.success),
                                onPressed: () {
                                  _resumeHeldSale(ctx, ref, s);
                                }),
                            IconButton(
                                tooltip: 'Delete held sale',
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: DesignColors.error),
                                onPressed: _resumingHeldSaleId != null
                                    ? null
                                    : () async {
                                        final confirmed =
                                            await showConfirmDialog(
                                          ctx,
                                          title: 'Discard Held Sale',
                                          message:
                                              'Discard "${s.label}"? This sale will be permanently removed.',
                                          confirmLabel: 'Discard',
                                          confirmColor: DesignColors.error,
                                        );
                                        if (confirmed == true && ctx.mounted) {
                                          try {
                                            await ref
                                                .read(parkedSalesProvider
                                                    .notifier)
                                                .remove(s.id);
                                          } catch (error) {
                                            if (ctx.mounted) {
                                              showGlassSnackBar(
                                                ctx,
                                                'Could not discard the held sale. It is still saved. ${apiErrorMessage(error)}',
                                                icon:
                                                    Icons.error_outline_rounded,
                                                color: DesignColors.error,
                                              );
                                            }
                                          }
                                        }
                                      }),
                          ]),
                          onTap: () {
                            _resumeHeldSale(ctx, ref, s);
                          },
                        ));
                  }),
              ]),
        );
      },
    ));
  }

  Future<void> _resumeHeldSale(
    BuildContext context,
    WidgetRef ref,
    ParkedSale sale,
  ) async {
    if (_resumingHeldSaleId != null) return;
    setState(() => _resumingHeldSaleId = sale.id);
    try {
      var catalogRefreshed = false;
      if (getIt<ConnectivityService>().currentStatus !=
          ConnectionStatus.offline) {
        await _refreshCatalog();
        catalogRefreshed = !_catalogSyncFailed;
      }
      if (!mounted || !context.mounted) return;

      final cartNotifier = ref.read(cartProvider.notifier);
      final review = await cartNotifier.reviewHeldSale(sale.cart);
      if (!mounted || !context.mounted) return;

      var cartToResume = review.cart;
      if (review.priceChanges.isNotEmpty) {
        final canKeepSavedPrices =
            await TillGuardService.instance.canOverridePrice();
        if (!mounted || !context.mounted) return;
        final updatedPrices = cartNotifier.applyCurrentHeldSalePrices(review);
        final decision = await _showHeldSalePriceReview(
          context,
          review,
          updatedPrices,
          canKeepSavedPrices: canKeepSavedPrices,
        );
        if (decision == null || !mounted || !context.mounted) return;
        if (decision == _HeldSalePriceDecision.useCurrentPrices) {
          cartToResume = updatedPrices;
        }
      }

      final catalogConfirmed = catalogRefreshed && review.catalogDataComplete;
      if (!catalogConfirmed || review.stockIssues.isNotEmpty) {
        final proceed = await _showHeldSaleStockReview(
          context,
          review,
          catalogConfirmed: catalogConfirmed,
        );
        if (proceed != true || !mounted || !context.mounted) return;
      }

      // Keep the held sale intact if the sheet was dismissed or another
      // cashier action already removed it while catalog checks were running.
      if (!ref.read(parkedSalesProvider).any((item) => item.id == sale.id)) {
        return;
      }
      final current = ref.read(cartProvider);
      final cartSessionGeneration = cartNotifier.sessionGeneration;
      final resumed = await ref
          .read(parkedSalesProvider.notifier)
          .resumeHeldSale(
            sale.id,
            current,
            reviewedCart: cartToResume,
            installCart: (saved) =>
                cartNotifier.restoreFromSession(saved, cartSessionGeneration),
          );
      if (!resumed || !mounted || !context.mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted && context.mounted) {
        showGlassSnackBar(
          context,
          'Could not review this held sale. It is still saved; try again.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
      debugPrint('[HeldSales] Resume review failed: $error');
    } finally {
      if (mounted) setState(() => _resumingHeldSaleId = null);
    }
  }

  Future<_HeldSalePriceDecision?> _showHeldSalePriceReview(
    BuildContext context,
    HeldSaleReview review,
    CartState currentPriceCart, {
    required bool canKeepSavedPrices,
  }) {
    final changes = review.priceChanges;
    return showDialog<_HeldSalePriceDecision>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Catalog prices changed'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review these items before checkout. The cart subtotal changes from '
                'KES ${review.cart.subtotal.toStringAsFixed(2)} to '
                'KES ${currentPriceCart.subtotal.toStringAsFixed(2)}.',
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: changes.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, index) {
                    final change = changes[index];
                    final factor = change.item.unitConversionFactor ?? 1;
                    final unit = change.item.saleUnit ?? 'unit';
                    final saved = change.item.unitPrice * factor;
                    final current = change.currentCatalogUnitPrice * factor;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(change.item.productName),
                      subtitle: Text(
                        'Saved KES ${saved.toStringAsFixed(2)} per $unit · '
                        'Current KES ${current.toStringAsFixed(2)} per $unit',
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          if (canKeepSavedPrices)
            TextButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_HeldSalePriceDecision.keepSavedPrices),
              child: const Text('Keep held prices'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(_HeldSalePriceDecision.useCurrentPrices),
            child: const Text('Use current prices'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showHeldSaleStockReview(
    BuildContext context,
    HeldSaleReview review, {
    required bool catalogConfirmed,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review held sale before checkout'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!catalogConfirmed) ...[
                const Text(
                  'The latest catalog and stock could not be fully confirmed. Review the available device data before charging.',
                ),
                if (review.stockIssues.isNotEmpty) const SizedBox(height: 10),
              ],
              if (review.stockIssues.isEmpty)
                const Text(
                  'Review the cart before checkout. The catalog could not confirm every current detail.',
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: review.stockIssues.length,
                    separatorBuilder: (_, __) => const Divider(height: 10),
                    itemBuilder: (context, index) {
                      final issue = review.stockIssues[index];
                      final stock = issue.currentStock;
                      final quantityDetail = stock == null
                          ? ''
                          : ' Requested ${_formatHeldQuantity(issue.requestedQuantity)}, available ${_formatHeldQuantity(stock)}.';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(issue.productName),
                        subtitle: Text('${issue.message}$quantityDetail'),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep on hold'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open to review'),
          ),
        ],
      ),
    );
  }
}

enum _HeldSalePriceDecision { useCurrentPrices, keepSavedPrices }

String _formatHeldQuantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
