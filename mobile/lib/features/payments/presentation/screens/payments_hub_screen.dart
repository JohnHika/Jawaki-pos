import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';

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
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _db = getIt<AppDatabase>();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sales = await _db.watchTodaysSales().first;

      if (mounted) {
        setState(() {
          _todaysSales = sales;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  double get _todaysTotal =>
      _todaysSales.fold<double>(0.0, (sum, s) => sum + s.total);

  int get _todaysTransactionCount => _todaysSales.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Payments',
        showBackButton: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => context.go('/receipts'),
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
                            const SizedBox(height: DesignSpacing.xl),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildGlassStatItem(
                                  label: 'Total Sales',
                                  value: _isLoading
                                      ? '...'
                                      : 'KES ${_todaysTotal.toStringAsFixed(0)}',
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
                              onTap: () => context.go('/receipts'),
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
                            method: 'Manual',
                            icon: Icons.receipt_long_outlined,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.md, vertical: DesignSpacing.md - 3),
      decoration: BoxDecoration(
        color: DesignColors.surfaceMuted,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(color: DesignColors.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: DesignColors.textSecondary),
          const SizedBox(width: DesignSpacing.sm - 1),
          Text(
            method,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: DesignColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
