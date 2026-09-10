import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
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
final _catalogGridViewProvider = StateProvider<bool>((ref) => true);

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
final _productStockProvider = StreamProvider.family<double?, String>(
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
    final gridView = ref.watch(_catalogGridViewProvider);
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
                padding: const EdgeInsets.all(DesignSpacing.sm),
                decoration: BoxDecoration(
                  color: DesignColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
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
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                  DesignSpacing.sm + 2, DesignSpacing.md, DesignSpacing.xs + 2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(DesignSpacing.sm),
                    decoration: BoxDecoration(
                      color: DesignColors.brand.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                    ),
                    child: const Icon(Icons.inventory_2_rounded,
                        color: DesignColors.brand, size: 18),
                  ),
                  const SizedBox(width: DesignSpacing.sm + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Catalog',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: titleColor,
                                  ),
                        ),
                        Text(
                          'Products, pricing, and stock',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: secondaryColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: gridView ? 'Use list view' : 'Use grid view',
                    // >=44px tap target for the list/grid toggle.
                    constraints: const BoxConstraints(
                        minWidth: DesignSpacing.xl + 24,
                        minHeight: DesignSpacing.xl + 24),
                    padding: EdgeInsets.zero,
                    onPressed: () => ref
                        .read(_catalogGridViewProvider.notifier)
                        .state = !gridView,
                    icon: Icon(
                      gridView
                          ? Icons.view_list_rounded
                          : Icons.grid_view_rounded,
                      color: secondaryColor,
                      size: 21,
                    ),
                  ),
                ],
              ),
            ),
            // Search bar with consistent styling
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  DesignSpacing.lg, 0, DesignSpacing.lg, DesignSpacing.xs + 2),
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
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    borderSide:
                        const BorderSide(color: DesignColors.brand, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: DesignSpacing.lg,
                      vertical: DesignSpacing.md - 1),
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
                  // 48 keeps every chip's tap area >=44px tall.
                  height: DesignSpacing.xl + 28,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.md,
                        vertical: DesignSpacing.xs),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.xs),
                        child: _buildChip(
                          context,
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: DesignSpacing.xs),
                          child: _buildChip(
                            context,
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

            const SizedBox(height: 2),

            // Product count
            productsAsync.when(
              data: (products) {
                final filtered =
                    _filterProducts(products, selectedCategory, searchQuery);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                      DesignSpacing.xs, DesignSpacing.lg, DesignSpacing.xs + 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${filtered.length} product${filtered.length == 1 ? '' : 's'}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: secondaryColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                          ),
                        ],
                      ),
                      Text(
                        gridView ? 'Grid' : 'List',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                        subtitle: 'Check your connection and try again.',
                        iconColor: DesignColors.error,
                        actionLabel: 'Retry',
                        onAction: () =>
                            ref.invalidate(_catalogSyncProvider(currentUserId)),
                      );
                    }
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: searchQuery.isNotEmpty
                          ? 'No products match "$searchQuery"'
                          : 'No products yet',
                      subtitle: searchQuery.isNotEmpty
                          ? 'Try a different search or clear the filters.'
                          : perms.canEditProducts
                              ? 'Tap + to add a new product.'
                              : 'Ask an administrator to add products to this catalog.',
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
                        child: gridView
                            ? GridView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                    DesignSpacing.lg,
                                    0,
                                    DesignSpacing.lg,
                                    DesignSpacing.xxl),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: DesignSpacing.sm + 2,
                                  mainAxisSpacing: DesignSpacing.sm + 2,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: filtered.length,
                                // First-mount entrance: each card fades/rises
                                // in once, staggered (see StaggeredItem).
                                // Keys are stable per product, so pull-to-
                                // refresh never replays the choreography.
                                itemBuilder: (context, index) {
                                  final product = filtered[index];
                                  return StaggeredItem(
                                    itemKey: 'catalog-grid-${product.id}',
                                    index: index,
                                    child: _ProductGridCard(
                                      product: product,
                                      categoryName:
                                          categoryMap[product.categoryId] ??
                                              'Unknown',
                                      onEdit: perms.canEditProducts
                                          ? () => _showAddEditProduct(
                                              context, ref,
                                              product: product)
                                          : null,
                                      onDelete: perms.canEditProducts
                                          ? () => _confirmDelete(
                                              context, ref, product)
                                          : null,
                                      isDark: isDark,
                                    ),
                                  );
                                },
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                    DesignSpacing.lg,
                                    0,
                                    DesignSpacing.lg,
                                    DesignSpacing.xxl),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final product = filtered[index];
                                  return StaggeredItem(
                                    itemKey: 'catalog-list-${product.id}',
                                    index: index,
                                    child: _ProductListTile(
                                      product: product,
                                      categoryName:
                                          categoryMap[product.categoryId] ??
                                              'Unknown',
                                      onEdit: perms.canEditProducts
                                          ? () => _showAddEditProduct(
                                              context, ref,
                                              product: product)
                                          : null,
                                      onDelete: perms.canEditProducts
                                          ? () => _confirmDelete(
                                              context, ref, product)
                                          : null,
                                      isDark: isDark,
                                    ),
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
                loading: () => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      DesignSpacing.lg, 0, DesignSpacing.lg, DesignSpacing.xxl),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: DesignSpacing.sm + 2,
                    mainAxisSpacing: DesignSpacing.sm + 2,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: 6,
                  itemBuilder: (context, index) => const ProductCardShimmer(),
                ),
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
              minimum: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                  DesignSpacing.sm, DesignSpacing.lg, DesignSpacing.md),
              child: GradientButton(
                label: 'Add Product',
                icon: Icons.add_rounded,
                onPressed: () => _showAddEditProduct(context, ref),
                height: 52,
                borderRadius: DesignSpacing.radiusMd,
              ),
            )
          : null,
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool isDark = false,
  }) {
    final borderColor = selected
        ? DesignColors.accent
        : isDark
            ? DesignColors.darkBorder
            : DesignColors.surfaceBorder;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        // Pressed state: the InkWell ripple doubles as press feedback while
        // the container keeps its selected/unselected styling.
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: DesignSpacing.xl + 24,
            minHeight: DesignSpacing.xl + 24,
          ),
          child: AnimatedContainer(
            duration: DesignAnimation.fast,
            padding: const EdgeInsets.symmetric(
                horizontal: DesignSpacing.md, vertical: DesignSpacing.sm),
            decoration: BoxDecoration(
              color: selected
                  ? DesignColors.accent
                  : isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? Colors.black
                          : (isDark
                              ? DesignColors.darkTextPrimary
                              : DesignColors.textPrimary),
                    ),
              ),
            ),
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
        await catalog_cache.deleteProductFromCache(product.id);
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

