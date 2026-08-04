import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/design_system.dart';

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'Payment Management',
                      subtitle: "Today's takings, receipts, and credit",
                      icon: Icons.payments_rounded,
                    ),
                    const SizedBox(height: 8),

                    // Today's summary
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      borderRadius: 16,
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
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.today_rounded,
                                    color: Colors.white, size: 24),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                "Today's Takings",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
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
                    ),

                    const SizedBox(height: 24),

                    const SectionHeader(
                      title: 'Quick Access',
                      subtitle: 'Jump into receipts, analytics, or credit',
                      icon: Icons.dashboard_rounded,
                    ),
                    const SizedBox(height: 8),

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
                        const SizedBox(width: 12),
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
                    ),
                    const SizedBox(height: 12),
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
                        const SizedBox(width: 12),
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
                    ),

                    const SizedBox(height: 24),

                    // Payment Methods
                    const SectionHeader(
                      title: 'Accepted Payment Methods',
                      subtitle: 'Available at checkout',
                      icon: Icons.credit_card_rounded,
                    ),
                    const SizedBox(height: 8),
                    const Wrap(
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
                    ),

                    const SizedBox(height: 24),
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
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: DesignColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesignColors.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: DesignColors.textSecondary),
          const SizedBox(width: 7),
          Text(
            method,
            style: const TextStyle(
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
