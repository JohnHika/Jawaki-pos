import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/design_system.dart';
import '../providers/cart_provider.dart';
import '../providers/payment_provider.dart';

enum PaymentMethod {
  cash,
  mpesa,
  manual,
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
              tint: DesignColors.brand.withValues(alpha: 0.08),
              borderColor: DesignColors.brand.withValues(alpha: 0.15),
              gradient: LinearGradient(
                colors: [
                  DesignColors.brand.withValues(alpha: 0.1),
                  DesignColors.brandDark.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              child: Column(
                children: [
                  const Text(
                    'Total Amount',
                    style: TextStyle(
                      color: DesignColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'KES ${cart.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: DesignColors.textPrimary,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
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
                        color: Colors.teal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.teal.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_rounded,
                              size: 15, color: Colors.teal),
                          const SizedBox(width: 6),
                          Text(
                            cart.customerName!,
                            style: const TextStyle(
                                color: Colors.teal,
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
            gradient: const [DesignColors.brand, DesignColors.brandDark],
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
        );
        break;
      case PaymentMethod.manual:
        result = await paymentNotifier.processManualPayment(
          amount: cart.total,
          items: cart.items,
        );
        break;
    }

    if (result != null && mounted) {
      final customerId = cart.customerId;

      if (customerId != null) {
        await getIt<AppDatabase>()
            .recordCustomerPurchase(customerId, cart.total);
      }

      if (!mounted) return;
      ref.read(cartProvider.notifier).clear();
      context.go('/receipt/$result');
    }
  }
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
