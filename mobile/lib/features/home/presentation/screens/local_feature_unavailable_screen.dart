import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/local_workspace_capabilities.dart';
import '../../../../core/theme/design_system.dart';

/// Explains when an old link points to a feature that depended on the retired
/// hosted POS service. Keeping this in the app avoids a silent jump home.
class LocalFeatureUnavailableScreen extends StatelessWidget {
  const LocalFeatureUnavailableScreen({
    super.key,
    required this.featureName,
    required this.sourcePath,
    required this.homePath,
    this.alternative,
  });

  final String featureName;
  final String sourcePath;
  final String homePath;
  final LocalWorkspaceAlternative? alternative;

  String get _explanation {
    if (sourcePath == '/users/invitations' ||
        sourcePath == '/invite-staff' ||
        sourcePath == '/accept-invite' ||
        sourcePath == '/set-password-after-invite') {
      return 'Staff profiles can be created on this device. Cross-device invitations and shared accounts need an online shop service.';
    }
    if (sourcePath == '/users/roles' ||
        sourcePath.startsWith('/users/roles/') ||
        (sourcePath.startsWith('/users/') &&
            sourcePath != '/users/invitations')) {
      return 'This install uses built-in local staff roles. Shared role templates and per-user overrides need an online shop service.';
    }
    if (sourcePath == '/inventory/request-stock' ||
        sourcePath == '/inventory/stock-requests') {
      return 'Stock requests between shops need a shared shop service. You can still record deliveries in this device’s inventory.';
    }
    if (sourcePath == '/inventory/restock-suggestions') {
      return 'Cloud restock suggestions need a shared shop service. Your local stock and sales reports are still available.';
    }
    if (sourcePath.startsWith('/payments/setup')) {
      return 'Online provider payouts are turned off in this standalone edition. Cash, credit, and locally recorded payment history stay available.';
    }
    if (sourcePath == '/statements/replies') {
      return 'Customers cannot reply to hosted statement links without an online shop service. You can still review their local account and send a device-generated statement.';
    }
    if (sourcePath.startsWith('/containers')) {
      return 'Container and shipment tracking needs a shared shop service. Supplier invoices and stock receipts remain available in local Finance and Inventory.';
    }
    return 'This action needs shared online services, which this standalone app does not use. Your locally saved shop records remain on this device.';
  }

  @override
  Widget build(BuildContext context) {
    final alternative = this.alternative;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Scaffold(
      appBar:
          const BrandedAppBar(title: 'Not available', showBackButton: false),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DesignSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: DesignColors.info.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusXl),
                    ),
                    child: const Icon(
                      Icons.cloud_off_rounded,
                      color: DesignColors.info,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.xl),
                  Text(
                    'This feature isn’t available here',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: DesignSpacing.sm),
                  Text(
                    featureName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: DesignColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: DesignSpacing.md),
                  Text(
                    _explanation,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: secondary,
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: DesignSpacing.xl),
                  if (alternative != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go(alternative.path),
                        icon: Icon(alternative.icon),
                        label: Text(alternative.label),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.lg,
                            vertical: DesignSpacing.md,
                          ),
                          foregroundColor: DesignColors.accent,
                          side: BorderSide(
                            color: DesignColors.accent.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              DesignSpacing.radiusLg,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      label: 'Return to your shop',
                      icon: Icons.storefront_rounded,
                      onPressed: () => context.go(homePath),
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
