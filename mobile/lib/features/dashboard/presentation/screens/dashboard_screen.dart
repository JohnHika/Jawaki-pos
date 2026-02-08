import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';

final _dashboardSummaryProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final db = getIt<AppDatabase>();
  // Re-emit every time pending_sales changes
  await for (final _ in db.watchTodaysSales()) {
    yield await db.getDashboardSummary();
  }
});

final _recentSalesProvider = StreamProvider<List<PendingSale>>((ref) {
  final db = getIt<AppDatabase>();
  return db.watchTodaysSales();
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static final _currencyFmt = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);
  static final _timeFmt = DateFormat('hh:mm a');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(_dashboardSummaryProvider);
    final salesAsync = ref.watch(_recentSalesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(_dashboardSummaryProvider);
              ref.invalidate(_recentSalesProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_dashboardSummaryProvider);
          ref.invalidate(_recentSalesProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting
              Text('Welcome back!', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color),
              ),
              const SizedBox(height: 20),

              // Summary Cards
              summaryAsync.when(
                data: (summary) => _buildSummaryGrid(context, summary),
                loading: () => _buildSummaryGrid(context, {
                  'transactionCount': 0,
                  'totalRevenue': 0.0,
                  'avgTicket': 0.0,
                  'itemsSold': 0,
                }),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),

              const SizedBox(height: 24),

              // Recent Sales
              Text('Recent Sales', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),

              salesAsync.when(
                data: (sales) {
                  if (sales.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: theme.cardTheme.color ?? theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long, size: 48, color: theme.textTheme.bodySmall?.color),
                            const SizedBox(height: 12),
                            Text('No sales today yet', style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: sales.take(10).map((sale) => _SaleCard(sale: sale)).toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading sales: $e')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(BuildContext context, Map<String, dynamic> summary) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _DashboardCard(
              title: "Today's Revenue",
              value: _currencyFmt.format(summary['totalRevenue'] ?? 0),
              icon: Icons.trending_up,
              color: AppColors.success,
            )),
            const SizedBox(width: 12),
            Expanded(child: _DashboardCard(
              title: 'Transactions',
              value: '${summary['transactionCount'] ?? 0}',
              icon: Icons.receipt_long,
              color: AppColors.primary,
            )),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _DashboardCard(
              title: 'Avg. Ticket',
              value: _currencyFmt.format(summary['avgTicket'] ?? 0),
              icon: Icons.shopping_cart,
              color: AppColors.info,
            )),
            const SizedBox(width: 12),
            Expanded(child: _DashboardCard(
              title: 'Items Sold',
              value: '${summary['itemsSold'] ?? 0}',
              icon: Icons.inventory_2,
              color: AppColors.secondary,
            )),
          ],
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold, color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          Text(title, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final PendingSale sale;
  const _SaleCard({required this.sale});

  static final _currencyFmt = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);
  static final _timeFmt = DateFormat('hh:mm a');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: const Icon(Icons.receipt, color: AppColors.primary, size: 20),
        ),
        title: Text(sale.receiptNumber, style: theme.textTheme.titleSmall),
        subtitle: Text(
          '${sale.paymentMethod} • ${_timeFmt.format(sale.createdAt)}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Text(
          _currencyFmt.format(sale.total),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.success,
          ),
        ),
      ),
    );
  }
}
