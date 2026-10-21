import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'tenant_changes.dart';
import 'tenant_detail_screen.dart';
import 'tenants_logic.dart';

/// Clients tab: every company on Counterbase, searchable, filterable by
/// subscription status, loaded 20 at a time.
class TenantsScreen extends StatefulWidget {
  const TenantsScreen({super.key, this.initialStatus});

  /// When pushed from the Overview, pre-selects a status filter (ACTIVE, TRIAL, PAST_DUE, SUSPENDED, CANCELLED).
  final String? initialStatus;

  @override
  State<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends State<TenantsScreen> {
  static const _pageSize = 20;
  static const _debounceFor = Duration(milliseconds: 400);
  static const _refreshPageCap = 5;

  final _searchCtl = TextEditingController();
  final _scroll = ScrollController();
  final _chipKeys = List<GlobalKey>.generate(kStatusFilters.length, (_) => GlobalKey());
  Timer? _debounce;

  String? _status;
  String _query = '';

  /// Bumped on every new query so a slow, outdated response is ignored.
  int _epoch = 0;

  List<TenantSummary> _items = [];
  int _total = 0;
  int _page = 0;
  bool _hasMore = false;
  bool _loadingFirst = true;
  bool _loadingMore = false;
  Object? _error;
  Object? _moreError;

  AcaRepository get _repo => context.read<AcaRepository>();
  bool get _filtered => _query.isNotEmpty || _status != null;

  @override
  void initState() {
    super.initState();
    _status = normalizeStatus(widget.initialStatus);
    _scroll.addListener(_maybeLoadMore);
    tenantChanges.addListener(_onTenantChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedChip());
    _loadFirst();
  }

  @override
  void dispose() {
    tenantChanges.removeListener(_onTenantChanged);
    _debounce?.cancel();
    _searchCtl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ loading

  Future<void> _loadFirst() async {
    final epoch = ++_epoch;
    setState(() {
      _loadingFirst = true;
      _loadingMore = false;
      _error = null;
      _moreError = null;
      _items = [];
      _hasMore = false;
    });
    try {
      final r = await _repo.tenants(
        search: _query.isEmpty ? null : _query,
        status: _status,
        page: 1,
        pageSize: _pageSize,
      );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _items = r.items;
        _total = r.total;
        _page = r.page;
        _hasMore = r.hasMore;
        _loadingFirst = false;
      });
      _afterFrame(_maybeLoadMore);
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _error = e;
        _loadingFirst = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loadingFirst || !_hasMore) return;
    final epoch = _epoch;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final r = await _repo.tenants(
        search: _query.isEmpty ? null : _query,
        status: _status,
        page: _page + 1,
        pageSize: _pageSize,
      );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _items = mergePage(_items, r.items, (t) => t.id);
        _total = r.total;
        _page = r.page;
        _hasMore = r.hasMore;
        _loadingMore = false;
      });
      _afterFrame(_maybeLoadMore);
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _loadingMore = false;
        _moreError = e;
      });
    }
  }

  /// Pull-to-refresh and "something changed": re-reads the pages already on
  /// screen (up to a few) so the list keeps its length and scroll position.
  Future<void> _refreshInPlace() async {
    if (_loadingFirst) return;
    final epoch = _epoch;
    final upTo = _page.clamp(1, _refreshPageCap);
    try {
      var merged = <TenantSummary>[];
      Paged<TenantSummary>? last;
      for (var p = 1; p <= upTo; p++) {
        final r = await _repo.tenants(
          search: _query.isEmpty ? null : _query,
          status: _status,
          page: p,
          pageSize: _pageSize,
        );
        merged = mergePage(merged, r.items, (t) => t.id);
        last = r;
        if (!r.hasMore) break;
      }
      final l = last;
      if (!mounted || epoch != _epoch || l == null) return;
      setState(() {
        _items = merged;
        _total = l.total;
        _page = l.page;
        _hasMore = l.hasMore;
        _error = null;
        _moreError = null;
      });
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      toast(context, e is ApiException ? e.message : 'Refresh failed', error: true);
    }
  }

  void _onTenantChanged() {
    if (mounted && !_loadingFirst && _error == null) _refreshInPlace();
  }

  void _maybeLoadMore() {
    if (!mounted || !_scroll.hasClients || !_hasMore || _loadingMore || _loadingFirst || _moreError != null) return;
    if (_scroll.position.extentAfter < 600) _loadMore();
  }

  void _afterFrame(VoidCallback fn) => WidgetsBinding.instance.addPostFrameCallback((_) => fn());

  // ------------------------------------------------------------ user actions

  void _onSearchChanged(String text) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(_debounceFor, () => _applySearch(text));
  }

  void _applySearch(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q == _query) return;
    _query = q;
    _jumpToTop();
    _loadFirst();
  }

  void _selectStatus(String? status) {
    if (status == _status) return;
    _status = status;
    _jumpToTop();
    _loadFirst();
    _revealSelectedChip();
  }

  void _clearAll() {
    _debounce?.cancel();
    _searchCtl.clear();
    _query = '';
    _status = null;
    _loadFirst();
    _revealSelectedChip();
  }

  void _jumpToTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _revealSelectedChip() {
    final ctx = _chipKeys[statusFilterIndex(_status)].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 200), alignment: 0.5);
    }
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Scaffold(
      appBar: AppBar(title: const Text('Clients')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtl,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: _applySearch,
              decoration: InputDecoration(
                hintText: 'Search company or staff email',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchCtl.clear();
                          _applySearch('');
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: kStatusFilters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = kStatusFilters[i];
                return Center(
                  key: _chipKeys[i],
                  child: ChoiceChip(
                    label: Text(f.label),
                    selected: f.value == _status,
                    showCheckmark: false,
                    onSelected: (_) => _selectStatus(f.value),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _loadingFirst || _error != null ? ' ' : companyCountLabel(_total, filtered: _filtered),
                style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loadingFirst) return const ListSkeleton(rows: 6, rowHeight: 112);
    if (_error != null) return ErrorState(error: _error!, onRetry: _loadFirst);
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshInPlace,
        child: LayoutBuilder(
          builder: (_, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: c.maxHeight,
              child: _filtered
                  ? EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No companies match',
                      message: _query.isNotEmpty
                          ? 'Nothing matches “$_query”${_status == null ? '' : ' with the ${statusFilterLabel(_status).toLowerCase()} filter'}. Check the spelling or try a shorter name.'
                          : 'No company is ${statusFilterLabel(_status).toLowerCase()} right now.',
                      action: 'Clear search and filters',
                      onAction: _clearAll,
                    )
                  : const EmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'No companies yet',
                      message: 'Companies show up here as soon as they sign up for Counterbase.',
                    ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshInPlace,
      child: ListView.builder(
        key: const ValueKey('tenants-list'),
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i == _items.length) return _footer(context);
          final t = _items[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TenantCard(
              tenant: t,
              onTap: () => openTenant(context, id: t.id, name: t.name),
            ),
          );
        },
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final p = context.aca;
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
      );
    }
    if (_moreError != null) {
      final msg = _moreError is ApiException ? (_moreError as ApiException).message : _moreError.toString();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AcaCard(
          tone: Tone.danger,
          child: Column(
            children: [
              Text('Couldn\'t load more companies', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(msg, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 13)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(160, 44)),
                onPressed: _loadMore,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_hasMore && _items.length > _pageSize) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(child: Text('That\'s every company', style: TextStyle(color: p.textFaint, fontSize: 12.5))),
      );
    }
    return const SizedBox(height: 4);
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.tenant, required this.onTap});

  final TenantSummary tenant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final t = tenant;
    final locked = !t.isActive;
    final statusTone = StatusTone.subscription(t.subscriptionStatus);
    final end = endTone(t.currentPeriodEnd);
    final endColor = end == Tone.neutral ? p.textMuted : p.toneColor(end);

    return AcaCard(
      onTap: onTap,
      tone: locked ? Tone.danger : null,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(t.name, size: 44, tone: locked ? Tone.danger : (statusTone == Tone.neutral ? Tone.brand : statusTone)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (locked) const StatusPill('Locked out', tone: Tone.danger, icon: Icons.lock_rounded, dense: true),
                    if (!planRepeatsStatus(t.plan, t.subscriptionStatus)) StatusPill(Fmt.label(t.plan), tone: Tone.brand, dense: true),
                    StatusPill(Fmt.label(t.subscriptionStatus), tone: statusTone, dense: true),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: endColor),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        Fmt.daysUntil(t.currentPeriodEnd),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: endColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    _Count(icon: Icons.people_outline_rounded, text: plural(t.userCount, 'user')),
                    _Count(icon: Icons.storefront_outlined, text: plural(t.branchCount, 'branch', 'branches')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(Icons.chevron_right_rounded, color: p.textFaint),
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: p.textFaint),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12.5, color: p.textMuted)),
      ],
    );
  }
}
