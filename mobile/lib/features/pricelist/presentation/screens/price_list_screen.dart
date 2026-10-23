import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/shop_name.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../sales/presentation/providers/catalog_provider.dart';
import '../../domain/price_list_builder.dart';

/// Pick what to include and send today's prices to a customer on WhatsApp.
/// Traders sell by sending prices around; this makes that one tap, always
/// with the current prices from the till.
class PriceListScreen extends ConsumerStatefulWidget {
  const PriceListScreen({super.key});

  @override
  ConsumerState<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends ConsumerState<PriceListScreen> {
  final _phone = TextEditingController();
  final Set<String> _hiddenCategories = {};
  bool _inStockOnly = true;
  bool _showTiers = true;

  @override
  void initState() {
    super.initState();
    final user = getIt<StorageService>().getUser() ?? {};
    final phone = user['phone'];
    if (phone is String) _phone.text = phone;
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  List<PriceListItem> _items(
    List<Map<String, dynamic>> products,
    Map<String, String> categoryNames,
  ) {
    final items = <PriceListItem>[];
    for (final p in products) {
      final categoryId = '${p['categoryId'] ?? ''}';
      if (_hiddenCategories.contains(categoryId)) continue;
      final tracks = p['trackInventory'] != false;
      final stock = (p['stock'] as num?)?.toDouble() ?? 0;
      if (_inStockOnly && tracks && stock <= 0) continue;
      items.add(PriceListItem(
        name: '${p['name']}',
        unit: '${p['unit'] ?? 'piece'}',
        price: asDouble(p['price']),
        categoryName: categoryNames[categoryId] ?? '',
        tiers: [
          for (final t in (p['pricingTiers'] as List?) ?? const [])
            if (t is Map)
              PriceTierLine(
                unit: '${t['unit']}',
                quantityPerUnit: asDouble(t['quantityPerUnit'], 1),
                price: asDouble(t['price']),
              ),
        ],
      ));
    }
    return items;
  }

  String _text(List<PriceListItem> items) => buildPriceListText(
        shopName: currentShopName(),
        date: DateTime.now(),
        items: items,
        phone: _phone.text,
        showTiers: _showTiers,
      );

  Future<void> _whatsapp(String text) async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    await Share.share(text, subject: 'Price list');
  }

  Future<void> _pdf(List<PriceListItem> items) async {
    final sections = [
      for (final entry in groupPriceList(items).entries)
        PdfReportSection(
          heading: entry.key,
          headers: const ['Item', 'Price', 'Bulk prices'],
          rows: [
            for (final item in entry.value)
              [
                item.name,
                '${priceKes(item.price)}${item.unit == 'piece' || item.unit.isEmpty ? '' : ' per ${item.unit}'}',
                _showTiers
                    ? item.tiers
                        .map((t) => '${t.unit}: ${priceKes(t.price)}')
                        .join(', ')
                    : '',
              ],
          ],
        ),
    ];
    final bytes = await ExportDocumentService.buildPdfReport(
      title: 'Price list',
      companyName: currentShopName(),
      subtitle: [
        '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
        if (_phone.text.trim().isNotEmpty) _phone.text.trim(),
      ].join(' · '),
      sections: sections,
    );
    await ExportDocumentService.sharePdf(bytes, 'price-list');
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(filteredProductsProvider(FilterParams()));
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final categoryNames = {
      for (final c in categories) '${c['id']}': '${c['name']}',
    };
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Price List',
        showBackButton: GoRouter.of(context).canPop(),
      ),
      body: products.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(DesignSpacing.lg),
          children: [
            InlineRetryNotice(
              message: apiErrorMessage(e),
              onRetry: () => ref.invalidate(filteredProductsProvider),
            ),
          ],
        ),
        data: (rows) {
          final items = _items(rows, categoryNames);
          final text = _text(items);
          return ListView(
            padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                DesignSpacing.md, DesignSpacing.lg, DesignSpacing.xxxl),
            children: [
              Text(
                'Send your prices to a customer in one tap. It always uses the prices on your till right now.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: DesignSpacing.md),
              if (categories.isNotEmpty) ...[
                const FormLabel('Include'),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in categories)
                    ChoicePill(
                      label: '${c['name']}',
                      selected: !_hiddenCategories.contains('${c['id']}'),
                      onTap: () => setState(() {
                        final id = '${c['id']}';
                        if (!_hiddenCategories.add(id)) {
                          _hiddenCategories.remove(id);
                        }
                      }),
                    ),
                ]),
                const SizedBox(height: DesignSpacing.md),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _inStockOnly,
                activeThumbColor: DesignColors.accent,
                onChanged: (v) => setState(() => _inStockOnly = v),
                title: const Text('Only items in stock'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showTiers,
                activeThumbColor: DesignColors.accent,
                onChanged: (v) => setState(() => _showTiers = v),
                title: const Text('Show bulk prices'),
                subtitle: const Text('Dozen, carton and other wholesale prices'),
              ),
              const SizedBox(height: DesignSpacing.sm),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: kitFieldDecoration(context,
                    label: 'Phone on the list',
                    hint: 'So customers know how to reach you',
                    prefixIcon: Icons.phone_outlined),
              ),
              const SizedBox(height: DesignSpacing.lg),
              Text('${items.length} item${items.length == 1 ? '' : 's'} on the list',
                  style: TextStyle(color: secondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: DesignSpacing.sm),
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                padding: const EdgeInsets.all(DesignSpacing.md),
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceBorder.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(text,
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                ),
              ),
              const SizedBox(height: DesignSpacing.lg),
              GradientButton(
                label: 'Send on WhatsApp',
                icon: Icons.chat_rounded,
                onPressed: items.isEmpty ? null : () => _whatsapp(text),
              ),
              const SizedBox(height: DesignSpacing.sm),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: items.isEmpty ? null : () => _pdf(items),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Share PDF'),
                  ),
                ),
                const SizedBox(width: DesignSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: items.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: text));
                            showGlassSnackBar(context, 'Price list copied',
                                icon: Icons.copy_rounded,
                                color: DesignColors.success);
                          },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy'),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}
