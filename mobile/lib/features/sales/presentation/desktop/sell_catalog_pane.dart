import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/business_layout_search.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
import 'sell_style.dart';

/// How the product area is drawn. Remembered per computer.
enum SellProductView { list, grid }

/// The left half of the till: an always-live search / scan field, quick
/// filters and the products as a dense list or a grid of tiles.
///
/// The search field keeps keyboard focus: type to filter, Down / Up to move
/// the highlight, Enter to add the highlighted product to the ticket.
class SellCatalogPane extends ConsumerStatefulWidget {
  const SellCatalogPane({
    super.key,
    required this.searchController,
    required this.searchFocus,
    required this.view,
    required this.onViewChanged,
    required this.onAdd,
    this.notice,
    this.onDismissNotice,
    this.showFavorites = false,
    this.onFavoritesChanged,
    this.productPages = const [],
    this.selectedProductPageId,
    this.onProductPageChanged,
    this.catalogRefreshing = false,
    this.catalogSyncFailed = false,
    this.isOffline = false,
    this.isLocalWorkspace = false,
    this.onRetryCatalog,
    this.onOpenProducts,
  });

  final TextEditingController searchController;
  final FocusNode searchFocus;
  final SellProductView view;
  final ValueChanged<SellProductView> onViewChanged;

  /// Add one of [product] to the ticket.
  final ValueChanged<Map<String, dynamic>> onAdd;

  final SellNotice? notice;
  final VoidCallback? onDismissNotice;

  final bool showFavorites;
  final ValueChanged<bool>? onFavoritesChanged;
  final List<BusinessLayoutProductPage> productPages;
  final String? selectedProductPageId;
  final ValueChanged<String?>? onProductPageChanged;

  final bool catalogRefreshing;
  final bool catalogSyncFailed;
  final bool isOffline;
  final bool isLocalWorkspace;
  final VoidCallback? onRetryCatalog;
  final VoidCallback? onOpenProducts;

  @override
  ConsumerState<SellCatalogPane> createState() => _SellCatalogPaneState();
}

class _SellCatalogPaneState extends ConsumerState<SellCatalogPane> {
  static const double _rowHeight = 44;
  static const double _tileHeight = 92;
  static const double _gap = 8;

