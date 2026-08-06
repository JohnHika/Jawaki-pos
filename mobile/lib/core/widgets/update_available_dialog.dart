import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../di/injection.dart';
import '../services/update_check_service.dart';
import '../theme/design_system.dart';
import 'release_notes.dart';

/// A compact, dismissible "an update is available" dialog — used for the
/// manual "Check for updates" entry point in Settings, where the app is
/// still above its minimum supported version, the calling context is a
/// genuine descendant of the app's Navigator, and there's no reason to
/// force the user off what they're doing. Choosing to update hands off
/// to [UpdateCheckService.beginOptionalUpdateNow], which promotes the
/// update into the same full-screen [ForcedUpdateGate] flow every other
/// update path in the app uses.
Future<void> showUpdateAvailableDialog({
  required BuildContext context,
  required AppUpdateInfo update,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _UpdateDialog(
      update: update,
      dialogContext: dialogContext,
    ),
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({
    required this.update,
    required this.dialogContext,
  });

  final AppUpdateInfo update;
  final BuildContext dialogContext;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? DesignColors.darkSurface : Colors.white;
    final borderColor = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final textPrimary = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;

    return Dialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _IconBadge(isDark: isDark),
                const SizedBox(width: DesignSpacing.md),
                Expanded(
                  child: Text(
                    'Update available',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignSpacing.lg),
            Row(
              children: [
                StatusBadge(
                  label: update.displayVersion,
                  color: DesignColors.accent,
                ),
              ],
            ),
            if (update.releaseNotes.trim().isNotEmpty) ...[
              const SizedBox(height: DesignSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: CategorizedNotes(releaseNotes: update.releaseNotes.trim()),
                ),
              ),
            ],
            const SizedBox(height: DesignSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: DesignColors.accentSubtle,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(
          color: DesignColors.accent.withValues(alpha: isDark ? 0.25 : 0.15),
        ),
      ),
      child: const Icon(
        Icons.system_update_alt_rounded,
        color: DesignColors.accent,
        size: 22,
      ),
    );
  }
}

/// Same visual content as [showUpdateAvailableDialog], but rendered inline
/// as a plain widget instead of pushed via `showDialog`. Used by hosts
/// (e.g. OptionalUpdatePromptHost) that build from a BuildContext sitting
/// above MaterialApp.router's internal Navigator, where `showDialog` and
/// `Navigator.of(context)` throw "Navigator operation requested with a
/// context that does not include a Navigator" every single time.
class UpdateAvailableCard extends StatelessWidget {
  const UpdateAvailableCard({
    super.key,
    required this.update,
    required this.onDismiss,
  });

  final AppUpdateInfo update;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? DesignColors.darkSurface : Colors.white;
    final borderColor = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final textPrimary = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final textSecondary = isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Material(
      color: isDark ? Colors.black54 : Colors.black45,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(DesignSpacing.xl),
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(DesignSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _IconBadge(isDark: isDark),
                        const SizedBox(width: DesignSpacing.md),
                        Expanded(
                          child: Text(
                            'Update available',
                            style:
                                Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignSpacing.lg),
                    Row(
                      children: [
                        StatusBadge(
                          label: update.displayVersion,
                          color: DesignColors.accent,
                        ),
                      ],
                    ),
                    if (update.releaseNotes.trim().isNotEmpty) ...[
                      const SizedBox(height: DesignSpacing.md),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: SingleChildScrollView(
                          child: CategorizedNotes(releaseNotes: update.releaseNotes.trim()),
                        ),
                      ),
                    ],
                    const SizedBox(height: DesignSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: onDismiss,
                            style: TextButton.styleFrom(
                              foregroundColor: textSecondary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  DesignSpacing.radiusMd,
                                ),
                              ),
                            ),
                            child: const Text('Later'),
                          ),
                        ),
                        const SizedBox(width: DesignSpacing.sm),
                        Expanded(
                          child: SettingsPrimaryButton(
                            label: 'Update now',
                            onPressed: () {
                              onDismiss();
                              getIt<UpdateCheckService>()
                                  .beginOptionalUpdateNow(update);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ).animate().scale(
                  begin: const Offset(0.88, 0.88),
                  end: const Offset(1.0, 1.0),
                  duration: 450.ms,
                  curve: Curves.easeOutBack,
                ),
          ),
        ),
      ),
    );
  }
}

class _UpdateDialogButtonBar extends StatelessWidget {
  const _UpdateDialogButtonBar({
    required this.update,
    required this.dialogContext,
  });

  final AppUpdateInfo update;
  final BuildContext dialogContext;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: TextButton.styleFrom(
              foregroundColor: textSecondary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              ),
            ),
            child: const Text('Later'),
          ),
        ),
        const SizedBox(width: DesignSpacing.sm),
        Expanded(
          child: SettingsPrimaryButton(
            label: 'Update now',
            onPressed: () {
              Navigator.of(dialogContext).pop();
              getIt<UpdateCheckService>().beginOptionalUpdateNow(update);
            },
          ),
        ),
      ],
    );
  }
}
