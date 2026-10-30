import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../domain/stocktake_models.dart';
import '../providers/stocktake_provider.dart';

/// Counting the shelf and comparing it with the system: the way a loss shows
/// up before it becomes a habit.
class StockCountsScreen extends ConsumerWidget {
  const StockCountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(stockCountsProvider);
    final perms = ref.watch(permissionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: BrandedAppBar(
        title: ref
            .watch(businessLayoutProvider)
            .actionLabel('/stock-counts', 'Stock Counts'),
        showBackButton: GoRouter.of(context).canPop(),
      ),
      floatingActionButton: perms.has('inventory.stocktake.create')
          ? FloatingActionButton.extended(
              onPressed: () => _startSheet(context, ref),
              backgroundColor: DesignColors.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('New count'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(stockCountsProvider),
        child: counts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(DesignSpacing.lg),
            children: [
              InlineRetryNotice(
                message: apiErrorMessage(e),
                onRetry: () => ref.invalidate(stockCountsProvider),
              ),
            ],
          ),
          data: (rows) => rows.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 80),
                    EmptyState(
                      icon: Icons.fact_check_outlined,
                      title: 'No stock counts yet',
                      subtitle:
                          'Count what is on the shelf and compare it with the system. Do it weekly and losses show up early.',
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                      DesignSpacing.md, DesignSpacing.lg, 120),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _CountTile(
                    row: rows[i],
                    isDark: isDark,
                    onTap: () => context.push('/stock-counts/${rows[i].id}'),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _startSheet(BuildContext context, WidgetRef ref) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _StartCountSheet(),
    );
    ref.invalidate(stockCountsProvider);
    if (id != null && context.mounted) context.push('/stock-counts/$id');
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile(
      {required this.row, required this.isDark, required this.onTap});

  final StockCountSummary row;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (row.status) {
      'IN_PROGRESS' => ('Counting', DesignColors.info),
      'SUBMITTED' => ('Needs approval', DesignColors.warning),
      'APPROVED' => ('Done', DesignColors.success),
      _ => ('Cancelled', DesignColors.error),
    };
    final variance = row.totalVarianceValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: ListCard(
        leading: Icon(Icons.fact_check_outlined, color: color),
        title: row.displayTitle,
        subtitle:
            '${row.itemCount} items · ${timeAgo(row.createdAt)}${row.createdByName != null ? ' · ${row.createdByName}' : ''}'
            '${variance != null && variance != 0 ? '\n${variance < 0 ? 'Missing' : 'Extra'} ${kesWhole(variance.abs())}' : ''}',
        trailing: StatusBadge(label: label, color: color),
        onTap: onTap,
      ),
    );
  }
}

class _StartCountSheet extends StatefulWidget {
  const _StartCountSheet();

  @override
  State<_StartCountSheet> createState() => _StartCountSheetState();
}

class _StartCountSheetState extends State<_StartCountSheet> {
  final _title = TextEditingController();
  bool _blind = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final branchId = getIt<StorageService>().getBranchId();
    if (branchId == null) {
      setState(() => _error = 'Pick a branch first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final localWorkspace = getIt<AuthService>().isLocalWorkspace;
      final countId = localWorkspace
          ? await getIt<AppDatabase>().startLocalStockCount(
              branchId: branchId,
              title: _title.text,
              blind: _blind,
              createdByName:
                  getIt<AuthService>().currentUser?['name']?.toString(),
            )
          : '${(await getIt<ApiClient>().startStockCount(
              branchId: branchId,
              title: _title.text,
              blind: _blind,
            ))['id']}';
      if (!mounted) return;
      Navigator.of(context).pop(countId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(DesignSpacing.lg, 0, DesignSpacing.lg,
            media.viewInsets.bottom + DesignSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Start a stock count',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: DesignSpacing.md),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: kitFieldDecoration(context,
                    label: 'Name (optional)', hint: 'e.g. Weekly shelf count'),
              ),
              const SizedBox(height: DesignSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _blind,
                activeThumbColor: DesignColors.accent,
                onChanged: _busy ? null : (v) => setState(() => _blind = v),
                title: const Text('Hide system quantities while counting'),
                subtitle: const Text(
                    'The counter reports what is really on the shelf, not what they expect to find.'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
                  child: Text(_error!,
                      style: const TextStyle(color: DesignColors.error)),
                ),
              const SizedBox(height: DesignSpacing.sm),
              GradientButton(
                label: 'Start counting',
                icon: Icons.play_arrow_rounded,
                isLoading: _busy,
                onPressed: _busy ? null : _start,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
