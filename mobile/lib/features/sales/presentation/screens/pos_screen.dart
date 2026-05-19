import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/connectivity_service.dart';
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
    final connectivity = getIt<ConnectivityService>();

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'POS',
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
                      gradient: LinearGradient(
                        colors: [DesignColors.brand, DesignColors.brandDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${cart.itemCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
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
                  padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top, bottom: 6),
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
                        decoration: BoxDecoration(
                          color: DesignColors.warning,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color:
                                    DesignColors.warning.withValues(alpha: 0.6),
                                blurRadius: 4)
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Offline Mode — sales will sync when reconnected',
                        style: TextStyle(
                            fontSize: 11,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: DesignColors.teal.withValues(alpha: 0.08),
              child: Text(
                cart.customerName!,
                style: const TextStyle(
                  fontSize: 11,
                  color: DesignColors.teal,
                  fontWeight: FontWeight.w700,
                ),
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
                                color: DesignColors.brand)),
                        error: (e, _) => EmptyState(
                            icon: Icons.error_outline_rounded,
                            title: 'Error',
                            subtitle: e.toString(),
                            iconColor: DesignColors.error),
                      );
                    },
                  )
                : const ProductGrid(),
          ),
          if (cart.itemCount > 0) const CartSummaryBar(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (parkedSales.isNotEmpty)
            FloatingActionButton.small(
              heroTag: 'viewParked',
              backgroundColor: DesignColors.warning,
              onPressed: () => _showParkedSalesSheet(context),
              tooltip: 'Parked (${parkedSales.length})',
              child: Text('${parkedSales.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          if (parkedSales.isNotEmpty) const SizedBox(height: 8),
          if (cart.items.isNotEmpty)
            FloatingActionButton.small(
              heroTag: 'parkSale',
              backgroundColor: const Color(0xFF64748B),
              onPressed: () => _parkCurrentSale(context),
              tooltip: 'Park Sale',
              child: const Icon(Icons.pause_rounded, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _topAction(
      IconData icon, String tooltip, VoidCallback onTap, bool isDark,
      {bool active = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: active
                ? DesignColors.error.withValues(alpha: 0.1)
                : DesignColors.brand.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              color: active ? DesignColors.error : DesignColors.textSecondary,
              size: 20),
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

    GlassBottomSheet.show(context,
        scrollable: true,
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.of(ctx).padding.bottom,
            ),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text('Customer',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Set or search for a customer',
                      style: TextStyle(
                          fontSize: 13, color: DesignColors.textSecondary)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                        labelText: 'Name',
                        prefixIcon:
                            const Icon(Icons.person_outline_rounded, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        filled: true),
                    onChanged: (_) => setSheet(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                        labelText: 'Phone',
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
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
                                  child: Text(
                                      (customers[i]['name'] as String)[0]
                                          .toUpperCase())),
                              title: Text(customers[i]['name'] as String),
                              subtitle: Text(
                                  '${customers[i]['totalPurchases']} purchases'),
                              onTap: () {
                                ref.read(cartProvider.notifier).setCustomer(
                                    customers[i]['id'] as String,
                                    customerName:
                                        customers[i]['name'] as String);
                                Navigator.pop(ctx);
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 14),
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
                    const SizedBox(width: 10),
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
                                    ref.read(cartProvider.notifier).setCustomer(
                                        id,
                                        customerName: nameCtrl.text.trim());
                                    if (context.mounted) Navigator.pop(context);
                                  },
                            height: 44,
                            borderRadius: 12)),
                  ]),
                ]),
          ),
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
              20, 8, 20, 16 + MediaQuery.of(ctx).padding.bottom),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: DesignColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.pause_circle_filled_rounded,
                          color: DesignColors.warning, size: 22)),
                  const SizedBox(width: 10),
                  Text('Parked (${parked.length})',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? DesignColors.darkTextPrimary
                              : DesignColors.textPrimary)),
                ]),
                if (parked.isEmpty)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                          child: Text('No parked sales',
                              style:
                                  TextStyle(color: DesignColors.textTertiary))))
                else
                  ...parked.map((s) {
                    final elapsed = DateTime.now().difference(s.parkedAt);
                    return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ListCard(
                          leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                  color: DesignColors.warning
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10)),
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
                                    color: DesignColors.teal),
                                onPressed: () {
                                  final current = ref.read(cartProvider);
                                  if (current.items.isNotEmpty)
                                    ref
                                        .read(parkedSalesProvider.notifier)
                                        .park(current);
                                  final resumed = ref
                                      .read(parkedSalesProvider.notifier)
                                      .resume(s.id);
                                  if (resumed != null)
                                    ref
                                        .read(cartProvider.notifier)
                                        .restoreFrom(resumed);
                                  Navigator.pop(ctx);
                                }),
                            IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: DesignColors.error),
                                onPressed: () => ref
                                    .read(parkedSalesProvider.notifier)
                                    .remove(s.id)),
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
