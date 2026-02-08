import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/cart_provider.dart';
import '../providers/payment_provider.dart';

enum PaymentMethod {
  cash,
  mpesa,
  pesapal,
  touristtap,
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Payment'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Total Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    'Total Amount',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'KES ${cart.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${cart.itemCount} items',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  if (cart.customerName != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        cart.customerName!,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Payment Methods
            Text(
              'Select Payment Method',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            
            // Cash
            _PaymentMethodTile(
              icon: Icons.money,
              title: 'Cash',
              subtitle: 'Pay with cash',
              color: AppColors.cash,
              isSelected: _selectedMethod == PaymentMethod.cash,
              onTap: () => setState(() => _selectedMethod = PaymentMethod.cash),
            ),
            const SizedBox(height: 12),
            
            // M-Pesa
            _PaymentMethodTile(
              icon: Icons.phone_android,
              title: 'M-Pesa',
              subtitle: 'Pay via M-Pesa STK Push',
              color: AppColors.mpesa,
              isSelected: _selectedMethod == PaymentMethod.mpesa,
              onTap: () => setState(() => _selectedMethod = PaymentMethod.mpesa),
            ),
            const SizedBox(height: 12),
            
            // PesaPal
            _PaymentMethodTile(
              icon: Icons.credit_card,
              title: 'PesaPal',
              subtitle: 'Card, Mobile Money, Bank',
              color: AppColors.pesapal,
              isSelected: _selectedMethod == PaymentMethod.pesapal,
              onTap: () => setState(() => _selectedMethod = PaymentMethod.pesapal),
            ),
            const SizedBox(height: 12),
            
            // TouristTap
            _PaymentMethodTile(
              icon: Icons.contactless,
              title: 'TouristTap',
              subtitle: 'NFC / Contactless Payment',
              color: AppColors.touristtap,
              isSelected: _selectedMethod == PaymentMethod.touristtap,
              onTap: () => setState(() => _selectedMethod = PaymentMethod.touristtap),
            ),
            
            // Phone number input for M-Pesa
            if (_selectedMethod == PaymentMethod.mpesa) ...[
              const SizedBox(height: 24),
              Text(
                'Enter M-Pesa Phone Number',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: '0712345678',
                  prefixIcon: Icon(Icons.phone),
                  prefixText: '+254 ',
                ),
              ),
            ],
            
            // Error message
            if (paymentState.error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        paymentState.error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _selectedMethod == null || paymentState.isProcessing
                ? null
                : _processPayment,
            child: paymentState.isProcessing
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text('Processing...'),
                    ],
                  )
                : Text(_getButtonText()),
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
      case PaymentMethod.pesapal:
        return 'Pay with PesaPal';
      case PaymentMethod.touristtap:
        return 'Initiate NFC Payment';
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter phone number')),
          );
          return;
        }
        result = await paymentNotifier.processMpesaPayment(
          amount: cart.total,
          phoneNumber: _phoneController.text,
          items: cart.items,
        );
        break;
      case PaymentMethod.pesapal:
        result = await paymentNotifier.processPesaPalPayment(
          amount: cart.total,
          items: cart.items,
        );
        break;
      case PaymentMethod.touristtap:
        result = await paymentNotifier.processTouristTapPayment(
          amount: cart.total,
          items: cart.items,
        );
        break;
    }

    if (result != null && mounted) {
      // Record customer purchase if customer is set
      final customerId = cart.customerId;
      if (customerId != null) {
        await getIt<AppDatabase>().recordCustomerPurchase(customerId, cart.total);
      }

      // Clear cart and navigate to receipt
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
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : theme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? color : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.disabledColor,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color),
          ],
        ),
      ),
    );
  }
}
