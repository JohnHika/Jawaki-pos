import 'dart:ui' show DisplayFeatureType, DisplayFeatureState, FontFeature;

import 'package:flutter/material.dart';

import '../../../../core/responsive/device_class.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/alive_feedback.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../../core/widgets/skeleton_kit.dart';
import '../../domain/price_history.dart';
import '../../domain/price_list_builder.dart';
import '../../domain/price_row_data.dart';
import 'price_detail_sheet.dart';

export '../../domain/price_row_data.dart';

/// The phone and tablet price list: a sticky header (how many items, how fresh
/// the prices are, search, category chips), a flat list grouped by category with
/// the price in large type, and a send bar.
///
/// - **Phone:** one column. Options live in a sheet.
/// - **Tablet, till terminal, unfolded foldable:** the list sits beside a panel
///   with the options, the message preview and the send buttons. A vertical fold
///   or hinge in the screen becomes the split between the two.
///
/// What is listed is exactly what is sent.
class PriceListMobileView extends StatelessWidget {
  const PriceListMobileView({
    super.key,
    required this.rows,
    required this.categories,
    required this.hiddenCategoryIds,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onToggleCategory,
    required this.onShowAllCategories,
    required this.showTiers,
    required this.onShowTiersChanged,
    required this.inStockOnly,
    required this.onInStockOnlyChanged,
    required this.productsLabel,
    required this.productSingular,
    required this.phoneController,
    required this.onPhoneChanged,
    required this.preview,
    required this.onWhatsApp,
    required this.onPdf,
    required this.onCopy,
    required this.onRefresh,
    this.onOpenRow,
    this.accent = DesignColors.accent,
    this.copied = false,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.savedCopyNote,
    this.savedCopyCanRetry = false,
    this.sendCount = 0,
    this.freshness,
    this.syncing = false,
    this.changedOnly = false,
    this.onChangedOnlyChanged,
  });

  final List<PriceListRowData> rows;
  final List<Map<String, dynamic>> categories;
  final Set<String> hiddenCategoryIds;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onToggleCategory;
  final VoidCallback onShowAllCategories;
  final bool showTiers;
  final ValueChanged<bool> onShowTiersChanged;
  final bool inStockOnly;
  final ValueChanged<bool> onInStockOnlyChanged;
  final String productsLabel;
  final String productSingular;
  final TextEditingController phoneController;
  final ValueChanged<String> onPhoneChanged;
  final String preview;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onPdf;
  final VoidCallback? onCopy;
  final Future<void> Function() onRefresh;
  final ValueChanged<PriceListRowData>? onOpenRow;
  final bool copied;

  /// The business type's own colour, so a bakery and a bookshop do not look
  /// the same.
  final Color accent;

  /// No rows yet: draw placeholders shaped like the rows.
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// Set while rows come from the copy kept on the phone.
  final String? savedCopyNote;

  /// Shows a Retry button on the saved-copy note (asks the server again).
  final bool savedCopyCanRetry;

  /// How many items go out (before the search narrows what is shown).
  final int sendCount;

  /// "Updated 5 min ago", or null when the shop has no server to ask.
  final String? freshness;

  /// A refresh from the server is running.
  final bool syncing;

  /// Shows only the items whose price moved recently.
  final bool changedOnly;
  final ValueChanged<bool>? onChangedOnlyChanged;

  int get changedCount => rows.where((r) => r.item.change != null).length;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final fold = _foldSplit(context);
    final twoColumn = fold != null || context.hasRoomForTwoColumns;
    final list = _ListColumn(view: this);
    if (!twoColumn) {
      return TabletContent(
        child: SizedBox.expand(
          child: Column(
            children: [
              Expanded(child: list),
              _SendBar(view: this),
            ],
          ),
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final Widget panes;
    if (fold != null) {
      panes = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: fold.left, child: list),
          SizedBox(width: fold.width, child: ColoredBox(color: divider)),
          Expanded(child: _SidePanel(view: this)),
        ],
      );
    } else {
      final panelWidth = (width * 0.42).clamp(300.0, 380.0);
      panes = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: list),
          VerticalDivider(width: 1, color: divider),
          SizedBox(width: panelWidth, child: _SidePanel(view: this)),
        ],
      );
    }
    return TabletContent(child: SizedBox.expand(child: panes));
  }

  /// Where a vertical fold or hinge splits the screen, when it does. A fold the
  /// phone is lying flat across is no reason to split: the content just
  /// spans it.
  Rect? _foldSplit(BuildContext context) {
    final media = MediaQuery.of(context);
    for (final feature in media.displayFeatures) {
      final splits = feature.type == DisplayFeatureType.hinge ||
          feature.state == DisplayFeatureState.postureHalfOpened;
      final vertical = feature.bounds.height > feature.bounds.width;
      if (!splits || !vertical) continue;
      final left = feature.bounds.left;
      final right = media.size.width - feature.bounds.right;
      if (left >= 260 && right >= 260) return feature.bounds;
    }
    return null;
  }

  /// Opens the options (and share) sheet on a phone.
  void showOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 520),
      backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(DesignSpacing.radiusXxl)),
      ),
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          DesignSpacing.xl,
          DesignSpacing.lg,
          DesignSpacing.xl,
          MediaQuery.viewInsetsOf(sheet).bottom + DesignSpacing.xl,
        ),
        child: SingleChildScrollView(
          child: _OptionsBlock(view: this, withShare: true),
        ),
      ),
    );
  }
}

