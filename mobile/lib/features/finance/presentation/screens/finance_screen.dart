import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';

final _supplierBalancesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final db = getIt<AppDatabase>();
    return await db.getSupplierDebts();
  } catch (e) {
    // Tables may not exist yet — return empty list
    debugPrint('Finance: supplier tables not available ($e)');
    return [];
  }
});

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  static final _currencyFmt = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(_supplierBalancesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_supplierBalancesProvider),
          ),
        ],
      ),
      body: balancesAsync.when(
        data: (suppliers) {
          if (suppliers.isEmpty) {
            return const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No Supplier Data',
              subtitle: 'Supplier financial records will appear here once purchases are recorded.',
            );
          }

          final totalOwed = suppliers.fold<double>(0, (sum, s) => sum + ((s['totalOwed'] as double?) ?? 0));
          final totalPaid = suppliers.fold<double>(0, (sum, s) => sum + ((s['totalPaid'] as double?) ?? 0));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              // Summary Cards
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      title: 'Total Owed',
                      value: _currencyFmt.format(totalOwed),
                      icon: Icons.trending_up_rounded,
                      color: DesignColors.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricCard(
                      title: 'Total Paid',
                      value: _currencyFmt.format(totalPaid),
                      icon: Icons.check_circle_rounded,
                      color: DesignColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: 'Supplier Balances',
                subtitle: '${suppliers.length} supplier${suppliers.length == 1 ? '' : 's'}',
                icon: Icons.business_rounded,
                trailing: StatusBadge(
                  label: '${suppliers.where((s) => ((s['totalOwed'] as double?) ?? 0) > 0).length} with debt',
                  color: DesignColors.warning,
                  isActive: true,
                ),
              ),
              const SizedBox(height: 8),
              ...suppliers.map((s) => _SupplierBalanceCard(supplier: s, onRecordPayment: (amount) => _recordPayment(context, ref, s['id'] as String, s['name'] as String, amount))),
            ],
          );
        },
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: List.generate(4, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: const ShimmerWidget(width: double.infinity, height: 100, borderRadius: 14),
          )),
        ),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Error loading supplier data',
          subtitle: e.toString(),
          iconColor: DesignColors.error,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(_supplierBalancesProvider),
        ),
      ),
    );
  }

  Future<void> _recordPayment(BuildContext context, WidgetRef ref, String supplierId, String supplierName, double currentDebt) async {
    final controller = TextEditingController(text: currentDebt > 0 ? currentDebt.toStringAsFixed(0) : '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Pay $supplierName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current balance: ${_currencyFmt.format(currentDebt)}', style: const TextStyle(color: DesignColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Payment Amount (KES)',
                prefixIcon: const Icon(Icons.payments_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DesignColors.success),
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final amount = double.tryParse(controller.text) ?? 0;
      if (amount > 0) {
        try {
          final db = getIt<AppDatabase>();
          await db.recordSupplierPayment(supplierId, amount);
          ref.invalidate(_supplierBalancesProvider);
          if (context.mounted) {
            showGlassSnackBar(context, 'Payment of ${_currencyFmt.format(amount)} recorded', icon: Icons.check_circle_rounded, color: DesignColors.success);
          }
        } catch (e) {
          if (context.mounted) {
            showGlassSnackBar(context, 'Payment failed: $e', icon: Icons.error_outline_rounded, color: DesignColors.error);
          }
        }
      }
    }
  }
}

class _SupplierBalanceCard extends StatelessWidget {
  final Map<String, dynamic> supplier;
  final void Function(double amount) onRecordPayment;

  const _SupplierBalanceCard({required this.supplier, required this.onRecordPayment});

  @override
  Widget build(BuildContext context) {
    final totalOwed = (supplier['totalOwed'] as double?) ?? 0;
    final totalPaid = (supplier['totalPaid'] as double?) ?? 0;
    final lastPayment = supplier['lastPaymentDate'] as String?;
    final percentage = (totalOwed + totalPaid) > 0 ? (totalPaid / (totalOwed + totalPaid) * 100) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 14,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: DesignColors.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DesignColors.brand.withValues(alpha: 0.15)),
                  ),
                  child: const Icon(Icons.business_rounded, color: DesignColors.brand, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(supplier['name'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: DesignColors.textPrimary)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text('Owed: ${FinanceScreen._currencyFmt.format(totalOwed)}',
                            style: TextStyle(fontSize: 12, color: totalOwed > 0 ? DesignColors.error : DesignColors.success, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 12),
                          Text('Paid: ${FinanceScreen._currencyFmt.format(totalPaid)}',
                            style: const TextStyle(fontSize: 12, color: DesignColors.textTertiary)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (totalOwed > 0)
                  SizedBox(
                    height: 36,
                    child: GradientButton(
                      label: 'Pay',
                      icon: Icons.payment_rounded,
                      onPressed: () => onRecordPayment(totalOwed),
                      gradient: [DesignColors.success, const Color(0xFF059669)],
                      height: 36,
                      expanded: false,
                      borderRadius: 10,
                    ),
                  ),
              ],
            ),
            if (totalOwed + totalPaid > 0) ...[
              const SizedBox(height: 10),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: DesignColors.surfaceBorder.withValues(alpha: 0.4),
                  valueColor: const AlwaysStoppedAnimation<Color>(DesignColors.success),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${percentage.toStringAsFixed(0)}% paid', style: const TextStyle(fontSize: 10, color: DesignColors.textTertiary)),
                  const Spacer(),
                  if (lastPayment != null)
                    Text('Last: $lastPayment', style: const TextStyle(fontSize: 10, color: DesignColors.textTertiary)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
