import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../domain/price_list_builder.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: title,
          subtitle:
              'Choose what to include. Prices use the latest values on your till.',
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
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
                      width: 116,
                      numeric: true,
                      sortBy: (item) => item.price,
                      cell: (context, item) =>
                          DesktopCellText(priceKes(item.price), numeric: true),
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
                  minWidth: 503,
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
