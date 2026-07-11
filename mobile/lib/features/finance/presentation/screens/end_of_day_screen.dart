import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
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
  final results = await Future.wait([
    api.getSalesDailySummary(branchId, date),
    api.getAvailableCash(branchId).catchError((_) => <String, dynamic>{}),
    api.getDailyClose(branchId, date: date).then<Map<String, dynamic>?>((v) => v).catchError((_) => null),
  ]);
  return {
    'summary': results[0] as Map<String, dynamic>,
    'cash': results[1] as Map<String, dynamic>,
    'close': results[2],
  };
});

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
          return _buildBody(summary, cash, close);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: "Couldn't load today's figures",
          subtitle: 'Check your connection and try again.',
          iconColor: DesignColors.error,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(_eodProvider),
        ),
      ),
    );
  }

  Widget _buildBody(
    Map<String, dynamic> summary,
    Map<String, dynamic> cash,
    Map<String, dynamic>? close,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final closed = close != null;

    final totalSales = (summary['totalSales'] as num?)?.toDouble() ?? 0;
    final txns = (summary['totalTransactions'] as num?)?.toInt() ?? 0;
    final cashSales = (summary['cashSales'] as num?)?.toDouble() ?? 0;
    final mpesaSales = (summary['mpesaSales'] as num?)?.toDouble() ?? 0;
    final creditSales = (summary['creditSales'] as num?)?.toDouble() ?? 0;
    final expectedCash = (cash['availableCash'] as num?)?.toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Status banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (closed ? DesignColors.success : DesignColors.accent)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                closed ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: closed ? DesignColors.success : DesignColors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  closed
                      ? 'Day closed${close['closedByName'] != null ? ' by ${close['closedByName']}' : ''}'
                          '${_closedAtSuffix(close)}'
                      : 'Today is still open',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        const SettingsGroupLabel("Today's sales"),
        GroupedCard(children: [
          _summaryRow('Total sales', _currencyFmt.format(totalSales), isDark, bold: true),
          _summaryRow('Transactions', '$txns', isDark),
          _summaryRow('Cash', _currencyFmt.format(cashSales), isDark),
          _summaryRow('M-Pesa', _currencyFmt.format(mpesaSales), isDark),
          _summaryRow('Credit', _currencyFmt.format(creditSales), isDark),
          if (expectedCash != null)
            _summaryRow('Expected cash in till', _currencyFmt.format(expectedCash), isDark),
        ]),

        if (closed) ...[
          const SizedBox(height: 16),
          const SettingsGroupLabel('Close details'),
          GroupedCard(children: [
            _summaryRow('Counted cash', _currencyFmt.format((close['countedCash'] as num).toDouble()), isDark),
            _summaryRow(
              'Discrepancy',
              _currencyFmt.format((close['cashDiscrepancy'] as num).toDouble()),
              isDark,
            ),
          ]),
          const SizedBox(height: 20),
          Text(
            'The day is already closed. Re-close only if you re-counted the till.',
            style: TextStyle(
              color: isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
        ],

        const SizedBox(height: 20),
        GradientButton(
          label: closed ? 'Re-close day' : 'Close end of day',
          icon: Icons.check_circle_outline_rounded,
          onPressed: () => _showCloseSheet(expectedCash),
          height: 52,
          borderRadius: 12,
        ),
      ],
    );
  }

  String _closedAtSuffix(Map<String, dynamic> close) {
    final at = DateTime.tryParse(close['closedAt'] as String? ?? '');
    return at != null ? ' at ${_timeFmt.format(at)}' : '';
  }

  Widget _summaryRow(String label, String value, bool isDark, {bool bold = false}) {
    final textColor = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondary = isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: secondary, fontSize: 14))),
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
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final counted = double.tryParse(countController.text);
          final discrepancy =
              (counted != null && expectedCash != null) ? counted - expectedCash : null;
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 4, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Close end of day',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  expectedCash != null
                      ? 'System expects ${_currencyFmt.format(expectedCash)} in the till. Count it to finalize the day.'
                      : 'Count the cash in the till to finalize the day.',
                  style: TextStyle(
                      color: isDark
                          ? DesignColors.darkTextSecondary
                          : DesignColors.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: countController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Counted cash in till (KES)',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                  maxLines: 2,
                ),
                if (discrepancy != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (discrepancy.abs() < 0.01
                              ? DesignColors.success
                              : discrepancy < 0
                                  ? DesignColors.error
                                  : DesignColors.warning)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: counted == null || counted < 0
                        ? null
                        : () => Navigator.pop(sheetContext, true),
                    child: const Text('Confirm & close day'),
                  ),
                ),
              ],
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
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      );
      ref.invalidate(_eodProvider);
      if (mounted) {
        showGlassSnackBar(context, 'End of day closed',
            icon: Icons.check_circle_rounded, color: DesignColors.success);
      }
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Could not close the day. Please try again.',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    }
  }
}
