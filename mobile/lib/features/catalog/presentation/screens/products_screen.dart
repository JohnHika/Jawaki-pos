import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../../core/theme/design_system.dart';
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
      appBar: BrandedAppBar(
        title: 'Products',
        actions: [
          if (perms.canEditProducts)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DesignColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.category_outlined,
                    color: DesignColors.brand, size: 20),
              ),
              tooltip: 'Manage Categories',
              onPressed: () => _showCategoryManagement(context, ref),
            ),
        ],
      ),
      body: PageContainer(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search products by name or SKU...',
                  hintStyle: TextStyle(color: DesignColors.textTertiary),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: DesignColors.textTertiary),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              color: DesignColors.textTertiary),
                          onPressed: () => ref
                              .read(_searchQueryProvider.notifier)
                              .state = '',
                        )
                      : null,
                  filled: true,
                  fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: DesignColors.brand, width: 1.5),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (value) =>
                    ref.read(_searchQueryProvider.notifier).state = value,
              ),
            ),

            // Category chips
            categoriesAsync.when(
              data: (categories) {
                final activeCategories = categories
                    .where((c) => c.isActive)
                    .toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                return SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _buildChip(
                          label: 'All',
                          selected: selectedCategory == null,
                          onTap: () => ref
                              .read(_selectedCategoryFilterProvider.notifier)
                              .state = null,
                        ),
                      ),
                      ...activeCategories.map(
                        (cat) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _buildChip(
                            label: cat.name,
                            selected: selectedCategory == cat.id,
                            onTap: () {
                              ref
                                      .read(_selectedCategoryFilterProvider
                                          .notifier)
                                      .state =
                                  selectedCategory == cat.id ? null : cat.id;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox(height: 48),
              error: (e, _) => const SizedBox(height: 48),
            ),

            const SizedBox(height: 4),

            // Product count
            productsAsync.when(
              data: (products) {
                final filtered =
                    _filterProducts(products, selectedCategory, searchQuery);
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: DesignColors.brand.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.inventory_2_rounded,
                              size: 14,
                              color: DesignColors.brand,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${filtered.length} product${filtered.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: DesignColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Total: ${products.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: DesignColors.textTertiary,
                          fontWeight: FontWeight.w500,
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
                  final filtered =
                      _filterProducts(products, selectedCategory, searchQuery);
                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: searchQuery.isNotEmpty
                          ? 'No products match "$searchQuery"'
                          : 'No products yet',
                      subtitle: 'Tap + to add a new product',
                      iconColor: DesignColors.textTertiary,
                    );
                  }

                  return categoriesAsync.when(
                    data: (categories) {
                      final categoryMap = {
                        for (var c in categories) c.id: c.name
                      };
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final product = filtered[index];
                          return _ProductListTile(
                            product: product,
                            categoryName:
                                categoryMap[product.categoryId] ?? 'Unknown',
                            onEdit: perms.canEditProducts
                                ? () => _showAddEditProduct(context, ref,
                                    product: product)
                                : null,
                            onDelete: perms.canEditProducts
                                ? () => _confirmDelete(context, ref, product)
                                : null,
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: DesignColors.brand)),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  );
                },
                loading: () => const Center(
                    child:
                        CircularProgressIndicator(color: DesignColors.brand)),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: perms.canEditProducts
          ? GradientButton(
              label: 'Add Product',
              icon: Icons.add_rounded,
              onPressed: () => _showAddEditProduct(context, ref),
              height: 48,
              expanded: false,
              borderRadius: 14,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DesignAnimation.fast,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [DesignColors.brand, DesignColors.brandDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected
              ? null
              : DesignColors.surfaceBorder.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? DesignColors.brand
                : DesignColors.surfaceBorder.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : DesignColors.textSecondary,
          ),
        ),
      ),
    );
  }

  List<Product> _filterProducts(
      List<Product> products, String? categoryId, String query) {
    var filtered = products.where((p) => p.isActive).toList();
    if (categoryId != null) {
      filtered = filtered.where((p) => p.categoryId == categoryId).toList();
    }
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      filtered = filtered
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q))
          .toList();
    }
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  void _showCategoryManagement(BuildContext context, WidgetRef ref) {
    GlassBottomSheet.show(
      context,
      title: 'Categories',
      initialSize: 0.62,
      maxSize: 0.72,
      child: _CategoryManagementSheet(),
    );
  }

  void _showAddEditProduct(BuildContext context, WidgetRef ref,
      {Product? product}) {
    GlassBottomSheet.show(
      context,
      title: product == null ? 'Add Product' : 'Edit Product',
      initialSize: 0.85,
      maxSize: 0.95,
      scrollable: true,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _AddEditProductSheet(product: product),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Product product) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Product',
      message: 'Are you sure you want to delete "${product.name}"?',
      confirmLabel: 'Delete',
      confirmColor: DesignColors.error,
    );
    if (confirmed) {
      await getIt<AppDatabase>().deleteProduct(product.id);
    }
  }
}

