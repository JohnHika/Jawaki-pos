import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/app_roles.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/load_error.dart';
import '../../../../core/widgets/motion.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../desktop/desktop_cash_flow_view.dart';
import '../desktop/desktop_figures_row.dart';
import '../desktop/desktop_finance_tabs.dart';
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

final _localCashActivityProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final auth = getIt<AuthService>();
  final branchId = auth.branchId;
  if (branchId == null || branchId.isEmpty) return const {};
  final db = getIt<AppDatabase>();
  final now = DateTime.now();
  final summary = await db.getDailySalesSummary(branchId, now);
  final businessDate =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final close = await db.getLatestLocalDailyClose(
    branchId: branchId,
    businessDate: businessDate,
  );
  return <String, dynamic>{
    'summary': summary,
    'latestClose': close,
    'businessDate': businessDate,
  };
});

class CashFlowScreen extends ConsumerStatefulWidget {
  const CashFlowScreen({super.key});

  @override
  ConsumerState<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends ConsumerState<CashFlowScreen> {
  bool _isChangingMode = false;

  Widget _financeTabs(RolePermissions permissions) => DesktopFinanceTabs(
        current: FinanceSection.cashFlow,
        available: DesktopFinanceTabs.forRole(
          canViewFinance: permissions.canViewFinance,
          canViewCashFlow: permissions.canViewCashFlow,
        ),
      );

  /// The Cash flow page inside the desktop shell, for both kinds of shop.
  Widget _buildDesktop(RolePermissions permissions) {
    if (!permissions.canViewCashFlow) {
      return const Scaffold(
        body: DesktopEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Cash flow is restricted',
          message: 'Only store managers and admins can view cash flow.',
        ),
      );
    }
    final local = getIt<AuthService>().isLocalWorkspace;
    final async =
        ref.watch(local ? _localCashActivityProvider : _availableCashProvider);
    void refresh() => ref.invalidate(
        local ? _localCashActivityProvider : _availableCashProvider);
    final currency = FinanceScreen.currencyFmt;

    DesktopCashFlowView view({
      List<DesktopFigure> figures = const [],
      List<CashLedgerLine> lines = const [],
      String totalLabel = '',
      double total = 0,
      String? dateLabel,
      Widget? side,
      String? footnote,
      bool loading = false,
      String? errorMessage,
      String? emptyTitle,
      String? emptyMessage,
      VoidCallback? onRetry,
    }) =>
        DesktopCashFlowView(
          title: 'Cash flow',
          figures: figures,
          lines: lines,
          totalLabel: totalLabel,
          total: total,
          dateLabel: dateLabel,
          headerBottom: _financeTabs(permissions),
          onRefresh: refresh,
          side: side,
          footnote: footnote,
          loading: loading,
          errorMessage: errorMessage,
          onRetry: onRetry,
          emptyTitle: emptyTitle,
          emptyMessage: emptyMessage,
        );

    return Scaffold(
      body: async.when(
        loading: () => view(loading: true),
        error: (e, _) => view(
          errorMessage: loadErrorSubtitle(e),
          onRetry: isPermissionDenied(e) ? null : refresh,
        ),
        data: (data) {
          if (data.isEmpty) {
            return view(
              emptyTitle: local ? 'No shop selected' : 'No branch selected',
              emptyMessage: local
                  ? 'Choose or create a local shop to view cash activity.'
                  : 'Select a branch to view cash flow.',
            );
          }
          if (local) {
            final summary = Map<String, dynamic>.from(data['summary'] as Map);
            double n(String k) => (summary[k] as num? ?? 0).toDouble();
            final sales = n('cashSales');
            final collections = n('cashCollections');
            final voided = n('voidedCashReceived');
            final refunds = n('cashRefunds');
            final payouts = n('cashPayouts');
            final transactions = (summary['totalTransactions'] as num? ?? 0).toInt();
            final close = data['latestClose'] as Map<String, dynamic>?;
            final date = DateTime.tryParse(data['businessDate'] as String);
            final closedAt = DateTime.tryParse(
                    close?['closedAt']?.toString() ?? '')
                ?.toLocal();
            final net = sales + collections + voided - refunds - payouts;
            return view(
              dateLabel:
                  date == null ? 'Today' : DateFormat('EEEE, d MMMM').format(date),
              figures: [
                DesktopFigure(
                  label: 'Cash sales',
                  value: currency.format(sales),
                  hint: '$transactions ${transactions == 1 ? 'sale' : 'sales'}',
                ),
                DesktopFigure(
                  label: 'Debt collected',
                  value: currency.format(collections),
                ),
                DesktopFigure(
                  label: 'Paid out of the till',
                  value: payouts + refunds > 0
                      ? '-${currency.format(payouts + refunds)}'
                      : currency.format(0),
                  hint: 'Suppliers and refunds',
                ),
                DesktopFigure(
                  label: 'Net cash movement',
                  value: net < 0
                      ? '-${currency.format(-net)}'
                      : currency.format(net),
                  hint: 'Before the opening float',
                  valueColor: net < 0 ? negativeAmountColor(context.desktop) : null,
                ),
              ],
              lines: [
                CashLedgerLine('Cash sales', sales),
                CashLedgerLine('Debt collected', collections),
                if (voided > 0)
                  CashLedgerLine('Cash received on voided sales', voided),
                if (refunds > 0) CashLedgerLine('Cash refunded', -refunds),
                CashLedgerLine('Supplier payments from the till', -payouts),
              ],
              totalLabel: 'Net cash movement',
              total: net,
              side: DesktopTillCountPanel(
                counted: close != null,
                expected: (close?['expectedCash'] as num? ?? 0).toDouble(),
                countedCash: (close?['countedCash'] as num? ?? 0).toDouble(),
                difference: (close?['cashDiscrepancy'] as num? ?? 0).toDouble(),
                closedAtLabel:
                    closedAt == null ? null : DateFormat('h:mm a').format(closedAt),
                onClose: () async {
                  await context.push<void>('/cash-flow/end-of-day');
                  if (mounted) ref.invalidate(_localCashActivityProvider);
                },
                onHistory: () async {
                  await context.push<void>('/cash-flow/reconciliation');
                  if (mounted) ref.invalidate(_localCashActivityProvider);
                },
              ),
              footnote: 'These figures include completed cash sales, cash '
                  'received on voided sales, debt collections, recorded cash '
                  'refunds and supplier payments from this branch’s till. They '
                  'do not include the opening float, unrecorded expenses, a '
                  'bank balance or payment-provider confirmations.',
            );
          }

          final mode = CashFlowModeWireFormat.fromWire(data['mode'] as String);
          final available = (data['availableCash'] as num).toDouble();
          final cashIn = (data['todaysCashIn'] as num).toDouble();
          final cashOut = (data['todaysCashOut'] as num).toDouble();
          final breakdown = Map<String, dynamic>.from(data['breakdown'] as Map);
          double? b(String k) => (breakdown[k] as num?)?.toDouble();
          return view(
            dateLabel: 'Today',
            figures: [
              DesktopFigure(
                label: 'Available to restock',
                value: available < 0
                    ? '-${currency.format(-available)}'
                    : currency.format(available),
                hint: mode.label,
                valueColor:
                    available <= 0 ? negativeAmountColor(context.desktop) : null,
              ),
              DesktopFigure(label: 'Cash in today', value: currency.format(cashIn)),
              DesktopFigure(
                label: 'Cash out today',
                value: cashOut > 0
                    ? '-${currency.format(cashOut)}'
                    : currency.format(0),
              ),
            ],
            lines: [
              if (b('salesCashIn') != null)
                CashLedgerLine('Cash sales', b('salesCashIn')!),
              if (b('allRevenue') != null)
                CashLedgerLine('Total revenue', b('allRevenue')!),
              if (b('runningBalance') != null)
                CashLedgerLine('Running balance', b('runningBalance')!),
              CashLedgerLine('Restock purchases', -(b('restockOut') ?? 0)),
              CashLedgerLine('Expenses', -(b('expenseOut') ?? 0)),
            ],
            totalLabel: 'Available to restock',
            total: available,
            side: DesktopCashModePanel(
              options: [
                for (final m in CashFlowMode.values)
                  (id: m.name, label: m.label, description: m.description),
              ],
              selectedId: mode.name,
              changing: _isChangingMode,
              onChanged: (id) =>
                  _changeMode(CashFlowMode.values.firstWhere((m) => m.name == id)),
              onReconcile: () => context.push('/cash-flow/reconciliation'),
              onEndOfDay: () => context.push('/cash-flow/end-of-day'),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionsProvider);
    if (context.inDesktopShell) return _buildDesktop(permissions);
    if (getIt<AuthService>().isLocalWorkspace) {
      return _buildLocalCashFlow(context, permissions);
    }
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
            padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                DesignSpacing.md, DesignSpacing.lg, DesignSpacing.xxl),
            children: [
              StaggeredItem(
                itemKey: 'cashflow-metrics',
                child: MetricCard(
                  title: 'Available to restock',
                  value: FinanceScreen.currencyFmt.format(availableCash),
                  icon: Icons.account_balance_wallet_rounded,
                  color: availableCash > 0
                      ? DesignColors.success
                      : DesignColors.error,
                ),
              ),
              const SizedBox(height: DesignSpacing.md),
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
                  const SizedBox(width: DesignSpacing.md),
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
              const SizedBox(height: DesignSpacing.xl),
              const SettingsGroupLabel('CALCULATION MODE'),
              GroupedCard(
                children: CashFlowMode.values
                    .map((m) => SettingsRow(
                          icon: Icons.calculate_outlined,
                          title: m.label,
                          subtitle: m.description,
                          subtitleMaxLines: 5,
                          trailing: _isChangingMode
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
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
              const SizedBox(height: DesignSpacing.xl),
              const SettingsGroupLabel('TODAY\'S BREAKDOWN'),
              StaggeredItem(
                itemKey: 'cashflow-shortcuts',
                index: 1,
                child: GroupedCard(
                  children: [
                    if (breakdown['salesCashIn'] != null)
                      SettingsRow(
                        icon: Icons.point_of_sale_rounded,
                        iconColor: DesignColors.success,
                        title: 'Cash sales',
                        trailing: Text(FinanceScreen.currencyFmt.format(
                            (breakdown['salesCashIn'] as num).toDouble())),
                      ),
                    if (breakdown['allRevenue'] != null)
                      SettingsRow(
                        icon: Icons.point_of_sale_rounded,
                        iconColor: DesignColors.success,
                        title: 'Total revenue',
                        trailing: Text(FinanceScreen.currencyFmt.format(
                            (breakdown['allRevenue'] as num).toDouble())),
                      ),
                    if (breakdown['runningBalance'] != null)
                      SettingsRow(
                        icon: Icons.savings_outlined,
                        iconColor: DesignColors.success,
                        title: 'Running balance',
                        trailing: Text(FinanceScreen.currencyFmt.format(
                            (breakdown['runningBalance'] as num).toDouble())),
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
              ),
              const SizedBox(height: DesignSpacing.xl),
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
          padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.md,
              DesignSpacing.lg, DesignSpacing.xxl),
          children: List.generate(
              3,
              (_) => const Padding(
                    padding: EdgeInsets.only(bottom: DesignSpacing.md),
                    child: ShimmerWidget(
                        width: double.infinity,
                        height: 90,
                        borderRadius: DesignSpacing.radiusLg),
                  )),
        ),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load cash flow',
          subtitle: loadErrorSubtitle(e),
          iconColor: DesignColors.error,
          actionLabel: isPermissionDenied(e) ? null : 'Retry',
          onAction: isPermissionDenied(e)
              ? null
              : () => ref.invalidate(_availableCashProvider),
        ),
      ),
    );
  }

  Widget _buildLocalCashFlow(
    BuildContext context,
    RolePermissions permissions,
  ) {
    final activityAsync = ref.watch(_localCashActivityProvider);
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
            onPressed: () => ref.invalidate(_localCashActivityProvider),
          ),
        ],
      ),
      body: activityAsync.when(
        data: (activity) {
          if (activity.isEmpty) {
            return const EmptyState(
              icon: Icons.store_mall_directory_outlined,
              title: 'No shop selected',
              subtitle: 'Choose or create a local shop to view cash activity.',
            );
          }
          final summary = Map<String, dynamic>.from(activity['summary'] as Map);
          final sales = (summary['cashSales'] as num? ?? 0).toDouble();
          final collections =
              (summary['cashCollections'] as num? ?? 0).toDouble();
          final voidedCashReceived =
              (summary['voidedCashReceived'] as num? ?? 0).toDouble();
          final cashRefunds = (summary['cashRefunds'] as num? ?? 0).toDouble();
          final supplierCashOut =
              (summary['cashPayouts'] as num? ?? 0).toDouble();
          final transactions =
              (summary['totalTransactions'] as num? ?? 0).toInt();
          final close = activity['latestClose'] as Map<String, dynamic>?;
          final date = DateTime.tryParse(activity['businessDate'] as String);
          final dateLabel =
              date == null ? 'Today' : DateFormat('EEEE, d MMMM').format(date);

          return RefreshIndicator(
            onRefresh: () async {
              try {
                await ref
                    .refresh(_localCashActivityProvider.future)
                    .then<void>((_) {});
              } catch (_) {
                // The provider renders its retry state after a failed refresh.
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                DesignSpacing.lg,
                DesignSpacing.md,
                DesignSpacing.lg,
                DesignSpacing.xxl,
              ),
              children: [
                Text(dateLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: DesignColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        )),
                const SizedBox(height: DesignSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        title: 'Cash sales',
                        value: FinanceScreen.currencyFmt.format(sales),
                        icon: Icons.point_of_sale_rounded,
                        color: DesignColors.success,
                      ),
                    ),
                    const SizedBox(width: DesignSpacing.md),
                    Expanded(
                      child: MetricCard(
                        title: 'Debt collected',
                        value: FinanceScreen.currencyFmt.format(collections),
                        icon: Icons.call_received_rounded,
                        color: DesignColors.accent,
                      ),
                    ),
                  ],
                ),
                if (voidedCashReceived > 0 || cashRefunds > 0) ...[
                  const SizedBox(height: DesignSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          title: 'Cash received on voids',
                          value: FinanceScreen.currencyFmt
                              .format(voidedCashReceived),
                          icon: Icons.undo_rounded,
                          color: DesignColors.warning,
                        ),
                      ),
                      const SizedBox(width: DesignSpacing.md),
                      Expanded(
                        child: MetricCard(
                          title: 'Cash refunded',
                          value: FinanceScreen.currencyFmt.format(cashRefunds),
                          icon: Icons.outbox_rounded,
                          color: DesignColors.error,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: DesignSpacing.md),
                MetricCard(
                  title: 'Supplier payments from till',
                  value: FinanceScreen.currencyFmt.format(supplierCashOut),
                  icon: Icons.outbox_rounded,
                  color: DesignColors.error,
                ),
                const SizedBox(height: DesignSpacing.md),
                MetricCard(
                  title: 'Sales transactions',
                  value: transactions.toString(),
                  icon: Icons.receipt_long_outlined,
                  color: DesignColors.info,
                ),
                const SizedBox(height: DesignSpacing.lg),
                _LocalTillCloseCard(
                  close: close,
                  onClose: () async {
                    await context.push<void>('/cash-flow/end-of-day');
                    if (mounted) ref.invalidate(_localCashActivityProvider);
                  },
                  onHistory: () async {
                    await context.push<void>('/cash-flow/reconciliation');
                    if (mounted) ref.invalidate(_localCashActivityProvider);
                  },
                ),
                const SizedBox(height: DesignSpacing.md),
                Container(
                  padding: const EdgeInsets.all(DesignSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                  child: Text(
                    'These figures include completed cash sales, cash received on voided sales, debt collections, recorded cash refunds, and supplier payments from this branch’s till. They do not include the opening float, unrecorded expenses, a bank balance, or payment-provider confirmations.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DesignColors.textSecondary,
                          height: 1.4,
                        ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load cash activity',
          subtitle: loadErrorSubtitle(error),
          iconColor: DesignColors.error,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(_localCashActivityProvider),
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
        showGlassSnackBar(
            context, 'Could not change cash flow mode. ${apiErrorMessage(e)}',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _isChangingMode = false);
    }
  }
}

class _LocalTillCloseCard extends StatelessWidget {
  const _LocalTillCloseCard({
    required this.close,
    required this.onClose,
    required this.onHistory,
  });

  final Map<String, dynamic>? close;
  final Future<void> Function() onClose;
  final Future<void> Function() onHistory;

  @override
  Widget build(BuildContext context) {
    final closed = close != null;
    final expected = (close?['expectedCash'] as num? ?? 0).toDouble();
    final counted = (close?['countedCash'] as num? ?? 0).toDouble();
    final difference = (close?['cashDiscrepancy'] as num? ?? 0).toDouble();
    final closedAt =
        DateTime.tryParse(close?['closedAt']?.toString() ?? '')?.toLocal();
    final currency = FinanceScreen.currencyFmt;

    return GroupedCard(
      children: [
        SettingsRow(
          icon: closed ? Icons.task_alt_rounded : Icons.pending_actions_rounded,
          iconColor: closed ? DesignColors.success : DesignColors.warning,
          title: closed ? 'Till counted today' : 'Till not counted today',
          subtitle: closedAt == null
              ? 'Close the day to compare expected and counted cash.'
              : 'Last count ${DateFormat('h:mm a').format(closedAt)}',
          subtitleMaxLines: 2,
        ),
        if (closed) ...[
          SettingsRow(
            icon: Icons.calculate_outlined,
            title: 'Expected cash',
            trailing: Text(currency.format(expected)),
          ),
          SettingsRow(
            icon: Icons.payments_outlined,
            title: 'Counted cash',
            trailing: Text(currency.format(counted)),
          ),
          if (difference.abs() >= 0.01)
            SettingsRow(
              icon: Icons.compare_arrows_rounded,
              iconColor:
                  difference < 0 ? DesignColors.error : DesignColors.warning,
              title: difference < 0 ? 'Shortfall' : 'Overage',
              trailing: Text(currency.format(difference.abs())),
            ),
        ],
        SettingsRow(
          icon: Icons.event_available_rounded,
          title: closed ? 'Review or close again' : 'Close the day',
          subtitle: closed
              ? 'Record a new count if sales changed after closing.'
              : 'Count the till and save an auditable close.',
          onTap: onClose,
        ),
        SettingsRow(
          icon: Icons.history_rounded,
          title: 'Close history',
          subtitle: 'Review previous till counts and differences.',
          onTap: onHistory,
        ),
      ],
    );
  }
}
