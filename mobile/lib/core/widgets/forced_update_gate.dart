import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/update_check_service.dart';
import '../theme/design_system.dart';

/// Full-screen, non-dismissible update prompt — shown whenever
/// [UpdateCheckService.activeGateUpdate] is non-null, regardless of
/// whether it came from the resume/cold-start version-floor check or the
/// post-login "any newer version is required" check. The two triggers are
/// tracked separately on the service, but from here they're the same
/// moment: the user must update before continuing.
class ForcedUpdateGate extends StatelessWidget {
  const ForcedUpdateGate({
    super.key,
    required this.updateService,
  });

  final UpdateCheckService updateService;

  @override
  Widget build(BuildContext context) {
    final update = updateService.activeGateUpdate;
    if (update == null) {
      return const SizedBox.shrink();
    }

    final isBusy = updateService.isDownloading || updateService.isInstalling;

    return Material(
      color: DesignColors.darkBg,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignSpacing.xxl,
                vertical: DesignSpacing.xxxl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Mark(pulsing: isBusy),
                  const SizedBox(height: DesignSpacing.xxl),
                  Text(
                    isBusy ? 'Updating Axon POS' : 'Update Required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: DesignColors.darkTextPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  )
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(
                        begin: 0.1,
                        end: 0.0,
                        duration: 400.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: DesignSpacing.sm),
                  Text(
                    isBusy
                        ? 'Hang tight — this only takes a moment.'
                        : 'A newer version is available. Update now to keep using Axon POS.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: DesignColors.darkTextSecondary,
                          height: 1.45,
                        ),
                  )
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 100.ms)
                      .slideY(
                        begin: 0.1,
                        end: 0.0,
                        duration: 400.ms,
                        delay: 100.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: DesignSpacing.xxl),
                  if (isBusy)
                    _DownloadTelemetry(updateService: updateService)
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .slideY(
                          begin: 0.08,
                          end: 0.0,
                          duration: 400.ms,
                          curve: Curves.easeOutCubic,
                        )
                  else
                    _UpdateSummary(
                      updateService: updateService,
                      update: update,
                    )
                        .animate()
                        .fadeIn(duration: 500.ms)
                        .slideY(
                          begin: 0.12,
                          end: 0.0,
                          duration: 500.ms,
                          curve: Curves.easeOutCubic,
                        ),
                  if (updateService.errorMessage != null) ...[
                    const SizedBox(height: DesignSpacing.lg),
                    _ErrorBanner(message: updateService.errorMessage!)
                        .animate()
                        .fadeIn(duration: 300.ms)
                        .slideY(
                          begin: 0.05,
                          end: 0.0,
                          duration: 300.ms,
                          curve: Curves.easeOutCubic,
                        ),
                  ],
                  const SizedBox(height: DesignSpacing.xxl),
                  if (updateService.requiresInstallerPermission)
                    SettingsPrimaryButton(
                      label: 'Enable install permission',
                      onPressed: updateService.openInstallerPermissionSettings,
                    )
                  else if (updateService.isDownloading)
                    const SettingsPrimaryButton(
                      label: 'Downloading…',
                      isLoading: true,
                      onPressed: null,
                    )
                  else if (updateService.isInstalling)
                    const SettingsPrimaryButton(
                      label: 'Opening installer…',
                      isLoading: true,
                      onPressed: null,
                    )
                  else
                    SettingsPrimaryButton(
                      label: 'Download & install update',
                      onPressed: updateService.downloadAndInstallRequiredUpdate,
                    ),
                  const SizedBox(height: DesignSpacing.md),
                  TextButton(
                    onPressed: updateService.openDownloadFallback,
                    style: TextButton.styleFrom(
                      foregroundColor: DesignColors.darkTextSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Open fallback download link'),
                  ),
                  if (!isBusy) ...[
                    const SizedBox(height: DesignSpacing.xs),
                    TextButton(
                      onPressed: SystemNavigator.pop,
                      style: TextButton.styleFrom(
                        foregroundColor: DesignColors.darkTextTertiary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: const Text('Close app'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.pulsing});

  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: DesignColors.accentSubtle,
          shape: BoxShape.circle,
          border: Border.all(
            color: DesignColors.accent.withValues(alpha: pulsing ? 0.6 : 0.35),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: DesignColors.accent.withValues(
                alpha: pulsing ? 0.35 : 0.18,
              ),
              blurRadius: pulsing ? 32 : 20,
              spreadRadius: pulsing ? 4 : 1,
            ),
          ],
        ),
        child: Icon(
          pulsing
              ? Icons.downloading_rounded
              : Icons.system_update_alt_rounded,
          color: DesignColors.accent,
          size: 42,
        ),
      )
          .animate()
          .scale(
            begin: const Offset(0.75, 0.75),
            end: const Offset(1.0, 1.0),
            duration: 500.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 350.ms)
          .then()
          .custom(
            duration: 1800.ms,
            builder: (context, value, child) {
              final scale = 1.0 + (pulsing ? 0.05 * value : 0.0);
              return Transform.scale(scale: scale, child: child);
            },
          ),
    );
  }
}

class _UpdateSummary extends StatelessWidget {
  const _UpdateSummary({
    required this.updateService,
    required this.update,
  });

