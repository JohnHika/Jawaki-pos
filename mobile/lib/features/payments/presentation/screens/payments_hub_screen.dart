import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/design_system.dart';

/// Payments Hub - Main screen for all payment-related features
/// Includes: Manual Payments, Hold Queue, Bulk Payments, Receipts
class PaymentsHubScreen extends ConsumerStatefulWidget {
  const PaymentsHubScreen({super.key});

  @override
  ConsumerState<PaymentsHubScreen> createState() => _PaymentsHubScreenState();
}

class _PaymentsHubScreenState extends ConsumerState<PaymentsHubScreen> {
  late final AppDatabase _db;
  List<PendingSale> _todaysSales = [];
  List<Map<String, dynamic>> _paymentMethodBreakdown = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _db = getIt<AppDatabase>();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final sales = await _db.watchTodaysSales().first;
      final breakdown = await _db.getSalesByPaymentMethod(startOfDay, endOfDay);

      if (mounted) {
        setState(() {
          _todaysSales = sales;
          _paymentMethodBreakdown = breakdown;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  double get _todaysTotal =>
      _todaysSales.fold<double>(0.0, (sum, s) => sum + s.total);

  int get _creditSalesCount {
    for (final entry in _paymentMethodBreakdown) {
      final method = (entry['paymentMethod'] as String).toLowerCase();
      if (method == 'credit') {
        return entry['count'] as int;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => context.go('/receipts'),
            tooltip: 'View Receipts',
          ),
        ],
      ),
      body: PageContainer(
        withScroll: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            SectionHeader(
              title: 'Payment Management',
              subtitle: 'Manage manual payments, credit sales, and bulk transactions',
              icon: Icons.payments_rounded,
            ),
            const SizedBox(height: 8),

            // Quick action grid
            Row(
              children: [
                Expanded(
                  child: QuickActionTile(
                    icon: Icons.approval_rounded,
                    label: 'Manual Payments',
                    subtitle: 'Request & approve',
                    color: DesignColors.success,
                    onTap: () {
                      showGlassSnackBar(
                        context,
                        'Manual payment requests can be made from the payment screen',
                        icon: Icons.info_outline_rounded,
                        color: DesignColors.info,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuickActionTile(
                    icon: Icons.schedule_rounded,
                    label: 'Hold Queue',
                    subtitle: 'Pay Later',
                    color: DesignColors.warning,
                    onTap: () {
                      showGlassSnackBar(
                        context,
                        'Credit sales are tracked in the reports section',
                        icon: Icons.info_outline_rounded,
                        color: DesignColors.info,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: QuickActionTile(
                    icon: Icons.payments_rounded,
                    label: 'Bulk Payments',
                    subtitle: 'Process multiple',
                    color: DesignColors.brand,
                    onTap: () {
                      showGlassSnackBar(
                        context,
                        'Bulk payments can be processed from the web dashboard',
                        icon: Icons.info_outline_rounded,
                        color: DesignColors.info,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: QuickActionTile(
                    icon: Icons.receipt_long_rounded,
                    label: 'Receipts',
                    subtitle: 'View & reprint',
                    color: DesignColors.info,
                    onTap: () => context.go('/receipts'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Payment Methods
            SectionHeader(
              title: 'Payment Methods',
              subtitle: 'Supported payment types',
              icon: Icons.credit_card_rounded,
            ),
            const SizedBox(height: 8),

            // Payment method chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                PaymentChip(method: 'Cash', isSelected: true),
                PaymentChip(method: 'Mpesa'),
                PaymentChip(method: 'Card'),
                PaymentChip(method: 'PesaPal'),
                PaymentChip(method: 'TouristTap'),
                PaymentChip(method: 'Credit'),
              ],
            ),

            const SizedBox(height: 24),

            // Quick Stats with glass card (real data)
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
                        child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Quick Stats',
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
                        label: "Today's Sales",
                        value: _isLoading ? '...' : 'KES ${_todaysTotal.toStringAsFixed(0)}',
                        icon: Icons.point_of_sale_rounded,
                      ),
                      _buildGlassStatItem(
                        label: 'Credit Sales',
                        value: _isLoading ? '...' : '$_creditSalesCount',
                        icon: Icons.credit_card_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Info card
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 12,
              blur: 8,
              tint: DesignColors.info.withValues(alpha: 0.08),
              borderColor: DesignColors.info.withValues(alpha: 0.2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: DesignColors.info.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.info_outline_rounded, color: DesignColors.info, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Levisa Adventures POS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: DesignColors.info,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Complete payment management with manual approvals, credit tracking, and bulk processing',
                          style: TextStyle(
                            fontSize: 12,
                            color: DesignColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
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