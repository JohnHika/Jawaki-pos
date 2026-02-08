import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

const _uuid = Uuid();

// Providers for the products screen
final _categoriesProvider = StreamProvider<List<Category>>((ref) {
  return getIt<AppDatabase>().watchAllCategories();
});

final _productsProvider = StreamProvider<List<Product>>((ref) {
  return getIt<AppDatabase>().watchAllProducts();
});

final _selectedCategoryFilterProvider = StateProvider<String?>((ref) => null);
final _searchQueryProvider = StateProvider<String>((ref) => '');

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(_categoriesProvider);
    final productsAsync = ref.watch(_productsProvider);
    final selectedCategory = ref.watch(_selectedCategoryFilterProvider);
    final searchQuery = ref.watch(_searchQueryProvider);
    final perms = ref.watch(permissionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Catalog'),
        actions: [
          if (perms.canEditProducts)
            IconButton(
              icon: const Icon(Icons.category_outlined),
              tooltip: 'Manage Categories',
              onPressed: () => _showCategoryManagement(context, ref),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search products by name or SKU...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => ref.read(_searchQueryProvider.notifier).state = '',
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) => ref.read(_searchQueryProvider.notifier).state = value,
            ),
          ),

          // Category chips
          categoriesAsync.when(
            data: (categories) {
              final activeCategories = categories.where((c) => c.isActive).toList()
                ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
              return SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: selectedCategory == null,
                        onSelected: (_) => ref.read(_selectedCategoryFilterProvider.notifier).state = null,
                      ),
                    ),
                    ...activeCategories.map((cat) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(cat.name),
                        selected: selectedCategory == cat.id,
                        onSelected: (_) {
                          ref.read(_selectedCategoryFilterProvider.notifier).state =
                              selectedCategory == cat.id ? null : cat.id;
                        },
                      ),
                    )),
                  ],
                ),
              );
            },
            loading: () => const SizedBox(height: 48),
            error: (e, _) => const SizedBox(height: 48),
          ),

          const Divider(height: 1),

          // Product count
          productsAsync.when(
            data: (products) {
              final filtered = _filterProducts(products, selectedCategory, searchQuery);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${filtered.length} product${filtered.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Total: ${products.length}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // Products list
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final filtered = _filterProducts(products, selectedCategory, searchQuery);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.textTertiary),
                        const SizedBox(height: 16),
                        Text(
                          searchQuery.isNotEmpty
                              ? 'No products match "$searchQuery"'
                              : 'No products yet',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap + to add a new product',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return categoriesAsync.when(
                  data: (categories) {
                    final categoryMap = {for (var c in categories) c.id: c.name};
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final product = filtered[index];
                        return _ProductListTile(
                          product: product,
                          categoryName: categoryMap[product.categoryId] ?? 'Unknown',
                          onEdit: perms.canEditProducts
                              ? () => _showAddEditProduct(context, ref, product: product)
                              : null,
                          onDelete: perms.canEditProducts
                              ? () => _confirmDelete(context, ref, product)
                              : null,
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: perms.canEditProducts ? FloatingActionButton.extended(
        onPressed: () => _showAddEditProduct(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ) : null,
    );
  }

  List<Product> _filterProducts(List<Product> products, String? categoryId, String query) {
    var filtered = products.where((p) => p.isActive).toList();
    if (categoryId != null) {
      filtered = filtered.where((p) => p.categoryId == categoryId).toList();
    }
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      filtered = filtered.where((p) =>
          p.name.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q)).toList();
    }
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  void _showCategoryManagement(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _CategoryManagementSheet(scrollController: scrollController),
      ),
    );
  }

  void _showAddEditProduct(BuildContext context, WidgetRef ref, {Product? product}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _AddEditProductSheet(product: product),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Product product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await getIt<AppDatabase>().deleteProduct(product.id);
              if (context.mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// Product list tile widget
class _ProductListTile extends StatelessWidget {
  final Product product;
  final String categoryName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ProductListTile({
    required this.product,
    required this.categoryName,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.inventory_2, color: AppColors.primary),
        ),
        title: Text(
          product.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      categoryName,
                      style: const TextStyle(fontSize: 10, color: AppColors.primary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'SKU: ${product.sku}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${product.unit} • Cost: KES ${product.costPrice?.toStringAsFixed(0) ?? '-'}',
              style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
          ],
        ),
        trailing: Text(
          'KES ${product.price.toStringAsFixed(0)}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppColors.primary,
          ),
        ),
        onTap: onEdit,
        onLongPress: onDelete,
      ),
    );
  }
}

