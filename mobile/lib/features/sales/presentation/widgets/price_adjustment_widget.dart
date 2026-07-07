import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/cart_provider.dart';

/// Allows sellers to manually adjust a single cart line's price during
/// checkout. [productId] identifies the cart line (matches
/// `CartItem.productId`, which is what `CartNotifier.updateItemDiscount`
/// keys on).
class PriceAdjustmentWidget extends ConsumerStatefulWidget {
  final String productId;
  final double originalPrice;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;

  const PriceAdjustmentWidget({
    super.key,
    required this.productId,
    required this.originalPrice,
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
      text: widget.originalPrice.toStringAsFixed(0),
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
    final cartItem = cartState.items.firstWhere(
      (item) => item.productId == widget.productId,
      orElse: () => throw Exception('Item not found'),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.attach_money, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Original: KES ${widget.originalPrice.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'New Price (KES)',
                  prefixIcon: const Icon(Icons.currency_exchange),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
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
                    borderRadius: BorderRadius.circular(12),
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
                          borderRadius: BorderRadius.circular(12),
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
                        if (newPrice != null && newPrice >= 0) {
                          ref
                              .read(cartProvider.notifier)
                              .updateItemDiscount(
                                widget.productId,
                                widget.originalPrice - newPrice,
                                reason: _reasonController.text.trim(),
                              );

                          widget.onSave?.call();
                          Navigator.pop(context);
                        } else {
                          setState(
                            () => _errorMessage = 'Please enter a valid price',
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
