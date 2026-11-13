import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/stock_quantity_display.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../../catalog/presentation/desktop/desktop_products_view.dart'
    show DesktopNotice, DesktopStockFilter;

/// How one stock row reads: counted and above its warning level, running low,
/// or gone.
enum _Level { ok, low, out }

_Level _levelOf(Map<String, dynamic> item) {
  final qty = (item['stock'] as num?)?.toDouble() ?? 0;
  final min = (item['minStock'] as num?)?.toDouble() ?? 0;
  if (qty <= 0) return _Level.out;
  if (min > 0 && qty <= min) return _Level.low;
  return _Level.ok;
}

/// The Stock levels tab on a computer: search, All / Low / Out chips, a table
/// of every product with how many are on the shelf, and an inspector for the
/// row you pick.
///
/// Plain data in (the maps the stock report returns), callbacks out.
class DesktopStockView extends StatefulWidget {
  const DesktopStockView({
    super.key,
    required this.items,
    required this.searchController,
    required this.onSearchChanged,
    required this.selectedId,
    required this.onSelect,
    required this.filter,
    required this.onFilter,
    this.searchHint = 'Search name or scan a barcode',
    this.searchQuery = '',
    this.productsLabel = 'products',
    this.canReceive = false,
    this.showCost = false,
    this.loading = false,
    this.errorMessage,
    this.notice,
    this.onRetry,
    this.onReceive,
    this.onOpenProduct,
    this.onSearchSubmitted,
    this.totalWorth,
  });

  /// Rows after search, before the stock chips.
  final List<Map<String, dynamic>> items;
  final TextEditingController searchController;
  final String searchQuery;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final DesktopStockFilter filter;
  final ValueChanged<DesktopStockFilter> onFilter;
  final String productsLabel;
  final bool canReceive;
  final bool showCost;
  final bool loading;
  final String? errorMessage;

  /// A stale-data warning shown above the table.
  final String? notice;
  final VoidCallback? onRetry;
  final ValueChanged<Map<String, dynamic>>? onReceive;
  final ValueChanged<Map<String, dynamic>>? onOpenProduct;

  /// Worth of the stock on the shelf, for the footer.
  final double? totalWorth;

  @override
  State<DesktopStockView> createState() => _DesktopStockViewState();
}

class _DesktopStockViewState extends State<DesktopStockView> {
  final FocusNode _searchFocus = FocusNode(debugLabel: 'StockSearch');

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  String _id(Map<String, dynamic> item) => item['id']?.toString() ?? '';

