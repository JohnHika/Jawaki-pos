import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/cache/swr_cache.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/shop_name.dart';
import '../../../../core/widgets/alive_feedback.dart';
import '../../../sales/presentation/providers/catalog_provider.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/price_freshness.dart';
import '../../domain/price_history.dart';
import '../../domain/price_list_builder.dart';
import '../desktop/desktop_price_list_view.dart';
import '../providers/price_list_sync_provider.dart';
import '../widgets/price_detail_sheet.dart';
import '../widgets/price_list_mobile_view.dart';

/// Pick what to include and send today's prices to a customer on WhatsApp.
/// Traders sell by sending prices around; this makes that one tap, always
/// with the current prices from the till.
///
/// Refreshing asks the shop's server for the latest prices (the same catalogue
/// sync Products and Inventory use), not just the copy on this phone. A shop
/// that keeps everything on the phone has no server to ask, so it only re-reads
/// its own list.
class PriceListScreen extends ConsumerStatefulWidget {
  const PriceListScreen({super.key});

  @override
  ConsumerState<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends ConsumerState<PriceListScreen> {
  final _phone = TextEditingController();
  final Set<String> _hiddenCategories = {};
  final _search = TextEditingController();
  String _query = '';
  bool _inStockOnly = true;
  bool _showTiers = true;
  bool _changedOnly = false;
  bool _copied = false;
  Timer? _copiedTimer;
  Timer? _clock;
  bool _userRefreshing = false;

  // The last prices seen on this phone: drawn at once while the till's own
  // list loads, and kept when it cannot.
  static final _cache = SwrCache(
    namespace: 'pricelist',
    schemaVersion: 2,
    softTtl: Duration.zero,
    hardTtl: const Duration(days: 30),
  );

  // The last price seen for each product, so a move can be shown as "up KES 5".
  static final _historyCache = SwrCache(
    namespace: 'pricelist_history',
    schemaVersion: 1,
    softTtl: Duration.zero,
    hardTtl: const Duration(days: 90),
  );

  _SavedPrices? _saved;
  Object? _lastPersistedRows;
  Object? _lastTrackedRows;
  PriceHistory _history = PriceHistory.empty;

  @override
  void initState() {
    super.initState();
    final user = getIt<StorageService>().getUser() ?? {};
    final phone = user['phone'];
    if (phone is String) _phone.text = phone;
    unawaited(_loadSaved());
    // Keep "Updated 5 min ago" honest while the page stays open.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(priceListSyncProvider.notifier).syncIfStale());
    });
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _clock?.cancel();
    _search.dispose();
    _phone.dispose();
    super.dispose();
  }

  String get _cacheKey {
    final user = getIt<StorageService>().getUser() ?? {};
    return '${user['tenantId'] ?? ''}:${user['branchId'] ?? ''}';
  }

  Future<void> _loadSaved() async {
    try {
      final entry = await _cache.read(_cacheKey);
      final json = entry?.json;
      if (json is Map && mounted) {
        final saved = _SavedPrices.fromJson(json);
        if (saved != null) setState(() => _saved = saved);
      }
    } catch (_) {
      // No saved copy: the page simply waits for the till.
    }
    try {
      final entry = await _historyCache.read(_cacheKey);
      if (entry != null && mounted && _history.isEmpty) {
        setState(() => _history = PriceHistory.fromJson(entry.json));
      }
    } catch (_) {
      // No history yet: the first prices seen become the starting point.
    }
  }

  /// Keeps what the till just showed, once per change of the list.
  void _persist(List<Map<String, dynamic>> rows, List<Map<String, dynamic>> cats) {
    if (identical(_lastPersistedRows, rows)) return;
    _lastPersistedRows = rows;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _cache.write(_cacheKey, _SavedPrices.slim(rows, cats));
      } catch (_) {}
    });
  }

  /// Folds the prices on screen into the history, once per change of the list.
  void _trackOnBuild(List<Map<String, dynamic>> rows) {
    if (identical(_lastTrackedRows, rows)) return;
    _lastTrackedRows = rows;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recordPrices(rows);
    });
  }

  /// Returns how many products moved to a different price than last seen.
  int _recordPrices(List<Map<String, dynamic>> rows) {
    final prices = <String, double>{};
    for (final p in rows) {
      final id = '${p['id'] ?? ''}';
      if (id.isEmpty) continue;
      prices[id] = asDouble(p['price']);
    }
    final next = _history.update(prices, DateTime.now());
    if (identical(next, _history)) return 0;
    var moved = 0;
    prices.forEach((id, price) {
      final old = _history.entries[id];
      if (old != null && (old.price - price).abs() > 0.004) moved++;
    });
    if (mounted) setState(() => _history = next);
    unawaited(() async {
      try {
        await _historyCache.write(_cacheKey, next.toJson());
      } catch (_) {}
    }());
    return moved;
  }

  List<PriceListRowData> _rows(
    List<Map<String, dynamic>> products,
    Map<String, String> categoryNames,
  ) {
    final rows = <PriceListRowData>[];
    final now = DateTime.now();
    for (final p in products) {
      final categoryId = '${p['categoryId'] ?? ''}';
      if (_hiddenCategories.contains(categoryId)) continue;
      final tracks = p['trackInventory'] != false;
      final stock = (p['stock'] as num?)?.toDouble() ?? 0;
      if (_inStockOnly && tracks && stock <= 0) continue;
      final minStock = p['minStock'];
      final lowRaw = p['lowStockThreshold'] ??
          p['reorderLevel'] ??
          (minStock is num && minStock > 0 ? minStock : null);
      final low = lowRaw is num ? lowRaw.toDouble() : null;
      final id = '${p['id'] ?? ''}';
      final price = asDouble(p['price']);
      rows.add(PriceListRowData(
        sku: p['sku'] == null ? null : '${p['sku']}',
        stock: !tracks
            ? PriceStock.untracked
            : stock <= 0
                ? PriceStock.out
                : (low != null && stock <= low
                    ? PriceStock.low
                    : PriceStock.available),
        item: PriceListItem(
          id: id,
          name: '${p['name']}',
          unit: '${p['unit'] ?? 'piece'}',
          price: price,
          categoryName: categoryNames[categoryId] ?? '',
          change: id.isEmpty ? null : _history.changeFor(id, price, now),
          tiers: [
            for (final t in (p['pricingTiers'] as List?) ?? const [])
              if (t is Map)
                PriceTierLine(
                  unit: '${t['unit']}',
                  quantityPerUnit: asDouble(t['quantityPerUnit'], 1),
                  price: asDouble(t['price']),
                ),
          ],
        ),
      ));
    }
    return rows;
  }

  List<PriceListItem> _items(
    List<Map<String, dynamic>> products,
    Map<String, String> categoryNames,
  ) =>
      [for (final r in _rows(products, categoryNames)) r.item];

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
    final businessLayout = ref.watch(businessLayoutProvider);
    final accent = businessLayout.preset.accent ?? DesignColors.accent;
    final products = ref.watch(filteredProductsProvider(FilterParams()));
    final categoriesAsync = ref.watch(categoriesProvider);
    final categories = categoriesAsync.valueOrNull ?? const [];
    final categoryNames = {
      for (final c in categories) '${c['id']}': '${c['name']}',
    };
    final sync = ref.watch(priceListSyncProvider);
    ref.listen<PriceSyncState>(priceListSyncProvider, (previous, next) {
      // A quiet refresh finished: show what it brought. (A pull or a tap on
      // Refresh reads the list itself.)
      if (previous?.syncing == true &&
          !next.syncing &&
          !next.lastFailed &&
          !_userRefreshing) {
        ref.invalidate(categoriesProvider);
        ref.invalidate(filteredProductsProvider);
      }
    });
    final freshness = sync.deviceOnly
        ? null
        : priceFreshnessLabel(sync.lastSyncedAt, DateTime.now());
    final savedPricesNote = sync.lastFailed && !sync.syncing && !sync.deviceOnly
        ? 'Showing saved prices'
        : null;

    final live = products.valueOrNull;
    if (live != null) _trackOnBuild(live);

    if (context.inDesktopShell) {
      final title = businessLayout.actionLabel('/price-list', 'Price List');
      return Scaffold(
        appBar: null,
        body: products.when(
          loading: () => _desktopWorkspace(
            context: context,
            title: title,
            businessLayout: businessLayout,
            categories: categories,
            items: const [],
            text: _text(const []),
            loading: true,
            sync: sync,
            freshness: freshness,
            savedNote: savedPricesNote,
          ),
          error: (e, _) => _desktopError(context, title, e),
          data: (rows) {
            final items = _items(rows, categoryNames);
            return _desktopWorkspace(
              context: context,
              title: title,
              businessLayout: businessLayout,
              categories: categories,
              items: items,
              text: _text(items),
              sync: sync,
              freshness: freshness,
              savedNote: savedPricesNote,
            );
          },
        ),
      );
    }

    // Phone and tablet. The saved copy stands in until the till answers, and
    // stays if it cannot.
    final liveCategories = categoriesAsync.valueOrNull;
    if (live != null) _persist(live, liveCategories ?? const []);
    final source = live ?? _saved?.products;
    final cats = liveCategories ?? _saved?.categories ?? const [];
    final names = {for (final c in cats) '${c['id']}': '${c['name']}'};
    final rows = source == null
        ? const <PriceListRowData>[]
        : _rows(source, names);
    final text = _text([for (final r in rows) r.item]);
    final usingSaved = live == null && source != null;
    final note = savedPricesNote ??
        (!usingSaved
            ? null
            : (products.hasError
                ? 'Showing your saved prices. They could not be refreshed.'
                : 'Showing your saved prices while they update'));

    return Scaffold(
      appBar: BrandedAppBar(
        title: businessLayout.actionLabel('/price-list', 'Price List'),
        showBackButton: GoRouter.of(context).canPop(),
      ),
      body: PriceListMobileView(
        rows: rows,
        categories: cats,
        accent: accent,
        hiddenCategoryIds: _hiddenCategories,
        query: _query,
        searchController: _search,
        onQueryChanged: (v) => setState(() => _query = v),
        onToggleCategory: (id) => setState(() {
          _changedOnly = false;
          if (!_hiddenCategories.add(id)) _hiddenCategories.remove(id);
        }),
        onShowAllCategories: () => setState(_hiddenCategories.clear),
        showTiers: _showTiers,
        onShowTiersChanged: (v) => setState(() => _showTiers = v),
        inStockOnly: _inStockOnly,
        onInStockOnlyChanged: (v) => setState(() => _inStockOnly = v),
        changedOnly: _changedOnly,
        onChangedOnlyChanged: (v) => setState(() => _changedOnly = v),
        productsLabel: businessLayout.productsLabel,
        productSingular: businessLayout.productSingular,
        phoneController: _phone,
        onPhoneChanged: (_) => setState(() {}),
        preview: text,
        sendCount: rows.length,
        copied: _copied,
        loading: products.isLoading && source == null,
        errorMessage: products.hasError && source == null
            ? apiErrorMessage(products.error!)
            : null,
        savedCopyNote: note,
        savedCopyCanRetry: savedPricesNote != null,
        freshness: freshness,
        syncing: sync.syncing,
        onRetry: () => ref.invalidate(filteredProductsProvider),
        onWhatsApp: rows.isEmpty ? null : () => _whatsapp(text),
        onPdf: rows.isEmpty ? null : () => _pdf([for (final r in rows) r.item]),
        onCopy: rows.isEmpty ? null : () => _copy(text),
        onRefresh: _refresh,
        onOpenRow: _openRow,
      ),
    );
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _copiedTimer?.cancel();
    _copiedTimer = AliveIcon.flash((v) {
      if (mounted) setState(() => _copied = v);
    });
    Alive.done(context, 'Price list copied', icon: Icons.copy_rounded);
  }

  /// One product's price, with Send and Copy for just that item.
  void _openRow(PriceListRowData data) {
    final businessLayout = ref.read(businessLayoutProvider);
    final text = buildPriceListText(
      shopName: currentShopName(),
      date: DateTime.now(),
      items: [data.item],
      phone: _phone.text,
      showTiers: true,
    );
    showPriceDetail(
      context,
      data: data,
      accent: businessLayout.preset.accent ?? DesignColors.accent,
      shareText: text,
      onWhatsApp: () => _whatsapp(text),
      onCopy: () {
        Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          Alive.done(context, '${data.item.name} copied',
              icon: Icons.copy_rounded);
        }
      },
    );
  }

  /// Pull to refresh, and the Refresh button on a computer: ask the shop's
  /// server for the latest prices, read the list again, then say what happened.
  /// A shop that keeps everything on the phone only re-reads its own list.
  Future<void> _refresh() async {
    _userRefreshing = true;
    try {
      final synced = await ref.read(priceListSyncProvider.notifier).refresh();
      ref.invalidate(categoriesProvider);
      final provider = filteredProductsProvider(FilterParams());
      ref.invalidate(provider);
      List<Map<String, dynamic>>? fresh;
      try {
        fresh = await ref.read(provider.future);
      } catch (_) {
        fresh = null;
      }
      if (!mounted) return;
      final moved = fresh == null ? 0 : _recordPrices(fresh);
      if (!synced) {
        // Calm, not an error: the list is still usable and says so itself.
        Alive.done(
          context,
          'Could not reach the shop. Showing saved prices.',
          icon: Icons.cloud_off_rounded,
          color: DesignColors.warning,
          haptic: false,
        );
      } else if (fresh == null) {
        Alive.failed(context, 'Could not refresh the prices. Try again.');
      } else {
        Alive.done(
          context,
          moved > 0 ? 'Prices updated · $moved changed' : 'Prices are up to date',
          icon: Icons.sync_rounded,
        );
      }
    } finally {
      _userRefreshing = false;
    }
  }

  Widget _desktopWorkspace({
    required BuildContext context,
    required String title,
    required BusinessLayoutConfig businessLayout,
    required List<Map<String, dynamic>> categories,
    required List<PriceListItem> items,
    required String text,
    required PriceSyncState sync,
    required String? freshness,
    required String? savedNote,
    bool loading = false,
  }) {
    return DesktopPriceListView(
      title: title,
      productSingular: businessLayout.productSingular,
      productsLabel: businessLayout.productsLabel,
      items: items,
      categories: categories,
      hiddenCategoryIds: _hiddenCategories,
      inStockOnly: _inStockOnly,
      onInStockOnlyChanged: (value) => setState(() => _inStockOnly = value),
      showTiers: _showTiers,
      onShowTiersChanged: (value) => setState(() => _showTiers = value),
      phoneController: _phone,
      onPhoneChanged: (_) => setState(() {}),
      preview: text,
      onToggleCategory: (id) => setState(() {
        if (!_hiddenCategories.add(id)) _hiddenCategories.remove(id);
      }),
      onWhatsApp: items.isEmpty ? null : () => _whatsapp(text),
      onSharePdf: items.isEmpty ? null : () => _pdf(items),
      onCopy: items.isEmpty ? null : () => _copy(text),
      loading: loading,
      onRefresh: _refresh,
      refreshing: sync.syncing,
      freshness: freshness,
      savedNote: savedNote,
      onOpenItem: (item) => _openRow(PriceListRowData(item: item)),
    );
  }

  Widget _desktopError(BuildContext context, String title, Object error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: title,
          subtitle: 'The current catalogue is unavailable.',
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
        ),
        Expanded(
          child: DesktopContent(
            child: DesktopPanel(
              title: 'Price list',
              child: DesktopEmptyState(
                icon: Icons.cloud_off_rounded,
                title: "Couldn't load price list",
                message: apiErrorMessage(error),
                action: OutlinedButton(
                  style: desktopSecondaryButton(context),
                  onPressed: () => ref.invalidate(filteredProductsProvider),
                  child: const Text('Try again'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A slim, JSON-safe copy of the till's products and categories, kept on the
/// phone for the next time the page opens.
class _SavedPrices {
  const _SavedPrices(this.products, this.categories);

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> categories;

  static Map<String, dynamic> slim(
    List<Map<String, dynamic>> products,
    List<Map<String, dynamic>> categories,
  ) =>
      {
        'products': [
          for (final p in products)
            {
              'id': '${p['id'] ?? ''}',
              'name': '${p['name']}',
              'sku': p['sku'] == null ? null : '${p['sku']}',
              'unit': '${p['unit'] ?? 'piece'}',
              'price': asDouble(p['price']),
              'categoryId': '${p['categoryId'] ?? ''}',
              'trackInventory': p['trackInventory'] != false,
              'stock': (p['stock'] as num?)?.toDouble() ?? 0,
              if (p['lowStockThreshold'] is num)
                'lowStockThreshold': p['lowStockThreshold'],
              if (p['minStock'] is num) 'minStock': p['minStock'],
              'pricingTiers': [
                for (final t in (p['pricingTiers'] as List?) ?? const [])
                  if (t is Map)
                    {
                      'unit': '${t['unit']}',
                      'quantityPerUnit': asDouble(t['quantityPerUnit'], 1),
                      'price': asDouble(t['price']),
                    },
              ],
            },
        ],
        'categories': [
          for (final c in categories)
            {'id': '${c['id']}', 'name': '${c['name']}'},
        ],
      };

  static _SavedPrices? fromJson(Map json) {
    try {
      final copy = jsonDecode(jsonEncode(json)) as Map;
      return _SavedPrices(
        [
          for (final p in copy['products'] as List)
            Map<String, dynamic>.from(p as Map),
        ],
        [
          for (final c in copy['categories'] as List)
            Map<String, dynamic>.from(c as Map),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}
