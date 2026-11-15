import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../domain/price_history.dart';
import '../../domain/price_list_builder.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../widgets/price_detail_sheet.dart' show PriceChangeStyle;

/// The price-list workspace on a computer. The routed screen owns its data,
/// filters and actions; this view presents the current rows and reports edits.
class DesktopPriceListView extends StatelessWidget {
  const DesktopPriceListView({
    super.key,
    required this.title,
    required this.productSingular,
    required this.productsLabel,
    required this.items,
    required this.categories,
    required this.hiddenCategoryIds,
    required this.inStockOnly,
    required this.onInStockOnlyChanged,
    required this.showTiers,
    required this.onShowTiersChanged,
    required this.phoneController,
    required this.onPhoneChanged,
    required this.preview,
    required this.onToggleCategory,
    required this.onWhatsApp,
    required this.onSharePdf,
    required this.onCopy,
    this.loading = false,
    this.onRefresh,
    this.refreshing = false,
    this.freshness,
    this.savedNote,
    this.onOpenItem,
  });

  final String title;
  final String productSingular;
  final String productsLabel;
  final List<PriceListItem> items;
  final List<Map<String, dynamic>> categories;
  final Set<String> hiddenCategoryIds;
  final bool inStockOnly;
  final ValueChanged<bool> onInStockOnlyChanged;
  final bool showTiers;
  final ValueChanged<bool> onShowTiersChanged;
  final TextEditingController phoneController;
  final ValueChanged<String> onPhoneChanged;
  final String preview;
  final ValueChanged<String> onToggleCategory;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onSharePdf;
  final VoidCallback? onCopy;
  final bool loading;

  /// Pulls the shop's prices from the server. Null hides the Refresh button.
  final Future<void> Function()? onRefresh;
  final bool refreshing;

  /// "Updated 5 min ago", or null when the shop has no server to ask.
  final String? freshness;

  /// Shown above the table while the prices on screen are the saved ones.
  final String? savedNote;

  /// Double click or Enter on a row.
  final ValueChanged<PriceListItem>? onOpenItem;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final refresh = onRefresh;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: title,
          subtitle:
              'Choose what to include. Prices use the latest values on your till.',
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actions: [
            if (freshness != null || refreshing)
              Text(
                refreshing ? 'Updating prices…' : freshness!,
                key: const ValueKey('price-list-freshness'),
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (refresh != null)
              OutlinedButton.icon(
                key: const ValueKey('price-list-refresh'),
                style: desktopSecondaryButton(context),
                onPressed: refreshing ? null : () => refresh(),
                icon: refreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh'),
              ),
          ],
        ),
        Expanded(
          child: DesktopContent(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: SizedBox.expand(
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: constraints.maxWidth < 1020 ? 5 : 6,
                      child: _productsPanel(
                        context,
                        height: constraints.maxHeight,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: _previewPanel(
                        context,
                        height: constraints.maxHeight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    if (refresh == null) return body;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): () {
          if (!refreshing) refresh();
        },
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
          if (!refreshing) refresh();
        },
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        debugLabel: 'PriceListRefresh',
        child: body,
      ),
    );
  }

