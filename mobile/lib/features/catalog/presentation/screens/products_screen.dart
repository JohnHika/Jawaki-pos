import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../sales/presentation/providers/catalog_provider.dart'
    as catalog_cache;

// Providers for the products screen
final _categoriesProvider = StreamProvider<List<Category>>((ref) {
  return getIt<AppDatabase>().watchAllCategories();
});

final _productsProvider = StreamProvider<List<Product>>((ref) {
  return getIt<AppDatabase>().watchAllProducts();
});

final _selectedCategoryFilterProvider = StateProvider<String?>((ref) => null);
final _searchQueryProvider = StateProvider<String>((ref) => '');
final _catalogSyncProvider = FutureProvider<void>((ref) async {
  try {
    await catalog_cache.syncCatalogCacheFromApi();
  } catch (_) {
    // Keep the local cache visible if the backend is temporarily unavailable.
  }
});

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(_catalogSyncProvider);
    final categoriesAsync = ref.watch(_categoriesProvider);
    final productsAsync = ref.watch(_productsProvider);
    final selectedCategory = ref.watch(_selectedCategoryFilterProvider);
    final searchQuery = ref.watch(_searchQueryProvider);
    final perms = ref.watch(permissionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Product Catalog',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: DesignColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Manage inventory items, pricing, and categories',
                          style: TextStyle(
                            fontSize: 12,
                            color: DesignColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: (perms.canEditProducts
                              ? DesignColors.success
                              : DesignColors.info)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: (perms.canEditProducts
                                ? DesignColors.success
                                : DesignColors.info)
                            .withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          perms.canEditProducts
                              ? Icons.edit_rounded
                              : Icons.visibility_rounded,
                          size: 14,
                          color: perms.canEditProducts
                              ? DesignColors.success
                              : DesignColors.info,
                        ),
                        SizedBox(width: 6),
                        Text(
                          perms.canEditProducts ? 'Editor' : 'Viewer',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: perms.canEditProducts
                                ? DesignColors.success
                                : DesignColors.info,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Search bar with consistent styling
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search products by name...',
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
                  fillColor: DesignColors.surfaceSubtle.withValues(alpha: 0.3),
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
                  height: 44,
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
                          isDark: isDark,
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
                            isDark: isDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox(height: 44),
              error: (e, _) => const SizedBox(height: 44),
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
                            isDark: isDark,
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
              borderRadius: 12,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool isDark = false,
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
              : isDark
                  ? DesignColors.darkSurfaceElevated
                  : DesignColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? DesignColors.brand
                : isDark
                    ? DesignColors.darkBorder
                    : DesignColors.surfaceBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? Colors.white
                : (isDark
                    ? DesignColors.darkTextPrimary
                    : DesignColors.textPrimary),
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
      filtered =
          filtered.where((p) => p.name.toLowerCase().contains(q)).toList();
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
      try {
        await getIt<ApiClient>().deleteProduct(product.id);
        await catalog_cache.syncCatalogCacheFromApi();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not delete product: $e'),
              backgroundColor: DesignColors.error,
            ),
          );
        }
      }
    }
  }
}

// Product list tile widget - Premium GlassCard design with consistent styling
class _ProductListTile extends StatelessWidget {
  final Product product;
  final String categoryName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isDark;

