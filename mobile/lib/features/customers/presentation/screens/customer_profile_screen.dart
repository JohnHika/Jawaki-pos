import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../../core/theme/design_system.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../sales/presentation/providers/cart_provider.dart';
import '../../../finance/domain/bulk_allocation.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/api_message.dart';
import '../widgets/credit_limit_card.dart';
import '../../../statements/presentation/widgets/send_statement_button.dart';

class CustomerProfileScreen extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerProfileScreen({super.key, required this.customerId});
  @override
  ConsumerState<CustomerProfileScreen> createState() =>
      _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
  Map<String, dynamic>? _customer;
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _installments = [];
  bool _isLoading = true;
  String? _loadError;
  bool _purchasesLoadFailed = false;
  bool _installmentsLoadFailed = false;
  final Set<String> _savingInstallmentIds = <String>{};

  String get _customerName {
    final name = _customer?['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Customer' : name;
  }

  String get _customerInitial => _customerName == 'Customer'
      ? 'C'
      : String.fromCharCode(_customerName.runes.first).toUpperCase();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant CustomerProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customerId != widget.customerId) {
      _customer = null;
      _purchases = [];
      _topProducts = [];
      _installments = [];
      _loadError = null;
      _purchasesLoadFailed = false;
      _installmentsLoadFailed = false;
      _isLoading = true;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = _customer == null;
      _loadError = null;
    });
    try {
      final db = getIt<AppDatabase>();
      final customer = await db.getCustomer(widget.customerId);
      if (customer == null) {
        if (!mounted) return;
        setState(() {
          _customer = null;
          _purchases = [];
          _topProducts = [];
          _installments = [];
          _isLoading = false;
          _loadError = 'This customer could not be found.';
          _purchasesLoadFailed = false;
          _installmentsLoadFailed = false;
        });
        return;
      }

      Future<T?> capture<T>(Future<T> request) async {
        try {
          return await request;
        } catch (_) {
          return null;
        }
      }

      final values = await Future.wait<dynamic>([
        capture(db.customSelect(
          'SELECT * FROM pending_sales WHERE customer_id = ? ORDER BY created_at DESC',
          variables: [Variable.withString(widget.customerId)],
        ).get()),
        capture(db.getCustomerTopProducts(widget.customerId)),
        capture(db.getCustomerInstallments(widget.customerId)),
      ]);
      final purchases = values[0] as List<QueryRow>?;
      final topProducts = values[1] as List<Map<String, dynamic>>?;
      final installments = values[2] as List<Map<String, dynamic>>?;
      if (mounted) {
        setState(() {
          _customer = customer;
          if (purchases != null) {
            _purchases = purchases
                .map((r) => {
                      'id': r.read<String>('id'),
                      'total': r.read<double>('total'),
                      'paymentMethod': r.read<String>('payment_method'),
                      'createdAt': r.read<String>('created_at'),
                    })
                .toList();
          }
          if (topProducts != null) _topProducts = topProducts;
          if (installments != null) _installments = installments;
          _isLoading = false;
          _purchasesLoadFailed = purchases == null;
          _installmentsLoadFailed = installments == null;
          _loadError =
              purchases == null || topProducts == null || installments == null
                  ? 'Some customer activity could not be loaded. Try again.'
                  : null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load this customer. Try again.';
        });
      }
    }
  }

  double get _unscheduledBalance {
    final balance = (_customer?['balance'] as num?)?.toDouble() ?? 0;
    final alreadyScheduled = _installments
        .where((item) => item['status']?.toString().toLowerCase() != 'paid')
        .fold<double>(
          0,
          (total, item) => total + ((item['amount'] as num?)?.toDouble() ?? 0),
        );
    final remaining = balance - alreadyScheduled;
    return remaining > 0 ? remaining : 0;
  }

  Future<void> _showAddInstallmentSheet() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime? dueDate;
    bool isSaving = false;
    String? error;

    try {
      await GlassBottomSheet.show<void>(
        context,
        title: 'Add Payment Due',
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20,
                  20 + MediaQuery.of(sheetContext).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Schedule part of the current balance. This will not add new debt.',
                    style:
                        Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                              color: isDark
                                  ? DesignColors.darkTextSecondary
                                  : DesignColors.textSecondary,
                            ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Available to schedule: ${formatMoney(_unscheduledBalance)}',
                    style: DesignType.numeric(
                      color: DesignColors.brand,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                        initialDate:
                            DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null && sheetContext.mounted) {
                        setSheetState(() {
                          dueDate = picked;
                          error = null;
                        });
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
                              ? (isDark
                                  ? DesignColors.darkTextTertiary
                                  : DesignColors.textTertiary)
                              : (isDark
                                  ? DesignColors.darkTextPrimary
                                  : DesignColors.textPrimary),
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
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: const TextStyle(color: DesignColors.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  GradientButton(
                    label: 'Save due date',
                    isLoading: isSaving,
                    onPressed: isSaving
                        ? null
                        : () async {
                            final amount = double.tryParse(
                                amountCtrl.text.trim().replaceAll(',', ''));
                            if (amount == null ||
                                !amount.isFinite ||
                                amount <= 0 ||
                                dueDate == null) {
                              setSheetState(() {
                                error = 'Enter a valid amount and due date.';
                              });
                              return;
                            }
                            final available = _unscheduledBalance;
                            if (amount > available + 0.005) {
                              setSheetState(() {
                                error = 'Only ${formatMoney(available)} is '
                                    'available to schedule.';
                              });
                              return;
                            }
                            setSheetState(() {
                              isSaving = true;
                              error = null;
                            });
                            try {
                              await getIt<AppDatabase>().addCustomerInstallment(
                                widget.customerId,
                                amount,
                                dueDate!,
                                note: noteCtrl.text.trim(),
                              );
                              if (!sheetContext.mounted) return;
                              Navigator.of(sheetContext).pop();
                              await _loadData();
                            } catch (_) {
                              if (!sheetContext.mounted) return;
                              setSheetState(() {
                                isSaving = false;
                                error =
                                    'Could not save this due date. Try again.';
                              });
                            }
                          },
                  ),
                ],
              ),
            );
          },
        ),
      );
    } finally {
      amountCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<void> _confirmMarkInstallmentPaid(
    Map<String, dynamic> installment,
  ) async {
    final amount = (installment['amount'] as num?)?.toDouble() ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record payment received?'),
        content: Text(
          'This records ${formatMoney(amount)} of cash in Finance and reduces '
          '${_customer?['name'] ?? 'the customer'}’s outstanding balance. '
          'Continue only after you have received the cash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Record received'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _markInstallmentPaid(installment);
    }
  }

  Future<void> _markInstallmentPaid(Map<String, dynamic> installment) async {
    final id = installment['id']?.toString();
    if (id == null || id.isEmpty || _savingInstallmentIds.contains(id)) return;
    setState(() => _savingInstallmentIds.add(id));
    try {
      final amount = (installment['amount'] as num?)?.toDouble() ?? 0;
      final localBalance = (_customer?['balance'] as num?)?.toDouble() ?? 0;
      if (amount <= 0 || amount > localBalance + 0.005) {
        throw StateError(
          'The customer balance changed. Refresh the profile and try again.',
        );
      }

      final auth = getIt<AuthService>();
      final branchId = auth.branchId;
      if (branchId == null || branchId.isEmpty) {
        throw StateError('Select a branch before recording a collection.');
      }

      // Use server receivables as the source of truth. A local schedule row
      // alone must never make a debt look collected in Finance.
      final api = getIt<ApiClient>();
      final receivables = await api.getRetailReceivables(branchId);
      final savedAllocations = installment['collectionAllocations']?.toString();
      var allocationsJson = savedAllocations;
      if (allocationsJson == null || allocationsJson.isEmpty) {
        final customerReceivables = receivables
            .where((receivable) =>
                receivable.customerId == widget.customerId &&
                receivable.outstandingAmount > 0.005)
            .toList();
        final plan = allocateOldestFirst(customerReceivables, amount);
        if (plan.allocations.isEmpty || plan.unallocated > 0.005) {
          throw StateError(
            'No matching open cloud balance was found for this customer. '
            'Sync the customer’s sales and refresh before recording cash.',
          );
        }
        allocationsJson = jsonEncode(plan.allocations
            .map((allocation) => <String, dynamic>{
                  'receivableId': allocation.receivableId,
                  'amount': allocation.amount,
                })
            .toList());
        allocationsJson = await getIt<AppDatabase>()
            .prepareInstallmentCollection(id, allocationsJson);
      }

      final decoded = jsonDecode(allocationsJson);
      if (decoded is! List || decoded.isEmpty) {
        throw StateError('The saved collection details are invalid.');
      }
      final allocations = decoded.map((value) {
        if (value is! Map) throw StateError('The saved collection is invalid.');
        final row = Map<String, dynamic>.from(value);
        final receivableId = row['receivableId']?.toString() ?? '';
        final allocationAmount = (row['amount'] as num?)?.toDouble() ?? 0;
        if (receivableId.isEmpty || allocationAmount <= 0) {
          throw StateError('The saved collection is invalid.');
        }
        return ReceivableAllocation(
          receivableId: receivableId,
          amount: allocationAmount,
        );
      }).toList();

      await api.recordRetailBulkPayment(
        branchId: branchId,
        method: 'CASH',
        allocations: allocations
            .map((allocation) => <String, dynamic>{
                  'receivableId': allocation.receivableId,
                  'amount': allocation.amount,
                })
            .toList(),
        offlineId: id,
      );
      final recorded = await getIt<AppDatabase>().markInstallmentPaid(id);
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      showGlassSnackBar(
        context,
        recorded
            ? 'Cash collection recorded in Finance and customer balance updated.'
            : 'This collection was already recorded. Customer details refreshed.',
        icon:
            recorded ? Icons.check_circle_rounded : Icons.info_outline_rounded,
        color: recorded ? DesignColors.success : DesignColors.warning,
      );
    } catch (_) {
      if (!mounted) return;
      await _loadData();
      if (!mounted) return;
      final error = _;
      showGlassSnackBar(
        context,
        error is StateError
            ? error.message.toString()
            : 'Could not record cash. The customer balance was not changed. ${apiErrorMessage(error)}',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    } finally {
      if (mounted) setState(() => _savingInstallmentIds.remove(id));
    }
  }

  String _shortReceiptId(String id) =>
      (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();

  String _purchaseDateLabel(Object? value) {
    final raw = value?.toString() ?? '';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date != null) return '${date.day}/${date.month}/${date.year}';
    return raw.length > 10 ? raw.substring(0, 10) : raw;
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
        title: 'Customer Profile',
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_rounded,
                color: DesignColors.accent),
            tooltip: 'Start Sale with this customer',
            onPressed: _customer == null
                ? null
                : () {
                    ref.read(cartProvider.notifier).setCustomer(
                          widget.customerId,
                          customerName: _customerName,
                        );
                    context.go('/');
                    showGlassSnackBar(
                        context, '$_customerName assigned to sale',
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
                ? EmptyState(
                    icon: Icons.person_off_rounded,
                    title: _loadError == 'This customer could not be found.'
                        ? 'Customer not found'
                        : "Couldn't load customer",
                    subtitle: _loadError,
                    actionLabel:
                        _loadError == 'Could not load this customer. Try again.'
                            ? 'Try again'
                            : null,
                    onAction:
                        _loadError == 'Could not load this customer. Try again.'
                            ? _loadData
                            : null,
                    iconColor: _loadError == 'This customer could not be found.'
                        ? DesignColors.textTertiary
                        : DesignColors.error,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_loadError != null) ...[
                        InlineRetryNotice(
                          message: _loadError!,
                          onRetry: _loadData,
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 8),
                      // Profile header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: surface,
                          border: Border.all(color: border),
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusLg),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor:
                                  DesignColors.brand.withValues(alpha: 0.15),
                              child: Text(_customerInitial,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: DesignColors.brand,
                                      )),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_customerName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.5,
                                            color: titleColor,
                                          )),
                                  if ((_customer!['phone'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Row(children: [
                                      Icon(Icons.phone_outlined,
                                          size: 14, color: secondaryColor),
                                      const SizedBox(width: 4),
                                      Text(_customer!['phone'],
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: secondaryColor,
                                              ))
                                    ]),
                                  if ((_customer!['location'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Row(children: [
                                      Icon(Icons.location_on_outlined,
                                          size: 14, color: secondaryColor),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(_customer!['location'],
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: secondaryColor,
                                                )),
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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const gap = 12.0;
                          final columns = constraints.maxWidth < 380 ? 1 : 2;
                          final width = columns == 1
                              ? constraints.maxWidth
                              : (constraints.maxWidth - gap) / 2;
                          final metrics = <Widget>[
                            MetricCard(
                              title: 'Purchases',
                              value: '${_customer!['totalPurchases'] ?? 0}',
                              icon: Icons.receipt_long_rounded,
                              color: DesignColors.brand,
                            ),
                            MetricCard(
                              title: 'Total Spent',
                              value:
                                  'KES ${(_customer!['totalSpent'] as num?)?.toStringAsFixed(0) ?? '0'}',
                              icon: Icons.payments_rounded,
                              color: DesignColors.success,
                            ),
                            MetricCard(
                              title: 'Loyalty Points',
                              value: '${_customer!['loyaltyPoints'] ?? 0}',
                              icon: Icons.card_giftcard_rounded,
                              color: DesignColors.warning,
                            ),
                            MetricCard(
                              title: 'Balance Owed',
                              value:
                                  'KES ${(_customer!['balance'] as num?)?.toStringAsFixed(0) ?? '0'}',
                              icon: Icons.account_balance_wallet_rounded,
                              color: (_customer!['balance'] as num? ?? 0) > 0
                                  ? DesignColors.error
                                  : DesignColors.success,
                            ),
                          ];
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: metrics
                                .map((metric) => SizedBox(
                                      width: width,
                                      child: metric,
                                    ))
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      CreditLimitCard(
                        customerId: widget.customerId,
                        customerName: _customerName,
                      ),
                      if ((_customer!['balance'] as num? ?? 0) > 0) ...[
                        const SizedBox(height: 12),
                        SendStatementButton(
                          customerId: widget.customerId,
                          name: _customerName,
                          phone: _customer!['phone'] as String?,
                        ),
                      ],
                      const SizedBox(height: 20),
                      // Payment schedule (installments)
                      SectionHeader(
                        title: 'Payment Schedule',
                        icon: Icons.event_note_rounded,
                        trailing: TextButton.icon(
                          onPressed: _unscheduledBalance > 0.005
                              ? _showAddInstallmentSheet
                              : null,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add due date'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_installmentsLoadFailed)
                        InlineRetryNotice(
                          message: 'Could not load scheduled due dates.',
                          onRetry: _loadData,
                        )
                      else if (_installments.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text(
                            (_customer!['balance'] as num? ?? 0) > 0
                                ? 'No due dates yet. Schedule part of the current balance when you agree on a repayment date.'
                                : 'There is no outstanding balance to schedule.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: tertiaryColor,
                                    ),
                          ),
                        )
                      else
                        ..._installments.map((inst) {
                          final dueDate = DateTime.tryParse(
                              inst['dueDate']?.toString() ?? '');
                          final isPaid =
                              inst['status']?.toString().toLowerCase() ==
                                  'paid';
                          final today = DateTime.now();
                          final isOverdue = !isPaid &&
                              dueDate != null &&
                              dueDate.isBefore(
                                  DateTime(today.year, today.month, today.day));
                          final installmentId = inst['id']?.toString() ?? '';
                          final isSaving =
                              _savingInstallmentIds.contains(installmentId);
                          final note = inst['note']?.toString().trim() ?? '';
                          final statusColor = isPaid
                              ? DesignColors.success
                              : isOverdue
                                  ? DesignColors.error
                                  : DesignColors.warning;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: surface,
                                border: Border.all(
                                    color: statusColor.withValues(alpha: 0.4)),
                              ),
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
                                          formatMoney((inst['amount'] as num)),
                                          style: DesignType.numeric(
                                            color: titleColor,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          isPaid
                                              ? 'Paid'
                                              : isOverdue
                                                  ? 'Overdue — was due ${dueDate.day}/${dueDate.month}/${dueDate.year}'
                                                  : dueDate == null
                                                      ? 'Due date unavailable'
                                                      : 'Due ${dueDate.day}/${dueDate.month}/${dueDate.year}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: statusColor,
                                              ),
                                        ),
                                        if (note.isNotEmpty)
                                          Text(
                                            note,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                    color: tertiaryColor),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (!isPaid)
                                    TextButton(
                                      onPressed: isSaving
                                          ? null
                                          : () =>
                                              _confirmMarkInstallmentPaid(inst),
                                      child: isSaving
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Record'),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      if (_unscheduledBalance <= 0.005 &&
                          (_customer!['balance'] as num? ?? 0) > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                          child: Text(
                            'The full outstanding balance already has due dates.',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: tertiaryColor),
                          ),
                        ),
                      const SizedBox(height: 20),
                      // Top Products
                      if (_topProducts.isNotEmpty) ...[
                        const SectionHeader(
                            title: 'Frequently Bought',
                            icon: Icons.trending_up_rounded),
                        const SizedBox(height: 8),
                        ...(_topProducts.take(5).map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                    border: Border.all(color: border)),
                                child: Row(children: [
                                  const Icon(Icons.inventory_2_outlined,
                                      size: 16, color: DesignColors.brand),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(p['productName'] ?? '',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: titleColor,
                                              ))),
                                  Text('${p['timesBought'] ?? 0}x',
                                      style: DesignType.numeric(
                                        color: DesignColors.brand,
                                        fontWeight: FontWeight.w700,
                                      )),
                                ]),
                              ),
                            ))),
                        const SizedBox(height: 20),
                      ],
                      // Purchase History
                      const SectionHeader(
                          title: 'Purchase History',
                          icon: Icons.history_rounded),
                      const SizedBox(height: 8),
                      ...(_purchasesLoadFailed && _purchases.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Text(
                                    'Could not load purchase history. Try again.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: tertiaryColor),
                                  ),
                                ),
                              ),
                            ]
                          : _purchases.isEmpty
                              ? [
                                  Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Center(
                                          child: Text('No purchases yet',
                                              style: TextStyle(
                                                  color: tertiaryColor))))
                                ]
                              : _purchases.map((s) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () =>
                                            context.push('/receipt/${s['id']}'),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: surface,
                                            border: Border.all(color: border),
                                            borderRadius: BorderRadius.circular(
                                                DesignSpacing.radiusLg),
                                          ),
                                          child: Row(children: [
                                            Expanded(
                                                child: Text(
                                                    'Receipt #${_shortReceiptId(s['id']?.toString() ?? '')}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: titleColor,
                                                        ))),
                                            Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                      formatMoney(
                                                          (s['total'] as num)),
                                                      style: DesignType.numeric(
                                                        color:
                                                            DesignColors.brand,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      )),
                                                  Text(
                                                      _purchaseDateLabel(
                                                          s['createdAt']),
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color:
                                                                tertiaryColor,
                                                          )),
                                                ]),
                                          ]),
                                        ),
                                      ),
                                    ),
                                  ))),
                      const SizedBox(height: 32),
                    ],
                  ),
      ),
    );
  }
}
