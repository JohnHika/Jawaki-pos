import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/design_system.dart';

/// Product Picker Dialog - Select a product from the catalog
class ProductPickerDialog extends ConsumerStatefulWidget {
  final String? initialProductId;

  const ProductPickerDialog({super.key, this.initialProductId});

  @override
  ConsumerState<ProductPickerDialog> createState() =>
      _ProductPickerDialogState();
}

class _ProductPickerDialogState extends ConsumerState<ProductPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;
  String? _selectedProductId;

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.initialProductId;
    _loadProducts();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);

    try {
      final db = getIt<AppDatabase>();
      final products = await db.getAllProducts();

      if (mounted) {
        setState(() {
          _products = products;
          _filteredProducts = products;
        });
      }
    } catch (e) {
      debugPrint('Error loading products: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading products: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products
            .where((p) =>
                p.name.toLowerCase().contains(query) ||
                p.sku.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final availableHeight = MediaQuery.sizeOf(context).height -
        viewInsets.bottom -
        safePadding.top -
        safePadding.bottom -
        24;

    final content = Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DesignColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: DesignColors.brand,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Select Product',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: DesignColors.surfaceBorder.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: isDark
                        ? DesignColors.darkTextSecondary
                        : DesignColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _searchController,
            autofocus: false,
            decoration: InputDecoration(
              hintText: 'Search by name or SKU...',
              hintStyle: TextStyle(color: DesignColors.textTertiary),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: DesignColors.textTertiary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: DesignColors.textTertiary),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: DesignColors.brand, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Results count
        if (!_isLoading && _filteredProducts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  '${_filteredProducts.length} product${_filteredProducts.length != 1 ? 's' : ''} found',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? DesignColors.darkTextSecondary
                        : DesignColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // Product List
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: DesignColors.brand,
                  ),
                )
              : _filteredProducts.isEmpty
                  ? EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: _searchController.text.isEmpty
                          ? 'No products available'
                          : 'No products found',
                      subtitle: _searchController.text.isNotEmpty
                          ? 'Try a different search term'
                          : null,
                      actionLabel: _searchController.text.isNotEmpty
                          ? 'Clear search'
                          : null,
                      onAction: _searchController.text.isNotEmpty
                          ? () => _searchController.clear()
                          : null,
                      iconColor: DesignColors.textTertiary,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        final isSelected = product.id == _selectedProductId;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            onTap: () {
                              setState(() => _selectedProductId = product.id);
                            },
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            borderRadius: 12,
                            blur: 8,
                            tint: isSelected
                                ? DesignColors.brand.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderColor: isSelected
                                ? DesignColors.brand.withValues(alpha: 0.3)
                                : DesignColors.surfaceBorder,
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: DesignColors.brand
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      product.name[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: DesignColors.brand,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          fontSize: 14,
                                          color: isDark
                                              ? DesignColors.darkTextPrimary
                                              : DesignColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            'SKU: ${product.sku}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? DesignColors
                                                      .darkTextSecondary
                                                  : DesignColors.textTertiary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: product.isActive
                                                  ? DesignColors.successSubtle
                                                  : DesignColors.surfaceBorder,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              product.isActive
                                                  ? 'Active'
                                                  : 'Inactive',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: product.isActive
                                                    ? DesignColors.success
                                                    : DesignColors.textTertiary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'KES ${product.price.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: DesignColors.brand,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: DesignColors.brand,
                                    size: 22,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),

        // Action Buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: DesignColors.surfaceBorder),
                    ),
                    side: const BorderSide(color: DesignColors.surfaceBorder),
                    foregroundColor: DesignColors.textSecondary,
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(
                  label: 'Select',
                  onPressed: _selectedProductId == null
                      ? null
                      : () {
                          final selectedProduct = _products.firstWhere(
                            (p) => p.id == _selectedProductId,
                          );
                          Navigator.pop(context, {
                            'id': selectedProduct.id,
                            'name': selectedProduct.name,
                            'sku': selectedProduct.sku,
                            'unit': selectedProduct.unit,
                          });
                        },
                  height: 48,
                  borderRadius: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Dialog(
      insetPadding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: availableHeight.clamp(280.0, 720.0),
          ),
          child: SizedBox(
            width: double.infinity,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Helper function to show the product picker
Future<Map<String, dynamic>?> showProductPicker(
  BuildContext context, {
  String? initialProductId,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => ProductPickerDialog(
      initialProductId: initialProductId,
    ),
  );
}