/// Text colour for [accent] that stays readable on a tint of itself.
Color _inkOn(Color accent, bool isDark) =>
    isDark ? accent : Color.alphaBlend(Colors.black.withValues(alpha: 0.28), accent);

class _ListColumn extends StatelessWidget {
  const _ListColumn({required this.view});

  final PriceListMobileView view;

  List<Object> _entries() {
    final q = view.query.trim().toLowerCase();
    Iterable<PriceListRowData> shown = view.rows;
    if (view.changedOnly) shown = shown.where((r) => r.item.change != null);
    if (q.isNotEmpty) {
      shown = shown.where((r) =>
          r.item.name.toLowerCase().contains(q) ||
          (r.sku ?? '').toLowerCase().contains(q));
    }
    final groups = <String, List<PriceListRowData>>{};
    for (final r in shown) {
      final name = r.item.categoryName.trim().isEmpty
          ? 'Other'
          : r.item.categoryName.trim();
      groups.putIfAbsent(name, () => []).add(r);
    }
    final names = groups.keys.toList()
      ..sort((a, b) {
        if (a == 'Other') return 1;
        if (b == 'Other') return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return [
      for (final name in names) ...[
        _SectionTitle(name, groups[name]!.length, accent: view.accent),
        ...(groups[name]!
          ..sort((a, b) =>
              a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase()))),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StickyHeader(view: view),
        if (view.savedCopyNote != null)
          _SavedCopyNote(
            view.savedCopyNote!,
            onRetry: view.savedCopyCanRetry ? () => view.onRefresh() : null,
          ),
        Expanded(child: _body(context, isDark)),
      ],
    );
  }

  Widget _body(BuildContext context, bool isDark) {
    if (view.errorMessage != null && view.rows.isEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load the price list",
          subtitle: view.errorMessage,
          actionLabel: 'Try again',
          onAction: view.onRetry,
        ),
      );
    }
    if (view.loading && view.rows.isEmpty) {
      return ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, 0, DesignSpacing.lg, 0),
        itemCount: 9,
        itemBuilder: (_, __) => const _RowSkeleton(),
      );
    }
    final entries = _entries();
    if (entries.isEmpty) {
      return RefreshIndicator(
        color: view.accent,
        onRefresh: view.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: 360, child: Center(child: _emptyState())),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: view.accent,
      onRefresh: view.onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: DesignSpacing.xxxl),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          if (e is _SectionTitle) return e;
          final data = e as PriceListRowData;
          final nextIsRow = i + 1 < entries.length && entries[i + 1] is! _SectionTitle;
          return _PriceRow(
            data: data,
            showTiers: view.showTiers,
            accent: view.accent,
            divider: nextIsRow,
            onTap: view.onOpenRow == null ? null : () => view.onOpenRow!(data),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    final searching = view.query.trim().isNotEmpty;
    final hiding = view.inStockOnly;
    if (view.changedOnly && !searching) {
      return EmptyState(
        icon: Icons.trending_flat_rounded,
        title: 'No price changes this week',
        subtitle: 'When a price goes up or down it shows here for 7 days.',
        actionLabel: 'Show everything',
        actionIcon: Icons.list_alt_rounded,
        onAction: () => view.onChangedOnlyChanged?.call(false),
      );
    }
    return EmptyState(
      icon: searching ? Icons.search_off_rounded : Icons.sell_outlined,
      title: searching
          ? 'Nothing matches "${view.query.trim()}"'
          : 'No ${view.productsLabel.toLowerCase()} on this list',
      subtitle: searching
          ? 'Check the spelling, or clear the search.'
          : (hiding
              ? 'Out-of-stock ${view.productsLabel.toLowerCase()} are left off. Include them to see more.'
              : 'Add ${view.productsLabel.toLowerCase()} and their prices will appear here.'),
      actionLabel:
          searching ? 'Clear search' : (hiding ? 'Include out of stock' : null),
      actionIcon:
          searching ? Icons.close_rounded : Icons.inventory_2_outlined,
      onAction: searching
          ? () {
              view.searchController.clear();
              view.onQueryChanged('');
            }
          : (hiding ? () => view.onInStockOnlyChanged(false) : null),
    );
  }
}

