import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  Product? _product;
  String _categoryName = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  Future<void> _loadProduct() async {
    try {
      final db = getIt<AppDatabase>();
      final product = await db.getProduct(widget.productId);
      if (product != null) {
        final categories = await db.getAllCategories();
        final categoryMap = {
          for (var c in categories) c.id: c.name
        };
        if (mounted) {
          setState(() {
            _product = product;
            _categoryName =
                categoryMap[product.categoryId] ?? 'Unknown';
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Product Details',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DesignColors.surfaceBorder.withValues(alpha:0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.edit_outlined,
                  color: DesignColors.textSecondary, size: 20),
            ),
            onPressed: () {
              // TODO: Navigate to edit
            },
          ),
        ],
      ),
      body: PageContainer(
        withScroll: true,
        child: _isLoading
            ? _buildLoading()
            : _product == null
                ? EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Product not found',
                    subtitle:
                        'The product you are looking for does not exist.',
                    iconColor: DesignColors.textTertiary,
                  )
                : _buildContent(),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      children: [
        const SizedBox(height: kToolbarHeight + 100),
        const Center(
          child: CircularProgressIndicator(
              color: DesignColors.brand),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final product = _product!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: kToolbarHeight + 16),

        // Hero Image Section
        GlassCard(
          padding: const EdgeInsets.all(0),
          borderRadius: 20,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          tint: DesignColors.brand.withValues(alpha:0.03),
          borderColor: DesignColors.surfaceBorder,
          child: Column(
            children: [
              // Product Image Area
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      DesignColors.brand.withValues(alpha:0.08),
                      DesignColors.brand.withValues(alpha:0.02),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20)),
                ),
                child: Center(
                  child: product.imageUrl != null &&
                          product.imageUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius:
                              const BorderRadius.vertical(
                                  top: Radius.circular(20)),
                          child: Image.network(
                            product.imageUrl!,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: 200,
                            errorBuilder: (_, __, ___) =>
                                _buildProductPlaceholder(),
                          ),
                        )
                      : _buildProductPlaceholder(),
                ),
              ),

              // Quick Info Bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: DesignColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3),
                                decoration: BoxDecoration(
                                  color: DesignColors.brand
                                      .withValues(alpha:0.1),
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _categoryName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: DesignColors.brand,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'SKU: ${product.sku}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color:
                                      DesignColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'KES ${product.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: DesignColors.brand,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (product.costPrice != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Cost: KES ${product.costPrice!.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: DesignColors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Stock & Status Section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'Current Stock',
                  value: '0',
                  icon: Icons.inventory_2_rounded,
                  color: DesignColors.brand,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  title: 'Unit',
                  value: product.unit,
                  icon: Icons.straighten_rounded,
                  color: DesignColors.teal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  title: 'Status',
                  value: product.isActive ? 'Active' : 'Inactive',
                  icon: product.isActive
                      ? Icons.check_circle_rounded
                      : Icons.cancel_outlined,
                  color: product.isActive
                      ? DesignColors.success
                      : DesignColors.textTertiary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Description Section
        SectionHeader(
          title: 'Description',
          icon: Icons.description_outlined,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            borderRadius: 14,
            tint: Colors.transparent,
            borderColor: DesignColors.surfaceBorder,
            child: Text(
              product.description?.isNotEmpty == true
                  ? product.description!
                  : 'No description provided for this product.',
              style: TextStyle(
                fontSize: 14,
                color: product.description?.isNotEmpty == true
                    ? DesignColors.textPrimary
                    : DesignColors.textTertiary,
                height: 1.5,
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Additional Details
        SectionHeader(
          title: 'Additional Details',
          icon: Icons.info_outline_rounded,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GlassCard(
            padding: const EdgeInsets.all(4),
            borderRadius: 14,
            tint: Colors.transparent,
            borderColor: DesignColors.surfaceBorder,
            child: Column(
              children: [
                _detailRow(
                  Icons.qr_code_rounded,
                  'SKU',
                  product.sku,
                ),
                _divider(),
                _detailRow(
                  Icons.category_outlined,
                  'Category',
                  _categoryName,
                ),
                _divider(),
                _detailRow(
                  Icons.straighten_rounded,
                  'Unit',
                  product.unit,
                ),
                if (product.secondaryUnit != null) ...[
                  _divider(),
                  _detailRow(
                    Icons.inventory_2_outlined,
                    'Secondary Unit',
                    '${product.secondaryUnit} (${product.secondaryUnitQty} per base)',
                  ),
                ],
                if (product.tertiaryUnit != null) ...[
                  _divider(),
                  _detailRow(
                    Icons.inventory_2_outlined,
                    'Tertiary Unit',
                    '${product.tertiaryUnit} (${product.tertiaryUnitQty} per base)',
                  ),
                ],
                _divider(),
                _detailRow(
                  Icons.attach_money_rounded,
                  'Selling Price',
                  'KES ${product.price.toStringAsFixed(2)}',
                  valueColor: DesignColors.brand,
                ),
                if (product.costPrice != null) ...[
                  _divider(),
                  _detailRow(
                    Icons.price_change_outlined,
                    'Cost Price',
                    'KES ${product.costPrice!.toStringAsFixed(2)}',
                    valueColor: DesignColors.teal,
                  ),
                ],
                _divider(),
                _detailRow(
                  Icons.track_changes_rounded,
                  'Track Inventory',
                  product.trackInventory ? 'Enabled' : 'Disabled',
                ),
                _divider(),
                _detailRow(
                  Icons.toggle_on_outlined,
                  'Status',
                  product.isActive ? 'Active' : 'Inactive',
                  valueColor: product.isActive
                      ? DesignColors.success
                      : DesignColors.error,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildProductPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: DesignColors.brand.withValues(alpha:0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.inventory_2_rounded,
            size: 56,
            color: DesignColors.textTertiary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _product?.name ?? 'Product',
          style: const TextStyle(
            color: DesignColors.textTertiary,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: DesignColors.surfaceBorder.withValues(alpha:0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Icon(icon, size: 16, color: DesignColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: DesignColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? DesignColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        height: 1,
        color: DesignColors.surfaceBorder.withValues(alpha:0.5),
      ),
    );
  }
}
