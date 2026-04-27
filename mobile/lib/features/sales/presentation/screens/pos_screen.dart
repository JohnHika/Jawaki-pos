import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
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
  bool _showFavorites = false;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final parkedSales = ref.watch(parkedSalesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: GlassCard(
          padding: EdgeInsets.zero,
          margin: EdgeInsets.zero,
          borderRadius: 0,
          blur: 24,
          tint: isDark
              ? DesignColors.darkSurface.withValues(alpha:0.92)
              : Colors.white.withValues(alpha:0.92),
          borderColor: isDark
              ? DesignColors.darkBorder
              : DesignColors.surfaceBorder,
          child: AppBar(
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [DesignColors.brand, DesignColors.brandDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: DesignColors.brand.withValues(alpha:0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.point_of_sale_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'POS',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    letterSpacing: -0.5,
                    color: isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary,
                  ),
                ),
                if (cart.customerName != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: DesignColors.teal.withValues(alpha:0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: DesignColors.teal.withValues(alpha:0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_rounded,
                              size: 12, color: DesignColors.teal),
                          const SizedBox(width: 4),
                          Text(
                            cart.customerName!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: DesignColors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            centerTitle: false,
            elevation: 0,
            backgroundColor: Colors.transparent,
            actions: [
              // Customer button
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cart.customerName != null
                        ? DesignColors.teal.withValues(alpha:0.12)
                        : DesignColors.brand.withValues(alpha:0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    cart.customerName != null
                        ? Icons.person_rounded
                        : Icons.person_add_alt_1_rounded,
                    color: cart.customerName != null
                        ? DesignColors.teal
                        : DesignColors.brand,
                    size: 20,
                  ),
                ),
                tooltip: 'Customer',
                onPressed: () => _showCustomerDialog(context),
              ),

              // Parked sales badge
              if (parkedSales.isNotEmpty)
                Stack(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.pause_circle_outline_rounded,
                        color: DesignColors.warning,
                      ),
                      tooltip: 'Parked Sales',
                      onPressed: () => _showParkedSalesSheet(context),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [DesignColors.warning, Color(0xFFD97706)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: DesignColors.warning.withValues(alpha:0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints:
                            const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          '${parkedSales.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),

              // Favorites toggle
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _showFavorites
                        ? DesignColors.error.withValues(alpha:0.12)
                        : DesignColors.brand.withValues(alpha:0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _showFavorites
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: _showFavorites ? DesignColors.error : DesignColors.brand,
                    size: 20,
                  ),
                ),
                tooltip: 'Favorites',
                onPressed: () {
                  setState(() {
                    _showFavorites = !_showFavorites;
                    if (_showFavorites) {
                      ref.read(selectedCategoryProvider.notifier).state = null;
                    }
                  });
                },
              ),

              // Cart with badge
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.shopping_cart_outlined),
                    onPressed: () => context.push('/cart'),
                  ),
                  if (cart.itemCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: TweenAnimationBuilder<int>(
                        duration: DesignAnimation.fast,
                        tween: IntTween(begin: 0, end: cart.itemCount),
                        builder: (context, value, child) {
                          return Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [DesignColors.brand, DesignColors.brandDark],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: DesignColors.brand.withValues(alpha:0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                                minWidth: 18, minHeight: 18),
                            child: Text(
                              '$value',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
      // Park Sale FAB – visible when cart isn't empty
      floatingActionButton: cart.items.isNotEmpty
          ? FloatingActionButton.small(
              heroTag: 'parkSale',
              backgroundColor: DesignColors.warning,
              onPressed: () => _parkCurrentSale(context),
              tooltip: 'Park Sale',
              child: const Icon(Icons.pause_rounded, color: Colors.white),
            )
          : null,
      body: Column(
        children: [
          // Spacer for glass app bar
          const SizedBox(height: 64),
          // Search Bar
          const SearchBarWidget(),

          // Category Chips
          if (!_showFavorites) const CategoryChips(),

          // Products Grid
          Expanded(
            child: _showFavorites
                ? Consumer(
                    builder: (context, ref, child) {
                      final favorites = ref.watch(favoriteProductsProvider);
                      return favorites.when(
                        data: (products) {
                          if (products.isEmpty) {
                            return EmptyState(
                              icon: Icons.favorite_border_rounded,
                              title: 'No favorite products yet',
                              subtitle:
                                  'Tap the heart icon on products to add them',
                            );
                          }
                          return const ProductGrid();
                        },
                        loading: () => const Center(
                          child: CircularProgressIndicator(
                            color: DesignColors.brand,
                          ),
                        ),
                        error: (e, _) => EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: 'Error loading favorites',
                          subtitle: e.toString(),
                          iconColor: DesignColors.error,
                        ),
                      );
                    },
                  )
                : const ProductGrid(),
          ),

          // Cart Summary Bar
          if (cart.itemCount > 0) const CartSummaryBar(),
        ],
      ),
    );
  }

  // ════════ Customer Dialog ════════

  void _showCustomerDialog(BuildContext context) {
    final cart = ref.read(cartProvider);
    final nameCtrl = TextEditingController(
      text: cart.customerName ?? '',
    );
    final phoneCtrl = TextEditingController();
    final db = getIt<AppDatabase>();

    if (cart.customerId != null) {
      db.getCustomer(cart.customerId!).then((customer) {
        if (customer != null) {
          phoneCtrl.text = customer['phone'] as String? ?? '';
        }
      });
    }

    GlassBottomSheet.show(
      context,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),

                Text(
                  'Customer',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set or search for a customer',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? DesignColors.darkTextSecondary
                        : DesignColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Customer Name',
                    hintText: 'e.g. John Doe',
                    prefixIcon:
                        const Icon(Icons.person_outline_rounded, size: 20),
                    suffixIcon: nameCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20),
                            onPressed: () {
                              nameCtrl.clear();
                              setSheetState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? DesignColors.darkSurfaceElevated
                            : DesignColors.surfaceMuted,
                  ),
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    hintText: 'e.g. 0712345678',
                    prefixIcon:
                        const Icon(Icons.phone_outlined, size: 20),
                    suffixIcon: phoneCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20),
                            onPressed: () {
                              phoneCtrl.clear();
                              setSheetState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? DesignColors.darkSurfaceElevated
                            : DesignColors.surfaceMuted,
                  ),
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 12),

                // Recent / matching customers
                if (nameCtrl.text.trim().length >= 2)
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: db.searchCustomers(nameCtrl.text.trim()),
                    builder: (context, snap) {
                      final customers = snap.data ?? [];
                      if (customers.isEmpty) return const SizedBox.shrink();
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: customers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 4),
                          itemBuilder: (_, i) {
                            final c = customers[i];
                            return GlassCard(
                              onTap: () {
                                ref.read(cartProvider.notifier).setCustomer(
                                  c['id'] as String,
                                  customerName: c['name'] as String,
                                );
                                Navigator.pop(context);
                              },
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              borderRadius: 10,
                              blur: 4,
                              tint: DesignColors.teal.withValues(alpha:0.04),
                              borderColor: DesignColors.surfaceBorder,
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: DesignColors.teal.withValues(alpha:0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        (c['name'] as String)
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          color: DesignColors.teal,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c['name'] as String,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          '${c['totalPurchases']} purchases \u00b7 KES ${(c['totalSpent'] as double).toStringAsFixed(0)}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color:
                                                  DesignColors.textTertiary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: DesignColors.textTertiary,
                                    size: 20,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ref
                              .read(cartProvider.notifier)
                              .setCustomer(null, customerName: null);
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? DesignColors.darkBorder
                                : DesignColors.surfaceBorder,
                          ),
                        ),
                        child: const Text('Remove'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GradientButton(
                        label: 'Set Customer',
                        icon: Icons.check_rounded,
                        onPressed: nameCtrl.text.trim().isEmpty
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                final phone = phoneCtrl.text.trim();
                                final id = await db.insertOrGetCustomer(
                                  const Uuid().v4(),
                                  name,
                                  phone: phone.isEmpty ? null : phone,
                                );
                                ref
                                    .read(cartProvider.notifier)
                                    .setCustomer(id, customerName: name);
                                if (context.mounted) Navigator.pop(context);
                              },
                        height: 48,
                        borderRadius: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  // ════════ Park Sale ════════

  void _parkCurrentSale(BuildContext context) {
    final cart = ref.read(cartProvider);
    if (cart.items.isEmpty) return;

    ref.read(parkedSalesProvider.notifier).park(cart);
    ref.read(cartProvider.notifier).clear();

    showGlassSnackBar(
      context,
      cart.customerName != null
          ? 'Sale parked for ${cart.customerName}'
          : 'Sale parked',
      icon: Icons.pause_circle_filled_rounded,
      color: DesignColors.warning,
      actionLabel: 'VIEW',
      onAction: () => _showParkedSalesSheet(context),
    );
  }

  // ════════ Parked Sales Sheet ════════

  void _showParkedSalesSheet(BuildContext context) {
    GlassBottomSheet.show(
      context,
      initialSize: 0.5,
      maxSize: 0.85,
      child: Consumer(
        builder: (context, ref, _) {
          final parked = ref.watch(parkedSalesProvider);
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: DesignColors.warning.withValues(alpha:0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.pause_circle_filled_rounded,
                        color: DesignColors.warning,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Parked Sales (${parked.length})',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (parked.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No parked sales',
                        style: TextStyle(
                          color: DesignColors.textTertiary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  )
                else
                  ...parked.map((sale) {
                    final elapsed =
                        DateTime.now().difference(sale.parkedAt);
                    final timeStr = elapsed.inMinutes < 60
                        ? '${elapsed.inMinutes}m ago'
                        : '${elapsed.inHours}h ago';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        padding: const EdgeInsets.all(12),
                        borderRadius: 14,
                        blur: 6,
                        tint: isDark
                            ? DesignColors.glassDark
                            : DesignColors.glassWhite,
                        borderColor: isDark
                            ? DesignColors.glassDarkBorder
                            : DesignColors.glassBorder,
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: DesignColors.warning.withValues(alpha:0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  '${sale.cart.itemCount}',
                                  style: const TextStyle(
                                    color: DesignColors.warning,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sale.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        'KES ${sale.cart.total.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: DesignColors.brand,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '\u00b7 $timeStr',
                                        style: TextStyle(
                                          color: isDark
                                              ? DesignColors.darkTextTertiary
                                              : DesignColors.textTertiary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Resume
                                Material(
                                  color: DesignColors.teal.withValues(alpha:0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () {
                                      final currentCart =
                                          ref.read(cartProvider);
                                      if (currentCart.items.isNotEmpty) {
                                        ref
                                            .read(
                                                parkedSalesProvider.notifier)
                                            .park(currentCart);
                                      }
                                      final resumed = ref
                                          .read(parkedSalesProvider.notifier)
                                          .resume(sale.id);
                                      if (resumed != null) {
                                        ref
                                            .read(cartProvider.notifier)
                                            .restoreFrom(resumed);
                                      }
                                      Navigator.pop(context);
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Icon(
                                        Icons.play_arrow_rounded,
                                        color: DesignColors.teal,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Delete
                                Material(
                                  color: DesignColors.error.withValues(alpha:0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () {
                                      ref
                                          .read(parkedSalesProvider.notifier)
                                          .remove(sale.id);
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Icon(
                                        Icons.delete_outline_rounded,
                                        color: DesignColors.error,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
              ],
            ),
          );
        },
      ),
    );
  }
}
