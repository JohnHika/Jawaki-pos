import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/widgets/add_edit_product_sheet.dart';

/// One-shot welcome shown right after a brand-new company finishes
/// signing up, before they ever see the (empty) POS screen. Ends with a
/// direct call to action — add the first product — rather than a passive
/// tour, since that's the single action that turns an empty shop into a
/// usable one.
class OwnerWelcomeScreen extends StatelessWidget {
  const OwnerWelcomeScreen({super.key, this.companyName});

  final String? companyName;

  Future<void> _addFirstProduct(BuildContext context) async {
    await GlassBottomSheet.show(
      context,
      title: 'Add Product',
      initialSize: 0.85,
      maxSize: 0.95,
      scrollable: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const AddEditProductSheet(),
      ),
    );
    if (context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final name = companyName?.trim();
    return Material(
      color: DesignColors.darkBg,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignSpacing.xxl,
                vertical: DesignSpacing.xxxl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: DesignColors.brand.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: DesignColors.brand.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: DesignColors.brand,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.xxl),
                  Text(
                    name == null || name.isEmpty
                        ? 'Welcome to Axon POS!'
                        : 'Welcome to Axon POS, $name!',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: DesignColors.darkTextPrimary,
                        ),
                  ),
                  const SizedBox(height: DesignSpacing.md),
                  Text(
                    "Your workspace is ready. Sell products, track stock as it moves, "
                    "and see how the business is doing — all from here.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: DesignColors.darkTextSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.xxl),
                  GradientButton(
                    label: '+ Add Your First Product',
                    onPressed: () => _addFirstProduct(context),
                    height: 56,
                    borderRadius: 14,
                  ),
                  const SizedBox(height: DesignSpacing.md),
                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/'),
                      child: Text(
                        'Skip for now',
                        style: TextStyle(
                          color: DesignColors.darkTextTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
