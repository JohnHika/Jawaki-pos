import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/stock_request_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/di/injection.dart';
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

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.productId;
    _selectedProductName = widget.productName;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product')),
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
        reason: _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
        priority: _priority.toUpperCase(),
        images: _images.isEmpty ? null : _images,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock request submitted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      context.pop(true); // Return true to indicate success
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
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
      appBar: AppBar(
        title: const Text('Request Stock'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Product Selection
            Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2),
                title: Text(
                  _selectedProductName ?? 'Select Product',
                  style: TextStyle(
                    color: _selectedProductName == null
                        ? Theme.of(context).hintColor
                        : null,
                  ),
                ),
                subtitle: _selectedProductId == null
                    ? const Text('Tap to select a product')
                    : null,
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
              ),
            ),

            const SizedBox(height: 16),

            // Quantity Input
            TextFormField(
              controller: _quantityController,
              decoration: InputDecoration(
                labelText: 'Quantity',
                hintText: 'Enter quantity needed',
                border: const OutlineInputBorder(),
                suffixText: _unit,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

            const SizedBox(height: 16),

            // Priority Selection
            DropdownButtonFormField<String>(
              value: _priority,
              decoration: const InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
              ),
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

            const SizedBox(height: 16),

            // Reason Input
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (Optional)',
                hintText: 'Why do you need this stock?',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),

            const SizedBox(height: 16),

            // Image Upload Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.image, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Photos (${_images.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        if (_images.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => setState(() => _images.clear()),
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('Clear'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Optional: Add photos of empty shelves or low stock',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    
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
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    image,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.error),
                                  ),
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
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),

                    if (_images.isEmpty)
                      OutlinedButton.icon(
                        onPressed: () {
                          // TODO: Implement image picker
                          // final result = await ImagePicker().pickImage(source: ImageSource.camera);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Image upload coming soon')),
                          );
                        },
                        icon: const Icon(Icons.add_a_photo),
                        label: const Text('Add Photo'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Submit Button
            FilledButton(
              onPressed: _isLoading ? null : _submitRequest,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }
}
