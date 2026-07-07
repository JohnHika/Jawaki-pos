import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../../core/theme/design_system.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../sales/presentation/providers/cart_provider.dart';

class CustomerProfileScreen extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerProfileScreen({super.key, required this.customerId});
  @override
  ConsumerState<CustomerProfileScreen> createState() =>
      _CustomerProfileScreenState();
}

class _CustomerProfileScreenState
    extends ConsumerState<CustomerProfileScreen> {
  Map<String, dynamic>? _customer;
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _installments = [];
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
      final installments =
          await db.getCustomerInstallments(widget.customerId);
      if (mounted) {
        setState(() {
          _customer = customer;
          _purchases = purchases
              .map((r) => {
                    'id': r.read<String>('id'),
                    'total': r.read<double>('total'),
                    'paymentMethod': r.read<String>('payment_method'),
                    'createdAt': r.read<String>('created_at'),
                  })
              .toList();
          _topProducts = topProducts;
          _installments = installments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddInstallmentSheet() {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime? dueDate;
    bool isSaving = false;

    GlassBottomSheet.show(
      context,
      title: 'Add Payment Due',
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount due',
                    prefixText: 'KES ',
                    prefixIcon: Icon(Icons.request_quote_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: sheetContext,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setSheetState(() => dueDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Due date',
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                    child: Text(
                      dueDate == null
                          ? 'Select a date'
                          : '${dueDate!.day}/${dueDate!.month}/${dueDate!.year}',
                      style: TextStyle(
                        color: dueDate == null
                            ? DesignColors.textTertiary
                            : DesignColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                GradientButton(
                  label: 'Save',
                  isLoading: isSaving,
                  onPressed: isSaving
                      ? null
                      : () async {
                          final amount =
                              double.tryParse(amountCtrl.text.trim());
                          if (amount == null || amount <= 0 || dueDate == null) {
                            showGlassSnackBar(
                              sheetContext,
                              'Enter an amount and due date',
                              icon: Icons.error_outline_rounded,
                              color: DesignColors.error,
                            );
                            return;
                          }
                          setSheetState(() => isSaving = true);
                          final db = getIt<AppDatabase>();
                          await db.addCustomerInstallment(
                            widget.customerId,
                            amount,
                            dueDate!,
                            note: noteCtrl.text.trim(),
                          );
                          await db.updateCustomerBalance(
                              widget.customerId, amount);
                          if (!sheetContext.mounted) return;
                          Navigator.of(sheetContext).pop();
                          _loadData();
                        },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _markInstallmentPaid(Map<String, dynamic> installment) async {
    final db = getIt<AppDatabase>();
    await db.markInstallmentPaid(installment['id'] as String);
    await db.updateCustomerBalance(
        widget.customerId, -(installment['amount'] as double));
    _loadData();
    if (!mounted) return;
    showGlassSnackBar(
      context,
      'Payment recorded',
      icon: Icons.check_circle_rounded,
      color: DesignColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Customer Profile',
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_rounded,
                color: DesignColors.brand),
            tooltip: 'Start Sale with this customer',
            onPressed: _customer == null
                ? null
                : () {
                    ref.read(cartProvider.notifier).setCustomer(
                          widget.customerId,
                          customerName: _customer!['name'] as String?,
                        );
                    context.go('/');
                    showGlassSnackBar(context,
                        '${_customer!['name']} assigned to sale',
                        icon: Icons.check_circle_rounded,
                        color: DesignColors.success);
                  },
          ),
        ],
      ),
      body: PageContainer(
        withScroll: true,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: DesignColors.brand))
            : _customer == null
                ? const EmptyState(
                    icon: Icons.person_off_rounded,
                    title: 'Customer not found',
                    iconColor: DesignColors.textTertiary)
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
                              backgroundColor:
                                  DesignColors.brand.withValues(alpha: 0.15),
                              child: Text(
                                  (_customer!['name'] as String)[0]
                                      .toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: DesignColors.brand)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_customer!['name'],
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5)),
                                  if ((_customer!['phone'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Row(children: [
                                      const Icon(Icons.phone_outlined,
                                          size: 14,
                                          color: DesignColors.textSecondary),
                                      const SizedBox(width: 4),
                                      Text(_customer!['phone'],
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color:
                                                  DesignColors.textSecondary))
                                    ]),
                                  if ((_customer!['location'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Row(children: [
                                      const Icon(Icons.location_on_outlined,
                                          size: 14,
                                          color: DesignColors.textSecondary),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(_customer!['location'],
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: DesignColors
                                                    .textSecondary)),
                                      ),
                                    ]),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Stats
                      Row(children: [
                        Expanded(
                            child: MetricCard(
                                title: 'Purchases',
                                value: '${_customer!['totalPurchases'] ?? 0}',
                                icon: Icons.receipt_long_rounded,
                                color: DesignColors.brand)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: MetricCard(
                                title: 'Total Spent',
                                value:
                                    'KES ${(_customer!['totalSpent'] as num?)?.toStringAsFixed(0) ?? '0'}',
                                icon: Icons.payments_rounded,
                                color: DesignColors.success)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: MetricCard(
                                title: 'Loyalty Points',
                                value: '${_customer!['loyaltyPoints'] ?? 0}',
                                icon: Icons.card_giftcard_rounded,
                                color: DesignColors.warning)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: MetricCard(
                                title: 'Balance Owed',
                                value:
                                    'KES ${(_customer!['balance'] as num?)?.toStringAsFixed(0) ?? '0'}',
                                icon: Icons.account_balance_wallet_rounded,
                                color: (_customer!['balance'] as num? ?? 0) > 0
                                    ? DesignColors.error
                                    : Colors.teal)),
                      ]),
                      const SizedBox(height: 20),
                      // Payment schedule (installments)
                      SectionHeader(
                        title: 'Payment Schedule',
                        icon: Icons.event_note_rounded,
                        trailing: TextButton.icon(
                          onPressed: _showAddInstallmentSheet,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_installments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text(
                            'No scheduled payments. Add one when this customer takes stock on credit.',
                            style: TextStyle(
                                fontSize: 13, color: DesignColors.textTertiary),
                          ),
                        )
                      else
                        ..._installments.map((inst) {
                          final dueDate = DateTime.parse(inst['dueDate']);
                          final isPaid = inst['status'] == 'paid';
                          final isOverdue = !isPaid &&
                              dueDate.isBefore(DateTime.now());
                          final statusColor = isPaid
                              ? DesignColors.success
                              : isOverdue
                                  ? DesignColors.error
                                  : DesignColors.warning;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GlassCard(
                              padding: const EdgeInsets.all(12),
                              borderRadius: 12,
                              borderColor: statusColor.withValues(alpha: 0.3),
                              child: Row(
                                children: [
                                  Icon(
                                    isPaid
                                        ? Icons.check_circle_rounded
                                        : isOverdue
                                            ? Icons.warning_rounded
                                            : Icons.schedule_rounded,
                                    color: statusColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'KES ${(inst['amount'] as num).toStringAsFixed(0)}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14),
                                        ),
                                        Text(
                                          isPaid
                                              ? 'Paid'
                                              : isOverdue
                                                  ? 'Overdue — was due ${dueDate.day}/${dueDate.month}/${dueDate.year}'
                                                  : 'Due ${dueDate.day}/${dueDate.month}/${dueDate.year}',
                                          style: TextStyle(
                                              fontSize: 12, color: statusColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isPaid)
                                    TextButton(
                                      onPressed: () =>
                                          _markInstallmentPaid(inst),
                                      child: const Text('Mark Paid'),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 20),
                      // Top Products
                      if (_topProducts.isNotEmpty) ...[
                        SectionHeader(
                            title: 'Frequently Bought',
                            icon: Icons.trending_up_rounded),
                        const SizedBox(height: 8),
                        ...(_topProducts.take(5).map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: GlassCard(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                borderRadius: 12,
                                tint: Colors.transparent,
                                child: Row(children: [
                                  const Icon(Icons.inventory_2_outlined,
                                      size: 16, color: DesignColors.brand),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(p['productName'] ?? '',
                                          style: const TextStyle(fontSize: 13))),
                                  Text('${p['timesBought'] ?? 0}x',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: DesignColors.brand)),
                                ]),
                              ),
                            ))),
                        const SizedBox(height: 20),
                      ],
                      // Purchase History
                      SectionHeader(
                          title: 'Purchase History',
                          icon: Icons.history_rounded),
                      const SizedBox(height: 8),
                      ...(_purchases.isEmpty
                          ? [
                              const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                      child: Text('No purchases yet',
                                          style: TextStyle(
                                              color:
                                                  DesignColors.textTertiary))))
                            ]
                          : _purchases.map((s) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: GlassCard(
                                  padding: const EdgeInsets.all(12),
                                  borderRadius: 12,
                                  onTap: () =>
                                      context.push('/receipt/${s['id']}'),
                                  child: Row(children: [
                                    Expanded(
                                        child: Text(
                                            'Receipt #${(s['id'] as String).substring(0, 8).toUpperCase()}',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600))),
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                              'KES ${(s['total'] as num).toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: DesignColors.brand)),
                                          Text(
                                              s['createdAt']
                                                      ?.toString()
                                                      .substring(0, 10) ??
                                                  '',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: DesignColors
                                                      .textTertiary)),
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
