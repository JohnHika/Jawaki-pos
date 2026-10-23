import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/stocktake_models.dart';
import '../providers/stocktake_provider.dart';

/// One stock count: counting it, handing it in, and (for a manager) reviewing
/// the gaps and approving the stock changes.
class StockCountScreen extends ConsumerWidget {
  const StockCountScreen({super.key, required this.countId});

  final String countId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(stockCountProvider(countId));
    return Scaffold(
      appBar: BrandedAppBar(
        title: detail.valueOrNull?.displayTitle ?? 'Stock count',
        showBackButton: true,
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(DesignSpacing.lg),
          child: InlineRetryNotice(
            message: apiErrorMessage(e),
            onRetry: () => ref.invalidate(stockCountProvider(countId)),
          ),
        ),
        data: (d) => d.inProgress
            ? _CountingView(detail: d)
            : _ReviewView(detail: d),
      ),
    );
  }
}

// ----------------------------------------------------------------- counting

class _CountingView extends ConsumerStatefulWidget {
  const _CountingView({required this.detail});

  final StockCountDetail detail;

  @override
  ConsumerState<_CountingView> createState() => _CountingViewState();
}

enum _Show { toCount, counted, all }

class _CountingViewState extends ConsumerState<_CountingView> {
  final _search = TextEditingController();
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _dirty = {};
  _Show _show = _Show.toCount;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final line in widget.detail.items) {
      _controllers[line.productId] = TextEditingController(
        text: line.countedQty == null ? '' : kitNumber(line.countedQty!),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isCounted(StockCountLine l) =>
      (_controllers[l.productId]?.text.trim().isNotEmpty ?? false);

  int get _countedNow =>
      widget.detail.items.where(_isCounted).length;

  List<StockCountLine> _visible() {
    final q = _search.text.trim().toLowerCase();
    return widget.detail.items.where((l) {
      if (q.isNotEmpty &&
          !l.productName.toLowerCase().contains(q) &&
          !(l.sku ?? '').toLowerCase().contains(q)) {
        return false;
      }
      return switch (_show) {
        _Show.toCount => !_isCounted(l),
        _Show.counted => _isCounted(l),
        _Show.all => true,
      };
    }).toList();
  }

  Future<bool> _saveProgress({bool quiet = false}) async {
    if (_dirty.isEmpty) return true;
    final entries = <Map<String, dynamic>>[];
    for (final id in _dirty) {
      final text = _controllers[id]?.text.trim() ?? '';
      final qty = double.tryParse(text);
      if (qty == null) continue;
      entries.add({'productId': id, 'countedQty': qty});
    }
    if (entries.isEmpty) return true;
    try {
      // Sent in slices so a long count never exceeds the request limit.
      for (var i = 0; i < entries.length; i += 400) {
        await getIt<ApiClient>().recordStockCounts(
          widget.detail.id,
          entries.sublist(i, i + 400 > entries.length ? entries.length : i + 400),
        );
      }
      _dirty.clear();
      if (!quiet && mounted) {
        showGlassSnackBar(context, 'Progress saved',
            icon: Icons.check_circle_rounded, color: DesignColors.success);
      }
      return true;
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, apiErrorMessage(e),
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
      return false;
    }
  }

  Future<void> _handIn() async {
    final left = widget.detail.totalLines - _countedNow;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hand in this count?'),
        content: Text(left > 0
            ? '$left item${left == 1 ? '' : 's'} not counted will be left as they are in the system. A manager reviews the count before any stock changes.'
            : 'A manager reviews the count before any stock changes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep counting')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hand in')),
        ],
      ),
    );
    if (go != true) return;
    setState(() => _busy = true);
    try {
      if (!await _saveProgress(quiet: true)) return;
      await getIt<ApiClient>().submitStockCount(widget.detail.id);
      ref.invalidate(stockCountProvider(widget.detail.id));
      ref.invalidate(stockCountsProvider);
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, apiErrorMessage(e),
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final lines = _visible();
    final total = widget.detail.totalLines;
    final counted = _countedNow;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, 0),
          child: Column(
            children: [
              if (widget.detail.expectedHidden)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(DesignSpacing.md),
                  margin: const EdgeInsets.only(bottom: DesignSpacing.md),
                  decoration: BoxDecoration(
                    color: DesignColors.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.visibility_off_outlined,
                          size: 18, color: DesignColors.info),
                      SizedBox(width: DesignSpacing.sm),
                      Expanded(
                        child: Text(
                            'System quantities are hidden. Count what is really on the shelf.'),
                      ),
                    ],
                  ),
                ),
              LinearProgressIndicator(
                value: total == 0 ? 0 : counted / total,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: DesignColors.accent,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('$counted of $total counted',
                    style: TextStyle(color: secondary, fontSize: 12)),
              ),
              const SizedBox(height: DesignSpacing.sm),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: kitFieldDecoration(context,
                    label: 'Find an item',
                    hint: 'Name or SKU',
                    prefixIcon: Icons.search_rounded),
              ),
              const SizedBox(height: DesignSpacing.sm),
              Row(
                children: [
                  ChoicePill(
                      label: 'To count',
                      selected: _show == _Show.toCount,
                      onTap: () => setState(() => _show = _Show.toCount)),
                  const SizedBox(width: DesignSpacing.sm),
                  ChoicePill(
                      label: 'Counted',
                      selected: _show == _Show.counted,
                      onTap: () => setState(() => _show = _Show.counted)),
                  const SizedBox(width: DesignSpacing.sm),
                  ChoicePill(
                      label: 'All',
                      selected: _show == _Show.all,
                      onTap: () => setState(() => _show = _Show.all)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? Center(
                  child: Text(
                    _show == _Show.toCount && total > 0
                        ? 'Everything is counted.'
                        : 'Nothing here.',
                    style: TextStyle(color: secondary),
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                      DesignSpacing.md, DesignSpacing.lg, DesignSpacing.lg),
                  itemCount: lines.length,
                  itemBuilder: (context, i) {
                    final line = lines[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.productName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                if ((line.sku ?? '').isNotEmpty ||
                                    line.expectedQty != null)
                                  Text(
                                    [
                                      if ((line.sku ?? '').isNotEmpty) line.sku!,
                                      if (line.expectedQty != null)
                                        'System: ${kitNumber(line.expectedQty!)}',
                                    ].join(' · '),
                                    style: TextStyle(
                                        color: secondary, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: DesignSpacing.md),
                          SizedBox(
                            width: 96,
                            child: TextField(
                              controller: _controllers[line.productId],
                              textAlign: TextAlign.center,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]')),
                              ],
                              onChanged: (_) => setState(
                                  () => _dirty.add(line.productId)),
                              decoration: kitFieldDecoration(context,
                                  label: 'Counted', hint: '0'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        PinnedActionBar(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _saveProgress(),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                flex: 2,
                child: GradientButton(
                  label: 'Hand in count',
                  icon: Icons.send_rounded,
                  isLoading: _busy,
                  onPressed: _busy || counted == 0 ? null : _handIn,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- review

class _ReviewView extends ConsumerStatefulWidget {
  const _ReviewView({required this.detail});

  final StockCountDetail detail;

  @override
  ConsumerState<_ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends ConsumerState<_ReviewView> {
  bool _busy = false;

  Future<void> _approve() async {
    final d = widget.detail;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve and adjust stock?'),
        content: Text(
            'Stock will be changed to match this count: ${d.shortLines} item${d.shortLines == 1 ? '' : 's'} short (${kesWhole(d.lossValue)} at cost) and ${d.overLines} over (${kesWhole(d.gainValue)}). This is recorded against your name.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not yet')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Approve')),
        ],
      ),
    );
    if (go != true) return;
    await _run(() => getIt<ApiClient>().approveStockCount(d.id), 'Stock updated');
  }

  Future<void> _cancel() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this count?'),
        content: const Text('No stock will change.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel count')),
        ],
      ),
    );
    if (go != true) return;
    await _run(() => getIt<ApiClient>().cancelStockCount(widget.detail.id),
        'Count cancelled');
  }

  Future<void> _run(Future<dynamic> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(stockCountProvider(widget.detail.id));
      ref.invalidate(stockCountsProvider);
      if (mounted) {
        showGlassSnackBar(context, done,
            icon: Icons.check_circle_rounded, color: DesignColors.success);
      }
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, apiErrorMessage(e),
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final perms = ref.watch(permissionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final differences = d.items
        .where((l) => l.isCounted && (l.varianceQty ?? 0) != 0)
        .toList()
      ..sort((a, b) =>
          (a.varianceValue ?? 0).compareTo(b.varianceValue ?? 0));

    final statusText = switch (d.status) {
      'SUBMITTED' => 'Handed in${d.submittedByName != null ? ' by ${d.submittedByName}' : ''}. Waiting for approval.',
      'APPROVED' => 'Approved${d.approvedByName != null ? ' by ${d.approvedByName}' : ''}. Stock was adjusted.',
      _ => 'This count was cancelled. No stock changed.',
    };

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, 32),
            children: [
              Text(statusText, style: TextStyle(color: secondary)),
              const SizedBox(height: DesignSpacing.md),
              if (!d.expectedHidden && !d.cancelled)
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                          label: 'Missing',
                          value: kesWhole(d.lossValue),
                          color: DesignColors.error),
                    ),
                    const SizedBox(width: DesignSpacing.sm),
                    Expanded(
                      child: _Tile(
                          label: 'Extra',
                          value: kesWhole(d.gainValue),
                          color: DesignColors.success),
                    ),
                    const SizedBox(width: DesignSpacing.sm),
                    Expanded(
                      child: _Tile(
                          label: 'Net',
                          value: kesWhole(d.netValue),
                          color: d.netValue < 0
                              ? DesignColors.error
                              : DesignColors.success),
                    ),
                  ],
                ),
              const SizedBox(height: DesignSpacing.lg),
              SectionHeader(
                title: 'Differences',
                subtitle: '${differences.length} of ${d.countedLines} counted',
              ),
              const SizedBox(height: DesignSpacing.sm),
              if (differences.isEmpty)
                Text('Everything counted matched the system.',
                    style: TextStyle(color: secondary))
              else
                for (final l in differences)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
                    child: ListCard(
                      leading: Icon(
                        (l.varianceQty ?? 0) < 0
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        color: (l.varianceQty ?? 0) < 0
                            ? DesignColors.error
                            : DesignColors.success,
                      ),
                      title: l.productName,
                      subtitle:
                          'System ${kitNumber(l.expectedQty ?? 0)} · Counted ${kitNumber(l.countedQty ?? 0)}${l.countedByName != null ? ' · ${l.countedByName}' : ''}',
                      trailing: Text(
                        '${(l.varianceQty ?? 0) > 0 ? '+' : ''}${kitNumber(l.varianceQty ?? 0)}\n${kesWhole(l.varianceValue ?? 0)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: (l.varianceQty ?? 0) < 0
                              ? DesignColors.error
                              : DesignColors.success,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        if (d.submitted && perms.has('inventory.stocktake.approve'))
          PinnedActionBar(
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _cancel,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: const Text('Cancel count'),
                  ),
                ),
                const SizedBox(width: DesignSpacing.md),
                Expanded(
                  flex: 2,
                  child: GradientButton(
                    label: 'Approve & adjust',
                    icon: Icons.verified_rounded,
                    isLoading: _busy,
                    onPressed: _busy ? null : _approve,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
