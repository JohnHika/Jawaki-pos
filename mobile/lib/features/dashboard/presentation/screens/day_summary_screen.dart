import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/widgets/app_markdown.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/axon_ai_icon.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/utils/load_error.dart';
import '../../../ai/presentation/screens/ai_chat_service.dart';

/// Everything the calendar day-detail screen needs for one date. A local
/// workspace uses its device database; a connected workspace uses the server
/// so it can include sales from every device.
class DaySummaryData {
  final Map<String, dynamic> summary;
  final List<dynamic> sales;
  DaySummaryData({required this.summary, required this.sales});
}

final _daySummaryProvider = FutureProvider.autoDispose
    .family<DaySummaryData, DateTime>((ref, date) async {
  final branchId = getIt<AuthService>().branchId;
  final dateStr = DateFormat('yyyy-MM-dd').format(date);

  if (getIt<AuthService>().isLocalWorkspace) {
    if (branchId == null || branchId.isEmpty) {
      throw StateError(
        'Select an active branch before viewing this day’s sales.',
      );
    }
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1)).subtract(
          const Duration(microseconds: 1),
        );
    final db = getIt<AppDatabase>();
    final results = await Future.wait([
      db.getDailySalesSummary(branchId, date),
      db.getSalesByDateRangeForBranch(branchId, start, end),
    ]);
    final summary = results[0] as Map<String, dynamic>;
    final sales = (results[1] as List<PendingSale>)
        .where((sale) => sale.status.toUpperCase() == 'COMPLETED')
        .map((sale) => <String, dynamic>{
              'id': sale.id,
              'receiptNumber': sale.receiptNumber,
              'totalAmount': sale.total,
              'paymentMethod': sale.paymentMethod,
              'createdAt': sale.createdAt.toIso8601String(),
            })
        .toList(growable: false);
    return DaySummaryData(summary: summary, sales: sales);
  }

  final api = getIt<ApiClient>();

  final results = await Future.wait([
    branchId == null
        ? Future.value(<String, dynamic>{})
        : api.getSalesDailySummary(branchId, dateStr),
    api.getSales(startDate: dateStr, endDate: dateStr, limit: 200),
  ]);

  return DaySummaryData(
    summary: results[0] as Map<String, dynamic>,
    sales: results[1] as List<dynamic>,
  );
});

final _dayAiBriefProvider =
    FutureProvider.autoDispose.family<String?, DateTime>((ref, date) async {
  final dateStr = DateFormat('yyyy-MM-dd').format(date);
  return AiChatService().fetchDailyBrief(date: dateStr);
});

final _gatewayKeyConfiguredProvider = FutureProvider.autoDispose<bool>(
  (ref) => AiChatService().isGatewayConfigured(),
);

Future<void> _refreshDaySummary(WidgetRef ref, DateTime date) async {
  ref.invalidate(_daySummaryProvider(date));
  if (getIt<AuthService>().isLocalWorkspace) {
    // Keep the Gateway request independent from sales-data loading. The
    // refresh indicator follows the local database refresh, while the brief
    // card shows its own loading state.
    ref.invalidate(_dayAiBriefProvider(date));
  }
  try {
    await ref.read(_daySummaryProvider(date).future);
  } catch (_) {
    // The provider renders the actionable error state after refresh ends.
  }
}

/// Shown when the dashboard's calendar icon returns a past date: sales for
/// that day, plus an AI brief when an Axon Gateway key is configured.
class DaySummaryScreen extends ConsumerWidget {
  const DaySummaryScreen({super.key, required this.date});

  final DateTime date;

