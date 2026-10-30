import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
const _eodRequestTimeout = Duration(seconds: 8);

/// Combines today's sales summary, expected cash, and any existing close so
/// the screen can show either "open — review & close" or "closed at …".
final _eodProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final authService = getIt<AuthService>();
  final branchId = authService.branchId;
  if (branchId == null) return {'noBranch': true};

  // A local workspace has no POS API and must not spend several timeouts
  // waiting for cloud sales, till cash, and close-status endpoints before
  // showing records that are already on this device.
  if (authService.isLocalWorkspace) {
    final db = getIt<AppDatabase>();
    final today = DateTime.now();
    Map<String, dynamic>? summary;
    Object? localSummaryError;
    try {
      summary = await db.getDailySalesSummary(branchId, today);
    } catch (error) {
      localSummaryError = error;
    }

    Map<String, dynamic>? close;
    var closeNeedsReconciliation = false;
    var localCloseStatusKnown = false;
    Object? localCloseError;
    if (summary != null) {
      try {
        final businessDate = summary['date']?.toString() ?? '';
        close = await db.getLatestLocalDailyClose(
          branchId: branchId,
          businessDate: businessDate,
        );
        final closedAt =
            DateTime.tryParse(close?['closedAt']?.toString() ?? '');
        if (closedAt != null) {
          final start = DateTime(today.year, today.month, today.day);
          final end = start.add(const Duration(days: 1));
          closeNeedsReconciliation = await db.hasSalesActivityAfterClose(
                branchId: branchId,
                from: start,
                to: end,
                closedAt: closedAt,
              ) ||
              await db.hasLocalCashPayoutsAfterClose(
                branchId: branchId,
                from: start,
                to: end,
                closedAt: closedAt,
              ) ||
              _cashCloseAmountChanged(
                summary['cashSales'],
                close?['cashSales'],
              ) ||
              _cashCloseAmountChanged(
                summary['cashCollections'],
                close?['cashCollections'],
              ) ||
              _cashCloseAmountChanged(
                summary['cashPayouts'],
                close?['cashPayouts'],
              ) ||
              _cashCloseAmountChanged(
                summary['cashRefunds'],
                close?['cashRefunds'],
              ) ||
              _cashCloseAmountChanged(
                summary['voidedCashReceived'],
                close?['voidedCashReceived'],
              );
        }
        localCloseStatusKnown = true;
      } catch (error) {
        localCloseError = error;
        // Never treat a saved close as current when its reconciliation checks
        // could not complete.
        closeNeedsReconciliation = close != null;
      }
    }
    return {
      'summary': summary ?? const <String, dynamic>{},
      'summaryFromDevice': summary != null,
      'summaryUnavailable': summary == null,
      'summaryError': localSummaryError ?? localCloseError,
      'localSummaryError': localSummaryError,
      'closeError': localCloseError,
      'localCloseStatusKnown': localCloseStatusKnown,
      'localOnly': true,
      'cash': {
        if (close != null) 'expectedPhysicalCash': close['expectedCash'],
        'mode': 'LOCAL_RECORDED',
      },
      'close': close,
      'closeNeedsReconciliation': closeNeedsReconciliation,
    };
  }

  final api = getIt<ApiClient>();
  final apiHost = Uri.tryParse(api.baseUrl)?.host;
  final isLocalServer =
      apiHost == '127.0.0.1' || apiHost == 'localhost' || apiHost == '::1';
  // Sales figures are essential; cash and close status are secondary. A
  // failure in either secondary request must not blank the whole report.
  final results = await Future.wait([
    _captureEodRequest(
        api.getSalesTodaySummary(branchId, requestTimeout: _eodRequestTimeout)),
    _captureEodRequest(
        api.getAvailableCash(branchId, requestTimeout: _eodRequestTimeout)),
    _captureEodRequest(
        api.getDailyClose(branchId, requestTimeout: _eodRequestTimeout)),
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

bool _cashCloseAmountChanged(Object? current, Object? closed) =>
    (asDouble(current) - asDouble(closed)).abs() > 0.005;

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
  bool _isClosing = false;

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionsProvider);
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;

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

    // Do not load sales totals or cash-close details for a role that cannot
    // access the End of Day screen.
    final eodAsync = ref.watch(_eodProvider);

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
            closeNeedsReconciliation: data['closeNeedsReconciliation'] == true,
            localSummaryError: data['localSummaryError'],
            cashError: data['cashError'],
            closeError: data['closeError'],
            localCloseStatusKnown: data['localCloseStatusKnown'] == true,
            localServer: data['localServer'] == true,
            localOnly: data['localOnly'] == true,
          );
        },
        loading: () => const _EodSkeletonList(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: "Couldn't load today's figures",
          subtitle: isLocalWorkspace
              ? 'Couldn’t read the sales records stored on this device. Check the selected shop and branch, then retry.'
              : apiErrorMessage(e),
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
      bool closeNeedsReconciliation = false,
      Object? localSummaryError,
      Object? cashError,
      Object? closeError,
      bool localCloseStatusKnown = true,
      bool localServer = false,
      bool localOnly = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final closed = close != null &&
        !closeNeedsReconciliation &&
        (!localOnly || localCloseStatusKnown);

    final totalSales = asDouble(summary['totalSales']);
    final txns = asInt(summary['totalTransactions']);
    final cashSales = asDouble(summary['cashSales']);
    final cashCollections = asDouble(summary['cashCollections']);
    final cashPayouts = asDouble(summary['cashPayouts']);
    final cashRefunds = asDouble(summary['cashRefunds']);
    final voidedCashReceived = asDouble(summary['voidedCashReceived']);
    final mpesaSales = asDouble(summary['mpesaSales']);
    final cardSales = asDouble(summary['cardSales']);
    final creditSales = asDouble(summary['creditSales']);
    final otherSales = asDouble(summary['otherSales']);
    final otherPaymentMethods = (summary['otherPaymentMethods'] as List? ?? [])
        .whereType<Map>()
        .map((method) => Map<String, dynamic>.from(method))
        .toList(growable: false);
    final cashMode = cash['mode']?.toString();
    final physicalCash = cash['expectedPhysicalCash'] ??
        ((cashMode == 'CASH_ONLY' || cashMode == 'RUNNING_BALANCE')
            ? cash['availableCash']
            : null);
    final expectedCash = cashError == null && physicalCash is num
        ? asDouble(physicalCash)
        : null;
    final closeStatusKnown =
        !localOnly && closeError == null && summaryError == null;
    final cashStatusKnown = cashError == null && expectedCash != null;
    final businessDate = summary['date']?.toString();
    final validBusinessDate = businessDate != null &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(businessDate);
    final canClose = localOnly
        ? validBusinessDate && !summaryUnavailable && localCloseStatusKnown
        : closeStatusKnown && cashStatusKnown && validBusinessDate;

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
                    localOnly
                        ? !localCloseStatusKnown
                            ? 'Close status unavailable'
                            : closeNeedsReconciliation
                                ? 'New activity since till close'
                                : closed
                                    ? 'Day closed${_closedAtSuffix(close)}'
                                    : 'On-device sales summary'
                        : closed
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

        if (localOnly) ...[
          if (summaryError != null || closeError != null) ...[
            StaggeredItem(
              itemKey: 'eod-local-load-warning',
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
                        summaryUnavailable
                            ? 'Sales saved on this device could not be read. Check the selected shop and branch, then refresh. ${apiErrorMessage(localSummaryError ?? summaryError!)}'
                            : 'Sales are available, but the saved till-close status could not be verified. Refresh before closing so an existing close is not overwritten. ${apiErrorMessage(closeError ?? summaryError!)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: DesignSpacing.lg),
          ],
          StaggeredItem(
            itemKey: 'eod-local-only-note',
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
                    child: Text(closeNeedsReconciliation
                        ? 'A sale changed or a debt collection was recorded after the last close. Reconcile the till and close the day again.'
                        : 'Figures load from this device. At close, enter the opening float and net cash added or removed. This stores one net adjustment, not each till movement. Include cash movements made outside Counterbase and explain them in the notes.'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: DesignSpacing.lg),
          if (otherPaymentMethods.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(DesignSpacing.md),
              decoration: BoxDecoration(
                color: DesignColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: DesignColors.warning),
                      const SizedBox(width: DesignSpacing.sm),
                      Expanded(
                        child: Text(
                          'Some sales use an older payment label or have incomplete split details. They stay in total sales, appear below, and are excluded from cash totals. Check whether any belong in the till and record that adjustment in the close notes.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignSpacing.sm),
                  ...otherPaymentMethods.map((method) => Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: Text(
                          '${method['method']}: ${_currencyFmt.format(asDouble(method['amount']))}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: DesignSpacing.lg),
          ],
        ] else if (summaryError != null ||
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
                'Cash sales',
                summaryUnavailable
                    ? 'Unavailable'
                    : _currencyFmt.format(cashSales),
                isDark),
            if (localOnly)
              _summaryRow(
                'Cash debt collections',
                summaryUnavailable
                    ? 'Unavailable'
                    : _currencyFmt.format(cashCollections),
                isDark,
              ),
            if (localOnly && (summaryUnavailable || voidedCashReceived > 0))
              _summaryRow(
                'Cash received on voided sales',
                summaryUnavailable
                    ? 'Unavailable'
                    : _currencyFmt.format(voidedCashReceived),
                isDark,
              ),
            if (localOnly && (summaryUnavailable || cashRefunds > 0))
              _summaryRow(
                'Cash refunds from till',
                summaryUnavailable
                    ? 'Unavailable'
                    : '-${_currencyFmt.format(cashRefunds)}',
                isDark,
              ),
            if (localOnly)
              _summaryRow(
                'Supplier payments from till',
                summaryUnavailable
                    ? 'Unavailable'
                    : '-${_currencyFmt.format(cashPayouts)}',
                isDark,
              ),
            _summaryRow(
                'M-Pesa',
                summaryUnavailable
                    ? 'Unavailable'
                    : _currencyFmt.format(mpesaSales),
                isDark),
            _summaryRow(
                'Card',
                summaryUnavailable
                    ? 'Unavailable'
                    : _currencyFmt.format(cardSales),
                isDark),
            _summaryRow(
                'Credit',
                summaryUnavailable
                    ? 'Unavailable'
                    : _currencyFmt.format(creditSales),
                isDark),
            if (otherSales > 0)
              _summaryRow('Other payment methods',
                  _currencyFmt.format(otherSales), isDark),
            if (expectedCash != null)
              _summaryRow(
                localOnly && closeNeedsReconciliation
                    ? 'Expected at last close'
                    : 'Expected cash in till',
                _currencyFmt.format(expectedCash),
                isDark,
              ),
          ]),
        ),

        if (close != null) ...[
          const SizedBox(height: DesignSpacing.lg),
          SettingsGroupLabel(localOnly ? 'Latest till close' : 'Close details'),
          StaggeredItem(
            itemKey: 'eod-close-details',
            index: 2,
            child: GroupedCard(dividerIndent: 14, children: [
              if (localOnly)
                _summaryRow(
                    'Opening float',
                    _currencyFmt.format(asDouble(close['openingFloat'])),
                    isDark),
              if (localOnly)
                _summaryRow('Recorded cash sales',
                    _currencyFmt.format(asDouble(close['cashSales'])), isDark),
              if (localOnly)
                _summaryRow(
                    'Cash debt collections',
                    _currencyFmt.format(asDouble(close['cashCollections'])),
                    isDark),
              if (localOnly && asDouble(close['voidedCashReceived']) > 0)
                _summaryRow(
                    'Cash received on voided sales',
                    _currencyFmt.format(asDouble(close['voidedCashReceived'])),
                    isDark),
              if (localOnly && asDouble(close['cashRefunds']) > 0)
                _summaryRow(
                    'Cash refunds from till',
                    '-${_currencyFmt.format(asDouble(close['cashRefunds']))}',
                    isDark),
              if (localOnly)
                _summaryRow(
                    'Supplier payments from till',
                    '-${_currencyFmt.format(asDouble(close['cashPayouts']))}',
                    isDark),
              if (localOnly)
                _summaryRow(
                    'Net cash movement',
                    _currencyFmt.format(asDouble(close['netCashMovement'])),
                    isDark),
              if (localOnly)
                _summaryRow(
                    'Expected cash',
                    _currencyFmt.format(asDouble(close['expectedCash'])),
                    isDark),
              _summaryRow('Counted cash',
                  _currencyFmt.format(asDouble(close['countedCash'])), isDark),
              _summaryRow(
                'Discrepancy',
                _currencyFmt.format(
                    asDouble(close['cashDiscrepancy'] ?? close['discrepancy'])),
                isDark,
              ),
            ]),
          ),
          const SizedBox(height: DesignSpacing.xl),
          Text(
            localOnly && closeNeedsReconciliation
                ? 'This close is out of date. Reconcile the new activity to keep the till record accurate.'
                : 'The day is already closed. Re-close only if you re-counted the till.',
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
            label: localOnly
                ? _isClosing
                    ? 'Saving close…'
                    : !localCloseStatusKnown
                        ? 'Refresh to verify close'
                        : closeNeedsReconciliation
                            ? 'Reconcile and re-close'
                            : close != null
                                ? 'Re-close day'
                                : 'Close end of day'
                : _isClosing
                    ? 'Closing…'
                    : summaryError != null
                        ? 'Reconnect to verify sales'
                        : closeError != null
                            ? 'Connect to check close status'
                            : !cashStatusKnown
                                ? 'Reconnect to verify till cash'
                                : closed
                                    ? 'Re-close day'
                                    : 'Close end of day',
            icon: Icons.check_circle_outline_rounded,
            onPressed: canClose && !_isClosing
                ? () => localOnly
                    ? _showLocalCloseSheet(
                        cashSales,
                        cashCollections: cashCollections,
                        cashPayouts: cashPayouts,
                        cashRefunds: cashRefunds,
                        voidedCashReceived: voidedCashReceived,
                        businessDate: businessDate,
                        existingClose: close,
                      )
                    : _showCloseSheet(
                        expectedCash,
                        businessDate: businessDate,
                      )
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

  Future<void> _showLocalCloseSheet(
    double cashSales, {
    required double cashCollections,
    required double cashPayouts,
    required double cashRefunds,
    required double voidedCashReceived,
    required String businessDate,
    Map<String, dynamic>? existingClose,
  }) async {
    if (_isClosing || !mounted) return;
    final auth = getIt<AuthService>();
    final branchId = auth.branchId;
    if (branchId == null) return;

    final openingController = TextEditingController(
      text: existingClose == null
          ? ''
          : asDouble(existingClose['openingFloat']).toStringAsFixed(2),
    );
    final movementController = TextEditingController(
      text: existingClose == null
          ? '0'
          : asDouble(existingClose['netCashMovement']).toStringAsFixed(2),
    );
    final countController = TextEditingController(
      text: existingClose == null
          ? ''
          : asDouble(existingClose['countedCash']).toStringAsFixed(2),
    );
    final notesController = TextEditingController(
      text: existingClose?['notes']?.toString() ?? '',
    );

    bool? confirmed;
    double? openingFloat;
    double? netCashMovement;
    double? countedCash;
    String? closeNotes;
    try {
      confirmed = await showModalBottomSheet<bool>(
        useRootNavigator: true,
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (ctx, setSheetState) {
            final opening = _parseCashCount(openingController.text);
            final movement = _parseSignedCash(movementController.text);
            final counted = _parseCashCount(countController.text);
            final expectedCents = opening == null || movement == null
                ? null
                : (opening * 100).round() +
                    (cashSales * 100).round() +
                    (cashCollections * 100).round() -
                    (cashPayouts * 100).round() +
                    (voidedCashReceived * 100).round() -
                    (cashRefunds * 100).round() +
                    (movement * 100).round();
            final expected = expectedCents == null ? null : expectedCents / 100;
            final discrepancy = expectedCents != null && counted != null
                ? ((counted * 100).round() - expectedCents) / 100
                : null;
            final movementNeedsNote =
                movement != null && (movement * 100).round() != 0;
            final discrepancyNeedsNote =
                discrepancy != null && discrepancy.abs() >= 0.01;
            final noteRequired = movementNeedsNote || discrepancyNeedsNote;
            final statusColor = discrepancy == null || discrepancy.abs() < 0.01
                ? DesignColors.success
                : discrepancy < 0
                    ? DesignColors.error
                    : DesignColors.warning;
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                DesignSpacing.xl,
                DesignSpacing.xs,
                DesignSpacing.xl,
                DesignSpacing.xl + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
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
                        'Business day $businessDate. Expected cash is opening float + cash sales + debt collections + cash received on voided sales − supplier payments − recorded cash refunds + other net cash movement.',
                        style: TextStyle(
                          color: isDark
                              ? DesignColors.darkTextSecondary
                              : DesignColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: DesignSpacing.md),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(DesignSpacing.md),
                        decoration: BoxDecoration(
                          color: DesignColors.info.withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusMd),
                        ),
                        child: Text(
                          'Cash sales: ${_currencyFmt.format(cashSales)}. Debt collections: ${_currencyFmt.format(cashCollections)}. Cash received on voided sales: ${_currencyFmt.format(voidedCashReceived)}. Supplier payments: ${_currencyFmt.format(cashPayouts)}. Recorded cash refunds: ${_currencyFmt.format(cashRefunds)}. Use net movement for other cash added or removed and explain it in the notes.',
                        ),
                      ),
                      const SizedBox(height: DesignSpacing.md),
                      TextField(
                        controller: openingController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [_cashAmountFormatter],
                        decoration: const InputDecoration(
                          labelText: 'Opening float (KES)',
                          prefixIcon: Icon(Icons.savings_outlined),
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      const SizedBox(height: DesignSpacing.sm),
                      TextField(
                        controller: movementController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        inputFormatters: [_signedCashAmountFormatter],
                        decoration: const InputDecoration(
                          labelText: 'Net cash movement (KES)',
                          helperText:
                              'Positive adds cash; negative removes cash.',
                          prefixIcon: Icon(Icons.swap_vert_rounded),
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      const SizedBox(height: DesignSpacing.sm),
                      TextField(
                        controller: countController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [_cashAmountFormatter],
                        decoration: const InputDecoration(
                          labelText: 'Counted cash in till (KES)',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      if (expected != null) ...[
                        const SizedBox(height: DesignSpacing.md),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(DesignSpacing.md),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusMd),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Expected cash  ${_currencyFmt.format(expected)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              if (discrepancy != null) ...[
                                const SizedBox(height: DesignSpacing.xs),
                                Text(
                                  discrepancy.abs() < 0.01
                                      ? 'Cash count matches'
                                      : discrepancy < 0
                                          ? 'Short by ${_currencyFmt.format(discrepancy.abs())}'
                                          : 'Over by ${_currencyFmt.format(discrepancy)}',
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: DesignSpacing.sm),
                      TextField(
                        controller: notesController,
                        decoration: InputDecoration(
                          labelText: noteRequired
                              ? 'Explain cash movement or difference'
                              : 'Close notes (optional)',
                          hintText: movementNeedsNote
                              ? 'Explain why cash was added or removed'
                              : 'Explain the cash difference',
                          prefixIcon: const Icon(Icons.notes_rounded),
                        ),
                        maxLines: 2,
                        maxLength: 240,
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      if (noteRequired &&
                          notesController.text.trim().isEmpty) ...[
                        const SizedBox(height: DesignSpacing.xs),
                        const Text(
                          'Add a note explaining the cash movement or difference before saving.',
                          style: TextStyle(
                            color: DesignColors.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: DesignSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(64, DesignSpacing.huge),
                          ),
                          onPressed: opening == null ||
                                  movement == null ||
                                  counted == null ||
                                  expected == null ||
                                  expected < 0 ||
                                  (noteRequired &&
                                      notesController.text.trim().isEmpty)
                              ? null
                              : () => Navigator.pop(sheetContext, true),
                          icon: const Icon(Icons.lock_rounded),
                          label: const Text('Save till close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      if (confirmed == true) {
        openingFloat = _parseCashCount(openingController.text);
        netCashMovement = _parseSignedCash(movementController.text);
        countedCash = _parseCashCount(countController.text);
        final notes = notesController.text.trim();
        closeNotes = notes.isEmpty ? null : notes;
      }
    } finally {
      openingController.dispose();
      movementController.dispose();
      countController.dispose();
      notesController.dispose();
    }

    if (confirmed != true ||
        !mounted ||
        openingFloat == null ||
        netCashMovement == null ||
        countedCash == null) {
      return;
    }

    setState(() => _isClosing = true);
    try {
      await getIt<AppDatabase>().saveLocalDailyClose(
        branchId: branchId,
        businessDate: businessDate,
        openingFloat: openingFloat,
        cashSales: cashSales,
        cashCollections: cashCollections,
        cashPayouts: cashPayouts,
        cashRefunds: cashRefunds,
        voidedCashReceived: voidedCashReceived,
        netCashMovement: netCashMovement,
        countedCash: countedCash,
        closedBy: auth.currentUser?['name']?.toString() ?? 'Owner',
        notes: closeNotes,
      );
      if (mounted) {
        ref.invalidate(_eodProvider);
        showGlassSnackBar(
          context,
          'Till close saved on this device',
          icon: Icons.check_circle_rounded,
          color: DesignColors.success,
        );
      }
    } catch (error) {
      if (mounted) {
        if (error is StateError) ref.invalidate(_eodProvider);
        showGlassSnackBar(
          context,
          error is StateError
              ? error.message.toString()
              : 'Could not save the till close. Your sales were not changed; try again.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isClosing = false);
    }
  }

  Future<void> _showCloseSheet(
    double? expectedCash, {
    required String businessDate,
  }) async {
    if (_isClosing || !mounted) return;
    final branchId = getIt<AuthService>().branchId;
    if (branchId == null) return;

    final countController = TextEditingController();
    final notesController = TextEditingController();

    bool? confirmed;
    double? countedCash;
    String? closeNotes;
    try {
      confirmed = await showModalBottomSheet<bool>(
        useRootNavigator: true,
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final counted = _parseCashCount(countController.text);
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
                child: SingleChildScrollView(
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
                            ? 'Closing business day $businessDate. System expects ${_currencyFmt.format(expectedCash)} in the till. Count it to finalize the day.'
                            : 'Closing business day $businessDate. Count the cash in the till to finalize the day.',
                        style: TextStyle(
                            color: isDark
                                ? DesignColors.darkTextSecondary
                                : DesignColors.textSecondary),
                      ),
                      const SizedBox(height: DesignSpacing.lg),
                      TextField(
                        controller: countController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final text = newValue.text;
                            return text.isEmpty ||
                                    RegExp(r'^(?:\d{0,12}(?:\.\d{0,2})?|\.\d{0,2})$')
                                        .hasMatch(text)
                                ? newValue
                                : oldValue;
                          }),
                        ],
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
                          onPressed: counted == null
                              ? null
                              : () => Navigator.pop(sheetContext, true),
                          child: const Text('Confirm & close day'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      if (confirmed == true) {
        countedCash = _parseCashCount(countController.text);
        final notes = notesController.text.trim();
        closeNotes = notes.isEmpty ? null : notes;
      }
    } finally {
      countController.dispose();
      notesController.dispose();
    }

    if (confirmed != true || !mounted || countedCash == null) return;
    setState(() => _isClosing = true);

    try {
      await getIt<ApiClient>().closeEndOfDay(
        branchId,
        countedCash: countedCash,
        // Close the exact branch-local business date returned with the report.
        date: businessDate,
        notes: closeNotes,
      );
      if (mounted) {
        ref.invalidate(_eodProvider);
        showGlassSnackBar(context, 'End of day closed',
            icon: Icons.check_circle_rounded, color: DesignColors.success);
      }
    } catch (e) {
      if (mounted) {
        // The server may have committed the close even if its response was
        // lost. Refresh the authoritative status so a safe retry does not
        // leave the screen claiming that the day is still open.
        ref.invalidate(_eodProvider);
        var closeConfirmed = false;
        try {
          final refreshed = await ref.read(_eodProvider.future);
          closeConfirmed = refreshed['close'] is Map<String, dynamic>;
        } catch (_) {
          // The screen's refreshed error state remains the source of truth.
        }
        if (!mounted) return;
        showGlassSnackBar(
          context,
          closeConfirmed
              ? 'End of day closed. The confirmation response was delayed.'
              : 'Close status refreshed. Check the latest status before retrying. ${apiErrorMessage(e)}',
          icon: closeConfirmed
              ? Icons.check_circle_rounded
              : Icons.info_outline_rounded,
          color: closeConfirmed ? DesignColors.success : DesignColors.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _isClosing = false);
    }
  }
}

final _cashAmountFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) => newValue.text.isEmpty ||
          RegExp(r'^(?:\d{0,12}(?:\.\d{0,2})?|\.\d{0,2})$')
              .hasMatch(newValue.text)
      ? newValue
      : oldValue,
);

final _signedCashAmountFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) => newValue.text.isEmpty ||
          RegExp(r'^-?(?:\d{0,12}(?:\.\d{0,2})?|\.\d{0,2})$')
              .hasMatch(newValue.text)
      ? newValue
      : oldValue,
);

double? _parseCashCount(String value) {
  final amount = double.tryParse(value.trim());
  if (amount == null || !amount.isFinite || amount < 0) return null;
  return amount;
}

double? _parseSignedCash(String value) {
  final amount = double.tryParse(value.trim());
  if (amount == null || !amount.isFinite) return null;
  return amount;
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
