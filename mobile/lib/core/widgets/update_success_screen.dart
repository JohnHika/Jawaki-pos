import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

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
                          fontWeight: FontWeight.w700,
                        ),
                  )
                      .animate()
                      .fadeIn(duration: 450.ms, delay: 200.ms)
                      .slideY(
                        begin: 0.15,
                        end: 0.0,
                        duration: 450.ms,
                        delay: 200.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: DesignSpacing.sm),
                  Center(
                    child: StatusBadge(
                      label: update.displayVersion,
                      color: DesignColors.success,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 350.ms, delay: 350.ms)
                      .scale(
                        begin: const Offset(0.85, 0.85),
                        end: const Offset(1.0, 1.0),
                        duration: 400.ms,
                        delay: 350.ms,
                        curve: Curves.easeOutBack,
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
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: DesignSpacing.md),
                              CategorizedNotes(releaseNotes: update.releaseNotes),
                            ],
                          ),
                        ).animate().fadeIn(duration: 500.ms, delay: 450.ms),
                      ),
                    ),
                  ],
                  const SizedBox(height: DesignSpacing.xxl),
                  SettingsPrimaryButton(
                    label: 'Continue',
                    onPressed: onDismiss,
                  ).animate().fadeIn(duration: 350.ms, delay: 600.ms).slideY(
                        begin: 0.2,
                        end: 0.0,
                        duration: 350.ms,
                        delay: 600.ms,
                        curve: Curves.easeOutCubic,
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
        width: 96,
        height: 96,
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
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.check_rounded,
          color: DesignColors.success,
          size: 44,
        ),
      )
          .animate()
          .scale(
            begin: const Offset(0.4, 0.4),
            end: const Offset(1.0, 1.0),
            duration: 600.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 400.ms),
    );
  }
}
