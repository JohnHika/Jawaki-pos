import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../domain/news_models.dart';

/// Opens publisher pages inside Counterbase so reading an article does not
/// switch the cashier into a separate browser app or custom tab.
class BusinessNewsArticleScreen extends StatefulWidget {
  const BusinessNewsArticleScreen({
    super.key,
    required this.item,
    this.showPublishedAt = true,
  });

  final NewsItem item;
  final bool showPublishedAt;

  @override
  State<BusinessNewsArticleScreen> createState() =>
      _BusinessNewsArticleScreenState();
}

class _BusinessNewsArticleScreenState extends State<BusinessNewsArticleScreen> {
  WebViewController? _controller;
  int _progress = 0;
  bool _isLoading = true;
  bool _canGoBack = false;
  String? _loadError;

  bool get _supportsEmbeddedView =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.macOS =>
          true,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    if (!_supportsEmbeddedView) return;

    final uri = Uri.tryParse(widget.item.url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _loadError = 'This article link is invalid.';
      _isLoading = false;
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _loadError = null;
              _progress = 0;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _progress = 100;
            });
            unawaited(_refreshBackState());
          },
          onWebResourceError: (error) {
            // Images and ad resources often fail independently of the article.
            // Only replace the page with an error state when the main document
            // itself failed to load.
            if (error.isForMainFrame == false || !mounted) return;
            setState(() {
              _isLoading = false;
              _loadError =
                  'The publisher page could not load. Check your connection and try again.';
            });
          },
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            if (target == null ||
                target.host.isEmpty ||
                target.scheme.toLowerCase() != 'https') {
              // Keep mailto:, tel:, intent:, file:, and other external schemes
              // from launching another app or opening local resources.
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(uri);
  }

  Future<void> _refreshBackState() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final canGoBack = await controller.canGoBack();
      if (mounted && canGoBack != _canGoBack) {
        setState(() => _canGoBack = canGoBack);
      }
    } catch (_) {
      // Navigation history can be unavailable while a WebView is shutting down.
    }
  }

  Future<void> _goBackInArticle() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      if (await controller.canGoBack()) {
        await controller.goBack();
      }
    } catch (_) {
      // Keep the app route usable if the embedded page loses its history.
    }
    await _refreshBackState();
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _loadError = null;
      _isLoading = true;
      _progress = 0;
    });
    try {
      await controller.reload();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError =
            'The publisher page could not load. Check your connection and try again.';
      });
    }
  }

  Future<void> _share() => Share.share(
        '${widget.item.title}\n${widget.item.url}',
        subject: widget.item.title,
      );

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return PopScope<Object?>(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _canGoBack) unawaited(_goBackInArticle());
      },
      child: Scaffold(
        appBar: BrandedAppBar(
          title: 'Article',
          actions: [
            IconButton(
              tooltip: 'Reload article',
              onPressed: controller == null ? null : _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Share article',
              onPressed: _share,
              icon: const Icon(Icons.share_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            _ArticleHeader(
              item: widget.item,
              secondary: secondary,
              showPublishedAt: widget.showPublishedAt,
            ),
            if (_isLoading && controller != null)
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress / 100,
                minHeight: 2,
                color: DesignColors.accent,
                backgroundColor: DesignColors.accent.withValues(alpha: 0.12),
              ),
            Expanded(
              child: controller == null
                  ? _UnsupportedArticleView(item: widget.item)
                  : Stack(
                      children: [
                        WebViewWidget(controller: controller),
                        if (_loadError != null)
                          Positioned.fill(
                            child: _ArticleLoadError(
                              message: _loadError!,
                              onRetry: _reload,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleHeader extends StatelessWidget {
  const _ArticleHeader({
    required this.item,
    required this.secondary,
    required this.showPublishedAt,
  });

  final NewsItem item;
  final Color secondary;
  final bool showPublishedAt;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        DesignSpacing.md,
        DesignSpacing.md,
        DesignSpacing.md,
        DesignSpacing.sm,
      ),
      padding: const EdgeInsets.all(DesignSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(
          color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.article_outlined,
                  size: 17, color: DesignColors.accent),
              const SizedBox(width: DesignSpacing.sm),
              Expanded(
                child: Text(
                  item.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (showPublishedAt)
                Text(
                  timeAgo(item.publishedAt),
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: DesignSpacing.sm),
          Text(
            item.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.2,
                ),
          ),
          if ((item.summary ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: DesignSpacing.xs),
            Text(
              item.summary!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondary, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArticleLoadError extends StatelessWidget {
  const _ArticleLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignSpacing.xl),
          child: GlassCard(
            padding: const EdgeInsets.all(DesignSpacing.xl),
            borderRadius: DesignSpacing.radiusLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded,
                    size: 34, color: DesignColors.warning),
                const SizedBox(height: DesignSpacing.md),
                Text(
                  'Article unavailable',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: DesignSpacing.xs),
                Text(message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: DesignSpacing.lg),
                SettingsPrimaryButton(
                  label: 'Try again',
                  onPressed: onRetry,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnsupportedArticleView extends StatelessWidget {
  const _UnsupportedArticleView({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignSpacing.xl),
        child: GlassCard(
          padding: const EdgeInsets.all(DesignSpacing.xl),
          borderRadius: DesignSpacing.radiusLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.article_outlined,
                  size: 34, color: DesignColors.accent),
              const SizedBox(height: DesignSpacing.md),
              Text(
                'Article preview',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if ((item.summary ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: DesignSpacing.sm),
                Text(item.summary!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: DesignSpacing.sm),
              Text(
                'The full article reader is available in Counterbase on mobile.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
