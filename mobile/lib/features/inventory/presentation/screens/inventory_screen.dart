import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/auth/app_roles.dart';
import '../widgets/product_picker_dialog.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  int _totalItems = 0;
  int _lowStockCount = 0;
  double _totalValue = 0;
  List<Map<String, dynamic>> _inventoryItems = [];
  List<Map<String, dynamic>> _lowStockItems = [];
  bool _isLoading = true;
  String _stockSearchQuery = '';
  String? _transferProductId;
  String? _transferToBranchId;
  final TextEditingController _transferQtyController = TextEditingController(
    text: '1',
  );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _transferQtyController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
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
            ((item['price'] as double?) ?? 0) * ((item['stock'] as int?) ?? 0),
      );

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

  String _formatCurrency(double amount) {
    return 'KES ${amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2)}';
  }

  Color _stockColor(int stock, int minStock) {
    if (stock == 0) return DesignColors.error;
    if (stock <= minStock && minStock > 0) return DesignColors.warning;
    if (stock < 5) return DesignColors.warning;
    return DesignColors.success;
  }

  IconData _stockIcon(int stock, int minStock) {
    if (stock == 0) return Icons.cancel_rounded;
    if (stock <= minStock && minStock > 0) return Icons.warning_amber_rounded;
    if (stock < 5) return Icons.warning_amber_rounded;
    return Icons.check_circle_rounded;
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
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Inventory',
        showBackButton: false,
        actions: [
          if (permissions.canManageStock)
            IconButton(
              icon: const Icon(Icons.assignment_outlined, size: 20),
              tooltip: 'Stock Requests',
              onPressed: () => context.push('/inventory/stock-requests'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loadData,
          ),
        ],
      ),
      body: PageContainer(
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              // Metrics Row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        title: 'Total Items',
                        value: _isLoading ? '...' : '$_totalItems',
                        icon: Icons.inventory_2_rounded,
                        color: DesignColors.brand,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        title: 'Low Stock',
                        value: _isLoading ? '...' : '$_lowStockCount',
                        icon: Icons.warning_amber_rounded,
                        color: DesignColors.warning,
                        trend: _lowStockCount > 0 ? 'Alerts' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        title: 'Total Value',
                        value: _isLoading
                            ? '...'
                            : _formatCurrency(_totalValue),
                        icon: Icons.account_balance_wallet_rounded,
                        color: DesignColors.info,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceBorder.withValues(alpha: 0.3),
                  border: Border.all(color: border),
                ),
                child: TabBar(
                  labelColor: Colors.black,
                  unselectedLabelColor: secondaryColor,
                  indicator: const BoxDecoration(color: DesignColors.accent),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicatorPadding: const EdgeInsets.all(4),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  tabs: const [
                    Tab(text: 'Stock'),
                    Tab(text: 'Low Stock'),
                    Tab(text: 'Transfers'),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildStockTab(context, permissions),
                    _buildLowStockTab(context, permissions),
                    _buildTransfersTab(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: permissions.canManageStock
          ? _buildActionButtons(context)
          : null,
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: 'requestStock',
          backgroundColor: DesignColors.warning,
          onPressed: () => context.push('/inventory/request-stock'),
          tooltip: 'Request Stock',
          child: const Icon(
            Icons.add_shopping_cart_rounded,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.small(
          heroTag: 'receiveStock',
          backgroundColor: DesignColors.brand,
          onPressed: () => _startReceiveStock(context),
          tooltip: 'Receive Stock',
          child: const Icon(Icons.inventory_rounded, color: Colors.white),
        ),
      ],
    );
  }

  Future<void> _startReceiveStock(BuildContext context) async {
    final selected = await showProductPicker(context);
    if (selected == null || !context.mounted) return;
    context.push(
      '/inventory/batch-receive?productId=${Uri.encodeComponent(selected['id'] as String)}&productName=${Uri.encodeComponent(selected['name'] as String)}',
    );
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? DesignColors.darkSurfaceElevated
                  : DesignColors.surfaceBorder.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              onChanged: (value) => setState(() => _stockSearchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search products, SKU, category...',
                hintStyle: TextStyle(color: tertiaryColor, fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded, color: tertiaryColor, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: TextStyle(fontSize: 14, color: titleColor),
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildStockItemCard(item, permissions);
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
    final stock = (item['stock'] as int?) ?? 0;
    final minStock = (item['minStock'] as int?) ?? 0;
    final category = item['categoryName'] as String? ?? 'Uncategorised';
    final productId = item['id'] as String? ?? '';
    final stockColor = _stockColor(stock, minStock);
    final stockIcon = _stockIcon(stock, minStock);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
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
                    borderRadius: BorderRadius.circular(12),
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
                        style: TextStyle(
                          fontSize: 14,
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
                            style: TextStyle(
                              fontSize: 11,
                              color: tertiaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (sku.isNotEmpty) ...[
                            Text(' · ', style: TextStyle(color: tertiaryColor, fontSize: 11)),
                          ],
                          Text(category, style: TextStyle(fontSize: 11, color: tertiaryColor)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Price
                Text(
                  _formatCurrency(price),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DesignColors.brand,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Stock row + actions
            Row(
              children: [
                // Stock count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: stockColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: stockColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(stockIcon, color: stockColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '$stock units',
                        style: TextStyle(
                          color: stockColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (minStock > 0) ...[
                  const SizedBox(width: 8),
                  Text('Min: $minStock', style: TextStyle(fontSize: 11, color: tertiaryColor)),
                ],
                const Spacer(),
                // Receive button
                if (permissions.canManageStock)
                  SizedBox(
                    height: 34,
                    child: GradientButton(
                      label: 'Receive',
                      icon: Icons.add_box_outlined,
                      onPressed: () => context.push(
                        '/inventory/batch-receive?productId=${Uri.encodeComponent(productId)}&productName=${Uri.encodeComponent(name)}',
                      ),
                      height: 34,
                      expanded: false,
                      borderRadius: 8,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowStockTab(BuildContext context, RolePermissions permissions) {
    if (_isLoading) {
      return _buildLoadingList();
    }

    final critical = _lowStockItems
        .where((i) => ((i['quantity'] as int?) ?? 0) == 0)
        .toList();
    final warning = _lowStockItems.where((i) {
      final qty = (i['quantity'] as int?) ?? 0;
      return qty > 0 && qty < 5;
    }).toList();
    final low = _lowStockItems.where((i) {
      final qty = (i['quantity'] as int?) ?? 0;
      return qty >= 5;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
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
        if (_lowStockItems.isEmpty)
          Builder(builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final titleColor =
                isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
            final secondaryColor = isDark
                ? DesignColors.darkTextSecondary
                : DesignColors.textSecondary;
            final border =
                isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
            final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
            return Container(
              padding: const EdgeInsets.all(24),
              decoration:
                  BoxDecoration(color: surface, border: Border.all(color: border)),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: DesignColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No items are currently low in stock. Everything looks good!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: secondaryColor, height: 1.4),
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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
    final quantity = (item['quantity'] as int?) ?? 0;
    final category = item['categoryName'] as String? ?? 'Uncategorised';
    final productId = item['id'] as String? ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: severityColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: severityColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(sku, style: TextStyle(fontSize: 11, color: tertiaryColor)),
                      if (sku.isNotEmpty) ...[
                        Text(' · ', style: TextStyle(color: tertiaryColor, fontSize: 11)),
                      ],
                      Text(category, style: TextStyle(fontSize: 11, color: tertiaryColor)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: severityColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: severityColor.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                quantity == 0 ? 'OUT' : '$quantity left',
                style: TextStyle(
                  color: severityColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (permissions.canManageStock) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: GradientButton(
                  label: 'Request',
                  icon: Icons.add_shopping_cart_rounded,
                  onPressed: () => context.push(
                    '/inventory/request-stock?productId=$productId',
                  ),
                  height: 32,
                  expanded: false,
                  borderRadius: 8,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransfersTab(BuildContext context) {
    final authService = getIt<AuthService>();
    final fromBranchId = authService.branchId ?? 'branch-main';

    return FutureBuilder<List<dynamic>>(
      future: getIt<ApiClient>().getBranches(),
      builder: (context, snapshot) {
        final branches = (snapshot.data ?? const [])
            .cast<Map<String, dynamic>>();
        final destinationBranches = branches
            .where((b) => b['id'] != fromBranchId)
            .toList();
        final products = _inventoryItems
            .where((item) => (item['stock'] as int? ?? 0) > 0)
            .toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            SectionHeader(
              title: 'Stock Transfers',
              subtitle: 'Move stock from this branch to another branch',
              icon: Icons.swap_horiz_rounded,
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final secondaryColor = isDark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary;
              final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
              return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                border: Border.all(color: DesignColors.info.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      final stock = item['stock'] as int? ?? 0;
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                          '$name  ($stock available)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setState(() => _transferProductId = value),
                  ),
                  const SizedBox(height: 12),
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
                    onChanged: (value) =>
                        setState(() => _transferToBranchId = value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _transferQtyController,
                    keyboardType: TextInputType.number,
                    decoration: _transferInputDecoration(
                      context,
                      label: 'Quantity',
                      icon: Icons.numbers_rounded,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GradientButton(
                    label: 'Transfer Stock',
                    icon: Icons.swap_horiz_rounded,
                    height: 50,
                    borderRadius: 14,
                    onPressed: destinationBranches.isEmpty || products.isEmpty
                        ? null
                        : () => _submitStockTransfer(fromBranchId),
                  ),
                  if (destinationBranches.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Add another branch in Settings before making a transfer.',
                      style: TextStyle(color: secondaryColor, fontSize: 13),
                    ),
                  ],
                ],
              ),
              );
            }),
          ],
        );
      },
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
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DesignColors.info, width: 1.4),
      ),
    );
  }

  Future<void> _submitStockTransfer(String fromBranchId) async {
    final productId = _transferProductId;
    final toBranchId = _transferToBranchId;
    final quantity = int.tryParse(_transferQtyController.text.trim()) ?? 0;

    if (productId == null || toBranchId == null || quantity <= 0) {
      showGlassSnackBar(
        context,
        'Select product, destination branch, and quantity',
        icon: Icons.warning_amber_rounded,
        color: DesignColors.warning,
      );
      return;
    }

    try {
      await getIt<AppDatabase>().transferStock(
        productId: productId,
        fromBranchId: fromBranchId,
        toBranchId: toBranchId,
        quantity: quantity,
      );
      _transferQtyController.text = '1';
      setState(() {
        _transferProductId = null;
        _transferToBranchId = null;
      });
      await _loadData();
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Stock transferred',
        icon: Icons.check_circle_rounded,
        color: DesignColors.success,
      );
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        e.toString().replaceFirst('Bad state: ', ''),
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
  }

  Widget _buildLoadingList() {
    return Builder(builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
      final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
      return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: List.generate(5, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
            child: Row(
              children: [
                const ShimmerWidget(width: 42, height: 42, borderRadius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ShimmerWidget(
                        width: 160,
                        height: 14,
                        borderRadius: 4,
                      ),
                      const SizedBox(height: 6),
                      const ShimmerWidget(
                        width: 100,
                        height: 10,
                        borderRadius: 4,
                      ),
                    ],
                  ),
                ),
                const ShimmerWidget(width: 60, height: 14, borderRadius: 4),
              ],
            ),
          ),
        );
      }),
      );
    });
  }
}
