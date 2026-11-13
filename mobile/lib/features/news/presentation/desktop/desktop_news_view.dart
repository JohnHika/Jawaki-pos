import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/news_models.dart';

/// Business News on a computer: the shilling rates in a strip, topic chips, a
/// table of headlines and, for the one picked, an inspector with the summary
/// and a button that opens the original article in the browser.
///
/// Plain data in, callbacks out; the routed page owns the providers.
class DesktopNewsView extends StatelessWidget {
  const DesktopNewsView({
    super.key,
    required this.title,
    required this.items,
    required this.loading,
    required this.category,
    required this.onCategory,
    required this.selectedId,
    required this.onSelect,
    required this.onOpenArticle,
    required this.onRefresh,
    this.urgent = const [],
    this.rates,
    this.links = const [],
    this.error,
    this.onRetry,
  });

  final String title;
  final List<NewsItem> items;

  /// Headlines the digest marks as needing attention; pinned above the rest.
  final List<NewsItem> urgent;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final RateBoard? rates;
  final List<OfficialLink> links;
  final String? category;
  final ValueChanged<String?> onCategory;
  final String? selectedId;
  final ValueChanged<NewsItem?> onSelect;
  final ValueChanged<NewsItem> onOpenArticle;
  final VoidCallback onRefresh;

