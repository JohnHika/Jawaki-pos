import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';

/// Product Picker Dialog - Select a product from the catalog
class ProductPickerDialog extends ConsumerStatefulWidget {
  final String? initialProductId;

  const ProductPickerDialog({super.key, this.initialProductId});

  @override
  ConsumerState<ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends ConsumerState<ProductPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;
  String? _selectedProductId;

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.initialProductId;
    _loadProducts();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);

    try {
      final db = getIt<AppDatabase>();
      final products = await db.getAllProducts();
      
      if (mounted) {
        setState(() {
          _products = products;
          _filteredProducts = products;
        });
      }
    } catch (e) {
      debugPrint('Error loading products: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading products: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products
            .where((p) =>
                p.name.toLowerCase().contains(query) ||
                p.sku.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.shopping_bag_outlined),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select Product',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search Bar
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by name or SKU...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Results count
            if (!_isLoading && _filteredProducts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_filteredProducts.length} product${_filteredProducts.length != 1 ? 's' : ''} found',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),

            // Product List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredProducts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isEmpty
                                    ? 'No products available'
                                    : 'No products found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              if (_searchController.text.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () => _searchController.clear(),
                                  child: const Text('Clear search'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = _filteredProducts[index];
                            final isSelected = product.id == _selectedProductId;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: isSelected ? 4 : 1,
                              color: isSelected
                                  ? Theme.of(context)
                                      .primaryColor
                                      .withOpacity(0.1)
                                  : null,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      Theme.of(context).primaryColor,
                                  child: Text(
                                    product.name[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(
                                  product.name,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('SKU: ${product.sku}'),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          '\$${product.price.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: Theme.of(context).primaryColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: product.isActive
                                                ? Colors.green.shade100
                                                : Colors.grey.shade300,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            product.isActive ? 'Active' : 'Inactive',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: product.isActive
                                                  ? Colors.green.shade800
                                                  : Colors.grey.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_circle,
                                        color: Theme.of(context).primaryColor,
                                      )
                                    : const Icon(Icons.chevron_right),
                                onTap: () {
                                  setState(() => _selectedProductId = product.id);
                                },
                              ),
                            );
                          },
                        ),
            ),

            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectedProductId == null
                        ? null
                        : () {
                            final selectedProduct = _products.firstWhere(
                              (p) => p.id == _selectedProductId,
                            );
                            Navigator.pop(context, {
                              'id': selectedProduct.id,
                              'name': selectedProduct.name,
                              'sku': selectedProduct.sku,
                              'unit': selectedProduct.unit,
                            });
                          },
                    child: const Text('Select'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper function to show the product picker
Future<Map<String, dynamic>?> showProductPicker(
  BuildContext context, {
  String? initialProductId,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => ProductPickerDialog(
      initialProductId: initialProductId,
    ),
  );
}
