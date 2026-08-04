import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../widgets/unit_selector_widget.dart';
import '../../../../core/providers/api_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/design_system.dart';

/// Enhanced Batch Receive Screen with Multi-Unit Support
/// Supervisors can receive stock in cartons/boxes and auto-convert to pieces
class BatchReceiveScreen extends ConsumerStatefulWidget {
  final String? productId;
  final String? productName;
  final String? branchId;

  const BatchReceiveScreen({
    super.key,
    this.productId,
    this.productName,
    this.branchId,
  });

  @override
  ConsumerState<BatchReceiveScreen> createState() => _BatchReceiveScreenState();
}

class _BatchReceiveScreenState extends ConsumerState<BatchReceiveScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<BatchEntry> _batches = [];
  bool _isLoading = false;
  bool _isLoadingConfig = true;
  String? _resolvedProductName;

  // Product unit configuration - loaded from API
  UnitConfig? _unitConfig;

  @override
  void initState() {
    super.initState();
    _resolvedProductName = widget.productName;
    // If no product specified, show error
    if (widget.productId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showGlassSnackBar(
            context,
            'Please select a product first',
            icon: Icons.error_outline_rounded,
            color: DesignColors.error,
          );
          Navigator.of(context).pop();
        }
      });
      return;
    }
    _loadProductConfig();
  }

  Future<void> _loadProductConfig() async {
    if (widget.productId == null) return;

    try {
      final apiClient = ref.read(apiClientProvider);
      final product = await apiClient.getProduct(widget.productId!);

      if (mounted) {
        final rawTiers = product['pricingTiers'];
        final extraTiers = <UnitOption>[];
        if (rawTiers is List) {
          for (final tier in rawTiers) {
            if (tier is! Map) continue;
            final unit = tier['unit']?.toString();
            final qty = (tier['quantityPerUnit'] as num?)?.toDouble();
            if (unit == null || qty == null) continue;
            extraTiers.add(UnitOption(name: unit, conversionFactor: qty));
          }
        }
        setState(() {
          _resolvedProductName =
              product['name']?.toString() ?? _resolvedProductName;
          _unitConfig = UnitConfig(
            baseUnit: product['unit'] ?? 'piece',
            extraTiers: extraTiers,
          );
          _isLoadingConfig = false;
        });
        _ensureInitialBatch();
      }
    } catch (e) {
      final localProduct = await getIt<AppDatabase>().getProduct(
        widget.productId!,
      );
      final localTiers = await getIt<AppDatabase>()
          .getPricingTiersForProduct(widget.productId!);
      if (mounted) {
        setState(() {
          _resolvedProductName = localProduct?.name ?? _resolvedProductName;
          _unitConfig = UnitConfig(
            baseUnit: localProduct?.unit ?? 'piece',
            extraTiers: localTiers
                .map((t) => UnitOption(
                      name: t.unit,
                      conversionFactor: t.quantityPerUnit,
                    ))
                .toList(),
          );
          _isLoadingConfig = false;
        });
        _ensureInitialBatch();
      }
      debugPrint('Error loading product config: $e');
    }
  }

  void _ensureInitialBatch() {
    if (_batches.isEmpty && _unitConfig != null) {
      _addBatch();
    }
  }

  void _addBatch() {
    if (_unitConfig == null) return;

    setState(() {
      _batches.add(
        BatchEntry(
          quantityController: TextEditingController(),
          costPriceController: TextEditingController(),
          notesController: TextEditingController(),
          supplierRefController: TextEditingController(),
          selectedUnit: _unitConfig!.baseUnit,
        ),
      );
    });
  }

  void _removeBatch(int index) {
    if (_batches.length == 1) {
      showGlassSnackBar(
        context,
        'At least one batch is required',
        icon: Icons.info_outline_rounded,
        color: DesignColors.warning,
      );
      return;
    }

    setState(() {
      _batches[index].dispose();
      _batches.removeAt(index);
    });
  }

  Future<void> _submitBatches() async {
    if (!_formKey.currentState!.validate()) return;

    if (_batches.isEmpty) {
      showGlassSnackBar(
        context,
        'Please add at least one batch',
        icon: Icons.error_outline_rounded,
        color: DesignColors.warning,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Prepare batches for API
      final batchesData = _batches.map((batch) {
        final quantity = double.parse(batch.quantityController.text);
        final unitOption = _unitConfig!.availableUnits.firstWhere(
          (u) => u.name == batch.selectedUnit,
          orElse: () =>
              UnitOption(name: batch.selectedUnit, conversionFactor: 1.0),
        );
        final isBaseUnit = batch.selectedUnit == _unitConfig!.baseUnit;

        return {
          'quantity': quantity,
          'unit': batch.selectedUnit,
          if (!isBaseUnit) 'unitsPerQuantity': unitOption.conversionFactor,
          'expiryDate': batch.expiryDate?.toIso8601String(),
          'manufactureDate': batch.manufactureDate?.toIso8601String(),
          'costPrice': batch.costPriceController.text.isEmpty
              ? null
              : double.parse(batch.costPriceController.text),
          'supplierRef': batch.supplierRefController.text.isEmpty
              ? null
              : batch.supplierRefController.text,
          'notes': batch.notesController.text.isEmpty
              ? null
              : batch.notesController.text,
        };
      }).toList();

      // Call API to receive batches
      final apiClient = ref.read(apiClientProvider);
      final authService = getIt<AuthService>();
      final branchId = widget.branchId ?? authService.branchId;

      if (branchId == null || widget.productId == null) {
        throw Exception('Missing branch ID or product ID');
      }

      final result = await apiClient.receiveBatches({
        'branchId': branchId,
        'productId': widget.productId!,
        'batches': batchesData,
      });

      // Inventory and product details render from Drift. Update that cache
      // before returning so a successful receipt is visible immediately.
      final db = getIt<AppDatabase>();
      final existingStock =
          await db.getProductStock(widget.productId!, branchId);
      final currentQuantity = (result['currentQuantity'] as num?)?.toDouble() ??
          ((existingStock?.quantity ?? 0) +
              ((result['totalQuantity'] as num?)?.toDouble() ?? 0));
      final receivedUnits = (result['receivedUnits'] as List?)
              ?.whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList() ??
          batchesData;
      final receiptMetadata = result['receiptMetadata'] is Map
          ? Map<String, dynamic>.from(result['receiptMetadata'] as Map)
          : null;
      final lastUnit = receivedUnits.isEmpty ? null : receivedUnits.last;
      final preferredUnit =
          receiptMetadata?['unit']?.toString() ?? lastUnit?['unit']?.toString();
      final unitsPerQuantity =
          (receiptMetadata?['unitsPerQuantity'] as num?)?.toDouble() ??
              (lastUnit?['unitsPerQuantity'] as num?)?.toDouble() ??
              1;
      final samePackaging = lastUnit != null &&
          receivedUnits.every(
            (entry) =>
                entry['unit']?.toString() == preferredUnit &&
                ((entry['unitsPerQuantity'] as num?)?.toDouble() ?? 1) ==
                    unitsPerQuantity,
          );
      final receivedQuantity =
          (receiptMetadata?['quantity'] as num?)?.toDouble() ??
              (samePackaging
                  ? receivedUnits.fold<double>(
                      0,
                      (sum, entry) =>
                          sum + ((entry['quantity'] as num?)?.toDouble() ?? 0),
                    )
                  : (lastUnit?['quantity'] as num?)?.toDouble());

      await db.upsertAuthoritativeStock(
        productId: widget.productId!,
        branchId: branchId,
        quantity: currentQuantity,
        displayUnit: preferredUnit,
        displayQuantityPerUnit: unitsPerQuantity,
        lastReceivedQuantity: receivedQuantity,
        lastReceivedAt: DateTime.now(),
      );

      if (!mounted) return;

      final createdBatches = (result['batches'] as List?) ?? const [];
      final batchNumbers = createdBatches
          .map((b) => (b as Map)['batchNumber']?.toString())
          .whereType<String>()
          .toList();

      String message;
      if (batchNumbers.length == 1) {
        message = 'Received — Batch: ${batchNumbers.first}';
      } else if (batchNumbers.length > 1) {
        final shown = batchNumbers.take(3).join(', ');
        final remaining = batchNumbers.length - 3;
        message = remaining > 0
            ? 'Received batches: $shown and $remaining more'
            : 'Received batches: $shown';
      } else {
        message = 'Batches received successfully';
      }

      showGlassSnackBar(
        context,
        message,
        icon: Icons.check_circle_rounded,
        color: DesignColors.success,
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      showGlassSnackBar(
        context,
        _userFacingError(e),
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
  void dispose() {
    for (var batch in _batches) {
      batch.dispose();
    }
    super.dispose();
  }

  /// Short, user-readable error message. Never dumps the raw DioException
  /// text into the snackbar.
  String _userFacingError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      final serverMessage = data is Map && data['message'] != null
          ? data['message'].toString()
          : null;

      switch (status) {
        case 400:
          return serverMessage ?? 'Check the entered details and try again.';
        case 401:
          return 'Session expired. Please log in again.';
        case 403:
          return 'You do not have permission to receive stock.';
        case 404:
          return serverMessage ?? 'Product or branch not found.';
        case 409:
          return 'Batch number conflict. Please try again.';
        case 422:
          return serverMessage ?? 'Some values are invalid. Please review.';
      }

      if (status != null && status >= 500) {
        return 'Server error. Please try again in a moment.';
      }

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return 'Connection timed out. Check your network.';
        case DioExceptionType.connectionError:
          return 'No internet connection.';
        default:
          break;
      }
    }

    final message = error.toString();
    if (message.contains('Missing branch ID') ||
        message.contains('product ID')) {
      return 'Missing product or branch information.';
    }
    return 'Could not receive stock. Please try again.';
  }

  /// Shared field decoration so every TextFormField in this form picks up
  /// the same theme-aware fill/label/hint colors instead of each one
  /// hardcoding a light-only palette.
  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String labelText,
    String? hintText,
    String? prefixText,
    IconData? prefixIcon,
    String? helperText,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final borderColor =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final fill = isDark
        ? DesignColors.darkSurfaceElevated
        : DesignColors.surfaceBorder.withValues(alpha: 0.15);

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      helperStyle: TextStyle(color: tertiaryColor, fontSize: 12),
      hintStyle: TextStyle(color: tertiaryColor),
      labelStyle: TextStyle(color: secondaryColor, fontWeight: FontWeight.w500),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      prefixText: prefixText,
      prefixStyle: prefixText != null
          ? TextStyle(color: secondaryColor, fontWeight: FontWeight.w600)
          : null,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: tertiaryColor, size: 20)
          : null,
      filled: true,
      fillColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DesignColors.brand, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DesignColors.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DesignColors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingConfig || _unitConfig == null) {
      return const Scaffold(
        appBar: BrandedAppBar(title: 'Receive Stock'),
        body: Center(
          child: CircularProgressIndicator(color: DesignColors.brand),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Receive Stock',
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DesignColors.brand.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.add_circle_outline_rounded,
                color: DesignColors.brand,
                size: 20,
              ),
            ),
            tooltip: 'Add another batch',
            onPressed: _addBatch,
          ),
        ],
      ),
      body: PageContainer(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Product Info Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surface,
                    border: Border.all(
                        color: DesignColors.brand.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: DesignColors.brand.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.inventory_2_rounded,
                              color: DesignColors.brand,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _resolvedProductName ?? 'Selected Product',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: titleColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Base Unit: ${_unitConfig?.baseUnit ?? 'N/A'}',
                                  style: TextStyle(
                                      fontSize: 13, color: secondaryColor),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_unitConfig != null &&
                          _unitConfig!.availableUnits.length > 1) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _unitConfig!.availableUnits
                              .where((u) => u.conversionFactor != 1.0)
                              .map(
                                (unit) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: DesignColors.brand.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: DesignColors.brand.withValues(
                                        alpha: 0.15,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    '1 ${unit.name} = ${unit.conversionFactor} ${_unitConfig!.baseUnit}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: DesignColors.brand,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Batch List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _batches.length,
                  itemBuilder: (context, index) {
                    return _buildBatchCard(index);
                  },
                ),
              ),

              // Bottom Submit Section
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Summary
                      if (_batches.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Batches:',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: secondaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${_batches.length}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: titleColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Submit Button
                      GradientButton(
                        label: 'Receive Batches',
                        icon: Icons.check_rounded,
                        onPressed: _isLoading ? null : _submitBatches,
                        isLoading: _isLoading,
                        height: 52,
                        borderRadius: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatchCard(int index) {
    final batch = _batches[index];
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration:
            BoxDecoration(color: surface, border: Border.all(color: border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with batch number and delete button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: DesignColors.brand,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Batch ${index + 1}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const Spacer(),
                if (_batches.length > 1)
                  GestureDetector(
                    onTap: () => _removeBatch(index),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: DesignColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: DesignColors.error,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Quantity with Unit Selector
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: batch.quantityController,
                    style: DesignType.numeric(
                      fontSize: 18,
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _fieldDecoration(
                      context,
                      labelText: 'Quantity *',
                      hintText: 'Enter quantity',
                      helperText: 'How many units are you receiving?',
                      prefixIcon: Icons.numbers_rounded,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      if (double.tryParse(value) == null) {
                        return 'Invalid';
                      }
                      if (double.parse(value) <= 0) {
                        return 'Must be > 0';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? DesignColors.darkSurfaceElevated
                          : DesignColors.surfaceBorder.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border, width: 1),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: batch.selectedUnit,
                        isExpanded: true,
                        dropdownColor:
                            isDark ? DesignColors.darkSurface : Colors.white,
                        icon: Icon(Icons.expand_more_rounded,
                            color: tertiaryColor),
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        items: _unitConfig!.availableUnits.map((unit) {
                          return DropdownMenuItem(
                            value: unit.name,
                            child: Text(unit.name),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => batch.selectedUnit = value);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Conversion Preview
            if (batch.quantityController.text.isNotEmpty &&
                _unitConfig != null &&
                batch.selectedUnit != _unitConfig!.baseUnit) ...[
              const SizedBox(height: 12),
              _buildConversionPreview(batch),
            ],

            const SizedBox(height: 14),

            // Expiry Date
            InkWell(
              onTap: () => _selectDate(context, batch, isExpiry: true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceBorder.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        color: tertiaryColor, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Expiry Date',
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            batch.expiryDate == null
                                ? 'Select date'
                                : DateFormat(
                                    'MMM d, yyyy',
                                  ).format(batch.expiryDate!),
                            style: TextStyle(
                              color: batch.expiryDate == null
                                  ? tertiaryColor
                                  : titleColor,
                              fontWeight: batch.expiryDate != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: tertiaryColor, size: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Collapsible Additional Details
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(
                  'Additional Details (Optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: secondaryColor,
                  ),
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 12),
                iconColor: tertiaryColor,
                collapsedIconColor: tertiaryColor,
                children: [
                  // Manufacture Date
                  InkWell(
                    onTap: () => _selectDate(context, batch, isExpiry: false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? DesignColors.darkSurfaceElevated
                            : DesignColors.surfaceBorder
                                .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_rounded,
                              color: tertiaryColor, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Manufacture Date',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: secondaryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  batch.manufactureDate == null
                                      ? 'Select date'
                                      : DateFormat(
                                          'MMM d, yyyy',
                                        ).format(batch.manufactureDate!),
                                  style: TextStyle(
                                    color: batch.manufactureDate == null
                                        ? tertiaryColor
                                        : titleColor,
                                    fontWeight: batch.manufactureDate != null
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: tertiaryColor, size: 20),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Cost Price
                  TextFormField(
                    controller: batch.costPriceController,
                    style: TextStyle(color: titleColor),
                    decoration: _fieldDecoration(
                      context,
                      labelText:
                          'Cost Price per ${_unitConfig?.baseUnit ?? 'unit'}',
                      prefixText: 'KES ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Supplier Reference
                  TextFormField(
                    controller: batch.supplierRefController,
                    style: TextStyle(color: titleColor),
                    decoration: _fieldDecoration(
                      context,
                      labelText: 'Supplier Reference / Invoice #',
                      hintText: 'e.g., INV-001',
                      prefixIcon: Icons.receipt_rounded,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Notes
                  TextFormField(
                    controller: batch.notesController,
                    style: TextStyle(color: titleColor),
                    decoration: _fieldDecoration(
                      context,
                      labelText: 'Notes',
                      hintText: 'Any additional notes...',
                      prefixIcon: Icons.notes_rounded,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversionPreview(BatchEntry batch) {
    final qty = double.tryParse(batch.quantityController.text);
    if (qty == null) return const SizedBox.shrink();

    final unitOption = _unitConfig!.availableUnits.firstWhere(
      (u) => u.name == batch.selectedUnit,
      orElse: () => UnitOption(name: batch.selectedUnit, conversionFactor: 1.0),
    );

    final baseQty = qty * unitOption.conversionFactor;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DesignColors.brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesignColors.brand.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calculate_rounded,
            size: 18,
            color: DesignColors.brand,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '= $baseQty ${_unitConfig!.baseUnit}${baseQty > 1 ? 's' : ''}',
              style: const TextStyle(
                fontSize: 14,
                color: DesignColors.brand,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(
    BuildContext context,
    BatchEntry batch, {
    required bool isExpiry,
  }) async {
    final initialDate = isExpiry ? batch.expiryDate : batch.manufactureDate;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: isExpiry ? DateTime.now() : DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(
                    primary: DesignColors.accent,
                    onPrimary: Colors.black,
                    surface: DesignColors.darkSurface,
                  )
                : const ColorScheme.light(
                    primary: DesignColors.accent,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                  ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() {
        if (isExpiry) {
          batch.expiryDate = date;
        } else {
          batch.manufactureDate = date;
        }
      });
    }
  }
}

/// Batch Entry Data Model
class BatchEntry {
  final TextEditingController quantityController;
  final TextEditingController costPriceController;
  final TextEditingController notesController;
  final TextEditingController supplierRefController;
  String selectedUnit;
  DateTime? expiryDate;
  DateTime? manufactureDate;

  BatchEntry({
    required this.quantityController,
    required this.costPriceController,
    required this.notesController,
    required this.supplierRefController,
    required this.selectedUnit,
    this.expiryDate,
    this.manufactureDate,
  });

  void dispose() {
    quantityController.dispose();
    costPriceController.dispose();
    notesController.dispose();
    supplierRefController.dispose();
  }
}
