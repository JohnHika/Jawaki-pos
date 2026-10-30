import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/axon_gateway_client.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/utils/api_message.dart';
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
  final String? entityLabel;
  const AddEditProductSheet({super.key, this.product, this.entityLabel});
  @override
  ConsumerState<AddEditProductSheet> createState() =>
      _AddEditProductSheetState();
}

class _AddEditProductSheetState extends ConsumerState<AddEditProductSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _minStockController;
  // Lowest price a cashier may sell at without a manager. Lives on the server
  // only (the phone's product cache has no column for it), so an edit loads it
  // from there.
  final TextEditingController _minPriceController = TextEditingController();
  double? _serverMinPrice;
  String? _selectedCategoryId;
  String? _imageUrl;
  String? _imagePublicId;
  late List<_UnitPriceTier> _unitPriceTiers;
  late List<BusinessLayoutProductField> _industryFields;
  late Map<String, TextEditingController> _industryFieldControllers;
  late String _minStockUnit;
  bool _allowFractions = false;
  bool _trackInventory = true;
  bool _isSaving = false;

  // Axon AI product recognition only runs after the owner taps the explicit
  // action below; selecting or saving a photo never sends it by itself.
  bool _aiLooking = false;
  Map<String, dynamic>? _aiSuggestion;
  String? _aiMessage;

  bool get isEditing => widget.product != null;

  String? _validateNonNegativeNumber(String? value, {bool required = false}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? 'Required' : null;
    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      return 'Enter a valid amount of 0 or more';
    }
    return null;
  }

  String? _validatePositiveNumber(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      return 'Enter a finite count greater than 0';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _skuController = TextEditingController(text: widget.product?.sku ?? '');
    _descriptionController =
        TextEditingController(text: widget.product?.description ?? '');
    final existingCategoryId = widget.product?.categoryId;
    _selectedCategoryId =
        existingCategoryId?.isNotEmpty == true ? existingCategoryId : null;
    _imageUrl = widget.product?.imageUrl;
    final businessLayout = ref.read(businessLayoutProvider);
    _industryFields = businessLayout.effectiveProductFields;
    final existingIndustryValues = _readExistingIndustryValues();
    _industryFieldControllers = {
      for (final field in _industryFields)
        field.key: TextEditingController(
          text: existingIndustryValues[field.key]?.toString() ?? '',
        ),
    };
    _allowFractions = widget.product?.allowFractions ??
        businessLayout.effectiveAllowFractionsForNewProducts;
    _trackInventory = widget.product?.trackInventory ??
        businessLayout.effectiveTrackInventoryForNewProducts;
    final defaultUnit = businessLayout.defaultBaseUnit;

    // Start with just the primary tier; any existing bulk tiers (any
    // number) load a moment later from the local cache, once fetched.
    _unitPriceTiers = [
      _UnitPriceTier(
        unit: widget.product?.unit ?? defaultUnit,
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
      _loadServerMinPrice();
    }
  }

  Map<String, dynamic> _readExistingIndustryValues() {
    final raw = widget.product?.metadata;
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['industryFields'] is Map) {
        return Map<String, dynamic>.from(decoded['industryFields'] as Map);
      }
    } catch (_) {
      // Malformed legacy metadata must not prevent product editing.
    }
    return const {};
  }

  Map<String, dynamic> _productMetadataForSave() {
    final metadata = <String, dynamic>{};
    final raw = widget.product?.metadata;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          metadata.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // Ignore malformed cache data and save a clean metadata object.
      }
    }
    final industryValues = <String, dynamic>{};
    final existing = metadata['industryFields'];
    if (existing is Map) {
      industryValues.addAll(Map<String, dynamic>.from(existing));
    }
    for (final entry in _industryFieldControllers.entries) {
      final value = entry.value.text.trim();
      if (value.isEmpty) {
        industryValues.remove(entry.key);
      } else {
        industryValues[entry.key] = value;
      }
    }
    if (industryValues.isEmpty) {
      metadata.remove('industryFields');
    } else {
      metadata['industryFields'] = industryValues;
    }
    return metadata;
  }

  Future<void> _loadServerMinPrice() async {
    if (getIt<AuthService>().isLocalWorkspace) return;
    try {
      final json = await getIt<ApiClient>().getProduct(widget.product!.id);
      final raw = json['minPrice'];
      final value =
          raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
      if (!mounted || value == null) return;
      setState(() {
        _serverMinPrice = value;
        if (_minPriceController.text.isEmpty) {
          _minPriceController.text = value.toStringAsFixed(0);
        }
      });
    } catch (_) {
      // Offline: leave it blank. Saving then leaves the server value alone.
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

  /// Sends a locally stored photo to the owner-configured Axon Gateway only
  /// after explicit user action. No image is sent when the key is missing.
  Future<void> _identifyFromPhoto(String path) async {
    if (_aiLooking) return;
    setState(() {
      _aiLooking = true;
      _aiSuggestion = null;
      _aiMessage = null;
    });

    try {
      if (!getIt<AuthService>().isLocalWorkspace) {
        throw const AxonGatewayException(
          'Product photo recognition is available in the standalone workspace.',
        );
      }
      if (path.toLowerCase().startsWith('http://') ||
          path.toLowerCase().startsWith('https://')) {
        throw const AxonGatewayException(
          'This photo is only available online. Choose a photo saved on this device.',
        );
      }

      final imageFile = File(path);
      if (!await imageFile.exists()) {
        throw const AxonGatewayException(
          'This photo is no longer available on this device. Choose it again.',
        );
      }
      if (await imageFile.length() > AxonGatewayClient.maxVisionImageBytes) {
        throw const AxonGatewayException(
          'This image is too large to analyze. Choose a smaller photo.',
        );
      }
      final imageBytes = await imageFile.readAsBytes();
      final configuredFields =
          _industryFields.map((field) => field.key).toList();
      final response = await AxonGatewayClient().vision(
        prompt: 'Identify the retail product visible in this photo. Return '
            'only one valid JSON object with keys: name (string or null), '
            'description (string or null), category (string or null), and '
            'attributes (object containing only clearly visible values for '
            'these configured product fields: '
            '${jsonEncode(configuredFields)}). Do not invent a price, cost, '
            'stock quantity, barcode, brand, or text that is not visible. '
            'Use null or an empty object when uncertain.',
        imageBase64: base64Encode(imageBytes),
        maxTokens: 400,
      );
      final suggestion = _parseAiProductSuggestion(response);
      if (!mounted) return;
      setState(() {
        _aiSuggestion = suggestion;
        _aiMessage = suggestion == null
            ? 'Axon AI could not identify clear product details. You can still enter them yourself.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _aiMessage = error is AxonGatewayException
            ? error.message
            : 'Could not analyze this photo. Try again or enter the details yourself.';
      });
    } finally {
      if (mounted) setState(() => _aiLooking = false);
    }
  }

  Map<String, dynamic>? _parseAiProductSuggestion(String response) {
    final jsonStart = response.indexOf('{');
    final jsonEnd = response.lastIndexOf('}');
    if (jsonStart < 0 || jsonEnd < jsonStart) {
      throw const AxonGatewayException(
        'Axon AI returned product details in an unreadable format. Try again.',
      );
    }
    try {
      final decoded = jsonDecode(response.substring(jsonStart, jsonEnd + 1));
      if (decoded is! Map) {
        throw const FormatException('Expected a product object.');
      }
      final suggestion = Map<String, dynamic>.from(decoded);
      final name = suggestion['name']?.toString().trim();
      if (name == null || name.isEmpty) return null;
      suggestion['name'] = name;
      for (final key in ['description', 'category']) {
        final value = suggestion[key]?.toString().trim();
        suggestion[key] = value == null || value.isEmpty ? null : value;
      }
      final rawAttributes = suggestion['attributes'];
      suggestion['attributes'] = rawAttributes is Map
          ? Map<String, dynamic>.from(rawAttributes)
          : <String, dynamic>{};
      return suggestion;
    } on FormatException {
      throw const AxonGatewayException(
        'Axon AI returned product details in an unreadable format. Try again.',
      );
    } on TypeError {
      throw const AxonGatewayException(
        'Axon AI returned product details in an unreadable format. Try again.',
      );
    }
  }

  void _applyAiSuggestion(List<dynamic> categories) {
    final s = _aiSuggestion;
    if (s == null) return;
    final name = (s['name'] as String?)?.trim();
    final description = (s['description'] as String?)?.trim();
    final category = (s['category'] as String?)?.trim().toLowerCase();
    String? categoryId;
    if (category != null && category.isNotEmpty) {
      for (final c in categories) {
        final cName = (c.name as String).toLowerCase();
        if (c.isActive == true &&
            (cName == category ||
                cName.contains(category) ||
                category.contains(cName))) {
          categoryId = c.id as String;
          break;
        }
      }
    }
    setState(() {
      if (name != null && name.isNotEmpty) _nameController.text = name;
      if (description != null &&
          description.isNotEmpty &&
          _descriptionController.text.trim().isEmpty) {
        _descriptionController.text = description;
      }
      if (categoryId != null) _selectedCategoryId = categoryId;
      final attributes = s['attributes'];
      if (attributes is Map) {
        for (final entry in _industryFieldControllers.entries) {
          final value = attributes[entry.key]?.toString().trim();
          if (entry.value.text.trim().isEmpty &&
              value != null &&
              value.isNotEmpty) {
            entry.value.text = value;
          }
        }
      }
      _aiSuggestion = null;
    });
  }

  String _formatQty(double qty) {
    return qty % 1 == 0 ? qty.toStringAsFixed(0) : qty.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _descriptionController.dispose();
    _minStockController.dispose();
    _minPriceController.dispose();
    for (final controller in _industryFieldControllers.values) {
      controller.dispose();
    }
    for (final tier in _unitPriceTiers) {
      tier.priceController.dispose();
      tier.qtyController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final businessLayout = ref.watch(businessLayoutProvider);
    final entityLabel = widget.entityLabel ?? businessLayout.productSingular;
    final entityLabelLower = entityLabel.toLowerCase();
    final categoriesAsync = ref.watch(categoriesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final fieldBorder =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final fieldFill =
        isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceSubtle;
    // The fields scroll; the save button stays pinned above the keyboard so
    // it is never lost when a long form is half filled in.
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(DesignSpacing.xxl,
                  DesignSpacing.lg, DesignSpacing.xxl, DesignSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_aiLooking ||
                      _aiSuggestion != null ||
                      _aiMessage != null) ...[
                    _AiProductCard(
                      looking: _aiLooking,
                      suggestion: _aiSuggestion,
                      message: _aiMessage,
                      onUse: () => _applyAiSuggestion(
                          categoriesAsync.valueOrNull ?? const <dynamic>[]),
                    ),
                    const SizedBox(height: DesignSpacing.md + 2),
                  ],

                  // ── Product Name ──────────────────────────────────────────
                  TextFormField(
                    controller: _nameController,
                    style: TextStyle(color: titleColor),
                    decoration: InputDecoration(
                      labelText: '$entityLabel Name *',
                      hintText: businessLayout.productNameHint,
                      hintStyle: TextStyle(color: tertiaryColor),
                      labelStyle: TextStyle(
                        color: secondaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.auto,
                      prefixIcon: Icon(Icons.inventory_2_outlined,
                          color: tertiaryColor),
                      filled: true,
                      fillColor: fieldFill,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        borderSide: BorderSide(color: fieldBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        borderSide: BorderSide(color: fieldBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        borderSide: const BorderSide(
                            color: DesignColors.brand, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: DesignSpacing.lg, vertical: 14),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter $entityLabelLower name'
                        : null,
                  ),
                  const SizedBox(height: DesignSpacing.md + 2),

                  TextFormField(
                    controller: _skuController,
                    style: TextStyle(color: titleColor),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9_-]')),
                      LengthLimitingTextInputFormatter(50),
                    ],
                    decoration: InputDecoration(
                      labelText: businessLayout.productCodeLabel,
                      hintText: businessLayout.productCodeHint,
                      hintStyle: TextStyle(color: tertiaryColor),
                      prefixIcon:
                          Icon(Icons.qr_code_2_rounded, color: tertiaryColor),
                      filled: true,
                      fillColor: fieldFill,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        borderSide: BorderSide(color: fieldBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        borderSide: BorderSide(color: fieldBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        borderSide: const BorderSide(
                            color: DesignColors.brand, width: 1.5),
                      ),
                    ),
                    validator: (value) {
                      final code = value?.trim() ?? '';
                      if (code.isNotEmpty && code.length < 3) {
                        return 'Enter at least 3 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: DesignSpacing.md + 2),

                  // ── Category ──────────────────────────────────────────────
                  categoriesAsync.when(
                    data: (categories) {
                      final ac = categories
                          .where(
                              (c) => c.isActive || c.id == _selectedCategoryId)
                          .toList();
                      return Container(
                        decoration: BoxDecoration(
                          color: fieldFill,
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusMd),
                          border: Border.all(color: fieldBorder),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.md),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedCategoryId,
                            style: TextStyle(color: titleColor),
                            decoration: InputDecoration(
                              labelText: 'Category (optional)',
                              labelStyle: TextStyle(
                                color: secondaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                              floatingLabelBehavior: FloatingLabelBehavior.auto,
                              prefixIcon: Icon(Icons.category_outlined,
                                  color: tertiaryColor),
                              // The wrapping Container already draws the field box;
                              // without these the theme added a second outline inside.
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                            ),
                            dropdownColor: isDark
                                ? DesignColors.darkSurface
                                : Colors.white,
                            items: ac
                                .map((c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.isActive
                                          ? c.name
                                          : '${c.name} (inactive)'),
                                    ))
                                .toList(),
                            hint: const Text('Uncategorized'),
                            onChanged: (v) =>
                                setState(() => _selectedCategoryId = v),
                          ),
                        ),
                      );
                    },
                    loading: () => _buildCategoryLoading(isDark),
                    error: (e, _) => _buildCategoryError(isDark),
                  ),
                  const SizedBox(height: DesignSpacing.md + 2),

                  // ── Multi-unit Pricing ────────────────────────────────────
                  _buildPricingSection(isDark),
                  const SizedBox(height: DesignSpacing.md + 2),

                  Container(
                    decoration: BoxDecoration(
                      color: fieldFill,
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      border: Border.all(color: fieldBorder),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: SwitchListTile.adaptive(
                        value: _trackInventory,
                        onChanged: (value) =>
                            setState(() => _trackInventory = value),
                        activeTrackColor: DesignColors.brand,
                        secondary: Icon(Icons.inventory_2_outlined,
                            color: secondaryColor),
                        title: Text('Track stock for this item',
                            style: TextStyle(color: titleColor)),
                        subtitle: Text(
                          _trackInventory
                              ? 'Stock levels and low-stock alerts follow sales.'
                              : 'Use for services or items that do not reduce stock.',
                          style: TextStyle(color: secondaryColor),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.md + 2),

                  // Weight, volume, fabric, and other measured goods may be sold
                  // in partial base units. The POS and API both enforce this flag.
                  Container(
                    decoration: BoxDecoration(
                      color: fieldFill,
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      border: Border.all(color: fieldBorder),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: SwitchListTile.adaptive(
                        value: _allowFractions,
                        onChanged: (value) =>
                            setState(() => _allowFractions = value),
                        activeTrackColor: DesignColors.brand,
                        secondary:
                            Icon(Icons.scale_outlined, color: secondaryColor),
                        title: Text('Sell partial quantities',
                            style: TextStyle(color: titleColor)),
                        subtitle: Text(
                          'Allow amounts such as 0.5 ${_unitPriceTiers.first.unit}.',
                          style: TextStyle(color: secondaryColor),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.md + 2),

                  if (!getIt<AuthService>().isLocalWorkspace) ...[
                    TextFormField(
                      controller: _minPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: titleColor),
                      decoration: kitFieldDecoration(
                        context,
                        label: 'Lowest price you will accept (optional)',
                        prefixText: 'KES ',
                        helper:
                            'Per ${_unitPriceTiers[0].unit}. Cashiers cannot sell below this without a manager.',
                      ),
                      validator: _validateNonNegativeNumber,
                    ),
                    const SizedBox(height: DesignSpacing.md + 2),
                  ],

                  // ── Reorder Point ─────────────────────────────────────────
                  if (_trackInventory) ...[
                    _buildReorderPointSection(isDark),
                    const SizedBox(height: DesignSpacing.md + 2),
                  ],

                  // ── Description ───────────────────────────────────────────
                  TextFormField(
                    controller: _descriptionController,
                    style: TextStyle(color: titleColor),
                    decoration: InputDecoration(
                      labelText: 'Description (optional)',
                      hintStyle: TextStyle(color: tertiaryColor),
                      labelStyle: TextStyle(
                        color: secondaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                      floatingLabelBehavior: FloatingLabelBehavior.auto,
                      prefixIcon: Icon(Icons.description_outlined,
                          color: tertiaryColor),
                      filled: true,
                      fillColor: fieldFill,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        borderSide: BorderSide(color: fieldBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        borderSide: BorderSide(color: fieldBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        borderSide: const BorderSide(
                            color: DesignColors.brand, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: DesignSpacing.lg, vertical: 14),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                  ),
                  const SizedBox(height: DesignSpacing.md + 2),

                  if (_industryFields.isNotEmpty) ...[
                    Text(
                      'Product details',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: titleColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    for (final field in _industryFields) ...[
                      TextFormField(
                        controller: _industryFieldControllers[field.key],
                        style: TextStyle(color: titleColor),
                        decoration: InputDecoration(
                          labelText: '${field.label} (optional)',
                          hintText: field.hint,
                          hintStyle: TextStyle(color: tertiaryColor),
                          labelStyle: TextStyle(color: secondaryColor),
                          prefixIcon:
                              Icon(Icons.tune_rounded, color: tertiaryColor),
                          filled: true,
                          fillColor: fieldFill,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusMd),
                            borderSide: BorderSide(color: fieldBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusMd),
                            borderSide: BorderSide(color: fieldBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusMd),
                            borderSide: const BorderSide(
                                color: DesignColors.brand, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: DesignSpacing.lg, vertical: 14),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 120,
                      ),
                      const SizedBox(height: DesignSpacing.md),
                    ],
                  ],

                  // ── Product image ─────────────────────────────────────────
                  ImagePickerSection(
                    initialImageUrl: _imageUrl,
                    type: 'product',
                    label: 'Add $entityLabelLower image (optional)',
                    onImageChanged: (url, publicId) => setState(() {
                      _imageUrl = url;
                      _imagePublicId = publicId;
                    }),
                  ),
                  if (getIt<AuthService>().isLocalWorkspace &&
                      _imageUrl != null &&
                      !_imageUrl!.startsWith('http://') &&
                      !_imageUrl!.startsWith('https://')) ...[
                    const SizedBox(height: DesignSpacing.sm),
                    Text(
                      'The photo stays on this device unless you choose to send it to Axon AI for product recognition.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: DesignSpacing.xs),
                    OutlinedButton.icon(
                      onPressed: _aiLooking
                          ? null
                          : () => _identifyFromPhoto(_imageUrl!),
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: Text(_aiLooking
                          ? 'Analyzing photo…'
                          : 'Identify with Axon AI'),
                    ),
                  ],
                  const SizedBox(height: DesignSpacing.xxl),
                ],
              ),
            ),
          ),
          PinnedActionBar(
            child: GradientButton(
              label: isEditing ? 'Save Changes' : 'Add $entityLabel',
              icon: isEditing ? Icons.save_rounded : Icons.add_rounded,
              onPressed: _isSaving ? null : _saveProduct,
              isLoading: _isSaving,
              height: 52,
              borderRadius: DesignSpacing.radiusMd,
            ),
          ),
        ],
      ),
    );
  }

  /// Polished loading state for the category dropdown — uses a shimmer-like
  /// skeleton instead of a bare LinearProgressIndicator.
  Widget _buildCategoryLoading(bool isDark) {
    final fill =
        isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceSubtle;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(
          color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.lg),
      child: Row(
        children: [
          Icon(Icons.category_outlined,
              color: isDark
                  ? DesignColors.darkTextTertiary
                  : DesignColors.textTertiary,
              size: 20),
          const SizedBox(width: DesignSpacing.md),
          Text(
            'Loading categories...',
            style: TextStyle(
              color: isDark
                  ? DesignColors.darkTextTertiary
                  : DesignColors.textTertiary,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: DesignColors.brand.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// Polished error state for the category dropdown.
  Widget _buildCategoryError(bool isDark) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: DesignColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(
          color: DesignColors.error.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.lg),
      child: Row(
        children: [
          Icon(
            getIt<AuthService>().isLocalWorkspace
                ? Icons.storage_rounded
                : Icons.cloud_off_rounded,
            color: DesignColors.error,
            size: 20,
          ),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: Text(
              getIt<AuthService>().isLocalWorkspace
                  ? 'Couldn’t read saved categories on this device. Try again.'
                  : 'Couldn\'t load categories. Check your connection.',
              style: const TextStyle(
                color: DesignColors.error,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    final units = _unitPriceTiers
        .map((tier) => tier.unit.trim().toLowerCase())
        .toList(growable: false);
    if (units.toSet().length != units.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a different unit for each price tier.'),
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final apiClient = getIt<ApiClient>();
      final storageService = getIt<StorageService>();
      final requestTenantId = storageService.getTenantId();
      final requestBranchId = storageService.getBranchId();
      final requestApiBaseUrl = apiClient.baseUrl;
      final description = _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim();
      final clearImage =
          isEditing && widget.product?.imageUrl != null && _imageUrl == null;

      final primary = _unitPriceTiers[0];
      final bulkTiers = _unitPriceTiers.sublist(1);

      final primaryPrice = double.tryParse(primary.priceController.text.trim());
      if (primaryPrice == null || !primaryPrice.isFinite || primaryPrice < 0) {
        throw StateError('Enter a valid primary price of 0 or more.');
      }

      // Every tier beyond the primary — any number of them — with its real,
      // directly-entered price and conversion count (how many primary units
      // make up one of the tier's unit; entered directly, not derived from
      // price, since bulk pricing often includes a discount).
      final pricingTiers = <Map<String, dynamic>>[];
      for (final tier in bulkTiers) {
        final tierPrice = double.tryParse(tier.priceController.text.trim());
        if (tierPrice == null || !tierPrice.isFinite || tierPrice < 0) {
          throw StateError('Check the price for ${tier.unit}.');
        }
        // The conversion count is optional in the UI -- a priced tier
        // shouldn't be silently dropped just because this was left blank.
        // Default to 1 (1:1 with the primary unit) until the admin sets a
        // real count.
        final qtyText = tier.qtyController.text.trim();
        final tierQty = qtyText.isEmpty ? 1.0 : double.tryParse(qtyText);
        if (tierQty == null || !tierQty.isFinite || tierQty <= 0) {
          throw StateError('Enter a valid unit count for ${tier.unit}.');
        }
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
        final enteredQty = double.tryParse(minStockText);
        if (enteredQty == null || !enteredQty.isFinite || enteredQty < 0) {
          throw StateError('Enter a valid low-stock quantity of 0 or more.');
        }
        double minStockBase = enteredQty;
        if (_minStockUnit != primary.unit) {
          final matchingTier = bulkTiers.where((t) => t.unit == _minStockUnit);
          if (matchingTier.isNotEmpty) {
            final factorText = matchingTier.first.qtyController.text.trim();
            final factor =
                factorText.isEmpty ? 1.0 : double.tryParse(factorText);
            if (factor == null || !factor.isFinite || factor <= 0) {
              throw StateError(
                  'Enter a valid unit count before setting its low-stock level.');
            }
            minStockBase = enteredQty * factor;
          }
        }
        // Product.minStock is an integer in both SQLite and the shared API.
        // Reject overflow before round() so the form can recover cleanly.
        if (!minStockBase.isFinite || minStockBase > 2147483647) {
          throw StateError('The low-stock quantity is too large.');
        }
        minStock = minStockBase.round();
      }

      final minPriceText = _minPriceController.text.trim();
      final minPrice =
          minPriceText.isEmpty ? null : double.tryParse(minPriceText);
      if (minPriceText.isNotEmpty &&
          (minPrice == null || !minPrice.isFinite || minPrice < 0)) {
        throw StateError('Enter a valid minimum price of 0 or more.');
      }
      // Emptying a field that had a value means "remove the floor".
      final clearMinPrice =
          isEditing && minPriceText.isEmpty && _serverMinPrice != null;

      if (getIt<AuthService>().isLocalWorkspace) {
        final database = getIt<AppDatabase>();
        final branchId = storageService.getBranchId();
        if (branchId == null || branchId.isEmpty) {
          throw StateError('The local shop branch is missing. Reopen setup.');
        }
        final productId = widget.product?.id ?? const Uuid().v4();
        final categoryId =
            _selectedCategoryId ?? await database.ensureLocalDefaultCategory();
        final now = DateTime.now();
        final sku = _skuController.text.trim().isNotEmpty
            ? _skuController.text.trim()
            : 'CB-${productId.substring(0, 8).toUpperCase()}';
        final metadata = _productMetadataForSave();
        final localTiers = <ProductPricingTiersCompanion>[
          for (var i = 0; i < pricingTiers.length; i++)
            ProductPricingTiersCompanion.insert(
              id: '$productId-tier-${i + 1}',
              productId: productId,
              unit: pricingTiers[i]['unit'] as String,
              quantityPerUnit:
                  (pricingTiers[i]['quantityPerUnit'] as num).toDouble(),
              price: (pricingTiers[i]['price'] as num).toDouble(),
              sortOrder: Value(i + 1),
            ),
        ];
        await database.saveLocalProduct(
          productId: productId,
          branchId: branchId,
          tiers: localTiers,
          product: ProductsCompanion.insert(
            id: productId,
            sku: sku,
            name: _nameController.text.trim(),
            description: Value(description),
            metadata: Value(jsonEncode(metadata)),
            categoryId: categoryId,
            price: primaryPrice,
            costPrice: Value(widget.product?.costPrice),
            unit: Value(primary.unit),
            imageUrl: Value(_imageUrl),
            isActive: Value(widget.product?.isActive ?? true),
            trackInventory: Value(_trackInventory),
            allowFractions: Value(_allowFractions),
            minStock: Value(_trackInventory
                ? (minStock ?? widget.product?.minStock ?? 0)
                : 0),
            createdAt: widget.product?.createdAt ?? now,
            updatedAt: now,
          ),
        );
        if (!mounted) return;
        ref.invalidate(catalog_cache.filteredProductsProvider);
        ref.invalidate(catalog_cache.favoriteProductsProvider);
        ref.invalidate(catalog_cache.categoriesProvider);
        Navigator.pop(context);
        return;
      }

      Map<String, dynamic> savedProduct;
      if (isEditing) {
        savedProduct = await apiClient.updateProduct(
          widget.product!.id,
          name: _nameController.text.trim(),
          sku: _skuController.text.trim(),
          basePrice: primaryPrice,
          categoryIds:
              _selectedCategoryId == null ? const [] : [_selectedCategoryId!],
          description: description,
          image: _imageUrl,
          imagePublicId: _imagePublicId,
          unit: primary.unit,
          pricingTiers: pricingTiers,
          minStock: _trackInventory ? minStock : null,
          minPrice: minPrice,
          allowFractions: _allowFractions,
          trackInventory: _trackInventory,
          clearMinPrice: clearMinPrice,
          clearImage: clearImage,
          metadata: _productMetadataForSave(),
        );
      } else {
        savedProduct = await apiClient.createProduct(
          name: _nameController.text.trim(),
          sku: _skuController.text.trim().isEmpty
              ? null
              : _skuController.text.trim(),
          basePrice: primaryPrice,
          categoryIds:
              _selectedCategoryId == null ? const [] : [_selectedCategoryId!],
          description: description,
          image: _imageUrl,
          imagePublicId: _imagePublicId,
          unit: primary.unit,
          pricingTiers: pricingTiers,
          minStock: _trackInventory ? minStock : null,
          minPrice: minPrice,
          allowFractions: _allowFractions,
          trackInventory: _trackInventory,
          metadata: _productMetadataForSave(),
        );
      }

      await catalog_cache.upsertProductCacheFromApi(
        savedProduct,
        expectedTenantId: requestTenantId,
        expectedBranchId: requestBranchId,
        expectedApiBaseUrl: requestApiBaseUrl,
      );
      // POS reads its grid from FutureProviders backed by the local database.
      // Refresh those snapshots after the cache write so a POS tab kept alive
      // by navigation immediately reflects edits made from Products.
      if (mounted) {
        ref.invalidate(catalog_cache.filteredProductsProvider);
        ref.invalidate(catalog_cache.favoriteProductsProvider);
        ref.invalidate(catalog_cache.categoriesProvider);
        Navigator.pop(context);
      }
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
    final reason = apiErrorMessage(error);
    if (reason == 'Something went wrong. Please try again.') {
      return 'Could not save product. Please check the details and try again.';
    }
    return 'Could not save product: $reason';
  }

  // ─── Reorder point ──────────────────────────────────────────────────────

  Widget _buildReorderPointSection(bool isDark) {
    final tierUnits = _unitPriceTiers.map((t) => t.unit).toList();
    if (!tierUnits.contains(_minStockUnit)) {
      _minStockUnit = tierUnits.first;
    }
    final fill =
        isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceSubtle;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final fieldBorder =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: _minStockController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: titleColor),
            decoration: InputDecoration(
              labelText: 'Low stock at',
              hintStyle: TextStyle(color: tertiaryColor),
              labelStyle: TextStyle(
                color: secondaryColor,
                fontWeight: FontWeight.w500,
              ),
              floatingLabelBehavior: FloatingLabelBehavior.auto,
              prefixIcon:
                  Icon(Icons.warning_amber_rounded, color: tertiaryColor),
              filled: true,
              fillColor: fill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                borderSide: BorderSide(color: fieldBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                borderSide: BorderSide(color: fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                borderSide:
                    const BorderSide(color: DesignColors.brand, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: DesignSpacing.lg, vertical: 14),
            ),
            validator: _validateNonNegativeNumber,
          ),
        ),
        const SizedBox(width: DesignSpacing.md),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.md),
            height: 52,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              border: Border.all(color: fieldBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _minStockUnit,
                isExpanded: true,
                style: TextStyle(color: titleColor),
                dropdownColor: isDark ? DesignColors.darkSurface : Colors.white,
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
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
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
                borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
              ),
              child: const Icon(Icons.local_offer_rounded,
                  color: DesignColors.brand, size: 16),
            ),
            const SizedBox(width: DesignSpacing.sm),
            Text(
              'Pricing by Unit',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: titleColor,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: DesignSpacing.sm, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
              ),
              child: Text(
                '${_unitPriceTiers.length} '
                '${_unitPriceTiers.length == 1 ? 'tier' : 'tiers'}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: tertiaryColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignSpacing.sm + 2),
        // Tiers container — no cap: add as many pricing tiers (piece,
        // dozen, carton, pallet, ...) as the business actually sells in.
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? DesignColors.darkSurfaceElevated
                : DesignColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusMd + 2),
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
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final fieldBorder =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
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
            indent: DesignSpacing.md,
            endIndent: DesignSpacing.md,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              DesignSpacing.md, DesignSpacing.md, DesignSpacing.md, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Unit selector
              Expanded(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? DesignColors.darkSurface : Colors.white,
                    borderRadius:
                        BorderRadius.circular(DesignSpacing.radiusSm + 2),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: DesignSpacing.sm + 2),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: tier.unit,
                      isDense: true,
                      isExpanded: true,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: titleColor,
                      ),
                      dropdownColor:
                          isDark ? DesignColors.darkSurface : Colors.white,
                      // A product saved with a unit that is not in the
                      // standard list (e.g. "bale") must still be selectable,
                      // or the dropdown asserts on its own value.
                      items: [
                        ...businessLayoutUnits,
                        if (!businessLayoutUnits.contains(tier.unit)) tier.unit,
                      ]
                          .map(
                            (u) => DropdownMenuItem(
                              value: u,
                              child: Text(
                                u[0].toUpperCase() + u.substring(1),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setState(() => tier.unit = val ?? tier.unit),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: DesignSpacing.sm),
              // Price field
              Expanded(
                flex: 7,
                child: TextFormField(
                  controller: tier.priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Price',
                    hintText: '0.00',
                    hintStyle: TextStyle(
                      color: tertiaryColor,
                      fontWeight: FontWeight.normal,
                    ),
                    prefixText: 'KES ',
                    prefixStyle: TextStyle(
                      color: secondaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: isDark ? DesignColors.darkSurface : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusSm + 2),
                      borderSide: BorderSide(color: fieldBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusSm + 2),
                      borderSide: BorderSide(color: fieldBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusSm + 2),
                      borderSide: const BorderSide(
                          color: DesignColors.brand, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.md,
                        vertical: DesignSpacing.md),
                  ),
                  validator: (v) => _validateNonNegativeNumber(
                    v,
                    required: true,
                  ),
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
                    padding: const EdgeInsets.all(DesignSpacing.sm),
                    decoration: BoxDecoration(
                      color: DesignColors.error.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusSm),
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
            padding: const EdgeInsets.fromLTRB(
                DesignSpacing.md, DesignSpacing.sm, DesignSpacing.md, 0),
            child: TextFormField(
              controller: tier.qtyController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                color: titleColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                labelText:
                    'How many ${_unitPriceTiers[0].unit} per ${tier.unit}? (optional)',
                labelStyle: TextStyle(
                  color: secondaryColor,
                  fontSize: 12,
                ),
                hintText: 'e.g. 12 — defaults to 1 if left blank',
                hintStyle: TextStyle(
                  color: tertiaryColor,
                  fontWeight: FontWeight.normal,
                ),
                filled: true,
                fillColor: isDark ? DesignColors.darkSurface : Colors.white,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(DesignSpacing.radiusSm + 2),
                  borderSide: BorderSide(color: fieldBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(DesignSpacing.radiusSm + 2),
                  borderSide: BorderSide(color: fieldBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(DesignSpacing.radiusSm + 2),
                  borderSide:
                      const BorderSide(color: DesignColors.brand, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: DesignSpacing.md,
                    vertical: DesignSpacing.sm + 2),
              ),
              // Optional: only validate the format when something was
              // typed. A blank value is fine -- _saveProduct() defaults
              // the conversion count to 1 rather than dropping the tier.
              validator: _validatePositiveNumber,
            ),
          ),
        // Label below each row
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, DesignSpacing.md),
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
                          style: TextStyle(
                            fontSize: 11,
                            color: tertiaryColor,
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
                        color: tertiaryColor.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                )
              : Text(
                  'Tier ${index + 1} — set the real pack/carton size',
                  style: TextStyle(
                    fontSize: 11,
                    color: tertiaryColor,
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
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
    for (final u in businessLayoutUnits) {
      if (!used.contains(u)) return u;
    }
    // Every option in the dropdown is already used as a tier — fall back
    // to whatever the dropdown's first entry is; the admin can still
    // change it manually.
    return businessLayoutUnits.first;
  }
}

/// "Axon AI sees…" card on the Add Product form: a thinking state while the
/// photo is analysed, then the recognised product with a one-tap "Use these
/// details", or a short note when the photo isn't a product.
class _AiProductCard extends StatelessWidget {
  const _AiProductCard({
    required this.looking,
    required this.suggestion,
    required this.message,
    required this.onUse,
  });

  final bool looking;
  final Map<String, dynamic>? suggestion;
  final String? message;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = context.themed(DesignColors.darkTextPrimary);
    final secondary = context.themed(DesignColors.darkTextSecondary);

    String? detail;
    final s = suggestion;
    if (s != null) {
      final details = <String>[
        if ((s['category'] as String?)?.trim().isNotEmpty == true)
          (s['category'] as String).trim(),
      ];
      final attributes = s['attributes'];
      if (attributes is Map) {
        details.addAll(
          attributes.entries
              .where(
                  (entry) => entry.value?.toString().trim().isNotEmpty == true)
              .take(3)
              .map((entry) => '${entry.key}: ${entry.value}'),
        );
      }
      detail = details.join(' · ');
    }

    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md + 2),
      decoration: BoxDecoration(
        color: DesignColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(color: DesignColors.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (looking)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.auto_awesome_rounded,
                color: DesignColors.accent, size: 20),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: looking
                ? Text('Axon AI is looking at your photo…',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: primary, fontWeight: FontWeight.w600))
                : s != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Axon AI sees',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: DesignColors.accentDark,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4)),
                          const SizedBox(height: 2),
                          Text(s['name'] as String,
                              style: theme.textTheme.titleSmall?.copyWith(
                                  color: primary, fontWeight: FontWeight.w800)),
                          if (detail != null && detail.isNotEmpty)
                            Text(detail,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: secondary)),
                          if ((s['description'] as String?)?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: DesignSpacing.xs,
                              ),
                              child: Text(
                                s['description'] as String,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: secondary),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const SizedBox(height: DesignSpacing.sm),
                          FilledButton.icon(
                            onPressed: onUse,
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Use these details'),
                          ),
                        ],
                      )
                    : Text(message ?? '',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: secondary)),
          ),
        ],
      ),
    );
  }
}
