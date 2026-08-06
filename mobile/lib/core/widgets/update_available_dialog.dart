import 'package:flutter/material.dart';

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
    builder: (ctx) => Dialog(
      backgroundColor: DesignColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
        side: const BorderSide(color: DesignColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: DesignColors.accentSubtle,
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    color: DesignColors.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: DesignSpacing.md),
                Expanded(
                  child: Text(
                    'Update available',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          color: DesignColors.darkTextPrimary,
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
                constraints: const BoxConstraints(maxHeight: 140),
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
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: DesignColors.darkTextSecondary,
                    ),
                    child: const Text('Later'),
                  ),
                ),
                const SizedBox(width: DesignSpacing.sm),
                Expanded(
                  child: SettingsPrimaryButton(
                    label: 'Update now',
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      getIt<UpdateCheckService>().beginOptionalUpdateNow(update);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
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
    return Material(
      color: Colors.black54,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(DesignSpacing.xl),
            child: Container(
              decoration: BoxDecoration(
                color: DesignColors.darkSurface,
                borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
                border: Border.all(color: DesignColors.darkBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.all(DesignSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: DesignColors.accentSubtle,
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusMd),
                          ),
                          child: const Icon(
                            Icons.system_update_alt_rounded,
                            color: DesignColors.accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: DesignSpacing.md),
                        Expanded(
                          child: Text(
                            'Update available',
                            style:
                                Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: DesignColors.darkTextPrimary,
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
                        constraints: const BoxConstraints(maxHeight: 140),
                        child: SingleChildScrollView(
                          child: Text(
                            update.releaseNotes.trim(),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: DesignColors.darkTextSecondary,
                                    ),
                          ),
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
                              foregroundColor: DesignColors.darkTextSecondary,
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
            ),
          ),
        ),
      ),
    );
  }
}
