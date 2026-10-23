import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';

/// A safe landing page for older navigation links to manual SMS matching.
/// An SMS or pasted statement is not proof that Paystack received a payment.
class MpesaMatchScreen extends StatelessWidget {
  const MpesaMatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Match M-Pesa',
        showBackButton: GoRouter.of(context).canPop(),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DesignSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: GlassCard(
                padding: const EdgeInsets.all(DesignSpacing.xl),
                borderRadius: DesignSpacing.radiusLg,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 42,
                      color: DesignColors.accent,
                    ),
                    const SizedBox(height: DesignSpacing.lg),
                    Text(
                      'Verify debt payments with Paystack',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    const Text(
                      'Pasted M-Pesa messages cannot confirm a debt payment. '
                      'Open Finance, choose the customer debt, and send an '
                      'M-Pesa request. Counterbase will update the balance '
                      'only after Paystack confirms the payment.',
                    ),
                    const SizedBox(height: DesignSpacing.xl),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.push('/finance'),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('Open Finance'),
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => context.push('/payments/setup'),
                        child: const Text('Check customer payment setup'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
