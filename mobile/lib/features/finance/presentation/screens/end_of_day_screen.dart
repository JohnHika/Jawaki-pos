import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/motion.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final _currencyFmt =
    NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);
final _timeFmt = DateFormat('dd MMM, HH:mm');

String _todayIso() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Combines today's sales summary, expected cash, and any existing close so
/// the screen can show either "open — review & close" or "closed at …".
final _eodProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final branchId = getIt<AuthService>().branchId;
  if (branchId == null) return {'noBranch': true};
  final api = getIt<ApiClient>();
  final date = _todayIso();
  final apiHost = Uri.tryParse(api.baseUrl)?.host;
  final isLocalServer =
      apiHost == '127.0.0.1' || apiHost == 'localhost' || apiHost == '::1';
  // Sales figures are essential; cash and close status are secondary. A
  // failure in either secondary request must not blank the whole report.
  final results = await Future.wait([
    _captureEodRequest(api.getSalesDailySummary(branchId, date)),
    _captureEodRequest(api.getAvailableCash(branchId)),
    _captureEodRequest(api.getDailyClose(branchId, date: date)),
  ]);
  var summary = results[0]['value'] as Map<String, dynamic>?;
  Object? summaryError = results[0]['error'];
  var summaryFromDevice = false;
  Object? localSummaryError;
  if (summary == null) {
    summaryError ??= StateError('The cloud sales summary was empty.');
    // Keep the page useful during a cloud outage, while clearly marking the
    // local figures as incomplete and preventing an unsafe close.
    try {
      summary = await getIt<AppDatabase>()
          .getDailySalesSummary(branchId, DateTime.now());
      summaryFromDevice = true;
    } catch (error) {
      // A local database failure should not replace the whole page with a
      // generic provider error. Keep totals explicitly unavailable and leave
      // the close action disabled until a refresh can verify them.
      localSummaryError = error;
    }
  }

  final cashResult = results[1];
  final closeResult = results[2];
  return {
    'summary': summary ?? const <String, dynamic>{},
    'summaryError': summaryError ?? localSummaryError,
    'summaryUnavailable': summary == null,
    'localSummaryError': localSummaryError,
    'summaryFromDevice': summaryFromDevice,
    'cash': cashResult['value'] as Map<String, dynamic>?,
    'cashError': cashResult['error'],
    'close': closeResult['value'] as Map<String, dynamic>?,
    'closeError': closeResult['error'],
    'localServer': isLocalServer,
  };
});

Future<Map<String, dynamic>> _captureEodRequest<T>(Future<T> request) async {
  try {
    return {'value': await request};
  } catch (error) {
    return {'error': error};
  }
}

class EndOfDayScreen extends ConsumerStatefulWidget {
  const EndOfDayScreen({super.key});

  @override
  ConsumerState<EndOfDayScreen> createState() => _EndOfDayScreenState();
}