  final UpdateCheckService updateService;
  final AppUpdateInfo update;

  @override
  Widget build(BuildContext context) {
    final notes = _parseReleaseNotes(update.releaseNotes);

    return GlassCard(
      padding: const EdgeInsets.all(DesignSpacing.xl),
      borderRadius: DesignSpacing.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _VersionColumn(
                  label: 'Current',
                  value: _cleanVersion(updateService.currentVersion),
                  color: DesignColors.darkTextSecondary,
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: DesignColors.accent,
              ),
              Expanded(
                child: _VersionColumn(
                  label: 'New',
                  value: update.displayVersion,
                  color: DesignColors.accent,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: DesignSpacing.lg),
            const Divider(color: DesignColors.darkBorder, height: 1),
            const SizedBox(height: DesignSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "What's new",
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: DesignColors.darkTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(height: DesignSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < notes.length; i++)
                      _ReleaseNoteRow(
                        text: notes[i],
                        delay: i * 60,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VersionColumn extends StatelessWidget {
  const _VersionColumn({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: DesignColors.darkTextTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: DesignType.numeric(fontSize: 18, color: color),
        ),
      ],
    );
  }
}

class _ReleaseNoteRow extends StatelessWidget {
  const _ReleaseNoteRow({required this.text, required this.delay});

  final String text;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: DesignColors.accent,
            ),
          ),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DesignColors.darkTextSecondary,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms, delay: Duration(milliseconds: delay))
        .slideX(
          begin: -0.04,
          end: 0.0,
          duration: 350.ms,
          delay: Duration(milliseconds: delay),
          curve: Curves.easeOutCubic,
        );
  }
}

class _DownloadTelemetry extends StatelessWidget {
  const _DownloadTelemetry({required this.updateService});

  final UpdateCheckService updateService;

  @override
  Widget build(BuildContext context) {
    final progress = updateService.downloadProgress;
    final downloaded = updateService.downloadedBytes;
    final total = updateService.totalBytes;
    final elapsed = updateService.downloadElapsed;

    final percentLabel = progress == null
        ? '—'
        : '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%';
    final sizeLabel = (downloaded == null)
        ? null
        : total != null
            ? '${_formatBytes(downloaded)} / ${_formatBytes(total)}'
            : _formatBytes(downloaded);
    final speedLabel = (downloaded != null && elapsed.inMilliseconds > 500)
        ? '${_formatBytes((downloaded / (elapsed.inMilliseconds / 1000)).round())}/s'
        : null;

    return GlassCard(
      padding: const EdgeInsets.all(DesignSpacing.xl),
      borderRadius: DesignSpacing.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                updateService.isInstalling ? 'Installing' : 'Downloading',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: DesignColors.darkTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                percentLabel,
                style: DesignType.numeric(
                  fontSize: 20,
                  color: DesignColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.md),
          _AnimatedProgressBar(progress: updateService.isInstalling ? null : progress),
          if (sizeLabel != null || speedLabel != null) ...[
            const SizedBox(height: DesignSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (sizeLabel != null)
                  Text(
                    sizeLabel,
                    style: DesignType.numeric(
                      fontSize: 13,
                      color: DesignColors.darkTextSecondary,
                    ),
                  ),
                if (speedLabel != null)
                  StatusBadge(
                    label: speedLabel,
                    color: DesignColors.accent,
                    isActive: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AnimatedProgressBar extends StatelessWidget {
  const _AnimatedProgressBar({this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final clamped = progress?.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(
            height: 8,
            decoration: const BoxDecoration(
              color: DesignColors.darkSurfaceElevated,
            ),
          ),
          if (clamped != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              height: 8,
              width: MediaQuery.of(context).size.width * clamped,
              decoration: BoxDecoration(
                color: DesignColors.accent,
                boxShadow: [
                  BoxShadow(
                    color: DesignColors.accent.withValues(alpha: 0.45),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            )
              .animate()
              .shimmer(
                duration: 1500.ms,
                color: DesignColors.accentLight.withValues(alpha: 0.35),
              )
              .shake(
                hz: 0.6,
                rotation: 0.0,
                duration: const Duration(seconds: 2),
              )
          else
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: DesignColors.accent.withValues(alpha: 0.25),
              ),
            ).animate().shimmer(
                  duration: 1200.ms,
                  color: DesignColors.accent.withValues(alpha: 0.4),
                ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: DesignColors.errorSubtle,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(
          color: DesignColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: DesignColors.error,
          ),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: DesignColors.error,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _cleanVersion(String? value) {
  if (value == null || value.isEmpty) return 'Unknown';
  final plusIndex = value.indexOf('+');
  return plusIndex < 0 ? value : value.substring(0, plusIndex);
}

/// Splits release notes into individual bullet lines. Falls back to a
/// single "row" containing the whole string if it has no newlines, so a
/// plain sentence still renders instead of looking empty.
List<String> _parseReleaseNotes(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];

  final lines = trimmed
      .split('\n')
      .map((line) => line.trim().replaceFirst(RegExp(r'^[-*•]\s*'), ''))
      .where((line) => line.isNotEmpty)
      .toList();

  return lines.isEmpty ? [trimmed] : lines;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}
