import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../sales/presentation/providers/catalog_provider.dart'
    as catalog_cache;
import '../providers/catalog_categories_provider.dart';
import '../widgets/add_edit_product_sheet.dart';
import '../widgets/image_picker_section.dart';

// Providers for the products screen
final _productsProvider = StreamProvider<List<Product>>((ref) {
  return getIt<AppDatabase>().watchAllProducts();
});

final _selectedCategoryFilterProvider = StateProvider<String?>((ref) => null);
final _searchQueryProvider = StateProvider<String>((ref) => '');

// Keyed by the logged-in user's id (or a sentinel while logged out) so a
// fresh login — including logging in as a different org on the same
// device — always gets its own provider instance and re-runs the sync,
// instead of forever reusing whichever tenant's sync happened to run
// first in this app process.
final _catalogSyncProvider =
    FutureProvider.family<void, String>((ref, userKey) async {
  await catalog_cache.syncCatalogCacheFromApi();
});

// A StreamProvider (not a one-shot FutureProvider) so the displayed
// quantity updates live once a catalog sync writes a fresh stock row —
// e.g. right after receiving stock — instead of staying stuck at whatever
// value was cached the first time this provider resolved, which pull-to-
// refresh alone never invalidated.
final _productStockProvider = StreamProvider.family<int?, String>(
  (ref, productId) {
    return getIt<AppDatabase>()
        .watchStockForProduct(productId)
        .map((stock) => stock?.quantity);
  },
);

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId =
        ref.watch(currentUserProvider)?['id'] as String? ?? 'logged-out';
    final syncAsync = ref.watch(_catalogSyncProvider(currentUserId));
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(_productsProvider);
    final selectedCategory = ref.watch(_selectedCategoryFilterProvider);
    final searchQuery = ref.watch(_searchQueryProvider);
    final perms = ref.watch(permissionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Products',
        showBackButton: false,
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
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Manage inventory items, pricing, and categories',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryColor,
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
                        const SizedBox(width: 6),
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
                style: TextStyle(color: titleColor),
                decoration: InputDecoration(
                  hintText: 'Search products by name...',
                  hintStyle: TextStyle(color: tertiaryColor),
                  prefixIcon: Icon(Icons.search_rounded, color: tertiaryColor),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: tertiaryColor),
                          onPressed: () => ref
                              .read(_searchQueryProvider.notifier)
                              .state = '',
                        )
                      : null,
                  filled: true,
                  fillColor: isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceSubtle.withValues(alpha: 0.3),
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
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Total: ${products.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: tertiaryColor,
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
                    // Distinguish a genuinely empty catalog from a local
                    // cache that's empty because the sync from the backend
                    // failed — showing "no products yet" in the latter case
                    // would wrongly suggest the org has no products at all.
                    if (products.isEmpty &&
                        searchQuery.isEmpty &&
                        syncAsync.hasError) {
                      return EmptyState(
                        icon: Icons.sync_problem_rounded,
                        title: 'Couldn\'t load your product catalog',
                        subtitle:
                            'Check your connection and try again.',
                        iconColor: DesignColors.error,
                        actionLabel: 'Retry',
                        onAction: () => ref
                            .invalidate(_catalogSyncProvider(currentUserId)),
                      );
                    }
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: searchQuery.isNotEmpty
                          ? 'No products match "$searchQuery"'
                          : 'No products yet',
                      subtitle: 'Tap + to add a new product',
                    );
                  }

                  return categoriesAsync.when(
                    data: (categories) {
                      final categoryMap = {
                        for (var c in categories) c.id: c.name
                      };
                      return RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(_catalogSyncProvider(currentUserId));
                          ref.invalidate(_productsProvider);
                        },
                        color: DesignColors.brand,
                        backgroundColor: isDark
                            ? DesignColors.darkSurfaceElevated
                            : Colors.white,
                        child: ListView.builder(
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
                        ),
                      );
                    },
                    loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: DesignColors.brand)),
                    error: (e, _) => EmptyState(
                      icon: Icons.category_outlined,
                      title: 'Couldn\'t load categories',
                      subtitle: 'Check your connection and try again.',
                      iconColor: DesignColors.error,
                      actionLabel: 'Retry',
                      onAction: () => ref.invalidate(categoriesProvider),
                    ),
                  );
                },
                loading: () => const Center(
                    child:
                        CircularProgressIndicator(color: DesignColors.brand)),
                error: (e, _) => EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Couldn\'t load products',
                  subtitle: 'Check your connection and try again.',
                  iconColor: DesignColors.error,
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(_productsProvider),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: perms.canEditProducts
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: GradientButton(
                label: 'Add Product',
                icon: Icons.add_rounded,
                onPressed: () => _showAddEditProduct(context, ref),
                height: 52,
                borderRadius: 12,
              ),
            )
          : null,
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
          color: selected
              ? DesignColors.accent
              : isDark
                  ? DesignColors.darkSurfaceElevated
                  : DesignColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? DesignColors.accent
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
                ? Colors.black
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
        child: AddEditProductSheet(product: product),
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
class _ProductListTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    final stockAsync = ref.watch(_productStockProvider(product.id));
    final stock = stockAsync.valueOrNull;
    final hasStock = stock != null && stock > 0;
    final stockColor = hasStock ? DesignColors.success : DesignColors.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_rounded, color: DesignColors.brand, size: 22),
                const SizedBox(width: 14),

                // Product info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: titleColor,
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
                              color: DesignColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              categoryName,
                              style: const TextStyle(
                                fontSize: 10,
                                color: DesignColors.accent,
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
                        style: TextStyle(fontSize: 11, color: tertiaryColor),
                      ),
                      const SizedBox(height: 2),
                      stockAsync.when(
                        data: (qty) => Text(
                          hasStock
                              ? '$stock ${product.unit} in stock'
                              : 'Out of stock',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: stockColor,
                          ),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
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
        ),
      ),
    );
  }
}

