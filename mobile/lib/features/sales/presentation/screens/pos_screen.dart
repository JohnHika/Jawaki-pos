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
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
import '../widgets/category_chips.dart';
import '../widgets/product_grid.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/cart_summary_bar.dart';

class POSScreen extends ConsumerStatefulWidget {
  const POSScreen({super.key});

  @override
  ConsumerState<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends ConsumerState<POSScreen> {
  static String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('connection')) {
      return 'Please check your internet connection and try again';
    } else if (errorString.contains('timeout')) {
      return 'Request timed out. Please try again.';
    } else if (errorString.contains('format') ||
        errorString.contains('parse')) {
      return 'Data format error. We\'re working to fix this.';
    } else if (errorString.contains('auth') ||
        errorString.contains('permission') ||
        errorString.contains('unauthorized')) {
      return 'Authentication required. Please log in again.';
    } else if (error is Exception) {
      return 'An unexpected error occurred. Please try again.';
    }

    return 'Unable to complete request. Please try again.';
  }

  bool _showFavorites = false;

  @override
  void initState() {
    super.initState();
    // Filters belong to one POS visit. A previous query (for example
    // "tessi") must not silently filter a newly mounted product grid.
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(selectedCategoryProvider.notifier).state = null;
    // The grid renders instantly from the local cache via
    // filteredProductsProvider, which never talks to the API on its own —
    // nothing else refreshes stock/prices for a cashier who lands here
    // straight from login without ever visiting the Products screen. Kick
    // off a background refresh so stock changes made elsewhere (other
    // devices, admin corrections) show up without requiring a detour
    // through Products first.
    Future.microtask(() async {
      try {
        await syncCatalogCacheFromApi();
      } catch (_) {
        return;
      }
      if (!mounted) return;
      ref.invalidate(filteredProductsProvider);
      ref.invalidate(favoriteProductsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final parkedSales = ref.watch(parkedSalesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connectivity = getIt<ConnectivityService>();

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'POS',
        showBackButton: false,
        actions: [
          _topAction(Icons.person_add_alt_1_rounded, 'Customer',
              () => _showCustomerDialog(context), isDark),
          _topAction(
              _showFavorites
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              'Favorites', () {
            setState(() {
              _showFavorites = !_showFavorites;
              if (_showFavorites) {
                ref.read(selectedCategoryProvider.notifier).state = null;
              }
            });
          }, isDark, active: _showFavorites),
          if (parkedSales.isNotEmpty)
            _topAction(
                Icons.inventory_2_outlined,
                'Parked (${parkedSales.length})',
                () => _showParkedSalesSheet(context),
                isDark),
          if (cart.items.isNotEmpty)
            _topAction(Icons.pause_rounded, 'Park Sale',
                () => _parkCurrentSale(context), isDark),
          Stack(
            children: [
              _topAction(Icons.shopping_cart_outlined, 'Cart',
                  () => context.push('/cart'), isDark),
              if (cart.itemCount > 0)
                Positioned(
                  right: 2,
                  top: 0,
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
            ],
          ),
          const SizedBox(width: DesignSpacing.xs),
        ],
      ),
      body: Column(
        children: [
          // ── Compact Top Bar ──
          StreamBuilder<ConnectionStatus>(
            stream: connectivity.statusStream,
            initialData: connectivity.currentStatus,
            builder: (context, snap) {
              final isOffline = snap.data == ConnectionStatus.offline;
              if (isOffline) {
                return Container(
                  width: double.infinity,
                  // Sits below the AppBar, which already consumes the top
                  // system inset - re-adding the status-bar padding here
                  // double-padded the banner, so no manual top inset (and no
                  // SafeArea) is needed.
                  padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
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
                        width: DesignSpacing.xs,
                        height: DesignSpacing.xs,
                        decoration: BoxDecoration(
                          color: DesignColors.warning,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color:
                                    DesignColors.warning.withValues(alpha: 0.6),
                                blurRadius: DesignSpacing.xs)
                          ],
                        ),
                      ),
                      const SizedBox(width: DesignSpacing.sm - 2),
                      const Text(
                        'Offline Mode — sales will sync when reconnected',
                        style: TextStyle(
                            fontSize: DesignType.chatMeta,
                            fontWeight: FontWeight.w600,
                            color: DesignColors.warning),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
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
                  const Text('Customer selected',
                      style: TextStyle(
                          fontSize: 10,
                          color: DesignColors.success,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.sm,
                DesignSpacing.lg, DesignSpacing.sm - 3),
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
                        _showFavorites ? 'Favorites' : 'Sell',
                        style: TextStyle(
                          fontSize: DesignType.chatBody + 1,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? DesignColors.darkTextPrimary
                              : DesignColors.textPrimary,
                        ),
                      ),
                      Text(
                        _showFavorites
                            ? 'Saved products'
                            : 'Choose products to start a sale',
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
          if (!_showFavorites) const CategoryChips(),
          Expanded(
            child: _showFavorites
                ? Consumer(
                    builder: (context, ref, child) {
                      final favorites = ref.watch(favoriteProductsProvider);
                      return favorites.when(
                        data: (products) => products.isEmpty
                            ? const EmptyState(
                                icon: Icons.favorite_border_rounded,
                                title: 'No favorites',
                                subtitle: 'Tap heart on products to add')
                            : const ProductGrid(),
                        loading: () => const Center(
                            child: CircularProgressIndicator(
                                color: DesignColors.accent)),
                        error: (e, _) => EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: 'Error loading favorites',
                          subtitle: _getUserFriendlyErrorMessage(e),
                          iconColor: DesignColors.error,
                          actionLabel: 'Retry',
                          onAction: () => ref.refresh(favoriteProductsProvider),
                        ),
                      );
                    },
                  )
                : const ProductGrid(),
          ),
          if (cart.itemCount > 0) const CartSummaryBar(),
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

  void _showCustomerDialog(BuildContext context) {
    final cart = ref.read(cartProvider);
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
                const Text('Customer',
                    style: TextStyle(
                        fontSize: DesignSpacing.xl, fontWeight: FontWeight.w700)),
                const SizedBox(height: DesignSpacing.xs),
                Text('Set or search for a customer',
                    style: TextStyle(
                        fontSize: DesignType.chatBody - 1,
                        color: secondaryColor)),
                const SizedBox(height: DesignSpacing.md + 2),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                      labelText: 'Name',
                      prefixIcon:
                          const Icon(Icons.person_outline_rounded, size: 20),
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusMd),
                          borderSide: BorderSide.none),
                      filled: true),
                  onChanged: (_) => setSheet(() {}),
                ),
                const SizedBox(height: DesignSpacing.md - 2),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusMd),
                          borderSide: BorderSide.none),
                      filled: true),
                  onChanged: (_) => setSheet(() {}),
                ),
                if (nameCtrl.text.trim().length >= 2)
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: db.searchCustomers(nameCtrl.text.trim()),
                    builder: (_, snap) {
                      final customers = snap.data ?? [];
                      if (customers.isEmpty) return const SizedBox.shrink();
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 224),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          primary: false,
                          itemCount: customers.length,
                          itemBuilder: (_, i) => ListTile(
                            dense: true,
                            leading: CircleAvatar(
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
                            Navigator.pop(context);
                          },
                          child: const Text('Remove'))),
                  const SizedBox(width: DesignSpacing.md - 2),
                  Expanded(
                      flex: 2,
                      child: GradientButton(
                          label: 'Set',
                          onPressed: nameCtrl.text.isEmpty
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

  void _parkCurrentSale(BuildContext context) {
    final cart = ref.read(cartProvider);
    if (cart.items.isEmpty) return;
    ref.read(parkedSalesProvider.notifier).park(cart);
    ref.read(cartProvider.notifier).clear();
    showGlassSnackBar(context, 'Sale parked',
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
                  Text('Parked (${parked.length})',
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
                              'KES ${s.cart.total.toStringAsFixed(0)} \u00b7 ${elapsed.inMinutes}m ago',
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                icon: const Icon(Icons.play_arrow_rounded,
                                    color: DesignColors.success),
                                onPressed: () {
                                  final current = ref.read(cartProvider);
                                  if (current.items.isNotEmpty) {
                                    ref
                                        .read(parkedSalesProvider.notifier)
                                        .park(current);
                                  }
                                  final resumed = ref
                                      .read(parkedSalesProvider.notifier)
                                      .resume(s.id);
                                  if (resumed != null) {
                                    ref
                                        .read(cartProvider.notifier)
                                        .restoreFrom(resumed);
                                  }
                                  Navigator.pop(ctx);
                                }),
                            IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: DesignColors.error),
                                onPressed: () async {
                                  final confirmed = await showConfirmDialog(
                                    ctx,
                                    title: 'Discard Parked Sale',
                                    message:
                                        'Discard "${s.label}"? This sale will be permanently removed.',
                                    confirmLabel: 'Discard',
                                    confirmColor: DesignColors.error,
                                  );
                                  if (confirmed == true) {
                                    ref
                                        .read(parkedSalesProvider.notifier)
                                        .remove(s.id);
                                  }
                                }),
                          ]),
                          onTap: () {
                            Navigator.pop(ctx);
                            ref.read(cartProvider.notifier).restoreFrom(s.cart);
                            ref.read(parkedSalesProvider.notifier).remove(s.id);
                          },
                        ));
                  }),
              ]),
        );
      },
    ));
  }
}
