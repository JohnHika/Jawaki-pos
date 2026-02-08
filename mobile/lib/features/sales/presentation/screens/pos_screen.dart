import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.point_of_sale, size: 22),
            const SizedBox(width: 8),
            const Text('POS'),
            if (cart.customerName != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    cart.customerName!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Customer button
          IconButton(
            icon: Icon(
              cart.customerName != null ? Icons.person : Icons.person_add_alt_1,
              color: cart.customerName != null ? AppColors.secondary : null,
            ),
            tooltip: 'Customer',
            onPressed: () => _showCustomerDialog(context),
          ),

          // Parked sales badge
          if (parkedSales.isNotEmpty)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.pause_circle_outline),
                  tooltip: 'Parked Sales',
                  onPressed: () => _showParkedSalesSheet(context),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.warning,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '${parkedSales.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),

          // Favorites toggle
          IconButton(
            icon: Icon(
              _showFavorites ? Icons.favorite : Icons.favorite_border,
              color: _showFavorites ? AppColors.error : null,
            ),
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
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      cart.itemCount.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      // Park Sale FAB – visible when cart isn't empty
      floatingActionButton: cart.items.isNotEmpty
          ? FloatingActionButton.small(
              heroTag: 'parkSale',
              backgroundColor: AppColors.warning,
              onPressed: () => _parkCurrentSale(context),
              tooltip: 'Park Sale',
              child: const Icon(Icons.pause, color: Colors.white),
            )
          : null,
      body: Column(
        children: [
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
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.favorite_border, size: 48, color: theme.disabledColor),
                                  const SizedBox(height: 8),
                                  Text('No favorite products yet',
                                      style: TextStyle(color: theme.disabledColor)),
                                ],
                              ),
                            );
                          }
                          return const ProductGrid();
                        },
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Error: $e')),
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
    final ctrl = TextEditingController(
      text: ref.read(cartProvider).customerName ?? '',
    );
    final db = getIt<AppDatabase>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20, right: 20, top: 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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

                  Text('Customer', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 12),

                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Customer Name',
                      hintText: 'e.g. John Doe',
                      prefixIcon: const Icon(Icons.person_outline),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          ctrl.clear();
                          setSheetState(() {});
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 12),

                  // Recent / matching customers
                  if (ctrl.text.trim().length >= 2)
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: db.searchCustomers(ctrl.text.trim()),
                      builder: (context, snap) {
                        final customers = snap.data ?? [];
                        if (customers.isEmpty) return const SizedBox.shrink();
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: customers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final c = customers[i];
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppColors.secondary.withOpacity(0.12),
                                  child: Text(
                                    (c['name'] as String).substring(0, 1).toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.secondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(c['name'] as String),
                                subtitle: Text(
                                  '${c['totalPurchases']} purchases · KES ${(c['totalSpent'] as double).toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onTap: () {
                                  ref.read(cartProvider.notifier).setCustomer(
                                    c['id'] as String,
                                    customerName: c['name'] as String,
                                  );
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            ref.read(cartProvider.notifier).setCustomer(null, customerName: null);
                            Navigator.pop(ctx);
                          },
                          child: const Text('Remove'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: ctrl.text.trim().isEmpty
                              ? null
                              : () async {
                                  final name = ctrl.text.trim();
                                  final id = await db.insertOrGetCustomer(
                                    const Uuid().v4(),
                                    name,
                                  );
                                  ref.read(cartProvider.notifier).setCustomer(id, customerName: name);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                          child: const Text('Set Customer'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ════════ Park Sale ════════

  void _parkCurrentSale(BuildContext context) {
    final cart = ref.read(cartProvider);
    if (cart.items.isEmpty) return;

    ref.read(parkedSalesProvider.notifier).park(cart);
    ref.read(cartProvider.notifier).clear();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sale parked${cart.customerName != null ? ' for ${cart.customerName}' : ''}'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'VIEW',
          onPressed: () => _showParkedSalesSheet(context),
        ),
      ),
    );
  }

  // ════════ Parked Sales Sheet ════════

  void _showParkedSalesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final parked = ref.watch(parkedSalesProvider);
            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.85,
              expand: false,
              builder: (context, scrollCtrl) {
                return Column(
                  children: [
                    // Handle
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.pause_circle_filled, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Text(
                            'Parked Sales (${parked.length})',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: parked.isEmpty
                          ? const Center(child: Text('No parked sales'))
                          : ListView.separated(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.all(16),
                              itemCount: parked.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final sale = parked[i];
                                final elapsed = DateTime.now()
                                    .difference(sale.parkedAt);
                                final timeStr = elapsed.inMinutes < 60
                                    ? '${elapsed.inMinutes}m ago'
                                    : '${elapsed.inHours}h ago';

                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          AppColors.warning.withOpacity(0.15),
                                      child: Text(
                                        '${sale.cart.itemCount}',
                                        style: const TextStyle(
                                          color: AppColors.warning,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      sale.label,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      'KES ${sale.cart.total.toStringAsFixed(0)} · $timeStr',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Resume
                                        IconButton(
                                          icon: const Icon(Icons.play_arrow,
                                              color: AppColors.secondary),
                                          tooltip: 'Resume',
                                          onPressed: () {
                                            final currentCart = ref.read(cartProvider);
                                            if (currentCart.items.isNotEmpty) {
                                              ref.read(parkedSalesProvider.notifier)
                                                  .park(currentCart);
                                            }
                                            final resumed = ref
                                                .read(parkedSalesProvider.notifier)
                                                .resume(sale.id);
                                            if (resumed != null) {
                                              ref.read(cartProvider.notifier)
                                                  .restoreFrom(resumed);
                                            }
                                            Navigator.pop(ctx);
                                          },
                                        ),
                                        // Delete
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              color: AppColors.error),
                                          tooltip: 'Discard',
                                          onPressed: () {
                                            ref.read(parkedSalesProvider.notifier)
                                                .remove(sale.id);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
