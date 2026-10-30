import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/stock_quantity_display.dart';
import '../../../../core/widgets/motion.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/load_error.dart';
import '../../../../core/utils/business_layout_search.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../sales/presentation/providers/catalog_provider.dart'
    as catalog_cache;
import '../providers/catalog_categories_provider.dart';
import '../widgets/add_edit_product_sheet.dart';
import '../widgets/image_picker_section.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/workspace_image.dart';

// Providers for the products screen
final _productsProvider = StreamProvider<List<Product>>((ref) {
  final showArchived = getIt<AuthService>().isLocalWorkspace &&
      ref.watch(_showArchivedProductsProvider);
  return getIt<AppDatabase>().watchCatalogProducts(
    isActive: !showArchived,
    categoryId: ref.watch(_selectedCategoryFilterProvider),
    searchQuery: ref.watch(_searchQueryProvider),
  );
});

final _selectedCategoryFilterProvider = StateProvider<String?>((ref) => null);
final _searchQueryProvider = StateProvider<String>((ref) => '');
final _catalogGridViewProvider = StateProvider<bool>((ref) => true);
final _showArchivedProductsProvider = StateProvider<bool>((ref) => false);
final _lastCatalogScopeProvider = StateProvider<String?>((ref) => null);

// Search and category filters belong to one shop/branch. Without this scope,
// switching shops can leave the previous shop's category selected and make a
// perfectly healthy catalog look empty.
final _catalogScopeProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  final storage = getIt<StorageService>();
  final tenantId =
      user?['tenantId']?.toString() ?? storage.getTenantId() ?? '';
  final branchId =
      user?['branchId']?.toString() ?? storage.getBranchId() ?? '';
  final workspaceKind =
      getIt<AuthService>().isLocalWorkspace ? 'local' : 'connected';
  return [
    user?['id']?.toString() ?? '',
    tenantId,
    branchId,
    workspaceKind,
  ].join('\u0000');
});