class _StickyHeader extends StatelessWidget {
  const _StickyHeader({required this.view});

  final PriceListMobileView view;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DesignColors.darkSurface : Colors.white;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final primary =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final allIncluded = view.hiddenCategoryIds.isEmpty && !view.changedOnly;
    final changed = view.changedCount;
    final loadingFirst = view.loading && view.rows.isEmpty;
    final noun = view.sendCount == 1
        ? view.productSingular.toLowerCase()
        : view.productsLabel.toLowerCase();
    final stale = view.savedCopyNote != null;
    final dot = view.syncing
        ? view.accent
        : (stale ? DesignColors.warning : DesignColors.success);

    return Material(
      color: bg,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        padding: const EdgeInsets.only(top: DesignSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loadingFirst
                              ? 'Loading prices…'
                              : '${view.sendCount} $noun on the list',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: primary,
                          ),
                        ),
                        if (view.freshness != null || view.syncing) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                    color: dot, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  view.syncing
                                      ? 'Updating prices…'
                                      : view.freshness!,
                                  key: const ValueKey('price-list-freshness'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  _RefreshButton(
                    syncing: view.syncing,
                    accent: view.accent,
                    onPressed: view.onRefresh,
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.lg),
              child: TextField(
                controller: view.searchController,
                onChanged: view.onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search ${view.productsLabel.toLowerCase()} or code',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: view.query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            view.searchController.clear();
                            view.onQueryChanged('');
                          },
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceMuted,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: view.accent, width: 1.4),
                  ),
                ),
              ),
            ),
            if (view.categories.isNotEmpty || changed > 0) ...[
              const SizedBox(height: DesignSpacing.sm),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: DesignSpacing.lg),
                  children: [
                    ChoicePill(
                      label: 'All',
                      color: view.accent,
                      selected: allIncluded,
                      onTap: () {
                        view.onShowAllCategories();
                        view.onChangedOnlyChanged?.call(false);
                      },
                    ),
                    if (changed > 0) ...[
                      const SizedBox(width: 8),
                      ChoicePill(
                        key: const ValueKey('price-list-changed-chip'),
                        label: 'Changed · $changed',
                        icon: Icons.swap_vert_rounded,
                        color: view.accent,
                        selected: view.changedOnly,
                        onTap: () => view.onChangedOnlyChanged
                            ?.call(!view.changedOnly),
                      ),
                    ],
                    for (final c in view.categories) ...[
                      const SizedBox(width: 8),
                      ChoicePill(
                        label: '${c['name']}',
                        color: view.accent,
                        selected:
                            !view.hiddenCategoryIds.contains('${c['id']}'),
                        onTap: () => view.onToggleCategory('${c['id']}'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: DesignSpacing.sm),
            if (view.syncing)
              LinearProgressIndicator(
                minHeight: 2,
                color: view.accent,
                backgroundColor: Colors.transparent,
              ),
          ],
        ),
      ),
    );
  }
}

