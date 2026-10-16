import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../domain/billing_entitlement.dart';
import '../providers/entitlement_provider.dart';

/// Returns true when [feature] is part of this company's licence. Otherwise
/// shows the "not included in your plan" sheet and returns false, so a tap
/// handler can simply `if (!await ensureFeature(...)) return;`.
///
/// Fails open: until the licence is known, or while the operator has
/// enforcement off, every module is available. The server is the real gate.
Future<bool> ensureFeature(
  BuildContext context,
  WidgetRef ref,
  String feature,
) async {
  if (ref.read(featureAllowedProvider(feature))) return true;
  await showFeatureLockedSheet(context, feature);
  return false;
}

Future<void> showFeatureLockedSheet(BuildContext context, String feature) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignSpacing.xl,
          0,
          DesignSpacing.xl,
          DesignSpacing.xl,
        ),
        child: FeatureLockedPanel(
          feature: feature,
          onSeePlans: () {
            Navigator.of(sheetContext).pop();
            context.push('/billing');
          },
          onDismiss: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    ),
  );
}

/// Replaces a screen's body when its module is not licensed.
class FeatureGate extends ConsumerWidget {
  const FeatureGate({super.key, required this.feature, required this.child});

  final String feature;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(featureAllowedProvider(feature))) return child;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignSpacing.xl),
        child: FeatureLockedPanel(
          feature: feature,
          onSeePlans: () => context.push('/billing'),
        ),
      ),
    );
  }
}

/// The lock message itself, shared by the sheet and the full-screen gate.
class FeatureLockedPanel extends StatelessWidget {
  const FeatureLockedPanel({
    super.key,
    required this.feature,
    required this.onSeePlans,
    this.onDismiss,
  });

  final String feature;
  final VoidCallback onSeePlans;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final label = LicensedFeature.labels[feature] ?? 'This feature';
    final blurb = LicensedFeature.blurbs[feature];
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: DesignColors.brand.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            size: 30,
            color: DesignColors.brand,
          ),
        ),
        const SizedBox(height: DesignSpacing.lg),
        Text(
          "$label isn't included in your plan",
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (blurb != null) ...[
          const SizedBox(height: DesignSpacing.sm),
          Text(
            blurb,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: DesignSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onSeePlans,
            child: const Text('See plans'),
          ),
        ),
        if (onDismiss != null)
          TextButton(onPressed: onDismiss, child: const Text('Not now')),
      ],
    );
  }
}
