import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../../core/theme/design_system.dart';
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
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../domain/starter_products.dart';
import '../../domain/stock_status.dart';
import '../widgets/add_edit_product_sheet.dart';
import '../widgets/image_picker_section.dart';
import '../widgets/stock_kit.dart';
import '../widgets/stock_pane.dart';
import '../../../../core/utils/format.dart';

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
final _catalogGridViewProvider = StateProvider<bool>((ref) => false);
final _stockViewProvider = StateProvider<bool>((ref) => false);
final _lowStockOnlyProvider = StateProvider<bool>((ref) => false);
final _showArchivedProductsProvider = StateProvider<bool>((ref) => false);
final _lastCatalogScopeProvider = StateProvider<String?>((ref) => null);

/// Every active product, whatever the search or category, so the Low stock
/// count and the Stock view always cover the whole shop.
final _allActiveProductsProvider = StreamProvider<List<Product>>((ref) {
  return getIt<AppDatabase>().watchCatalogProducts(isActive: true);
});

/// How many are on the shelf for every product in this branch, kept live.
final _stockQuantitiesProvider = StreamProvider<Map<String, double>>((ref) {
  final branchId = getIt<StorageService>().getBranchId();
  return getIt<AppDatabase>().watchAllStock().map((rows) => {
        for (final row in rows)
          if (branchId == null || row.branchId == branchId)
            row.productId: row.quantity.toDouble(),
      });
});

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
    final scopeChanged = previousScope != null && previousScope != scope;
    // Providers cannot be changed while the widget tree is building, so the
    // reset for a different shop or branch runs right after this frame starts.
    Future.microtask(() {
      if (!mounted) return;
      if (scopeChanged) {
        ref.read(_selectedCategoryFilterProvider.notifier).state = null;
        ref.read(_searchQueryProvider.notifier).state = '';
        ref.read(_showArchivedProductsProvider.notifier).state = false;
      }
      ref.read(_lastCatalogScopeProvider.notifier).state = scope;
    });
    _searchController = TextEditingController(
      text: scopeChanged ? '' : ref.read(_searchQueryProvider),
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
      ref.read(_lowStockOnlyProvider.notifier).state = false;
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
    final stockView = ref.watch(_stockViewProvider);
    final lowOnly = ref.watch(_lowStockOnlyProvider);
    final quantities = ref.watch(_stockQuantitiesProvider).valueOrNull ??
        const <String, double>{};
    final allActive =
        ref.watch(_allActiveProductsProvider).valueOrNull ?? const <Product>[];
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final showArchivedProducts =
        isLocalWorkspace && ref.watch(_showArchivedProductsProvider);
    final perms = ref.watch(permissionsProvider);
    final businessLayout = ref.watch(businessLayoutProvider);
    final productSingular = businessLayout.productSingular;
    final productPlural = businessLayout.productsLabel.toLowerCase();
    final palette = SignInPalette.of(context);

    bool needsReorder(Product p) {
      final level = _levelOf(p, quantities);
      return level == StockLevel.low || level == StockLevel.out;
    }

    final reorderCount = allActive.where(needsReorder).length;

    Widget bottomAction() {
      if (stockView) {
        return perms.canManageStock
            ? BottomActionBar(
                label: 'Receive stock',
                icon: Icons.local_shipping_outlined,
                onTap: () => context.push('/inventory/receive'),
              )
            : const SizedBox.shrink();
      }
      if (!perms.canEditProducts || showArchivedProducts) {
        return const SizedBox.shrink();
      }
      return BottomActionBar(
        label: 'Add ${productSingular.toLowerCase()}',
        icon: Icons.add_rounded,
        onTap: () => _showAddEditProduct(context, ref,
            entityLabel: productSingular),
      );
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: businessLayout.actionLabel(
            '/products', businessLayout.productsLabel),
        showBackButton: false,
        actions: [
          IconButton(
            tooltip: 'View, removed items and categories',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _showOptions(context, ref,
                canEdit: perms.canEditProducts, isLocal: isLocalWorkspace),
          ),
        ],
      ),
      body: PageContainer(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: ProductsSwitch(
                stockSelected: stockView,
                productsLabel: businessLayout.productsLabel,
                onChanged: (value) =>
                    ref.read(_stockViewProvider.notifier).state = value,
              ),
            ),
            if (stockView)
              Expanded(
                child: StockPane(
                  products: allActive,
                  quantities: quantities,
                  canReceive: perms.canManageStock,
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: _SearchField(
                  controller: _searchController,
                  hint: businessLayout.catalogSearchHint,
                  showClear: searchQuery.isNotEmpty,
                  onChanged: _scheduleSearch,
                  onSubmitted: _commitSearch,
                  onClear: _clearSearch,
                ),
              ),
              _CategoryChips(
                categories: categoriesAsync.valueOrNull ?? const <Category>[],
                selected: selectedCategory,
                lowOnly: lowOnly,
                totalCount: allActive.length,
                reorderCount: reorderCount,
                onAll: () {
                  ref.read(_selectedCategoryFilterProvider.notifier).state =
                      null;
                  ref.read(_lowStockOnlyProvider.notifier).state = false;
                },
                onLow: () => ref.read(_lowStockOnlyProvider.notifier).state =
                    !lowOnly,
                onCategory: (id) {
                  ref.read(_selectedCategoryFilterProvider.notifier).state =
                      selectedCategory == id ? null : id;
                },
              ),
              const SizedBox(height: 4),
              Expanded(
                child: productsAsync.when(
                  data: (products) {
                    var filtered = _filterProducts(
                      products,
                      selectedCategory,
                      searchQuery,
                      businessLayout,
                      showArchived: showArchivedProducts,
                    );
                    if (lowOnly) {
                      filtered = filtered.where(needsReorder).toList();
                    }
                    if (filtered.isEmpty) {
                      return _emptyPane(
                        context,
                        ref,
                        products: products,
                        searchQuery: searchQuery,
                        lowOnly: lowOnly,
                        showArchived: showArchivedProducts,
                        syncAsync: syncAsync,
                        currentUserId: currentUserId,
                        canEdit: perms.canEditProducts,
                        productSingular: productSingular,
                        productPlural: productPlural,
                        profileId: businessLayout.preset.id,
                      );
                    }

                    final categoryMap = {
                      for (final category
                          in categoriesAsync.valueOrNull ?? const <Category>[])
                        category.id: category.name,
                    };
                    final results = gridView
                        ? GridView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: productGridColumns(
                                  MediaQuery.sizeOf(context).width),
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              mainAxisExtent: 176,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final product = filtered[index];
                              return _ProductGridCard(
                                product: product,
                                categoryName: categoryMap[product.categoryId] ??
                                    'Uncategorized',
                                quantity: quantities[product.id],
                              );
                            },
                          )
                        : _ProductList(
                            products: filtered,
                            categoryMap: categoryMap,
                            quantities: quantities,
                          );

                    return RefreshIndicator(
                      onRefresh: () async {
                        try {
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
                      backgroundColor: palette.card,
                      child: Column(
                        children: [
                          if (syncAsync.hasError && products.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
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
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                              child: InlineRetryNotice(
                                message: isPermissionDenied(categoriesAsync.error)
                                    ? 'Your role cannot view product categories. You can still browse and sell your saved products.'
                                    : 'Product categories are unavailable. ${loadErrorSubtitle(categoriesAsync.error)} You can still browse and sell your saved products.',
                                onRetry: isPermissionDenied(categoriesAsync.error)
                                    ? null
                                    : () => ref.invalidate(categoriesProvider),
                              ),
                            ),
                          Expanded(child: results),
                        ],
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
            bottomAction(),
          ],
        ),
      ),
    );
  }

  StockLevel _levelOf(Product p, Map<String, double> quantities) =>
      stockLevelFor(
        trackInventory: p.trackInventory,
        quantity: quantities[p.id],
        minStock: p.minStock,
      );

  /// What shows when the list has nothing to list: a first-run welcome, a
  /// search with no match, a quiet filter, or a failed first load.
  Widget _emptyPane(
    BuildContext context,
    WidgetRef ref, {
    required List<Product> products,
    required String searchQuery,
    required bool lowOnly,
    required bool showArchived,
    required AsyncValue<void> syncAsync,
    required String currentUserId,
    required bool canEdit,
    required String productSingular,
    required String productPlural,
    required String profileId,
  }) {
    final palette = SignInPalette.of(context);
    if (products.isEmpty && searchQuery.isEmpty && syncAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // A catalog that is empty because the first load failed must not read as
    // "no products yet".
    if (products.isEmpty && searchQuery.isEmpty && syncAsync.hasError) {
      return EmptyState(
        icon: Icons.sync_problem_rounded,
        title: 'Couldn\'t load your $productPlural catalog',
        subtitle: loadErrorSubtitle(syncAsync.error),
        iconColor: DesignColors.error,
        actionLabel: isPermissionDenied(syncAsync.error) ? null : 'Retry',
        onAction: isPermissionDenied(syncAsync.error)
            ? null
            : () => ref.invalidate(_catalogSyncProvider(currentUserId)),
      );
    }
    if (searchQuery.isNotEmpty) {
      return _EmptyCard(
        icon: Icons.search_rounded,
        title: 'No ${productSingular.toLowerCase()} called "$searchQuery"',
        body: 'Check the spelling, or add it as a new ${productSingular.toLowerCase()}.',
        actionLabel: canEdit ? 'Add "$searchQuery"' : null,
        onAction: canEdit
            ? () => _showAddEditProduct(context, ref,
                entityLabel: productSingular, initialName: searchQuery)
            : null,
      );
    }
    if (lowOnly) {
      return const _EmptyCard(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing is running low',
        body: 'Everything you count is above its warning level.',
      );
    }
    if (showArchived) {
      return const _EmptyCard(
        icon: Icons.inventory_2_outlined,
        title: 'Nothing removed',
        body: 'Products you remove wait here. You can bring them back.',
      );
    }
    final suggestions = starterProductsFor(profileId);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        _EmptyCard(
          icon: Icons.inventory_2_outlined,
          title: 'Nothing to sell yet',
          body: canEdit
              ? 'Add your first ${productSingular.toLowerCase()} and it appears on Sell straight away.'
              : 'Ask an administrator to add $productPlural to this shop.',
        ),
        if (canEdit) ...[
          const SizedBox(height: 18),
          Text('SHOPS LIKE YOURS START WITH',
              style: DesignType.numeric(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: palette.soft,
                  letterSpacing: 1.1)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in suggestions)
                ActionChip(
                  label: Text(name),
                  onPressed: () => _showAddEditProduct(context, ref,
                      entityLabel: productSingular, initialName: name),
                  backgroundColor: palette.card,
                  side: BorderSide(color: palette.line),
                  labelStyle: TextStyle(
                      color: palette.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Tap one to start a ${productSingular.toLowerCase()} with that name.',
              style: TextStyle(color: palette.soft, fontSize: 12.5)),
        ],
      ],
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref,
      {required bool canEdit, required bool isLocal}) {
    final palette = SignInPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: palette.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final grid = ref.watch(_catalogGridViewProvider);
          final removed = ref.watch(_showArchivedProductsProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: palette.line,
                          borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Show products as',
                      style: TextStyle(
                          color: palette.soft,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _OptionPill(
                          label: 'List',
                          icon: Icons.view_list_rounded,
                          selected: !grid,
                          onTap: () => ref
                              .read(_catalogGridViewProvider.notifier)
                              .state = false,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OptionPill(
                          label: 'Grid',
                          icon: Icons.grid_view_rounded,
                          selected: grid,
                          onTap: () => ref
                              .read(_catalogGridViewProvider.notifier)
                              .state = true,
                        ),
                      ),
                    ],
                  ),
                  if (isLocal) ...[
                    const SizedBox(height: 6),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: removed,
                      activeTrackColor: DesignColors.accent,
                      title: Text('Show removed products',
                          style: TextStyle(
                              color: palette.ink, fontWeight: FontWeight.w600)),
                      subtitle: Text('Bring one back from here.',
                          style: TextStyle(color: palette.soft, fontSize: 12.5)),
                      onChanged: (value) {
                        ref.read(_showArchivedProductsProvider.notifier).state =
                            value;
                        ref.read(_selectedCategoryFilterProvider.notifier).state =
                            null;
                        ref.read(_lowStockOnlyProvider.notifier).state = false;
                      },
                    ),
                  ],
                  if (canEdit)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.category_outlined, color: palette.ink),
                      title: Text('Categories',
                          style: TextStyle(
                              color: palette.ink, fontWeight: FontWeight.w600)),
                      subtitle: Text('Add, rename and put them in order',
                          style: TextStyle(color: palette.soft, fontSize: 12.5)),
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: palette.soft),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _showCategoryManagement(context, ref);
                      },
                    ),
                ],
              ),
            ),
          );
        },
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
      initialSize: 0.8,
      maxSize: 0.9,
      child: _CategoryManagementSheet(),
    );
  }

  void _showAddEditProduct(BuildContext context, WidgetRef ref,
      {Product? product, String? entityLabel, String? initialName}) {
    final resolvedLabel =
        entityLabel ?? ref.read(businessLayoutProvider).productSingular;
    openProductForm(
      context,
      product: product,
      entityLabel: resolvedLabel,
      initialName: initialName,
    );
  }
}

