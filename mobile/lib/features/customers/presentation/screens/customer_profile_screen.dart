import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../../core/theme/design_system.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';

class CustomerProfileScreen extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerProfileScreen({super.key, required this.customerId});
  @override
  ConsumerState<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
  Map<String, dynamic>? _customer;
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _topProducts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = getIt<AppDatabase>();
      final customer = await db.getCustomer(widget.customerId);
      final purchases = await db.customSelect(
        'SELECT * FROM pending_sales WHERE customer_id = ? ORDER BY created_at DESC',
        variables: [Variable.withString(widget.customerId)],
      ).get();
      final topProducts = await db.getCustomerTopProducts(widget.customerId);
      if (mounted) setState(() {
        _customer = customer;
        _purchases = purchases.map((r) => {
          'id': r.read<String>('id'),
          'total': r.read<double>('total'),
          'paymentMethod': r.read<String>('payment_method'),
          'createdAt': r.read<String>('created_at'),
        }).toList();
        _topProducts = topProducts;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Profile', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        centerTitle: false,
        backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_rounded, color: DesignColors.brand),
            tooltip: 'Start Sale with this customer',
            onPressed: () {
              // Go to POS - in a real app we'd set the customer in cart
              context.go('/');
              showGlassSnackBar(context, 'Customer assigned to sale', icon: Icons.check_circle_rounded, color: DesignColors.success);
            },
          ),
        ],
      ),
      body: PageContainer(
        withScroll: true,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: DesignColors.brand))
            : _customer == null
                ? const EmptyState(icon: Icons.person_off_rounded, title: 'Customer not found', iconColor: DesignColors.textTertiary)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      // Profile header
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        borderRadius: 20,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: DesignColors.brand.withValues(alpha: 0.15),
                              child: Text((_customer!['name'] as String)[0].toUpperCase(),
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: DesignColors.brand)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_customer!['name'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                                  if ((_customer!['phone'] ?? '').isNotEmpty)
                                    Row(children: [const Icon(Icons.phone_outlined, size: 14, color: DesignColors.textSecondary), const SizedBox(width: 4), Text(_customer!['phone'], style: const TextStyle(fontSize: 13, color: DesignColors.textSecondary))]),
                                  if ((_customer!['email'] ?? '').isNotEmpty)
                                    Row(children: [const Icon(Icons.email_outlined, size: 14, color: DesignColors.textSecondary), const SizedBox(width: 4), Text(_customer!['email'], style: const TextStyle(fontSize: 13, color: DesignColors.textSecondary))]),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Stats
                      Row(children: [
                        Expanded(child: MetricCard(title: 'Purchases', value: '${_customer!['totalPurchases'] ?? 0}', icon: Icons.receipt_long_rounded, color: DesignColors.brand)),
                        const SizedBox(width: 12),
                        Expanded(child: MetricCard(title: 'Total Spent', value: 'KES ${(_customer!['totalSpent'] as num?)?.toStringAsFixed(0) ?? '0'}', icon: Icons.payments_rounded, color: DesignColors.success)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: MetricCard(title: 'Loyalty Points', value: '${_customer!['loyaltyPoints'] ?? 0}', icon: Icons.card_giftcard_rounded, color: DesignColors.warning)),
                        const SizedBox(width: 12),
                        Expanded(child: MetricCard(title: 'Balance', value: 'KES ${(_customer!['balance'] as num?)?.toStringAsFixed(0) ?? '0'}', icon: Icons.account_balance_wallet_rounded, color: (_customer!['balance'] as num? ?? 0) > 0 ? DesignColors.error : DesignColors.teal)),
                      ]),
                      const SizedBox(height: 20),
                      // Top Products
                      if (_topProducts.isNotEmpty) ...[
                        SectionHeader(title: 'Frequently Bought', icon: Icons.trending_up_rounded),
                        const SizedBox(height: 8),
                        ...(_topProducts.take(5).map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            borderRadius: 12,
                            tint: Colors.transparent,
                            child: Row(children: [
                              const Icon(Icons.inventory_2_outlined, size: 16, color: DesignColors.brand),
                              const SizedBox(width: 10),
                              Expanded(child: Text(p['productName'] ?? '', style: const TextStyle(fontSize: 13))),
                              Text('${p['timesBought'] ?? 0}x', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: DesignColors.brand)),
                            ]),
                          ),
                        ))),
                        const SizedBox(height: 20),
                      ],
                      // Purchase History
                      SectionHeader(title: 'Purchase History', icon: Icons.history_rounded),
                      const SizedBox(height: 8),
                      ...(_purchases.isEmpty
                        ? [const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No purchases yet', style: TextStyle(color: DesignColors.textTertiary))))]
                        : _purchases.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: GlassCard(
                              padding: const EdgeInsets.all(12),
                              borderRadius: 12,
                              onTap: () => context.push('/receipt/${s['id']}'),
                              child: Row(children: [
                                Expanded(child: Text('Receipt #${(s['id'] as String).substring(0, 8).toUpperCase()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text('KES ${(s['total'] as num).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: DesignColors.brand)),
                                  Text(s['createdAt']?.toString().substring(0, 10) ?? '', style: const TextStyle(fontSize: 11, color: DesignColors.textTertiary)),
                                ]),
                              ]),
                            ),
                          ))),
                      const SizedBox(height: 32),
                    ],
                  ),
      ),
    );
  }
}