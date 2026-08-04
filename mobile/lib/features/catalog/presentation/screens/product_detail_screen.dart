import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/stock_quantity_display.dart';
import '../widgets/add_edit_product_sheet.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  Product? _product;
  List<ProductPricingTier> _pricingTiers = [];
  LocalStockData? _stock;
  StreamSubscription<LocalStockData?>? _stockSubscription;
  String _categoryName = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _stockSubscription = getIt<AppDatabase>()
        .watchStockForProduct(widget.productId)
        .listen((stock) {
      if (mounted) setState(() => _stock = stock);
    });
    _loadProduct();
  }

  @override
  void dispose() {
    _stockSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    try {
      final db = getIt<AppDatabase>();
      final product = await db.getProduct(widget.productId);
      if (product != null) {
        final categories = await db.getAllCategories();
        final categoryMap = {for (var c in categories) c.id: c.name};
        final tiers = await db.getPricingTiersForProduct(widget.productId);
        if (mounted) {
          setState(() {
            _product = product;
            _pricingTiers = tiers;
            _categoryName = categoryMap[product.categoryId] ?? 'Unknown';
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

  Future<void> _editProduct() async {
    final product = _product;
    if (product == null) return;

    await GlassBottomSheet.show(
      context,
      title: 'Edit Product',
      initialSize: 0.85,
      maxSize: 0.95,
      scrollable: true,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: AddEditProductSheet(product: product),
      ),
    );
    // The sheet syncs the catalog cache and pops itself on success; reload
    // this screen's copy so any changes show immediately.
    if (mounted) _loadProduct();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Product Details',
        showLogo: false,
        actions: [
          if (_product != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Edit product',
              onPressed: _editProduct,
            ),
        ],
      ),
      body: PageContainer(
        withScroll: true,
        child: _isLoading
            ? _buildLoading()
            : _product == null
                ? const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Product not found',
                    subtitle: 'The product you are looking for does not exist.',
                  )
                : _buildContent(context),
      ),
    );
  }

  Widget _buildLoading() {
    return const Column(
      children: [
        SizedBox(height: 60),
        Center(
          child: CircularProgressIndicator(color: DesignColors.brand),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final product = _product!;
    final stockPresentation = buildStockQuantityPresentation(
      baseQuantity: _stock?.quantity ?? 0,
      baseUnit: product.unit,
      preferredUnit: _stock?.displayUnit,
      unitsPerPreferredUnit: _stock?.displayQuantityPerUnit,
      lastReceivedQuantity: _stock?.lastReceivedQuantity,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // Hero Image Section
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: border),
          ),
          child: Column(
            children: [
              // Product Image Area
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignColors.darkSurface
                      : DesignColors.surfaceMuted,
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: Center(
                  child:
                      product.imageUrl != null && product.imageUrl!.isNotEmpty
                          ? Image.network(
                              product.imageUrl!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: 200,
                              errorBuilder: (_, __, ___) =>
                                  _buildProductPlaceholder(tertiaryColor),
                            )
                          : _buildProductPlaceholder(tertiaryColor),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: DesignColors.accent
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _categoryName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: DesignColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'SKU: ${product.sku}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tertiaryColor,
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
                          style: DesignType.numeric(
                            fontSize: 22,
                            color: titleColor,
                          ),
                        ),
                        if (product.costPrice != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Cost: KES ${product.costPrice!.toStringAsFixed(0)}',
                            style: DesignType.numeric(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: tertiaryColor,
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
                  value: stockPresentation.primary,
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
                  color: DesignColors.info,
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
        const SectionHeader(
          title: 'Description',
          icon: Icons.description_outlined,
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration:
              BoxDecoration(color: surface, border: Border.all(color: border)),
          child: Text(
            product.description?.isNotEmpty == true
                ? product.description!
                : 'No description provided for this product.',
            style: TextStyle(
              fontSize: 14,
              color: product.description?.isNotEmpty == true
                  ? titleColor
                  : tertiaryColor,
              height: 1.5,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Additional Details
        const SectionHeader(
          title: 'Additional Details',
          icon: Icons.info_outline_rounded,
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration:
              BoxDecoration(color: surface, border: Border.all(color: border)),
          child: Column(
            children: [
              _detailRow(Icons.qr_code_rounded, 'SKU', product.sku,
                  secondaryColor, titleColor),
              _divider(border),
              _detailRow(Icons.category_outlined, 'Category', _categoryName,
                  secondaryColor, titleColor),
              _divider(border),
              _detailRow(Icons.straighten_rounded, 'Unit', product.unit,
                  secondaryColor, titleColor),
              _divider(border),
              _detailRow(
                Icons.inventory_2_rounded,
                'Current Stock',
                stockPresentation.secondary == null
                    ? stockPresentation.primary
                    : '${stockPresentation.primary} (${stockPresentation.secondary})',
                secondaryColor,
                titleColor,
              ),
              if (stockPresentation.lastReceived != null) ...[
                _divider(border),
                _detailRow(
                  Icons.move_to_inbox_rounded,
                  'Last Received',
                  stockPresentation.lastReceived!
                      .replaceFirst('Last received: ', ''),
                  secondaryColor,
                  titleColor,
                  valueColor: DesignColors.success,
                ),
              ],
              for (final tier in _pricingTiers) ...[
                _divider(border),
                _detailRow(
                  Icons.inventory_2_outlined,
                  '${tier.unit[0].toUpperCase()}${tier.unit.substring(1)} Pricing',
                  '${tier.unit} (${tier.quantityPerUnit} ${product.unit}) — '
                      'KES ${tier.price.toStringAsFixed(0)}',
                  secondaryColor,
                  titleColor,
                ),
              ],
              _divider(border),
              _detailRow(
                Icons.attach_money_rounded,
                'Selling Price',
                'KES ${product.price.toStringAsFixed(2)}',
                secondaryColor,
                titleColor,
                valueColor: DesignColors.brand,
              ),
              if (product.costPrice != null) ...[
                _divider(border),
                _detailRow(
                  Icons.price_change_outlined,
                  'Cost Price',
                  'KES ${product.costPrice!.toStringAsFixed(2)}',
                  secondaryColor,
                  titleColor,
                  valueColor: DesignColors.info,
                ),
              ],
              _divider(border),
              _detailRow(
                Icons.track_changes_rounded,
                'Track Inventory',
                product.trackInventory ? 'Enabled' : 'Disabled',
                secondaryColor,
                titleColor,
              ),
              _divider(border),
              _detailRow(
                Icons.toggle_on_outlined,
                'Status',
                product.isActive ? 'Active' : 'Inactive',
                secondaryColor,
                titleColor,
                valueColor: product.isActive
                    ? DesignColors.success
                    : DesignColors.error,
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildProductPlaceholder(Color tertiaryColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: DesignColors.brand.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.inventory_2_rounded,
            size: 56,
            color: tertiaryColor,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _product?.name ?? 'Product',
          style: TextStyle(
            color: tertiaryColor,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value,
    Color secondaryColor,
    Color titleColor, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: secondaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: secondaryColor),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? titleColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(Color border) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(height: 1, color: border),
    );
  }
}
