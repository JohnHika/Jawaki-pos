import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../domain/news_models.dart';
import '../providers/news_provider.dart';

/// What is happening in the country that can touch a trader's money: customs
/// and tax changes, import rules, the dollar, county notices, fuel prices.
class BusinessNewsScreen extends ConsumerStatefulWidget {
  const BusinessNewsScreen({super.key});

  @override
  ConsumerState<BusinessNewsScreen> createState() => _BusinessNewsScreenState();
}

class _BusinessNewsScreenState extends ConsumerState<BusinessNewsScreen> {
  String? _category;

  Future<void> _refresh() async {
    ref.invalidate(newsDigestProvider);
    ref.invalidate(exchangeRatesProvider);
    ref.invalidate(newsListProvider(_category));
    ref.invalidate(officialLinksProvider);
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showGlassSnackBar(context, "Couldn't open that link.",
          icon: Icons.link_off_rounded, color: DesignColors.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final digest = ref.watch(newsDigestProvider);
    final list = ref.watch(newsListProvider(_category));
    final links = ref.watch(officialLinksProvider);

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Business News',
        showBackButton: GoRouter.of(context).canPop(),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, 120),
          children: [
            const _RatesStrip(),
            const SizedBox(height: DesignSpacing.lg),
            ...digest.maybeWhen(
              data: (d) => d.urgent.isEmpty
                  ? const <Widget>[]
                  : [
                      const SectionHeader(
                        title: 'Needs your attention',
                        subtitle: 'This week',
                        icon: Icons.priority_high_rounded,
                      ),
                      const SizedBox(height: DesignSpacing.sm),
                      for (final n in d.urgent)
                        _NewsTile(item: n, onTap: () => _open(n.url), urgent: true),
                      const SizedBox(height: DesignSpacing.lg),
                    ],
              orElse: () => const <Widget>[],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoicePill(
                    label: 'Everything',
                    selected: _category == null,
                    onTap: () => setState(() => _category = null),
                  ),
                  for (final e in newsCategories.entries) ...[
                    const SizedBox(width: DesignSpacing.sm),
                    ChoicePill(
                      label: e.value,
                      selected: _category == e.key,
                      onTap: () => setState(() => _category = e.key),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: DesignSpacing.md),
            list.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(DesignSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => InlineRetryNotice(
                message: apiErrorMessage(e),
                onRetry: () => ref.invalidate(newsListProvider(_category)),
              ),
              data: (items) => items.isEmpty
                  ? const EmptyState(
                      icon: Icons.newspaper_rounded,
                      title: 'No news here yet',
                      subtitle:
                          'Headlines that can affect your business show up here as they are published.',
                    )
                  : Column(
                      children: [
                        for (final n in items)
                          _NewsTile(item: n, onTap: () => _open(n.url)),
                      ],
                    ),
            ),
            const SizedBox(height: DesignSpacing.xl),
            links.maybeWhen(
              data: (rows) => rows.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(
                          title: 'Check the official source',
                          subtitle: 'Before you act on any headline',
                          icon: Icons.verified_outlined,
                        ),
                        const SizedBox(height: DesignSpacing.sm),
                        for (final l in rows)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: DesignSpacing.sm),
                            child: ListCard(
                              leading: const Icon(Icons.open_in_new_rounded),
                              title: l.name,
                              subtitle: l.about,
                              onTap: () => _open(l.url),
                            ),
                          ),
                        Text(
                          'Headlines come from Kenyan news sites and link to the original. We do not copy full stories.',
                          style: TextStyle(color: secondary, fontSize: 12),
                        ),
                      ],
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatesStrip extends ConsumerWidget {
  const _RatesStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(exchangeRatesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return board.maybeWhen(
      data: (b) {
        const show = ['USD', 'CNY', 'AED', 'EUR'];
        final entries = [
          for (final c in show)
            if (b.rates[c] != null) MapEntry(c, b.rates[c]!),
        ];
        if (entries.isEmpty) return const SizedBox.shrink();
        return GlassCard(
          padding: const EdgeInsets.all(DesignSpacing.md),
          borderRadius: DesignSpacing.radiusLg,
          blur: 8,
          tint: DesignColors.accent.withValues(alpha: 0.06),
          borderColor: DesignColors.accent.withValues(alpha: 0.15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.currency_exchange_rounded,
                      size: 18, color: DesignColors.accent),
                  const SizedBox(width: DesignSpacing.sm),
                  const Text('Shilling today',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (b.updatedAt != null)
                    Text(b.stale ? 'old rates' : timeAgo(b.updatedAt!),
                        style: TextStyle(
                            color: b.stale ? DesignColors.warning : secondary,
                            fontSize: 12)),
                ],
              ),
              const SizedBox(height: DesignSpacing.sm),
              Row(
                children: [
                  for (final e in entries)
                    Expanded(
                      child: Column(
                        children: [
                          Text(e.key,
                              style: TextStyle(color: secondary, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(e.value.toStringAsFixed(e.value < 50 ? 2 : 1),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 17)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: DesignSpacing.sm),
              Text('KES for 1 unit. ${b.disclaimer}',
                  style: TextStyle(color: secondary, fontSize: 11)),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _NewsTile extends StatelessWidget {
  const _NewsTile({required this.item, required this.onTap, this.urgent = false});

  final NewsItem item;
  final VoidCallback onTap;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final accent = urgent ? DesignColors.error : DesignColors.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: Material(
        color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(DesignSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              border: Border.all(
                color: urgent
                    ? accent.withValues(alpha: 0.5)
                    : (isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(label: item.categoryLabel, color: accent),
                    const SizedBox(width: DesignSpacing.sm),
                    Expanded(
                      child: Text(
                        '${item.source} · ${timeAgo(item.publishedAt)}',
                        style: TextStyle(color: secondary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.open_in_new_rounded, size: 16, color: secondary),
                  ],
                ),
                const SizedBox(height: 6),
                Text(item.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15, height: 1.3)),
                if ((item.summary ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.summary!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondary, height: 1.35)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