  List<NewsItem> get _rows {
    final ids = {for (final n in urgent) n.id};
    return [...urgent, ...items.where((n) => !ids.contains(n.id))];
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final rows = _rows;
    NewsItem? selected = rows.where((n) => n.id == selectedId).firstOrNull;
    if (selected == null && selectedId != null) {
      final link = links.where((l) => l.url == selectedId).firstOrNull;
      if (link != null) {
        selected = NewsItem(
          id: link.url,
          source: link.name,
          title: link.name,
          url: link.url,
          publishedAt: DateTime.now(),
          category: 'OFFICIAL',
          impact: 'LOW',
          summary: link.about,
        );
      }
    }
    final rateEntries = <MapEntry<String, double>>[
      for (final c in const ['USD', 'CNY', 'AED', 'EUR'])
        if (rates?.rates[c] != null) MapEntry(c, rates!.rates[c]!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: title,
          subtitle: 'What is happening that can touch a trader’s money',
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: DesktopInspectorLayout(
            inspectorWidth: 400,
            onClose: () => onSelect(null),
            inspector: selected == null
                ? null
                : _ArticleInspector(
                    item: selected,
                    onClose: () => onSelect(null),
                    onOpen: () => onOpenArticle(selected!),
                  ),
            main: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rateEntries.isNotEmpty)
                  _RatesLine(entries: rateEntries, board: rates!),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      DesktopFilterChip(
                        label: 'Everything',
                        selected: category == null,
                        onTap: () => onCategory(null),
                      ),
                      for (final e in newsCategories.entries)
                        DesktopFilterChip(
                          label: e.value,
                          selected: category == e.key,
                          onTap: () => onCategory(e.key),
                        ),
                    ],
                  ),
                ),
                if (error != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                    decoration: BoxDecoration(
                      color: DesignColors.warning
                          .withValues(alpha: p.dark ? 0.16 : 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            error!,
                            style: GoogleFonts.plusJakartaSans(
                              color: p.text,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (onRetry != null)
                          TextButton(
                            style: desktopLinkButton(context),
                            onPressed: onRetry,
                            child: const Text('Try again'),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: DesktopDataTable<NewsItem>(
                    rows: rows,
                    rowId: (n) => n.id,
                    selectedId: selectedId,
                    onRowSelected: onSelect,
                    loading: loading,
                    minWidth: 560,
                    columns: [
                      DesktopColumn<NewsItem>(
                        label: 'Topic',
                        width: 172,
                        cell: (_, n) => Align(
                          alignment: Alignment.centerLeft,
                          child: DesktopStatusChip(
                            label: n.isUrgent ? 'Urgent' : n.categoryLabel,
                            color: n.isUrgent ? DesignColors.error : p.textMuted,
                          ),
                        ),
                      ),
                      DesktopColumn<NewsItem>(
                        label: 'Headline',
                        flex: 5,
                        minWidth: 220,
                        cell: (_, n) => DesktopCellText(n.title, strong: true),
                      ),
                      DesktopColumn<NewsItem>(
                        label: 'Source',
                        flex: 2,
                        minWidth: 90,
                        cell: (_, n) => DesktopCellText(n.source, muted: true),
                      ),
                      DesktopColumn<NewsItem>(
                        label: 'When',
                        width: 110,
                        sortBy: (n) => n.publishedAt.millisecondsSinceEpoch,
                        cell: (_, n) => DesktopCellText(
                          timeAgo(n.publishedAt),
                          muted: true,
                        ),
                      ),
                    ],
                    empty: const SingleChildScrollView(
                      child: DesktopEmptyState(
                        icon: Icons.newspaper_rounded,
                        title: 'No news here yet',
                        message:
                            'Headlines that can affect your business show up here as they are published.',
                      ),
                    ),
                    footer: links.isEmpty
                        ? null
                        : _OfficialSources(links: links, onSelect: (l) {
                            onSelect(NewsItem(
                              id: l.url,
                              source: l.name,
                              title: l.name,
                              url: l.url,
                              publishedAt: DateTime.now(),
                              category: 'OFFICIAL',
                              impact: 'LOW',
                              summary: l.about,
                            ));
                          }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The shilling against the dollar, yuan, dirham and euro, on one line.
class _RatesLine extends StatelessWidget {
  const _RatesLine({required this.entries, required this.board});

  final List<MapEntry<String, double>> entries;
  final RateBoard board;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Wrap(
        spacing: 22,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.currency_exchange_rounded, size: 16, color: p.textMuted),
              const SizedBox(width: 6),
              Text(
                'KES for 1',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          for (final e in entries)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.key,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  e.value.toStringAsFixed(e.value < 50 ? 2 : 1),
                  style: DesignType.numeric(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                ),
              ],
            ),
          if (board.updatedAt != null)
            Text(
              board.stale ? 'old rates' : 'updated ${timeAgo(board.updatedAt!)}',
              style: GoogleFonts.plusJakartaSans(
                color: board.stale ? DesignColors.warning : p.textFaint,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

/// A one-line strip under the table: the official sources to check before
/// acting on a headline.
class _OfficialSources extends StatelessWidget {
  const _OfficialSources({required this.links, required this.onSelect});

  final List<OfficialLink> links;
  final ValueChanged<OfficialLink> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Check the official source:',
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final l in links)
            TextButton(
              style: desktopLinkButton(context),
              onPressed: () => onSelect(l),
              child: Text(l.name),
            ),
        ],
      ),
    );
  }
}

class _ArticleInspector extends StatelessWidget {
  const _ArticleInspector({
    required this.item,
    required this.onClose,
    required this.onOpen,
  });

  final NewsItem item;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final official = item.category == 'OFFICIAL';
    return DesktopInspector(
      title: item.title,
      subtitle: official ? 'Official source' : '${item.source}, ${timeAgo(item.publishedAt)}',
      onClose: onClose,
      footer: FilledButton.icon(
        style: desktopPrimaryButton(context),
        onPressed: onOpen,
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: Text(official ? 'Open the website' : 'Read the original article'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!official)
            DesktopStatusChip(
              label: item.isUrgent ? 'Urgent' : item.categoryLabel,
              color: item.isUrgent ? DesignColors.error : p.textMuted,
            ),
          if (!official) const SizedBox(height: 14),
          if ((item.summary ?? '').isNotEmpty)
            SelectableText(
              item.summary!,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 14,
                height: 1.55,
              ),
            )
          else
            Text(
              'No summary was published with this headline.',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 13.5,
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Headlines link to the original story. We do not copy full articles.',
            style: GoogleFonts.plusJakartaSans(
              color: p.textFaint,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
