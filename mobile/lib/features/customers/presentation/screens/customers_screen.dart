import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _overdueInstallments = [];
  bool _isLoading = true;
  bool _showDebtOnly = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadOverdue() async {
    final db = getIt<AppDatabase>();
    final overdue = await db.getOverdueInstallments();
    if (mounted) setState(() => _overdueInstallments = overdue);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers({String? query}) async {
    setState(() => _isLoading = true);
    try {
      final db = getIt<AppDatabase>();
      final customers = _showDebtOnly
          ? await db.getCustomersWithDebt()
          : (query != null && query.isNotEmpty)
              ? await db.searchCustomers(query)
              : await db.getAllCustomers();
      if (mounted) {
        setState(() {
          _customers = customers;
          _isLoading = false;
        });
      }
      _loadOverdue();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Add customer — captures what a shop actually needs to track a credit
  // client: name, a phone number to follow up on, where their shop is, and
  // (optionally) the terms of a credit sale being recorded right now.
  void _showAddCustomerSheet() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final creditAmountCtrl = TextEditingController();
    DateTime? firstDueDate;
    bool isSaving = false;

    GlassBottomSheet.show(
      context,
      title: 'Add Customer',
      initialSize: 0.9,
      maxSize: 0.95,
      scrollable: true,
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Contact details',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: DesignColors.textTertiary,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Customer or shop name',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '07xx xxx xxx',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'A phone number is needed to follow up on payments'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: locationCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Shop location',
                      hintText: 'e.g. Gikomba, Stall 14',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Credit sale (optional)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: DesignColors.textTertiary,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Record what this customer owes right now if they\'re taking stock today and paying later.',
                    style: TextStyle(
                        fontSize: 12, color: DesignColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: creditAmountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount owed',
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
                        initialDate:
                            DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setSheetState(() => firstDueDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'First payment due',
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                      child: Text(
                        firstDueDate == null
                            ? 'Select a date'
                            : '${firstDueDate!.day}/${firstDueDate!.month}/${firstDueDate!.year}',
                        style: TextStyle(
                          color: firstDueDate == null
                              ? DesignColors.textTertiary
                              : DesignColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GradientButton(
                    label: 'Save Customer',
                    isLoading: isSaving,
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheetState(() => isSaving = true);
                            final db = getIt<AppDatabase>();
                            final creditAmount =
                                double.tryParse(creditAmountCtrl.text.trim()) ??
                                    0;
                            final customerId = await db.insertOrGetCustomer(
                              DateTime.now().millisecondsSinceEpoch.toString(),
                              nameCtrl.text.trim(),
                              phone: phoneCtrl.text.trim(),
                              location: locationCtrl.text.trim(),
                              notes: notesCtrl.text.trim(),
                              initialBalance: creditAmount,
                            );
                            if (creditAmount > 0 && firstDueDate != null) {
                              await db.addCustomerInstallment(
                                customerId,
                                creditAmount,
                                firstDueDate!,
                                note: 'Initial credit sale',
                              );
                            }
                            if (!sheetContext.mounted) return;
                            Navigator.of(sheetContext).pop();
                            _loadCustomers();
                            if (!mounted) return;
                            showGlassSnackBar(
                              context,
                              '${nameCtrl.text.trim()} added',
                              icon: Icons.check_circle_rounded,
                              color: DesignColors.success,
                            );
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(title: 'Customers'),
      body: PageContainer(
        child: Column(
          children: [
            // Overdue payments — who to follow up with today
            if (_overdueInstallments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  borderRadius: 14,
                  borderColor: DesignColors.error.withValues(alpha: 0.3),
                  tint: DesignColors.error.withValues(alpha: 0.06),
                  onTap: () {
                    setState(() => _showDebtOnly = true);
                    _loadCustomers();
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.warning_rounded,
                          color: DesignColors.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_overdueInstallments.length} overdue payment${_overdueInstallments.length == 1 ? '' : 's'} — follow up today',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DesignColors.error),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: DesignColors.error, size: 18),
                    ],
                  ),
                ),
              ),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                borderRadius: 12,
                tint: Colors.transparent,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search customers...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    border: InputBorder.none,
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _loadCustomers();
                            })
                        : null,
                  ),
                  onChanged: (v) {
                    setState(() {});
                    _loadCustomers(query: v);
                  },
                ),
              ),
            ),
            // Filter: everyone vs. customers who owe money
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All customers'),
                    selected: !_showDebtOnly,
                    onSelected: (_) {
                      setState(() => _showDebtOnly = false);
                      _loadCustomers();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Owes money'),
                    avatar: const Icon(Icons.account_balance_wallet_outlined,
                        size: 16),
                    selected: _showDebtOnly,
                    selectedColor: DesignColors.error.withValues(alpha: 0.15),
                    onSelected: (_) {
                      setState(() => _showDebtOnly = true);
                      _loadCustomers();
                    },
                  ),
                ],
              ),
            ),
            // Customer list
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: DesignColors.brand))
                  : _customers.isEmpty
                      ? EmptyState(
                          icon: Icons.people_outlined,
                          title: _showDebtOnly
                              ? 'No customers owe money'
                              : 'No Customers Yet',
                          subtitle: _showDebtOnly
                              ? 'Everyone is paid up'
                              : 'Add your first customer to get started',
                          iconColor: DesignColors.textTertiary,
                          actionLabel: _showDebtOnly ? null : 'Add Customer',
                          onAction: _showDebtOnly ? null : _showAddCustomerSheet,
                        )
                      : RefreshIndicator(
                          onRefresh: () => _loadCustomers(),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: _customers.length,
                            itemBuilder: (context, index) {
                              final c = _customers[index];
                              final balance =
                                  (c['balance'] as num?)?.toDouble() ?? 0;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GlassCard(
                                  padding: const EdgeInsets.all(12),
                                  borderRadius: 14,
                                  borderColor: balance > 0
                                      ? DesignColors.error.withValues(alpha: 0.3)
                                      : null,
                                  onTap: () =>
                                      context.push('/customers/${c['id']}'),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: DesignColors.brand
                                            .withValues(alpha: 0.15),
                                        child: Text(
                                          (c['name'] as String? ?? '?')[0]
                                              .toUpperCase(),
                                          style: const TextStyle(
                                              color: DesignColors.brand,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(c['name'] ?? '',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14)),
                                            if ((c['phone'] ?? '')
                                                .toString()
                                                .isNotEmpty)
                                              Text(c['phone'],
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: DesignColors
                                                          .textSecondary)),
                                            if ((c['location'] ?? '')
                                                .toString()
                                                .isNotEmpty)
                                              Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                      Icons
                                                          .location_on_outlined,
                                                      size: 11,
                                                      color: DesignColors
                                                          .textTertiary),
                                                  const SizedBox(width: 2),
                                                  Text(c['location'],
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          color: DesignColors
                                                              .textTertiary)),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          if (balance > 0)
                                            Text(
                                                'Owes KES ${balance.toStringAsFixed(0)}',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: DesignColors.error))
                                          else
                                            Text(
                                                'KES ${(c['totalSpent'] as num?)?.toStringAsFixed(0) ?? '0'}',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: DesignColors.brand)),
                                          Text(
                                              '${c['totalPurchases'] ?? 0} purchases',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: DesignColors
                                                      .textTertiary)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCustomerSheet,
        backgroundColor: DesignColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Customer'),
      ),
    );
  }
}
