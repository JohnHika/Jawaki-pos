import 'package:flutter/material.dart';

import '../../../../core/theme/design_system.dart';

class _GuideStep {
  const _GuideStep(this.text);
  final String text;
}

class _GuideTopic {
  const _GuideTopic({
    required this.icon,
    required this.title,
    required this.steps,
  });
  final IconData icon;
  final String title;
  final List<_GuideStep> steps;
}

const _topics = [
  _GuideTopic(
    icon: Icons.point_of_sale_rounded,
    title: 'Making a Sale',
    steps: [
      _GuideStep('Go to the POS tab'),
      _GuideStep('Search or browse for products'),
      _GuideStep('Tap a product and set the quantity'),
      _GuideStep('Review the cart and proceed to payment'),
      _GuideStep('Choose a payment method and complete the sale'),
    ],
  ),
  _GuideTopic(
    icon: Icons.inventory_2_rounded,
    title: 'Managing Products',
    steps: [
      _GuideStep('Go to the Products tab'),
      _GuideStep('Tap + to add a new product'),
      _GuideStep('Long-press a product to delete it'),
      _GuideStep('Tap a product to edit its details'),
      _GuideStep('Use the category button to manage categories'),
    ],
  ),
  _GuideTopic(
    icon: Icons.analytics_rounded,
    title: 'Reports',
    steps: [
      _GuideStep('Go to the Reports tab'),
      _GuideStep('View daily, weekly, or monthly sales'),
      _GuideStep('Track revenue and top-selling products'),
    ],
  ),
  _GuideTopic(
    icon: Icons.warehouse_rounded,
    title: 'Inventory',
    steps: [
      _GuideStep('Go to the Inventory tab'),
      _GuideStep('Check current stock levels'),
      _GuideStep('Receive new stock deliveries'),
    ],
  ),
];

/// Replaces the old single-dialog User Guide (one dense `\n•`-joined
/// paragraph per topic) with a real scrollable screen of expandable
/// sections, matching the rest of the app's design system.
class UserGuideScreen extends StatelessWidget {
  const UserGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Scaffold(
      appBar: const BrandedAppBar(title: 'User Guide'),
      body: PageContainer(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          itemCount: _topics.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final topic = _topics[index];
            return Container(
              decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: index == 0,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DesignColors.brand.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(topic.icon, color: DesignColors.brand, size: 20),
                  ),
                  title: Text(
                    topic.title,
                    style: TextStyle(fontWeight: FontWeight.w700, color: titleColor),
                  ),
                  iconColor: secondaryColor,
                  collapsedIconColor: secondaryColor,
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final step in topic.steps)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.check_circle_rounded,
                                  size: 16, color: DesignColors.success),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                step.text,
                                style: TextStyle(color: secondaryColor, fontSize: 14, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
