import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../sales/presentation/providers/payment_provider.dart';

/// Payments Hub - overview of today's takings plus real links into
/// Receipts, Payment Analytics, and Customer Credit/Installments.
class PaymentsHubScreen extends ConsumerStatefulWidget {
  const PaymentsHubScreen({super.key});

  @override
  ConsumerState<PaymentsHubScreen> createState() => _PaymentsHubScreenState();
}

class _PaymentsHubScreenState extends ConsumerState<PaymentsHubScreen> {
  late final AppDatabase _db;
  List<PendingSale> _todaysSales = [];
  // The server figures cover every device in this branch. Only local offline
  // sales that are not yet present on the server are added to those totals.
  double _serverTotal = 0;
  int _serverCount = 0;
  bool _cloudTotalsAvailable = false;
  bool _canReconcileLocalSales = false;
  Set<String> _serverOfflineSaleIds = const {};
  int _serverRefreshGeneration = 0;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _merchantCharges = const [];

  @override
  void initState() {
    super.initState();
    _db = getIt<AppDatabase>();
    _loadData();
  }

  StreamSubscription<List<PendingSale>>? _salesSub;

  @override
  void dispose() {
    _salesSub?.cancel();
    super.dispose();
  }

  /// Follows today's sales live, so a sale rung up while this tab sits in the
  /// background shows in "Today's Takings" instead of a stale first read.
  Future<void> _loadData() async {
    unawaited(_refreshMerchantCharges());
    await _salesSub?.cancel();
    _serverRefreshGeneration++;
    setState(() {
      _isLoading = true;
      _error = null;
      _cloudTotalsAvailable = false;
      _canReconcileLocalSales = false;
      _serverOfflineSaleIds = const {};
      _serverTotal = 0;
      _serverCount = 0;
    });
    final branchId = getIt<AuthService>().branchId;
    final salesStream = branchId == null
        ? _db.watchTodaysSales().map((sales) => sales
            .where((sale) => sale.status.toUpperCase() == 'COMPLETED')
            .toList())
        : _db.watchCompletedSalesForBranchToday(branchId);
    _salesSub = salesStream.listen(
      (sales) {
        if (!mounted) return;
        setState(() {
          _todaysSales = sales;
          _isLoading = false;
        });
        unawaited(_refreshServerTotals());
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      },
    );
  }

  Future<void> _refreshMerchantCharges() async {
    try {
      final rows = await getIt<ApiClient>().getRecentMerchantCharges();
      if (mounted) setState(() => _merchantCharges = rows);
    } catch (_) {
      // Offline takings remain available from the local database.
    }
  }

