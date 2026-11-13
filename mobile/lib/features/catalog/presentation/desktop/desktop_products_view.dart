import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/database/app_database.dart' show Product;
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../domain/stock_status.dart';
import '../widgets/stock_kit.dart' show ProductAvatar;
import 'desktop_button_styles.dart';

/// Which stock level the table is narrowed to.
enum DesktopStockFilter { all, low, out }

/// One category in the filter menu.
class DesktopCategoryOption {
  const DesktopCategoryOption(this.id, this.name);

  final String id;
  final String name;
}

/// Value of the "all categories" menu entry. An empty id means products with
/// no category.
const String _allCategories = '__all__';

/// Menu entry that switches the table to removed products.
const String _removedView = '__removed__';

/// The Products page on a computer: a toolbar, a sortable table and, when a
/// row is picked, an inspector on the right.
///
/// It takes plain data so a test can feed it sample rows. The routed screen
/// owns the providers, the filters and every action; this widget only draws
/// them and reports what the person did.
class DesktopProductsView extends StatefulWidget {
  const DesktopProductsView({
    super.key,
    required this.title,
    required this.singular,
    required this.products,
    required this.quantities,
    required this.categoryNames,
    required this.categories,
    required this.totalCount,
    required this.lowCount,
    required this.outCount,
    required this.stockFilter,
    required this.onStockFilter,
    required this.categoryId,
    required this.onCategory,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.selectedId,
    required this.onSelect,
    this.searchHint = 'Search name or scan a barcode',
    this.searchQuery = '',
    this.showRemoved = false,
    this.onShowRemoved,
    this.canEdit = false,
    this.canReceive = false,
    this.showCost = false,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    this.inspector,
    this.notices = const [],
    this.starterNames = const [],
    this.onAdd,
    this.onAddNamed,
    this.onManageCategories,
    this.onEdit,
    this.onReceive,
    this.onCorrectCount,
    this.onToggleRemoved,
  });

  /// "Products", or the shop type's own word ("Menu items").
  final String title;

  /// "Product", for button labels.
  final String singular;

  /// The rows to show, already narrowed by search and category.
  final List<Product> products;
  final Map<String, double> quantities;
  final Map<String, String> categoryNames;
  final List<DesktopCategoryOption> categories;

  /// Counts for the filter chips, over every active product in the shop.
  final int totalCount;
  final int lowCount;
  final int outCount;
  final DesktopStockFilter stockFilter;
  final ValueChanged<DesktopStockFilter> onStockFilter;

  /// null is every category, an empty string is products with no category.
  final String? categoryId;
  final ValueChanged<String?> onCategory;
  final TextEditingController searchController;
  final String searchQuery;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;

  /// Enter in the search box. A barcode scanner types the code and presses
  /// Enter, so this is also the scan path.
  final ValueChanged<String> onSearchSubmitted;
  final String? selectedId;
  final ValueChanged<Product?> onSelect;

  /// Show the "Removed" chip. null hides it (only shops kept on this
  /// computer can bring a removed product back).
  final bool showRemoved;
  final ValueChanged<bool>? onShowRemoved;
  final bool canEdit;
  final bool canReceive;
  final bool showCost;
  final bool loading;

  /// When set, the table is replaced by "Couldn't load" with a Retry button.
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// Re-fetch from the server (Ctrl+R). null hides the button, for shops
  /// whose records live on this computer.
  final VoidCallback? onRefresh;

  /// The panel for [selectedId], or null for none.
  final Widget? inspector;

  /// Slim banners between the toolbar and the table (a failed refresh).
  final List<Widget> notices;

  /// Names offered on a brand-new shop.
  final List<String> starterNames;
  final VoidCallback? onAdd;
  final ValueChanged<String>? onAddNamed;
  final VoidCallback? onManageCategories;
  final ValueChanged<Product>? onEdit;
  final ValueChanged<Product>? onReceive;
  final ValueChanged<Product>? onCorrectCount;
  final ValueChanged<Product>? onToggleRemoved;

  @override
  State<DesktopProductsView> createState() => _DesktopProductsViewState();
}

