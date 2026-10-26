import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/accountability_models.dart';
import '../providers/accountability_provider.dart';

/// The owner's watch-list: what happened in the shop that deserves a second
/// look (sales below cost, voids, stock written off, credit over the limit,
/// a short till...), plus how today went.
class ShopAlertsScreen extends ConsumerStatefulWidget {
  const ShopAlertsScreen({super.key});

  @override
  ConsumerState<ShopAlertsScreen> createState() => _ShopAlertsScreenState();
}

enum _Filter { open, high, all }

class _ShopAlertsScreenState extends ConsumerState<ShopAlertsScreen> {
  _Filter _filter = _Filter.open;

  List<ShopAlert> _visible(List<ShopAlert> all) => switch (_filter) {
        _Filter.open => all.where((a) => !a.acknowledged).toList(),
        _Filter.high =>
          all.where((a) => a.severity == AlertSeverity.high).toList(),
        _Filter.all => all,
      };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(alertsProvider);
    final controller = ref.read(alertsProvider.notifier);
    final perms = ref.watch(permissionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _visible(state.page.items);
    final branchId = getIt<StorageService>().getBranchId();

    return Scaffold(
      appBar: BrandedAppBar(
        title: ref
            .watch(businessLayoutProvider)
            .actionLabel('/shop-alerts', 'Shop Alerts'),
        showBackButton: GoRouter.of(context).canPop(),
        actions: [
          if (perms.has('accountability.manage'))
            IconButton(
              tooltip: 'Rules',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => context.push('/shop-alerts/rules'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, 120),
          children: [
            if (branchId != null) _TodayCard(branchId: branchId),
            const SizedBox(height: DesignSpacing.lg),
            Row(
              children: [
                _FilterChip(
                  label: state.page.openCount > 0
                      ? 'New (${state.page.openCount})'
                      : 'New',
                  selected: _filter == _Filter.open,
                  onTap: () => setState(() => _filter = _Filter.open),
                ),
                const SizedBox(width: DesignSpacing.sm),
                _FilterChip(
                  label: 'Serious',
                  selected: _filter == _Filter.high,
                  onTap: () => setState(() => _filter = _Filter.high),
                ),
                const SizedBox(width: DesignSpacing.sm),
                _FilterChip(
                  label: 'All',
                  selected: _filter == _Filter.all,
                  onTap: () => setState(() => _filter = _Filter.all),
                ),
                const Spacer(),
                if (state.page.openCount > 0)
                  TextButton(
                    onPressed: controller.acknowledgeAll,
                    child: const Text('Mark all seen'),
                  ),
              ],
            ),
            const SizedBox(height: DesignSpacing.md),
            if (!state.loadedOnce && state.page.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(DesignSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (state.error != null) ...[
                InlineRetryNotice(
                    message: state.error!, onRetry: controller.refresh),
                const SizedBox(height: DesignSpacing.md),
              ],
              if (items.isEmpty && state.error == null)
                EmptyState(
                  icon: Icons.verified_user_outlined,
                  iconColor: DesignColors.success,
                  title: _filter == _Filter.open
                      ? 'Nothing needs your attention'
                      : 'No alerts here',
                  subtitle:
                      'You will see sales below cost, voids, stock written off, '
                      'credit over the limit and a short till here.',
                )
              else
                for (final alert in items)
                  _AlertTile(
                    alert: alert,
                    isDark: isDark,
                    onSeen: alert.acknowledged
                        ? null
                        : () => controller.acknowledge([alert.id]),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: DesignColors.accent.withValues(alpha: 0.18),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        color: selected
            ? DesignColors.accent
            : (isDark
                ? DesignColors.darkTextSecondary
                : DesignColors.textSecondary),
      ),
      side: BorderSide(
        color: selected
            ? DesignColors.accent
            : (isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder),
      ),
      showCheckmark: false,
    );
  }
}

Color _severityColor(AlertSeverity s) => switch (s) {
      AlertSeverity.high => DesignColors.error,
      AlertSeverity.medium => DesignColors.warning,
      AlertSeverity.low => DesignColors.info,
    };

IconData _typeIcon(String type) => switch (type) {
      'BELOW_COST' || 'BELOW_FLOOR' => Icons.trending_down_rounded,
      'DISCOUNT_LIMIT' => Icons.percent_rounded,
      'VOID' => Icons.block_rounded,
      'REFUND' => Icons.undo_rounded,
      'STOCK_WRITE_OFF' || 'STOCK_ADJUSTMENT' => Icons.inventory_2_outlined,
      'PRICE_CHANGE' || 'PRICE_REVIEW' => Icons.sell_outlined,
      'CREDIT_NO_CUSTOMER' ||
      'CREDIT_LIMIT_EXCEEDED' ||
      'CREDIT_OVERDUE' ||
      'CREDIT_LIMIT_RAISED' =>
        Icons.account_balance_wallet_outlined,
      'CASH_SHORT' || 'CASH_OVER' => Icons.payments_outlined,
      'STOCKTAKE_VARIANCE' => Icons.fact_check_outlined,
      'DAILY_SUMMARY' => Icons.summarize_outlined,
      _ => Icons.flag_outlined,
    };

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, required this.isDark, this.onSeen});

  final ShopAlert alert;
  final bool isDark;
  final VoidCallback? onSeen;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(alert.severity);
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(
            color: alert.acknowledged
                ? (isDark
                    ? DesignColors.darkBorder
                    : DesignColors.surfaceBorder)
                : color.withValues(alpha: 0.5),
          ),
        ),
        padding: const EdgeInsets.all(DesignSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(_typeIcon(alert.type), size: 20, color: color),
            ),
            const SizedBox(width: DesignSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      Text(
                        timeAgo(alert.createdAt),
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(alert.body,
                      style: TextStyle(color: secondary, height: 1.35)),
                  if (onSeen != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: onSeen,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Seen'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.branchId});

  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(branchSummaryProvider(branchId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return GlassCard(
      padding: const EdgeInsets.all(DesignSpacing.lg),
      borderRadius: DesignSpacing.radiusXl,
      blur: 8,
      tint: DesignColors.accent.withValues(alpha: 0.08),
      borderColor: DesignColors.accent.withValues(alpha: 0.15),
      child: summary.when(
        loading: () => const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: secondary),
            const SizedBox(width: DesignSpacing.md),
            Expanded(
              child: Text("Today's summary isn't available right now.",
                  style: TextStyle(color: secondary)),
            ),
            TextButton(
              onPressed: () => ref.invalidate(branchSummaryProvider(branchId)),
              child: const Text('Retry'),
            ),
          ],
        ),
        data: (data) {
          final text = (data['text'] as Map?)?.cast<String, dynamic>() ?? {};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.today_rounded,
                      color: DesignColors.accent, size: 20),
                  const SizedBox(width: DesignSpacing.sm),
                  Expanded(
                    child: Text(
                      '${text['title'] ?? 'Today'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: () =>
                        ref.invalidate(branchSummaryProvider(branchId)),
                  ),
                ],
              ),
              const SizedBox(height: DesignSpacing.xs),
              Text(
                '${text['body'] ?? ''}',
                style: TextStyle(color: secondary, height: 1.45),
              ),
            ],
          );
        },
      ),
    );
  }
}