  Widget _productsPanel(BuildContext context, {required double height}) {
    final p = context.desktop;
    final bodyHeight = (height - 84).clamp(0.0, height).toDouble();
    final noun = items.length == 1
        ? productSingular.toLowerCase()
        : productsLabel.toLowerCase();
    return SizedBox(
      height: height,
      child: DesktopPanel(
        title: 'Products',
        subtitle: '${items.length} $noun included',
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: SizedBox(
          height: bodyHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Only ${productsLabel.toLowerCase()} in stock',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    key: const ValueKey('price-list-stock-toggle'),
                    value: inStockOnly,
                    onChanged: onInStockOnlyChanged,
                  ),
                ],
              ),
              if (savedNote != null)
                Container(
                  key: const ValueKey('price-list-saved-note'),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: p.panelAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, size: 15, color: p.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          savedNote!,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (onRefresh != null)
                        TextButton(
                          key: const ValueKey('price-list-retry'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(48, 28),
                          ),
                          onPressed: refreshing ? null : () => onRefresh!(),
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              if (categories.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 7),
                  child: Text(
                    'Include categories',
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 72),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final category in categories)
                          DesktopFilterChip(
                            label: '${category['name']}',
                            selected: !hiddenCategoryIds.contains(
                              '${category['id']}',
                            ),
                            onTap: () => onToggleCategory('${category['id']}'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: DesktopDataTable<PriceListItem>(
                  columns: [
                    DesktopColumn<PriceListItem>(
                      label: 'Item',
                      flex: 3,
                      minWidth: 170,
                      sortBy: (item) => item.name.toLowerCase(),
                      cell: (context, item) =>
                          DesktopCellText(item.name, strong: true),
                    ),
                    DesktopColumn<PriceListItem>(
                      label: 'Category',
                      flex: 2,
                      minWidth: 92,
                      sortBy: (item) => item.categoryName.toLowerCase(),
                      cell: (context, item) => DesktopCellText(
                        item.categoryName.trim().isEmpty
                            ? 'Other'
                            : item.categoryName,
                        muted: true,
                      ),
                    ),
                    DesktopColumn<PriceListItem>(
                      label: 'Price',
                      width: 140,
                      numeric: true,
                      sortBy: (item) => item.price,
                      cell: (context, item) {
                        final change = item.change;
                        final text =
                            DesktopCellText(priceKes(item.price), numeric: true);
                        if (change == null) return text;
                        final style = PriceChangeStyle.of(change);
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Tooltip(
                              message: priceChangeLabel(change, priceKes),
                              child: Icon(style.icon,
                                  size: 13, color: style.color),
                            ),
                            const SizedBox(width: 4),
                            Flexible(child: text),
                          ],
                        );
                      },
                    ),
                    DesktopColumn<PriceListItem>(
                      label: 'Bulk (KES)',
                      flex: 3,
                      minWidth: 125,
                      sortBy: (item) => item.tiers.length,
                      cell: (context, item) => DesktopCellText(
                        _tierSummary(item),
                        muted: !showTiers || item.tiers.isEmpty,
                      ),
                    ),
                  ],
                  rows: items,
                  rowId: (item) => '${item.categoryName}:${item.name}',
                  onRowActivated: onOpenItem,
                  minWidth: 527,
                  loading: loading,
                  empty: const DesktopEmptyState(
                    icon: Icons.filter_list_off_rounded,
                    title: 'No items match these settings',
                    message:
                        'Include a category or show products that are out of stock.',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _tierSummary(PriceListItem item) {
    if (!showTiers || item.tiers.isEmpty) return '—';
    return item.tiers
        .map((tier) =>
            '${tier.unit}: ${priceKes(tier.price).replaceFirst('KES ', '')}')
        .join(' · ');
  }

  Widget _previewPanel(BuildContext context, {required double height}) {
    final p = context.desktop;
    final bodyHeight = (height - 72).clamp(0.0, height).toDouble();
    return SizedBox(
      height: height,
      child: DesktopPanel(
        title: 'WhatsApp preview',
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          height: bodyHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('price-list-contact-phone'),
                controller: phoneController,
                keyboardType: TextInputType.phone,
                onChanged: onPhoneChanged,
                decoration: kitFieldDecoration(
                  context,
                  label: 'Phone on the list',
                  hint: 'So customers know how to reach you',
                  prefixIcon: Icons.phone_outlined,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show bulk prices',
                          style: GoogleFonts.plusJakartaSans(
                            color: p.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    key: const ValueKey('price-list-tiers-toggle'),
                    value: showTiers,
                    onChanged: onShowTiersChanged,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.panelAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        loading ? 'Loading current prices…' : preview,
                        key: const ValueKey('price-list-preview'),
                        style: GoogleFonts.plusJakartaSans(
                          color: p.text,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                key: const ValueKey('price-list-whatsapp'),
                style: desktopPrimaryButton(context),
                onPressed: items.isEmpty ? null : onWhatsApp,
                icon: const Icon(Icons.chat_rounded, size: 17),
                label: const Text('Send on WhatsApp'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('price-list-share-pdf'),
                      style: desktopSecondaryButton(context),
                      onPressed: items.isEmpty ? null : onSharePdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('Share PDF'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('price-list-copy'),
                      style: desktopSecondaryButton(context),
                      onPressed: items.isEmpty ? null : onCopy,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
