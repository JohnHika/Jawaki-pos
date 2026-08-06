import 'package:flutter/material.dart';

import '../services/update_check_service.dart';
import '../theme/design_system.dart';
import 'release_notes.dart';

/// Full-screen "you're up to date" moment shown once, right after the app
/// relaunches on a version it just installed. Reuses the same
/// `last_seen_update_notice` de-dupe key the previous AlertDialog-based
/// implementation used, so it still only shows once per released version.
class UpdateSuccessScreen extends StatelessWidget {
  const UpdateSuccessScreen({
    super.key,
    required this.update,
    required this.onDismiss,
  });

  final AppUpdateInfo update;

  // Shown as a Stack overlay (see main.dart), not pushed onto a Navigator,
  // so dismissal is a plain callback rather than Navigator.of(context).pop().
  // (This screen previously used Navigator.of(context) here, which threw
  // "Navigator operation requested with a context that does not include a
  // Navigator" every time, because the host widget that built it sits above
  // MaterialApp.router's internal Navigator, not below it.)
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final notes = parseReleaseNotes(update.releaseNotes);

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
                  const _SuccessMark(),
                  const SizedBox(height: DesignSpacing.xxl),
                  Text(
                    "You're up to date",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: DesignColors.darkTextPrimary,
                        ),
                  ),
                  const SizedBox(height: DesignSpacing.sm),
                  Center(
                    child: StatusBadge(
                      label: update.displayVersion,
                      color: DesignColors.success,
                    ),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: DesignSpacing.xxl),
                    Flexible(
                      child: SingleChildScrollView(
                        child: GlassCard(
                          padding: const EdgeInsets.all(DesignSpacing.xl),
                          borderRadius: DesignSpacing.radiusLg,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "What's new",
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: DesignColors.darkTextPrimary,
                                    ),
                              ),
                              const SizedBox(height: DesignSpacing.md),
                              CategorizedNotes(releaseNotes: update.releaseNotes),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: DesignSpacing.xxl),
                  SettingsPrimaryButton(
                    label: 'Continue',
                    onPressed: onDismiss,
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

class _SuccessMark extends StatelessWidget {
  const _SuccessMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: DesignColors.successSubtle,
          shape: BoxShape.circle,
          border: Border.all(
            color: DesignColors.success.withValues(alpha: 0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: DesignColors.success.withValues(alpha: 0.25),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          color: DesignColors.success,
          size: 38,
        ),
      ),
    );
  }
}
