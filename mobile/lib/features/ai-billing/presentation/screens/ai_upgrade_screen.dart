import 'package:flutter/material.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion.dart';

/// Upgrade screen shown when the AI assistant is not available on the
/// tenant's current plan (TRIAL / not yet activated). AI is included in
/// every Axon POS plan (Core, Business and Enterprise) — there is nothing
/// to subscribe to or pay for here; the user just needs an active plan.
class AiUpgradeScreen extends StatelessWidget {
  final String branchId;
  final String branchName;
  final VoidCallback onViewPlans;

  const AiUpgradeScreen({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.onViewPlans,
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
                StaggeredItem(
                  itemKey: 'upgrade-mark',
                  index: 0,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: DesignColors.brand.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome,
                        size: 48, color: DesignColors.brand),
                  ),
                ),
                const SizedBox(height: DesignSpacing.xxl),

                const Text(
                  'Axon AI Assistant',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: DesignColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: DesignSpacing.md),

                const Text(
                  'The AI assistant is included in every Axon POS plan — Core, '
                  'Business and Enterprise. Activate your plan to get instant '
                  'insights, product recommendations, and business analytics.',
                  style: TextStyle(
                    color: DesignColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: DesignSpacing.xxxl),

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
                const SizedBox(height: DesignSpacing.xxxl),

                StaggeredItem(
                  itemKey: 'upgrade-plan-card',
                  index: 1,
                  child: GlassCard(
                    padding: const EdgeInsets.all(DesignSpacing.xl),
                    borderRadius: DesignSpacing.radiusLg,
                    borderColor: DesignColors.brand.withValues(alpha: 0.3),
                    tint: DesignColors.brand.withValues(alpha: 0.05),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.workspace_premium,
                                color: DesignColors.brand, size: 24),
                            const SizedBox(width: DesignSpacing.sm),
                            Text(
                              'Included in every plan',
                              style: DesignType.numeric(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: DesignColors.brand,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: DesignSpacing.sm),
                        const Text(
                          'Core, Business and Enterprise all include the AI '
                          'assistant. No separate AI subscription, no add-on '
                          'charge.',
                          style: TextStyle(
                            color: DesignColors.textSecondary,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: DesignSpacing.lg),
                        GradientButton(
                          label: 'View Plans',
                          icon: Icons.workspace_premium,
                          onPressed: onViewPlans,
                          height: DesignSpacing.xl + 28,
                          borderRadius: DesignSpacing.radiusMd,
                        ),
                      ],
                    ),
                  ),
                ),
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
      padding: const EdgeInsets.only(bottom: DesignSpacing.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: DesignColors.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            ),
            child: Icon(icon, color: DesignColors.brand, size: 22),
          ),
          const SizedBox(width: DesignSpacing.md),
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
    );
  }
}