  final _scroll = ScrollController();
  Timer? _debounce;
  int? _highlight;
  int _columns = 4;
  List<Map<String, dynamic>> _visible = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      ref.read(searchQueryProvider.notifier).state = '';
      return;
    }
    // Read the field when the timer fires, not the value typed 160 ms ago: a
    // scan that slipped a character in is undone by then.
    _debounce = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      ref.read(searchQueryProvider.notifier).state =
          widget.searchController.text;
    });
  }

  int? get _effectiveHighlight {
    if (_visible.isEmpty) return null;
    final h = _highlight ??
        (ref.read(searchQueryProvider).trim().isNotEmpty ? 0 : null);
    if (h == null) return null;
    return h.clamp(0, _visible.length - 1);
  }

  void _move(int delta) {
    if (_visible.isEmpty) return;
    final current = _effectiveHighlight;
    final next = current == null
        ? (delta > 0 ? 0 : _visible.length - 1)
        : (current + delta).clamp(0, _visible.length - 1);
    setState(() => _highlight = next);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(next));
  }

  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final grid = widget.view == SellProductView.grid;
    final extent = grid ? _tileHeight + _gap : _rowHeight;
    final row = grid ? index ~/ _columns : index;
    final top = row * extent;
    final bottom = top + (grid ? _tileHeight : _rowHeight);
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top.clamp(0.0, position.maxScrollExtent));
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (bottom - position.viewportDimension)
            .clamp(0.0, position.maxScrollExtent),
      );
    }
  }

  void _commit() {
    final index = _effectiveHighlight;
    if (index == null) return;
    final product = _visible[index];
    widget.searchController.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    setState(() => _highlight = null);
    widget.onAdd(product);
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final grid = widget.view == SellProductView.grid;
    final empty = widget.searchController.text.isEmpty;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(grid ? _columns : 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(grid ? -_columns : -1);
      return KeyEventResult.handled;
    }
    if (grid && empty && key == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (grid && empty && key == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        _effectiveHighlight != null) {
      _commit();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        key == LogicalKeyboardKey.escape &&
        !empty) {
      widget.searchController.clear();
      ref.read(searchQueryProvider.notifier).state = '';
      setState(() => _highlight = null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  AsyncValue<List<Map<String, dynamic>>> _products(
    BusinessLayoutConfig layout,
  ) {
    final query = ref.watch(searchQueryProvider).trim();
    if (widget.showFavorites) {
      return ref.watch(favoriteProductsProvider).whenData(
            (all) => all
                .where(
                  (p) => businessLayoutProductMatchesSearch(
                    name: p['name'] as String? ?? '',
                    code: p['sku'] as String? ?? '',
                    metadata: p['metadata'],
                    layout: layout,
                    query: query,
                  ),
                )
                .toList(growable: false),
          );
    }
    final categoryId = layout.effectiveShowPosCategories
        ? ref.watch(selectedCategoryProvider)
        : null;
    final pageIds = widget.selectedProductPageId == null
        ? null
        : widget.productPages
            .where((p) => p.id == widget.selectedProductPageId)
            .firstOrNull
            ?.productIds;
    return ref.watch(
      filteredProductsProvider(
        FilterParams(
          categoryId: categoryId,
          searchQuery: query.isEmpty ? null : query,
          productIds: pageIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    final layout = ref.watch(businessLayoutProvider);
    ref.listen<String>(searchQueryProvider, (_, query) {
      if (widget.searchController.text != query && query.isEmpty) {
        widget.searchController.clear();
      }
      if (_highlight != null) setState(() => _highlight = null);
    });
    ref.listen<String?>(selectedCategoryProvider, (_, __) {
      if (_highlight != null) setState(() => _highlight = null);
    });
    final cart = ref.watch(cartProvider);
    final inTicket = <String, double>{
      for (final item in cart.items)
        item.productId: item.saleQuantity ?? item.quantity,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SearchBox(
                controller: widget.searchController,
                focusNode: widget.searchFocus,
                hint: layout.posSearchHint,
                onChanged: _onChanged,
                onKey: _onSearchKey,
                onSubmitted: (_) => _commit(),
                onClear: () {
                  widget.searchController.clear();
                  ref.read(searchQueryProvider.notifier).state = '';
                  widget.searchFocus.requestFocus();
                },
              ),
            ),
            const SizedBox(width: 10),
            _ViewToggle(view: widget.view, onChanged: widget.onViewChanged),
          ],
        ),
        const SizedBox(height: 8),
        _FilterChips(
          showFavorites: widget.showFavorites,
          onFavoritesChanged: widget.onFavoritesChanged,
          productPages: widget.productPages,
          selectedProductPageId: widget.selectedProductPageId,
          onProductPageChanged: widget.onProductPageChanged,
        ),
        if (widget.notice != null) ...[
          const SizedBox(height: 8),
          SellNoticeBanner(
            notice: widget.notice!,
            onClose: widget.onDismissNotice,
          ),
        ] else if (widget.catalogSyncFailed || widget.isOffline) ...[
          const SizedBox(height: 8),
          SellNoticeBanner(
            notice: SellNotice(
              widget.isOffline
                  ? 'Showing saved products. They may be out of date until you are back online.'
                  : 'The product list could not refresh. Showing saved products.',
              kind: SellNoticeKind.warning,
              actions: [
                if (!widget.isOffline && widget.onRetryCatalog != null)
                  SellNoticeAction('Refresh', widget.onRetryCatalog!),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(child: _results(context, s, layout, inTicket)),
      ],
    );
  }

  Widget _results(
    BuildContext context,
    SellStyle s,
    BusinessLayoutConfig layout,
    Map<String, double> inTicket,
  ) {
    final async = _products(layout);
    final data = async.valueOrNull;
    if (async.hasError && data == null) {
      return DesktopEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Products did not load',
        message: apiErrorMessage(async.error!),
        action: OutlinedButton(
          onPressed: () {
            ref.invalidate(filteredProductsProvider);
            ref.invalidate(favoriteProductsProvider);
            widget.onRetryCatalog?.call();
          },
          child: const Text('Try again'),
        ),
      );
    }
    if (data != null) _visible = data;
    final products = data ?? _visible;
    if (data == null && products.isEmpty) return _Skeleton(style: s);
    if (products.isEmpty) {
      if (widget.catalogRefreshing) return _Skeleton(style: s);
      return _emptyState(layout);
    }

    if (widget.view == SellProductView.list) {
      final highlight = _effectiveHighlight;
      return Column(
        children: [
          _ListHeader(style: s),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemExtent: _rowHeight,
              itemCount: products.length,
              itemBuilder: (context, i) => _ProductRow(
                product: products[i],
                highlighted: highlight == i,
                inTicket: inTicket[products[i]['id']],
                onTap: () {
                  setState(() => _highlight = i);
                  widget.onAdd(products[i]);
                },
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        _columns = ((box.maxWidth + _gap) / (150 + _gap)).floor().clamp(2, 8);
        final highlight = _effectiveHighlight;
        return GridView.builder(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _columns,
            mainAxisExtent: _tileHeight,
            crossAxisSpacing: _gap,
            mainAxisSpacing: _gap,
          ),
          itemCount: products.length,
          itemBuilder: (context, i) => _ProductTile(
            product: products[i],
            highlighted: highlight == i,
            inTicket: inTicket[products[i]['id']],
            onTap: () {
              setState(() => _highlight = i);
              widget.onAdd(products[i]);
            },
          ),
        );
      },
    );
  }

  Widget _emptyState(BusinessLayoutConfig layout) {
    final filtered = ref.read(searchQueryProvider).trim().isNotEmpty ||
        ref.read(selectedCategoryProvider) != null ||
        widget.selectedProductPageId != null;
    final catalog = layout.productsLabel.toLowerCase();
    if (widget.showFavorites) {
      return DesktopEmptyState(
        icon: Icons.favorite_border_rounded,
        title: 'No favourites yet',
        message:
            'Mark $catalog as favourites on the phone or in Products and they show here.',
      );
    }
    if (filtered) {
      return DesktopEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nothing matches',
        message:
            'No $catalog match this search. Check the spelling, scan the barcode or clear the filters.',
        action: OutlinedButton(
          onPressed: () {
            widget.searchController.clear();
            ref.read(searchQueryProvider.notifier).state = '';
            ref.read(selectedCategoryProvider.notifier).state = null;
            widget.onProductPageChanged?.call(null);
          },
          child: const Text('Clear filters'),
        ),
      );
    }
    if (widget.isOffline || widget.catalogSyncFailed) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No $catalog saved on this computer',
        message: widget.isOffline
            ? 'Connect to the internet to load your shop catalog, then try again.'
            : 'The catalog did not load. Check the connection and try again.',
        action: OutlinedButton(
          onPressed: widget.isOffline ? null : widget.onRetryCatalog,
          child: const Text('Try again'),
        ),
      );
    }
    return DesktopEmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'Add your first ${layout.productSingular.toLowerCase()}',
      message:
          'Items you add in ${layout.productsLabel} are ready to sell here. Scan or search to put them on the ticket.',
      action: widget.onOpenProducts == null
          ? null
          : OutlinedButton(
              onPressed: widget.onOpenProducts,
              child: Text('Open ${layout.productsLabel}'),
            ),
    );
  }
}

// ─── Search ───

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.onKey,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([focusNode, controller]),
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return Container(
          height: 40,
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: focused ? s.accentFill : s.p.borderStrong,
              width: focused ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(Icons.search_rounded, size: 19, color: s.p.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Focus(
                  onKeyEvent: onKey,
                  child: TextField(
                    key: const ValueKey('sell-search'),
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    // The search field stays live: clicking elsewhere must not
                    // take focus (and the scanner) away from it.
                    onTapOutside: (_) {},
                    textInputAction: TextInputAction.search,
                    cursorColor: s.p.accent,
                    style: s.body(size: 14),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: hint,
                      hintStyle: s.body(size: 14, color: s.p.textFaint),
                    ),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search (Esc)',
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: Icon(Icons.close_rounded, color: s.p.textMuted),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Tooltip(
                    message: 'Press F2 to search or scan',
                    child: SellKey('F2'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final SellProductView view;
  final ValueChanged<SellProductView> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    Widget button(SellProductView v, IconData icon, String tip) {
      final selected = view == v;
      return Tooltip(
        message: tip,
        child: HoverBuilder(
          builder: (context, hovered) => Material(
            color: selected
                ? s.p.selected
                : (hovered ? s.p.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: () => onChanged(v),
              hoverColor: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  icon,
                  size: 18,
                  color: selected ? s.p.text : s.p.textMuted,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: s.p.border),
      ),
      child: Row(
        children: [
          button(SellProductView.list, Icons.view_list_rounded, 'List'),
          const SizedBox(width: 2),
          button(SellProductView.grid, Icons.grid_view_rounded, 'Tiles'),
        ],
      ),
    );
  }
}

// ─── Filters ───

class _FilterChips extends ConsumerStatefulWidget {
  const _FilterChips({
    required this.showFavorites,
    required this.onFavoritesChanged,
    required this.productPages,
    required this.selectedProductPageId,
    required this.onProductPageChanged,
  });

  final bool showFavorites;
  final ValueChanged<bool>? onFavoritesChanged;
  final List<BusinessLayoutProductPage> productPages;
  final String? selectedProductPageId;
  final ValueChanged<String?>? onProductPageChanged;

  @override
  ConsumerState<_FilterChips> createState() => _FilterChipsState();
}

class _FilterChipsState extends ConsumerState<_FilterChips> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(businessLayoutProvider);
    final categories = layout.effectiveShowPosCategories
        ? ref.watch(categoriesProvider).valueOrNull ?? const []
        : const <Map<String, dynamic>>[];
    final selected = ref.watch(selectedCategoryProvider);
    final noFilter = !widget.showFavorites &&
        selected == null &&
        widget.selectedProductPageId == null;

    void clearOthers() {
      ref.read(selectedCategoryProvider.notifier).state = null;
      widget.onProductPageChanged?.call(null);
    }

    final chips = <Widget>[
      DesktopFilterChip(
        label: 'All',
        selected: noFilter,
        onTap: () {
          clearOthers();
          widget.onFavoritesChanged?.call(false);
        },
      ),
      if (layout.effectiveShowPosFavorites && widget.onFavoritesChanged != null)
        DesktopFilterChip(
          label: 'Favourites',
          selected: widget.showFavorites,
          onTap: () {
            clearOthers();
            widget.onFavoritesChanged!(true);
          },
        ),
      for (final page in widget.productPages)
        DesktopFilterChip(
          label: page.name,
          selected: widget.selectedProductPageId == page.id,
          onTap: () {
            ref.read(selectedCategoryProvider.notifier).state = null;
            widget.onFavoritesChanged?.call(false);
            widget.onProductPageChanged?.call(page.id);
          },
        ),
      for (final category in categories)
        DesktopFilterChip(
          label: category['name'] as String? ?? '',
          selected: selected == category['id'],
          onTap: () {
            widget.onProductPageChanged?.call(null);
            widget.onFavoritesChanged?.call(false);
            ref.read(selectedCategoryProvider.notifier).state =
                category['id'] as String?;
          },
        ),
    ];
    return SizedBox(
      height: 32,
      // A mouse wheel scrolls the row sideways.
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent && _scroll.hasClients) {
            final target = (_scroll.offset + event.scrollDelta.dy).clamp(
              0.0,
              _scroll.position.maxScrollExtent,
            );
            _scroll.jumpTo(target);
          }
        },
        child: ListView.separated(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => Center(child: chips[i]),
        ),
      ),
    );
  }
}

// ─── Products ───

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.style});

  final SellStyle style;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final label = s.body(size: 12, weight: FontWeight.w600, color: s.p.textMuted);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: s.p.border)),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Product', style: label)),
          SizedBox(
            width: 84,
            child: Text('Price', style: label, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 104,
            child: Text('In stock', style: label, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

({bool tracked, double stock, bool out, bool low}) _stockOf(
  Map<String, dynamic> product,
) {
  final tracked = product['trackInventory'] as bool? ?? true;
  final stock = (product['stock'] as num?)?.toDouble() ?? 0;
  final minStock = (product['minStock'] as num?)?.toDouble() ?? 0;
  final lowLevel = minStock > 0 ? minStock : 3.0;
  return (
    tracked: tracked,
    stock: stock,
    out: tracked && stock <= 0,
    low: tracked && stock > 0 && stock <= lowLevel,
  );
}

class _StockChip extends StatelessWidget {
  const _StockChip({required this.style, required this.compact});

  final SellStyle style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = style;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: s.tint(s.danger),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'Out of stock',
        style: s.body(size: 11.5, weight: FontWeight.w700, color: s.danger),
      ),
    );
  }
}