// Category management bottom sheet
class _CategoryManagementSheet extends ConsumerWidget {
  final ScrollController scrollController;

  const _CategoryManagementSheet({required this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(_categoriesProvider);

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Categories', style: Theme.of(context).textTheme.titleLarge),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: () => _showAddCategoryDialog(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: categoriesAsync.when(
            data: (categories) {
              final sorted = [...categories]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
              if (sorted.isEmpty) return const Center(child: Text('No categories yet'));
              return ListView.builder(
                controller: scrollController,
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  final cat = sorted[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text(cat.name[0].toUpperCase(),
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(cat.name),
                    subtitle: cat.description != null
                        ? Text(cat.description!, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _showEditCategoryDialog(context, cat)),
                        IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                          onPressed: () => _confirmDeleteCategory(context, cat)),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }

  void _showAddCategoryDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController,
              decoration: const InputDecoration(labelText: 'Category Name', hintText: 'e.g. Painkillers'),
              textCapitalization: TextCapitalization.words, autofocus: true),
            const SizedBox(height: 12),
            TextField(controller: descController,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              textCapitalization: TextCapitalization.sentences),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            if (nameController.text.trim().isEmpty) return;
            final now = DateTime.now();
            await getIt<AppDatabase>().insertCategory(CategoriesCompanion.insert(
              id: 'cat-${_uuid.v4().substring(0, 8)}', name: nameController.text.trim(),
              description: Value(descController.text.trim().isEmpty ? null : descController.text.trim()),
              sortOrder: const Value(99), isActive: const Value(true), createdAt: now, updatedAt: now,
            ));
            if (context.mounted) Navigator.pop(context);
          }, child: const Text('Add')),
        ],
      ),
    );
  }

  void _showEditCategoryDialog(BuildContext context, Category cat) {
    final nameController = TextEditingController(text: cat.name);
    final descController = TextEditingController(text: cat.description ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController,
              decoration: const InputDecoration(labelText: 'Category Name'),
              textCapitalization: TextCapitalization.words),
            const SizedBox(height: 12),
            TextField(controller: descController,
              decoration: const InputDecoration(labelText: 'Description'),
              textCapitalization: TextCapitalization.sentences),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            if (nameController.text.trim().isEmpty) return;
            await getIt<AppDatabase>().updateCategory(cat.id, CategoriesCompanion(
              name: Value(nameController.text.trim()),
              description: Value(descController.text.trim().isEmpty ? null : descController.text.trim()),
              updatedAt: Value(DateTime.now()),
            ));
            if (context.mounted) Navigator.pop(context);
          }, child: const Text('Save')),
        ],
      ),
    );
  }

  void _confirmDeleteCategory(BuildContext context, Category cat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Delete "${cat.name}"? Products in this category will need reassigning.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () async {
            await getIt<AppDatabase>().deleteCategory(cat.id);
            if (context.mounted) Navigator.pop(context);
          }, style: TextButton.styleFrom(foregroundColor: AppColors.error), child: const Text('Delete')),
        ],
      ),
    );
  }
}

// Add/Edit product bottom sheet
class _AddEditProductSheet extends ConsumerStatefulWidget {
  final Product? product;
  const _AddEditProductSheet({this.product});
  @override
  ConsumerState<_AddEditProductSheet> createState() => _AddEditProductSheetState();
}