// Product list tile widget - Premium GlassCard design
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: onEdit,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: 14,
        blur: 8,
        tint: Colors.transparent,
        borderColor: DesignColors.surfaceBorder,
        child: Row(
          children: [
            // Product image/avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DesignColors.brand.withValues(alpha: 0.1),
                    DesignColors.brand.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                color: DesignColors.brand,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),

            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: DesignColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: DesignColors.brand.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          categoryName,
                          style: const TextStyle(
                            fontSize: 10,
                            color: DesignColors.brand,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'SKU: ${product.sku}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: DesignColors.textTertiary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${product.unit} \u2022 Cost: KES ${product.costPrice?.toStringAsFixed(0) ?? '-'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: DesignColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // Price
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'KES ${product.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: DesignColors.brand,
                    letterSpacing: -0.3,
                  ),
                ),
                if (onDelete != null)
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: DesignColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: DesignColors.error,
                      ),
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

// Category management bottom sheet - Premium
class _CategoryManagementSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(_categoriesProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 112,
              child: GradientButton(
                label: 'Add',
                icon: Icons.add_rounded,
                onPressed: () => _showAddCategoryDialog(context),
                height: 36,
                expanded: false,
                borderRadius: 10,
                gradient: [DesignColors.brand, DesignColors.brandDark],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: DesignColors.surfaceBorder, height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: categoriesAsync.when(
              data: (categories) {
                final sorted = [...categories]
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                if (sorted.isEmpty) {
                  return const EmptyState(
                    icon: Icons.category_outlined,
                    title: 'No categories yet',
                    subtitle: 'Add your first category to organize products',
                  );
                }
                return ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final cat = sorted[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        borderRadius: 12,
                        tint: Colors.transparent,
                        borderColor: DesignColors.surfaceBorder,
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color:
                                    DesignColors.brand.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  cat.name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: DesignColors.brand,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cat.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: DesignColors.textPrimary,
                                    ),
                                  ),
                                  if (cat.description != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      cat.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: DesignColors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  _showEditCategoryDialog(context, cat),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      DesignColors.info.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: DesignColors.info,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _confirmDeleteCategory(context, cat),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: DesignColors.error
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: DesignColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                  child: CircularProgressIndicator(color: DesignColors.brand)),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCategoryDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Add Category',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: DesignColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Category Name',
                hintText: 'e.g. Painkillers',
                hintStyle: TextStyle(color: DesignColors.textTertiary),
                labelStyle: const TextStyle(
                  color: DesignColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                filled: true,
                fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                hintStyle: TextStyle(color: DesignColors.textTertiary),
                labelStyle: const TextStyle(
                  color: DesignColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                filled: true,
                fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: DesignColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              final now = DateTime.now();
              await getIt<AppDatabase>()
                  .insertCategory(CategoriesCompanion.insert(
                id: 'cat-${_uuid.v4().substring(0, 8)}',
                name: nameController.text.trim(),
                description: Value(descController.text.trim().isEmpty
                    ? null
                    : descController.text.trim()),
                sortOrder: const Value(99),
                isActive: const Value(true),
                createdAt: now,
                updatedAt: now,
              ));
              if (context.mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: DesignColors.brand,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Add'),
          ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Edit Category',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: DesignColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Category Name',
                filled: true,
                fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: InputDecoration(
                labelText: 'Description',
                filled: true,
                fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: DesignColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              await getIt<AppDatabase>().updateCategory(
                  cat.id,
                  CategoriesCompanion(
                    name: Value(nameController.text.trim()),
                    description: Value(descController.text.trim().isEmpty
                        ? null
                        : descController.text.trim()),
                    updatedAt: Value(DateTime.now()),
                  ));
              if (context.mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: DesignColors.brand,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCategory(BuildContext context, Category cat) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Category',
      message:
          'Delete "${cat.name}"? Products in this category will need reassigning.',
      confirmLabel: 'Delete',
      confirmColor: DesignColors.error,
    );
    if (confirmed) {
      await getIt<AppDatabase>().deleteCategory(cat.id);
    }
  }
}

// Add/Edit product bottom sheet - Premium
class _AddEditProductSheet extends ConsumerStatefulWidget {
  final Product? product;
  const _AddEditProductSheet({this.product});
  @override
  ConsumerState<_AddEditProductSheet> createState() =>
      _AddEditProductSheetState();
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

  final _units = [
    'piece',
    'pack',
    'box',
    'bottle',
    'tube',
    'bar',
    'roll',
    'jar',
    'kg',
    'g',
    'litre',
    'ml'
  ];

  bool get isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _skuController = TextEditingController(text: widget.product?.sku ?? '');
    _priceController = TextEditingController(
        text: widget.product?.price.toStringAsFixed(0) ?? '');
    _costPriceController = TextEditingController(
        text: widget.product?.costPrice?.toStringAsFixed(0) ?? '');
    _descriptionController =
        TextEditingController(text: widget.product?.description ?? '');
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: DesignColors.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isEditing
                        ? Icons.edit_rounded
                        : Icons.add_circle_outline_rounded,
                    color: DesignColors.brand,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isEditing ? 'Edit Product' : 'Add New Product',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: DesignColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Product Name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Product Name *',
                hintText: 'e.g. Panadol Extra (10 tablets)',
                hintStyle: TextStyle(color: DesignColors.textTertiary),
                labelStyle: const TextStyle(
                  color: DesignColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.auto,
                prefixIcon: const Icon(Icons.inventory_2_outlined,
                    color: DesignColors.textTertiary),
                filled: true,
                fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.2),
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
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter product name' : null,
            ),
            const SizedBox(height: 14),

            // SKU
            TextFormField(
              controller: _skuController,
              decoration: InputDecoration(
                labelText: 'SKU Code *',
                hintText: 'e.g. PAN-001',
                hintStyle: TextStyle(color: DesignColors.textTertiary),
                labelStyle: const TextStyle(
                  color: DesignColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.auto,
                prefixIcon: const Icon(Icons.qr_code_rounded,
                    color: DesignColors.textTertiary),
                filled: true,
                fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.2),
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
              textCapitalization: TextCapitalization.characters,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter SKU code' : null,
            ),
            const SizedBox(height: 14),

            // Category dropdown
            categoriesAsync.when(
              data: (categories) {
                final ac = categories.where((c) => c.isActive).toList();
                return Container(
                  decoration: BoxDecoration(
                    color: DesignColors.surfaceBorder.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Category *',
                        labelStyle: TextStyle(
                          color: DesignColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        floatingLabelBehavior: FloatingLabelBehavior.auto,
                        prefixIcon: Icon(Icons.category_outlined,
                            color: DesignColors.textTertiary),
                        border: InputBorder.none,
                      ),
                      dropdownColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? DesignColors.darkSurface
                              : Colors.white,
                      items: ac
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                      validator: (v) => v == null ? 'Select a category' : null,
                    ),
                  ),
                );
              },
              loading: () =>
                  const LinearProgressIndicator(color: DesignColors.brand),
              error: (e, _) => Text('Error: $e'),
            ),
            const SizedBox(height: 14),

            // Price row
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _priceController,
                  decoration: InputDecoration(
                    labelText: 'Selling Price (KES) *',
                    hintStyle: TextStyle(color: DesignColors.textTertiary),
                    labelStyle: const TextStyle(
                      color: DesignColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.auto,
                    prefixIcon: const Icon(Icons.sell_outlined,
                        color: DesignColors.textTertiary),
                    filled: true,
                    fillColor:
                        DesignColors.surfaceBorder.withValues(alpha: 0.2),
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
                      borderSide: const BorderSide(
                          color: DesignColors.brand, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Enter price';
                    }
                    if (double.tryParse(v) == null) return 'Invalid';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _costPriceController,
                  decoration: InputDecoration(
                    labelText: 'Cost Price (KES)',
                    hintStyle: TextStyle(color: DesignColors.textTertiary),
                    labelStyle: const TextStyle(
                      color: DesignColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.auto,
                    prefixIcon: const Icon(Icons.price_change_outlined,
                        color: DesignColors.textTertiary),
                    filled: true,
                    fillColor:
                        DesignColors.surfaceBorder.withValues(alpha: 0.2),
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
                      borderSide: const BorderSide(
                          color: DesignColors.brand, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ]),
            const SizedBox(height: 14),

            // Unit
            Container(
              decoration: BoxDecoration(
                color: DesignColors.surfaceBorder.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    labelStyle: TextStyle(
                      color: DesignColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.auto,
                    prefixIcon: Icon(Icons.straighten_rounded,
                        color: DesignColors.textTertiary),
                    border: InputBorder.none,
                  ),
                  dropdownColor: Theme.of(context).brightness == Brightness.dark
                      ? DesignColors.darkSurface
                      : Colors.white,
                  items: _units
                      .map((u) => DropdownMenuItem(
                          value: u,
                          child: Text(u[0].toUpperCase() + u.substring(1))))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedUnit = v ?? 'piece'),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                hintStyle: TextStyle(color: DesignColors.textTertiary),
                labelStyle: const TextStyle(
                  color: DesignColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.auto,
                prefixIcon: const Icon(Icons.description_outlined,
                    color: DesignColors.textTertiary),
                filled: true,
                fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.2),
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
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            // Save button
            GradientButton(
              label: isEditing ? 'Save Changes' : 'Add Product',
              icon: isEditing ? Icons.save_rounded : Icons.add_rounded,
              onPressed: _saveProduct,
              height: 52,
              borderRadius: 14,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    final db = getIt<AppDatabase>();
    final now = DateTime.now();

    if (isEditing) {
      await db.updateProduct(
          widget.product!.id,
          ProductsCompanion(
            name: Value(_nameController.text.trim()),
            sku: Value(_skuController.text.trim()),
            categoryId: Value(_selectedCategoryId!),
            price: Value(double.parse(_priceController.text.trim())),
            costPrice: Value(_costPriceController.text.trim().isNotEmpty
                ? double.parse(_costPriceController.text.trim())
                : null),
            unit: Value(_selectedUnit),
            description: Value(_descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim()),
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
            ? double.parse(_costPriceController.text.trim())
            : null),
        unit: Value(_selectedUnit),
        description: Value(_descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim()),
        createdAt: now,
        updatedAt: now,
      ));
    }
    if (mounted) Navigator.pop(context);
  }
}
