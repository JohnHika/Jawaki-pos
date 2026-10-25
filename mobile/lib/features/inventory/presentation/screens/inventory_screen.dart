import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/auth/app_roles.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/stock_quantity_display.dart';
import '../../../sales/presentation/providers/catalog_provider.dart'
    show syncCatalogCacheFromApi;
import '../widgets/product_picker_dialog.dart';
import '../../../../core/widgets/motion_kit_extras.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  static const _uuid = Uuid();
  int _totalItems = 0;
  int _lowStockCount = 0;
  double _totalValue = 0;
  List<Map<String, dynamic>> _inventoryItems = [];
  List<Map<String, dynamic>> _lowStockItems = [];
  bool _isLoading = true;
  String _stockSearchQuery = '';
  String? _transferProductId;
  String? _transferToBranchId;
  late Future<List<dynamic>> _branchesFuture;
  List<Map<String, dynamic>> _transfers = const [];
  bool _isLoadingTransfers = true;
  bool _isSubmittingTransfer = false;
  String? _transferError;
  String? _transferRequestId;
  final TextEditingController _transferQtyController = TextEditingController(
    text: '1',
  );
  StreamSubscription<List<LocalStockData>>? _stockSubscription;
  Timer? _stockRefreshDebounce;

  @override
  void initState() {
    super.initState();
    _transferQtyController.addListener(_invalidateTransferRequestKey);
    final currentUser = getIt<AuthService>().currentUser;
    final canViewTransfers = RolePermissions(
      currentUser?['permissions'] as List<dynamic>?,
    ).has('inventory.transfers.view');
    _branchesFuture = canViewTransfers
        ? getIt<ApiClient>().getBranches()
        : Future.value(const <dynamic>[]);
    _isLoadingTransfers = canViewTransfers;
    _loadData();
    if (canViewTransfers) unawaited(_loadTransfers());
    // Stock levels live in the local cache that the POS/Products screens fill
    // from the server. Opened first on a fresh install, Inventory showed every
    // product at 0 with "20 alerts" and a KES 0 stock value. Refresh the cache
    // here too (best effort - offline simply keeps whatever is already cached);
    // the stock stream below reloads the screen when new levels arrive.
    unawaited(_refreshCatalogCache());
    _stockSubscription = getIt<AppDatabase>().watchAllStock().listen((_) {
      _stockRefreshDebounce?.cancel();
      _stockRefreshDebounce = Timer(const Duration(milliseconds: 100), () {
        if (mounted) _loadData(showLoading: false);
      });
    });
  }

  @override
  void dispose() {
    _stockSubscription?.cancel();
    _stockRefreshDebounce?.cancel();
    _transferQtyController.dispose();
    super.dispose();
  }

  Future<void> _refreshCatalogCache() async {
    try {
      await syncCatalogCacheFromApi();
      if (mounted) await _loadData(showLoading: false);
    } catch (e) {
      debugPrint('Inventory catalog refresh skipped: $e');
    }
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) setState(() => _isLoading = true);
    try {
      final db = getIt<AppDatabase>();
      final results = await Future.wait([
        db.getProductCount(),
        db.getLowStockProducts(),
        db.getInventoryReport(),
      ]);

      final totalItems = results[0] as int;
      final lowStockList = results[1] as List<Map<String, dynamic>>;
      final inventoryReport = results[2] as List<Map<String, dynamic>>;

      final totalValue = inventoryReport.fold<double>(
        0,
        (sum, item) =>
            sum +
            ((item['price'] as num?)?.toDouble() ?? 0) *
                ((item['stock'] as num?)?.toDouble() ?? 0),
      );

      if (!mounted) return;
      setState(() {
        _totalItems = totalItems;
        _lowStockCount = lowStockList.length;
        _totalValue = totalValue;
        _lowStockItems = lowStockList;
        _inventoryItems = inventoryReport;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading inventory data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        showGlassSnackBar(
          context,
          'Failed to load inventory data',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    }
  }

  Future<void> _loadTransfers() async {
    final branchId = getIt<AuthService>().branchId;
    if (!mounted) return;
    setState(() {
      _isLoadingTransfers = true;
      _transferError = null;
    });
    if (branchId == null || branchId.isEmpty) {
      setState(() {
        _transfers = const [];
        _isLoadingTransfers = false;
        _transferError = 'Choose a branch to view its stock transfers.';
      });
      return;
    }

    try {
      final result = await getIt<ApiClient>()
          .getInventoryTransfers(branchId: branchId, limit: 50);
      if (!mounted) return;
      final rows = result['items'];
      setState(() {
        _transfers = rows is List
            ? rows
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : const [];
        _isLoadingTransfers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingTransfers = false;
        _transferError = apiErrorMessage(error);
      });
    }
  }

  void _replaceBranchesFuture() {
    setState(() => _branchesFuture = getIt<ApiClient>().getBranches());
  }

  void _invalidateTransferRequestKey() {
    _transferRequestId = null;
  }

  String _formatCurrency(double amount) {
    return formatMoney(amount, decimals: amount % 1 != 0);
  }

  Color _stockColor(num stock, int minStock) {
    if (stock == 0) return DesignColors.error;
    if (stock <= minStock && minStock > 0) return DesignColors.warning;
    if (stock < 5) return DesignColors.warning;
    return DesignColors.success;
  }

  IconData _stockIcon(num stock, int minStock) {
    if (stock == 0) return Icons.cancel_rounded;
    if (stock <= minStock && minStock > 0) return Icons.warning_amber_rounded;
    if (stock < 5) return Icons.warning_amber_rounded;
    return Icons.check_circle_rounded;
  }

  String _formatUnitQty(double qty) {
    return qty % 1 == 0 ? qty.toStringAsFixed(0) : qty.toStringAsFixed(1);
  }

  /// Builds a packaging-unit-aware summary for a low-stock item, e.g.
  /// "3 pieces (0.3 box) — reorder below 1 box", falling back to a
  /// plain base-unit message when the product has no bulk pricing tier.
  String? _packagingSummary(
    Map<String, dynamic> item,
    num quantity,
    int minStock,
  ) {
    final unit = item['unit'] as String? ?? 'piece';
    final rememberedUnit = item['displayUnit'] as String?;
    final rememberedFactor =
        (item['displayQuantityPerUnit'] as num?)?.toDouble();
    if (rememberedUnit != null &&
        rememberedFactor != null &&
        rememberedFactor > 0) {
      final presentation = buildStockQuantityPresentation(
        baseQuantity: quantity,
        baseUnit: unit,
        preferredUnit: rememberedUnit,
        unitsPerPreferredUnit: rememberedFactor,
      );
      final reorderQuantity = _formatUnitQty(minStock / rememberedFactor);
      return '${presentation.primary}'
          '${presentation.secondary == null ? '' : ' (${presentation.secondary})'}'
          ' — reorder below $reorderQuantity $rememberedUnit';
    }

    final rawTiers = item['pricingTiers'];
    final firstTier =
        rawTiers is List && rawTiers.isNotEmpty ? rawTiers.first as Map : null;
    final tierUnit = firstTier?['unit'] as String?;
    final tierQty = (firstTier?['quantityPerUnit'] as num?)?.toDouble();

    if (tierUnit != null && tierQty != null && tierQty > 0) {
      final packagingQty = quantity / tierQty;
      final reorderPackagingQty = minStock / tierQty;
      return '${_formatUnitQty(quantity.toDouble())} $unit '
          '(${_formatUnitQty(packagingQty)} $tierUnit)'
          ' — reorder below ${_formatUnitQty(reorderPackagingQty)} $tierUnit';
    }

    return '${_formatUnitQty(quantity.toDouble())} ${pluralizeUnit(unit, quantity)} in stock · reorder below ${_formatUnitQty(minStock.toDouble())}';
  }

  List<Map<String, dynamic>> get _filteredInventoryItems {
    if (_stockSearchQuery.isEmpty) return _inventoryItems;
    final q = _stockSearchQuery.toLowerCase();
    return _inventoryItems.where((item) {
      final name = (item['name'] as String? ?? '').toLowerCase();
      final sku = (item['sku'] as String? ?? '').toLowerCase();
      final category = (item['categoryName'] as String? ?? '').toLowerCase();
      return name.contains(q) || sku.contains(q) || category.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final authService = getIt<AuthService>();
    final permissions = RolePermissions(
      authService.currentUser?['permissions'] as List<dynamic>?,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final canViewTransfers = permissions.has('inventory.transfers.view');

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Inventory',
        showBackButton: false,
        actions: [
          if (permissions.canMakeSales || permissions.canManageStock)
            IconButton(
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
              tooltip: 'Request Stock',
              onPressed: () => context.push('/inventory/request-stock'),
            ),
          if (permissions.canManageStock) ...[
            IconButton(
              icon: const Icon(Icons.inventory_rounded, size: 20),
              tooltip: 'Receive Stock',
              onPressed: () => _startReceiveStock(context),
            ),
            IconButton(
              icon: const Icon(Icons.assignment_outlined, size: 20),
              tooltip: 'Stock Requests',
              onPressed: () => context.push('/inventory/stock-requests'),
            ),
          ],
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loadData,
          ),
        ],
      ),
      body: PageContainer(
        padding: EdgeInsets.zero,
        child: DefaultTabController(
          length: canViewTransfers ? 3 : 2,
          child: Column(
            children: [
              // Compact overview keeps the stock work area visible above the fold.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignSpacing.lg,
                  DesignSpacing.sm + 2,
                  DesignSpacing.lg,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _InventoryMiniStat(
                        title: 'Items',
                        value: _isLoading ? '...' : '$_totalItems',
                        icon: Icons.inventory_2_rounded,
                        color: DesignColors.brand,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InventoryMiniStat(
                        title: 'Low Stock',
                        value: _isLoading ? '...' : '$_lowStockCount',
                        icon: Icons.warning_amber_rounded,
                        color: DesignColors.warning,
                        trend: _lowStockCount > 0 ? 'Alerts' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InventoryMiniStat(
                        title: 'Value',
                        value:
                            _isLoading ? '...' : _formatCurrency(_totalValue),
                        icon: Icons.account_balance_wallet_rounded,
                        color: DesignColors.info,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: DesignSpacing.lg,
                ),
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceBorder.withValues(alpha: 0.3),
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                ),
                child: TabBar(
                  labelColor: Colors.black,
                  unselectedLabelColor: secondaryColor,
                  indicator: BoxDecoration(
                    color: DesignColors.accent,
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicatorPadding: const EdgeInsets.all(DesignSpacing.xs),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: [
                    const Tab(text: 'Stock'),
                    const Tab(text: 'Low Stock'),
                    if (canViewTransfers) const Tab(text: 'Transfers'),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildStockTab(context, permissions),
                    _buildLowStockTab(context, permissions),
                    if (canViewTransfers)
                      _buildTransfersTab(context, permissions),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startReceiveStock(BuildContext context) async {
    final selected = await showProductPicker(context);
    if (selected == null || !context.mounted) return;
    final updated = await context.push<bool>(
      '/inventory/batch-receive?productId=${Uri.encodeComponent(selected['id'] as String)}&productName=${Uri.encodeComponent(selected['name'] as String)}',
    );
    if (updated == true && mounted) await _loadData(showLoading: false);
  }

  Widget _buildStockTab(
    BuildContext context,
    RolePermissions permissions,
  ) {
    if (_isLoading) {
      return _buildLoadingList();
    }

    final items = _filteredInventoryItems;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignSpacing.lg,
            DesignSpacing.md,
            DesignSpacing.lg,
            DesignSpacing.xs,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? DesignColors.darkSurfaceElevated
                  : DesignColors.surfaceBorder.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            ),
            child: TextField(
              onChanged: (value) => setState(() => _stockSearchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search products, SKU, category...',
                hintStyle: TextStyle(color: tertiaryColor),
                prefixIcon:
                    Icon(Icons.search_rounded, color: tertiaryColor, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: DesignSpacing.lg,
                  vertical: DesignSpacing.md,
                ),
              ),
              style: TextStyle(color: titleColor),
            ),
          ),
        ),
        SectionHeader(
          title: 'Stock Levels',
          subtitle: '${items.length} product${items.length == 1 ? '' : 's'}',
          icon: Icons.warehouse_rounded,
          trailing: items.isEmpty
              ? null
              : StatusBadge(
                  label: '${items.length}',
                  color: DesignColors.brand,
                  isActive: false,
                ),
        ),
        Expanded(
          child: items.isEmpty
              ? EmptyState(
                  icon: _stockSearchQuery.isNotEmpty
                      ? Icons.search_off_rounded
                      : Icons.inventory_2_rounded,
                  title: _stockSearchQuery.isNotEmpty
                      ? 'No matches found'
                      : 'No Products Yet',
                  subtitle: _stockSearchQuery.isNotEmpty
                      ? 'Try a different search term'
                      : 'Products will appear here once added to inventory.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    DesignSpacing.lg,
                    0,
                    DesignSpacing.lg,
                    DesignSpacing.massive + 4,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return CascadeScale(
                        index: index,
                        child: _buildStockItemCard(item, permissions));
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStockItemCard(
    Map<String, dynamic> item,
    RolePermissions permissions,
  ) {
    final name = item['name'] as String? ?? 'Unknown';
    final sku = item['sku'] as String? ?? '';
    final price = (item['price'] as double?) ?? 0.0;
    final stock = (item['stock'] as num?)?.toDouble() ?? 0;
    final minStock = (item['minStock'] as int?) ?? 0;
    final category = item['categoryName'] as String? ?? 'Uncategorised';
    final productId = item['id'] as String? ?? '';
    final stockColor = context.readable(_stockColor(stock, minStock));
    final stockIcon = _stockIcon(stock, minStock);
    final stockPresentation = buildStockQuantityPresentation(
      baseQuantity: stock,
      baseUnit: item['unit'] as String? ?? 'piece',
      preferredUnit: item['displayUnit'] as String?,
      unitsPerPreferredUnit: item['displayQuantityPerUnit'] as num?,
      lastReceivedQuantity: item['lastReceivedQuantity'] as num?,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm + 2),
      child: Container(
        padding: const EdgeInsets.all(DesignSpacing.radiusMd + 2),
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product icon
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: stockColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    border: Border.all(
                      color: stockColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color: stockColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                // Name + SKU + category
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            sku,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall!
                                .copyWith(
                                  color: tertiaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          if (sku.isNotEmpty) ...[
                            Text(' · ',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall!
                                    .copyWith(color: tertiaryColor)),
                          ],
                          Text(category,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall!
                                  .copyWith(color: tertiaryColor)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Price
                Text(
                  _formatCurrency(price),
                  style: DesignType.numeric(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DesignColors.brand,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Stock row + actions. The badge and "Min" label share one
            // expanding group so the badge gets every pixel the Receive button
            // doesn't need (a Spacer next to a Flexible split the room 50/50
            // and truncated "0 pieces" to "0 piec…").
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // Stock count badge
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.sm + 2,
                            vertical: DesignSpacing.xs + 1,
                          ),
                          decoration: BoxDecoration(
                            color: stockColor.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusSm),
                            border: Border.all(
                              color: stockColor.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(stockIcon, color: stockColor, size: 14),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      stockPresentation.primary,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium!
                                          .copyWith(
                                            color: stockColor,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    if (stockPresentation.secondary != null)
                                      Text(
                                        stockPresentation.secondary!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall!
                                            .copyWith(
                                              color: stockColor.withValues(
                                                  alpha: 0.8),
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (minStock > 0) ...[
                        const SizedBox(width: 8),
                        Text('Min: $minStock',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall!
                                .copyWith(color: tertiaryColor)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Receive button
                if (permissions.canManageStock)
                  SizedBox(
                    height: 34,
                    child: GradientButton(
                      label: 'Receive',
                      icon: Icons.add_box_outlined,
                      onPressed: () async {
                        final updated = await context.push<bool>(
                          '/inventory/batch-receive?productId=${Uri.encodeComponent(productId)}&productName=${Uri.encodeComponent(name)}',
                        );
                        if (updated == true && mounted) {
                          await _loadData(showLoading: false);
                        }
                      },
                      height: 34,
                      expanded: false,
                      borderRadius: DesignSpacing.radiusSm,
                    ),
                  ),
              ],
            ),
            if (stockPresentation.lastReceived != null) ...[
              const SizedBox(height: 7),
              Text(
                stockPresentation.lastReceived!,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: tertiaryColor,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLowStockTab(BuildContext context, RolePermissions permissions) {
    if (_isLoading) {
      return _buildLoadingList();
    }

    // Severity is relative to each product's own reorder point (minStock),
    // not a hardcoded quantity cutoff — matches backend's shortfall logic.
    final critical = _lowStockItems
        .where((i) => ((i['quantity'] as num?)?.toDouble() ?? 0) == 0)
        .toList();
    final warning = _lowStockItems.where((i) {
      final qty = (i['quantity'] as num?)?.toDouble() ?? 0;
      final minStock = (i['minStock'] as int?) ?? 0;
      return qty > 0 && minStock > 0 && qty <= minStock * 0.5;
    }).toList();
    final low = _lowStockItems.where((i) {
      final qty = (i['quantity'] as num?)?.toDouble() ?? 0;
      final minStock = (i['minStock'] as int?) ?? 0;
      final isWarning = minStock > 0 && qty <= minStock * 0.5;
      return qty > 0 && !isWarning;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        DesignSpacing.lg,
        DesignSpacing.md,
        DesignSpacing.lg,
        DesignSpacing.massive + 4,
      ),
      children: [
        SectionHeader(
          title: 'Low Stock Alerts',
          subtitle:
              '${_lowStockItems.length} item${_lowStockItems.length == 1 ? '' : 's'} need attention',
          icon: Icons.warning_amber_rounded,
          trailing: StatusBadge(
            label: '${_lowStockItems.length}',
            color: _lowStockItems.isEmpty
                ? DesignColors.success
                : DesignColors.warning,
            isActive: _lowStockItems.isNotEmpty,
          ),
        ),
        // The restock suggestions screen existed but nothing linked to it.
        if (permissions.canRecordRestock && _lowStockItems.isNotEmpty) ...[
          const SizedBox(height: DesignSpacing.sm),
          OutlinedButton.icon(
            key: const ValueKey('open-restock-suggestions'),
            onPressed: () => context.push('/inventory/restock-suggestions'),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('See what to reorder'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(DesignSpacing.huge),
            ),
          ),
          const SizedBox(height: DesignSpacing.sm),
        ],
        if (_lowStockItems.isEmpty)
          Builder(builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final titleColor = isDark
                ? DesignColors.darkTextPrimary
                : DesignColors.textPrimary;
            final secondaryColor = isDark
                ? DesignColors.darkTextSecondary
                : DesignColors.textSecondary;
            final border =
                isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
            final surface =
                isDark ? DesignColors.darkSurfaceElevated : Colors.white;
            return Container(
              padding: const EdgeInsets.all(DesignSpacing.xxl),
              decoration: BoxDecoration(
                color: surface,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(DesignSpacing.lg),
                    decoration: BoxDecoration(
                      color: DesignColors.success.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusLg),
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 48,
                      color: DesignColors.success,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'All Stocked Up',
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No items are currently low in stock. Everything looks good!',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: secondaryColor,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            );
          })
        else ...[
          if (critical.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSeveritySection(
              title: 'Out of Stock',
              icon: Icons.cancel_rounded,
              color: DesignColors.error,
              items: critical,
              permissions: permissions,
            ),
          ],
          if (warning.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSeveritySection(
              title: 'Critical Low',
              icon: Icons.error_rounded,
              color: DesignColors.warning,
              items: warning,
              permissions: permissions,
            ),
          ],
          if (low.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSeveritySection(
              title: 'Running Low',
              icon: Icons.info_rounded,
              color: DesignColors.info,
              items: low,
              permissions: permissions,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildSeveritySection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> items,
    required RolePermissions permissions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignSpacing.xs,
            vertical: DesignSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(DesignSpacing.sm - 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      color: color,
                      letterSpacing: 0.3,
                    ),
              ),
              const SizedBox(width: 8),
              StatusBadge(
                label: '${items.length}',
                color: color,
                isActive: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => _buildLowStockCard(item, color, permissions)),
      ],
    );
  }

  Widget _buildLowStockCard(
    Map<String, dynamic> item,
    Color severityColor,
    RolePermissions permissions,
  ) {
    final name = item['name'] as String? ?? 'Unknown';
    final sku = item['sku'] as String? ?? '';
    final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
    final minStock = (item['minStock'] as int?) ?? 0;
    final category = item['categoryName'] as String? ?? 'Uncategorised';
    final productId = item['id'] as String? ?? '';
    final packagingSummary = _packagingSummary(item, quantity, minStock);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(DesignSpacing.md),
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: severityColor.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: severityColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
                border: Border.all(
                  color: severityColor.withValues(alpha: 0.15),
                ),
              ),
              child: Icon(
                quantity == 0
                    ? Icons.cancel_rounded
                    : Icons.warning_amber_rounded,
                color: severityColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sku.isEmpty ? category : '$sku · $category',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall!
                        .copyWith(color: tertiaryColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (packagingSummary != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      packagingSummary,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall!
                          .copyWith(color: tertiaryColor),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (permissions.canManageStock) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        height: 32,
                        child: GradientButton(
                          label: 'Request',
                          icon: Icons.add_shopping_cart_rounded,
                          onPressed: () => context.push(
                            '/inventory/request-stock?productId=$productId',
                          ),
                          height: 32,
                          expanded: false,
                          borderRadius: DesignSpacing.radiusSm,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignSpacing.sm + 2,
                vertical: DesignSpacing.xs + 1,
              ),
              decoration: BoxDecoration(
                color: severityColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
                border: Border.all(
                  color: severityColor.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                quantity == 0 ? 'OUT' : '${_formatUnitQty(quantity)} left',
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                      color: severityColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransfersTab(BuildContext context, RolePermissions permissions) {
    final authService = getIt<AuthService>();
    final fromBranchId = authService.branchId;
    final canCreateAndSend = permissions.has('inventory.transfers.create') &&
        permissions.has('inventory.transfers.send');
    final canReceive = permissions.has('inventory.transfers.receive');

    return FutureBuilder<List<dynamic>>(
      future: _branchesFuture,
      builder: (context, snapshot) {
        final branches =
            (snapshot.data ?? const []).cast<Map<String, dynamic>>();
        final destinationBranches =
            branches.where((b) => b['id'] != fromBranchId).toList();
        final products = _inventoryItems
            .where((item) => ((item['stock'] as num?)?.toDouble() ?? 0) > 0)
            .toList();

        return RefreshIndicator(
          onRefresh: _loadTransfers,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              DesignSpacing.lg,
              DesignSpacing.md,
              DesignSpacing.lg,
              DesignSpacing.massive + 4,
            ),
            children: [
              const SectionHeader(
                title: 'Stock Transfers',
                subtitle: 'Send stock to a branch and confirm it on arrival',
                icon: Icons.swap_horiz_rounded,
              ),
              const SizedBox(height: DesignSpacing.md),
              if (canCreateAndSend && fromBranchId != null)
                _buildTransferForm(
                  context,
                  products: products,
                  destinationBranches: destinationBranches,
                  branchesLoading:
                      snapshot.connectionState == ConnectionState.waiting,
                  branchesError: snapshot.hasError,
                )
              else
                _transferNotice(
                  context,
                  icon: Icons.lock_outline_rounded,
                  message: fromBranchId == null
                      ? 'Choose a branch before creating stock transfers.'
                      : 'Ask an owner or stock manager to grant the transfer create and dispatch permissions.',
                ),
              const SizedBox(height: DesignSpacing.lg),
              SectionHeader(
                title: 'Branch transfers',
                subtitle: canReceive
                    ? 'Receive arrivals here and track stock already sent.'
                    : 'Track stock already sent to or from this branch.',
                icon: Icons.local_shipping_outlined,
                trailing: IconButton(
                  tooltip: 'Refresh transfers',
                  onPressed: _isLoadingTransfers ? null : _loadTransfers,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              if (_transferError != null) ...[
                const SizedBox(height: DesignSpacing.sm),
                InlineRetryNotice(
                  message: _transferError!,
                  onRetry: _loadTransfers,
                ),
              ],
              if (_isLoadingTransfers)
                const Padding(
                  padding: EdgeInsets.all(DesignSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_transfers.isEmpty)
                _transferNotice(
                  context,
                  icon: Icons.inventory_2_outlined,
                  message:
                      'No branch transfers yet. Sent and incoming stock will appear here.',
                )
              else
                ..._transfers.map((transfer) => _transferCard(
                      context,
                      transfer,
                      currentBranchId: fromBranchId,
                      canReceive: canReceive,
                      canSend: permissions.has('inventory.transfers.send'),
                    )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransferForm(
    BuildContext context, {
    required List<Map<String, dynamic>> products,
    required List<Map<String, dynamic>> destinationBranches,
    required bool branchesLoading,
    required bool branchesError,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.lg),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: DesignColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Send stock',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: DesignSpacing.xs),
          Text(
            'The source branch is reduced when dispatched. The destination adds stock after it confirms receipt.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: secondaryColor,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: DesignSpacing.md),
          if (branchesLoading)
            const LinearProgressIndicator()
          else if (branchesError)
            InlineRetryNotice(
              message: 'Could not load branches. Refresh and try again.',
              onRetry: _replaceBranchesFuture,
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _transferProductId,
              isExpanded: true,
              decoration: _transferInputDecoration(
                context,
                label: 'Product',
                icon: Icons.inventory_2_rounded,
              ),
              items: products.map((item) {
                final id = item['id'] as String;
                final name = item['name'] as String? ?? 'Product';
                final stock = (item['stock'] as num?)?.toDouble() ?? 0;
                return DropdownMenuItem(
                  value: id,
                  child: Text(
                    '$name · ${_formatUnitQty(stock)} available',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _isSubmittingTransfer
                  ? null
                  : (value) => setState(() {
                        _transferProductId = value;
                        _transferRequestId = null;
                      }),
            ),
            const SizedBox(height: DesignSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _transferToBranchId,
              isExpanded: true,
              decoration: _transferInputDecoration(
                context,
                label: 'Destination branch',
                icon: Icons.store_mall_directory_rounded,
              ),
              items: destinationBranches.map((branch) {
                return DropdownMenuItem(
                  value: branch['id'] as String,
                  child: Text(
                    branch['name'] as String? ?? 'Branch',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _isSubmittingTransfer
                  ? null
                  : (value) => setState(() {
                        _transferToBranchId = value;
                        _transferRequestId = null;
                      }),
            ),
            const SizedBox(height: DesignSpacing.md),
            TextFormField(
              controller: _transferQtyController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              enabled: !_isSubmittingTransfer,
              decoration: _transferInputDecoration(
                context,
                label: 'Quantity',
                icon: Icons.numbers_rounded,
              ),
            ),
            if (destinationBranches.isEmpty) ...[
              const SizedBox(height: DesignSpacing.sm),
              Text(
                'Add another active branch in Settings before making a transfer.',
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      color: secondaryColor,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
            const SizedBox(height: DesignSpacing.md),
            GradientButton(
              label: _isSubmittingTransfer ? 'Sending…' : 'Send stock',
              icon:
                  _isSubmittingTransfer ? null : Icons.local_shipping_outlined,
              height: 50,
              borderRadius: DesignSpacing.radiusLg,
              isLoading: _isSubmittingTransfer,
              onPressed: destinationBranches.isEmpty ||
                      products.isEmpty ||
                      _isSubmittingTransfer
                  ? null
                  : _submitStockTransfer,
            ),
          ],
        ],
      ),
    );
  }

  Widget _transferNotice(BuildContext context,
      {required IconData icon, required String message}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: (isDark ? DesignColors.darkSurface : Colors.white),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(
          color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DesignColors.info),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }

  Widget _transferCard(
    BuildContext context,
    Map<String, dynamic> transfer, {
    required String? currentBranchId,
    required bool canReceive,
    required bool canSend,
  }) {
    final transferId = transfer['id']?.toString() ?? '';
    final status = transfer['status']?.toString().toLowerCase() ?? 'pending';
    final toBranchId = transfer['toBranchId']?.toString();
    final incoming = toBranchId == currentBranchId;
    final items = (transfer['items'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final itemSummary = items.map((item) {
      final quantity =
          (item['sentQty'] as num?) ?? (item['requestedQty'] as num?) ?? 0;
      return '${item['productName'] ?? 'Product'} × ${_formatUnitQty(quantity.toDouble())}';
    }).join(' · ');
    final actionLabel = status == 'pending' && !incoming && canSend
        ? 'Dispatch'
        : status == 'in_transit' && incoming && canReceive
            ? 'Receive'
            : null;
    return Card(
      margin: const EdgeInsets.only(top: DesignSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DesignSpacing.xs),
        child: ListTile(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  '${incoming ? 'From' : 'To'} ${incoming ? transfer['fromBranchName'] ?? 'branch' : transfer['toBranchName'] ?? 'branch'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: DesignSpacing.xs),
              StatusBadge(
                label: switch (status) {
                  'in_transit' => 'In transit',
                  'completed' => 'Received',
                  'pending' => 'Awaiting dispatch',
                  _ => status,
                },
                color: status == 'completed'
                    ? DesignColors.success
                    : status == 'in_transit'
                        ? DesignColors.info
                        : DesignColors.warning,
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: DesignSpacing.xs),
            child: Text(
              itemSummary.isEmpty ? 'No item details' : itemSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing: actionLabel == null
              ? null
              : TextButton(
                  onPressed: transferId.isEmpty
                      ? null
                      : () => status == 'pending'
                          ? _dispatchTransfer(transferId)
                          : _receiveTransfer(transfer),
                  child: Text(actionLabel),
                ),
        ),
      ),
    );
  }

  InputDecoration _transferInputDecoration(
    BuildContext context, {
    required String label,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: isDark ? DesignColors.darkSurface : DesignColors.surfaceMuted,
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
        borderSide: const BorderSide(color: DesignColors.info, width: 1.4),
      ),
    );
  }

  Future<void> _submitStockTransfer() async {
    final fromBranchId = getIt<AuthService>().branchId;
    final productId = _transferProductId;
    final toBranchId = _transferToBranchId;
    final quantity = double.tryParse(_transferQtyController.text.trim());

    if (fromBranchId == null ||
        fromBranchId.isEmpty ||
        productId == null ||
        toBranchId == null ||
        quantity == null ||
        !quantity.isFinite ||
        quantity <= 0) {
      showGlassSnackBar(
        context,
        'Select a product and destination, then enter a valid quantity.',
        icon: Icons.warning_amber_rounded,
        color: DesignColors.warning,
      );
      return;
    }

    setState(() => _isSubmittingTransfer = true);
    String? transferId;
    try {
      final requestId = _transferRequestId ??= _uuid.v4();
      final created = await getIt<ApiClient>().createInventoryTransfer({
        'requestId': requestId,
        'fromBranchId': fromBranchId,
        'toBranchId': toBranchId,
        'items': [
          {'productId': productId, 'quantity': quantity},
        ],
      });
      transferId = created['id']?.toString();
      if (transferId == null || transferId.isEmpty) {
        throw StateError(
            'The transfer was created without a reference. Refresh transfers before retrying.');
      }
      // Once creation is confirmed, retries should dispatch this record rather
      // than creating another request. A pending row stays visible if dispatch
      // fails so staff can safely try again from the list.
      _transferRequestId = null;
      await getIt<ApiClient>().sendInventoryTransfer(transferId);
      _transferQtyController.text = '1';
      setState(() {
        _transferProductId = null;
        _transferToBranchId = null;
      });
      unawaited(_loadData(showLoading: false));
      unawaited(_refreshCatalogCache());
      await _loadTransfers();
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Transfer dispatched. The destination branch must confirm receipt.',
        icon: Icons.local_shipping_rounded,
        color: DesignColors.info,
      );
    } catch (e) {
      if (transferId != null) {
        // The record exists even if dispatch failed. Refreshing lets staff
        // use its explicit Dispatch action without submitting another one.
        _transferRequestId = null;
        unawaited(_loadTransfers());
      }
      if (!mounted) return;
      showGlassSnackBar(
        context,
        transferId == null
            ? apiErrorMessage(e)
            : 'The transfer was created but not dispatched. Find it below and try Dispatch again.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    } finally {
      if (mounted) setState(() => _isSubmittingTransfer = false);
    }
  }

  Future<void> _dispatchTransfer(String transferId) async {
    try {
      await getIt<ApiClient>().sendInventoryTransfer(transferId);
      unawaited(_loadData(showLoading: false));
      unawaited(_refreshCatalogCache());
      await _loadTransfers();
      if (mounted) {
        showGlassSnackBar(
          context,
          'Transfer dispatched. The destination branch must confirm receipt.',
          icon: Icons.local_shipping_rounded,
          color: DesignColors.info,
        );
      }
    } catch (error) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        apiErrorMessage(error),
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
      unawaited(_loadTransfers());
    }
  }

  Future<void> _receiveTransfer(Map<String, dynamic> transfer) async {
    final transferId = transfer['id']?.toString();
    if (transferId == null || transferId.isEmpty) return;
    final result = await _showReceiveTransferDialog(transfer);
    if (result == null || !mounted) return;
    try {
      await getIt<ApiClient>().receiveInventoryTransfer(
        transferId,
        receivedItems:
            (result['receivedItems'] as List).cast<Map<String, dynamic>>(),
        notes: result['notes']?.toString(),
      );
      unawaited(_loadData(showLoading: false));
      unawaited(_refreshCatalogCache());
      await _loadTransfers();
      if (mounted) {
        showGlassSnackBar(
          context,
          'Receipt confirmed. Destination stock has been updated.',
          icon: Icons.check_circle_rounded,
          color: DesignColors.success,
        );
      }
    } catch (error) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        apiErrorMessage(error),
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
      unawaited(_loadTransfers());
    }
  }

  Future<Map<String, dynamic>?> _showReceiveTransferDialog(
      Map<String, dynamic> transfer) async {
    final items = (transfer['items'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final quantityControllers = items.map((item) {
      final sent =
          (item['sentQty'] as num?) ?? (item['requestedQty'] as num?) ?? 0;
      return TextEditingController(text: _formatUnitQty(sent.toDouble()));
    }).toList();
    final notesController = TextEditingController();
    String? validationError;
    try {
      return await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Confirm received stock'),
            content: SizedBox(
              width: 440,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const Text(
                        'Enter what physically arrived. If any quantity differs from what was sent, add a note.'),
                    const SizedBox(height: DesignSpacing.md),
                    for (var index = 0; index < items.length; index++) ...[
                      Text(
                        items[index]['productName']?.toString() ?? 'Product',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextFormField(
                        controller: quantityControllers[index],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              'Received (sent ${_formatUnitQty(((items[index]['sentQty'] as num?) ?? (items[index]['requestedQty'] as num?) ?? 0).toDouble())})',
                          suffixText: 'units',
                        ),
                      ),
                      const SizedBox(height: DesignSpacing.sm),
                    ],
                    TextField(
                      controller: notesController,
                      maxLength: 500,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes for a quantity difference',
                        hintText: 'Required when received quantities differ',
                      ),
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: DesignSpacing.xs),
                      Text(
                        validationError!,
                        style: const TextStyle(color: DesignColors.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.inventory_rounded),
                label: const Text('Confirm receipt'),
                onPressed: () {
                  final receivedItems = <Map<String, dynamic>>[];
                  var hasDifference = false;
                  for (var index = 0; index < items.length; index++) {
                    final sent = ((items[index]['sentQty'] as num?) ??
                            (items[index]['requestedQty'] as num?) ??
                            0)
                        .toDouble();
                    final received =
                        double.tryParse(quantityControllers[index].text.trim());
                    if (received == null ||
                        !received.isFinite ||
                        received < 0 ||
                        received > sent ||
                        (received * 1000).round() != received * 1000) {
                      setDialogState(() => validationError =
                          'Enter a valid quantity from 0 to the amount sent (up to 3 decimal places).');
                      return;
                    }
                    if ((sent * 1000).round() != (received * 1000).round()) {
                      hasDifference = true;
                    }
                    receivedItems.add({
                      'productId': items[index]['productId'],
                      'quantity': received,
                    });
                  }
                  if (hasDifference && notesController.text.trim().isEmpty) {
                    setDialogState(() => validationError =
                        'Add a note to explain the quantity difference.');
                    return;
                  }
                  Navigator.of(dialogContext).pop({
                    'receivedItems': receivedItems,
                    'notes': notesController.text.trim(),
                  });
                },
              ),
            ],
          ),
        ),
      );
    } finally {
      for (final controller in quantityControllers) {
        controller.dispose();
      }
      notesController.dispose();
    }
  }

  Widget _buildLoadingList() {
    return Builder(builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final border =
          isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
      final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          DesignSpacing.lg,
          DesignSpacing.md,
          DesignSpacing.lg,
          DesignSpacing.massive + 4,
        ),
        children: List.generate(5, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: DesignSpacing.sm + 2),
            child: Container(
              padding: const EdgeInsets.all(DesignSpacing.radiusMd + 2),
              decoration: BoxDecoration(
                color: surface,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              ),
              child: const Row(
                children: [
                  ShimmerWidget(
                      width: 42,
                      height: 42,
                      borderRadius: DesignSpacing.radiusMd),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerWidget(
                          width: 160,
                          height: 14,
                          borderRadius: DesignSpacing.xs,
                        ),
                        SizedBox(height: 6),
                        ShimmerWidget(
                          width: 100,
                          height: 10,
                          borderRadius: DesignSpacing.xs,
                        ),
                      ],
                    ),
                  ),
                  ShimmerWidget(
                      width: 60, height: 14, borderRadius: DesignSpacing.xs),
                ],
              ),
            ),
          );
        }),
      );
    });
  }
}

class _InventoryMiniStat extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? trend;

  const _InventoryMiniStat({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.trend,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignSpacing.sm + 2,
        vertical: DesignSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: double.infinity,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(DesignSpacing.xs),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: DesignType.numeric(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? DesignColors.darkTextPrimary
                          : DesignColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  trend ?? title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        fontWeight: FontWeight.w600,
                        color: trend == null
                            ? (isDark
                                ? DesignColors.darkTextTertiary
                                : DesignColors.textTertiary)
                            : color,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
