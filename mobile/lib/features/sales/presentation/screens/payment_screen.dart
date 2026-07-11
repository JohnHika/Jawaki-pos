import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/design_system.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/payment_provider.dart';

enum PaymentMethod {
  cash,
  mpesa,
  manual,
  debt,
  split,
}

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  PaymentMethod? _selectedMethod;
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final paymentState = ref.watch(paymentProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: Container(
          margin: const EdgeInsets.only(left: 4),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back_rounded, size: 20),
            ),
            onPressed: () => context.pop(),
          ),
        ),
        title: Text(
          'Payment',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: -0.5,
            color: isDark
                ? DesignColors.darkTextPrimary
                : DesignColors.textPrimary,
          ),
        ),
        centerTitle: false,
        backgroundColor:
            isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Total Card
            GlassCard(
              padding: const EdgeInsets.all(20),
              borderRadius: 20,
              blur: 8,
              tint: DesignColors.accent.withValues(alpha: 0.08),
              borderColor: DesignColors.accent.withValues(alpha: 0.15),
              child: Column(
                children: [
                  Text(
                    'Total Amount',
                    style: TextStyle(
                      color: isDark
                          ? DesignColors.darkTextSecondary
                          : DesignColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'KES ${cart.total.toStringAsFixed(2)}',
                    style: DesignType.numeric(
                      color: isDark
                          ? DesignColors.darkTextPrimary
                          : DesignColors.textPrimary,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${cart.itemCount} items',
                    style: TextStyle(
                      color: isDark
                          ? DesignColors.darkTextSecondary
                          : DesignColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  if (cart.customerName != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: DesignColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: DesignColors.accent.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_rounded,
                              size: 15, color: DesignColors.accent),
                          const SizedBox(width: 6),
                          Text(
                            cart.customerName!,
                            style: const TextStyle(
                                color: DesignColors.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Select Payment Method
            SectionHeader(
              title: 'Payment Method',
              subtitle: 'Choose how to pay',
            ),
            const SizedBox(height: 8),

            // Cash
            _PaymentMethodTile(
              icon: Icons.money_rounded,
              title: 'Cash',
              subtitle: 'Pay with cash',
              color: DesignColors.cash,
              isSelected: _selectedMethod == PaymentMethod.cash,
              onTap: () => setState(() => _selectedMethod = PaymentMethod.cash),
            ),
            const SizedBox(height: 10),

            // M-Pesa
            _PaymentMethodTile(
              icon: Icons.phone_android_rounded,
              title: 'M-Pesa',
              subtitle: 'Pay via M-Pesa STK Push',
              color: DesignColors.mpesa,
              isSelected: _selectedMethod == PaymentMethod.mpesa,
              onTap: () =>
                  setState(() => _selectedMethod = PaymentMethod.mpesa),
            ),
            const SizedBox(height: 10),

            // Manual
            _PaymentMethodTile(
              icon: Icons.edit_note_rounded,
              title: 'Manual',
              subtitle: 'Record payment already received',
              color: DesignColors.accent,
              isSelected: _selectedMethod == PaymentMethod.manual,
              onTap: () =>
                  setState(() => _selectedMethod = PaymentMethod.manual),
            ),
            const SizedBox(height: 10),

            // Debt (sell now, customer pays later)
            _PaymentMethodTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Add to Debt',
              subtitle: 'Customer pays later — requires a customer',
              color: DesignColors.error,
              isSelected: _selectedMethod == PaymentMethod.debt,
              onTap: () => setState(() => _selectedMethod = PaymentMethod.debt),
            ),
            const SizedBox(height: 10),

            // Split
            _PaymentMethodTile(
              icon: Icons.call_split_rounded,
              title: 'Split Payment',
              subtitle: 'Part cash, part M-Pesa, part debt',
              color: DesignColors.warning,
              isSelected: _selectedMethod == PaymentMethod.split,
              onTap: () =>
                  setState(() => _selectedMethod = PaymentMethod.split),
            ),

            // Phone number input for M-Pesa
            if (_selectedMethod == PaymentMethod.mpesa) ...[
              const SizedBox(height: 24),
              LabelDivider(label: 'M-PESA DETAILS'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '0712345678',
                  labelText: 'Phone Number',
                  prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                  prefixText: '+254 ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? DesignColors.darkSurfaceElevated
                      : DesignColors.surfaceMuted,
                ),
              ),
            ],

            // Error message
            if (paymentState.error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DesignColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: DesignColors.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: DesignColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        paymentState.error!,
                        style: const TextStyle(
                            color: DesignColors.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: GradientButton(
            label: _getButtonText(),
            icon: Icons.payment_rounded,
            onPressed: _selectedMethod == null || paymentState.isProcessing
                ? null
                : _processPayment,
            isLoading: paymentState.isProcessing,
            height: 56,
            borderRadius: 16,
          ),
        ),
      ),
    );
  }

  String _getButtonText() {
    switch (_selectedMethod) {
      case PaymentMethod.cash:
        return 'Confirm Cash Payment';
      case PaymentMethod.mpesa:
        return 'Send M-Pesa Request';
      case PaymentMethod.manual:
        return 'Confirm Manual Payment';
      case PaymentMethod.debt:
        return 'Record as Debt';
      case PaymentMethod.split:
        return 'Enter Split Payment';
      case null:
        return 'Select Payment Method';
    }
  }

  Future<void> _processPayment() async {
    if (_selectedMethod == null) return;

    final cart = ref.read(cartProvider);
    final paymentNotifier = ref.read(paymentProvider.notifier);

    String? result;

    switch (_selectedMethod!) {
      case PaymentMethod.cash:
        result = await paymentNotifier.processCashPayment(
          amount: cart.total,
          items: cart.items,
          customerId: cart.customerId,
        );
        break;
      case PaymentMethod.mpesa:
        if (_phoneController.text.isEmpty) {
          showGlassSnackBar(
            context,
            'Please enter phone number',
            icon: Icons.warning_amber_rounded,
            color: DesignColors.warning,
          );
          return;
        }
        result = await paymentNotifier.processMpesaPayment(
          amount: cart.total,
          phoneNumber: _phoneController.text,
          items: cart.items,
          customerId: cart.customerId,
        );
        break;
      case PaymentMethod.manual:
        result = await paymentNotifier.processManualPayment(
          amount: cart.total,
          items: cart.items,
          customerId: cart.customerId,
        );
        break;
      case PaymentMethod.debt:
        // Whole sale is owed — requires a customer to record the debt
        // against. Prompt to pick one if none is set.
        if (cart.customerId == null) {
          if (mounted) {
            showGlassSnackBar(
              context,
              'Select a customer before selling on debt',
              icon: Icons.person_off_rounded,
              color: DesignColors.warning,
            );
          }
          return;
        }
        result = await paymentNotifier.processCreditPayment(
          amount: cart.total,
          items: cart.items,
          customerId: cart.customerId,
          customerName: cart.customerName,
        );
        break;
      case PaymentMethod.split:
        final tenders = await _showSplitPaymentSheet(cart.total);
        if (tenders == null) return; // cancelled
        // A split with a debt (CREDIT) portion needs a customer to owe it.
        final hasDebt = tenders.any((t) => t.method == 'CREDIT');
        if (hasDebt && cart.customerId == null) {
          if (mounted) {
            showGlassSnackBar(
              context,
              'Select a customer before adding a debt portion',
              icon: Icons.person_off_rounded,
              color: DesignColors.warning,
            );
          }
          return;
        }
        result = await paymentNotifier.processSplitPayment(
          amount: cart.total,
          items: cart.items,
          tenders: tenders,
          customerId: cart.customerId,
        );
        break;
    }

    // Surface any error the payment notifier set (e.g. debt with no
    // customer, or a failed tender) instead of silently doing nothing.
    if (result == null) {
      final err = ref.read(paymentProvider).error;
      if (err != null && mounted) {
        showGlassSnackBar(
          context,
          err,
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    }

    if (result != null && mounted) {
      final customerId = cart.customerId;

      if (customerId != null) {
        await getIt<AppDatabase>()
            .recordCustomerPurchase(customerId, cart.total);
      }

      if (!mounted) return;
      ref.read(cartProvider.notifier).clear();
      // These FutureProviders retain their last result. Invalidate them so
      // the POS grid reflects the local stock decrement immediately.
      ref.invalidate(productsProvider);
      ref.invalidate(filteredProductsProvider);
      ref.invalidate(favoriteProductsProvider);
      context.go('/receipt/$result');
    }
  }

  /// Collects one or more tenders (method + amount) that together must
  /// cover the sale total. Returns null if the user cancels.
  Future<List<PaymentTender>?> _showSplitPaymentSheet(double total) async {
    final rows = <_TenderRow>[
      _TenderRow(method: 'CASH', amountController: TextEditingController()),
      _TenderRow(method: 'CASH', amountController: TextEditingController()),
    ];

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final entered = rows.fold<double>(
              0,
              (sum, r) =>
                  sum + (double.tryParse(r.amountController.text) ?? 0));
          final remaining = total - entered;

          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 4, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Split Payment',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Total due: KES ${total.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: isDark
                            ? DesignColors.darkTextSecondary
                            : DesignColors.textSecondary)),
                const SizedBox(height: 16),
                ...rows.asMap().entries.map((entry) {
                  final index = entry.key;
                  final row = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: row.method,
                            decoration:
                                const InputDecoration(labelText: 'Method'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'CASH', child: Text('Cash')),
                              DropdownMenuItem(
                                  value: 'CREDIT', child: Text('Debt (owed)')),
                            ],
                            onChanged: (v) => setSheetState(
                                () => row.method = v ?? row.method),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: row.amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Amount (KES)'),
                            onChanged: (_) => setSheetState(() {}),
                          ),
                        ),
                        if (rows.length > 1)
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: () =>
                                setSheetState(() => rows.removeAt(index)),
                            icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                color: DesignColors.error),
                          ),
                      ],
                    ),
                  );
                }),
                TextButton.icon(
                  onPressed: () => setSheetState(() => rows.add(_TenderRow(
                      method: 'CASH',
                      amountController: TextEditingController()))),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add another tender'),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (remaining > 0.01
                            ? DesignColors.warning
                            : DesignColors.success)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    remaining > 0.01
                        ? 'Remaining: KES ${remaining.toStringAsFixed(2)}'
                        : 'Fully covered'
                            '${remaining < -0.01 ? ' (change: KES ${(-remaining).toStringAsFixed(2)})' : ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: remaining > 0.01
                          ? DesignColors.warning
                          : DesignColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: remaining > 0.01
                        ? null
                        : () => Navigator.pop(sheetContext, true),
                    child: const Text('Confirm Split'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed != true) return null;

    return rows
        .where((r) => (double.tryParse(r.amountController.text) ?? 0) > 0)
        .map((r) => PaymentTender(
              method: r.method,
              amount: double.parse(r.amountController.text),
            ))
        .toList();
  }
}

class _TenderRow {
  String method;
  final TextEditingController amountController;

  _TenderRow({required this.method, required this.amountController});
}

class _PaymentMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      blur: isSelected ? 12 : 4,
      tint: isSelected
          ? color.withValues(alpha: 0.08)
          : (isDark ? DesignColors.glassDark : DesignColors.glassWhite),
      borderColor: isSelected
          ? color.withValues(alpha: 0.4)
          : (isDark ? DesignColors.glassDarkBorder : DesignColors.glassBorder),
      boxShadow: isSelected
          ? [
              BoxShadow(
                color: color.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.2)),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? color
                        : (isDark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? DesignColors.darkTextSecondary
                        : DesignColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 18),
            ),
        ],
      ),
    );
  }
}
