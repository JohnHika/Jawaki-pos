import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../../finance/presentation/desktop/desktop_figures_row.dart';

/// One suggested purchase.
class DesktopRestockItem {
  const DesktopRestockItem({
    required this.productName,
    required this.suggestedQty,
    required this.unitCost,
    required this.estimatedCost,
    required this.daysLeft,
    required this.currentStock,
  });

  final String productName;
  final double suggestedQty;
  final double unitCost;
  final double estimatedCost;

  /// 999 and above means there is no recent sales data to project from.
  final int daysLeft;
  final double currentStock;

  bool get urgent => daysLeft <= 3;

  factory DesktopRestockItem.fromMap(Map<String, dynamic> m) =>
      DesktopRestockItem(
        productName: m['productName'] as String? ?? 'Product',
        suggestedQty: (m['suggestedQty'] as num? ?? 0).toDouble(),
        unitCost: (m['unitCost'] as num? ?? 0).toDouble(),
        estimatedCost: (m['estimatedCost'] as num? ?? 0).toDouble(),
        daysLeft: (m['daysOfStockRemaining'] as num? ?? 999).toInt(),
        currentStock: (m['currentStock'] as num? ?? 0).toDouble(),
      );
}

/// Restock suggestions on a computer: what cash is available, what to buy
/// first, and the whole list in one table with a Buy button per row.
class DesktopRestockView extends StatelessWidget {
  const DesktopRestockView({
    super.key,
    required this.items,
    this.availableCash = 0,
    this.trimmedCount = 0,
    this.aiRationale,
    this.headerBottom,
    this.loading = false,
    this.errorMessage,
    this.restricted = false,
    this.noBranch = false,
    this.onRetry,
    this.onRefresh,
    this.onBuy,
  });

  final List<DesktopRestockItem> items;
  final double availableCash;

  /// Low-stock items left out because the cash would not stretch to them.
  final int trimmedCount;
  final String? aiRationale;
  final Widget? headerBottom;
  final bool loading;
  final String? errorMessage;
  final bool restricted;
  final bool noBranch;
  final VoidCallback? onRetry;
  final VoidCallback? onRefresh;
  final ValueChanged<DesktopRestockItem>? onBuy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: 'Restock suggestions',
          subtitle: 'What to buy next, ranked by how soon it runs out',
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          bottom: headerBottom,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: loading ? null : onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (restricted) {
      return const DesktopEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Restricted',
        message: 'Only stock keepers and above can view restock suggestions.',
      );
    }
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (errorMessage != null) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load restock suggestions",
        message: errorMessage,
        action: onRetry == null
            ? null
            : OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
      );
    }
    if (noBranch) {
      return const DesktopEmptyState(
        icon: Icons.store_mall_directory_outlined,
        title: 'No branch selected',
        message: 'Select a branch to see its restock suggestions.',
      );
    }

    final p = DesktopPalette.of(context);
    final spend = items.fold<double>(0, (a, i) => a + i.estimatedCost);
    final urgent = items.where((i) => i.urgent).length;
    final short = MediaQuery.sizeOf(context).height < 640;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(24, short ? 10 : 14, 24, 0),
          child: DesktopFiguresRow(
            dense: short,
            figures: [
              DesktopFigure(
                label: 'Cash available to restock',
                value: formatMoney(availableCash),
                hint: 'From today\'s cash position',
              ),
              DesktopFigure(
                label: 'Suggested spend',
                value: formatMoney(spend),
                hint: '${items.length} ${items.length == 1 ? 'item' : 'items'}',
              ),
              DesktopFigure(
                label: 'Urgent',
                value: '$urgent',
                hint: urgent == 0 ? 'Nothing about to run out' : '3 days or less',
                valueColor: urgent > 0 ? negativeAmountColor(p) : null,
              ),
              DesktopFigure(
                label: 'Waiting on cash',
                value: '$trimmedCount',
                hint: trimmedCount == 0 ? 'All affordable' : 'Left out for now',
              ),
            ],
          ),
        ),
        if (aiRationale != null && aiRationale!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: p.selected,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 17, color: p.dark ? DesignColors.accent : p.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      aiRationale!,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.text,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, short ? 10 : 14, 24, 20),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: p.dark ? p.panelAlt : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border),
              ),
              child: DesktopDataTable<DesktopRestockItem>(
                rows: items,
                rowId: (r) => r.productName,
                rowHeight: 48,
                minWidth: 700,
                initialSortColumn: 2,
                columns: [
                  DesktopColumn<DesktopRestockItem>(
                    label: 'Product',
                    flex: 3,
                    minWidth: 170,
                    sortBy: (r) => r.productName.toLowerCase(),
                    cell: (_, r) => DesktopCellText(r.productName, strong: true),
                  ),
                  DesktopColumn<DesktopRestockItem>(
                    label: 'In stock',
                    width: 92,
                    numeric: true,
                    sortBy: (r) => r.currentStock,
                    cell: (_, r) => DesktopCellText(
                      r.currentStock.toStringAsFixed(0),
                      numeric: true,
                    ),
                  ),
                  DesktopColumn<DesktopRestockItem>(
                    label: 'Runs out in',
                    width: 132,
                    sortBy: (r) => r.daysLeft,
                    cell: (_, r) => r.daysLeft >= 999
                        ? const DesktopCellText('No sales data', muted: true)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DesktopCellText(
                                '${r.daysLeft} ${r.daysLeft == 1 ? 'day' : 'days'}',
                                strong: r.urgent,
                              ),
                              if (r.urgent) ...[
                                const SizedBox(width: 6),
                                const DesktopStatusChip(
                                  label: 'Urgent',
                                  color: DesignColors.error,
                                ),
                              ],
                            ],
                          ),
                  ),
                  DesktopColumn<DesktopRestockItem>(
                    label: 'Buy',
                    width: 84,
                    numeric: true,
                    sortBy: (r) => r.suggestedQty,
                    cell: (_, r) => DesktopCellText(
                      r.suggestedQty.toStringAsFixed(0),
                      numeric: true,
                      strong: true,
                    ),
                  ),
                  DesktopColumn<DesktopRestockItem>(
                    label: 'Unit cost',
                    width: 108,
                    numeric: true,
                    sortBy: (r) => r.unitCost,
                    cell: (_, r) => DesktopCellText(
                      formatMoney(r.unitCost),
                      numeric: true,
                      muted: true,
                    ),
                  ),
                  DesktopColumn<DesktopRestockItem>(
                    label: 'Estimated cost',
                    width: 128,
                    numeric: true,
                    sortBy: (r) => r.estimatedCost,
                    cell: (_, r) => DesktopCellText(
                      formatMoney(r.estimatedCost),
                      numeric: true,
                      strong: true,
                    ),
                  ),
                  DesktopColumn<DesktopRestockItem>(
                    label: '',
                    width: 96,
                    cell: (context, r) => TextButton(
                      style: desktopLinkButton(context),
                      onPressed: onBuy == null ? null : () => onBuy!(r),
                      child: const Text('Buy'),
                    ),
                  ),
                ],
                footer: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Buy opens a supplier invoice with the quantity filled in.',
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                empty: DesktopEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: trimmedCount > 0
                      ? 'Not enough cash to restock yet'
                      : 'Stock levels look healthy',
                  message: trimmedCount > 0
                      ? '$trimmedCount low-stock ${trimmedCount == 1 ? 'item is' : 'items are'} waiting for more cash to become available.'
                      : 'No products are below their reorder level.',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