  Future<void> _checkMerchantCharge(String reference) async {
    try {
      final charge = await getIt<ApiClient>().getMerchantMpesaStatus(reference);
      await _refreshMerchantCharges();
      await _refreshServerTotals();
      if (!mounted) return;
      final status = charge['status']?.toString() ?? 'PENDING';
      ref.read(paymentProvider.notifier).acknowledgeMerchantPayment(reference, status);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        status == 'COMPLETED'
            ? 'Payment confirmed. Receipt ${charge['receiptNumber'] ?? reference} is saved.'
            : status == 'NEEDS_REVIEW'
                ? 'Payment needs review. Give support reference $reference.'
                : 'Payment status: $status · $reference',
      )));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not check payment yet. Try again when online.')),
        );
      }
    }
  }

  Future<void> _refreshServerTotals() async {
    final generation = ++_serverRefreshGeneration;
    final branchId = getIt<AuthService>().branchId;
    if (branchId == null) {
      if (mounted) {
        setState(() {
          _cloudTotalsAvailable = false;
          _canReconcileLocalSales = false;
        });
      }
      return;
    }
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final api = getIt<ApiClient>();
    Map<String, dynamic> summary;
    try {
      summary = await api
          .getSalesDailySummary(branchId, today)
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      if (!mounted || generation != _serverRefreshGeneration) return;
      setState(() {
        _cloudTotalsAvailable = false;
        _canReconcileLocalSales = false;
      });
      return;
    }

    if (!mounted || generation != _serverRefreshGeneration) return;
    setState(() {
      _serverTotal = (summary['totalSales'] as num?)?.toDouble() ?? 0;
      _serverCount = (summary['totalTransactions'] as num?)?.toInt() ?? 0;
      _cloudTotalsAvailable = true;
      _canReconcileLocalSales = false;
    });

    try {
      final offlineIds = _todaysSales
          .where((sale) => !sale.isSynced)
          .map((sale) => sale.id)
          .toList();
      final presentOnServer = <String>{};
      for (var offset = 0; offset < offlineIds.length; offset += 500) {
        final batch = offlineIds.skip(offset).take(500).toList();
        presentOnServer.addAll(await api.getSyncedOfflineSaleIds(
          branchId: branchId,
          offlineIds: batch,
        ));
      }
      if (!mounted || generation != _serverRefreshGeneration) return;
      setState(() {
        _serverOfflineSaleIds = presentOnServer;
        _canReconcileLocalSales = true;
      });
    } catch (_) {
      // Keep authoritative shop-wide figures, and visibly indicate when local
      // offline sales could not be reconciled instead of double-counting them.
      if (mounted && generation == _serverRefreshGeneration) {
        setState(() => _canReconcileLocalSales = false);
      }
    }
  }

  List<PendingSale> get _localSalesMissingFromServer {
    if (!_canReconcileLocalSales) return const [];
    return _todaysSales
        .where((sale) =>
            !sale.isSynced && !_serverOfflineSaleIds.contains(sale.id))
        .toList();
  }

  double get _todaysTotal {
    if (!_cloudTotalsAvailable) {
      return _todaysSales.fold<double>(0.0, (sum, sale) => sum + sale.total);
    }
    return _serverTotal + _localSalesMissingFromServer.fold<double>(
        0, (sum, sale) => sum + sale.total);
  }

  int get _todaysTransactionCount => _cloudTotalsAvailable
      ? _serverCount + _localSalesMissingFromServer.length
      : _todaysSales.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Payments',
        showBackButton: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => context.push('/receipts'),
            tooltip: 'View Receipts',
          ),
        ],
      ),
      body: _error != null
          ? EmptyState(
              icon: Icons.error_outline_rounded,
              title: "Couldn't load payment data",
              subtitle: 'Check your connection and try again.',
              actionLabel: 'Retry',
              iconColor: DesignColors.error,
              onAction: _loadData,
            )
          : RefreshIndicator(
              color: DesignColors.brand,
              onRefresh: _loadData,
              child: PageContainer(
                withScroll: true,
                padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.lg, DesignSpacing.lg, DesignSpacing.xxl + DesignSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Payment Management',
                      subtitle: "Today's takings, receipts, and credit",
                      icon: Icons.payments_rounded,
                    ),
                    const SizedBox(height: DesignSpacing.sm),

                    // Today's summary
                    StaggeredItem(
                      itemKey: 'payments-takings',
                      child:
                      GlassCard(
                        padding: const EdgeInsets.all(DesignSpacing.xl),
                        borderRadius: DesignSpacing.radiusLg,
                        blur: 12,
                        gradient: const LinearGradient(
                          colors: [DesignColors.brand, DesignColors.brandDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(DesignSpacing.sm),
                                  decoration: BoxDecoration(
                                    color: DesignColors.textOnBrand.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd - 2),
                                  ),
                                  child: const Icon(Icons.today_rounded,
                                      color: DesignColors.textOnBrand, size: 24),
                                ),
                                const SizedBox(width: DesignSpacing.md),
                                Text(
                                  "Today's Takings",
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: DesignColors.textOnBrand,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (_cloudTotalsAvailable &&
                                !_canReconcileLocalSales &&
                                _todaysSales.any((sale) => !sale.isSynced)) ...[
                              const SizedBox(height: DesignSpacing.sm),
                              Text(
                                'Offline sales are waiting to sync.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: DesignColors.textOnBrand
                                          .withValues(alpha: 0.8),
                                    ),
                              ),
                            ],
                            const SizedBox(height: DesignSpacing.xl),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildGlassStatItem(
                                  label: 'Total Sales',
                                  value: _isLoading
                                      ? '...'
                                      : 'KES ${NumberFormat('#,##0').format(_todaysTotal)}',
                                  icon: Icons.point_of_sale_rounded,
                                ),
                                _buildGlassStatItem(
                                  label: 'Transactions',
                                  value: _isLoading
                                      ? '...'
                                      : '$_todaysTransactionCount',
                                  icon: Icons.receipt_rounded,
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    ),

                    const SizedBox(height: DesignSpacing.xxl),

                    const SectionHeader(
                      title: 'Quick Access',
                      subtitle: 'Jump into receipts, analytics, or credit',
                      icon: Icons.dashboard_rounded,
                    ),
                    const SizedBox(height: DesignSpacing.sm),

                    StaggeredItem(
                      itemKey: 'payments-quick-receipts',
                      index: 1,
                      child:
                      Row(
                        children: [
                          Expanded(
                            child: QuickActionTile(
                              icon: Icons.receipt_long_rounded,
                              label: 'Receipts',
                              subtitle: 'View & share',
                              color: DesignColors.info,
                              onTap: () => context.push('/receipts'),
                            ),
                          ),
                          const SizedBox(width: DesignSpacing.md),
                          Expanded(
                            child: QuickActionTile(
                              icon: Icons.analytics_rounded,
                              label: 'Analytics',
                              subtitle: 'Payment breakdown',
                              color: DesignColors.brand,
                              onTap: () => context.push('/payment-analytics'),
                            ),
                          ),
                        ],
                      )
                    ),
                    const SizedBox(height: DesignSpacing.md),
                    StaggeredItem(
                      itemKey: 'payments-quick-credit',
                      index: 2,
                      child:
                      Row(
                        children: [
                          Expanded(
                            child: QuickActionTile(
                              icon: Icons.credit_score_rounded,
                              label: 'Customer Credit',
                              subtitle: 'Installments & balances',
                              color: DesignColors.warning,
                              onTap: () => context.go('/customers'),
                            ),
                          ),
                          const SizedBox(width: DesignSpacing.md),
                          Expanded(
                            child: QuickActionTile(
                              icon: Icons.point_of_sale_rounded,
                              label: 'New Sale',
                              subtitle: 'Start a checkout',
                              color: DesignColors.success,
                              onTap: () => context.go('/'),
                            ),
                          ),
                        ],
                      )
                    ),

                    if (ref.watch(currentUserProvider)?['role']?.toString().toUpperCase() == 'ADMIN') ...[
                      const SizedBox(height: DesignSpacing.md),
                      QuickActionTile(
                        icon: Icons.account_balance_rounded,
                        label: 'Payout account',
                        subtitle: 'Where your shop receives customer payments',
                        color: DesignColors.success,
                        onTap: () => context.push('/payments/setup'),
                      ),
                    ],

                    if (_merchantCharges.any((row) =>
                        row['status'] == 'PENDING' || row['status'] == 'NEEDS_REVIEW' || row['status'] == 'SETTLING')) ...[
                      const SizedBox(height: DesignSpacing.xxl),
                      const SectionHeader(
                        title: 'Payments to check',
                        subtitle: 'Review these before requesting another M-Pesa payment',
                        icon: Icons.pending_actions_rounded,
                      ),
                      const SizedBox(height: DesignSpacing.sm),
                      ..._merchantCharges.where((row) =>
                          row['status'] == 'PENDING' || row['status'] == 'NEEDS_REVIEW' || row['status'] == 'SETTLING')
                          .map((row) {
                        final reference = row['reference']?.toString() ?? '';
                        return Card(child: ListTile(
                          title: Text('KES ${row['amount']} · ${row['status']}'),
                          subtitle: Text(reference),
                          trailing: TextButton(
                            onPressed: reference.isEmpty ? null : () => _checkMerchantCharge(reference),
                            child: const Text('Check'),
                          ),
                        ));
                      }),
                    ],

                    Builder(builder: (context) {
                      final perms = ref.watch(permissionsProvider);
                      final tiles = <Widget>[
                        if (perms.canViewCashFlow)
                          QuickActionTile(
                            icon: Icons.account_balance_wallet_rounded,
                            label: 'Cash Flow',
                            subtitle: 'Till & restock cash',
                            color: DesignColors.info,
                            onTap: () => context.push('/cash-flow'),
                          ),
                      ];
                      if (tiles.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: DesignSpacing.md),
                        child: StaggeredItem(
                          itemKey: 'payments-quick-more',
                          index: 3,
                          // Two columns always, so a lone tile keeps the same
                          // width as its neighbours above instead of stretching.
                          child: Row(
                            children: [
                              Expanded(child: tiles[0]),
                              const SizedBox(width: DesignSpacing.md),
                              Expanded(
                                child: tiles.length > 1
                                    ? tiles[1]
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: DesignSpacing.xxl),

                    // Payment Methods
                    const SectionHeader(
                      title: 'Accepted Payment Methods',
                      subtitle: 'Available at checkout',
                      icon: Icons.credit_card_rounded,
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    const StaggeredItem(
                      itemKey: 'payments-methods',
                      index: 3,
                      child:
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _PaymentMethodBadge(
                            method: 'Cash',
                            icon: Icons.payments_outlined,
                          ),
                          _PaymentMethodBadge(
                            method: 'M-Pesa',
                            icon: Icons.phone_android_rounded,
                          ),
                          _PaymentMethodBadge(
                            method: 'Customer debt',
                            icon: Icons.credit_score_outlined,
                          ),
                          _PaymentMethodBadge(
                            method: 'Cash + debt split',
                            icon: Icons.call_split_rounded,
                          ),
                        ],
                      )
                    ),

                    const SizedBox(height: DesignSpacing.xxl),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildGlassStatItem({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(DesignSpacing.sm + 2),
          decoration: BoxDecoration(
            color: DesignColors.textOnBrand.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          ),
          child: Icon(icon, color: DesignColors.textOnBrand, size: 24),
        ),
        const SizedBox(height: DesignSpacing.sm),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: DesignColors.textOnBrand,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: DesignSpacing.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: DesignColors.textOnBrand.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodBadge extends StatelessWidget {
  const _PaymentMethodBadge({required this.method, required this.icon});

  final String method;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.md, vertical: DesignSpacing.md - 3),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceMuted,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(
            color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16,
              color: isDark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary),
          const SizedBox(width: DesignSpacing.sm - 1),
          Text(
            method,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? DesignColors.darkTextPrimary
                  : DesignColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