// Category management bottom sheet - Premium
class _CategoryManagementSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;

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
                gradient: const [DesignColors.accent],
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
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: titleColor,
                                    ),
                                  ),
                                  if (cat.description != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      cat.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: tertiaryColor,
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
              error: (e, _) => EmptyState(
                icon: Icons.category_outlined,
                title: 'Couldn\'t load categories',
                subtitle: 'Check your connection and try again.',
                iconColor: DesignColors.error,
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(categoriesProvider),
              ),
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
        builder: (ctx, setDialogState) {
          final titleColor =
              isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
          final secondaryColor = isDark
              ? DesignColors.darkTextSecondary
              : DesignColors.textSecondary;
          final tertiaryColor = isDark
              ? DesignColors.darkTextTertiary
              : DesignColors.textTertiary;
          return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Add Category',
              style: TextStyle(fontWeight: FontWeight.w700, color: titleColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: titleColor),
                decoration: InputDecoration(
                  labelText: 'Category Name',
                  hintText: 'e.g. Painkillers',
                  hintStyle: TextStyle(color: tertiaryColor),
                  labelStyle: TextStyle(
                    color: secondaryColor,
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
                style: TextStyle(color: titleColor),
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  hintStyle: TextStyle(color: tertiaryColor),
                  labelStyle: TextStyle(
                    color: secondaryColor,
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
              ImagePickerSection(
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
              style: TextButton.styleFrom(foregroundColor: secondaryColor),
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
                backgroundColor: DesignColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Add'),
            ),
          ],
          );
        },
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
        builder: (ctx, setDialogState) {
          final titleColor =
              isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
          final secondaryColor = isDark
              ? DesignColors.darkTextSecondary
              : DesignColors.textSecondary;
          return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Edit Category',
              style: TextStyle(fontWeight: FontWeight.w700, color: titleColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: titleColor),
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
                style: TextStyle(color: titleColor),
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
              ImagePickerSection(
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
              style: TextButton.styleFrom(foregroundColor: secondaryColor),
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
                backgroundColor: DesignColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Save'),
            ),
          ],
          );
        },
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