class _ProductImage extends StatelessWidget {
  final String? imageUrl;
  final double height;
  final BorderRadius borderRadius;
  final bool isDark;

  const _ProductImage({
    required this.imageUrl,
    required this.height,
    required this.borderRadius,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackColor =
        isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceSubtle;
    final url = imageUrl?.trim();
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        height: height,
        width: double.infinity,
        color: fallbackColor,
        child: url == null || url.isEmpty
            ? const Center(
                child: Icon(Icons.inventory_2_outlined,
                    color: DesignColors.brand, size: 30),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.inventory_2_outlined,
                      color: DesignColors.brand, size: 30),
                ),
              ),
      ),
    );
  }
}

class _ProductActions extends StatelessWidget {
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ProductActions({this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (onEdit == null && onDelete == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Product actions',
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      onSelected: (value) {
        if (value == 'edit') onEdit?.call();
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (context) => [
        if (onEdit != null)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.edit_outlined, size: 19),
              title: Text('Edit product'),
            ),
          ),
        if (onDelete != null)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.remove_circle_outline_rounded,
                  color: DesignColors.error, size: 19),
              title: Text('Remove product'),
            ),
          ),
      ],
    );
  }
}

class _ProductGridCard extends ConsumerWidget {
  final Product product;
  final String categoryName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isDark;

