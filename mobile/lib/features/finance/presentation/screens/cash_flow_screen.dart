import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'finance_screen.dart' show FinanceScreen;

enum CashFlowMode { cashOnly, allRevenue, runningBalance }

extension CashFlowModeWireFormat on CashFlowMode {
  String get wireName => switch (this) {
        CashFlowMode.cashOnly => 'CASH_ONLY',
        CashFlowMode.allRevenue => 'ALL_REVENUE',
        CashFlowMode.runningBalance => 'RUNNING_BALANCE',
      };

  String get label => switch (this) {
        CashFlowMode.cashOnly => 'Cash only',
        CashFlowMode.allRevenue => 'All revenue',
        CashFlowMode.runningBalance => 'Running balance',
      };

  String get description => switch (this) {
        CashFlowMode.cashOnly =>
          'Today\'s cash sales minus today\'s cash payouts. Resets every day — matches what\'s physically in the till.',
        CashFlowMode.allRevenue =>
          'Today\'s total revenue from any payment method, minus today\'s payouts.',
        CashFlowMode.runningBalance =>
          'A running balance carried forward across days, like a bank register.',
      };

  static CashFlowMode fromWire(String value) => switch (value) {
        'ALL_REVENUE' => CashFlowMode.allRevenue,
        'RUNNING_BALANCE' => CashFlowMode.runningBalance,
        _ => CashFlowMode.cashOnly,
      };
}

final _availableCashProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final branchId = getIt<AuthService>().branchId;
  if (branchId == null) return {};
  return getIt<ApiClient>().getAvailableCash(branchId);
});

class CashFlowScreen extends ConsumerStatefulWidget {
  const CashFlowScreen({super.key});

  @override
  ConsumerState<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends ConsumerState<CashFlowScreen> {
  bool _isChangingMode = false;

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionsProvider);
    final cashAsync = ref.watch(_availableCashProvider);

    if (!permissions.canViewCashFlow) {
      return const Scaffold(
        appBar: BrandedAppBar(title: 'Cash Flow'),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Restricted',
          subtitle: 'Only store managers and admins can view cash flow.',
        ),
      );
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Cash Flow',
        showBackButton: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_availableCashProvider),
          ),
        ],
      ),
      body: cashAsync.when(
        data: (data) {
          if (data.isEmpty) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'No branch selected',
              subtitle: 'Select a branch to view cash flow.',
            );
          }

          final mode = CashFlowModeWireFormat.fromWire(data['mode'] as String);
          final availableCash = (data['availableCash'] as num).toDouble();
          final todaysCashIn = (data['todaysCashIn'] as num).toDouble();
          final todaysCashOut = (data['todaysCashOut'] as num).toDouble();
          final breakdown = Map<String, dynamic>.from(data['breakdown'] as Map);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              MetricCard(
                title: 'Available to restock',
                value: FinanceScreen.currencyFmt.format(availableCash),
                icon: Icons.account_balance_wallet_rounded,
                color: availableCash > 0
                    ? DesignColors.success
                    : DesignColors.error,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      title: 'Cash in today',
                      value: FinanceScreen.currencyFmt.format(todaysCashIn),
                      icon: Icons.arrow_downward_rounded,
                      color: DesignColors.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricCard(
                      title: 'Cash out today',
                      value: FinanceScreen.currencyFmt.format(todaysCashOut),
                      icon: Icons.arrow_upward_rounded,
                      color: DesignColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SettingsGroupLabel('CALCULATION MODE'),
              GroupedCard(
                children: CashFlowMode.values
                    .map((m) => SettingsRow(
                          icon: Icons.calculate_outlined,
                          title: m.label,
                          subtitle: m.description,
                          trailing: _isChangingMode
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(
                                  m == mode
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: m == mode
                                      ? DesignColors.accent
                                      : DesignColors.textTertiary,
                                ),
                          onTap: _isChangingMode ? null : () => _changeMode(m),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 20),
              const SettingsGroupLabel('TODAY\'S BREAKDOWN'),
              GroupedCard(
                children: [
                  if (breakdown['salesCashIn'] != null)
                    SettingsRow(
                      icon: Icons.point_of_sale_rounded,
                      iconColor: DesignColors.success,
                      title: 'Cash sales',
                      trailing: Text(FinanceScreen.currencyFmt
                          .format((breakdown['salesCashIn'] as num).toDouble())),
                    ),
                  if (breakdown['allRevenue'] != null)
                    SettingsRow(
                      icon: Icons.point_of_sale_rounded,
                      iconColor: DesignColors.success,
                      title: 'Total revenue',
                      trailing: Text(FinanceScreen.currencyFmt
                          .format((breakdown['allRevenue'] as num).toDouble())),
                    ),
                  if (breakdown['runningBalance'] != null)
                    SettingsRow(
                      icon: Icons.savings_outlined,
                      iconColor: DesignColors.success,
                      title: 'Running balance',
                      trailing: Text(FinanceScreen.currencyFmt
                          .format((breakdown['runningBalance'] as num).toDouble())),
                    ),
                  SettingsRow(
                    icon: Icons.local_shipping_outlined,
                    iconColor: DesignColors.error,
                    title: 'Restock purchases',
                    trailing: Text(FinanceScreen.currencyFmt
                        .format((breakdown['restockOut'] as num).toDouble())),
                  ),
                  SettingsRow(
                    icon: Icons.receipt_long_outlined,
                    iconColor: DesignColors.error,
                    title: 'Expenses',
                    trailing: Text(FinanceScreen.currencyFmt
                        .format((breakdown['expenseOut'] as num).toDouble())),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              GroupedCard(
                children: [
                  SettingsRow(
                    icon: Icons.calculate_rounded,
                    title: 'Cash Reconciliation',
                    subtitle: 'Count the till and compare against this figure',
                    onTap: () => context.push('/cash-flow/reconciliation'),
                  ),
                  SettingsRow(
                    icon: Icons.event_available_rounded,
                    title: 'End of Day',
                    subtitle: "Close the day's sales & count the till",
                    onTap: () => context.push('/cash-flow/end-of-day'),
                  ),
                ],
              ),
            ],
          );
        },
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: List.generate(
              3,
              (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: ShimmerWidget(
                        width: double.infinity, height: 90, borderRadius: 14),
                  )),
        ),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load cash flow',
          subtitle: 'Check your connection and try again.',
          iconColor: DesignColors.error,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(_availableCashProvider),
        ),
      ),
    );
  }

  Future<void> _changeMode(CashFlowMode mode) async {
    final branchId = getIt<AuthService>().branchId;
    if (branchId == null) return;

    setState(() => _isChangingMode = true);
    try {
      await getIt<ApiClient>().updateCashFlowSettings(branchId, mode.wireName);
      ref.invalidate(_availableCashProvider);
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Could not change mode: $e',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _isChangingMode = false);
    }
  }
}
