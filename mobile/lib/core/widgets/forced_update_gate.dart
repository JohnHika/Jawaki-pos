import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/update_check_service.dart';

class ForcedUpdateGate extends StatelessWidget {
  const ForcedUpdateGate({
    super.key,
    required this.updateService,
  });

  final UpdateCheckService updateService;

  @override
  Widget build(BuildContext context) {
    final update = updateService.requiredUpdate;
    if (update == null) {
      return const SizedBox.shrink();
    }

    final progress = updateService.downloadProgress;
    final progressLabel = progress == null
        ? null
        : '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%';

    return Material(
      color: Colors.black.withValues(alpha: 0.76),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              margin: const EdgeInsets.all(24),
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.system_update_alt_rounded,
                        size: 56,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Update required',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This POS version is no longer supported. Install the latest update to continue using the app.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[700],
                            ),
                      ),
                      const SizedBox(height: 20),
                      _VersionTile(
                        label: 'Current version',
                        value: _cleanVersion(updateService.currentVersion),
                        valueColor: Colors.orange,
                      ),
                      const SizedBox(height: 8),
                      _VersionTile(
                        label: 'Required version',
                        value: update.releaseName ?? update.minSupportedVersion,
                        valueColor: Colors.green,
                      ),
                      if (update.latestVersion != update.minSupportedVersion ||
                          update.releaseName != null) ...[
                        const SizedBox(height: 8),
                        _VersionTile(
                          label: 'Latest version',
                          value: update.displayVersion,
                          valueColor: Colors.green,
                        ),
                      ],
                      if (update.releaseNotes.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'What\'s new',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SingleChildScrollView(
                            child: Text(update.releaseNotes),
                          ),
                        ),
                      ],
                      if (updateService.errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            updateService.errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                      if (progress != null) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 8),
                        Text(
                          progressLabel ?? 'Downloading...',
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (updateService.requiresInstallerPermission)
                        FilledButton.icon(
                          onPressed:
                              updateService.openInstallerPermissionSettings,
                          icon: const Icon(Icons.settings_applications_rounded),
                          label: const Text('Enable install permission'),
                        )
                      else if (updateService.isDownloading)
                        FilledButton.icon(
                          onPressed: null,
                          icon: const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          label: Text(
                            progressLabel == null
                                ? 'Downloading update...'
                                : 'Downloading update... $progressLabel',
                          ),
                        )
                      else if (updateService.isInstalling)
                        FilledButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.install_mobile_rounded),
                          label: const Text('Opening installer...'),
                        )
                      else
                        FilledButton.icon(
                          onPressed:
                              updateService.downloadAndInstallRequiredUpdate,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Download & install update'),
                        ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: updateService.openDownloadFallback,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Open fallback download link'),
                      ),
                      const SizedBox(height: 8),
                      const TextButton(
                        onPressed: SystemNavigator.pop,
                        child: Text('Close app'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _cleanVersion(String? value) {
  if (value == null || value.isEmpty) return 'Unknown';
  final plusIndex = value.indexOf('+');
  return plusIndex < 0 ? value : value.substring(0, plusIndex);
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[700],
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
          ),
        ],
      ),
    );
  }
}
