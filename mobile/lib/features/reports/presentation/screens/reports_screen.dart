import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../providers/reports_provider.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  static final _currencyFmt =
      NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Reports',
        showBackButton: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(dashboardSummaryProvider);
              ref.invalidate(salesListProvider);
            },
          ),
        ],
      ),
      body: PageContainer(
        withScroll: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dashboard-style summary cards with MetricCard
            summaryAsync.when(
              data: (summary) => _buildSummaryGrid(context, summary),
              loading: () => _buildSummaryGrid(context, {
                'transactionCount': 0,
                'totalRevenue': 0.0,
                'avgTicket': 0.0,
                'itemsSold': 0,
              }),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load summary',
                  subtitle: 'Check your connection and try again.',
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(dashboardSummaryProvider),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Date Range Selector
            _DateRangeSelector(),
            const SizedBox(height: 20),

            // Reports section
            SectionHeader(
              title: 'Reports',
              subtitle: 'Detailed sales and operational reports',
              icon: Icons.description_rounded,
            ),
            const SizedBox(height: 8),

            _ReportTile(
              icon: Icons.bar_chart_rounded,
              title: 'Sales Report',
              subtitle: 'View sales by period',
              color: DesignColors.brand,
              onTap: () => _showSalesReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.pie_chart_rounded,
              title: 'Payment Methods',
              subtitle: 'Breakdown of payment methods used',
              color: DesignColors.credit,
              onTap: () => _showPaymentMethodsReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.person_rounded,
              title: 'Cashier Performance',
              subtitle: 'Sales by cashier',
              color: DesignColors.accent,
              onTap: () => _showCashierReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.category_rounded,
              title: 'Category Sales',
              subtitle: 'Sales by product category',
              color: DesignColors.info,
              onTap: () => _showCategorySalesReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.star_rounded,
              title: 'Top Products',
              subtitle: 'Best selling products',
              color: DesignColors.warning,
              onTap: () => _showTopProductsReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.warehouse_rounded,
              title: 'Inventory Report',
              subtitle: 'Stock levels and movements',
              color: DesignColors.success,
              onTap: () => _showInventoryReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.people_rounded,
              title: 'Customer Report',
              subtitle: 'Customer purchases and loyalty',
              color: DesignColors.brandLight,
              onTap: () => _showCustomerReport(context, ref),
            ),

            const SizedBox(height: 20),

            // Analytics section
            SectionHeader(
              title: 'Analytics',
              subtitle: 'Advanced analytics and forecasting',
              icon: Icons.analytics_rounded,
            ),
            const SizedBox(height: 8),

            _GlassCardTile(
              icon: Icons.bar_chart_rounded,
              title: 'Analytics Dashboard',
              subtitle:
                  'Comprehensive sales analytics with multiple chart types',
              color: DesignColors.brand,
              onTap: () => context.push('/reports/analytics'),
            ),
            _GlassCardTile(
              icon: Icons.trending_up_rounded,
              title: 'Inventory Forecast',
              subtitle: 'Predictive inventory analytics and demand forecasting',
              color: DesignColors.credit,
              onTap: () => context.push('/reports/inventory-forecast'),
            ),
            _GlassCardTile(
              icon: Icons.payments_rounded,
              title: 'Payment Analytics',
              subtitle:
                  'Detailed payment method analysis and transaction trends',
              color: DesignColors.accent,
              onTap: () => context.push('/payment-analytics'),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(BuildContext context, Map<String, dynamic> s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: "Today's Sales",
                  value: _currencyFmt.format(s['totalRevenue'] ?? 0),
                  icon: Icons.trending_up_rounded,
                  color: DesignColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  title: 'Transactions',
                  value: '${s['transactionCount'] ?? 0}',
                  icon: Icons.receipt_long_rounded,
                  color: DesignColors.brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  title: 'Avg. Ticket',
                  value: _currencyFmt.format(s['avgTicket'] ?? 0),
                  icon: Icons.shopping_cart_rounded,
                  color: DesignColors.info,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  title: 'Items Sold',
                  value: '${s['itemsSold'] ?? 0}',
                  icon: Icons.inventory_2_rounded,
                  color: DesignColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===== SALES REPORT =====
  void _showSalesReport(BuildContext context, WidgetRef ref) {
    GlassBottomSheet.show(
      context,
      title: 'Sales Report',
      initialSize: 0.8,
      maxSize: 0.95,
      child: Consumer(builder: (ctx, ref, _) {
        final salesAsync = ref.watch(salesListProvider);
        final range = ref.watch(dateRangeProvider);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sales Report',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  StatusBadge(label: range.label, color: DesignColors.brand),
                ],
              ),
              const SizedBox(height: 8),
              // Report navigation tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildReportNavTab(context, 'Sales', true,
                        () => _showSalesReport(context, ref)),
                    const SizedBox(width: 4),
                    _buildReportNavTab(context, 'Customers', false,
                        () => _showCustomerReport(context, ref)),
                    const SizedBox(width: 4),
                    _buildReportNavTab(context, 'Payments', false,
                        () => _showPaymentMethodsReport(context, ref)),
                    const SizedBox(width: 4),
                    _buildReportNavTab(context, 'Cashier', false,
                        () => _showCashierReport(context, ref)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: salesAsync.when(
                  data: (sales) {
                    if (sales.isEmpty) {
                      return const EmptyState(
                        icon: Icons.receipt_long_rounded,
                        title: 'No sales in this period',
                      );
                    }
                    final totalRevenue =
                        sales.fold<double>(0, (a, s) => a + s.total);
                    final isDark = Theme.of(ctx).brightness == Brightness.dark;
                    final titleColor = isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary;
                    return Column(
                      children: [
                        GlassCard(
                          padding: const EdgeInsets.all(12),
                          borderRadius: 12,
                          blur: 8,
                          tint: DesignColors.success.withValues(alpha: 0.1),
                          borderColor:
                              DesignColors.success.withValues(alpha: 0.2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total: ${sales.length} sales',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: titleColor)),
                              Text(_currencyFmt.format(totalRevenue),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: DesignColors.success)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.builder(
                            itemCount: sales.length,
                            itemBuilder: (ctx, i) {
                              final sale = sales[i];
                              return ListCard(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      DesignColors.brand.withValues(alpha: 0.1),
                                  child: const Icon(Icons.receipt_rounded,
                                      color: DesignColors.brand, size: 18),
                                ),
                                title: sale.receiptNumber,
                                subtitle:
                                    '${sale.paymentMethod}  ${DateFormat('d MMM, hh:mm a').format(sale.createdAt)}',
                                trailing: Text(_currencyFmt.format(sale.total),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: titleColor)),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Couldn\'t load sales',
                    subtitle: 'Check your connection and try again.',
                    iconColor: DesignColors.error,
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(salesListProvider),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ===== PAYMENT METHODS =====
  void _showPaymentMethodsReport(BuildContext context, WidgetRef ref) {
    GlassBottomSheet.show(
      context,
      title: 'Payment Methods',
      initialSize: 0.6,
      maxSize: 0.9,
      child: Consumer(builder: (ctx, ref, _) {
        final dataAsync = ref.watch(paymentMethodProvider);
        final range = ref.watch(dateRangeProvider);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Payment Methods',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  StatusBadge(label: range.label, color: DesignColors.accent),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: dataAsync.when(
                  data: (data) {
                    if (data.isEmpty) {
                      return const EmptyState(
                        icon: Icons.payment_rounded,
                        title: 'No data for this period',
                      );
                    }
                    final total = data.fold<double>(
                        0, (a, d) => a + (d['totalAmount'] as double));
                    final isDark =
                        Theme.of(ctx).brightness == Brightness.dark;
                    final titleColor = isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary;
                    return ListView.builder(
                      itemCount: data.length,
                      itemBuilder: (ctx, i) {
                        final d = data[i];
                        final amount = d['totalAmount'] as double;
                        final pct = total > 0 ? (amount / total * 100) : 0.0;
                        final color =
                            _paymentColor(d['paymentMethod'] as String);
                        return GlassCard(
                          padding: const EdgeInsets.all(16),
                          borderRadius: 12,
                          blur: 8,
                          tint: color.withValues(alpha: 0.06),
                          borderColor: color.withValues(alpha: 0.15),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(children: [
                                    Icon(
                                        _paymentIcon(
                                            d['paymentMethod'] as String),
                                        color: color,
                                        size: 20),
                                    const SizedBox(width: 8),
                                    Text(d['paymentMethod'] as String,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: titleColor)),
                                  ]),
                                  Text(_currencyFmt.format(amount),
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: titleColor)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct / 100,
                                  backgroundColor: color.withValues(alpha: 0.1),
                                  valueColor: AlwaysStoppedAnimation(color),
                                  minHeight: 8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                  '${d['count']} transactions  ${pct.toStringAsFixed(1)}%',
                                  style: Theme.of(ctx).textTheme.bodySmall),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Couldn\'t load payment methods',
                    subtitle: 'Check your connection and try again.',
                    iconColor: DesignColors.error,
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(paymentMethodProvider),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ===== CASHIER PERFORMANCE =====
  void _showCashierReport(BuildContext context, WidgetRef ref) {
    GlassBottomSheet.show(
      context,
      title: 'Cashier Performance',
      initialSize: 0.6,
      maxSize: 0.9,
      child: Consumer(builder: (ctx, ref, _) {
        final dataAsync = ref.watch(cashierPerformanceProvider);
        final range = ref.watch(dateRangeProvider);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cashier Performance',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  StatusBadge(label: range.label, color: DesignColors.accent),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: dataAsync.when(
                  data: (data) {
                    if (data.isEmpty) {
                      return const EmptyState(
                        icon: Icons.person_rounded,
                        title: 'No cashier data for this period',
                      );
                    }
                    return ListView.builder(
                      itemCount: data.length,
                      itemBuilder: (ctx, i) {
                        final d = data[i];
                        return ListCard(
                          leading: CircleAvatar(
                            backgroundColor:
                                DesignColors.brand.withValues(alpha: 0.1),
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    color: DesignColors.brand,
                                    fontWeight: FontWeight.bold)),
                          ),
                          title: d['cashierId'] as String,
                          subtitle: '${d['count']} transactions',
                          trailing: Text(_currencyFmt.format(d['totalAmount']),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: DesignColors.success)),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Couldn\'t load cashier performance',
                    subtitle: 'Check your connection and try again.',
                    iconColor: DesignColors.error,
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(cashierPerformanceProvider),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ===== CATEGORY SALES =====
  void _showCategorySalesReport(BuildContext context, WidgetRef ref) {
    GlassBottomSheet.show(
      context,
      title: 'Category Sales',
      initialSize: 0.7,
      maxSize: 0.95,
      child: Consumer(builder: (ctx, ref, _) {
        final dataAsync = ref.watch(categorySalesProvider);
        final range = ref.watch(dateRangeProvider);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Category Sales',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  StatusBadge(label: range.label, color: DesignColors.info),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: dataAsync.when(
                  data: (data) {
                    if (data.isEmpty) {
                      return const EmptyState(
                        icon: Icons.category_rounded,
                        title: 'No category data',
                      );
                    }
                    final total = data.fold<double>(
                        0, (a, d) => a + (d['totalRevenue'] as double));
                    final isDark =
                        Theme.of(ctx).brightness == Brightness.dark;
                    final titleColor = isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary;
                    return ListView.builder(
                      itemCount: data.length,
                      itemBuilder: (ctx, i) {
                        final d = data[i];
                        final revenue = d['totalRevenue'] as double;
                        final pct = total > 0 ? (revenue / total * 100) : 0.0;
                        final colors = [
                          DesignColors.brand,
                          DesignColors.success,
                          DesignColors.info,
                          DesignColors.warning,
                          DesignColors.accent,
                          DesignColors.error
                        ];
                        final color = colors[i % colors.length];
                        return GlassCard(
                          padding: const EdgeInsets.all(16),
                          borderRadius: 12,
                          blur: 8,
                          tint: color.withValues(alpha: 0.06),
                          borderColor: color.withValues(alpha: 0.15),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: Text(d['categoryName'] as String,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: titleColor))),
                                  Text(_currencyFmt.format(revenue),
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: titleColor)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: total > 0 ? revenue / total : 0,
                                  backgroundColor: color.withValues(alpha: 0.1),
                                  valueColor: AlwaysStoppedAnimation(color),
                                  minHeight: 8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                  '${d['totalQty']} items  ${pct.toStringAsFixed(1)}%',
                                  style: Theme.of(ctx).textTheme.bodySmall),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Couldn\'t load category sales',
                    subtitle: 'Check your connection and try again.',
                    iconColor: DesignColors.error,
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(categorySalesProvider),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ===== TOP PRODUCTS =====
  void _showTopProductsReport(BuildContext context, WidgetRef ref) {
    GlassBottomSheet.show(
      context,
      title: 'Top Products',
      initialSize: 0.7,
      maxSize: 0.95,
      child: Consumer(builder: (ctx, ref, _) {
        final dataAsync = ref.watch(topProductsProvider);
        final range = ref.watch(dateRangeProvider);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Top Products',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  StatusBadge(label: range.label, color: DesignColors.warning),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: dataAsync.when(
                  data: (data) {
                    if (data.isEmpty) {
                      return const EmptyState(
                        icon: Icons.star_rounded,
                        title: 'No product data for this period',
                      );
                    }
                    return ListView.builder(
                      itemCount: data.length,
                      itemBuilder: (ctx, i) {
                        final d = data[i];
                        final isTop3 = i < 3;
                        return ListCard(
                          leading: CircleAvatar(
                            backgroundColor: isTop3
                                ? DesignColors.warning.withValues(alpha: 0.2)
                                : DesignColors.brand.withValues(alpha: 0.1),
                            child: isTop3
                                ? const Icon(Icons.emoji_events_rounded,
                                    color: DesignColors.warning, size: 20)
                                : Text('${i + 1}',
                                    style: const TextStyle(
                                        color: DesignColors.brand)),
                          ),
                          title: d['productName'] as String,
                          subtitle: '${d['totalQty']} units sold',
                          trailing: Text(_currencyFmt.format(d['totalRevenue']),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Couldn\'t load top products',
                    subtitle: 'Check your connection and try again.',
                    iconColor: DesignColors.error,
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(topProductsProvider),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ===== INVENTORY REPORT =====
  void _showInventoryReport(BuildContext context, WidgetRef ref) {
    GlassBottomSheet.show(
      context,
      title: 'Inventory Report',
      initialSize: 0.8,
      maxSize: 0.95,
      child: Consumer(builder: (ctx, ref, _) {
        final dataAsync = ref.watch(inventoryReportProvider);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text('Inventory Report',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              Expanded(
                child: dataAsync.when(
                  data: (data) {
                    if (data.isEmpty) {
                      return const EmptyState(
                        icon: Icons.warehouse_rounded,
                        title: 'No inventory data',
                      );
                    }
                    return ListView.builder(
                      itemCount: data.length,
                      itemBuilder: (ctx, i) {
                        final d = data[i];
                        final stock = d['stock'] as int;
                        final minStock = d['minStock'] as int;
                        final isLow = stock <= minStock && minStock > 0;
                        final isOut = stock == 0;
                        final statusColor = isOut
                            ? DesignColors.error
                            : isLow
                                ? DesignColors.warning
                                : DesignColors.success;
                        return ListCard(
                          leading: CircleAvatar(
                            backgroundColor: statusColor.withValues(alpha: 0.1),
                            child: Icon(
                              isOut
                                  ? Icons.error_outline_rounded
                                  : isLow
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_outline_rounded,
                              color: statusColor,
                              size: 20,
                            ),
                          ),
                          title: d['name'] as String,
                          subtitle: '${d['sku']}  ${d['categoryName']}',
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('$stock in stock',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  )),
                              if (minStock > 0)
                                Text('Min: $minStock',
                                    style: Theme.of(ctx).textTheme.bodySmall),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Couldn\'t load inventory report',
                    subtitle: 'Check your connection and try again.',
                    iconColor: DesignColors.error,
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(inventoryReportProvider),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ===== CUSTOMER REPORT =====
  void _showCustomerReport(BuildContext context, WidgetRef ref) {
    GlassBottomSheet.show(
      context,
      title: 'Customer Report',
      initialSize: 0.8,
      maxSize: 0.95,
      child: Consumer(builder: (ctx, ref, _) {
        final db = getIt<AppDatabase>();
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final secondaryColor = isDark
            ? DesignColors.darkTextSecondary
            : DesignColors.textSecondary;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Customer Report',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  // Add a close button for Customer Report
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: secondaryColor,
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Report navigation tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildReportNavTab(context, 'Sales', false,
                        () => _showSalesReport(context, ref)),
                    const SizedBox(width: 4),
                    _buildReportNavTab(context, 'Customers', true,
                        () => _showCustomerReport(context, ref)),
                    const SizedBox(width: 4),
                    _buildReportNavTab(context, 'Payments', false,
                        () => _showPaymentMethodsReport(context, ref)),
                    const SizedBox(width: 4),
                    _buildReportNavTab(context, 'Cashier', false,
                        () => _showCashierReport(context, ref)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: db.getAllCustomers(),
                  builder: (ctx, snap) {
                    final data = snap.data ?? [];
                    if (data.isEmpty) {
                      return const EmptyState(
                        icon: Icons.people_rounded,
                        title: 'No customer data',
                      );
                    }
                    return ListView.builder(
                      itemCount: data.length,
                      itemBuilder: (ctx, i) {
                        final c = data[i];
                        final totalPurchases = c['totalPurchases'] as int;
                        final totalSpent = c['totalSpent'] as double;
                        final lastPurchase = c['lastPurchaseAt'] as String?;
                        return ListCard(
                          leading: CircleAvatar(
                            backgroundColor:
                                DesignColors.accent.withValues(alpha: 0.1),
                            child: Text(
                              (c['name'] as String)
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                  color: DesignColors.accent,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: c['name'] as String,
                          subtitle:
                              '${c['phone'] != null && (c['phone'] as String).isNotEmpty ? '${c['phone']}  ' : ''}$totalPurchases purchases  ${_currencyFmt.format(totalSpent)}',
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (lastPurchase != null)
                                Text(
                                  DateFormat('d MMM')
                                      .format(DateTime.parse(lastPurchase)),
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                ),
                              const SizedBox(height: 2),
                              Text(
                                '${(totalPurchases > 0 ? totalSpent / totalPurchases : 0).toStringAsFixed(0)} avg',
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          onTap: () => _showCustomerDetails(ctx, c),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _showCustomerDetails(
      BuildContext context, Map<String, dynamic> customer) async {
    final db = getIt<AppDatabase>();
    final topProducts =
        await db.getCustomerTopProducts(customer['id'] as String);
    if (!context.mounted) return;

    GlassBottomSheet.show(
      context,
      title: 'Customer Details',
      initialSize: 0.5,
      maxSize: 0.7,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: DesignColors.accent.withValues(alpha: 0.1),
                  child: Text(
                    (customer['name'] as String).substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        color: DesignColors.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer['name'] as String,
                          style: Theme.of(context).textTheme.titleMedium),
                      if ((customer['phone'] as String?)?.isNotEmpty == true)
                        Text(customer['phone'] as String,
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: 'Purchases',
                    value: '${customer['totalPurchases']}',
                    icon: Icons.shopping_bag_rounded,
                    color: DesignColors.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MetricCard(
                    title: 'Total Spent',
                    value: _currencyFmt.format(customer['totalSpent']),
                    icon: Icons.attach_money_rounded,
                    color: DesignColors.brand,
                  ),
                ),
              ],
            ),
            if (topProducts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Top Products',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...topProducts.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            child: Text(p['productName'] as String,
                                overflow: TextOverflow.ellipsis)),
                        Text('${p['totalQty']} units',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _paymentIcon(String method) => switch (method.toUpperCase()) {
        'CASH' => Icons.money_rounded,
        'MPESA' || 'M-PESA' => Icons.phone_android_rounded,
        'CARD' || 'CREDIT_CARD' || 'DEBIT_CARD' => Icons.credit_card_rounded,
        _ => Icons.payment_rounded,
      };

  Color _paymentColor(String method) => switch (method.toUpperCase()) {
        'CASH' => DesignColors.cash,
        'MPESA' || 'M-PESA' => DesignColors.mpesa,
        'CARD' || 'CREDIT_CARD' || 'DEBIT_CARD' => DesignColors.credit,
        _ => DesignColors.brand,
      };
}

// ===== Glass Card Tile =====
class _GlassCardTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _GlassCardTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = isDark
        ? DesignColors.darkTextSecondary
        : DesignColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        borderRadius: 16,
        blur: 12,
        tint: color.withValues(alpha: 0.08),
        borderColor: color.withValues(alpha: 0.2),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: secondaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: secondaryColor,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Report Tile =====
class _ReportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListCard(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: title,
        subtitle: subtitle,
        onTap: onTap,
      ),
    );
  }
}

// ===== Date Range Selector =====
class _DateRangeSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(dateRangeProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _buildPeriodChip(context, ref, 'Today', range.label == 'Today',
              () => ref.read(dateRangeProvider.notifier).setToday()),
          const SizedBox(width: 8),
          _buildPeriodChip(
              context,
              ref,
              'This Week',
              range.label == 'This Week',
              () => ref.read(dateRangeProvider.notifier).setThisWeek()),
          const SizedBox(width: 8),
          _buildPeriodChip(
              context,
              ref,
              'This Month',
              range.label == 'This Month',
              () => ref.read(dateRangeProvider.notifier).setThisMonth()),
          const SizedBox(width: 8),
          _buildPeriodChip(
            context,
            ref,
            range.label.contains('–') ? range.label : 'Custom',
            range.label.contains('–'),
            () async {
              final isDark =
                  Theme.of(context).brightness == Brightness.dark;
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
                builder: (ctx, child) => Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: isDark
                        ? const ColorScheme.dark(
                            primary: DesignColors.accent,
                            onPrimary: Colors.black,
                            surface: DesignColors.darkSurface,
                          )
                        : const ColorScheme.light(
                            primary: DesignColors.accent,
                          ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                ref
                    .read(dateRangeProvider.notifier)
                    .setCustom(picked.start, picked.end);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(BuildContext context, WidgetRef ref, String label,
      bool selected, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final secondaryColor = isDark
        ? DesignColors.darkTextSecondary
        : DesignColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DesignAnimation.fast,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? DesignColors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? DesignColors.accent.withValues(alpha: 0.3)
                : border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label.contains('–')
              ? label.length > 12
                  ? '${label.substring(0, 12)}...'
                  : label
              : label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? DesignColors.accent : secondaryColor,
          ),
        ),
      ),
    );
  }
}

// Helper method to build report navigation tabs
Widget _buildReportNavTab(
    BuildContext context, String title, bool isActive, VoidCallback onTap) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
  final secondaryColor =
      isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
  return GestureDetector(
    onTap: () {
      Navigator.pop(context);
      Future<void>.delayed(Duration.zero, onTap);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? DesignColors.accent.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? DesignColors.accent : border,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          color: isActive ? DesignColors.accent : secondaryColor,
        ),
      ),
    ),
  );
}
