import 'dart:collection';

import 'package:flutter/material.dart';

import '../../core/widgets/widgets.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';

typedef PageFetcher<T> = Future<Paged<T>> Function(int page);

/// Drives an infinite-scroll list over a [Paged] endpoint.
///
/// * [refresh] reloads page 1 (optionally clearing what is on screen first).
/// * [loadMore] appends the next page; a failure is remembered in [moreError]
///   and is not retried automatically (use [retryMore]).
/// * A response that arrives after a newer [refresh] started is discarded, so
///   changing a filter quickly can never show results for the old filter.
/// * [idOf] (optional) drops rows already on screen, which happens when new
///   rows are inserted at the top while the user is paging.
class PagedController<T> extends ChangeNotifier {
  PagedController({required this.fetch, this.idOf});

  final PageFetcher<T> fetch;
  final Object? Function(T item)? idOf;

  final List<T> _items = <T>[];
  late final UnmodifiableListView<T> items = UnmodifiableListView<T>(_items);

  int _total = 0;
  int _nextPage = 1;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loadedOnce = false;
  Object? _error;
  Object? _moreError;
  int _generation = 0;
  bool _disposed = false;

  /// Total rows the server reports for the current filter.
  int get total => _total;
  bool get hasMore => _hasMore;

  /// True while page 1 is loading (first load, filter change or refresh).
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get loadedOnce => _loadedOnce;

  /// Error from the last page-1 load (cleared when a new load starts).
  Object? get error => _error;

  /// Error from the last "load more" attempt.
  Object? get moreError => _moreError;

  /// Nothing to show yet and the first page is on its way.
  bool get isInitialLoading => _items.isEmpty && (_loading || (!_loadedOnce && _error == null));

  Future<void> refresh({bool clear = false}) async {
    final gen = ++_generation;
    if (clear) {
      _items.clear();
      _total = 0;
      _nextPage = 1;
      _hasMore = false;
      _loadedOnce = false;
    }
    _loading = true;
    _loadingMore = false;
    _error = null;
    _moreError = null;
    _notify();
    try {
      final page = await fetch(1);
      if (_stale(gen)) return;
      _items
        ..clear()
        ..addAll(_unique(page.items));
      _total = page.total;
      _nextPage = 2;
      _hasMore = _more(page);
      _loadedOnce = true;
    } catch (e) {
      if (_stale(gen)) return;
      _error = e;
    }
    _loading = false;
    _notify();
  }

  Future<void> loadMore() async {
    if (!_hasMore || _loading || _loadingMore || _moreError != null) return;
    final gen = _generation;
    _loadingMore = true;
    _notify();
    try {
      final page = await fetch(_nextPage);
      if (_stale(gen)) return;
      _items.addAll(_unique(page.items));
      _total = page.total;
      _nextPage += 1;
      _hasMore = _more(page);
    } catch (e) {
      if (_stale(gen)) return;
      _moreError = e;
    }
    _loadingMore = false;
    _notify();
  }

  Future<void> retryMore() {
    _moreError = null;
    return loadMore();
  }

  bool _more(Paged<T> page) => page.items.isNotEmpty && page.hasMore;

  bool _stale(int gen) => _disposed || gen != _generation;

  List<T> _unique(List<T> incoming) {
    final id = idOf;
    if (id == null) return incoming;
    final seen = <Object?>{for (final i in _items) id(i)};
    return [
      for (final i in incoming)
        if (seen.add(id(i))) i,
    ];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The scrolling body for a [PagedController]: skeleton on first load, error
/// with retry, empty state, then the list with a footer spinner / retry row.
/// Pull-to-refresh is built in. Rebuilds itself when the controller changes;
/// the parent supplies [itemCount]/[itemBuilder], so rebuild the parent too
/// (e.g. wrap in a [ListenableBuilder]) when row content depends on items.
class PagedListBody extends StatefulWidget {
  const PagedListBody({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.emptyState,
    this.skeleton,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 24),
  });

  final PagedController<dynamic> controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget emptyState;
  final Widget? skeleton;
  final EdgeInsetsGeometry padding;

  @override
  State<PagedListBody> createState() => _PagedListBodyState();
}

class _PagedListBodyState extends State<PagedListBody> {
  final ScrollController _scroll = ScrollController();

  PagedController<dynamic> get _c => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await _c.refresh();
    if (!mounted) return;
    if (_c.error != null && _c.items.isNotEmpty) {
      final e = _c.error!;
      toast(context, e is ApiException ? e.message : 'Refresh failed. Try again.', error: true);
    }
  }

  /// When the rows do not fill the screen there is nothing to scroll, so no
  /// scroll notification would ever ask for the next page.
  void _fillCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.extentAfter < 600) _c.loadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        if (_c.isInitialLoading) return widget.skeleton ?? const ListSkeleton();
        if (_c.items.isEmpty && _c.error != null) {
          return ErrorState(error: _c.error!, onRetry: () => _c.refresh(clear: true));
        }
        if (_c.items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: LayoutBuilder(
              builder: (_, box) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(height: box.maxHeight, child: widget.emptyState),
              ),
            ),
          );
        }
        _fillCheck();
        return RefreshIndicator(
          onRefresh: _onRefresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600) _c.loadMore();
              return false;
            },
            child: ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: widget.padding,
              itemCount: widget.itemCount + 1,
              itemBuilder: (context, i) => i < widget.itemCount ? widget.itemBuilder(context, i) : _footer(context),
            ),
          ),
        );
      },
    );
  }

  Widget _footer(BuildContext context) {
    final p = Theme.of(context).textTheme;
    if (_c.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))),
      );
    }
    if (_c.moreError != null) {
      final e = _c.moreError!;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(
              e is ApiException ? e.message : 'Couldn\'t load more.',
              textAlign: TextAlign.center,
              style: p.bodySmall,
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: _c.retryMore, child: const Text('Try again')),
          ],
        ),
      );
    }
    return SizedBox(height: _c.hasMore ? 56 : 8);
  }
}
