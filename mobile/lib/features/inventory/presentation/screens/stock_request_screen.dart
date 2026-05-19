import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/services/stock_request_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/design_system.dart';
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
  bool _isLoading = false;
  List<String> _images = [];
  bool _showSuccess = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.productId;
    _selectedProductName = widget.productName;
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
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

      await stockRequestService.createRequest(
        branchId: branchId,
        productId: _selectedProductId!,
        quantity: double.parse(_quantityController.text),
        unit: _unit,
        reason: _reasonController.text.trim().isEmpty
            ? null
            : _reasonController.text.trim(),
        priority: _priority.toUpperCase(),
        images: _images.isEmpty ? null : _images,
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
        'Error: ${e.toString()}',
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
        withScroll: true,
        child: _showSuccess ? _buildSuccessView() : _buildForm(),
      ),
    );
  }

  Widget _buildSuccessView() {
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
                borderRadius: BorderRadius.circular(24),
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
            const Text(
              'Request Submitted!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: DesignColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your stock request for $_selectedProductName has been sent to the manager for approval.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: DesignColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Stock Request',
            subtitle: 'Fill in the details to request stock',
            icon: Icons.add_shopping_cart_rounded,
          ),

          // Product Selection
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            borderRadius: 14,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onTap: () async {
              final result = await showProductPicker(
                context,
                initialProductId: _selectedProductId,
              );
              if (result != null) {
                setState(() {
                  _selectedProductId = result['id'];
                  _selectedProductName = result['name'];
                  _unit = result['unit'] ?? 'piece';
                });
              }
            },
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _selectedProductName != null
                        ? DesignColors.brand.withValues(alpha: 0.1)
                        : DesignColors.surfaceBorder.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _selectedProductName != null
                        ? Icons.inventory_2_rounded
                        : Icons.add_circle_outline_rounded,
                    color: _selectedProductName != null
                        ? DesignColors.brand
                        : DesignColors.textTertiary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedProductName ?? 'Select Product',
                        style: TextStyle(
                          color: _selectedProductName == null
                              ? DesignColors.textTertiary
                              : DesignColors.textPrimary,
                          fontWeight: _selectedProductName != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                          fontSize: 15,
                        ),
                      ),
                      if (_selectedProductId == null)
                        const Text(
                          'Tap to select a product',
                          style: TextStyle(
                            fontSize: 12,
                            color: DesignColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: DesignColors.textTertiary,
                  size: 20,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Quantity Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 14,
              tint: Colors.transparent,
              borderColor: DesignColors.surfaceBorder,
              child: TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  hintText: 'Enter quantity needed',
                  hintStyle: TextStyle(color: DesignColors.textTertiary),
                  labelStyle: const TextStyle(
                    color: DesignColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  suffixText: _unit,
                  suffixStyle: const TextStyle(
                    color: DesignColors.brand,
                    fontWeight: FontWeight.w600,
                  ),
                  filled: true,
                  fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.15),
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a quantity';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  if (double.parse(value) <= 0) {
                    return 'Quantity must be greater than 0';
                  }
                  return null;
                },
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Priority Selection
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 14,
              tint: Colors.transparent,
              borderColor: DesignColors.surfaceBorder,
              child: DropdownButtonFormField<String>(
                value: _priority,
                decoration: InputDecoration(
                  labelText: 'Priority',
                  labelStyle: const TextStyle(
                    color: DesignColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  filled: true,
                  fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.15),
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
                dropdownColor: Theme.of(context).brightness == Brightness.dark
                    ? DesignColors.darkSurface
                    : Colors.white,
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'normal', child: Text('Normal')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                  DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _priority = value);
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Reason Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 14,
              tint: Colors.transparent,
              borderColor: DesignColors.surfaceBorder,
              child: TextFormField(
                controller: _reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason (Optional)',
                  hintText: 'Why do you need this stock?',
                  hintStyle: TextStyle(color: DesignColors.textTertiary),
                  labelStyle: const TextStyle(
                    color: DesignColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  filled: true,
                  fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.15),
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
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Image Upload Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: DesignColors.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.image_rounded,
                            size: 18, color: DesignColors.info),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Photos (${_images.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: DesignColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (_images.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => _images.clear()),
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              color: DesignColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Optional: Add photos of empty shelves or low stock',
                    style: TextStyle(
                      fontSize: 12,
                      color: DesignColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Image Grid
                  if (_images.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _images.map((image) {
                        return Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: DesignColors.surfaceBorder),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _buildRequestImage(image),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _images.remove(image));
                                },
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
                        );
                      }).toList(),
                    ),

                  if (_images.isNotEmpty) const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _addPhoto,
                    icon: const Icon(Icons.add_a_photo_rounded),
                    label: Text(
                        _images.isEmpty ? 'Add Photo' : 'Add Another Photo'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: const BorderSide(color: DesignColors.surfaceBorder),
                      foregroundColor: DesignColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Submit Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GradientButton(
              label: 'Submit Request',
              icon: Icons.send_rounded,
              onPressed: _isLoading ? null : _submitRequest,
              isLoading: _isLoading,
              height: 52,
              borderRadius: 14,
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