/// The search box under the Products switch.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.showClear,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final bool showClear;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    OutlineInputBorder outline(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextField(
      controller: controller,
      style: TextStyle(color: palette.ink),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: palette.faint),
        prefixIcon: Icon(Icons.search_rounded, color: palette.faint),
        suffixIcon: showClear
            ? IconButton(
                tooltip: 'Clear search',
                icon: Icon(Icons.clear_rounded, color: palette.faint),
                onPressed: onClear,
              )
            : null,
        filled: true,
        fillColor: palette.field,
        border: outline(palette.line),
        enabledBorder: outline(palette.line),
        focusedBorder: outline(DesignColors.brand, 1.5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// The row of filters: All, Low stock, then the shop's categories.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.lowOnly,
    required this.totalCount,
    required this.reorderCount,
    required this.onAll,
    required this.onLow,
    required this.onCategory,
  });

  final List<Category> categories;
  final String? selected;
  final bool lowOnly;
  final int totalCount;
  final int reorderCount;
  final VoidCallback onAll;
  final VoidCallback onLow;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context) {
    final active = categories.where((c) => c.isActive).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    Widget gap() => const SizedBox(width: 8);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _FilterChip(
            label: totalCount > 0 ? 'All $totalCount' : 'All',
            selected: selected == null && !lowOnly,
            onTap: onAll,
          ),
          if (reorderCount > 0 || lowOnly) ...[
            gap(),
            _FilterChip(
              label: 'Low stock $reorderCount',
              selected: lowOnly,
              amber: true,
              onTap: onLow,
            ),
          ],
          gap(),
          _FilterChip(
            label: 'Uncategorized',
            selected: selected == '',
            onTap: () => onCategory(''),
          ),
          for (final cat in active) ...[
            gap(),
            _FilterChip(
              label: cat.name,
              selected: selected == cat.id,
              onTap: () => onCategory(cat.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.amber = false,
  });

  final String label;
  final bool selected;
  final bool amber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final dark = palette.isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final onDark = palette.isDark ? DesignColors.darkBg : Colors.white;
    final Color bg;
    final Color border;
    final Color text;
    if (selected) {
      bg = dark;
      border = dark;
      text = onDark;
    } else if (amber) {
      bg = const Color(0xFFFBE9C8);
      border = const Color(0xFFECC98A);
      text = const Color(0xFF7A4A0C);
    } else {
      bg = palette.card;
      border = palette.line;
      text = palette.ink;
    }
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: DesignAnimation.fast,
            constraints: const BoxConstraints(minHeight: 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Text(
              label,
              style: TextStyle(
                  color: text, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionPill extends StatelessWidget {
  const _OptionPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: selected ? DesignColors.peach : palette.field,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
                color: selected ? DesignColors.accent : palette.line,
                width: selected ? 1.5 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 19,
                  color: selected ? const Color(0xFFA8430F) : palette.soft),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? const Color(0xFF6B2A08) : palette.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: DesignColors.peach,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: const Color(0xFFC4521A), size: 28),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: DesignType.display.copyWith(
                    color: palette.ink, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.soft, fontSize: 13.5, height: 1.4)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  foregroundColor: palette.ink,
                  side: BorderSide(color: palette.line),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
                child: Text(actionLabel!,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The list as one card of rows. Every row has the same height, so a long list
/// still builds only what is on screen.
class _ProductList extends StatelessWidget {
  const _ProductList({
    required this.products,
    required this.categoryMap,
    required this.quantities,
  });

  static const double rowHeight = 64;

  final List<Product> products;
  final Map<String, String> categoryMap;
  final Map<String, double> quantities;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        const margin = 20.0;
        final available = box.maxHeight - 16;
        final wanted = products.length * rowHeight;
        final height = wanted < available ? wanted : available;
        return Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.fromLTRB(margin, 4, margin, 12),
            height: height + 2,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              border: Border.all(color: palette.line),
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemExtent: rowHeight,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return _ProductListTile(
                  product: product,
                  categoryName:
                      categoryMap[product.categoryId] ?? 'Uncategorized',
                  quantity: quantities[product.id],
                  showDivider: index != products.length - 1,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ProductListTile extends StatelessWidget {
  const _ProductListTile({
    required this.product,
    required this.categoryName,
    required this.quantity,
    required this.showDivider,
  });

  final Product product;
  final String categoryName;
  final double? quantity;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final level = stockLevelFor(
      trackInventory: product.trackInventory,
      quantity: quantity,
      minStock: product.minStock,
    );
    return Semantics(
      button: true,
      label: '${product.name}, ${formatMoney(product.price)}, '
          '${stockWords(level, quantity)}',
      child: InkWell(
        onTap: () => context.push('/products/${product.id}'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(bottom: BorderSide(color: palette.line))
                : null,
          ),
          child: Row(
            children: [
              ProductAvatar(
                name: product.name,
                imageUrl: product.imageUrl,
                tint: product.isActive
                    ? null
                    : DesignColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: palette.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    Text('$categoryName · per ${product.unit}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.soft, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatMoney(product.price),
                      style: DesignType.numeric(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: palette.ink)),
                  const SizedBox(height: 3),
                  product.isActive
                      ? StockChip(level: level, quantity: quantity)
                      : const _RemovedChip(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemovedChip extends StatelessWidget {
  const _RemovedChip();

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: palette.field,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('Removed',
          style: TextStyle(
              color: palette.soft, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _ProductGridCard extends StatelessWidget {
  const _ProductGridCard({
    required this.product,
    required this.categoryName,
    required this.quantity,
  });

  final Product product;
  final String categoryName;
  final double? quantity;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final level = stockLevelFor(
      trackInventory: product.trackInventory,
      quantity: quantity,
      minStock: product.minStock,
    );
    return Semantics(
      button: true,
      label: '${product.name}, ${formatMoney(product.price)}, '
          '${stockWords(level, quantity)}',
      child: InkWell(
        onTap: () => context.push('/products/${product.id}'),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            border: Border.all(color: palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductAvatar(
                  name: product.name, imageUrl: product.imageUrl, size: 48),
              const SizedBox(height: 8),
              Text(product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: palette.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              Text(categoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.soft, fontSize: 11.5)),
              const Spacer(),
              Text(formatMoney(product.price),
                  style: DesignType.numeric(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: palette.ink)),
              const SizedBox(height: 4),
              product.isActive
                  ? StockChip(level: level, quantity: quantity)
                  : const _RemovedChip(),
            ],
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
    final products =
        ref.watch(_allActiveProductsProvider).valueOrNull ?? const <Product>[];
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final palette = SignInPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Groups that show as filters on Sell and Products. The order here is the order there.',
            style: TextStyle(color: palette.soft, fontSize: 13, height: 1.4),
          ),
        ),
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
              return ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                buildDefaultDragHandles: false,
                itemCount: sorted.length,
                onReorderItem: (from, to) =>
                    _reorder(context, ref, sorted, from, to, isLocalWorkspace),
                proxyDecorator: (child, index, animation) =>
                    Material(color: Colors.transparent, child: child),
                itemBuilder: (context, index) {
                  final cat = sorted[index];
                  final isProtectedDefaultCategory =
                      isLocalWorkspace && cat.id == 'local-default-category';
                  final isArchivedCategory = isLocalWorkspace && !cat.isActive;
                  final count =
                      products.where((p) => p.categoryId == cat.id).length;
                  return Padding(
                    key: ValueKey(cat.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: palette.card,
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusLg),
                        border: Border.all(color: palette.line),
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Icon(Icons.drag_indicator_rounded,
                                  color: palette.faint, semanticLabel: 'Drag to reorder'),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => _showEditCategoryDialog(context, cat),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cat.isActive ? cat.name : '${cat.name} · Removed',
                                      style: TextStyle(
                                          color: palette.ink,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      '$count ${count == 1 ? 'product' : 'products'}',
                                      style: TextStyle(
                                          color: palette.soft, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: isProtectedDefaultCategory
                                ? 'This one stays'
                                : isArchivedCategory
                                    ? 'Bring it back'
                                    : isLocalWorkspace
                                        ? 'Remove category'
                                        : 'Delete category',
                            onPressed: isProtectedDefaultCategory
                                ? null
                                : () => _confirmDeleteCategory(context, ref, cat),
                            icon: Icon(
                              isProtectedDefaultCategory
                                  ? Icons.lock_outline_rounded
                                  : isArchivedCategory
                                      ? Icons.unarchive_outlined
                                      : Icons.remove_circle_outline_rounded,
                              size: 20,
                              color: isArchivedCategory
                                  ? DesignColors.success
                                  : palette.soft,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Text(
            'Products with no category show under "Uncategorized". Removing a category never removes its products.',
            style: TextStyle(color: palette.soft, fontSize: 12.5, height: 1.4),
          ),
        ),
        BottomActionBar(
          label: 'Add category',
          icon: Icons.add_rounded,
          onTap: () => _showAddCategoryDialog(context),
        ),
      ],
    );
  }

  /// Saves the new order. Only a shop on this device can reorder.
  Future<void> _reorder(BuildContext context, WidgetRef ref,
      List<Category> sorted, int from, int to, bool isLocal) async {
    if (!isLocal) return;
    final moved = [...sorted];
    moved.insert(to, moved.removeAt(from));
    final db = getIt<AppDatabase>();
    final now = DateTime.now();
    try {
      for (var i = 0; i < moved.length; i++) {
        if (moved[i].sortOrder == i) continue;
        await db.updateCategory(
          moved[i].id,
          CategoriesCompanion(sortOrder: Value(i), updatedAt: Value(now)),
        );
      }
      ref.invalidate(catalog_cache.categoriesProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the order. ${apiErrorMessage(e)}')),
      );
    }
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