  List<Map<String, dynamic>> get _rows {
    switch (widget.filter) {
      case DesktopStockFilter.all:
        return widget.items;
      case DesktopStockFilter.low:
        return widget.items.where((i) => _levelOf(i) == _Level.low).toList();
      case DesktopStockFilter.out:
        return widget.items.where((i) => _levelOf(i) == _Level.out).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final p = context.desktop;
    final low = w.items.where((i) => _levelOf(i) == _Level.low).length;
    final out = w.items.where((i) => _levelOf(i) == _Level.out).length;
    final rows = _rows;
    Map<String, dynamic>? selected;
    for (final i in w.items) {
      if (_id(i) == w.selectedId) selected = i;
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _searchFocus.requestFocus(),
        // Esc closes the inspector even when focus is not inside the table.
        if (w.selectedId != null)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              w.onSelect(null),
      },
      child: Focus(
        autofocus: true,
        child: DesktopInspectorLayout(
          inspectorWidth: 340,
          onClose: () => w.onSelect(null),
          inspector: selected == null ? null : _inspector(context, selected),
          main: Padding(
            padding:
                EdgeInsets.fromLTRB(24, 14, selected == null ? 24 : 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
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
                          w.onSearchSubmitted?.call(value);
                          _searchFocus.requestFocus();
                        },
                      ),
                      DesktopFilterChip(
                        label: 'All',
                        count: w.items.length,
                        selected: w.filter == DesktopStockFilter.all,
                        onTap: () => w.onFilter(DesktopStockFilter.all),
                      ),
                      DesktopFilterChip(
                        label: 'Low stock',
                        count: low,
                        selected: w.filter == DesktopStockFilter.low,
                        onTap: () => w.onFilter(
                          w.filter == DesktopStockFilter.low
                              ? DesktopStockFilter.all
                              : DesktopStockFilter.low,
                        ),
                      ),
                      DesktopFilterChip(
                        label: 'Out of stock',
                        count: out,
                        selected: w.filter == DesktopStockFilter.out,
                        onTap: () => w.onFilter(
                          w.filter == DesktopStockFilter.out
                              ? DesktopStockFilter.all
                              : DesktopStockFilter.out,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (w.notice != null) ...[
                  DesktopNotice(message: w.notice!, onRetry: w.onRetry),
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
                    child: _table(context, rows),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _table(BuildContext context, List<Map<String, dynamic>> rows) {
    final w = widget;
    final p = context.desktop;
    if (w.errorMessage != null && w.items.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load stock levels",
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
    if (rows.isEmpty && !w.loading) {
      final query = w.searchQuery.trim();
      if (query.isNotEmpty) {
        return DesktopEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No match for "$query"',
          message: 'Check the spelling, or scan the barcode again.',
        );
      }
      if (w.filter == DesktopStockFilter.low) {
        return const DesktopEmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'Nothing is running low',
          message: 'Everything you count is above its warning level.',
        );
      }
      if (w.filter == DesktopStockFilter.out) {
        return const DesktopEmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'Nothing is out of stock',
          message: 'Every product you count has some on the shelf.',
        );
      }
      return DesktopEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No ${w.productsLabel} to count yet',
        message:
            'Add products first, then receive stock to start counting what is on the shelf.',
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 760;
        final columns = <DesktopColumn<Map<String, dynamic>>>[
          DesktopColumn<Map<String, dynamic>>(
            label: 'Product',
            flex: 4,
            minWidth: 200,
            sortBy: (i) => (i['name'] as String? ?? '').toLowerCase(),
            cell: (context, i) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DesktopCellText(i['name'] as String? ?? 'Unknown',
                    strong: true),
                DesktopCellText(
                  (i['sku'] as String?)?.isNotEmpty == true
                      ? i['sku'] as String
                      : 'No code',
                  muted: true,
                ),
              ],
            ),
          ),
          if (!compact)
            DesktopColumn<Map<String, dynamic>>(
              label: 'Category',
              flex: 2,
              minWidth: 100,
              sortBy: (i) => i['categoryName'] as String? ?? '',
              cell: (context, i) => DesktopCellText(
                i['categoryName'] as String? ?? 'Uncategorized',
                muted: true,
              ),
            ),
          DesktopColumn<Map<String, dynamic>>(
            label: 'On hand',
            width: 130,
            numeric: true,
            sortBy: (i) => (i['stock'] as num?) ?? 0,
            cell: (context, i) {
              final qty = (i['stock'] as num?)?.toDouble() ?? 0;
              final shown = buildStockQuantityPresentation(
                baseQuantity: qty,
                baseUnit: i['unit'] as String? ?? 'piece',
                preferredUnit: i['displayUnit'] as String?,
                unitsPerPreferredUnit: i['displayQuantityPerUnit'] as num?,
                lastReceivedQuantity: i['lastReceivedQuantity'] as num?,
              );
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  DesktopCellText(
                    shown.primary,
                    numeric: true,
                    color: qty <= 0 ? DesignColors.error : null,
                  ),
                  if (shown.secondary != null)
                    DesktopCellText(shown.secondary!, muted: true),
                ],
              );
            },
          ),
          if (!compact)
            DesktopColumn<Map<String, dynamic>>(
              label: 'Warns at',
              width: 96,
              numeric: true,
              sortBy: (i) => (i['minStock'] as num?) ?? 0,
              cell: (context, i) {
                final min = (i['minStock'] as num?)?.toInt() ?? 0;
                return DesktopCellText(
                  min > 0 ? '$min' : '—',
                  numeric: min > 0,
                  muted: true,
                );
              },
            ),
          DesktopColumn<Map<String, dynamic>>(
            label: 'Price',
            width: 104,
            numeric: true,
            sortBy: (i) => (i['price'] as num?) ?? 0,
            cell: (context, i) => DesktopCellText(
              formatMoney((i['price'] as num?) ?? 0),
              numeric: true,
            ),
          ),
          DesktopColumn<Map<String, dynamic>>(
            label: 'Status',
            width: 124,
            sortBy: (i) => _levelOf(i).index,
            cell: (context, i) {
              switch (_levelOf(i)) {
                case _Level.out:
                  return const DesktopStatusChip(
                    label: 'Out of stock',
                    color: DesignColors.error,
                  );
                case _Level.low:
                  return const DesktopStatusChip(
                    label: 'Low stock',
                    color: DesignColors.warning,
                  );
                case _Level.ok:
                  return const DesktopCellText('In stock', muted: true);
              }
            },
          ),
        ];
        final noun =
            rows.length == 1 ? 'product' : w.productsLabel.toLowerCase();
        return DesktopDataTable<Map<String, dynamic>>(
          columns: columns,
          rows: rows,
          rowId: _id,
          rowHeight: 48,
          minWidth: compact ? 540 : 760,
          loading: w.loading,
          initialSortColumn: 0,
          selectedId: w.selectedId,
          onRowSelected: (i) => w.onSelect(_id(i)),
          footer: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                Text(
                  '${formatMoney(rows.length, symbol: '')} $noun',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Expanded(
                  child: Text(
                    w.totalWorth == null
                        ? ''
                        : 'Stock worth ${formatMoney(w.totalWorth)}',
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

  Widget _inspector(BuildContext context, Map<String, dynamic> item) {
    final w = widget;
    final p = context.desktop;
    final qty = (item['stock'] as num?)?.toDouble() ?? 0;
    final min = (item['minStock'] as num?)?.toInt() ?? 0;
    final level = _levelOf(item);
    final color = switch (level) {
      _Level.ok => DesignColors.success,
      _Level.low => DesignColors.warning,
      _Level.out => DesignColors.error,
    };
    final shown = buildStockQuantityPresentation(
      baseQuantity: qty,
      baseUnit: item['unit'] as String? ?? 'piece',
      preferredUnit: item['displayUnit'] as String?,
      unitsPerPreferredUnit: item['displayQuantityPerUnit'] as num?,
      lastReceivedQuantity: item['lastReceivedQuantity'] as num?,
    );
    final top = [qty, min * 4.0, 1.0].reduce((a, b) => a > b ? a : b);
    final fill = (qty / top).clamp(0.0, 1.0);
    final tick = (min / top).clamp(0.0, 1.0);
    final cost = (item['costPrice'] as num?)?.toDouble() ?? 0;
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final lastReceived = item['lastReceivedAt'];

    Widget fact(String label, String value) => Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

    return DesktopInspector(
      title: item['name'] as String? ?? 'Unknown',
      subtitle: [
        if ((item['sku'] as String?)?.isNotEmpty == true) item['sku'] as String,
        item['categoryName'] as String? ?? 'Uncategorized',
      ].join(' · '),
      onClose: () => w.onSelect(null),
      footer: Row(
        children: [
          if (w.canReceive && w.onReceive != null)
            Expanded(
              child: FilledButton(
                style: desktopPrimaryButton(context),
                onPressed: () => w.onReceive!(item),
                child: const Text('Receive stock'),
              ),
            ),
          if (w.canReceive && w.onReceive != null && w.onOpenProduct != null)
            const SizedBox(width: 8),
          if (w.onOpenProduct != null)
            Expanded(
              child: OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: () => w.onOpenProduct!(item),
                child: const Text('Open product'),
              ),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.panelAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'On the shelf',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (level == _Level.low)
                      const DesktopStatusChip(
                        label: 'Low stock',
                        color: DesignColors.warning,
                      )
                    else if (level == _Level.out)
                      const DesktopStatusChip(
                        label: 'Out of stock',
                        color: DesignColors.error,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  shown.primary,
                  style: DesignType.numeric(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
                if (shown.secondary != null)
                  Text(
                    shown.secondary!,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 10,
                  child: LayoutBuilder(
                    builder: (context, box) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 2,
                          height: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: p.borderStrong.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 2,
                          height: 6,
                          width: box.maxWidth * fill,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        if (min > 0)
                          Positioned(
                            left: box.maxWidth * tick - 1,
                            top: 0,
                            width: 2,
                            height: 10,
                            child: ColoredBox(color: p.text),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          fact('Selling price', formatMoney(price)),
          if (w.showCost && cost > 0)
            fact('You paid', '${formatMoney(cost)} each'),
          if (w.showCost && cost > 0 && price > 0)
            fact('Worth on shelf', formatMoney(cost * qty)),
          fact('Warns below',
              min > 0 ? '$min ${item['unit'] ?? ''}' : 'Not set'),
          if (lastReceived is DateTime)
            fact(
              'Last delivery',
              '${lastReceived.day}/${lastReceived.month}/${lastReceived.year}',
            ),
        ],
      ),
    );
  }
}
