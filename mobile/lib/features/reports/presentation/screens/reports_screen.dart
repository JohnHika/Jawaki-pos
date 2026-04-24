import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../providers/reports_provider.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  static final _currencyFmt = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(dashboardSummaryProvider);
              ref.invalidate(salesListProvider);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary Cards (live)
            summaryAsync.when(
              data: (summary) => _buildSummary(context, summary),
              loading: () => _buildSummary(context, {
                'transactionCount': 0, 'totalRevenue': 0.0, 'avgTicket': 0.0, 'itemsSold': 0,
              }),
              error: (e, _) => Text('Error: $e'),
            ),
            const SizedBox(height: 24),

            // Date Range Selector
            _DateRangeSelector(),
            const SizedBox(height: 16),

            Text('Reports', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),

            _ReportTile(
              icon: Icons.bar_chart,
              title: 'Sales Report',
              subtitle: 'View sales by period',
              onTap: () => _showSalesReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.pie_chart,
              title: 'Payment Methods',
              subtitle: 'Breakdown of payment methods used',
              onTap: () => _showPaymentMethodsReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.person,
              title: 'Cashier Performance',
              subtitle: 'Sales by cashier',
              onTap: () => _showCashierReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.category,
              title: 'Category Sales',
              subtitle: 'Sales by product category',
              onTap: () => _showCategorySalesReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.star,
              title: 'Top Products',
              subtitle: 'Best selling products',
              onTap: () => _showTopProductsReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.warehouse,
              title: 'Inventory Report',
              subtitle: 'Stock levels and movements',
              onTap: () => _showInventoryReport(context, ref),
            ),
            _ReportTile(
              icon: Icons.people,
              title: 'Customer Report',
              subtitle: 'Customer purchases and loyalty',
              onTap: () => _showCustomerReport(context, ref),
            ),
            const SizedBox(height: 16),
            Text('Analytics', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),

            // Glassmorphism Analytics Tiles
            _GlassmorphismReportTile(
              icon: Icons.bar_chart_rounded,
              title: 'Analytics Dashboard',
              subtitle: 'Comprehensive sales analytics with multiple chart types',
              color: AppColors.primary,
              onTap: () => context.push('/reports/analytics'),
            ),
            _GlassmorphismReportTile(
              icon: Icons.trending_up_rounded,
              title: 'Inventory Forecast',
              subtitle: 'Predictive inventory analytics and demand forecasting',
              color: AppColors.accent,
              onTap: () => context.push('/reports/inventory-forecast'),
            ),
            _GlassmorphismReportTile(
              icon: Icons.payments_rounded,
              title: 'Payment Analytics',
              subtitle: 'Detailed payment method analysis and transaction trends',
              color: AppColors.secondary,
              onTap: () => context.push('/payment-analytics'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context, Map<String, dynamic> s) {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _SummaryCard(
            title: "Today's Sales",
            value: _currencyFmt.format(s['totalRevenue'] ?? 0),
            icon: Icons.trending_up,
            color: AppColors.success,
          )),
          const SizedBox(width: 12),
          Expanded(child: _SummaryCard(
            title: 'Transactions',
            value: '${s['transactionCount'] ?? 0}',
            icon: Icons.receipt_long,
            color: AppColors.primary,
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _SummaryCard(
            title: 'Avg. Ticket',
            value: _currencyFmt.format(s['avgTicket'] ?? 0),
            icon: Icons.shopping_cart,
            color: AppColors.info,
          )),
          const SizedBox(width: 12),
          Expanded(child: _SummaryCard(
            title: 'Items Sold',
            value: '${s['itemsSold'] ?? 0}',
            icon: Icons.inventory_2,
            color: AppColors.secondary,
          )),
        ]),
      ],
    );
  }

  // ═══════ SALES REPORT ═══════
  void _showSalesReport(BuildContext context, WidgetRef ref) {
    final sales = ref.read(salesListProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Consumer(builder: (ctx, ref, _) {
          final salesAsync = ref.watch(salesListProvider);
          final range = ref.watch(dateRangeProvider);
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(ctx),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sales Report', style: Theme.of(ctx).textTheme.titleLarge),
                    Chip(label: Text(range.label)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: salesAsync.when(
                    data: (sales) {
                      if (sales.isEmpty) {
                        return const Center(child: Text('No sales in this period'));
                      }
                      final totalRevenue = sales.fold<double>(0, (a, s) => a + s.total);
                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total: ${sales.length} sales'),
                                Text(_currencyFmt.format(totalRevenue),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.builder(
                              controller: scroll,
                              itemCount: sales.length,
                              itemBuilder: (ctx, i) {
                                final sale = sales[i];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                    child: const Icon(Icons.receipt, color: AppColors.primary, size: 18),
                                  ),
                                  title: Text(sale.receiptNumber),
                                  subtitle: Text(
                                    '${sale.paymentMethod} • ${DateFormat('d MMM, hh:mm a').format(sale.createdAt)}',
                                  ),
                                  trailing: Text(_currencyFmt.format(sale.total),
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ═══════ PAYMENT METHODS ═══════
  void _showPaymentMethodsReport(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => Consumer(builder: (ctx, ref, _) {
          final dataAsync = ref.watch(paymentMethodProvider);
          final range = ref.watch(dateRangeProvider);
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(ctx),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Payment Methods', style: Theme.of(ctx).textTheme.titleLarge),
                    Chip(label: Text(range.label)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: dataAsync.when(
                    data: (data) {
                      if (data.isEmpty) {
                        return const Center(child: Text('No data for this period'));
                      }
                      final total = data.fold<double>(0, (a, d) => a + (d['totalAmount'] as double));
                      return ListView.builder(
                        controller: scroll,
                        itemCount: data.length,
                        itemBuilder: (ctx, i) {
                          final d = data[i];
                          final amount = d['totalAmount'] as double;
                          final pct = total > 0 ? (amount / total * 100) : 0.0;
                          final color = _paymentColor(d['paymentMethod'] as String);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(children: [
                                        Icon(_paymentIcon(d['paymentMethod'] as String), color: color, size: 20),
                                        const SizedBox(width: 8),
                                        Text(d['paymentMethod'] as String,
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                      ]),
                                      Text(_currencyFmt.format(amount),
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
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
                                  Text('${d['count']} transactions • ${pct.toStringAsFixed(1)}%',
                                    style: Theme.of(ctx).textTheme.bodySmall),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ═══════ CASHIER PERFORMANCE ═══════
  void _showCashierReport(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => Consumer(builder: (ctx, ref, _) {
          final dataAsync = ref.watch(cashierPerformanceProvider);
          final range = ref.watch(dateRangeProvider);
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(ctx),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Cashier Performance', style: Theme.of(ctx).textTheme.titleLarge),
                    Chip(label: Text(range.label)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: dataAsync.when(
                    data: (data) {
                      if (data.isEmpty) {
                        return const Center(child: Text('No cashier data for this period'));
                      }
                      return ListView.builder(
                        controller: scroll,
                        itemCount: data.length,
                        itemBuilder: (ctx, i) {
                          final d = data[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: Text('${i + 1}',
                                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(d['cashierId'] as String),
                              subtitle: Text('${d['count']} transactions'),
                              trailing: Text(_currencyFmt.format(d['totalAmount']),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ═══════ CATEGORY SALES ═══════
  void _showCategorySalesReport(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Consumer(builder: (ctx, ref, _) {
          final dataAsync = ref.watch(categorySalesProvider);
          final range = ref.watch(dateRangeProvider);
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(ctx),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Category Sales', style: Theme.of(ctx).textTheme.titleLarge),
                    Chip(label: Text(range.label)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: dataAsync.when(
                    data: (data) {
                      if (data.isEmpty) {
                        return const Center(child: Text('No category data'));
                      }
                      final total = data.fold<double>(0, (a, d) => a + (d['totalRevenue'] as double));
                      return ListView.builder(
                        controller: scroll,
                        itemCount: data.length,
                        itemBuilder: (ctx, i) {
                          final d = data[i];
                          final revenue = d['totalRevenue'] as double;
                          final pct = total > 0 ? (revenue / total * 100) : 0.0;
                          final colors = [AppColors.primary, AppColors.success, AppColors.info,
                            AppColors.warning, AppColors.secondary, AppColors.error];
                          final color = colors[i % colors.length];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text(d['categoryName'] as String,
                                        style: const TextStyle(fontWeight: FontWeight.w600))),
                                      Text(_currencyFmt.format(revenue),
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
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
                                  Text('${d['totalQty']} items • ${pct.toStringAsFixed(1)}%',
                                    style: Theme.of(ctx).textTheme.bodySmall),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ═══════ TOP PRODUCTS ═══════
  void _showTopProductsReport(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Consumer(builder: (ctx, ref, _) {
          final dataAsync = ref.watch(topProductsProvider);
          final range = ref.watch(dateRangeProvider);
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(ctx),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Top Products', style: Theme.of(ctx).textTheme.titleLarge),
                    Chip(label: Text(range.label)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: dataAsync.when(
                    data: (data) {
                      if (data.isEmpty) {
                        return const Center(child: Text('No product data for this period'));
                      }
                      return ListView.builder(
                        controller: scroll,
                        itemCount: data.length,
                        itemBuilder: (ctx, i) {
                          final d = data[i];
                          final isTop3 = i < 3;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isTop3
                                    ? AppColors.warning.withValues(alpha: 0.2)
                                    : AppColors.primary.withValues(alpha: 0.1),
                                child: isTop3
                                    ? Icon(Icons.emoji_events, color: AppColors.warning, size: 20)
                                    : Text('${i + 1}', style: const TextStyle(color: AppColors.primary)),
                              ),
                              title: Text(d['productName'] as String),
                              subtitle: Text('${d['totalQty']} units sold'),
                              trailing: Text(_currencyFmt.format(d['totalRevenue']),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ═══════ INVENTORY REPORT ═══════
  void _showInventoryReport(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Consumer(builder: (ctx, ref, _) {
          final dataAsync = ref.watch(inventoryReportProvider);
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(ctx),
                Text('Inventory Report', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                Expanded(
                  child: dataAsync.when(
                    data: (data) {
                      if (data.isEmpty) {
                        return const Center(child: Text('No inventory data'));
                      }
                      return ListView.builder(
                        controller: scroll,
                        itemCount: data.length,
                        itemBuilder: (ctx, i) {
                          final d = data[i];
                          final stock = d['stock'] as int;
                          final minStock = d['minStock'] as int;
                          final isLow = stock <= minStock && minStock > 0;
                          final isOut = stock == 0;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isOut
                                    ? AppColors.error.withValues(alpha: 0.1)
                                    : isLow
                                        ? AppColors.warning.withValues(alpha: 0.1)
                                        : AppColors.success.withValues(alpha: 0.1),
                                child: Icon(
                                  isOut ? Icons.error_outline : isLow ? Icons.warning_amber : Icons.check_circle_outline,
                                  color: isOut ? AppColors.error : isLow ? AppColors.warning : AppColors.success,
                                  size: 20,
                                ),
                              ),
                              title: Text(d['name'] as String),
                              subtitle: Text('${d['sku']} • ${d['categoryName']}'),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('$stock in stock',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isOut ? AppColors.error : isLow ? AppColors.warning : null,
                                    )),
                                  if (minStock > 0) Text('Min: $minStock', style: Theme.of(ctx).textTheme.bodySmall),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ═══════ CUSTOMER REPORT ═══════
  void _showCustomerReport(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Consumer(builder: (ctx, ref, _) {
          final db = getIt<AppDatabase>();
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(ctx),
                Text('Customer Report', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: db.getAllCustomers(),
                    builder: (ctx, snap) {
                      final data = snap.data ?? [];
                      if (data.isEmpty) {
                        return const Center(child: Text('No customer data'));
                      }
                      return ListView.builder(
                        controller: scroll,
                        itemCount: data.length,
                        itemBuilder: (ctx, i) {
                          final c = data[i];
                          final totalPurchases = c['totalPurchases'] as int;
                          final totalSpent = c['totalSpent'] as double;
                          final lastPurchase = c['lastPurchaseAt'] as String?;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
                                child: Text(
                                  (c['name'] as String).substring(0, 1).toUpperCase(),
                                  style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(c['name'] as String),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if ((c['phone'] as String?)?.isNotEmpty == true)
                                    Text(c['phone'] as String, style: const TextStyle(fontSize: 12)),
                                  Text('$totalPurchases purchases • ${_currencyFmt.format(totalSpent)}',
                                    style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (lastPurchase != null)
                                    Text(
                                      DateFormat('d MMM').format(DateTime.parse(lastPurchase)),
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
                            ),
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
      ),
    );
  }

  void _showCustomerDetails(BuildContext context, Map<String, dynamic> customer) async {
    final db = getIt<AppDatabase>();
    final topProducts = await db.getCustomerTopProducts(customer['id'] as String);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(ctx),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
                  child: Text(
                    (customer['name'] as String).substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer['name'] as String, style: Theme.of(ctx).textTheme.titleMedium),
                      if ((customer['phone'] as String?)?.isNotEmpty == true)
                        Text(customer['phone'] as String, style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Purchases',
                    value: '${customer['totalPurchases']}',
                    icon: Icons.shopping_bag,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Total Spent',
                    value: _currencyFmt.format(customer['totalSpent']),
                    icon: Icons.attach_money,
                  ),
                ),
              ],
            ),
            if (topProducts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Top Products', style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...topProducts.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(p['productName'] as String, overflow: TextOverflow.ellipsis)),
                    Text('${p['totalQty']} units', style: Theme.of(ctx).textTheme.bodySmall),
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

  // ═══ Helpers ═══
  Widget _sheetHandle(BuildContext context) => Column(
    children: [
      Center(child: Container(
        width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)),
      )),
    ],
  );

  IconData _paymentIcon(String method) => switch (method.toUpperCase()) {
    'CASH' => Icons.money,
    'MPESA' || 'M-PESA' => Icons.phone_android,
    'CARD' || 'CREDIT_CARD' || 'DEBIT_CARD' => Icons.credit_card,
    _ => Icons.payment,
  };

  Color _paymentColor(String method) => switch (method.toUpperCase()) {
    'CASH' => AppColors.success,
    'MPESA' || 'M-PESA' => const Color(0xFF4CAF50),
    'CARD' || 'CREDIT_CARD' || 'DEBIT_CARD' => AppColors.info,
    _ => AppColors.primary,
  };
}

// ═══ Stat Card Widget ═══
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.secondary, size: 20),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ═══ Date Range Selector Widget ═══
class _DateRangeSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(dateRangeProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(label: 'Today', selected: range.label == 'Today',
            onTap: () => ref.read(dateRangeProvider.notifier).setToday()),
          const SizedBox(width: 8),
          _FilterChip(label: 'This Week', selected: range.label == 'This Week',
            onTap: () => ref.read(dateRangeProvider.notifier).setThisWeek()),
          const SizedBox(width: 8),
          _FilterChip(label: 'This Month', selected: range.label == 'This Month',
            onTap: () => ref.read(dateRangeProvider.notifier).setThisMonth()),
          const SizedBox(width: 8),
          _FilterChip(
            label: range.label.contains('–') ? range.label : 'Custom',
            selected: range.label.contains('–'),
            onTap: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                ref.read(dateRangeProvider.notifier).setCustom(picked.start, picked.end);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}

// ═══ Summary Card ═══
class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold, color: color,
            )),
          const SizedBox(height: 4),
          Text(title, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ═══ Glassmorphism Report Tile ═══
class _GlassmorphismReportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _GlassmorphismReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
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
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
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
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══ Report Tile ═══
class _ReportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        title: Text(title),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
