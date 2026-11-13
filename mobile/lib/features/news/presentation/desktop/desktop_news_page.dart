import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../domain/news_models.dart';
import '../providers/news_provider.dart';
import 'desktop_news_view.dart';

/// The routed Business News page inside the desktop shell. Same providers as
/// the phone page; the topic and the open headline are kept locally.
class DesktopNewsPage extends ConsumerStatefulWidget {
  const DesktopNewsPage({super.key});

  @override
  ConsumerState<DesktopNewsPage> createState() => _DesktopNewsPageState();
}

class _DesktopNewsPageState extends ConsumerState<DesktopNewsPage> {
  String? _category;
  String? _selected;

  void _refresh() {
    ref.invalidate(newsDigestProvider);
    ref.invalidate(exchangeRatesProvider);
    ref.invalidate(newsListProvider(_category));
    ref.invalidate(officialLinksProvider);
  }

  Future<void> _open(NewsItem item) async {
    final uri = Uri.tryParse(item.url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      showGlassSnackBar(context, 'This article link is invalid.',
          icon: Icons.link_off_rounded, color: DesignColors.warning);
      return;
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) {
      showGlassSnackBar(context, 'Could not open the browser. Try again.',
          icon: Icons.link_off_rounded, color: DesignColors.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digest = ref.watch(newsDigestProvider);
    final list = ref.watch(newsListProvider(_category));
    final links = ref.watch(officialLinksProvider);
    final rates = ref.watch(exchangeRatesProvider);

    return Scaffold(
      body: DesktopNewsView(
        title: ref
            .watch(businessLayoutProvider)
            .actionLabel('/news', 'Business news'),
        items: list.valueOrNull ?? const [],
        urgent: _category == null
            ? (digest.valueOrNull?.urgent ?? const [])
            : const [],
        loading: list.isLoading && !list.hasValue,
        error: list.hasError ? apiErrorMessage(list.error!) : null,
        onRetry: () => ref.invalidate(newsListProvider(_category)),
        rates: rates.valueOrNull,
        links: links.valueOrNull ?? const [],
        category: _category,
        onCategory: (c) => setState(() {
          _category = c;
          _selected = null;
        }),
        selectedId: _selected,
        onSelect: (n) => setState(() => _selected = n?.id),
        onOpenArticle: _open,
        onRefresh: _refresh,
      ),
    );
  }
}
