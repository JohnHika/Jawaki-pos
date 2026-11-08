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
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../providers/catalog_categories_provider.dart';
import '../screens/barcode_scan_screen.dart';
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

  /// A name to start the form with, such as one tapped from the starter list.
  final String? initialName;
  const AddEditProductSheet(
      {super.key, this.product, this.entityLabel, this.initialName});
  @override
  ConsumerState<AddEditProductSheet> createState() =>
      _AddEditProductSheetState();
}

class _AddEditProductSheetState extends ConsumerState<AddEditProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _moreFormKey = GlobalKey<FormState>();
  final TextEditingController _stockController = TextEditingController();
  Key _photoKey = UniqueKey();
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
    _nameController = TextEditingController(
        text: widget.product?.name ?? widget.initialName ?? '');
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
    _stockController.dispose();
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
    final entityLower = entityLabel.toLowerCase();
    final categoriesAsync = ref.watch(categoriesProvider);
    final palette = SignInPalette.of(context);
    final isLocal = getIt<AuthService>().isLocalWorkspace;
    final primary = _unitPriceTiers[0];

    // The fields scroll; the save button stays pinned above the keyboard so
    // it is never lost when the form is half filled in.
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_aiLooking || _aiSuggestion != null || _aiMessage != null) ...[
                    _AiProductCard(
                      looking: _aiLooking,
                      suggestion: _aiSuggestion,
                      message: _aiMessage,
                      onUse: () => _applyAiSuggestion(
                          categoriesAsync.valueOrNull ?? const <dynamic>[]),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _photoCard(palette, entityLower),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    style: TextStyle(color: palette.ink),
                    decoration: kitFieldDecoration(
                      context,
                      label: '$entityLabel name',
                      hint: businessLayout.productNameHint,
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter the $entityLower name'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          controller: primary.priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: TextStyle(
                              color: palette.ink, fontWeight: FontWeight.w700),
                          decoration: kitFieldDecoration(
                            context,
                            label: 'Price',
                            hint: '0',
                            prefixText: 'KES ',
                          ),
                          validator: (v) =>
                              _validateNonNegativeNumber(v, required: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(flex: 4, child: _unitField(primary)),
                    ],
                  ),
                  if (!isEditing && isLocal && _trackInventory) ...[
                    const SizedBox(height: 14),
                    _openingStockField(palette, primary.unit),
                  ],
                  const SizedBox(height: 14),
                  _SwitchCard(
                    palette: palette,
                    title: 'Count stock for this',
                    subtitle: _trackInventory
                        ? 'Warns you when it runs low. Sell stops at zero.'
                        : 'For services and loose items. Turn on to count it.',
                    value: _trackInventory,
                    onChanged: (value) => setState(() => _trackInventory = value),
                  ),
                  const SizedBox(height: 12),
                  _moreDetailsRow(palette, categoriesAsync.valueOrNull),
                ],
              ),
            ),
          ),
          PinnedActionBar(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SignInButton(
                  label: _isSaving
                      ? 'Saving…'
                      : isEditing
                          ? 'Save changes'
                          : 'Save $entityLower',
                  onPressed: _isSaving ? null : () => _saveProduct(),
                ),
                if (!isEditing)
                  TextButton(
                    onPressed: _isSaving ? null : () => _saveProduct(another: true),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      foregroundColor: palette.soft,
                    ),
                    child: const Text('Save and add another',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Essentials ────────────────────────────────────────────────────────

  Widget _photoCard(SignInPalette palette, String entityLower) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImagePickerSection(
            key: _photoKey,
            initialImageUrl: _imageUrl,
            type: 'product',
            label: 'Take or choose a photo (optional)',
            onImageChanged: (url, publicId) => setState(() {
              _imageUrl = url;
              _imagePublicId = publicId;
            }),
          ),
          if (getIt<AuthService>().isLocalWorkspace &&
              _imageUrl != null &&
              !_imageUrl!.startsWith('http://') &&
              !_imageUrl!.startsWith('https://')) ...[
            const SizedBox(height: 10),
            Text(
              'The photo stays on this device unless you choose to send it to Axon AI to suggest the name and category.',
              style: TextStyle(color: palette.soft, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _aiLooking ? null : () => _identifyFromPhoto(_imageUrl!),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(_aiLooking ? 'Looking at the photo…' : 'Suggest with Axon AI'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 46),
                foregroundColor: palette.ink,
                side: BorderSide(color: palette.line),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _unitField(_UnitPriceTier tier) {
    final units = [
      ...businessLayoutUnits,
      if (!businessLayoutUnits.contains(tier.unit)) tier.unit,
    ];
    return DropdownButtonFormField<String>(
      initialValue: tier.unit,
      isExpanded: true,
      decoration: kitFieldDecoration(context, label: 'Sold per'),
      items: [
        for (final u in units)
          DropdownMenuItem(value: u, child: Text(u[0].toUpperCase() + u.substring(1))),
      ],
      onChanged: (value) => setState(() => tier.unit = value ?? tier.unit),
    );
  }

  Widget _openingStockField(SignInPalette palette, String unit) {
    void nudge(double by) {
      final current = double.tryParse(_stockController.text.trim()) ?? 0;
      final next = (current + by).clamp(0, 1e9).toDouble();
      final text = kitNumber(next);
      setState(() => _stockController.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ));
    }

    Widget step(IconData icon, String label, double by) => Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: () => nudge(by),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.line),
              ),
              child: Icon(icon, size: 20, color: palette.ink),
            ),
          ),
        );

    return TextFormField(
      controller: _stockController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
      decoration: kitFieldDecoration(
        context,
        label: 'On the shelf now',
        hint: '0',
        suffixText: unit,
      ).copyWith(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: step(Icons.remove_rounded, 'One less', -1),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 52),
        // An icon slot, not `suffix`: the field already has `suffixText` (the
        // unit), and declaring both fails an assertion and blanks the form.
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: step(Icons.add_rounded, 'One more', 1),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 52),
      ),
      validator: (v) => _validateNonNegativeNumber(v),
    );
  }

  Widget _moreDetailsRow(SignInPalette palette, List<dynamic>? categories) {
    final parts = <String>[];
    final code = _skuController.text.trim();
    if (code.isNotEmpty) parts.add('Code $code');
    if (_selectedCategoryId != null && categories != null) {
      for (final c in categories) {
        if (c.id == _selectedCategoryId) {
          parts.add(c.name as String);
          break;
        }
      }
    }
    final extra = _unitPriceTiers.length - 1;
    if (extra > 0) parts.add('$extra more ${extra == 1 ? 'unit' : 'units'}');
    final low = _minStockController.text.trim();
    if (low.isNotEmpty && _trackInventory) parts.add('Warns below $low');
    return Semantics(
      button: true,
      label: 'More details',
      child: InkWell(
        onTap: _openMoreDetails,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('More details',
                        style: TextStyle(
                            color: palette.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      parts.isEmpty
                          ? 'Barcode, category, carton price, low stock level'
                          : parts.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.soft, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.soft),
            ],
          ),
        ),
      ),
    );
  }

  // ─── More details ─────────────────────────────────────────────────────

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (code == null || !mounted) return;
    setState(() => _skuController.text =
        code.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '').toUpperCase());
  }

  Future<void> _openMoreDetails() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => StatefulBuilder(
          builder: (ctx, setPage) => _buildMoreDetails(ctx, () {
            if (mounted) setState(() {});
            setPage(() {});
          }),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _buildMoreDetails(BuildContext ctx, VoidCallback refresh) {
    final palette = SignInPalette.of(ctx);
    final isLocal = getIt<AuthService>().isLocalWorkspace;
    final businessLayout = ref.read(businessLayoutProvider);
    final primary = _unitPriceTiers[0];
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        elevation: 0,
        title: Text('More details',
            style: DesignType.display.copyWith(
                color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Form(
        key: _moreFormKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  TextFormField(
                    controller: _skuController,
                    style: TextStyle(color: palette.ink),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
                      LengthLimitingTextInputFormatter(50),
                    ],
                    decoration: kitFieldDecoration(
                      ctx,
                      label: businessLayout.productCodeLabel,
                      hint: businessLayout.productCodeHint,
                    ).copyWith(
                      suffixIcon: IconButton(
                        tooltip: 'Scan the barcode',
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        onPressed: () async {
                          await _scanBarcode();
                          refresh();
                        },
                      ),
                    ),
                    onChanged: (_) => refresh(),
                    validator: (value) {
                      final code = value?.trim() ?? '';
                      if (code.isNotEmpty && code.length < 3) {
                        return 'Enter at least 3 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  Consumer(builder: (context, ref, _) {
                    final categories = ref.watch(categoriesProvider);
                    return categories.when(
                      data: (list) {
                        final usable = list
                            .where((c) => c.isActive || c.id == _selectedCategoryId)
                            .toList();
                        return DropdownButtonFormField<String>(
                          initialValue: _selectedCategoryId,
                          isExpanded: true,
                          decoration:
                              kitFieldDecoration(ctx, label: 'Category (optional)'),
                          hint: const Text('Uncategorized'),
                          items: [
                            for (final c in usable)
                              DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                    c.isActive ? c.name : '${c.name} (inactive)'),
                              ),
                          ],
                          onChanged: (v) {
                            _selectedCategoryId = v;
                            refresh();
                          },
                        );
                      },
                      loading: () => _buildCategoryLoading(palette.isDark),
                      error: (e, _) => _buildCategoryError(palette.isDark),
                    );
                  }),
                  const SizedBox(height: 22),
                  Text('ALSO SOLD BY THE',
                      style: DesignType.numeric(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: palette.soft,
                          letterSpacing: 1.1)),
                  const SizedBox(height: 10),
                  for (var i = 1; i < _unitPriceTiers.length; i++) ...[
                    _extraTierCard(ctx, palette, i, refresh),
                    const SizedBox(height: 10),
                  ],
                  OutlinedButton.icon(
                    onPressed: () {
                      _unitPriceTiers.add(_UnitPriceTier(unit: _getNextUnit()));
                      refresh();
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(_unitPriceTiers.length == 1
                        ? 'Also sell it by the carton or pack'
                        : 'Add another unit'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: palette.ink,
                      side: BorderSide(color: palette.line),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                  ),
                  if (_trackInventory) ...[
                    const SizedBox(height: 22),
                    _buildReorderPointSection(palette, ctx, refresh, primary.unit),
                  ],
                  const SizedBox(height: 14),
                  _SwitchCard(
                    palette: palette,
                    title: 'Sell partial amounts',
                    subtitle: 'For kilos and litres, such as 0.5 ${primary.unit}.',
                    value: _allowFractions,
                    onChanged: (value) {
                      _allowFractions = value;
                      refresh();
                    },
                  ),
                  if (!isLocal) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _minPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: palette.ink),
                      decoration: kitFieldDecoration(
                        ctx,
                        label: 'Lowest price you will accept (optional)',
                        prefixText: 'KES ',
                        helper:
                            'Per ${primary.unit}. Cashiers cannot sell below this without a manager.',
                      ),
                      validator: _validateNonNegativeNumber,
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    style: TextStyle(color: palette.ink),
                    decoration: kitFieldDecoration(ctx, label: 'Description (optional)'),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                  ),
                  if (_industryFields.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text('${businessLayout.productSingular.toUpperCase()} DETAILS',
                        style: DesignType.numeric(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: palette.soft,
                            letterSpacing: 1.1)),
                    const SizedBox(height: 10),
                    for (final field in _industryFields) ...[
                      TextFormField(
                        controller: _industryFieldControllers[field.key],
                        style: TextStyle(color: palette.ink),
                        decoration: kitFieldDecoration(
                          ctx,
                          label: '${field.label} (optional)',
                          hint: field.hint,
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 120,
                      ),
                      const SizedBox(height: 6),
                    ],
                  ],
                ],
              ),
            ),
            PinnedActionBar(
              child: SignInButton(
                label: 'Done',
                onPressed: () {
                  if (_moreFormKey.currentState?.validate() ?? true) {
                    Navigator.of(ctx).pop();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _extraTierCard(
      BuildContext ctx, SignInPalette palette, int index, VoidCallback refresh) {
    final tier = _unitPriceTiers[index];
    final base = _unitPriceTiers[0];
    final qty = double.tryParse(tier.qtyController.text.trim());
    final price = double.tryParse(tier.priceController.text.trim());
    final basePrice = double.tryParse(base.priceController.text.trim());
    String? maths;
    if (qty != null && qty > 0 && price != null && basePrice != null) {
      final single = qty * basePrice;
      final diff = single - price;
      final each = '${kitNumber(qty)} ${base.unit} at ${kitNumber(basePrice)}';
      maths = diff > 0
          ? '$each would be KES ${kitNumber(single)}. This price gives KES ${kitNumber(diff)} off.'
          : diff < 0
              ? '$each would be KES ${kitNumber(single)}. This price is KES ${kitNumber(-diff)} more.'
              : 'Same as buying them one by one.';
    }
    final units = [
      ...businessLayoutUnits,
      if (!businessLayoutUnits.contains(tier.unit)) tier.unit,
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  initialValue: tier.unit,
                  isExpanded: true,
                  decoration: kitFieldDecoration(ctx, label: 'Unit'),
                  items: [
                    for (final u in units)
                      DropdownMenuItem(
                          value: u, child: Text(u[0].toUpperCase() + u.substring(1))),
                  ],
                  onChanged: (v) {
                    tier.unit = v ?? tier.unit;
                    refresh();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: TextFormField(
                  controller: tier.qtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
                  decoration: kitFieldDecoration(ctx,
                      label: '${base.unit.endsWith('s') ? base.unit : '${base.unit}s'} in it', hint: '12'),
                  onChanged: (_) => refresh(),
                  validator: _validatePositiveNumber,
                ),
              ),
              IconButton(
                tooltip: 'Remove this unit',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 56),
                icon: const Icon(Icons.delete_outline_rounded,
                    color: DesignColors.error),
                onPressed: () {
                  tier.priceController.dispose();
                  tier.qtyController.dispose();
                  _unitPriceTiers.removeAt(index);
                  refresh();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: tier.priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
            decoration: kitFieldDecoration(ctx,
                label: '${tier.unit[0].toUpperCase()}${tier.unit.substring(1)} price',
                hint: '0',
                prefixText: 'KES '),
            onChanged: (_) => refresh(),
            validator: (v) => _validateNonNegativeNumber(v, required: true),
          ),
          if (maths != null) ...[
            const SizedBox(height: 8),
            Text(maths,
                style: TextStyle(color: palette.soft, fontSize: 12.5, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _buildReorderPointSection(SignInPalette palette, BuildContext ctx,
      VoidCallback refresh, String baseUnit) {
    final tierUnits = _unitPriceTiers.map((t) => t.unit).toList();
    if (!tierUnits.contains(_minStockUnit)) _minStockUnit = tierUnits.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: TextFormField(
            controller: _minStockController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
            decoration: kitFieldDecoration(
              ctx,
              label: 'Warn me when fewer than',
              hint: '10',
              helper: 'Sell stops at zero.',
            ),
            onChanged: (_) => refresh(),
            validator: _validateNonNegativeNumber,
          ),
        ),
        if (tierUnits.length > 1) ...[
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: _minStockUnit,
              isExpanded: true,
              decoration: kitFieldDecoration(ctx, label: 'In'),
              items: [
                for (final u in tierUnits) DropdownMenuItem(value: u, child: Text(u)),
              ],
              onChanged: (v) {
                if (v != null) {
                  _minStockUnit = v;
                  refresh();
                }
              },
            ),
          ),
        ] else ...[
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(baseUnit,
                style: TextStyle(color: palette.soft, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  /// Asks before saving a price that loses money on every sale.
  Future<bool> _confirmBelowCost(double cost, double price, String unit) async {
    final palette = SignInPalette.of(context);
    final loss = cost - price;
    final go = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: palette.line, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Price is below what you paid',
                  style: DesignType.display.copyWith(
                      color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'KES ${kitNumber(price)} is below the KES ${kitNumber(cost)} you paid last time. You lose KES ${kitNumber(loss)} on each $unit.',
                style: TextStyle(color: palette.soft, fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 18),
              SignInButton(
                  label: 'Check the price', onPressed: () => Navigator.pop(sheet, false)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(sheet, true),
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 46), foregroundColor: palette.soft),
                child: const Text('Save it anyway',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
    return go ?? false;
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

  Future<void> _saveProduct({bool another = false}) async {
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

      // Selling below what the shop last paid loses money on every sale. Ask
      // once, plainly, and let the shop decide.
      final lastCost = widget.product?.costPrice;
      if (lastCost != null && lastCost > 0 && primaryPrice < lastCost) {
        if (!await _confirmBelowCost(lastCost, primaryPrice, primary.unit)) {
          if (mounted) setState(() => _isSaving = false);
          return;
        }
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
        // The starting count. A counted product always gets a stock row, even
        // at zero, so Sell says "out of stock" instead of "not found".
        String? stockProblem;
        if (_trackInventory) {
          try {
            final opening = isEditing
                ? 0.0
                : (double.tryParse(_stockController.text.trim()) ?? 0.0);
            if (opening > 0) {
              await database.recordLocalStockReceipt(
                receiptId: 'opening-$productId',
                productId: productId,
                branchId: branchId,
                batches: [
                  {
                    'quantity': opening,
                    'unit': primary.unit,
                    'unitsPerQuantity': 1.0,
                    'notes': 'Opening stock',
                  },
                ],
                receivedAt: now,
              );
            } else if (await database.getProductStock(productId, branchId) ==
                null) {
              await database.upsertAuthoritativeStock(
                productId: productId,
                branchId: branchId,
                quantity: 0,
              );
            }
          } catch (_) {
            stockProblem =
                'Saved, but the starting count was not recorded. Use Receive stock on the product page.';
          }
        }
        if (!mounted) return;
        ref.invalidate(catalog_cache.filteredProductsProvider);
        ref.invalidate(catalog_cache.favoriteProductsProvider);
        ref.invalidate(catalog_cache.categoriesProvider);
        if (stockProblem != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(stockProblem)));
        }
        if (another) {
          _resetForNext();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved. Add the next one.')),
          );
          return;
        }
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

  /// Clears the form for the next product after "Save and add another". The
  /// category, unit and counting choice stay, because a shop adds similar
  /// products in a run.
  void _resetForNext() {
    setState(() {
      _nameController.clear();
      _skuController.clear();
      _descriptionController.clear();
      _minStockController.clear();
      _stockController.clear();
      for (final c in _industryFieldControllers.values) {
        c.clear();
      }
      final unit = _unitPriceTiers[0].unit;
      for (final tier in _unitPriceTiers) {
        tier.priceController.dispose();
        tier.qtyController.dispose();
      }
      _unitPriceTiers = [_UnitPriceTier(unit: unit)];
      _minStockUnit = unit;
      _imageUrl = null;
      _imagePublicId = null;
      _aiSuggestion = null;
      _aiMessage = null;
      _photoKey = UniqueKey();
    });
    _formKey.currentState?.reset();
  }

  String _productSaveErrorMessage(Object error) {
    final reason = apiErrorMessage(error);
    if (reason == 'Something went wrong. Please try again.') {
      return 'Could not save product. Please check the details and try again.';
    }
    return 'Could not save product: $reason';
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

/// A yes/no choice on its own card, with one plain sentence under it.
class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final SignInPalette palette;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: palette.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: palette.soft, fontSize: 12.5, height: 1.35)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: DesignColors.accent,
          ),
        ],
      ),
    );
  }
}

/// Opens the add or edit form as its own full screen, above the bottom bar.
Future<void> openProductForm(
  BuildContext context, {
  Product? product,
  required String entityLabel,
  String? initialName,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ProductFormPage(
        product: product,
        entityLabel: entityLabel,
        initialName: initialName,
      ),
    ),
  );
}

class ProductFormPage extends StatelessWidget {
  const ProductFormPage({
    super.key,
    this.product,
    required this.entityLabel,
    this.initialName,
  });

  final Product? product;
  final String entityLabel;
  final String? initialName;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        elevation: 0,
        title: Text(
          product == null
              ? 'New ${entityLabel.toLowerCase()}'
              : 'Edit ${entityLabel.toLowerCase()}',
          style: DesignType.display.copyWith(
              color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AddEditProductSheet(
          product: product,
          entityLabel: entityLabel,
          initialName: initialName,
        ),
      ),
    );
  }
}