class _EndOfDayScreenState extends ConsumerState<EndOfDayScreen> {
  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionsProvider);
    final eodAsync = ref.watch(_eodProvider);

    if (!permissions.canCloseEndOfDay) {
      return const Scaffold(
        appBar: BrandedAppBar(title: 'End of Day'),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Restricted',
          subtitle:
              'You do not have permission to close the end of day. Ask an admin to grant it.',
        ),
      );
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'End of Day',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_eodProvider),
          ),
        ],
      ),
      body: eodAsync.when(
        data: (data) {
          if (data['noBranch'] == true) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'No branch selected',
              subtitle: 'Select a branch to close the day.',
            );
          }
          final summary = (data['summary'] as Map<String, dynamic>?) ?? {};
          final cash = (data['cash'] as Map<String, dynamic>?) ?? {};
          final close = data['close'] as Map<String, dynamic>?;
          return _buildBody(
            summary,
            cash,
            close,
            summaryError: data['summaryError'],
            summaryFromDevice: data['summaryFromDevice'] == true,
            summaryUnavailable: data['summaryUnavailable'] == true,
            localSummaryError: data['localSummaryError'],
            cashError: data['cashError'],
            closeError: data['closeError'],
            localServer: data['localServer'] == true,
          );
        },
        loading: () => const _EodSkeletonList(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: "Couldn't load today's figures",
          subtitle: apiErrorMessage(e),
          iconColor: DesignColors.error,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(_eodProvider),
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> summary, Map<String, dynamic> cash,
      Map<String, dynamic>? close,
      {Object? summaryError,
      bool summaryFromDevice = false,
      bool summaryUnavailable = false,
      Object? localSummaryError,
      Object? cashError,
      Object? closeError,
      bool localServer = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final closed = close != null;

    final totalSales = asDouble(summary['totalSales']);
    final txns = asInt(summary['totalTransactions']);
    final cashSales = asDouble(summary['cashSales']);
    final mpesaSales = asDouble(summary['mpesaSales']);
    final creditSales = asDouble(summary['creditSales']);
    final cashMode = cash['mode']?.toString();
    final physicalCash = cash['expectedPhysicalCash'] ??
        ((cashMode == 'CASH_ONLY' || cashMode == 'RUNNING_BALANCE')
            ? cash['availableCash']
            : null);
    final expectedCash = cashError == null && physicalCash is num
        ? asDouble(physicalCash)
        : null;
    final closeStatusKnown = closeError == null && summaryError == null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.lg,
          DesignSpacing.lg, DesignSpacing.xl + DesignSpacing.sm),
      children: [
        // Status banner
        StaggeredItem(
          itemKey: 'eod-status',
          child: Container(
            padding: const EdgeInsets.all(DesignSpacing.radiusMd + 2),
            decoration: BoxDecoration(
              color: (closed ? DesignColors.success : DesignColors.accent)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg - 2),
            ),
            child: Row(
              children: [
                Icon(
                  closed ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: closed ? DesignColors.success : DesignColors.accent,
                ),
                const SizedBox(width: DesignSpacing.sm + 2),
                Expanded(
                  child: Text(
                    closed
                        ? 'Day closed${close['closedByName'] != null ? ' by ${close['closedByName']}' : ''}'
                            '${_closedAtSuffix(close)}'
                        : closeStatusKnown
                            ? 'Today is still open'
                            : 'Close status unavailable',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: DesignSpacing.lg),

        if (summaryError != null ||
            cashError != null ||
            closeError != null) ...[
          StaggeredItem(
            itemKey: 'eod-partial-warning',
            child: Container(
              padding: const EdgeInsets.all(DesignSpacing.md),
              decoration: BoxDecoration(
                color: DesignColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: DesignColors.warning),
                  const SizedBox(width: DesignSpacing.sm),
                  Expanded(
                    child: Text(
                      summaryError != null
                          ? summaryUnavailable
                              ? 'Sales totals could not be loaded from the cloud or this device. Refresh before closing. ${apiErrorMessage(localSummaryError ?? summaryError)}'
                              : summaryFromDevice
                                  ? 'Cloud sales totals are unavailable. Showing sales saved on this device; reconnect and refresh before closing so the report includes every device. ${apiErrorMessage(summaryError)}'
                                  : 'Sales totals could not be verified. ${apiErrorMessage(summaryError)} Reconnect and refresh before closing.'
                          : closeError != null
                              ? localServer
                                  ? 'Sales are saved on this device, but the local server cannot verify or record an end-of-day close. Reconnect to the cloud workspace and refresh before closing.'
                                  : 'Sales loaded, but close status could not be checked. ${apiErrorMessage(closeError)} Refresh before closing to avoid changing an existing close.'
                              : localServer
                                  ? 'Sales are available on this device, but expected till cash is only available from the cloud workspace.'
                                  : 'Sales loaded, but expected till cash could not be fetched. ${apiErrorMessage(cashError!)} You can still review today’s sales.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: DesignSpacing.lg),
        ],

        const SettingsGroupLabel("Today's sales"),
        StaggeredItem(
          itemKey: 'eod-summary',
          index: 1,
          child: GroupedCard(dividerIndent: 14, children: [
            _summaryRow(
                'Total sales',
                summaryUnavailable
                    ? 'Unavailable'
                    : _currencyFmt.format(totalSales),
                isDark,
                bold: true),
            _summaryRow('Transactions',
                summaryUnavailable ? 'Unavailable' : '$txns', isDark),
            _summaryRow(
                'Cash',
                summaryUnavailable
                    ? 'Unavailable'
                    : _currencyFmt.format(cashSales),
                isDark),
            _summaryRow(
                'M-Pesa',
                summaryUnavailable
                    ? 'Unavailable'
                    : _currencyFmt.format(mpesaSales),
                isDark),
            _summaryRow(
                'Credit',
                summaryUnavailable
                    ? 'Unavailable'
                    : _currencyFmt.format(creditSales),
                isDark),
            if (expectedCash != null)
              _summaryRow('Expected cash in till',
                  _currencyFmt.format(expectedCash), isDark),
          ]),
        ),

        if (closed) ...[
          const SizedBox(height: DesignSpacing.lg),
          const SettingsGroupLabel('Close details'),
          StaggeredItem(
            itemKey: 'eod-close-details',
            index: 2,
            child: GroupedCard(dividerIndent: 14, children: [
              _summaryRow('Counted cash',
                  _currencyFmt.format(asDouble(close['countedCash'])), isDark),
              _summaryRow(
                'Discrepancy',
                _currencyFmt.format(asDouble(close['cashDiscrepancy'])),
                isDark,
              ),
            ]),
          ),
          const SizedBox(height: DesignSpacing.xl),
          Text(
            'The day is already closed. Re-close only if you re-counted the till.',
            style: TextStyle(
              color: isDark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: DesignSpacing.sm),
        ],

        const SizedBox(height: DesignSpacing.xl),
        StaggeredItem(
          itemKey: 'eod-close-cta',
          index: closed ? 3 : 2,
          child: GradientButton(
            label: summaryError != null
                ? 'Reconnect to verify sales'
                : !closeStatusKnown
                    ? 'Connect to check close status'
                    : closed
                        ? 'Re-close day'
                        : 'Close end of day',
            icon: Icons.check_circle_outline_rounded,
            onPressed: closeStatusKnown && summaryError == null
                ? () => _showCloseSheet(expectedCash)
                : null,
            height: 52,
            borderRadius: DesignSpacing.radiusMd,
          ),
        ),
      ],
    );
  }

  String _closedAtSuffix(Map<String, dynamic> close) {
    final at = DateTime.tryParse(close['closedAt'] as String? ?? '')?.toLocal();
    return at != null ? ' at ${_timeFmt.format(at)}' : '';
  }

  Widget _summaryRow(String label, String value, bool isDark,
      {bool bold = false}) {
    final textColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: DesignSpacing.radiusMd + 2,
          vertical: DesignSpacing.md - 1),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: secondary,
                    )),
          ),
          Text(
            value,
            style: DesignType.numeric(
              color: textColor,
              fontSize: 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCloseSheet(double? expectedCash) async {
    final branchId = getIt<AuthService>().branchId;
    if (branchId == null) return;

    final countController = TextEditingController();
    final notesController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      useRootNavigator: true,
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
                  Text('Close end of day',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: DesignSpacing.xs),
                  Text(
                    expectedCash != null
                        ? 'System expects ${_currencyFmt.format(expectedCash)} in the till. Count it to finalize the day.'
                        : 'Count the cash in the till to finalize the day.',
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
                      labelText: 'Counted cash in till (KES)',
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
                            ? 'Matches expected cash'
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
                      child: const Text('Confirm & close day'),
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
      await getIt<ApiClient>().closeEndOfDay(
        branchId,
        countedCash: counted,
        // Close the same branch-local business day whose figures and existing
        // close status were displayed above. The server otherwise defaults to
        // its UTC date, which can still be yesterday near midnight in Nairobi.
        date: _todayIso(),
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
      );
      ref.invalidate(_eodProvider);
      if (mounted) {
        showGlassSnackBar(context, 'End of day closed',
            icon: Icons.check_circle_rounded, color: DesignColors.success);
      }
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, apiErrorMessage(e),
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    }
  }
}

/// Loading placeholder for the EOD body: three blocks in the same card
/// shells the real body uses (status banner, summary GroupedCard, close
/// CTA), so the reveal doesn't jump when today's figures land.
/// ShimmerWidget already stops under reduced motion.
class _EodGroupSkeleton extends StatelessWidget {
  final double bannerLineWidth;
  final int lineCount;

  const _EodGroupSkeleton({
    required this.bannerLineWidth,
    required this.lineCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          height: 44,
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          ),
          child: Row(
            children: [
              const SizedBox(width: DesignSpacing.lg),
              ShimmerWidget(
                  width: bannerLineWidth,
                  height: 14,
                  borderRadius: DesignSpacing.xs),
              const SizedBox(width: DesignSpacing.lg),
            ],
          ),
        ),
        const SizedBox(height: DesignSpacing.lg),
        for (var i = 0; i < lineCount; i++) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: DesignSpacing.radiusMd + 2,
                vertical: DesignSpacing.md - 1),
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            ),
            child: const ShimmerWidget(
                width: double.infinity,
                height: 13,
                borderRadius: DesignSpacing.xs),
          ),
          if (i != lineCount - 1)
            Divider(
                height: 1,
                thickness: 1,
                indent: 60,
                color: border.withValues(alpha: 0.6)),
        ],
        Container(
          width: double.infinity,
          height: 20,
          decoration: BoxDecoration(
            color: surface,
            border: Border.all(color: border),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(18)),
          ),
        ),
        const SizedBox(height: DesignSpacing.xl),
      ],
    );
  }
}

class _EodSkeletonList extends StatelessWidget {
  const _EodSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.lg,
          DesignSpacing.lg, DesignSpacing.xl + DesignSpacing.sm),
      children: const [
        _EodGroupSkeleton(bannerLineWidth: 140, lineCount: 3),
        _EodGroupSkeleton(bannerLineWidth: 110, lineCount: 4),
        _EodGroupSkeleton(bannerLineWidth: 170, lineCount: 3),
      ],
    );
  }
}