  const _ProductGridCard({
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
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final stock = ref.watch(_productStockProvider(product.id)).valueOrNull;
    final inStock = stock != null && stock > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _ProductImage(
                    imageUrl: product.imageUrl,
                    height: 112,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(DesignSpacing.radiusLg)),
                    isDark: isDark,
                  ),
                  Positioned(
                    top: DesignSpacing.xs + 2,
                    right: DesignSpacing.xs + 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: surface.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                      ),
                      child:
                          _ProductActions(onEdit: onEdit, onDelete: onDelete),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(DesignSpacing.md,
                    DesignSpacing.sm, DesignSpacing.sm, DesignSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                            fontSize: 13,
                          ),
                    ),
                    const SizedBox(height: DesignSpacing.xs - 1),
                    Text(categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: secondaryColor)),
                    const SizedBox(height: DesignSpacing.sm - 1),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'KES ${product.price.toStringAsFixed(0)}',
                            style: DesignType.numeric(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: DesignColors.brand,
                            ),
                          ),
                        ),
                        Text(
                          inStock ? '${stock.toStringAsFixed(0)} left' : 'Out',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: inStock
                                        ? DesignColors.success
                                        : DesignColors.error,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Product list tile widget - compact image-first layout
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
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    final stockAsync = ref.watch(_productStockProvider(product.id));
    final stock = stockAsync.valueOrNull;
    final hasStock = stock != null && stock > 0;
    final stockLabel = stock == null || stock % 1 == 0
        ? stock?.toStringAsFixed(0) ?? ''
        : stock.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
    final stockColor = hasStock ? DesignColors.success : DesignColors.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          child: Container(
            padding: const EdgeInsets.all(DesignSpacing.md),
            decoration: BoxDecoration(
                color: surface,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusLg)),
            child: Row(
              children: [
                SizedBox(
                  width: 62,
                  child: _ProductImage(
                    imageUrl: product.imageUrl,
                    height: 62,
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: DesignSpacing.md),

                // Product info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: DesignSpacing.xs - 1),
                      Text('$categoryName · ${product.unit}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: tertiaryColor)),
                      const SizedBox(height: DesignSpacing.xs - 2),
                      stockAsync.when(
                        data: (qty) => Text(
                          hasStock
                              ? '$stockLabel ${product.unit} in stock'
                              : 'Out of stock',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
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

                const SizedBox(width: DesignSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'KES ${product.price.toStringAsFixed(0)}',
                      style: DesignType.numeric(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: DesignColors.brand,
                        letterSpacing: -0.3,
                      ),
                    ),
                    _ProductActions(onEdit: onEdit, onDelete: onDelete),
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
      padding: const EdgeInsets.fromLTRB(
          DesignSpacing.lg, 0, DesignSpacing.lg, DesignSpacing.lg),
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
                height: 44,
                expanded: false,
                borderRadius: DesignSpacing.radiusMd,
                gradient: const [DesignColors.accent],
              ),
            ),
          ),
          const SizedBox(height: DesignSpacing.sm),
          Divider(
            color:
                isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
            height: 1,
          ),
          const SizedBox(height: DesignSpacing.sm),
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
                      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.md,
                            vertical: DesignSpacing.xs + 2),
                        borderRadius: DesignSpacing.radiusMd,
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
                                borderRadius: BorderRadius.circular(
                                    DesignSpacing.radiusMd),
                              ),
                              child: Center(
                                child: Text(
                                  cat.name[0].toUpperCase(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: DesignColors.brand,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                            const SizedBox(width: DesignSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cat.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: titleColor,
                                        ),
                                  ),
                                  if (cat.description != null) ...[
                                    const SizedBox(
                                        height: DesignSpacing.xs - 2),
                                    Text(
                                      cat.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
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
                                padding: const EdgeInsets.all(DesignSpacing.sm),
                                decoration: BoxDecoration(
                                  color:
                                      DesignColors.info.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(
                                      DesignSpacing.radiusSm),
                                ),
                                child: const Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: DesignColors.info,
                                ),
                              ),
                            ),
                            const SizedBox(width: DesignSpacing.xs),
                            GestureDetector(
                              onTap: () => _confirmDeleteCategory(context, cat),
                              child: Container(
                                padding: const EdgeInsets.all(DesignSpacing.sm),
                                decoration: BoxDecoration(
                                  color: DesignColors.error
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(
                                      DesignSpacing.radiusSm),
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
              borderRadius: BorderRadius.circular(DesignSpacing.radiusXxl),
            ),
            title: Text('Add Category',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: titleColor)),
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
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.lg,
                        vertical: DesignSpacing.xl - 6),
                  ),
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                ),
                const SizedBox(height: DesignSpacing.md),
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
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.lg,
                        vertical: DesignSpacing.xl - 6),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: DesignSpacing.md),
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
                    final category = await getIt<ApiClient>().createCategory(
                      name: nameController.text.trim(),
                      description: descController.text.trim().isEmpty
                          ? null
                          : descController.text.trim(),
                      image: categoryImageUrl,
                      imagePublicId: categoryImagePublicId,
                    );
                    await catalog_cache.upsertCategoryCacheFromApi(category);
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
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: DesignSpacing.xxl,
                      vertical: DesignSpacing.md),
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
              borderRadius: BorderRadius.circular(DesignSpacing.radiusXxl),
            ),
            title: Text('Edit Category',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: titleColor)),
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
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.lg,
                        vertical: DesignSpacing.xl - 6),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: DesignSpacing.md),
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
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: DesignSpacing.lg,
                        vertical: DesignSpacing.xl - 6),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: DesignSpacing.md),
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
                    final category = await getIt<ApiClient>().updateCategory(
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
                    await catalog_cache.upsertCategoryCacheFromApi(category);
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
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: DesignSpacing.xxl,
                      vertical: DesignSpacing.md),
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
        await catalog_cache.deleteCategoryFromCache(cat.id);
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
