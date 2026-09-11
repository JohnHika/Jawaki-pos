import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/auth_service.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _overdueInstallments = [];
  bool _isLoading = true;
  String? _loadError;
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
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
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
          _loadError = null;
        });
      }
      _loadOverdue();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Couldn\'t load customers. Check your connection and try again.';
        });
      }
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
    String? saveError;

    GlassBottomSheet.show(
      context,
      title: 'Add Customer',
      initialSize: 0.9,
      maxSize: 0.95,
      scrollable: true,
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
          final titleColor =
              isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
          final secondaryColor = isDark
              ? DesignColors.darkTextSecondary
              : DesignColors.textSecondary;
          final tertiaryColor = isDark
              ? DesignColors.darkTextTertiary
              : DesignColors.textTertiary;
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
                  Text(
                    'Contact details',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: tertiaryColor,
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
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
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
                  Container(
                    padding: const EdgeInsets.all(DesignSpacing.md),
                    decoration: BoxDecoration(
                      color: isDark
                          ? DesignColors.darkSurfaceElevated
                          : DesignColors.surfaceSubtle,
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      border: Border.all(
                        color: isDark
                            ? DesignColors.darkBorder
                            : DesignColors.surfaceBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: DesignColors.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                    DesignSpacing.radiusSm),
                              ),
                              child: const Icon(Icons.credit_score_rounded,
                                  color: DesignColors.accent, size: 18),
                            ),
                            const SizedBox(width: DesignSpacing.sm),
                            Expanded(
                              child: Text(
                                'Credit sale (optional)',
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: titleColor,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: DesignSpacing.xs),
                        Text(
                          'If they are taking stock today and paying later, record the amount and due date.',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: secondaryColor),
                        ),
                        const SizedBox(height: DesignSpacing.md),
                        TextFormField(
                          controller: creditAmountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Amount owed',
                            prefixText: 'KES ',
                            prefixIcon: Icon(Icons.request_quote_outlined),
                          ),
                          validator: (v) {
                            final amount =
                                double.tryParse(v?.trim() ?? '') ?? 0;
                            if (amount < 0) return 'Amount cannot be negative';
                            return null;
                          },
                        ),
                        const SizedBox(height: DesignSpacing.md),
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
                                    ? tertiaryColor
                                    : titleColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (saveError != null) ...[
                    const SizedBox(height: DesignSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(DesignSpacing.md),
                      decoration: BoxDecoration(
                        color: DesignColors.error.withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        border: Border.all(
                            color: DesignColors.error.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        saveError!,
                        style: const TextStyle(
                            color: DesignColors.error, fontSize: 12),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  GradientButton(
                    label: 'Save Customer',
                    isLoading: isSaving,
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheetState(() {
                              isSaving = true;
                              saveError = null;
                            });
                            final db = getIt<AppDatabase>();
                            final creditAmount =
                                double.tryParse(creditAmountCtrl.text.trim()) ??
                                    0;
                            if (creditAmount > 0 && firstDueDate == null) {
                              setSheetState(() {
                                isSaving = false;
                                saveError =
                                    'Select the first payment due date for this credit sale';
                              });
                              return;
                            }
                            try {
                              final customerId = await db.insertOrGetCustomer(
                                DateTime.now().millisecondsSinceEpoch.toString(),
                                nameCtrl.text.trim(),
                                phone: phoneCtrl.text.trim(),
                                location: locationCtrl.text.trim(),
                                notes: notesCtrl.text.trim(),
                                initialBalance: creditAmount,
                              );
                              // Queue customer for cross-device sync so
                              // other devices in the same branch see this
                              // customer too.
                              try {
                                final syncService = getIt<SyncService>();
                                final storage = getIt<StorageService>();
                                final auth = getIt<AuthService>();
                                await syncService.queueSyncItem(
                                  tableName: 'customers',
                                  recordId: customerId,
                                  action: SyncAction.create,
                                  eventType: SyncEventType.customerCreated,
                                  data: {
                                    'id': customerId,
                                    'name': nameCtrl.text.trim(),
                                    'phone': phoneCtrl.text.trim(),
                                    'address': locationCtrl.text.trim(),
                                    'notes': notesCtrl.text.trim(),
                                  },
                                  deviceId: storage.getDeviceId() ?? '',
                                  userId: auth.userId ?? '',
                                );
                              } catch (_) {
                                // Non-fatal: local customer is still saved;
                                // the periodic sync will retry.
                              }
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
                            } catch (_) {
                              if (sheetContext.mounted) {
                                setSheetState(() {
                                  isSaving = false;
                                  saveError =
                                      'Could not save this customer. Please try again.';
                                });
                              }
                            }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Customers',
        showBackButton: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, size: 20),
            tooltip: 'Add Customer',
            onPressed: _showAddCustomerSheet,
          ),
        ],
      ),
      body: PageContainer(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Overdue payments — who to follow up with today
            if (_overdueInstallments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(DesignSpacing.radiusMd),
                    onTap: () {
                      setState(() => _showDebtOnly = true);
                      _loadCustomers();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: DesignColors.error.withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        border: Border.all(
                            color: DesignColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_rounded,
                              color: DesignColors.error, size: 17),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_overdueInstallments.length} overdue payment${_overdueInstallments.length == 1 ? '' : 's'} — follow up today',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: DesignColors.error,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: DesignColors.error, size: 17),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: titleColor),
                decoration: InputDecoration(
                  hintText: 'Search customers...',
                  hintStyle: TextStyle(color: tertiaryColor),
                  filled: true,
                  fillColor: surface,
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 19, color: tertiaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: DesignColors.brand, width: 1.5),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon:
                              Icon(Icons.clear, size: 18, color: tertiaryColor),
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
            // Filter: everyone vs. customers who owe money
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All customers'),
                    visualDensity: VisualDensity.compact,
                    labelStyle: Theme.of(context).textTheme.bodySmall,
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
                    visualDensity: VisualDensity.compact,
                    labelStyle: Theme.of(context).textTheme.bodySmall,
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
                  : _loadError != null
                      ? EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Couldn\'t load customers',
                          subtitle: _loadError!,
                          iconColor: DesignColors.error,
                          actionLabel: 'Retry',
                          onAction: () => _loadCustomers(
                              query: _searchController.text.trim()),
                        )
                      : _customers.isEmpty
                          ? EmptyState(
                              icon: Icons.people_outlined,
                              title: _showDebtOnly
                                  ? 'No customers owe money'
                                  : 'No Customers Yet',
                              subtitle: _showDebtOnly
                                  ? 'Everyone is paid up'
                                  : 'Add your first customer to get started',
                              actionLabel:
                                  _showDebtOnly ? null : 'Add Customer',
                              onAction:
                                  _showDebtOnly ? null : _showAddCustomerSheet,
                            )
                          : RefreshIndicator(
                              onRefresh: () => _loadCustomers(),
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 100),
                                itemCount: _customers.length,
                                itemBuilder: (context, index) {
                                  final c = _customers[index];
                                  final balance =
                                      (c['balance'] as num?)?.toDouble() ?? 0;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Material(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(
                                          DesignSpacing.radiusMd),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(
                                            DesignSpacing.radiusMd),
                                        onTap: () => context
                                            .push('/customers/${c['id']}'),
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: surface,
                                            borderRadius: BorderRadius.circular(
                                                DesignSpacing.radiusMd),
                                            border: Border.all(
                                              color: balance > 0
                                                  ? DesignColors.error
                                                      .withValues(alpha: 0.35)
                                                  : border,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                backgroundColor: DesignColors
                                                    .brand
                                                    .withValues(alpha: 0.15),
                                                child: Text(
                                                  (c['name'] as String? ??
                                                          '?')[0]
                                                      .toUpperCase(),
                                                  style: const TextStyle(
                                                      color: DesignColors.brand,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(c['name'] ?? '',
                                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                            fontWeight:
                                                            FontWeight.w600,
                                                            color: titleColor,
                                                        )),
                                                    if ((c['phone'] ?? '')
                                                        .toString()
                                                        .isNotEmpty)
                                                      Text(c['phone'],
                                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                              color:
                                                              secondaryColor,
                                                          )),
                                                    if ((c['location'] ?? '')
                                                        .toString()
                                                        .isNotEmpty)
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                              Icons
                                                                  .location_on_outlined,
                                                              size: 11,
                                                              color:
                                                                  tertiaryColor),
                                                          const SizedBox(
                                                              width: 2),
                                                          Text(c['location'],
                                                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                                  color:
                                                                  tertiaryColor,
                                                              )),
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
                                                        style: DesignType.numeric(
                                                            color: DesignColors
                                                            .error,
                                                            fontWeight: FontWeight.w700,
                                                        ))
                                                  else
                                                    Text(
                                                        'KES ${(c['totalSpent'] as num?)?.toStringAsFixed(0) ?? '0'}',
                                                        style: DesignType.numeric(
                                                            color: DesignColors
                                                            .brand,
                                                            fontWeight: FontWeight.w700,
                                                        )),
                                                  Text(
                                                      '${c['totalPurchases'] ?? 0} purchases',
                                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                          color:
                                                          tertiaryColor,
                                                      )),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
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
    );
  }
}
