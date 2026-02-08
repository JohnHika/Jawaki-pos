import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/catalog_provider.dart';
import '../providers/cart_provider.dart';

class ProductGrid extends ConsumerWidget {
  const ProductGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryId = ref.watch(selectedCategoryProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final productsAsync = ref.watch(filteredProductsProvider(
      FilterParams(
          categoryId: categoryId,
          searchQuery: searchQuery.isEmpty ? null : searchQuery),
    ));

    return productsAsync.when(
      data: (products) {
        if (products.isEmpty) return const _EmptyState();
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.78,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) =>
              _ProductCard(product: products[index]),
        );
      },
      loading: () => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.78,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => const _ProductCardSkeleton(),
      ),
      error: (error, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            const Text('Failed to load products'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => ref.refresh(productsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: theme.disabledColor),
          const SizedBox(height: 16),
          Text('No products found',
              style: theme.textTheme.titleMedium?.copyWith(color: theme.disabledColor)),
          const SizedBox(height: 8),
          Text('Try adjusting your search or category filter',
              style: TextStyle(color: theme.disabledColor)),
        ],
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final Map<String, dynamic> product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cartState = ref.watch(cartProvider);
    final productId = product['id'] as String;
    final productName = product['name'] as String;
    final price = (product['price'] as num).toDouble();
    final imageUrl = product['imageUrl'] as String?;
    final quantityInCart = cartState.items
        .where((item) => item.productId == productId)
        .fold<int>(0, (sum, item) => sum + item.quantity);

    return Card(
      elevation: quantityInCart > 0 ? 4 : 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: quantityInCart > 0
            ? const BorderSide(color: AppColors.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _addToCart(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl != null)
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _ImagePlaceholder(),
                      errorWidget: (_, __, ___) => _ImagePlaceholder(),
                    )
                  else
                    _ImagePlaceholder(),

                  // Quantity Badge
                  if (quantityInCart > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          'x$quantityInCart',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  // Quick-add button
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Material(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                      elevation: 3,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          // Quick add 1
                          final sku = product['sku'] as String? ?? '';
                          if (quantityInCart > 0) {
                            ref.read(cartProvider.notifier).updateQuantity(
                                productId, quantityInCart + 1);
                          } else {
                            ref.read(cartProvider.notifier).addItem(
                                  productId: productId,
                                  productName: productName,
                                  sku: sku,
                                  unitPrice: price,
                                  quantity: 1,
                                );
                          }
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('+1 $productName'),
                              duration: const Duration(milliseconds: 800),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.add, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Product Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      productName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      'KES ${price.toStringAsFixed(0)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addToCart(BuildContext context, WidgetRef ref) {
    final productId = product['id'] as String;
    final productName = product['name'] as String;
    final sku = product['sku'] as String? ?? '';
    final price = (product['price'] as num).toDouble();
    final unit = product['unit'] as String? ?? 'piece';

    final cartState = ref.read(cartProvider);
    final existing = cartState.items.where((i) => i.productId == productId);
    final currentQty = existing.isEmpty ? 0 : existing.first.quantity;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _QuantitySheet(
        productName: productName,
        price: price,
        unit: unit,
        currentQuantity: currentQty,
        onConfirm: (qty) {
          if (currentQty > 0) {
            ref.read(cartProvider.notifier).updateQuantity(productId, qty);
          } else {
            ref.read(cartProvider.notifier).addItem(
                  productId: productId,
                  productName: productName,
                  sku: sku,
                  unitPrice: price,
                  quantity: qty,
                );
          }
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$qty x $productName added to cart'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
      child: Center(
        child: Icon(
          Icons.image,
          size: 40,
          color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
//  Quantity Bottom Sheet (replaces AlertDialog – no overflow)
// ════════════════════════════════════════════

class _QuantitySheet extends StatefulWidget {
  final String productName;
  final double price;
  final String unit;
  final int currentQuantity;
  final void Function(int quantity) onConfirm;

  const _QuantitySheet({
    required this.productName,
    required this.price,
    required this.unit,
    required this.currentQuantity,
    required this.onConfirm,
  });

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  late int _quantity;
  late final TextEditingController _qtyController;
  bool _isCarton = false;

  // Common packaging sizes
  static const _quickPicks = [1, 6, 12, 24, 48];
  static const _bulkPicks = [
    {'label': 'Half Crate', 'qty': 12},
    {'label': 'Crate', 'qty': 24},
    {'label': 'Carton', 'qty': 48},
    {'label': '2 Cartons', 'qty': 96},
    {'label': '5 Cartons', 'qty': 240},
  ];

  @override
  void initState() {
    super.initState();
    _quantity = widget.currentQuantity > 0 ? widget.currentQuantity : 1;
    _qtyController = TextEditingController(text: '$_quantity');
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  void _updateQty(int newQty) {
    if (newQty < 1) newQty = 1;
    if (newQty > 99999) newQty = 99999;
    setState(() {
      _quantity = newQty;
      _qtyController.text = '$_quantity';
      _qtyController.selection = TextSelection.fromPosition(
        TextPosition(offset: _qtyController.text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.price * _quantity;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Product name + price
                Text(
                  widget.productName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'KES ${widget.price.toStringAsFixed(0)} per ${widget.unit}',
                  style: TextStyle(
                    color: theme.disabledColor,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 20),

                // +/- Quantity controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _circleButton(
                      icon: Icons.remove,
                      onTap: _quantity > 1
                          ? () => _updateQty(_quantity - 1)
                          : null,
                      color: isDark
                          ? AppColors.darkSurfaceVariant
                          : AppColors.surfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _qtyController,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (val) {
                          final n = int.tryParse(val);
                          if (n != null && n > 0 && n <= 99999) {
                            setState(() => _quantity = n);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    _circleButton(
                      icon: Icons.add,
                      onTap: () => _updateQty(_quantity + 1),
                      color: AppColors.primary,
                      iconColor: Colors.white,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Tabs: Pieces | Bulk
                Row(
                  children: [
                    Expanded(
                      child: _tabButton(
                        label: 'Quick Pick',
                        selected: !_isCarton,
                        onTap: () => setState(() => _isCarton = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _tabButton(
                        label: 'Bulk / Carton',
                        selected: _isCarton,
                        onTap: () => setState(() => _isCarton = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Quick picks or Bulk picks
                if (!_isCarton)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _quickPicks.map((n) {
                      final selected = _quantity == n;
                      return ChoiceChip(
                        label: Text('$n'),
                        selected: selected,
                        onSelected: (_) => _updateQty(n),
                        selectedColor: AppColors.primary.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: selected ? AppColors.primary : null,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _bulkPicks.map((pick) {
                      final qty = pick['qty'] as int;
                      final label = pick['label'] as String;
                      final selected = _quantity == qty;
                      return ChoiceChip(
                        label: Text('$label ($qty)'),
                        selected: selected,
                        onSelected: (_) => _updateQty(qty),
                        selectedColor: AppColors.secondary.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: selected ? AppColors.secondary : null,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 16),

                // Total bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.08),
                        AppColors.primary.withOpacity(0.04),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(
                                fontSize: 13, color: theme.disabledColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'KES ${total.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '$_quantity ${widget.unit}${_quantity != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.disabledColor,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onConfirm(_quantity);
                        },
                        icon: const Icon(Icons.shopping_cart_checkout, size: 18),
                        label: Text(widget.currentQuantity > 0
                            ? 'Update Cart'
                            : 'Add to Cart'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    VoidCallback? onTap,
    required Color color,
    Color? iconColor,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: iconColor ?? Theme.of(context).iconTheme.color),
        ),
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? AppColors.primary : null,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCardSkeleton extends StatelessWidget {
  const _ProductCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmer =
        isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: Container(color: shimmer)),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: double.infinity, color: shimmer),
                  const SizedBox(height: 4),
                  Container(height: 14, width: 60, color: shimmer),
                  const Spacer(),
                  Container(height: 18, width: 80, color: shimmer),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
