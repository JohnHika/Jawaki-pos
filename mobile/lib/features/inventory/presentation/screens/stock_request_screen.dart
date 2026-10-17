import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/services/stock_request_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/load_error.dart';
import '../../../../core/widgets/form_kit.dart';
import '../widgets/product_picker_dialog.dart';

/// Stock Request Screen - For cashiers/sellers to request stock from managers
class StockRequestScreen extends ConsumerStatefulWidget {
  final String? productId;
  final String? productName;

  const StockRequestScreen({
    super.key,
    this.productId,
    this.productName,
  });

  @override
  ConsumerState<StockRequestScreen> createState() => _StockRequestScreenState();
}

class _StockRequestScreenState extends ConsumerState<StockRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();

  String? _selectedProductId;
  String? _selectedProductName;
  String _priority = 'normal';
  String _unit = 'piece';
  double? _onHand;
  bool _isLoading = false;
  final List<String> _images = [];
  bool _showSuccess = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.productId;
    _selectedProductName = widget.productName;
    _loadOnHand();
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      useRootNavigator: true,
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final image = await _imagePicker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
    );

    if (image == null || !mounted) return;
    setState(() => _images.add(image.path));
  }

  Widget _buildRequestImage(String image) {
    final isRemote =
        image.startsWith('http://') || image.startsWith('https://');
    final ImageProvider provider;
    if (isRemote) {
      provider = NetworkImage(image);
    } else {
      provider = FileImage(File(image));
    }

    return Image(
      image: provider,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.error),
    );
  }

  /// Uploads each locally-picked photo and returns the resulting URLs.
  /// Local file paths only exist on this device, so they must become
  /// real URLs before being sent to the backend for a manager on another
  /// device to review.
  Future<List<String>> _uploadImages() async {
    if (_images.isEmpty) return [];

    final apiClient = getIt<ApiClient>();
    final urls = <String>[];

    for (final imagePath in _images) {
      if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        urls.add(imagePath);
        continue;
      }
      final fileName = imagePath.split(Platform.pathSeparator).last;
      final result = await apiClient.uploadImage(
        filePath: imagePath,
        fileName: fileName,
        type: 'stock-request',
      );
      final url = result['url'] as String?;
      if (url != null) urls.add(url);
    }

    return urls;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedProductId == null) {
      showGlassSnackBar(
        context,
        'Please select a product',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = getIt<AuthService>();
      final stockRequestService = ref.read(stockRequestServiceProvider);

      final branchId = authService.branchId;
      if (branchId == null) {
        throw Exception('No branch ID found. Please log in again.');
      }

      // Photos are picked as local file paths, which only exist on this
      // device — upload each one so the manager reviewing the request
      // (on a different device) can actually see them.
      final uploadedImageUrls = await _uploadImages();

      await stockRequestService.createRequest(
        branchId: branchId,
        productId: _selectedProductId!,
        quantity: double.parse(_quantityController.text),
        unit: _unit,
        reason: _reasonController.text.trim().isEmpty
            ? null
            : _reasonController.text.trim(),
        priority: _priority.toUpperCase(),
        images: uploadedImageUrls.isEmpty ? null : uploadedImageUrls,
      );

      if (!mounted) return;

      setState(() => _showSuccess = true);

      // Auto-dismiss after showing success
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          context.pop(true);
        }
      });
    } catch (e) {
      if (!mounted) return;

      showGlassSnackBar(
        context,
        loadErrorSubtitle(e),
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandedAppBar(title: 'Request Stock'),
      body: PageContainer(
        child: _showSuccess ? _buildSuccessView() : _buildForm(),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Builder(builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final titleColor =
          isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
      final secondaryColor =
          isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: DesignColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusXxl),
                  border: Border.all(
                      color: DesignColors.success.withValues(alpha: 0.2)),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 64,
                  color: DesignColors.success,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Request sent',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your request for $_selectedProductName is with the manager for approval.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 14, color: secondaryColor, height: 1.4),
              ),
            ],
          ),
        ),
      );
    });
  }

  static const _priorities = <(String, String, Color)>[
    ('low', 'Low', DesignColors.info),
    ('normal', 'Normal', DesignColors.accent),
    ('high', 'High', DesignColors.warning),
    ('urgent', 'Urgent', DesignColors.error),
  ];

  static const _quickReasons = <String>[
    'Running low',
    'Out of stock',
    'Customer demand',
    'Restock the shelf',
  ];

  Widget _buildForm() {
    return Builder(builder: (context) {
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
      final quantity = double.tryParse(_quantityController.text.trim());
      final hasProduct = _selectedProductId != null;

      return Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product
                    Material(
                      color: surface,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusLg),
                        side: BorderSide(
                          color: hasProduct
                              ? DesignColors.brand.withValues(alpha: 0.35)
                              : border,
                        ),
                      ),
                      child: InkWell(
                        key: const ValueKey('pick-product'),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusLg),
                        onTap: _pickProduct,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: hasProduct
                                      ? DesignColors.brand
                                          .withValues(alpha: 0.1)
                                      : border.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(
                                      DesignSpacing.radiusMd),
                                ),
                                child: Icon(
                                  hasProduct
                                      ? Icons.inventory_2_rounded
                                      : Icons.search_rounded,
                                  color: hasProduct
                                      ? DesignColors.brand
                                      : tertiaryColor,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedProductName ??
                                          'Choose a product',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: hasProduct
                                            ? titleColor
                                            : secondaryColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      !hasProduct
                                          ? 'Tap to search your products'
                                          : (_onHand == null
                                              ? 'Tap to change'
                                              : 'You have ${kitCount(_onHand!, _unit)} now'),
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: hasProduct &&
                                                _onHand != null &&
                                                _onHand! <= 0
                                            ? DesignColors.error
                                            : tertiaryColor,
                                        fontWeight: hasProduct &&
                                                _onHand != null &&
                                                _onHand! <= 0
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: tertiaryColor, size: 22),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    // Quantity
                    TextFormField(
                      key: const ValueKey('request-quantity'),
                      controller: _quantityController,
                      onChanged: (_) => setState(() {}),
                      style: DesignType.numeric(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                      ),
                      decoration: kitFieldDecoration(
                        context,
                        label: 'How many do you need?',
                        hint: 'e.g. 24',
                        suffixText: _unit,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter how many you need';
                        }
                        final qty = double.tryParse(value.trim());
                        if (qty == null) return 'Numbers only';
                        if (qty <= 0) return 'Must be more than 0';
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    QuickAddChips(
                      amounts: const [5, 10, 20, 50],
                      onAdd: (n) {
                        kitAddToField(_quantityController, n);
                        setState(() {});
                      },
                    ),

                    const SizedBox(height: 24),

                    // Priority
                    const FormLabel('How urgent is it?'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (value, label, color) in _priorities)
                          ChoicePill(
                            key: ValueKey('priority-$value'),
                            label: label,
                            color: color,
                            selected: _priority == value,
                            onTap: () => setState(() => _priority = value),
                          ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Reason
                    const FormLabel('Why do you need it?', trailing: 'optional'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final reason in _quickReasons)
                          ChoicePill(
                            label: reason,
                            selected: _reasonController.text.trim() == reason,
                            onTap: () => setState(() {
                              _reasonController.text =
                                  _reasonController.text.trim() == reason
                                      ? ''
                                      : reason;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _reasonController,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: titleColor),
                      decoration: kitFieldDecoration(
                        context,
                        label: 'Add a note for the manager',
                        hint: 'Anything they should know',
                      ),
                      minLines: 2,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),

                    const SizedBox(height: 24),

                    // Photos
                    FormLabel('Photos', trailing: 'optional, ${_images.length} added'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final image in _images)
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  border: Border.all(color: border),
                                  borderRadius: BorderRadius.circular(
                                      DesignSpacing.radiusMd),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      DesignSpacing.radiusMd),
                                  child: _buildRequestImage(image),
                                ),
                              ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _images.remove(image)),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: DesignColors.error,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        InkWell(
                          key: const ValueKey('add-photo'),
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusMd),
                          onTap: _addPhoto,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius:
                                  BorderRadius.circular(DesignSpacing.radiusMd),
                              border: Border.all(color: border),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_outlined,
                                    color: secondaryColor, size: 22),
                                const SizedBox(height: 4),
                                Text('Add',
                                    style: TextStyle(
                                        color: secondaryColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A photo of the empty shelf helps the manager decide faster.',
                      style: TextStyle(fontSize: 12, color: tertiaryColor),
                    ),
                  ],
                ),
              ),
            ),
            PinnedActionBar(
              summary: (hasProduct && quantity != null && quantity > 0)
                  ? Text(
                      'Requesting ${kitCount(quantity, _unit)} of $_selectedProductName',
                      key: const ValueKey('request-summary'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    )
                  : null,
              child: GradientButton(
                label: 'Send Request',
                icon: Icons.send_rounded,
                onPressed: _isLoading ? null : _submitRequest,
                isLoading: _isLoading,
                height: 52,
                borderRadius: 14,
              ),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _pickProduct() async {
    final result = await showProductPicker(
      context,
      initialProductId: _selectedProductId,
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedProductId = result['id'];
      _selectedProductName = result['name'];
      _unit = result['unit'] ?? 'piece';
      _onHand = null;
    });
    _loadOnHand();
  }

  /// Tells the requester what is on the shelf now, so they ask for a sensible
  /// amount. Purely informational: a missing figure is simply not shown.
  Future<void> _loadOnHand() async {
    final productId = _selectedProductId;
    if (productId == null) return;
    try {
      final branchId = getIt<AuthService>().branchId;
      if (branchId == null) return;
      final db = getIt<AppDatabase>();
      final stock = await db.getProductStock(productId, branchId);
      final product = await db.getProduct(productId);
      if (mounted && productId == _selectedProductId) {
        setState(() {
          _onHand = stock?.quantity.toDouble();
          if (product != null) _unit = product.unit;
        });
      }
    } catch (_) {}
  }
}
