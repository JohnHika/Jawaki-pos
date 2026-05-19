import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service that checks GitHub Releases for new versions of the app.
/// 
/// When a new GitHub Release is published with a higher version tag,
/// users see an update dialog when opening the app or from Settings.
class UpdateCheckService {
  UpdateCheckService._internal();
  static final UpdateCheckService _instance = UpdateCheckService._internal();
  factory UpdateCheckService() => _instance;

  static const String _githubOwner = 'JohnHika';
  static const String _githubRepo = 'Jawaki-pos';

  Uri get _apiUri => Uri.parse(
      'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest');

  DateTime? _lastCheckTime;
  static const Duration _checkInterval = Duration(hours: 6);
  bool _isChecking = false;

  /// Latest version info cached after successful check.
  /// Used so we can show it from settings without re-fetching.
  String? _cachedLatestVersion;
  String? _cachedReleaseNotes;
  String? _cachedReleaseUrl;

  /// Checks GitHub Releases for a newer version.
  /// 
  /// [context] — required to show the update dialog.
  /// [force] — if true, ignores the cache interval and checks immediately.
  /// Returns true if an update dialog was shown.
  Future<bool> checkForUpdates({
    BuildContext? context,
    bool force = false,
  }) async {
    if (_isChecking) return false;

    if (!force) {
      final now = DateTime.now();
      if (_lastCheckTime != null &&
          now.difference(_lastCheckTime!) < _checkInterval) {
        // Still within cache window — use cached data if we have context
        if (context != null && _cachedLatestVersion != null) {
          final packageInfo = await PackageInfo.fromPlatform();
          _showUpdateDialog(
            context: context,
            currentVersion: packageInfo.version,
            latestVersion: _cachedLatestVersion!,
            releaseNotes: _cachedReleaseNotes,
            releaseUrl: _cachedReleaseUrl,
          );
          return true;
        }
        return false;
      }
    }

    _isChecking = true;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http
          .get(_apiUri, headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'Levisa-POS-UpdateChecker',
          })
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final latestTag = data['tag_name'] as String?;
        final releaseNotes = data['body'] as String?;
        final releaseUrl = data['html_url'] as String?;

        if (latestTag != null && _isNewerVersion(latestTag, currentVersion)) {
          // Cache the info
          _cachedLatestVersion = latestTag;
          _cachedReleaseNotes = releaseNotes;
          _cachedReleaseUrl = releaseUrl;

          if (context != null) {
            _showUpdateDialog(
              context: context,
              currentVersion: currentVersion,
              latestVersion: latestTag,
              releaseNotes: releaseNotes,
              releaseUrl: releaseUrl,
            );
          }
          return true;
        }
      } else if (response.statusCode == 403) {
        if (!kReleaseMode) {
          debugPrint(
              '[UpdateCheck] GitHub API rate-limited (403). Try adding a token for private repos.');
        }
      } else {
        if (!kReleaseMode) {
          debugPrint('[UpdateCheck] Unexpected status: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('[UpdateCheck] Error: $e');
      }
    } finally {
      _isChecking = false;
      _lastCheckTime = DateTime.now();
    }
    return false;
  }

  bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts =
          latest.replaceFirst(RegExp(r'^v'), '').split('.').map(int.parse).toList();
      final currentParts =
          current.replaceFirst(RegExp(r'^v'), '').split('.').map(int.parse).toList();

      while (latestParts.length < 3) {
        latestParts.add(0);
      }
      while (currentParts.length < 3) {
        currentParts.add(0);
      }

      for (int i = 0; i < latestParts.length; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('[UpdateCheck] Version parse error: $e');
      }
      return latest.compareTo(current) > 0;
    }
  }

  /// Shows the update dialog.
  void showUpdateDialogFromCache(BuildContext context) async {
    if (_cachedLatestVersion != null) {
      final packageInfo = await PackageInfo.fromPlatform();
      _showUpdateDialog(
        context: context,
        currentVersion: packageInfo.version,
        latestVersion: _cachedLatestVersion!,
        releaseNotes: _cachedReleaseNotes,
        releaseUrl: _cachedReleaseUrl,
      );
    }
  }

  void _showUpdateDialog({
    required BuildContext context,
    required String currentVersion,
    required String latestVersion,
    String? releaseNotes,
    String? releaseUrl,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Colors.green),
            SizedBox(width: 8),
            Text('Update Available'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A new version of Levisa Adventures POS is available!',
              ),
              const SizedBox(height: 12),
              _versionRow('Current', currentVersion, isOld: true),
              _versionRow('Latest', latestVersion, isOld: false),
              if (releaseNotes != null && releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('What\'s New:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(releaseNotes,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.download),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final url = releaseUrl ??
                  'https://github.com/$_githubOwner/$_githubRepo/releases/latest';
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url),
                    mode: LaunchMode.externalApplication);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Could not open update page')),
                  );
                }
              }
            },
            label: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  Widget _versionRow(String label, String version, {required bool isOld}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
          Text(
            version,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isOld ? Colors.orange : Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}