// Keyed by the user, tenant, branch, and workspace type so switching shop
// scope always gets a fresh provider instance and re-runs the sync.
final _catalogSyncProvider =
    FutureProvider.family<void, String>((ref, catalogScope) async {
  await catalog_cache.syncCatalogCacheFromApi();
  ref.invalidate(catalog_cache.filteredProductsProvider);
  ref.invalidate(catalog_cache.favoriteProductsProvider);
  ref.invalidate(catalog_cache.categoriesProvider);
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

String _productStockQuantityLabel(double quantity) {
  if (quantity % 1 == 0) return quantity.toStringAsFixed(0);
  return quantity
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  late final TextEditingController _searchController;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    final scope = ref.read(_catalogScopeProvider);
    final previousScope = ref.read(_lastCatalogScopeProvider);
    if (previousScope != null && previousScope != scope) {
      ref.read(_selectedCategoryFilterProvider.notifier).state = null;
      ref.read(_searchQueryProvider.notifier).state = '';
      ref.read(_showArchivedProductsProvider.notifier).state = false;
    }
    ref.read(_lastCatalogScopeProvider.notifier).state = scope;
    _searchController = TextEditingController(
      text: ref.read(_searchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      ref.read(_searchQueryProvider.notifier).state = value;
    });
  }

  void _commitSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    ref.read(_searchQueryProvider.notifier).state = value;
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _searchController.clear();
    _commitSearch('');
  }

  @override
  Widget build(BuildContext context) {
    final catalogScope = ref.watch(_catalogScopeProvider);
    final currentUserId =
        ref.watch(currentUserProvider)?['id'] as String? ?? 'logged-out';
    ref.listen<String>(_catalogScopeProvider, (previous, next) {
      if (previous == null || previous == next) return;
      _searchDebounce?.cancel();
      _searchDebounce = null;
      ref.read(_lastCatalogScopeProvider.notifier).state = next;
      ref.read(_selectedCategoryFilterProvider.notifier).state = null;
      ref.read(_searchQueryProvider.notifier).state = '';
      ref.read(_showArchivedProductsProvider.notifier).state = false;
    });
    ref.listen<String>(_searchQueryProvider, (previous, next) {
      if (_searchController.text == next) return;
      _searchController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    });

    final syncAsync = ref.watch(_catalogSyncProvider(catalogScope));
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(_productsProvider);
    final selectedCategory = ref.watch(_selectedCategoryFilterProvider);
    final searchQuery = ref.watch(_searchQueryProvider);
    final gridView = ref.watch(_catalogGridViewProvider);
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final showArchivedProducts =
        isLocalWorkspace && ref.watch(_showArchivedProductsProvider);
    final perms = ref.watch(permissionsProvider);
    final businessLayout = ref.watch(businessLayoutProvider);
    final productName = businessLayout.productSingular.toLowerCase();
    final productPlural = businessLayout.productsLabel.toLowerCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;

    return Scaffold(
      appBar: BrandedAppBar(
        title: businessLayout.actionLabel(
            '/products', businessLayout.productsLabel),
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
                          '${businessLayout.productsLabel}, pricing, and stock',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: secondaryColor),
                        ),
                      ],
                    ),
                  ),
                  if (perms.canEditProducts)
                    IconButton(
                      tooltip: 'Add ${businessLayout.productSingular}',
                      constraints: const BoxConstraints(
                          minWidth: DesignSpacing.xl + 24,
                          minHeight: DesignSpacing.xl + 24),
                      padding: EdgeInsets.zero,
                      onPressed: () => _showAddEditProduct(
                        context,
                        ref,
                        entityLabel: businessLayout.productSingular,
                      ),
                      icon: Container(
                        padding: const EdgeInsets.all(DesignSpacing.sm),
                        decoration: BoxDecoration(
                          color: DesignColors.accent.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusMd),
                        ),
                        child: const Icon(Icons.add_rounded,
                            color: DesignColors.accent, size: 21),
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
                controller: _searchController,
                style: TextStyle(color: titleColor),
                decoration: InputDecoration(
                  hintText: businessLayout.catalogSearchHint,
                  hintStyle: TextStyle(color: tertiaryColor),
                  prefixIcon: Icon(Icons.search_rounded, color: tertiaryColor),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear search',
                          icon: Icon(Icons.clear_rounded, color: tertiaryColor),
                          onPressed: _clearSearch,
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
                onChanged: _scheduleSearch,
                onSubmitted: _commitSearch,
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
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.xs),
                        child: _buildChip(
                          context,
                          label: 'Uncategorized',
                          selected: selectedCategory == '',
                          onTap: () => ref
                              .read(_selectedCategoryFilterProvider.notifier)
                              .state = selectedCategory == '' ? null : '',
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
                final filtered = _filterProducts(
                  products,
                  selectedCategory,
                  searchQuery,
                  businessLayout,
                  showArchived: showArchivedProducts,
                );
                return Padding(
                  padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                      DesignSpacing.xs, DesignSpacing.lg, DesignSpacing.xs + 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${filtered.length} ${filtered.length == 1 ? productName : productPlural}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: secondaryColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLocalWorkspace)
                            TextButton.icon(
                              onPressed: () {
                                ref
                                    .read(
                                        _showArchivedProductsProvider.notifier)
                                    .state = !showArchivedProducts;
                                ref
                                    .read(_selectedCategoryFilterProvider
                                        .notifier)
                                    .state = null;
                              },
                              icon: Icon(
                                showArchivedProducts
                                    ? Icons.inventory_2_outlined
                                    : Icons.archive_outlined,
                                size: 16,
                              ),
                              label: Text(showArchivedProducts
                                  ? 'Active products'
                                  : 'Archived'),
                              style: TextButton.styleFrom(
                                foregroundColor: DesignColors.brand,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: DesignSpacing.xs),
                              ),
                            ),
                          Text(
                            gridView ? 'Grid' : 'List',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: tertiaryColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                          ),
                        ],
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
                  final filtered = _filterProducts(
                    products,
                    selectedCategory,
                    searchQuery,
                    businessLayout,
                    showArchived: showArchivedProducts,
                  );
                  if (filtered.isEmpty) {
                    if (products.isEmpty &&
                        searchQuery.isEmpty &&
                        syncAsync.isLoading) {
                      return Center(
                        child: Padding(
                          padding: DesignSpacing.paddingScreen,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: DesignSpacing.md),
                              Text(
                                'Loading your ${businessLayout.productsLabel.toLowerCase()} catalog…',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    // Distinguish a genuinely empty catalog from a local
                    // cache that's empty because the sync from the backend
                    // failed — showing "no products yet" in the latter case
                    // would wrongly suggest the org has no products at all.
                    if (products.isEmpty &&
                        searchQuery.isEmpty &&
                        syncAsync.hasError) {
                      return EmptyState(
                        icon: Icons.sync_problem_rounded,
                        title:
                            'Couldn\'t load your ${businessLayout.productsLabel.toLowerCase()} catalog',
                        subtitle: loadErrorSubtitle(syncAsync.error),
                        iconColor: DesignColors.error,
                        actionLabel: isPermissionDenied(syncAsync.error)
                            ? null
                            : 'Retry',
                        onAction: isPermissionDenied(syncAsync.error)
                            ? null
                            : () => ref.invalidate(
                                _catalogSyncProvider(currentUserId)),
                      );
                    }
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: searchQuery.isNotEmpty
                          ? 'No $productPlural match "$searchQuery"'
                          : 'No $productPlural yet',
                      subtitle: searchQuery.isNotEmpty
                          ? 'Try a different search or clear the filters.'
                          : perms.canEditProducts
                              ? 'Tap + to add a new $productName.'
                              : 'Ask an administrator to add $productPlural to this catalog.',
                    );
                  }

                  final categoryMap = {
                    for (final category
                        in categoriesAsync.valueOrNull ?? const <Category>[])
                      category.id: category.name,
                  };
                  final productResults = gridView
                      ? GridView.builder(
                          padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                              0, DesignSpacing.lg, DesignSpacing.xxl + 64),
                          // Photo cards need the tall shape; without any
                          // photos the same card left a big empty block
                          // under the price, so size it to its content.
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: productGridColumns(
                                MediaQuery.sizeOf(context).width),
                            crossAxisSpacing: DesignSpacing.sm + 2,
                            mainAxisSpacing: DesignSpacing.sm + 2,
                            childAspectRatio: 0.72,
                            // Fixed row height for photo-less cards: image
                            // header + a two-line name + category + price,
                            // so nothing is left empty below the price.
                            mainAxisExtent: filtered.any(
                                    (p) => (p.imageUrl ?? '').trim().isNotEmpty)
                                ? null
                                : 158,
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
                                categoryName: categoryMap[product.categoryId] ??
                                    'Uncategorized',
                                onEdit: perms.canEditProducts
                                    ? () => _showAddEditProduct(context, ref,
                                        product: product)
                                    : null,
                                onDelete: perms.canEditProducts
                                    ? () =>
                                        _confirmDelete(context, ref, product)
                                    : null,
                                isDark: isDark,
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                              0, DesignSpacing.lg, DesignSpacing.xxl + 64),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final product = filtered[index];
                            return StaggeredItem(
                              itemKey: 'catalog-list-${product.id}',
                              index: index,
                              child: _ProductListTile(
                                product: product,
                                categoryName: categoryMap[product.categoryId] ??
                                    'Uncategorized',
                                onEdit: perms.canEditProducts
                                    ? () => _showAddEditProduct(context, ref,
                                        product: product)
                                    : null,
                                onDelete: perms.canEditProducts
                                    ? () =>
                                        _confirmDelete(context, ref, product)
                                    : null,
                                isDark: isDark,
                              ),
                            );
                          },
                        );

                  return RefreshIndicator(
                    onRefresh: () async {
                      try {
                        // Keep the refresh indicator visible until the
                        // remote catalog has actually been fetched and
                        // written to Drift.
                        ref.invalidate(_catalogSyncProvider(currentUserId));
                        await ref
                            .read(_catalogSyncProvider(currentUserId).future);
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not refresh the catalog. Your saved products are still available.',
                            ),
                          ),
                        );
                      }
                    },
                    color: DesignColors.brand,
                    backgroundColor: isDark
                        ? DesignColors.darkSurfaceElevated
                        : Colors.white,
                    child: Column(
                      children: [
                        if (syncAsync.hasError && products.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              DesignSpacing.lg,
                              DesignSpacing.sm,
                              DesignSpacing.lg,
                              DesignSpacing.sm,
                            ),
                            child: InlineRetryNotice(
                              message: isPermissionDenied(syncAsync.error)
                                  ? 'Saved products are shown, but your role cannot refresh the catalog. Ask an administrator to check product access.'
                                  : 'Catalog refresh failed. Saved products are still available, but prices and stock may be out of date.',
                              onRetry: isPermissionDenied(syncAsync.error)
                                  ? null
                                  : () => ref.invalidate(
                                      _catalogSyncProvider(currentUserId)),
                            ),
                          ),
                        if (categoriesAsync.hasError)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              DesignSpacing.lg,
                              DesignSpacing.sm,
                              DesignSpacing.lg,
                              DesignSpacing.sm,
                            ),
                            child: InlineRetryNotice(
                              message: isPermissionDenied(categoriesAsync.error)
                                  ? 'Your role cannot view product categories. You can still browse and sell your saved products.'
                                  : 'Product categories are unavailable. ${loadErrorSubtitle(categoriesAsync.error)} You can still browse and sell your saved products.',
                              onRetry: isPermissionDenied(categoriesAsync.error)
                                  ? null
                                  : () => ref.invalidate(categoriesProvider),
                            ),
                          ),
                        Expanded(child: productResults),
                      ],
                    ),
                  );
                },
                loading: () => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, 0,
                      DesignSpacing.lg, DesignSpacing.xxl + 64),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        productGridColumns(MediaQuery.sizeOf(context).width),
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
                  subtitle: loadErrorSubtitle(e),
                  iconColor: DesignColors.error,
                  actionLabel: isPermissionDenied(e) ? null : 'Retry',
                  onAction: isPermissionDenied(e)
                      ? null
                      : () => ref.invalidate(_productsProvider),
                ),
              ),
            ),
          ],
        ),
      ),
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
        borderRadius: BorderRadius.circular(DesignSpacing.radiusFull),
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
                  ? (isDark
                      ? DesignColors.accent.withValues(alpha: 0.18)
                      : DesignColors.peach)
                  : isDark
                      ? DesignColors.darkSurfaceElevated
                      : Colors.white,
              borderRadius: BorderRadius.circular(DesignSpacing.radiusFull),
              border: Border.all(
                  color: selected
                      ? DesignColors.accent.withValues(alpha: 0.55)
                      : borderColor),
            ),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? DesignColors.accentDark
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
    List<Product> products,
    String? categoryId,
    String query,
    BusinessLayoutConfig businessLayout, {
    required bool showArchived,
  }) {
    var filtered = products.where((p) => p.isActive != showArchived).toList();
    if (categoryId != null) {
      filtered = filtered.where((p) => p.categoryId == categoryId).toList();
    }
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      filtered = filtered
          .where((product) => businessLayoutProductMatchesSearch(
                name: product.name,
                code: product.sku,
                metadata: product.metadata,
                layout: businessLayout,
                query: q,
              ))
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
      {Product? product, String? entityLabel}) {
    final resolvedLabel =
        entityLabel ?? ref.read(businessLayoutProvider).productSingular;
    GlassBottomSheet.show(
      context,
      title: product == null ? 'Add $resolvedLabel' : 'Edit $resolvedLabel',
      initialSize: 0.9,
      maxSize: 0.95,
      child: AddEditProductSheet(
        product: product,
        entityLabel: resolvedLabel,
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Product product) async {
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final isArchiveAction = isLocalWorkspace && product.isActive;
    final isRestoreAction = isLocalWorkspace && !product.isActive;
    final confirmed = await showConfirmDialog(
      context,
      title: isArchiveAction
          ? 'Archive product'
          : isRestoreAction
              ? 'Restore product'
              : 'Delete Product',
      message: isArchiveAction
          ? 'Hide "${product.name}" from the POS? Its sales and history will be kept. You can restore it later from Archived.'
          : isRestoreAction
              ? 'Make "${product.name}" available in the POS again?'
              : 'Are you sure you want to delete "${product.name}"?',
      confirmLabel: isArchiveAction
          ? 'Archive'
          : isRestoreAction
              ? 'Restore'
              : 'Delete',
      confirmColor: isRestoreAction ? DesignColors.accent : DesignColors.error,
    );
    if (confirmed) {
      try {
        if (isLocalWorkspace) {
          await getIt<AppDatabase>().setLocalProductActive(
            product.id,
            isActive: !product.isActive,
          );
        } else {
          await getIt<ApiClient>().deleteProduct(product.id);
          await catalog_cache.deleteProductFromCache(product.id);
        }
        // The POS grid is a cached FutureProvider, so invalidate its snapshots
        // as well as updating the live Products stream after a deletion.
        if (context.mounted) {
          ref.invalidate(catalog_cache.filteredProductsProvider);
          ref.invalidate(catalog_cache.favoriteProductsProvider);
          ref.invalidate(catalog_cache.categoriesProvider);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not update product. ${apiErrorMessage(e)}'),
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
        child: WorkspaceImage(
          source: url,
          fit: BoxFit.cover,
          placeholder: const Center(
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
  final bool productIsActive;

  const _ProductActions({
    this.onEdit,
    this.onDelete,
    required this.productIsActive,
  });

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
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              leading: Icon(
                getIt<AuthService>().isLocalWorkspace && !productIsActive
                    ? Icons.unarchive_outlined
                    : getIt<AuthService>().isLocalWorkspace
                        ? Icons.archive_outlined
                        : Icons.remove_circle_outline_rounded,
                color: getIt<AuthService>().isLocalWorkspace && !productIsActive
                    ? DesignColors.success
                    : DesignColors.error,
                size: 19,
              ),
              title: Text(
                getIt<AuthService>().isLocalWorkspace
                    ? productIsActive
                        ? 'Archive product'
                        : 'Restore product'
                    : 'Remove product',
              ),
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
    final stockAsync = ref.watch(_productStockProvider(product.id));
    final stock = stockAsync.valueOrNull;
    final stockStatus = !product.trackInventory
        ? 'Not tracked'
        : stockAsync.when(
            data: (quantity) => quantity == null
                ? 'No stock record'
                : quantity > 0
                    ? '${_productStockQuantityLabel(quantity)} left'
                    : 'Out',
            loading: () => 'Checking…',
            error: (_, __) => 'Unavailable',
          );
    final stockStatusColor = !product.trackInventory
        ? secondaryColor
        : stockAsync.hasError
            ? DesignColors.warning
            : stockAsync.isLoading || stock == null
                ? secondaryColor
                : stock > 0
                    ? DesignColors.success
                    : DesignColors.error;

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
                    // A photo-less card gets a slim header instead of a tall
                    // empty image block.
                    height: (product.imageUrl ?? '').trim().isEmpty ? 52 : 112,
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
                      child: _ProductActions(
                        onEdit: onEdit,
                        onDelete: onDelete,
                        productIsActive: product.isActive,
                      ),
                    ),
                  ),
                ],
              ),
              // Expanded + Spacer: the card fills its grid cell, the name and
              // category sit at the top and price/stock anchor to the bottom, so
              // spare height can never show up as an empty block under the price
              // and a long two-line name can never overflow.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(DesignSpacing.md,
                      DesignSpacing.sm, DesignSpacing.sm, DesignSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
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
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatMoney(product.price),
                              style: DesignType.numeric(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: DesignColors.brand,
                              ),
                            ),
                          ),
                          Text(
                            stockStatus,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: stockStatusColor,
                                ),
                          ),
                        ],
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
                        data: (qty) {
                          final message = !product.trackInventory
                              ? 'Stock not tracked'
                              : qty == null
                                  ? 'Stock not recorded'
                                  : qty > 0
                                      ? '${_productStockQuantityLabel(qty)} ${pluralizeUnit(product.unit, qty)} in stock'
                                      : 'Out of stock';
                          final color = !product.trackInventory || qty == null
                              ? tertiaryColor
                              : qty > 0
                                  ? DesignColors.success
                                  : DesignColors.error;
                          return Text(
                            message,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                          );
                        },
                        loading: () => Text(
                          'Checking stock…',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: tertiaryColor),
                        ),
                        error: (_, __) => Text(
                          'Stock unavailable',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: DesignColors.warning),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: DesignSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(product.price),
                      style: DesignType.numeric(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: DesignColors.brand,
                        letterSpacing: -0.3,
                      ),
                    ),
                    _ProductActions(
                      onEdit: onEdit,
                      onDelete: onDelete,
                      productIsActive: product.isActive,
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
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
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
                    final isProtectedDefaultCategory =
                        isLocalWorkspace && cat.id == 'local-default-category';
                    final isArchivedCategory =
                        isLocalWorkspace && !cat.isActive;
                    final categoryActionColor = isProtectedDefaultCategory
                        ? tertiaryColor
                        : isArchivedCategory
                            ? DesignColors.success
                            : DesignColors.error;
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
                                    cat.isActive
                                        ? cat.name
                                        : '${cat.name} · Archived',
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
                              onTap: isProtectedDefaultCategory
                                  ? null
                                  : () =>
                                      _confirmDeleteCategory(context, ref, cat),
                              child: Container(
                                padding: const EdgeInsets.all(DesignSpacing.sm),
                                decoration: BoxDecoration(
                                  color: categoryActionColor.withValues(
                                      alpha: 0.08),
                                  borderRadius: BorderRadius.circular(
                                      DesignSpacing.radiusSm),
                                ),
                                child: Icon(
                                  isProtectedDefaultCategory
                                      ? Icons.lock_outline_rounded
                                      : isArchivedCategory
                                          ? Icons.unarchive_outlined
                                          : isLocalWorkspace
                                              ? Icons.archive_outlined
                                              : Icons.delete_outline_rounded,
                                  size: 18,
                                  color: categoryActionColor,
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
                subtitle: loadErrorSubtitle(e),
                iconColor: DesignColors.error,
                actionLabel: isPermissionDenied(e) ? null : 'Retry',
                onAction: isPermissionDenied(e)
                    ? null
                    : () => ref.invalidate(categoriesProvider),
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
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
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
                    if (isLocalWorkspace) {
                      final now = DateTime.now();
                      await getIt<AppDatabase>().insertCategory(
                        CategoriesCompanion.insert(
                          id: const Uuid().v4(),
                          name: nameController.text.trim(),
                          description: Value(descController.text.trim().isEmpty
                              ? null
                              : descController.text.trim()),
                          imageUrl: Value(categoryImageUrl),
                          createdAt: now,
                          updatedAt: now,
                        ),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      return;
                    }
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
                          content: Text(
                              'Could not add category. ${apiErrorMessage(e)}'),
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
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
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
                    if (isLocalWorkspace) {
                      await getIt<AppDatabase>().updateCategory(
                        cat.id,
                        CategoriesCompanion(
                          name: Value(nameController.text.trim()),
                          description: Value(descController.text.trim().isEmpty
                              ? null
                              : descController.text.trim()),
                          imageUrl: Value(categoryImageUrl),
                          updatedAt: Value(DateTime.now()),
                        ),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      return;
                    }
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
                          content: Text(
                              'Could not update category. ${apiErrorMessage(e)}'),
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

  void _confirmDeleteCategory(
      BuildContext context, WidgetRef ref, Category cat) async {
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final confirmed = await showConfirmDialog(
      context,
      title: isLocalWorkspace
          ? cat.isActive
              ? 'Archive category'
              : 'Restore category'
          : 'Delete Category',
      message: isLocalWorkspace
          ? cat.isActive
              ? 'Hide "${cat.name}" from the POS filters? Products, sales, and reports will keep their category history. You can restore it from category management.'
              : 'Make "${cat.name}" available in the POS filters again?'
          : 'Delete "${cat.name}"? Products in this category will need reassigning.',
      confirmLabel: isLocalWorkspace
          ? cat.isActive
              ? 'Archive'
              : 'Restore'
          : 'Delete',
      confirmColor: isLocalWorkspace && !cat.isActive
          ? DesignColors.accent
          : DesignColors.error,
    );
    if (confirmed) {
      try {
        if (isLocalWorkspace) {
          await getIt<AppDatabase>().setLocalCategoryActive(
            cat.id,
            isActive: !cat.isActive,
          );
          ref.read(_selectedCategoryFilterProvider.notifier).state = null;
        } else {
          await getIt<ApiClient>().deleteCategory(cat.id);
          await catalog_cache.deleteCategoryFromCache(cat.id);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not update category. ${apiErrorMessage(e)}'),
              backgroundColor: DesignColors.error,
            ),
          );
        }
      }
    }
  }
}