  static final _currencyFmt =
      NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);
  static final _timeFmt = DateFormat('hh:mm a');
  static final _titleDateFmt = DateFormat('EEEE, d MMMM yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(_daySummaryProvider(date));

    return Scaffold(
      appBar: BrandedAppBar(
        title: _titleDateFmt.format(date),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _refreshDaySummary(ref, date),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshDaySummary(ref, date),
        child: dataAsync.when(
          data: (data) => _buildContent(context, ref, data),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(DesignSpacing.xl),
                child: EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: "Couldn't load this day",
                  subtitle: loadErrorSubtitle(e),
                  iconColor: DesignColors.error,
                  actionLabel: isPermissionDenied(e) ? null : 'Retry',
                  onAction: isPermissionDenied(e)
                      ? null
                      : () => ref.invalidate(_daySummaryProvider(date)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, DaySummaryData data) {
    final summary = data.summary;
    final sales = data.sales;
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final divider =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return PageContainer(
      withScroll: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary metrics for the day
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.xs),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        title: 'Total Sales',
                        value: _currencyFmt
                            .format((summary['totalSales'] as num?) ?? 0),
                        icon: Icons.trending_up_rounded,
                        color: DesignColors.success,
                      ),
                    ),
                    const SizedBox(width: DesignSpacing.md),
                    Expanded(
                      child: MetricCard(
                        title: 'Transactions',
                        value:
                            '${summary['totalTransactions'] ?? sales.length}',
                        icon: Icons.receipt_long_rounded,
                        color: DesignColors.brand,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        title: 'Cash',
                        value: _currencyFmt
                            .format((summary['cashSales'] as num?) ?? 0),
                        icon: Icons.money_rounded,
                        color: DesignColors.cash,
                      ),
                    ),
                    const SizedBox(width: DesignSpacing.md),
                    Expanded(
                      child: MetricCard(
                        title: isLocalWorkspace ? 'Credit Sales' : 'M-Pesa',
                        value: _currencyFmt.format((summary[isLocalWorkspace
                                ? 'creditSales'
                                : 'mpesaSales'] as num?) ??
                            0),
                        icon: isLocalWorkspace
                            ? Icons.credit_score_rounded
                            : Icons.phone_android_rounded,
                        color: isLocalWorkspace
                            ? DesignColors.credit
                            : DesignColors.mpesa,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: DesignSpacing.xl),

          if (isLocalWorkspace) ...[
            _buildAiBrief(context, ref),
            const SizedBox(height: DesignSpacing.xl),
          ],

          // Sales list for the day
          SectionHeader(
            icon: Icons.receipt_long_rounded,
            title: 'Sales',
            subtitle: '${sales.length} receipt${sales.length == 1 ? '' : 's'}',
          ),
          const SizedBox(height: DesignSpacing.sm),
          if (sales.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: DesignSpacing.xl),
              child: EmptyState(
                icon: Icons.receipt_long_rounded,
                title: 'No sales on this day',
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              child: Container(
                decoration: BoxDecoration(
                  color:
                      isDark ? DesignColors.darkSurfaceElevated : Colors.white,
                  border: Border.all(color: divider),
                ),
                child: Column(
                  children: sales.asMap().entries.map((entry) {
                    final isLast = entry.key == sales.length - 1;
                    final sale = entry.value as Map<String, dynamic>;
                    final createdAt =
                        DateTime.tryParse(sale['createdAt']?.toString() ?? '')
                                ?.toLocal() ??
                            date;
                    final total = (sale['totalAmount'] as num?) ?? 0;
                    final receiptNumber =
                        sale['receiptNumber']?.toString() ?? '';
                    final method =
                        sale['paymentMethod']?.toString().toUpperCase() ?? '';
                    final saleId = sale['id']?.toString();
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: saleId == null
                            ? null
                            : () => context.push('/receipt/$saleId'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          decoration: BoxDecoration(
                            border: isLast
                                ? null
                                : Border(bottom: BorderSide(color: divider)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: DesignColors.accent
                                      .withValues(alpha: 0.10),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.receipt_long_rounded,
                                    size: 18, color: DesignColors.accent),
                              ),
                              const SizedBox(width: DesignSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(receiptNumber,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: titleColor)),
                                    const SizedBox(height: 2),
                                    Text(
                                        '$method  \u00b7  ${_timeFmt.format(createdAt)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                                color: isDark
                                                    ? DesignColors
                                                        .darkTextTertiary
                                                    : DesignColors
                                                        .textTertiary)),
                                  ],
                                ),
                              ),
                              Text(_currencyFmt.format(total),
                                  style: DesignType.numeric(
                                      fontSize: 15, color: titleColor)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          const SizedBox(height: DesignSpacing.xxl),
        ],
      ),
    );
  }

  Widget _buildAiBrief(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final localWorkspace = getIt<AuthService>().isLocalWorkspace;
    final gatewayKeyStatus = ref.watch(_gatewayKeyConfiguredProvider);
    final briefAsync = ref.watch(_dayAiBriefProvider(date));
    final cardBorder =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSpacing.lg),
            decoration: BoxDecoration(
              color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AxonAiIcon(
                      tenantLogoUrl: ref.watch(tenantIdentityProvider).logoUrl,
                      size: 18,
                    ),
                    const SizedBox(width: DesignSpacing.sm),
                    Text(
                      'AI BRIEF',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: isDark
                              ? DesignColors.darkTextTertiary
                              : DesignColors.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: DesignSpacing.md),
                briefAsync.when(
                  data: (brief) {
                    if (brief != null && brief.trim().isNotEmpty) {
                      return AppMarkdown(
                        brief.trim(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                            color: isDark
                                ? DesignColors.darkTextSecondary
                                : DesignColors.textSecondary),
                      );
                    }
                    if (localWorkspace && gatewayKeyStatus.isLoading) {
                      return const Text('Checking Axon Gateway settings…');
                    }
                    if (localWorkspace && gatewayKeyStatus.hasError) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Secure key storage could not be checked. No AI request was sent.',
                          ),
                          TextButton.icon(
                            onPressed: () {
                              ref.invalidate(_gatewayKeyConfiguredProvider);
                              ref.invalidate(_dayAiBriefProvider(date));
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Check again'),
                          ),
                        ],
                      );
                    }
                    if (localWorkspace &&
                        gatewayKeyStatus.valueOrNull != true) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add your owner-issued Axon Gateway key to generate a brief from this device’s sales summary.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: isDark
                                      ? DesignColors.darkTextSecondary
                                      : DesignColors.textSecondary,
                                ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () async {
                                await context.push('/settings/ai-gateway');
                                if (!context.mounted) return;
                                ref.invalidate(_gatewayKeyConfiguredProvider);
                                ref.invalidate(_dayAiBriefProvider(date));
                              },
                              icon: const Icon(Icons.key_rounded, size: 18),
                              label: const Text('Open Gateway settings'),
                            ),
                          ),
                        ],
                      );
                    }
                    return Text(
                      'No AI brief available for this day.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? DesignColors.darkTextTertiary
                              : DesignColors.textTertiary),
                    );
                  },
                  loading: () => Row(
                    children: [
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: isDark
                              ? DesignColors.darkTextTertiary
                              : DesignColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: DesignSpacing.sm),
                      Text(
                        'Generating a brief for this day...',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: isDark
                                ? DesignColors.darkTextTertiary
                                : DesignColors.textTertiary),
                      ),
                    ],
                  ),
                  error: (_, __) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Couldn't generate a brief for this day.",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? DesignColors.darkTextTertiary
                                : DesignColors.textTertiary),
                      ),
                      if (localWorkspace)
                        TextButton.icon(
                          onPressed: () =>
                              ref.invalidate(_dayAiBriefProvider(date)),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Try again'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: DesignColors.accent),
          ),
        ],
      ),
    );
  }
}
