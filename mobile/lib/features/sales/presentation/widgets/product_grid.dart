import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/pricing_service.dart';
import '../../../../core/theme/design_system.dart';
import '../providers/catalog_provider.dart';
import '../providers/cart_provider.dart';

class ProductGrid extends ConsumerWidget {
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

    return 'Unable to load products. Please try again.';
  }

  const ProductGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryId = ref.watch(selectedCategoryProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final productsAsync = ref.watch(
      filteredProductsProvider(
        FilterParams(
          categoryId: categoryId,
          searchQuery: searchQuery.isEmpty ? null : searchQuery,
        ),
      ),
    );

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
        itemBuilder: (context, index) => const ProductCardShimmer(),
      ),
      error: (error, _) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Failed to load products',
        subtitle: _getUserFriendlyErrorMessage(error),
        actionLabel: 'Retry',
        iconColor: DesignColors.error,
        onAction: () => ref.refresh(productsProvider),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'No products found',
      subtitle: 'Try adjusting your search or category filter',
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final Map<String, dynamic> product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cartState = ref.watch(cartProvider);
    final productId = product['id'] as String;
    final productName = product['name'] as String;
    final price = (product['price'] as num).toDouble();
    final imageUrl = product['imageUrl'] as String?;
    final unit = product['unit'] as String? ?? 'piece';
    final stock = (product['stock'] as num?)?.toInt() ?? 0;
    final trackInventory = product['trackInventory'] as bool? ?? true;
    final isOutOfStock = trackInventory && stock <= 0;
    final quantityInCart = cartState.items
        .where((item) => item.productId == productId)
        .fold<int>(0, (sum, item) => sum + item.quantity);

    return GlassCard(
      onTap: () => _addToCart(context, ref),
      padding: EdgeInsets.zero,
      borderRadius: 16,
      blur: quantityInCart > 0 ? 12 : 6,
      tint: isDark
          ? DesignColors.glassDark
          : (quantityInCart > 0
              ? DesignColors.accent.withValues(alpha: 0.04)
              : DesignColors.glassWhite),
      borderColor: quantityInCart > 0
          ? DesignColors.accent.withValues(alpha: 0.3)
          : (isDark ? DesignColors.glassDarkBorder : DesignColors.glassBorder),
      boxShadow: quantityInCart > 0
          ? [
              BoxShadow(
                color: DesignColors.accent.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _ImagePlaceholder(),
                          errorWidget: (_, __, ___) => _ImagePlaceholder(),
                        )
                      : _ImagePlaceholder(),
                ),

                // Quantity Badge
                if (isOutOfStock)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.42),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'OUT OF STOCK',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Quantity Badge
                if (quantityInCart > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: TweenAnimationBuilder<int>(
                      duration: DesignAnimation.fast,
                      tween: IntTween(begin: 0, end: quantityInCart),
                      builder: (context, value, child) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: DesignColors.accent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: DesignColors.accent.withValues(
                                  alpha: 0.4,
                                ),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            'x$value',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
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
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? DesignColors.darkTextPrimary
                          : DesignColors.textPrimary,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Text(
                        'KES ${price.toStringAsFixed(0)}',
                        style: DesignType.numeric(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: DesignColors.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    trackInventory
                        ? '$stock $unit in stock'
                        : 'Stock not tracked',
                    style: TextStyle(
                      fontSize: 10,
                      color: isOutOfStock
                          ? DesignColors.error
                          : (isDark
                              ? DesignColors.darkTextTertiary
                              : DesignColors.textTertiary),
                      fontWeight:
                          isOutOfStock ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addToCart(BuildContext context, WidgetRef ref) {
    final productId = product['id'] as String;
    final productName = product['name'] as String;
    final sku = product['sku'] as String? ?? '';
    final price = (product['price'] as num).toDouble();
    final imageUrl = product['imageUrl'] as String?;
    final unit = product['unit'] as String? ?? 'piece';
    final stock = (product['stock'] as num?)?.toInt() ?? 0;
    final trackInventory = product['trackInventory'] as bool? ?? true;
    final tiers = PricingService.getAllPricingTiers(product);

    if (trackInventory && stock <= 0) {
      _showStockBlocked(context, productName, stock);
      return;
    }

    final cartState = ref.read(cartProvider);
    final existing = cartState.items.where((i) => i.productId == productId);
    final currentQty = existing.isEmpty ? 0 : existing.first.quantity;

    GlassBottomSheet.show(
      context,
      scrollable: true,
      initialSize: tiers.length > 1 ? 0.58 : 0.48,
      child: _QuantitySheet(
        productName: productName,
        imageUrl: imageUrl,
        basePrice: price,
        baseUnit: unit,
        pricingTiers: tiers,
        availableStock: trackInventory ? stock : null,
        currentQuantity: currentQty,
        onConfirm: (qty, tier, overridePrice) async {
          final conversion = tier.quantityPerUnit ?? 1;
          final baseQty = (qty * conversion).round();
          final unitPrice = (overridePrice ?? tier.price) / conversion;
          final result = currentQty > 0
              ? await ref
                  .read(cartProvider.notifier)
                  .updateQuantity(productId, baseQty)
              : await ref.read(cartProvider.notifier).addItem(
                    productId: productId,
                    productName: productName,
                    sku: sku,
                    unitPrice: unitPrice,
                    quantity: baseQty,
                    notes: tier.unitTypeLabel,
                    saleUnit: tier.unit,
                    saleQuantity: qty.toDouble(),
                    unitConversionFactor: conversion,
                  );

          if (!context.mounted) return;
          if (!result.success) {
            _showStockBlocked(context, productName, result.currentStock);
            return;
          }
          ScaffoldMessenger.of(context).clearSnackBars();
          showGlassSnackBar(
            context,
            '$qty ${tier.unit} $productName added to cart',
            icon: Icons.add_shopping_cart_rounded,
            color: DesignColors.success,
          );
        },
      ),
    );
  }

  void _showStockBlocked(
    BuildContext context,
    String productName,
    int currentStock,
  ) {
    ScaffoldMessenger.of(context).clearSnackBars();
    showGlassSnackBar(
      context,
      '$productName is out of stock. Receive inventory before selling.',
      icon: Icons.inventory_2_outlined,
      color: DesignColors.error,
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark
          ? DesignColors.darkSurfaceElevated
          : DesignColors.surfaceSubtle,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 40,
          color: isDark
              ? DesignColors.darkTextTertiary
              : DesignColors.textTertiary,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
//  Quantity Bottom Sheet (Premium)
// ════════════════════════════════════════════

class _QuantitySheet extends StatefulWidget {
  final String productName;
  final String? imageUrl;
  final double basePrice;
  final String baseUnit;
  final List<UnitPriceInfo> pricingTiers;
  final int? availableStock;
  final int currentQuantity;
  // overridePrice is null unless the cashier explicitly used the price
  // override control — always the price for one of [tier]'s unit, same
  // basis as UnitPriceInfo.price, never the product's stored catalog price.
  final Future<void> Function(
    int quantity,
    UnitPriceInfo tier,
    double? overridePrice,
  ) onConfirm;

  const _QuantitySheet({
    required this.productName,
    this.imageUrl,
    required this.basePrice,
    required this.baseUnit,
    required this.pricingTiers,
    required this.availableStock,
    required this.currentQuantity,
    required this.onConfirm,
  });

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  late int _quantity;
  late final TextEditingController _qtyController;
  late UnitPriceInfo _selectedTier;
  late final TextEditingController _priceController;
  late final FocusNode _priceFocusNode;
  double? _overridePrice;
  bool _editingPrice = false;

  @override
  void initState() {
    super.initState();
    _selectedTier = widget.pricingTiers.isNotEmpty
        ? widget.pricingTiers.first
        : UnitPriceInfo(
            unit: widget.baseUnit,
            price: widget.basePrice,
            unitTypeLabel: widget.baseUnit,
          );
    _quantity = 1;
    _qtyController = TextEditingController(text: '$_quantity');
    _priceController = TextEditingController(
      text: _selectedTier.price.toStringAsFixed(0),
    );
    _priceFocusNode = FocusNode();
    _priceFocusNode.addListener(() {
      if (!_priceFocusNode.hasFocus && _editingPrice && mounted) {
        _finishPriceEditing();
      }
    });
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    _priceFocusNode.dispose();
    super.dispose();
  }

  /// Effective per-unit price for the selected tier: the cashier's
  /// override for this sale only, or the tier's real catalog price.
  double get _effectivePrice => _overridePrice ?? _selectedTier.price;

  String _priceInputValue(double price) {
    return price.truncateToDouble() == price
        ? price.toStringAsFixed(0)
        : price.toStringAsFixed(2);
  }

  void _beginPriceEditing() {
    final value = _priceInputValue(_effectivePrice);
    setState(() {
      _editingPrice = true;
      _priceController.value = TextEditingValue(
        text: value,
        selection: TextSelection(baseOffset: 0, extentOffset: value.length),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _priceFocusNode.requestFocus();
    });
  }

  void _finishPriceEditing() {
    final enteredPrice = double.tryParse(_priceController.text);
    final validPrice = enteredPrice != null && enteredPrice > 0;
    final nextPrice = validPrice ? enteredPrice : _effectivePrice;

    if (!mounted) return;
    setState(() {
      _overridePrice = nextPrice == _selectedTier.price ? null : nextPrice;
      _priceController.text = _priceInputValue(nextPrice);
      _editingPrice = false;
    });
    _priceFocusNode.unfocus();
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
    final total = _effectivePrice * _quantity;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final conversion = _selectedTier.quantityPerUnit ?? 1;
    final baseUnits = (_quantity * conversion).round();
    final availableStock = widget.availableStock;
    final exceedsStock = availableStock != null && baseUnits > availableStock;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),

            // Product image + name + price
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DesignColors.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: DesignColors.accent.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: widget.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: widget.imageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _ImagePlaceholder(),
                              errorWidget: (_, __, ___) => _ImagePlaceholder(),
                            )
                          : _ImagePlaceholder(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.productName,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? DesignColors.darkTextPrimary
                                : DesignColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'KES ${_selectedTier.price.toStringAsFixed(0)} per ${_selectedTier.unit}',
                          style: TextStyle(
                            color: isDark
                                ? DesignColors.darkTextSecondary
                                : DesignColors.textSecondary,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (widget.availableStock != null) ...[
              const SizedBox(height: 12),
              _StockBreakdown(
                availableStock: widget.availableStock!,
                pricingTiers: widget.pricingTiers,
                baseUnit: widget.baseUnit,
              ),
            ],

            const SizedBox(height: 18),

            if (widget.pricingTiers.length > 1) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sell as',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? DesignColors.darkTextSecondary
                        : DesignColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.pricingTiers.map((tier) {
                  final selected = tier.unit == _selectedTier.unit;
                  final tierConversion = tier.quantityPerUnit ?? 1;
                  return ChoiceChip(
                    label: Text(
                      tierConversion > 1
                          ? '${tier.unit} (${tierConversion.toStringAsFixed(tierConversion.truncateToDouble() == tierConversion ? 0 : 1)} ${widget.baseUnit})'
                          : tier.unit,
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      _selectedTier = tier;
                      _overridePrice = null;
                      _priceController.text = _priceInputValue(tier.price);
                      _quantity = 1;
                      _qtyController.text = '1';
                    }),
                    selectedColor: DesignColors.accent.withValues(alpha: 0.15),
                    backgroundColor: isDark
                        ? DesignColors.darkSurfaceElevated
                        : DesignColors.surfaceMuted,
                    labelStyle: TextStyle(
                      color: selected ? DesignColors.accent : null,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],

            // Quantity: stepper + numeric field
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Material(
                  color: _quantity > 1
                      ? DesignColors.accent.withValues(alpha: 0.1)
                      : (isDark
                          ? DesignColors.darkSurfaceElevated
                          : DesignColors.surfaceSubtle),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap:
                        _quantity > 1 ? () => _updateQty(_quantity - 1) : null,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.remove_rounded,
                        color: _quantity > 1
                            ? DesignColors.accent
                            : (isDark
                                ? DesignColors.darkTextTertiary
                                : DesignColors.textTertiary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _qtyController,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? DesignColors.darkTextPrimary
                          : DesignColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? DesignColors.darkBorder
                              : DesignColors.surfaceBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? DesignColors.darkBorder
                              : DesignColors.surfaceBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: DesignColors.accent,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? DesignColors.darkSurface
                          : DesignColors.surfaceMuted,
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
                Material(
                  color: DesignColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _updateQty(_quantity + 1),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: DesignColors.accent,
                      ),
                      child: const Icon(Icons.add_rounded, color: Colors.black),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (availableStock != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(
                      exceedsStock
                          ? Icons.warning_amber_rounded
                          : Icons.inventory_2_outlined,
                      size: 16,
                      color: exceedsStock
                          ? DesignColors.error
                          : (isDark
                              ? DesignColors.darkTextSecondary
                              : DesignColors.textSecondary),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        exceedsStock
                            ? 'Only $availableStock ${widget.baseUnit} available'
                            : '${availableStock - baseUnits} ${widget.baseUnit} left after this sale',
                        style: TextStyle(
                          fontSize: 12,
                          color: exceedsStock
                              ? DesignColors.error
                              : (isDark
                                  ? DesignColors.darkTextSecondary
                                  : DesignColors.textSecondary),
                          fontWeight:
                              exceedsStock ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Total bar — the per-unit price on the right is the one
            // editable control here; tapping it expands an inline field
            // in place, so a manual price change is made where the
            // cashier is already looking (the number that's about to be
            // charged), not up in the header where it competed with the
            // product name for attention.
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              borderRadius: 14,
              blur: 6,
              tint: DesignColors.accent.withValues(alpha: 0.06),
              borderColor: DesignColors.accent.withValues(alpha: 0.12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? DesignColors.darkTextSecondary
                              : DesignColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'KES ${total.toStringAsFixed(0)}',
                        style: DesignType.numeric(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: DesignColors.accent,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$_quantity ${_selectedTier.unit}${_quantity != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? DesignColors.darkTextSecondary
                              : DesignColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _editingPrice
                          ? Container(
                              constraints: const BoxConstraints(
                                minWidth: 138,
                                maxWidth: 164,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: DesignColors.accent.withValues(
                                  alpha: 0.09,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: DesignColors.accent.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                              child: TextField(
                                controller: _priceController,
                                focusNode: _priceFocusNode,
                                autofocus: true,
                                textAlign: TextAlign.right,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  TextInputFormatter.withFunction(
                                    (oldValue, newValue) => RegExp(
                                      r'^\d*(\.\d{0,2})?$',
                                    ).hasMatch(newValue.text)
                                        ? newValue
                                        : oldValue,
                                  ),
                                ],
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: DesignColors.accent,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  prefixText: '@ KES ',
                                  prefixStyle: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: DesignColors.accent,
                                  ),
                                  suffixIcon: Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: DesignColors.accent,
                                  ),
                                  suffixIconConstraints: BoxConstraints(
                                    minWidth: 22,
                                    minHeight: 22,
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                ),
                                onChanged: (val) {
                                  final n = double.tryParse(val);
                                  if (n == null || n <= 0) return;
                                  setState(() {
                                    _overridePrice =
                                        n == _selectedTier.price ? null : n;
                                  });
                                },
                                onSubmitted: (_) => _finishPriceEditing(),
                              ),
                            )
                          : InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: _beginPriceEditing,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '@ KES ${_effectivePrice.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: _overridePrice != null
                                            ? DesignColors.accent
                                            : (isDark
                                                ? DesignColors.darkTextTertiary
                                                : DesignColors.textTertiary),
                                        fontWeight: _overridePrice != null
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.edit_rounded,
                                      size: 14,
                                      color: isDark
                                          ? DesignColors.darkTextTertiary
                                          : DesignColors.textTertiary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ],
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
                      side: BorderSide(
                        color: isDark
                            ? DesignColors.darkBorder
                            : DesignColors.surfaceBorder,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GradientButton(
                    label: widget.currentQuantity > 0
                        ? 'Update Cart'
                        : 'Add to Cart',
                    icon: Icons.shopping_cart_checkout_rounded,
                    onPressed: exceedsStock
                        ? null
                        : () {
                            Navigator.pop(context);
                            widget.onConfirm(
                                _quantity, _selectedTier, _overridePrice);
                          },
                    height: 48,
                    borderRadius: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows exactly how much stock is left, decomposed into every one of the
/// product's configured tiers — e.g. "4 packs + 4 pieces left" for a
/// product with 52 base units in stock and a 12-per-pack tier — instead of
/// a single generic stock number disconnected from how the tiers were set
/// up. [pricingTiers] includes the base tier as its first entry (per
/// [PricingService.getAllPricingTiers]); everything after that is a real
/// bulk tier with a [UnitPriceInfo.quantityPerUnit].
class _StockBreakdown extends StatelessWidget {
  final int availableStock;
  final List<UnitPriceInfo> pricingTiers;
  final String baseUnit;

  const _StockBreakdown({
    required this.availableStock,
    required this.pricingTiers,
    required this.baseUnit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bulkTiers = pricingTiers
        .where((t) => t.quantityPerUnit != null && t.quantityPerUnit! > 0)
        .toList();

    final lines = <String>[];
    for (final tier in bulkTiers) {
      final perUnit = tier.quantityPerUnit!.round();
      final whole = availableStock ~/ perUnit;
      final remainder = availableStock % perUnit;
      final unitLabel = whole == 1 ? tier.unit : _pluralize(tier.unit);
      lines.add(
        remainder > 0
            ? '$whole $unitLabel + $remainder $baseUnit left over'
            : '$whole $unitLabel left',
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? DesignColors.darkSurfaceElevated
            : DesignColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 14,
                  color: isDark
                      ? DesignColors.darkTextTertiary
                      : DesignColors.textTertiary),
              const SizedBox(width: 6),
              Text(
                '$availableStock $baseUnit${availableStock == 1 ? '' : 's'} in stock',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? DesignColors.darkTextSecondary
                      : DesignColors.textSecondary,
                ),
              ),
            ],
          ),
          for (final line in lines) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                line,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? DesignColors.darkTextTertiary
                      : DesignColors.textTertiary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _pluralize(String unit) {
    final lower = unit.toLowerCase();
    if (lower.endsWith('x') ||
        lower.endsWith('ch') ||
        lower.endsWith('sh') ||
        lower.endsWith('s')) {
      return '${unit}es';
    }
    return '${unit}s';
  }
}
