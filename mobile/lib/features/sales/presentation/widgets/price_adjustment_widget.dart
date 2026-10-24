import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_system.dart';

import '../providers/cart_provider.dart';
import '../../../../core/utils/format.dart';

/// Allows sellers to manually adjust a single cart line's price during
/// checkout. [productId] identifies the cart line (matches
/// `CartItem.productId`, which is what `CartNotifier.updateItemDiscount`
/// keys on).
class PriceAdjustmentWidget extends ConsumerStatefulWidget {
  final String productId;
  final double originalPrice;
  final double currentPrice;
  final String quantityLabel;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;

  const PriceAdjustmentWidget({
    super.key,
    required this.productId,
    required this.originalPrice,
    required this.currentPrice,
    required this.quantityLabel,
    this.onSave,
    this.onCancel,
  });

  @override
  ConsumerState<PriceAdjustmentWidget> createState() =>
      _PriceAdjustmentWidgetState();
}

class _PriceAdjustmentWidgetState extends ConsumerState<PriceAdjustmentWidget> {
  late final TextEditingController _priceController;
  late final TextEditingController _reasonController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.currentPrice.toStringAsFixed(2),
    );
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _priceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final cartIndex = cartState.items
        .indexWhere((item) => item.productId == widget.productId);
    if (cartIndex < 0) {
      return AlertDialog(
        title: const Text('Item removed'),
        content: const Text(
          'This item is no longer in the cart. Close this window and try again.',
        ),
        actions: [
          TextButton(
            onPressed: widget.onCancel ?? () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final cartItem = cartState.items[cartIndex];

    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Price Adjustment',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    tooltip: 'Cancel price change',
                    icon: const Icon(Icons.close),
                    onPressed: widget.onCancel ?? () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                cartItem.productName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: DesignColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Line quantity: ${widget.quantityLabel}',
                style: const TextStyle(
                  fontSize: 13,
                  color: DesignColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.attach_money,
                      size: 16, color: DesignColors.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                    'Original line total: ${formatMoney(widget.originalPrice)}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: DesignColors.textSecondary,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'New line total (KES)',
                  prefixIcon: const Icon(Icons.currency_exchange),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                  errorText: _errorMessage,
                  errorStyle: const TextStyle(fontSize: 12),
                ),
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'e.g., Promotion, Customer request, etc.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          widget.onCancel ?? () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusMd),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        final newPrice = double.tryParse(_priceController.text);
                        if (newPrice == null ||
                            !newPrice.isFinite ||
                            newPrice < 0) {
                          setState(() => _errorMessage =
                              'Enter a valid line total of KES 0 or more.');
                          return;
                        }
                        if (newPrice > widget.originalPrice) {
                          setState(() => _errorMessage =
                              'The adjusted total cannot exceed ${formatMoney(widget.originalPrice)}.');
                          return;
                        }

                        final originalCents =
                            (widget.originalPrice * 100).round();
                        final newPriceCents = (newPrice * 100).round();
                        if (newPriceCents > originalCents) {
                          setState(() => _errorMessage =
                              'The adjusted total cannot exceed ${formatMoney(widget.originalPrice)}.');
                          return;
                        }

                        final result =
                            ref.read(cartProvider.notifier).updateItemDiscount(
                                  widget.productId,
                                  (originalCents - newPriceCents) / 100,
                                  reason: _reasonController.text.trim(),
                                );
                        if (!result.success) {
                          setState(() => _errorMessage = result.message);
                          return;
                        }

                        widget.onSave?.call();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusMd),
                        ),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: const Text('Save Adjustment'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