class _AddEditProductSheetState extends ConsumerState<_AddEditProductSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _priceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _descriptionController;
  String? _selectedCategoryId;
  String _selectedUnit = 'piece';

  final _units = ['piece', 'pack', 'box', 'bottle', 'tube', 'bar', 'roll', 'jar', 'kg', 'g', 'litre', 'ml'];

  bool get isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _skuController = TextEditingController(text: widget.product?.sku ?? '');
    _priceController = TextEditingController(text: widget.product?.price.toStringAsFixed(0) ?? '');
    _costPriceController = TextEditingController(text: widget.product?.costPrice?.toStringAsFixed(0) ?? '');
    _descriptionController = TextEditingController(text: widget.product?.description ?? '');
    _selectedCategoryId = widget.product?.categoryId;
    _selectedUnit = widget.product?.unit ?? 'piece';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _priceController.dispose();
    _costPriceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(_categoriesProvider);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(isEditing ? 'Edit Product' : 'Add New Product',
                style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),

              // Product Name
              TextFormField(controller: _nameController,
                decoration: const InputDecoration(labelText: 'Product Name *',
                  hintText: 'e.g. Panadol Extra (10 tablets)', prefixIcon: Icon(Icons.inventory_2_outlined)),
                textCapitalization: TextCapitalization.words,
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter product name' : null),
              const SizedBox(height: 16),

              // SKU
              TextFormField(controller: _skuController,
                decoration: const InputDecoration(labelText: 'SKU Code *',
                  hintText: 'e.g. PAN-001', prefixIcon: Icon(Icons.qr_code)),
                textCapitalization: TextCapitalization.characters,
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter SKU code' : null),
              const SizedBox(height: 16),

              // Category dropdown
              categoriesAsync.when(
                data: (categories) {
                  final ac = categories.where((c) => c.isActive).toList();
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedCategoryId,
                    decoration: const InputDecoration(labelText: 'Category *', prefixIcon: Icon(Icons.category_outlined)),
                    items: ac.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                    validator: (v) => v == null ? 'Select a category' : null,
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
              ),
              const SizedBox(height: 16),

              // Price row
              Row(children: [
                Expanded(child: TextFormField(controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Selling Price (KES) *', prefixIcon: Icon(Icons.sell_outlined)),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter price';
                    if (double.tryParse(v) == null) return 'Invalid';
                    return null;
                  })),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(controller: _costPriceController,
                  decoration: const InputDecoration(labelText: 'Cost Price (KES)', prefixIcon: Icon(Icons.price_change_outlined)),
                  keyboardType: TextInputType.number)),
              ]),
              const SizedBox(height: 16),

              // Unit
              DropdownButtonFormField<String>(
                initialValue: _selectedUnit,
                decoration: const InputDecoration(labelText: 'Unit', prefixIcon: Icon(Icons.straighten)),
                items: _units.map((u) => DropdownMenuItem(value: u,
                  child: Text(u[0].toUpperCase() + u.substring(1)))).toList(),
                onChanged: (v) => setState(() => _selectedUnit = v ?? 'piece'),
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description (optional)', prefixIcon: Icon(Icons.description_outlined)),
                textCapitalization: TextCapitalization.sentences, maxLines: 2),
              const SizedBox(height: 24),

              // Save button
              SizedBox(width: double.infinity, height: 52,
                child: FilledButton.icon(
                  onPressed: _saveProduct,
                  icon: Icon(isEditing ? Icons.save : Icons.add),
                  label: Text(isEditing ? 'Save Changes' : 'Add Product'),
                )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    final db = getIt<AppDatabase>();
    final now = DateTime.now();

    if (isEditing) {
      await db.updateProduct(widget.product!.id, ProductsCompanion(
        name: Value(_nameController.text.trim()),
        sku: Value(_skuController.text.trim()),
        categoryId: Value(_selectedCategoryId!),
        price: Value(double.parse(_priceController.text.trim())),
        costPrice: Value(_costPriceController.text.trim().isNotEmpty
            ? double.parse(_costPriceController.text.trim()) : null),
        unit: Value(_selectedUnit),
        description: Value(_descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim()),
        updatedAt: Value(now),
      ));
    } else {
      await db.insertProduct(ProductsCompanion.insert(
        id: 'prod-${_uuid.v4().substring(0, 8)}',
        name: _nameController.text.trim(),
        sku: _skuController.text.trim(),
        categoryId: _selectedCategoryId!,
        price: double.parse(_priceController.text.trim()),
        costPrice: Value(_costPriceController.text.trim().isNotEmpty
            ? double.parse(_costPriceController.text.trim()) : null),
        unit: Value(_selectedUnit),
        description: Value(_descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim()),
        createdAt: now, updatedAt: now,
      ));
    }
    if (mounted) Navigator.pop(context);
  }
}