  const _ProductListTile({
    required this.product,
    required this.categoryName,
    this.onEdit,
    this.onDelete,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: onEdit,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: 12,
        blur: 8,
        tint: Colors.transparent,
        borderColor:
            isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
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
                borderRadius: BorderRadius.circular(12),
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
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Unit: ${product.unit}',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          Divider(
            color:
                isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
            height: 1,
          ),
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
                        borderColor: isDark
                            ? DesignColors.darkBorder
                            : DesignColors.surfaceBorder,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? categoryImageUrl;
    String? categoryImagePublicId;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Add Category',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: DesignColors.textPrimary)),
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
                  fillColor: isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceSubtle,
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
                  fillColor: isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceSubtle,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              _ImagePickerSection(
                initialImageUrl: categoryImageUrl,
                type: 'category',
                label: 'Add category image (optional)',
                onImageChanged: (url, publicId) => setDialogState(() {
                  categoryImageUrl = url;
                  categoryImagePublicId = publicId;
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: DesignColors.textSecondary,
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                try {
                  await getIt<ApiClient>().createCategory(
                    name: nameController.text.trim(),
                    description: descController.text.trim().isEmpty
                        ? null
                        : descController.text.trim(),
                    image: categoryImageUrl,
                    imagePublicId: categoryImagePublicId,
                  );
                  await catalog_cache.syncCatalogCacheFromApi();
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Could not add category: $e'),
                        backgroundColor: DesignColors.error,
                      ),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: DesignColors.brand,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditCategoryDialog(BuildContext context, Category cat) {
    final nameController = TextEditingController(text: cat.name);
    final descController = TextEditingController(text: cat.description ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? categoryImageUrl = cat.imageUrl;
    String? categoryImagePublicId;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Edit Category',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: DesignColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Category Name',
                  filled: true,
                  fillColor: isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceSubtle,
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
                  fillColor: isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceSubtle,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              _ImagePickerSection(
                initialImageUrl: categoryImageUrl,
                type: 'category',
                label: 'Change category image',
                onImageChanged: (url, publicId) => setDialogState(() {
                  categoryImageUrl = url;
                  categoryImagePublicId = publicId;
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: DesignColors.textSecondary,
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                try {
                  await getIt<ApiClient>().updateCategory(
                    cat.id,
                    name: nameController.text.trim(),
                    description: descController.text.trim().isEmpty
                        ? null
                        : descController.text.trim(),
                    image: categoryImageUrl,
                    imagePublicId: categoryImagePublicId,
                    clearImage:
                        cat.imageUrl != null && categoryImageUrl == null,
                  );
                  await catalog_cache.syncCatalogCacheFromApi();
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Could not update category: $e'),
                        backgroundColor: DesignColors.error,
                      ),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: DesignColors.brand,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
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
      try {
        await getIt<ApiClient>().deleteCategory(cat.id);
        await catalog_cache.syncCatalogCacheFromApi();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not delete category: $e'),
              backgroundColor: DesignColors.error,
            ),
          );
        }
      }
    }
  }
}

/// Helper model for a single unit+price pricing tier in the product form.
class _UnitPriceTier {
  String unit;
  TextEditingController priceController;
  _UnitPriceTier({required this.unit, String? price})
      : priceController = TextEditingController(text: price ?? '');
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
  late final TextEditingController _descriptionController;
  String? _selectedCategoryId;
  String? _imageUrl;
  String? _imagePublicId;
  late List<_UnitPriceTier> _unitPriceTiers;

  final _units = [
    'piece',
    'pack',
    'box',
    'bottle',
    'tube',
    'bar',
    'roll',
    'jar',
    'dozen',
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
    _descriptionController =
        TextEditingController(text: widget.product?.description ?? '');
    _selectedCategoryId = widget.product?.categoryId;
    _imageUrl = widget.product?.imageUrl;

    // Build pricing tiers from existing product data (or start with one blank tier)
    _unitPriceTiers = [
      _UnitPriceTier(
        unit: widget.product?.unit ?? 'piece',
        price: widget.product?.price.toStringAsFixed(0),
      ),
    ];
    if (widget.product?.secondaryUnit != null) {
      // Prefer stored secondaryUnitPrice; fallback to qty-based estimate
      final secPrice = widget.product!.secondaryUnitPrice ??
          (widget.product!.secondaryUnitQty != null
              ? widget.product!.price * widget.product!.secondaryUnitQty!
              : null);
      _unitPriceTiers.add(_UnitPriceTier(
        unit: widget.product!.secondaryUnit!,
        price: secPrice?.toStringAsFixed(0),
      ));
    }
    if (widget.product?.tertiaryUnit != null) {
      final terPrice = widget.product!.tertiaryUnitPrice ??
          (widget.product!.tertiaryUnitQty != null
              ? widget.product!.price * widget.product!.tertiaryUnitQty!
              : null);
      _unitPriceTiers.add(_UnitPriceTier(
        unit: widget.product!.tertiaryUnit!,
        price: terPrice?.toStringAsFixed(0),
      ));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    for (final tier in _unitPriceTiers) {
      tier.priceController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(_categoriesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                fillColor: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
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

            // Category dropdown
            categoriesAsync.when(
              data: (categories) {
                final ac = categories.where((c) => c.isActive).toList();
                return Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? DesignColors.darkSurfaceElevated
                        : DesignColors.surfaceSubtle,
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
                          isDark ? DesignColors.darkSurface : Colors.white,
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

            // ── Multi-unit Pricing ────────────────────────────────────────
            _buildPricingSection(isDark),
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
                fillColor: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
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
            const SizedBox(height: 14),

            // Product image
            _ImagePickerSection(
              initialImageUrl: _imageUrl,
              type: 'product',
              label: 'Add product image (optional)',
              onImageChanged: (url, publicId) => setState(() {
                _imageUrl = url;
                _imagePublicId = publicId;
              }),
            ),
            const SizedBox(height: 24),

            // Save button
            GradientButton(
              label: isEditing ? 'Save Changes' : 'Add Product',
              icon: isEditing ? Icons.save_rounded : Icons.add_rounded,
              onPressed: _saveProduct,
              height: 52,
              borderRadius: 12,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    final apiClient = getIt<ApiClient>();
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    final clearImage =
        isEditing && widget.product?.imageUrl != null && _imageUrl == null;

    final primary = _unitPriceTiers[0];
    final secondary = _unitPriceTiers.length > 1 ? _unitPriceTiers[1] : null;
    final tertiary = _unitPriceTiers.length > 2 ? _unitPriceTiers[2] : null;

    final primaryPrice = double.parse(primary.priceController.text.trim());
    final secondaryPrice = secondary != null
        ? double.tryParse(secondary.priceController.text.trim())
        : null;
    final tertiaryPrice = tertiary != null
        ? double.tryParse(tertiary.priceController.text.trim())
        : null;

    // secondaryUnitQty: how many primary units = 1 secondary unit
    // e.g. if piece=5, dozen=50 → qty=10 (50/5)
    final secondaryQty =
        (secondaryPrice != null && primaryPrice > 0)
            ? secondaryPrice / primaryPrice
            : null;
    final tertiaryQty =
        (tertiaryPrice != null && primaryPrice > 0)
            ? tertiaryPrice / primaryPrice
            : null;

    try {
      if (isEditing) {
        await apiClient.updateProduct(
          widget.product!.id,
          name: _nameController.text.trim(),
          basePrice: primaryPrice,
          categoryIds: [_selectedCategoryId!],
          description: description,
          image: _imageUrl,
          imagePublicId: _imagePublicId,
          unit: primary.unit,
          secondaryUnit: secondary?.unit,
          secondaryUnitQty: secondaryQty,
          secondaryUnitPrice: secondaryPrice,
          tertiaryUnit: tertiary?.unit,
          tertiaryUnitQty: tertiaryQty,
          tertiaryUnitPrice: tertiaryPrice,
          clearImage: clearImage,
        );
      } else {
        await apiClient.createProduct(
          name: _nameController.text.trim(),
          basePrice: primaryPrice,
          categoryIds: [_selectedCategoryId!],
          description: description,
          image: _imageUrl,
          imagePublicId: _imagePublicId,
          unit: primary.unit,
          secondaryUnit: secondary?.unit,
          secondaryUnitQty: secondaryQty,
          secondaryUnitPrice: secondaryPrice,
          tertiaryUnit: tertiary?.unit,
          tertiaryUnitQty: tertiaryQty,
          tertiaryUnitPrice: tertiaryPrice,
        );
      }

      await catalog_cache.syncCatalogCacheFromApi();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save product: $e'),
            backgroundColor: DesignColors.error,
          ),
        );
      }
    }
  }

  // ─── Pricing section helpers ────────────────────────────────────────────

  Widget _buildPricingSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: DesignColors.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.local_offer_rounded,
                  color: DesignColors.brand, size: 16),
            ),
            const SizedBox(width: 8),
            const Text(
              'Pricing by Unit',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DesignColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_unitPriceTiers.length}/3 tiers',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: DesignColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Tiers container
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? DesignColors.darkSurfaceElevated
                : DesignColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (int i = 0; i < _unitPriceTiers.length; i++)
                _buildPricingRow(i, isDark),
              if (_unitPriceTiers.length < 3) _buildAddTierButton(isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPricingRow(int index, bool isDark) {
    final tier = _unitPriceTiers[index];
    final isPrimary = index == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (index > 0)
          Divider(
            height: 1,
            thickness: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
            indent: 12,
            endIndent: 12,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Unit selector
              Expanded(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        isDark ? DesignColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: tier.unit,
                      isDense: true,
                      isExpanded: true,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.white
                            : DesignColors.textPrimary,
                      ),
                      dropdownColor: isDark
                          ? DesignColors.darkSurface
                          : Colors.white,
                      items: _units
                          .map(
                            (u) => DropdownMenuItem(
                              value: u,
                              child: Text(
                                u[0].toUpperCase() + u.substring(1),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setState(
                          () => tier.unit = val ?? tier.unit),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Price field
              Expanded(
                flex: 7,
                child: TextFormField(
                  controller: tier.priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(
                      color: DesignColors.textTertiary,
                      fontWeight: FontWeight.normal,
                    ),
                    prefixText: 'KES ',
                    prefixStyle: const TextStyle(
                      color: DesignColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? DesignColors.darkSurface
                        : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: DesignColors.brand, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Required';
                    }
                    if (double.tryParse(v.trim()) == null) {
                      return 'Invalid';
                    }
                    return null;
                  },
                ),
              ),
              // Delete button (not on primary row)
              if (!isPrimary) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() {
                    _unitPriceTiers[index].priceController.dispose();
                    _unitPriceTiers.removeAt(index);
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DesignColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: DesignColors.error, size: 18),
                  ),
                ),
              ] else
                // Spacer to keep row height consistent when no delete btn
                const SizedBox(width: 34),
            ],
          ),
        ),
        // Label below each row
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: isPrimary
              ? Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 11, color: DesignColors.brand),
                    const SizedBox(width: 4),
                    Text(
                      'Primary — base for stock deductions',
                      style: const TextStyle(
                        fontSize: 11,
                        color: DesignColors.textTertiary,
                      ),
                    ),
                  ],
                )
              : Text(
                  'Tier ${index + 1} — ratio auto-computed',
                  style: const TextStyle(
                    fontSize: 11,
                    color: DesignColors.textTertiary,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildAddTierButton(bool isDark) {
    return InkWell(
      onTap: () => setState(() {
        _unitPriceTiers.add(_UnitPriceTier(unit: _getNextUnit()));
      }),
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(14),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add_circle_outline_rounded,
                color: DesignColors.brand, size: 17),
            SizedBox(width: 6),
            Text(
              'Add pricing tier',
              style: TextStyle(
                color: DesignColors.brand,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getNextUnit() {
    final used = _unitPriceTiers.map((t) => t.unit).toSet();
    for (final u in ['dozen', 'box', 'pack', 'bottle', 'kg', 'litre']) {
      if (!used.contains(u)) return u;
    }
    return 'pack';
  }
}


// ────────────────────────────────────────────────────────────────────────────
// Shared image picker + upload widget used in product / category / logo forms
// ────────────────────────────────────────────────────────────────────────────

class _ImagePickerSection extends StatefulWidget {
  final String? initialImageUrl;
  final String type; // 'product' | 'category' | 'logo'
  final void Function(String? url, String? publicId) onImageChanged;
  final String label;

  const _ImagePickerSection({
    this.initialImageUrl,
    required this.type,
    required this.onImageChanged,
    this.label = 'Add image',
  });

  @override
  State<_ImagePickerSection> createState() => _ImagePickerSectionState();
}

class _ImagePickerSectionState extends State<_ImagePickerSection> {
  String? _imageUrl;
  String? _localImagePath;
  String? _errorMessage;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.initialImageUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostImage());
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    setState(() => _errorMessage = null);

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take photo'),
                subtitle: const Text('Use the camera'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                subtitle: const Text('Pick an existing image'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 180));

    XFile? file;
    try {
      file = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
      );
    } on PlatformException catch (e) {
      _showImageError(
        'Could not open ${source == ImageSource.camera ? 'camera' : 'gallery'}: ${e.message ?? e.code}',
      );
      return;
    } catch (e) {
      _showImageError(
        'Could not open ${source == ImageSource.camera ? 'camera' : 'gallery'}: $e',
      );
      return;
    }
    if (file == null || !mounted) return;

    setState(() {
      _localImagePath = file!.path;
      _isUploading = true;
    });

    try {
      final result = await getIt<ApiClient>().uploadImage(
        filePath: file.path,
        fileName: file.name,
        type: widget.type,
      );
      if (!mounted) return;
      final url = result['url'] as String?;
      final publicId = result['publicId'] as String?;
      setState(() {
        _imageUrl = url;
        _localImagePath = null;
      });
      widget.onImageChanged(url, publicId);
    } catch (e) {
      _showImageError('Image upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _recoverLostImage() async {
    try {
      final response = await ImagePicker().retrieveLostData();
      if (!mounted || response.isEmpty) return;
      if (response.exception != null) {
        _showImageError(
          'Image picker was interrupted: ${response.exception!.message ?? response.exception!.code}',
        );
        return;
      }

      final file = response.file;
      if (file == null) return;
      setState(() => _localImagePath = file.path);
    } catch (_) {
      // Lost-data recovery is best effort only.
    }
  }

  void _showImageError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: DesignColors.error,
      ),
    );
  }

  void _removeImage() {
    setState(() {
      _imageUrl = null;
      _localImagePath = null;
      _errorMessage = null;
    });
    widget.onImageChanged(null, null);
  }

  @override
  Widget build(BuildContext context) {
    if (_isUploading) {
      return Container(
        height: 64,
        decoration: BoxDecoration(
          color: DesignColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: DesignColors.brand,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Uploading...',
              style: TextStyle(fontSize: 13, color: DesignColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if ((_localImagePath != null && _localImagePath!.isNotEmpty) ||
        (_imageUrl != null && _imageUrl!.isNotEmpty)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildPreviewImage(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      onPressed: _isUploading ? null : _pickImage,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                      label: const Text('Change image'),
                      style: TextButton.styleFrom(
                        foregroundColor: DesignColors.brand,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _isUploading ? null : _removeImage,
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text('Remove'),
                      style: TextButton.styleFrom(
                        foregroundColor: DesignColors.error,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isUploading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              minHeight: 2,
              color: DesignColors.brand,
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: DesignColors.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: DesignColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DesignColors.surfaceBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.add_photo_alternate_outlined,
                  color: DesignColors.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: DesignColors.textTertiary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: DesignColors.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPreviewImage() {
    if (_localImagePath != null && _localImagePath!.isNotEmpty) {
      return Image.file(
        File(_localImagePath!),
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _brokenPreview(),
      );
    }

    return CachedNetworkImage(
      imageUrl: _imageUrl!,
      width: 64,
      height: 64,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        width: 64,
        height: 64,
        color: DesignColors.surfaceSubtle,
      ),
      errorWidget: (_, __, ___) => _brokenPreview(),
    );
  }

  Widget _brokenPreview() {
    return Container(
      width: 64,
      height: 64,
      color: DesignColors.surfaceSubtle,
      child: const Icon(
        Icons.broken_image_outlined,
        color: DesignColors.textTertiary,
        size: 28,
      ),
    );
  }
}
