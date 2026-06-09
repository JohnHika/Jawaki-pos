import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';

final _dashboardSummaryProvider =
    StreamProvider<Map<String, dynamic>>((ref) async* {
  final db = getIt<AppDatabase>();
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

  static final _currencyFmt =
      NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);
  static final _timeFmt = DateFormat('hh:mm a');
  static final _dateFmt = DateFormat('EEEE, d MMMM yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(_dashboardSummaryProvider);
    final salesAsync = ref.watch(_recentSalesProvider);
    final companyName = _companyDisplayName();
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Dashboard',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(_dashboardSummaryProvider);
              ref.invalidate(_recentSalesProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _shareDashboardReport(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_dashboardSummaryProvider);
          ref.invalidate(_recentSalesProvider);
        },
        child: PageContainer(
          withScroll: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting header
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Good ${_getGreeting()}, $companyName',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: DesignColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _dateFmt.format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 14,
                        color: DesignColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Summary Cards - Using Wrap+LayoutBuilder to prevent overflow in Column
              summaryAsync.when(
                data: (summary) => Column(
                  children: [
                    _buildSummaryGrid(context, summary),
                    const SizedBox(height: 12),
                    _buildAiBrief(context, summary),
                  ],
                ),
                loading: () => _buildSummaryGrid(context, {
                  'transactionCount': 0,
                  'totalRevenue': 0.0,
                  'avgTicket': 0.0,
                  'itemsSold': 0,
                }),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Error: $e',
                        style: const TextStyle(color: DesignColors.error)),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Recent Sales Section
              SectionHeader(
                icon: Icons.receipt_long_rounded,
                title: 'Recent Sales',
                subtitle: 'Today\'s transactions',
                trailing: Text(
                  'Last 10',
                  style: TextStyle(
                    fontSize: 12,
                    color: DesignColors.textTertiary,
                  ),
                ),
              ),

              salesAsync.when(
                data: (sales) {
                  if (sales.isEmpty) {
                    return const EmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: 'No sales today yet',
                      subtitle: 'Start selling to see transactions here',
                    );
                  }
                  return Column(
                    children: sales.take(10).map((sale) {
                      return GlassCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        borderRadius: 12,
                        blur: 8,
                        tint: Colors.transparent,
                        borderColor: DesignColors.surfaceBorder,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color:
                                    DesignColors.brand.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.receipt_rounded,
                                color: DesignColors.brand,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sale.receiptNumber,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: DesignColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${sale.paymentMethod}  •  ${_timeFmt.format(sale.createdAt)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: DesignColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _currencyFmt.format(sale.total),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Colors.teal,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Error: $e',
                        style: const TextStyle(color: DesignColors.error)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(BuildContext context, Map<String, dynamic> summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate card width to fit 2 per row with proper spacing
        final cardWidth = (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // Today's Revenue
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: "Today's Revenue",
                value: _currencyFmt.format(summary['totalRevenue'] ?? 0),
                icon: Icons.trending_up_rounded,
                color: Colors.teal,
              ),
            ),
            // Transactions
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: 'Transactions',
                value: '${summary['transactionCount'] ?? 0}',
                icon: Icons.receipt_long_rounded,
                color: DesignColors.brand,
              ),
            ),
            // Avg. Ticket
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: 'Avg. Ticket',
                value: _currencyFmt.format(summary['avgTicket'] ?? 0),
                icon: Icons.shopping_cart_rounded,
                color: DesignColors.info,
              ),
            ),
            // Items Sold
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: 'Items Sold',
                value: '${summary['itemsSold'] ?? 0}',
                icon: Icons.inventory_2_rounded,
                color: DesignColors.accent,
              ),
            ),
          ],
        );
      },
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }

  String _companyDisplayName() {
    final auth = getIt<AuthService>();
    final user = auth.currentUser;
    final tenant = user?['tenant'];
    final tenantMap =
        tenant is Map<String, dynamic> ? tenant : <String, dynamic>{};
    final candidates = [
      tenantMap['name'],
      user?['tenantName'],
      user?['companyName'],
      auth.tenantSlug,
      'Your Company',
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return 'Your Company';
  }

  Widget _buildAiBrief(BuildContext context, Map<String, dynamic> summary) {
    final revenue = (summary['totalRevenue'] as num?)?.toDouble() ?? 0;
    final transactions = (summary['transactionCount'] as num?)?.toInt() ?? 0;
    final avgTicket = (summary['avgTicket'] as num?)?.toDouble() ?? 0;
    final itemsSold = (summary['itemsSold'] as num?)?.toInt() ?? 0;

    final snippets = <String>[
      transactions == 0
          ? 'No sales have landed today yet. Start with fast-moving items and watch stock before checkout.'
          : '$transactions transactions have brought in ${_currencyFmt.format(revenue)} today.',
      avgTicket > 0
          ? 'Average ticket is ${_currencyFmt.format(avgTicket)} across $itemsSold sold items.'
          : 'Average ticket will appear once the first sale is completed.',
      itemsSold > 0
          ? 'Keep an eye on inventory after each sale so zero-stock items stay blocked from POS.'
          : 'Inventory and POS are linked, so received stock becomes sellable immediately.',
    ];

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 14,
      tint: DesignColors.info.withValues(alpha: 0.05),
      borderColor: DesignColors.info.withValues(alpha: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DesignColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: DesignColors.info,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'AI Brief',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: DesignColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...snippets.map(
            (snippet) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: DesignColors.info,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      snippet,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: DesignColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareDashboardReport(
      BuildContext context, WidgetRef ref) async {
    final db = getIt<AppDatabase>();
    final summary = await db.getDashboardSummary();
    final report = '''
  Daily Summary
  ═════════════
${_dateFmt.format(DateTime.now())}

Sales:    ${_currencyFmt.format(summary['totalSales'] ?? 0)}
Sales Count: ${summary['salesCount'] ?? 0}
Profit:   ${_currencyFmt.format(summary['grossProfit'] ?? 0)}
Avg Ticket: ${_currencyFmt.format(summary['avgTicket'] ?? 0)}
Items Sold: ${summary['itemsSold'] ?? 0}

Sent from your POS workspace
''';
    await Share.share(report, subject: 'Daily Sales Report');
  }
}