class _DesktopProductsViewState extends State<DesktopProductsView> {
  final FocusNode _searchFocus = FocusNode(debugLabel: 'ProductsSearch');

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  StockLevel _levelOf(Product product) => stockLevelFor(
        trackInventory: product.trackInventory,
        quantity: widget.quantities[product.id],
        minStock: product.minStock,
      );

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final w = widget;
    final canAdd = w.canEdit && w.onAdd != null && !w.showRemoved;
    final addLabel = 'Add ${w.singular.toLowerCase()}';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _searchFocus.requestFocus(),
        if (canAdd)
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              w.onAdd!,
        if (w.onRefresh != null)
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              w.onRefresh!,
        // Esc closes the inspector even when focus is not inside the table
        // (a scanned barcode opens it from the search box).
        if (w.selectedId != null)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              w.onSelect(null),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: w.title,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              actions: [
                if (w.onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh (Ctrl+R)',
                    onPressed: w.onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                if (w.canEdit && w.onManageCategories != null)
                  OutlinedButton.icon(
                    style: desktopSecondaryButton(context),
                    onPressed: w.onManageCategories,
                    icon: const Icon(Icons.category_outlined, size: 17),
                    label: const Text('Categories'),
                  ),
                if (canAdd)
                  Tooltip(
                    message: '$addLabel (Ctrl+N)',
                    child: FilledButton.icon(
                      style: desktopPrimaryButton(context),
                      onPressed: w.onAdd,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(addLabel),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: DesktopInspectorLayout(
                inspectorWidth: 340,
                onClose: () => w.onSelect(null),
                inspector: w.inspector,
                main: Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    w.inspector == null ? 24 : 16,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _toolbar(context),
                      const SizedBox(height: 10),
                      for (final notice in w.notices) ...[
                        notice,
                        const SizedBox(height: 8),
                      ],
                      Expanded(
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: p.dark ? p.panelAlt : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: p.border),
                          ),
                          child: _body(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final w = widget;
    String? categoryLabel;
    final id = w.categoryId;
    if (id != null) {
      categoryLabel = id.isEmpty
          ? 'Uncategorized'
          : w.categories
                  .where((c) => c.id == id)
                  .map((c) => c.name)
                  .firstOrNull ??
              'Category';
    }
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DesktopSearchField(
            controller: w.searchController,
            focusNode: _searchFocus,
            width: box.maxWidth < 700 ? 200 : 300,
            hint: w.searchHint,
            onChanged: w.onSearchChanged,
            onSubmitted: (value) {
              w.onSearchSubmitted(value);
              // Keep the cursor ready for the next scan.
              _searchFocus.requestFocus();
            },
          ),
          DesktopFilterChip(
            label: 'All',
            count: w.totalCount,
            selected: w.stockFilter == DesktopStockFilter.all && !w.showRemoved,
            onTap: () {
              w.onShowRemoved?.call(false);
              w.onStockFilter(DesktopStockFilter.all);
            },
          ),
          DesktopFilterChip(
            label: 'Low stock',
            count: w.lowCount,
            selected: w.stockFilter == DesktopStockFilter.low,
            onTap: () => w.onStockFilter(
              w.stockFilter == DesktopStockFilter.low
                  ? DesktopStockFilter.all
                  : DesktopStockFilter.low,
            ),
          ),
          DesktopFilterChip(
            label: 'Out of stock',
            count: w.outCount,
            selected: w.stockFilter == DesktopStockFilter.out,
            onTap: () => w.onStockFilter(
              w.stockFilter == DesktopStockFilter.out
                  ? DesktopStockFilter.all
                  : DesktopStockFilter.out,
            ),
          ),
          _CategoryMenu(
            label: w.showRemoved ? 'Removed products' : categoryLabel,
            selectedId: w.categoryId,
            categories: w.categories,
            showRemoved: w.showRemoved,
            canShowRemoved: w.onShowRemoved != null,
            onSelected: (value) {
              if (value == _removedView) {
                w.onShowRemoved?.call(!w.showRemoved);
              } else {
                w.onCategory(value == _allCategories ? null : value);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final w = widget;
    final p = context.desktop;
    if (w.errorMessage != null && w.products.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load ${w.title.toLowerCase()}",
        message: w.errorMessage,
        action: w.onRetry == null
            ? null
            : OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: w.onRetry,
                child: const Text('Try again'),
              ),
      );
    }
    if (w.products.isEmpty && !w.loading) return _empty(context);

    final showCost = w.showCost;
    return LayoutBuilder(
      builder: (context, box) {
        // With the inspector open the table is narrow. The inspector already
        // shows category and cost, so those columns step aside.
        final compact = box.maxWidth < 760;
        final columns = <DesktopColumn<Product>>[
          DesktopColumn<Product>(
            label: 'Product',
            flex: 4,
            minWidth: 200,
            sortBy: (r) => r.name.toLowerCase(),
            cell: (context, r) => Row(
              children: [
                ProductAvatar(
                  name: r.name,
                  imageUrl: r.imageUrl,
                  size: 32,
                  tint: r.isActive ? null : DesignColors.textTertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DesktopCellText(r.name, strong: true),
                      DesktopCellText(
                        r.sku.isEmpty ? 'No code' : r.sku,
                        muted: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!compact)
            DesktopColumn<Product>(
              label: 'Category',
              flex: 2,
              minWidth: 100,
              sortBy: (r) =>
                  (w.categoryNames[r.categoryId] ?? '').toLowerCase(),
              cell: (context, r) => DesktopCellText(
                w.categoryNames[r.categoryId] ?? 'Uncategorized',
                muted: true,
              ),
            ),
          if (showCost && !compact)
            DesktopColumn<Product>(
              label: 'Cost',
              width: 104,
              numeric: true,
              sortBy: (r) => r.costPrice ?? -1,
              cell: (context, r) => DesktopCellText(
                (r.costPrice ?? 0) > 0 ? formatMoney(r.costPrice) : '—',
                numeric: true,
                muted: true,
              ),
            ),
          DesktopColumn<Product>(
            label: 'Price',
            width: 108,
            numeric: true,
            sortBy: (r) => r.price,
            cell: (context, r) =>
                DesktopCellText(formatMoney(r.price), numeric: true),
          ),
          DesktopColumn<Product>(
            label: 'Stock',
            width: 96,
            numeric: true,
            sortBy: (r) => w.quantities[r.id] ?? -1,
            cell: (context, r) {
              final qty = w.quantities[r.id];
              if (!r.trackInventory || qty == null) {
                return const DesktopCellText('—', muted: true);
              }
              return DesktopCellText(
                '${stockNumber(qty)} ${r.unit}',
                numeric: true,
                color: qty <= 0 ? DesignColors.error : null,
              );
            },
          ),
          DesktopColumn<Product>(
            label: 'Status',
            width: 124,
            sortBy: (r) => r.isActive ? _levelOf(r).index : 99,
            cell: (context, r) => _statusCell(r),
          ),
        ];

        final totals = _footerText();
        return DesktopDataTable<Product>(
          columns: columns,
          rows: w.products,
          rowId: (r) => r.id,
          rowHeight: 48,
          minWidth: compact ? 540 : 760,
          loading: w.loading,
          initialSortColumn: 0,
          selectedId: w.selectedId,
          onRowSelected: w.onSelect,
          // No double-click handler on purpose: Flutter waits out the
          // double-tap timeout before it reports a single click, which makes
          // selecting a row feel slow. Edit is in the inspector and the menu.
          onRowSecondaryTap: _showRowMenu,
          footer: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                Text(
                  totals.$1,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: Text(
                    totals.$2,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  (String, String) _footerText() {
    final rows = widget.products;
    var low = 0;
    var out = 0;
    for (final r in rows) {
      if (!r.isActive) continue;
      final level = _levelOf(r);
      if (level == StockLevel.low) low++;
      if (level == StockLevel.out) out++;
    }
    final noun = rows.length == 1 ? 'product' : 'products';
    final left = '${formatMoney(rows.length, symbol: '')} $noun';
    final parts = [
      if (low > 0) '$low low',
      if (out > 0) '$out out of stock',
    ];
    return (left, parts.join(' · '));
  }

  Widget _statusCell(Product r) {
    if (!r.isActive) {
      return const DesktopStatusChip(
        label: 'Removed',
        color: DesignColors.textTertiary,
      );
    }
    switch (_levelOf(r)) {
      case StockLevel.low:
        return const DesktopStatusChip(
          label: 'Low stock',
          color: DesignColors.warning,
        );
      case StockLevel.out:
        return const DesktopStatusChip(
          label: 'Out of stock',
          color: DesignColors.error,
        );
      case StockLevel.inStock:
        return const DesktopCellText('In stock', muted: true);
      case StockLevel.notTracked:
        return const DesktopCellText('Not counted', muted: true);
      case StockLevel.unknown:
        return const DesktopCellText('No count yet', muted: true);
    }
  }

  Widget _empty(BuildContext context) {
    final w = widget;
    final p = context.desktop;
    final singular = w.singular.toLowerCase();
    final query = w.searchQuery.trim();

    if (query.isNotEmpty) {
      return DesktopEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No $singular called "$query"',
        message: 'Check the spelling, or scan the barcode again.',
        action: w.canEdit && w.onAddNamed != null && !w.showRemoved
            ? OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: () => w.onAddNamed!(query),
                child: Text('Add "$query"'),
              )
            : null,
      );
    }
    if (w.showRemoved) {
      return const DesktopEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Nothing removed',
        message: 'Products you remove wait here. You can bring them back.',
      );
    }
    if (w.stockFilter == DesktopStockFilter.low) {
      return const DesktopEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing is running low',
        message: 'Everything you count is above its warning level.',
      );
    }
    if (w.stockFilter == DesktopStockFilter.out) {
      return const DesktopEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing is out of stock',
        message: 'Every product you count has some on the shelf.',
      );
    }
    if (w.categoryId != null) {
      return DesktopEmptyState(
        icon: Icons.category_outlined,
        title: 'No ${w.title.toLowerCase()} in this category',
        message: 'Pick another category, or clear the filter.',
        action: OutlinedButton(
          style: desktopSecondaryButton(context),
          onPressed: () => w.onCategory(null),
          child: const Text('Show all categories'),
        ),
      );
    }
    // A brand new shop: teach the page.
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 280),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DesktopEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Nothing to sell yet',
              message: w.canEdit
                  ? 'Add your first $singular and it appears on Sell straight away. '
                      'Scan a barcode into the search box to find one fast.'
                  : 'Ask an administrator to add ${w.title.toLowerCase()} to this shop.',
              action: w.canEdit && w.onAdd != null
                  ? FilledButton.icon(
                      style: desktopPrimaryButton(context),
                      onPressed: w.onAdd,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('Add ${w.singular.toLowerCase()}'),
                    )
                  : null,
            ),
            if (w.canEdit &&
                w.onAddNamed != null &&
                w.starterNames.isNotEmpty) ...[
              Text(
                'Shops like yours start with',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in w.starterNames)
                      DesktopFilterChip(
                        label: name,
                        selected: false,
                        onTap: () => w.onAddNamed!(name),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showRowMenu(Product product, Offset position) async {
    final w = widget;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final tracked = product.trackInventory && product.isActive;
    final items = <PopupMenuEntry<String>>[
      if (w.canEdit && w.onEdit != null)
        const PopupMenuItem(value: 'edit', child: Text('Edit details')),
      if (w.canReceive && tracked && w.onReceive != null)
        const PopupMenuItem(value: 'receive', child: Text('Receive stock')),
      if (w.canEdit && tracked && w.onCorrectCount != null)
        const PopupMenuItem(value: 'count', child: Text('Correct count')),
      if (product.sku.isNotEmpty)
        const PopupMenuItem(value: 'copy', child: Text('Copy code')),
      if (w.canEdit && w.onToggleRemoved != null)
        PopupMenuItem(
          value: 'remove',
          child: Text(product.isActive ? 'Remove' : 'Bring back'),
        ),
    ];
    if (items.isEmpty) return;
    w.onSelect(product);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'edit':
        w.onEdit?.call(product);
      case 'receive':
        w.onReceive?.call(product);
      case 'count':
        w.onCorrectCount?.call(product);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: product.sku));
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Code copied')),
        );
      case 'remove':
        w.onToggleRemoved?.call(product);
    }
  }
}

/// "Category" drop-down that looks like the filter chips beside it.
class _CategoryMenu extends StatelessWidget {
  const _CategoryMenu({
    required this.label,
    required this.selectedId,
    required this.categories,
    required this.onSelected,
    required this.showRemoved,
    required this.canShowRemoved,
  });

  final String? label;
  final String? selectedId;
  final List<DesktopCategoryOption> categories;
  final ValueChanged<String> onSelected;
  final bool showRemoved;
  final bool canShowRemoved;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final active = label != null;
    return PopupMenuButton<String>(
      tooltip: 'Filter by category',
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _allCategories,
          child: Text(
            'All categories',
            style: TextStyle(
              fontWeight:
                  selectedId == null ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        PopupMenuItem(
          value: '',
          child: Text(
            'Uncategorized',
            style: TextStyle(
              fontWeight: selectedId == '' ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        for (final c in categories)
          PopupMenuItem(
            value: c.id,
            child: Text(
              c.name,
              style: TextStyle(
                fontWeight:
                    selectedId == c.id ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        if (canShowRemoved) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _removedView,
            child: Text(
              showRemoved ? 'Back to products' : 'Show removed products',
            ),
          ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: ShapeDecoration(
          color: active ? p.selected : Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(color: active ? Colors.transparent : p.border),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label ?? 'Category',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: active ? p.text : p.textMuted,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

/// A slim warning line above the table: a refresh that failed, categories that
/// could not load. Not a dialog, so the saved list stays usable.
class DesktopNotice extends StatelessWidget {
  const DesktopNotice({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: p.dark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: p.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: desktopLinkButton(context),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
