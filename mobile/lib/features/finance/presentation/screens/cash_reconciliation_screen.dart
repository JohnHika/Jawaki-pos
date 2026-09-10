import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final _reconciliationHistoryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final branchId = getIt<AuthService>().branchId;
  if (branchId == null) return {};
  return getIt<ApiClient>().getCashReconciliations(branchId, limit: 20);
});

final _currencyFmt =
    NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);
final _dateFmt = DateFormat('dd MMM, HH:mm');

class CashReconciliationScreen extends ConsumerStatefulWidget {
  const CashReconciliationScreen({super.key});

  @override
  ConsumerState<CashReconciliationScreen> createState() =>
      _CashReconciliationScreenState();
}

class _CashReconciliationScreenState
    extends ConsumerState<CashReconciliationScreen> {
  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionsProvider);
    final historyAsync = ref.watch(_reconciliationHistoryProvider);

    if (!permissions.canReconcileCash) {
      return const Scaffold(
        appBar: BrandedAppBar(title: 'Cash Reconciliation'),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Restricted',
          subtitle: 'Only store managers and admins can reconcile cash.',
        ),
      );
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Cash Reconciliation',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_reconciliationHistoryProvider),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.sm,
            DesignSpacing.lg, DesignSpacing.md),
        child: GradientButton(
          label: 'Count Cash',
          icon: Icons.calculate_rounded,
          onPressed: _showCountSheet,
          height: 52,
          borderRadius: DesignSpacing.radiusMd,
        ),
      ),
      body: historyAsync.when(
        data: (data) {
          if (data.isEmpty) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'No branch selected',
              subtitle: 'Select a branch to reconcile cash.',
            );
          }

          final items =
              (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();

          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.calculate_outlined,
              title: 'No reconciliations yet',
              subtitle: 'Tap "Count Cash" to record your first cash count.',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                DesignSpacing.lg,
                DesignSpacing.md,
                DesignSpacing.lg,
                DesignSpacing.huge + DesignSpacing.xl),
            children: items
                .asMap()
                .entries
                .map((entry) => StaggeredItem(
                      itemKey: 'recon-${entry.value['id'] ?? entry.key}',
                      index: entry.key,
                      child: _ReconciliationCard(item: entry.value),
                    ))
                .toList(),
          );
        },
        loading: () => const _ReconciliationSkeletonList(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load reconciliation history',
          subtitle: 'Check your connection and try again.',
          iconColor: DesignColors.error,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(_reconciliationHistoryProvider),
        ),
      ),
    );
  }

  Future<void> _showCountSheet() async {
    final branchId = getIt<AuthService>().branchId;
    if (branchId == null) return;

    Map<String, dynamic>? expected;
    try {
      expected = await getIt<ApiClient>().getAvailableCash(branchId);
    } catch (_) {
      // Sheet still opens; expected figure just won't be shown up front —
      // the backend computes and stores the authoritative expected figure
      // regardless of what's shown here.
    }

    final expectedCash =
        expected != null ? (expected['availableCash'] as num).toDouble() : null;
    final countController = TextEditingController();
    final notesController = TextEditingController();

    if (!mounted) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final counted = double.tryParse(countController.text);
          final discrepancy = (counted != null && expectedCash != null)
              ? counted - expectedCash
              : null;

          return Padding(
            padding: EdgeInsets.fromLTRB(
                DesignSpacing.xl,
                DesignSpacing.xs,
                DesignSpacing.xl,
                DesignSpacing.xl + MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Count Cash',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: DesignSpacing.xs),
                  Text(
                    expectedCash != null
                        ? 'System expects: ${_currencyFmt.format(expectedCash)}'
                        : 'Could not load expected cash figure',
                    style: TextStyle(
                        color: isDark
                            ? DesignColors.darkTextSecondary
                            : DesignColors.textSecondary),
                  ),
                  const SizedBox(height: DesignSpacing.lg),
                  TextField(
                    controller: countController,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Physically counted cash (KES)',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: DesignSpacing.md),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                    maxLines: 2,
                  ),
                  if (discrepancy != null) ...[
                    const SizedBox(height: DesignSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(DesignSpacing.md),
                      decoration: BoxDecoration(
                        color: (discrepancy.abs() < 0.01
                                ? DesignColors.success
                                : discrepancy < 0
                                    ? DesignColors.error
                                    : DesignColors.warning)
                            .withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                      ),
                      child: Text(
                        discrepancy.abs() < 0.01
                            ? 'Matches exactly'
                            : discrepancy < 0
                                ? 'Shortfall: ${_currencyFmt.format(discrepancy.abs())}'
                                : 'Overage: ${_currencyFmt.format(discrepancy)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: discrepancy.abs() < 0.01
                              ? DesignColors.success
                              : discrepancy < 0
                                  ? DesignColors.error
                                  : DesignColors.warning,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: DesignSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(64, DesignSpacing.huge),
                      ),
                      onPressed: counted == null || counted < 0
                          ? null
                          : () => Navigator.pop(sheetContext, true),
                      child: const Text('Submit Count'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;

    final counted = double.tryParse(countController.text);
    if (counted == null) return;

    try {
      await getIt<ApiClient>().createCashReconciliation(
        branchId,
        countedCash: counted,
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
      );
      ref.invalidate(_reconciliationHistoryProvider);
      if (mounted) {
        showGlassSnackBar(context, 'Cash count recorded',
            icon: Icons.check_circle_rounded, color: DesignColors.success);
      }
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Could not record cash count: $e',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    }
  }
}

class _ReconciliationCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ReconciliationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    final expectedCash = (item['expectedCash'] as num).toDouble();
    final countedCash = (item['countedCash'] as num).toDouble();
    final discrepancy = (item['discrepancy'] as num).toDouble();
    final countedByName = item['countedByName'] as String?;
    final createdAt = DateTime.tryParse(item['createdAt'] as String? ?? '');

    final isMatch = discrepancy.abs() < 0.01;
    final statusColor = isMatch
        ? DesignColors.success
        : discrepancy < 0
            ? DesignColors.error
            : DesignColors.warning;

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm + 2),
      child: Container(
        padding: const EdgeInsets.all(DesignSpacing.radiusMd + 2),
        decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg - 2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    createdAt != null ? _dateFmt.format(createdAt) : '—',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                StatusBadge(
                  label: isMatch
                      ? 'Matches'
                      : discrepancy < 0
                          ? 'Shortfall'
                          : 'Overage',
                  color: statusColor,
                  isActive: true,
                ),
              ],
            ),
            const SizedBox(height: DesignSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text('Expected: ${_currencyFmt.format(expectedCash)}',
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                          color: secondaryColor,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0)),
                ),
                Expanded(
                  child: Text('Counted: ${_currencyFmt.format(countedCash)}',
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                          color: secondaryColor,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0)),
                ),
              ],
            ),
            if (!isMatch) ...[
              const SizedBox(height: DesignSpacing.xs),
              Text(
                'Difference: ${_currencyFmt.format(discrepancy.abs())}',
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    color: statusColor),
              ),
            ],
            if (countedByName != null) ...[
              const SizedBox(height: DesignSpacing.sm - 2),
              Text('Counted by $countedByName',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: secondaryColor)),
            ],
            if ((item['notes'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: DesignSpacing.xs),
              Text(item['notes'] as String,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: secondaryColor)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading rows for the history list: mirrors [_ReconciliationCard]'s
/// anatomy (date header + status badge, expected/counted lines, meta line)
/// inside the same card shell, so the reveal doesn't jump when data lands.
/// All figures the real card shows are computed locally from the count
/// record, so this skeleton is purely a loading surface — no placeholder
/// values are ever shown. ShimmerWidget already stops under reduced motion.
class _ReconciliationSkeletonList extends StatelessWidget {
  const _ReconciliationSkeletonList();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return ListView(
      padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.md,
          DesignSpacing.lg, DesignSpacing.huge + DesignSpacing.xl),
      children: List.generate(
        4,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: DesignSpacing.sm + 2),
          child: Container(
            padding: const EdgeInsets.all(DesignSpacing.radiusMd + 2),
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg - 2),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ShimmerWidget(
                        width: 120, height: 14, borderRadius: DesignSpacing.xs),
                    Spacer(),
                    SizedBox(width: DesignSpacing.sm),
                    ShimmerWidget(
                        width: 64,
                        height: 20,
                        borderRadius: DesignSpacing.radiusSm),
                  ],
                ),
                SizedBox(height: DesignSpacing.sm),
                ShimmerWidget(
                    width: double.infinity,
                    height: 13,
                    borderRadius: DesignSpacing.xs),
                SizedBox(height: DesignSpacing.sm),
                ShimmerWidget(
                    width: 150, height: 12, borderRadius: DesignSpacing.xs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