/// Refresh from the server. Shows a small spinner while it runs.
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({
    required this.syncing,
    required this.accent,
    required this.onPressed,
  });

  final bool syncing;
  final Color accent;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: 'Refresh prices',
      child: Material(
        color: isDark
            ? DesignColors.darkSurfaceElevated
            : DesignColors.surfaceMuted,
        shape: const CircleBorder(),
        child: InkWell(
          key: const ValueKey('price-list-refresh'),
          customBorder: const CircleBorder(),
          onTap: syncing ? null : () => onPressed(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: syncing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: accent),
                    )
                  : Icon(Icons.refresh_rounded,
                      size: 21, color: _inkOn(accent, isDark)),
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedCopyNote extends StatelessWidget {
  const _SavedCopyNote(this.text, {this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: DesignColors.info.withValues(alpha: isDark ? 0.12 : 0.10),
      padding: const EdgeInsets.only(
          left: DesignSpacing.lg, right: DesignSpacing.sm),
      constraints: const BoxConstraints(minHeight: 36),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, size: 15, color: DesignColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              key: const ValueKey('price-list-saved-note'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? DesignColors.darkTextSecondary
                    : DesignColors.textSecondary,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              key: const ValueKey('price-list-retry'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(48, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.name, this.count, {required this.accent});

  final String name;
  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
      padding: const EdgeInsets.fromLTRB(
          DesignSpacing.lg, DesignSpacing.lg, DesignSpacing.lg, 8),
      child: Row(
        children: [
          Text(
            name.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: isDark
                  ? DesignColors.darkTextTertiary
                  : DesignColors.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _inkOn(accent, isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.data,
    required this.showTiers,
    required this.accent,
    required this.divider,
    this.onTap,
  });

  final PriceListRowData data;
  final bool showTiers;
  final Color accent;

  /// Draws the hairline under this row (not under the last row of a group).
  final bool divider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final item = data.item;
    final unit = item.unit == 'piece' || item.unit.isEmpty ? null : item.unit;
    final amount = priceKes(item.price).replaceFirst('KES ', '');
    final sub = [
      if (unit != null) 'per $unit',
      if ((data.sku ?? '').isNotEmpty) data.sku!,
    ].join(' · ');
    final initial = item.name.trim().isEmpty
        ? '?'
        : item.name.trim().substring(0, 1).toUpperCase();
    final out = data.stock == PriceStock.out;
    final change = item.change;
    final line = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;

    return Material(
      color: isDark ? DesignColors.darkSurface : Colors.white,
      child: InkWell(
        onTap: onTap,
        splashColor: accent.withValues(alpha: 0.10),
        highlightColor: accent.withValues(alpha: 0.05),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(
              horizontal: DesignSpacing.lg, vertical: DesignSpacing.md),
          decoration: BoxDecoration(
            border: divider
                ? Border(
                    bottom: BorderSide(color: line),
                  )
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    color: _inkOn(accent, isDark),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: primary,
                        height: 1.2,
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: secondary)),
                    ],
                    if (data.stock == PriceStock.low || out) ...[
                      const SizedBox(height: 6),
                      PriceStockChip(data.stock),
                    ],
                    if (showTiers && item.tiers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in item.tiers)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? DesignColors.darkSurfaceElevated
                                    : DesignColors.surfaceSubtle,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${t.unit} ${priceKes(t.price).replaceFirst('KES ', '')}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: secondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: 'KES ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: secondary,
                        ),
                      ),
                      TextSpan(
                        text: amount,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: out ? secondary : primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ]),
                  ),
                  if (change != null) ...[
                    const SizedBox(height: 6),
                    PriceChangePill(change: change, compact: true),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "▲ 5": a recent move in a price, small enough to sit under the price.
class PriceChangePill extends StatelessWidget {
  const PriceChangePill({super.key, required this.change, this.compact = false});

  final PriceChange change;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = PriceChangeStyle.of(change);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = compact
        ? priceKes(change.delta.abs()).replaceFirst('KES ', '')
        : priceChangeLabel(change, priceKes);
    return Semantics(
      label: priceChangeLabel(change, priceKes),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: style.color.withValues(alpha: isDark ? 0.18 : 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 11, color: _inkOn(style.color, isDark)),
            const SizedBox(width: 2),
            Text(
              text,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: _inkOn(style.color, isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder shaped like [_PriceRow].
class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? DesignColors.darkBorder
                : DesignColors.surfaceBorderLight,
          ),
        ),
      ),
      child: const SkeletonRow(leading: true, height: 76),
    );
  }
}

class _SendBar extends StatelessWidget {
  const _SendBar({required this.view});

  final PriceListMobileView view;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color:
                isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
          DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, DesignSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: GradientButton(
              label: 'Send on WhatsApp',
              icon: Icons.chat_rounded,
              height: 52,
              borderRadius: 14,
              gradient: [
                view.accent,
                Color.alphaBlend(Colors.black.withValues(alpha: 0.18), view.accent),
              ],
              onPressed: view.onWhatsApp,
            ),
          ),
          const SizedBox(width: DesignSpacing.sm),
          _SquareAction(
            tooltip: 'Copy price list',
            onTap: view.onCopy,
            child: AliveIcon(
              done: view.copied,
              idle: const Icon(Icons.copy_rounded, size: 20),
            ),
          ),
          const SizedBox(width: DesignSpacing.sm),
          _SquareAction(
            tooltip: 'Options',
            onTap: () => view.showOptions(context),
            child: const Icon(Icons.tune_rounded, size: 21),
          ),
        ],
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 52,
            height: 52,
            child: IconTheme(
              data: IconThemeData(
                color: enabled
                    ? (isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary)
                    : (isDark
                        ? DesignColors.darkTextTertiary
                        : DesignColors.textTertiary),
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tablet / till-terminal side panel: options, preview and the send buttons.
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.view});

  final PriceListMobileView view;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? DesignColors.darkSurface : Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(DesignSpacing.xl),
        children: [
          Text(
            'Send this list',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? DesignColors.darkTextPrimary
                  : DesignColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'It always uses the prices on your till right now.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: DesignSpacing.lg),
          _OptionsBlock(view: view, withShare: false),
          const SizedBox(height: DesignSpacing.lg),
          const FormLabel('Preview'),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(DesignSpacing.md),
            decoration: BoxDecoration(
              color: isDark
                  ? DesignColors.darkSurfaceElevated
                  : DesignColors.surfaceMuted,
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            ),
            child: SingleChildScrollView(
              child: SelectableText(view.preview,
                  style: const TextStyle(fontSize: 12.5, height: 1.4)),
            ),
          ),
          const SizedBox(height: DesignSpacing.lg),
          GradientButton(
            label: 'Send on WhatsApp',
            icon: Icons.chat_rounded,
            height: 52,
            borderRadius: 14,
            gradient: [
              view.accent,
              Color.alphaBlend(Colors.black.withValues(alpha: 0.18), view.accent),
            ],
            onPressed: view.onWhatsApp,
          ),
          const SizedBox(height: DesignSpacing.sm),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: view.onPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Share PDF'),
              ),
            ),
            const SizedBox(width: DesignSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: view.onCopy,
                icon: AliveIcon(
                  done: view.copied,
                  idle: const Icon(Icons.copy_rounded),
                ),
                label: const Text('Copy'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// The choices about what goes out, with the phone number line. Keeps its own
/// copy of the two switches so it also works inside a bottom sheet, which does
/// not rebuild when the page behind it does.
class _OptionsBlock extends StatefulWidget {
  const _OptionsBlock({required this.view, required this.withShare});

  final PriceListMobileView view;

  /// Adds the PDF button (the phone sheet has no side panel).
  final bool withShare;

  @override
  State<_OptionsBlock> createState() => _OptionsBlockState();
}

class _OptionsBlockState extends State<_OptionsBlock> {
  late bool _inStock = widget.view.inStockOnly;
  late bool _tiers = widget.view.showTiers;

  @override
  void didUpdateWidget(covariant _OptionsBlock old) {
    super.didUpdateWidget(old);
    if (old.view.inStockOnly != widget.view.inStockOnly) {
      _inStock = widget.view.inStockOnly;
    }
    if (old.view.showTiers != widget.view.showTiers) {
      _tiers = widget.view.showTiers;
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.withShare)
          Padding(
            padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
            child: Text(
              'List options',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? DesignColors.darkTextPrimary
                    : DesignColors.textPrimary,
              ),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _inStock,
          activeThumbColor: view.accent,
          onChanged: (v) {
            setState(() => _inStock = v);
            view.onInStockOnlyChanged(v);
          },
          title: Text('Only ${view.productsLabel.toLowerCase()} in stock'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _tiers,
          activeThumbColor: view.accent,
          onChanged: (v) {
            setState(() => _tiers = v);
            view.onShowTiersChanged(v);
          },
          title: const Text('Show bulk prices'),
          subtitle: const Text('Dozen, carton and other wholesale prices'),
        ),
        const SizedBox(height: DesignSpacing.sm),
        TextField(
          controller: view.phoneController,
          keyboardType: TextInputType.phone,
          onChanged: view.onPhoneChanged,
          decoration: kitFieldDecoration(
            context,
            label: 'Phone on the list',
            hint: 'So customers know how to reach you',
            prefixIcon: Icons.phone_outlined,
          ),
        ),
        if (widget.withShare) ...[
          const SizedBox(height: DesignSpacing.lg),
          OutlinedButton.icon(
            onPressed: view.onPdf == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    view.onPdf!();
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Share PDF'),
          ),
        ],
      ],
    );
  }
}