class _InTicketBadge extends StatelessWidget {
  const _InTicketBadge({required this.style, required this.qty});

  final SellStyle style;
  final double qty;

  @override
  Widget build(BuildContext context) {
    final s = style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: s.p.selected,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${sellQty(qty)} on ticket',
        style: s.body(size: 11, weight: FontWeight.w700, color: s.p.accent),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.highlighted,
    required this.inTicket,
    required this.onTap,
  });

  final Map<String, dynamic> product;
  final bool highlighted;
  final double? inTicket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    final stock = _stockOf(product);
    final sku = product['sku'] as String? ?? '';
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final muted = stock.out ? 0.6 : 1.0;
    return HoverBuilder(
      builder: (context, hovered) => Material(
        color: highlighted
            ? s.p.selected
            : (hovered ? s.p.hover : Colors.transparent),
        child: InkWell(
          onTap: onTap,
          hoverColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: s.p.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Opacity(
                    opacity: muted,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                product['name'] as String? ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: s.body(
                                  size: 13,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (inTicket != null) ...[
                              const SizedBox(width: 8),
                              _InTicketBadge(style: s, qty: inTicket!),
                            ],
                          ],
                        ),
                        if (sku.isNotEmpty)
                          Text(
                            sku,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: s.body(
                              size: 11.5,
                              color: s.p.textFaint,
                              height: 1.2,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 84,
                  child: Opacity(
                    opacity: muted,
                    child: Text(
                      sellMoney(price, symbol: false),
                      textAlign: TextAlign.right,
                      style: s.number(size: 13),
                    ),
                  ),
                ),
                SizedBox(
                  width: 104,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: stock.out
                        ? _StockChip(style: s, compact: true)
                        : !stock.tracked
                            ? Text(
                                '—',
                                style: s.body(color: s.p.textFaint),
                              )
                            : Text(
                                stock.low
                                    ? '${sellQty(stock.stock)} left'
                                    : sellQty(stock.stock),
                                style: s.number(
                                  size: 12.5,
                                  weight: FontWeight.w700,
                                  color: stock.low ? s.warning : s.p.textMuted,
                                ),
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.highlighted,
    required this.inTicket,
    required this.onTap,
  });

  final Map<String, dynamic> product;
  final bool highlighted;
  final double? inTicket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    final stock = _stockOf(product);
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    return HoverBuilder(
      builder: (context, hovered) => Material(
        color: highlighted
            ? s.p.selected
            : (hovered ? Color.alphaBlend(s.p.hover, s.surface) : s.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: highlighted ? s.accentFill : s.p.border,
            width: highlighted ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
            child: Opacity(
              opacity: stock.out ? 0.72 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      product['name'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: s.body(
                        size: 13,
                        weight: FontWeight.w600,
                        color: stock.out ? s.p.textMuted : s.p.text,
                        height: 1.25,
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        sellMoney(price, symbol: false),
                        style: s.number(size: 14),
                      ),
                      const Spacer(),
                      if (stock.out)
                        _StockChip(style: s, compact: true)
                      else if (inTicket != null)
                        _InTicketBadge(style: s, qty: inTicket!)
                      else if (stock.tracked)
                        Text(
                          stock.low
                              ? '${sellQty(stock.stock)} left'
                              : sellQty(stock.stock),
                          style: s.number(
                            size: 11.5,
                            weight: FontWeight.w700,
                            color: stock.low ? s.warning : s.p.textFaint,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.style});

  final SellStyle style;

  @override
  Widget build(BuildContext context) {
    final s = style;
    return Column(
      children: [
        for (var i = 0; i < 8; i++)
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: s.p.border)),
            ),
            child: FractionallySizedBox(
              widthFactor: 0.25 + 0.4 * math.Random(i).nextDouble(),
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  color: s.p.hover,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
