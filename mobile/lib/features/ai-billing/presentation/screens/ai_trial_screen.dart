import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:axon_pos/features/ai-billing/presentation/services/ai_billing_service.dart';
import '../../../../core/theme/design_system.dart';

/// Landing screen shown when a branch tries to use the AI assistant
/// without an active subscription. There is no free trial — this screen
/// explains what the assistant does and leads straight into payment.
class AiTrialScreen extends StatelessWidget {
  final String branchId;
  final String branchName;
  final VoidCallback onSubscribe;

  const AiTrialScreen({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.onSubscribe,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandedAppBar(title: 'Axon AI Assistant', showLogo: false),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: DesignColors.brand.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome,
                      size: 48, color: DesignColors.brand),
                ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 24),

                const Text(
                  'Axon AI Assistant',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: DesignColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                const Text(
                  'Get instant insights, product recommendations, and business analytics powered by AI.',
                  style: TextStyle(
                    color: DesignColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 200.ms),
                const SizedBox(height: 32),

                const _FeatureTile(
                  icon: Icons.analytics_outlined,
                  title: 'Sales Analytics',
                  subtitle: 'Understand your sales trends',
                ),
                const _FeatureTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Inventory Help',
                  subtitle: 'Smart stock recommendations',
                ),
                const _FeatureTile(
                  icon: Icons.lightbulb_outlined,
                  title: 'Business Tips',
                  subtitle: 'AI-powered advice for your store',
                ),
                const SizedBox(height: 32),

                GlassCard(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 16,
                  borderColor: DesignColors.brand.withValues(alpha: 0.3),
                  tint: DesignColors.brand.withValues(alpha: 0.05),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.workspace_premium,
                              color: DesignColors.brand, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'KES ${AiBillingService.subscriptionPrice.toStringAsFixed(0)}/month',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: DesignColors.brand,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Subscribe with a card for automatic monthly renewal, or pay via M-Pesa.',
                        style: TextStyle(
                          color: DesignColors.textSecondary,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      GradientButton(
                        label: 'Subscribe Now',
                        icon: Icons.workspace_premium,
                        onPressed: onSubscribe,
                        height: 48,
                        borderRadius: 12,
                      ),
                    ],
                  ),
                ).animate().slideY(
                    begin: 0.3, duration: 500.ms, curve: Curves.easeOut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DesignColors.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: DesignColors.brand, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: DesignColors.textPrimary)),
                Text(subtitle,
                    style: const TextStyle(
                        color: DesignColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.2);
  }
}
