import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../sales/presentation/providers/catalog_provider.dart'
    as catalog_cache;
import '../providers/catalog_categories_provider.dart';
import 'image_picker_section.dart';

class _UnitPriceTier {
  String unit;
  TextEditingController priceController;
  // How many of the primary (base) unit make up one of this tier's unit —
  // e.g. 12 for "12 pieces per pack". Entered directly by the admin, not
  // derived from price, since bulk pricing is rarely perfectly linear.
  TextEditingController qtyController;
  _UnitPriceTier({required this.unit, String? price, String? qty})
      : priceController = TextEditingController(text: price ?? ''),
        qtyController = TextEditingController(text: qty ?? '');
}

/// Add/edit product form, shown as a bottom sheet from both the products
/// list and the product detail screen.
class AddEditProductSheet extends ConsumerStatefulWidget {
  final Product? product;
  const AddEditProductSheet({super.key, this.product});
  @override
  ConsumerState<AddEditProductSheet> createState() =>
      _AddEditProductSheetState();
}

class _AddEditProductSheetState extends ConsumerState<AddEditProductSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _minStockController;
  String? _selectedCategoryId;
  String? _imageUrl;
  String? _imagePublicId;
  late List<_UnitPriceTier> _unitPriceTiers;
  late String _minStockUnit;
  bool _isSaving = false;

  final _units = [
    'piece',
    'pack',
    'box',
    'bottle',
    'tube',
    'bar',
    'roll',
    'jar',
    'half dozen',
    'dozen',
    'kg',
    'g',
    'litre',
    'ml'
  ];

  bool get isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.product?.description ?? '');
    _selectedCategoryId = widget.product?.categoryId;
    _imageUrl = widget.product?.imageUrl;

    // Start with just the primary tier; any existing bulk tiers (any
    // number) load a moment later from the local cache, once fetched.
    _unitPriceTiers = [
      _UnitPriceTier(
        unit: widget.product?.unit ?? 'piece',
        price: widget.product?.price.toStringAsFixed(0),
      ),
    ];

    // Reorder point: stored in base units, displayed/edited in whichever
    // tier unit is selected — defaults to the primary tier until real
    // tiers load, then re-picks the first bulk tier once available.
    _minStockUnit = _unitPriceTiers[0].unit;
    final minStockBase = widget.product?.minStock ?? 0;
    _minStockController = TextEditingController(
      text: minStockBase == 0 ? '' : minStockBase.toString(),
    );

    if (isEditing) {
      _loadExistingPricingTiers();
    }
  }

  Future<void> _loadExistingPricingTiers() async {
    final database = getIt<AppDatabase>();
    final tiers = await database.getPricingTiersForProduct(widget.product!.id);
    if (!mounted || tiers.isEmpty) return;

    setState(() {
      for (final tier in tiers) {
        _unitPriceTiers.add(_UnitPriceTier(
          unit: tier.unit,
          price: tier.price.toStringAsFixed(0),
          qty: _formatQty(tier.quantityPerUnit),
        ));
      }
      _minStockUnit = _unitPriceTiers.length > 1
          ? _unitPriceTiers[1].unit
          : _unitPriceTiers[0].unit;
      final minStockBase = widget.product?.minStock ?? 0;
      final minStockDisplay =
          _convertFromBaseUnits(minStockBase.toDouble(), _minStockUnit);
      _minStockController.text =
          minStockBase == 0 ? '' : _formatQty(minStockDisplay);
    });
  }

  /// Converts a base-unit quantity into the given tier unit using the real,
  /// admin-entered conversion count for that tier (how many base units per
  /// one of the tier's unit).
  double _convertFromBaseUnits(double baseQty, String unit) {
    final tier = _unitPriceTiers.firstWhere(
      (t) => t.unit == unit,
      orElse: () => _unitPriceTiers[0],
    );
    if (tier == _unitPriceTiers[0]) return baseQty;
    final factor = double.tryParse(tier.qtyController.text.trim());
    if (factor == null || factor == 0) return baseQty;
    return baseQty / factor;
  }

  String _formatQty(double qty) {
    return qty % 1 == 0 ? qty.toStringAsFixed(0) : qty.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _minStockController.dispose();
    for (final tier in _unitPriceTiers) {
      tier.priceController.dispose();
      tier.qtyController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: DesignColors.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isEditing
                        ? Icons.edit_rounded
                        : Icons.add_circle_outline_rounded,
                    color: DesignColors.brand,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isEditing ? 'Edit Product' : 'Add New Product',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: DesignColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Product Name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Product Name *',
                hintText: 'e.g. Panadol Extra (10 tablets)',
                hintStyle: TextStyle(color: DesignColors.textTertiary),
                labelStyle: const TextStyle(
                  color: DesignColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.auto,
                prefixIcon: const Icon(Icons.inventory_2_outlined,
                    color: DesignColors.textTertiary),
                filled: true,
                fillColor: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: DesignColors.brand, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter product name' : null,
            ),
            const SizedBox(height: 14),

            // Category dropdown
            categoriesAsync.when(
              data: (categories) {
                final ac = categories.where((c) => c.isActive).toList();
                return Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? DesignColors.darkSurfaceElevated
                        : DesignColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Category *',
                        labelStyle: TextStyle(
                          color: DesignColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        floatingLabelBehavior: FloatingLabelBehavior.auto,
                        prefixIcon: Icon(Icons.category_outlined,
                            color: DesignColors.textTertiary),
                        border: InputBorder.none,
                      ),
                      dropdownColor:
                          isDark ? DesignColors.darkSurface : Colors.white,
                      items: ac
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                      validator: (v) => v == null ? 'Select a category' : null,
                    ),
                  ),
                );
              },
              loading: () =>
                  const LinearProgressIndicator(color: DesignColors.brand),
              error: (e, _) => const Text(
                'Couldn\'t load categories. Check your connection.',
                style: TextStyle(color: DesignColors.error, fontSize: 12),
              ),
            ),
            const SizedBox(height: 14),

            // ── Multi-unit Pricing ────────────────────────────────────────
            _buildPricingSection(isDark),
            const SizedBox(height: 14),

            // ── Reorder Point ────────────────────────────────────────────
            _buildReorderPointSection(isDark),
            const SizedBox(height: 14),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                hintStyle: TextStyle(color: DesignColors.textTertiary),
                labelStyle: const TextStyle(
                  color: DesignColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.auto,
                prefixIcon: const Icon(Icons.description_outlined,
                    color: DesignColors.textTertiary),
                filled: true,
                fillColor: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: DesignColors.brand, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
            const SizedBox(height: 14),

            // Product image
            ImagePickerSection(
              initialImageUrl: _imageUrl,
              type: 'product',
              label: 'Add product image (optional)',
              onImageChanged: (url, publicId) => setState(() {
                _imageUrl = url;
                _imagePublicId = publicId;
              }),
            ),
            const SizedBox(height: 24),

            // Save button
            GradientButton(
              label: isEditing ? 'Save Changes' : 'Add Product',
              icon: isEditing ? Icons.save_rounded : Icons.add_rounded,
              onPressed: _isSaving ? null : _saveProduct,
              isLoading: _isSaving,
              height: 52,
              borderRadius: 12,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final apiClient = getIt<ApiClient>();
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    final clearImage =
        isEditing && widget.product?.imageUrl != null && _imageUrl == null;

    final primary = _unitPriceTiers[0];
    final bulkTiers = _unitPriceTiers.sublist(1);

    final primaryPrice = double.parse(primary.priceController.text.trim());

    // Every tier beyond the primary — any number of them — with its real,
    // directly-entered price and conversion count (how many primary units
    // make up one of the tier's unit; entered directly, not derived from
    // price, since bulk pricing often includes a discount).
    final pricingTiers = <Map<String, dynamic>>[];
    for (final tier in bulkTiers) {
      final tierPrice = double.tryParse(tier.priceController.text.trim());
      if (tierPrice == null) continue;
      // The conversion count is optional in the UI -- a priced tier
      // shouldn't be silently dropped just because this was left blank.
      // Default to 1 (1:1 with the primary unit) until the admin sets a
      // real count.
      final tierQty =
          double.tryParse(tier.qtyController.text.trim()) ?? 1;
      pricingTiers.add({
        'unit': tier.unit,
        'quantityPerUnit': tierQty,
        'price': tierPrice,
      });
    }

    // Convert the reorder point from whichever tier unit was selected back
    // into base units for storage, using that tier's real conversion count.
    int? minStock;
    final minStockText = _minStockController.text.trim();
    if (minStockText.isNotEmpty) {
      final enteredQty = double.parse(minStockText);
      double minStockBase = enteredQty;
      if (_minStockUnit != primary.unit) {
        final matchingTier = bulkTiers.where((t) => t.unit == _minStockUnit);
        if (matchingTier.isNotEmpty) {
          final factor =
              double.tryParse(matchingTier.first.qtyController.text.trim());
          minStockBase = enteredQty * (factor ?? 1);
        }
      }
      minStock = minStockBase.round();
    }

    try {
      Map<String, dynamic> savedProduct;
      if (isEditing) {
        savedProduct = await apiClient.updateProduct(
          widget.product!.id,
          name: _nameController.text.trim(),
          basePrice: primaryPrice,
          categoryIds: [_selectedCategoryId!],
          description: description,
          image: _imageUrl,
          imagePublicId: _imagePublicId,
          unit: primary.unit,
          pricingTiers: pricingTiers,
          minStock: minStock,
          clearImage: clearImage,
        );
      } else {
        savedProduct = await apiClient.createProduct(
          name: _nameController.text.trim(),
          basePrice: primaryPrice,
          categoryIds: [_selectedCategoryId!],
          description: description,
          image: _imageUrl,
          imagePublicId: _imagePublicId,
          unit: primary.unit,
          pricingTiers: pricingTiers,
          minStock: minStock,
        );
      }

      await catalog_cache.upsertProductCacheFromApi(savedProduct);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_productSaveErrorMessage(e)),
            backgroundColor: DesignColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _productSaveErrorMessage(Object error) {
    if (error is DioException && error.response?.statusCode == 429) {
      return 'Could not save product: server is busy. Please wait a moment and try again.';
    }
    if (error is DioException && error.response?.statusCode == 503) {
      return 'Could not save product: server is unavailable. Please try again later.';
    }
    if (error is DioException) {
      final message = error.response?.data is Map
          ? (error.response?.data['message']?.toString())
          : null;
      if (message != null && message.isNotEmpty) {
        return 'Could not save product: $message';
      }
    }
    return 'Could not save product. Please check the details and try again.';
  }

  // ─── Reorder point ──────────────────────────────────────────────────────

  Widget _buildReorderPointSection(bool isDark) {
    final tierUnits = _unitPriceTiers.map((t) => t.unit).toList();
    if (!tierUnits.contains(_minStockUnit)) {
      _minStockUnit = tierUnits.first;
    }
    final fill = isDark
        ? DesignColors.darkSurfaceElevated
        : DesignColors.surfaceSubtle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: _minStockController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Reorder when below (optional)',
              hintStyle: TextStyle(color: DesignColors.textTertiary),
              labelStyle: const TextStyle(
                color: DesignColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              floatingLabelBehavior: FloatingLabelBehavior.auto,
              prefixIcon: const Icon(Icons.warning_amber_rounded,
                  color: DesignColors.textTertiary),
              filled: true,
              fillColor: fill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: DesignColors.brand, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              if (double.tryParse(v.trim()) == null) return 'Invalid number';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            height: 52,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _minStockUnit,
                isExpanded: true,
                items: tierUnits
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _minStockUnit = v);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Pricing section helpers ────────────────────────────────────────────

  Widget _buildPricingSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: DesignColors.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.local_offer_rounded,
                  color: DesignColors.brand, size: 16),
            ),
            const SizedBox(width: 8),
            const Text(
              'Pricing by Unit',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DesignColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_unitPriceTiers.length} '
                '${_unitPriceTiers.length == 1 ? 'tier' : 'tiers'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: DesignColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Tiers container — no cap: add as many pricing tiers (piece,
        // dozen, carton, pallet, ...) as the business actually sells in.
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? DesignColors.darkSurfaceElevated
                : DesignColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (int i = 0; i < _unitPriceTiers.length; i++)
                _buildPricingRow(i, isDark),
              _buildAddTierButton(isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPricingRow(int index, bool isDark) {
    final tier = _unitPriceTiers[index];
    final isPrimary = index == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (index > 0)
          Divider(
            height: 1,
            thickness: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
            indent: 12,
            endIndent: 12,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Unit selector
              Expanded(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        isDark ? DesignColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: tier.unit,
                      isDense: true,
                      isExpanded: true,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.white
                            : DesignColors.textPrimary,
                      ),
                      dropdownColor: isDark
                          ? DesignColors.darkSurface
                          : Colors.white,
                      items: _units
                          .map(
                            (u) => DropdownMenuItem(
                              value: u,
                              child: Text(
                                u[0].toUpperCase() + u.substring(1),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setState(
                          () => tier.unit = val ?? tier.unit),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Price field
              Expanded(
                flex: 7,
                child: TextFormField(
                  controller: tier.priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(
                      color: DesignColors.textTertiary,
                      fontWeight: FontWeight.normal,
                    ),
                    prefixText: 'KES ',
                    prefixStyle: const TextStyle(
                      color: DesignColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? DesignColors.darkSurface
                        : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: DesignColors.brand, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Required';
                    }
                    if (double.tryParse(v.trim()) == null) {
                      return 'Invalid';
                    }
                    return null;
                  },
                ),
              ),
              // Delete button (not on primary row)
              if (!isPrimary) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() {
                    _unitPriceTiers[index].priceController.dispose();
                    _unitPriceTiers[index].qtyController.dispose();
                    _unitPriceTiers.removeAt(index);
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DesignColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: DesignColors.error, size: 18),
                  ),
                ),
              ] else
                // Spacer to keep row height consistent when no delete btn
                const SizedBox(width: 34),
            ],
          ),
        ),
        // Conversion count — how many primary units make up one of this
        // tier's unit. Entered directly, not derived from price, since
        // bulk pricing often includes a discount that would otherwise
        // silently corrupt the real physical count.
        if (!isPrimary)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextFormField(
              controller: tier.qtyController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              decoration: InputDecoration(
                labelText:
                    'How many ${_unitPriceTiers[0].unit} per ${tier.unit}? (optional)',
                labelStyle: const TextStyle(fontSize: 12),
                hintText: 'e.g. 12 — defaults to 1 if left blank',
                hintStyle: TextStyle(
                  color: DesignColors.textTertiary,
                  fontWeight: FontWeight.normal,
                ),
                filled: true,
                fillColor: isDark ? DesignColors.darkSurface : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: DesignColors.brand, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              // Optional: only validate the format when something was
              // typed. A blank value is fine -- _saveProduct() defaults
              // the conversion count to 1 rather than dropping the tier.
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final parsed = double.tryParse(v.trim());
                if (parsed == null || parsed <= 0) {
                  return 'Enter a count greater than 0';
                }
                return null;
              },
            ),
          ),
        // Label below each row
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: isPrimary
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 11, color: DesignColors.brand),
                        const SizedBox(width: 4),
                        Text(
                          'Primary — base for stock deductions',
                          style: const TextStyle(
                            fontSize: 11,
                            color: DesignColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tip: make this your smallest unit (e.g. Piece) — add '
                      'bigger units like Pack or Carton as tiers below.',
                      style: TextStyle(
                        fontSize: 11,
                        color: DesignColors.textTertiary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                )
              : Text(
                  'Tier ${index + 1} — set the real pack/carton size',
                  style: const TextStyle(
                    fontSize: 11,
                    color: DesignColors.textTertiary,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildAddTierButton(bool isDark) {
    return InkWell(
      onTap: () => setState(() {
        _unitPriceTiers.add(_UnitPriceTier(unit: _getNextUnit()));
      }),
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(14),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add_circle_outline_rounded,
                color: DesignColors.brand, size: 17),
            SizedBox(width: 6),
            Text(
              'Add pricing tier',
              style: TextStyle(
                color: DesignColors.brand,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getNextUnit() {
    final used = _unitPriceTiers.map((t) => t.unit).toSet();
    for (final u in _units) {
      if (!used.contains(u)) return u;
    }
    // Every option in the dropdown is already used as a tier — fall back
    // to whatever the dropdown's first entry is; the admin can still
    // change it manually.
    return _units.first;
  }
}
