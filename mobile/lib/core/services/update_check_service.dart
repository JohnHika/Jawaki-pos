import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service that checks release manifests for new Android versions.
///
/// Cloudflare R2 is the primary update source because it hosts the installable
/// APK. GitHub Releases are still checked as a fallback and for release notes.
class UpdateCheckService {
  UpdateCheckService._internal();
  static final UpdateCheckService _instance = UpdateCheckService._internal();
  factory UpdateCheckService() => _instance;

  static const String _githubOwner = 'JohnHika';
  static const String _githubRepo = 'Jawaki-pos';
  static const String _r2ManifestUrl =
      'https://pub-7f8ac9ce2a8c4e3cb5b1a89e37de7aec.r2.dev/android/latest.json';

  static const String _lastKnownInstalledKey =
      'update_notes_last_known_installed_version';
  static const String _lastShownInstalledKey =
      'update_notes_last_shown_installed_version';

  Uri get _r2ManifestUri => Uri.parse(_r2ManifestUrl);
  Uri get _githubReleasesUri => Uri.parse(
    'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases?per_page=10',
  );
  Uri get _githubLatestUri => Uri.parse(
    'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest',
  );

  DateTime? _lastCheckTime;
  static const Duration _checkInterval = Duration(hours: 6);
  bool _isChecking = false;

  _ReleaseInfo? _cachedUpdate;

  /// Checks for a newer version and shows the update dialog when one exists.
  Future<bool> checkForUpdates({
    BuildContext? context,
    bool force = false,
  }) async {
    if (_isChecking) return false;

    final now = DateTime.now();
    if (!force &&
        _lastCheckTime != null &&
        now.difference(_lastCheckTime!) < _checkInterval) {
      return false;
    }

    _isChecking = true;
    try {
      final current = await _InstalledVersion.current();
      final latest = await _fetchLatestUpdate();

      if (latest != null && latest.isNewerThan(current)) {
        _cachedUpdate = latest;
        if (context != null && context.mounted) {
          _showUpdateDialog(
            context: context,
            currentVersion: current.displayName,
            latest: latest,
          );
        }
        return true;
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

  /// Shows release notes once after the app has been upgraded.
  Future<bool> showInstalledUpdateNotesIfNeeded(BuildContext context) async {
    try {
      final current = await _InstalledVersion.current();
      final prefs = await SharedPreferences.getInstance();
      final currentKey = current.storageKey;
      final lastKnown = prefs.getString(_lastKnownInstalledKey);
      final lastShown = prefs.getString(_lastShownInstalledKey);

      if (lastKnown == null) {
        await prefs.setString(_lastKnownInstalledKey, currentKey);
        await prefs.setString(_lastShownInstalledKey, currentKey);
        return false;
      }

      if (lastKnown == currentKey || lastShown == currentKey) {
        await prefs.setString(_lastKnownInstalledKey, currentKey);
        return false;
      }

      final release = await _fetchReleaseForInstalledVersion(current);
      if (!context.mounted) return false;

      _showInstalledReleaseNotesDialog(
        context: context,
        installedVersion: current.displayName,
        release: release,
      );
      await prefs.setString(_lastKnownInstalledKey, currentKey);
      await prefs.setString(_lastShownInstalledKey, currentKey);
      return true;
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('[UpdateCheck] Installed notes error: $e');
      }
      return false;
    }
  }

  void showUpdateDialogFromCache(BuildContext context) async {
    final update = _cachedUpdate;
    if (update == null) return;

    final current = await _InstalledVersion.current();
    if (!context.mounted) return;
    _showUpdateDialog(
      context: context,
      currentVersion: current.displayName,
      latest: update,
    );
  }

  Future<_ReleaseInfo?> _fetchLatestUpdate() async {
    final candidates = <_ReleaseInfo>[];

    final manifestRelease = await _fetchR2ManifestRelease();
    if (manifestRelease != null) candidates.add(manifestRelease);

    candidates.addAll(await _fetchGitHubReleases());

    if (candidates.isEmpty) {
      final githubLatest = await _fetchGitHubLatestRelease();
      if (githubLatest != null) candidates.add(githubLatest);
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.compareTo(a));
    return candidates.first;
  }

  Future<_ReleaseInfo?> _fetchReleaseForInstalledVersion(
    _InstalledVersion installed,
  ) async {
    final candidates = <_ReleaseInfo>[];

    final manifestRelease = await _fetchR2ManifestRelease();
    if (manifestRelease != null) candidates.add(manifestRelease);
    candidates.addAll(await _fetchGitHubReleases());

    for (final release in candidates) {
      if (release.matches(installed)) return release;
    }
    return null;
  }

  Future<_ReleaseInfo?> _fetchR2ManifestRelease() async {
    try {
      final response = await http
          .get(
            _r2ManifestUri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'Levisa-POS-UpdateChecker',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final version = _asString(data['latestVersion']);
      if (version == null || version.isEmpty) return null;

      return _ReleaseInfo(
        version: version,
        buildNumber:
            _asInt(data['buildNumber']) ??
            _VersionParts.parse(version).buildNumber,
        notes: _asString(data['releaseNotes']),
        releaseUrl: _asString(data['releaseUrl']),
        apkUrl: _asString(data['apkUrl']),
      );
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('[UpdateCheck] R2 manifest error: $e');
      }
      return null;
    }
  }

  Future<List<_ReleaseInfo>> _fetchGitHubReleases() async {
    try {
      final response = await http
          .get(_githubReleasesUri, headers: _githubHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _logGitHubStatus(response.statusCode);
        return const [];
      }

      final releases = jsonDecode(response.body) as List<dynamic>;
      return releases
          .whereType<Map<String, dynamic>>()
          .where(
            (release) =>
                release['draft'] != true && release['prerelease'] != true,
          )
          .map(_releaseFromGitHubJson)
          .whereType<_ReleaseInfo>()
          .toList();
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('[UpdateCheck] GitHub releases error: $e');
      }
      return const [];
    }
  }

  Future<_ReleaseInfo?> _fetchGitHubLatestRelease() async {
    try {
      final response = await http
          .get(_githubLatestUri, headers: _githubHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _logGitHubStatus(response.statusCode);
        return null;
      }

      return _releaseFromGitHubJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('[UpdateCheck] GitHub latest error: $e');
      }
      return null;
    }
  }

  Map<String, String> get _githubHeaders => const {
    'Accept': 'application/vnd.github.v3+json',
    'User-Agent': 'Levisa-POS-UpdateChecker',
  };

  _ReleaseInfo? _releaseFromGitHubJson(Map<String, dynamic> data) {
    final tag = _asString(data['tag_name']);
    if (tag == null || tag.isEmpty) return null;

    final assets = data['assets'] is List ? data['assets'] as List : const [];
    String? apkUrl;
    for (final asset in assets.whereType<Map<String, dynamic>>()) {
      final name = _asString(asset['name'])?.toLowerCase();
      if (name != null && name.endsWith('.apk')) {
        apkUrl = _asString(asset['browser_download_url']);
        break;
      }
    }

    final parts = _VersionParts.parse(tag);
    return _ReleaseInfo(
      version: parts.semanticVersion,
      buildNumber: parts.buildNumber,
      notes: _asString(data['body']),
      releaseUrl:
          _asString(data['html_url']) ??
          'https://github.com/$_githubOwner/$_githubRepo/releases/tag/$tag',
      apkUrl: apkUrl,
    );
  }

  void _logGitHubStatus(int statusCode) {
    if (kReleaseMode) return;
    if (statusCode == 403) {
      debugPrint('[UpdateCheck] GitHub API rate-limited (403).');
    } else {
      debugPrint('[UpdateCheck] GitHub status: $statusCode');
    }
  }

  void _showUpdateDialog({
    required BuildContext context,
    required String currentVersion,
    required _ReleaseInfo latest,
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
                'A new version of Levisa Adventures POS is available.',
              ),
              const SizedBox(height: 12),
              _versionRow('Current', currentVersion, isOld: true),
              _versionRow('Latest', latest.displayName, isOld: false),
              if (latest.notes != null && latest.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'What\'s New:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _trimReleaseNotes(latest.notes!),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
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
            icon: Icon(
              latest.apkUrl != null ? Icons.download : Icons.open_in_new,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final url =
                  latest.apkUrl ??
                  latest.releaseUrl ??
                  'https://github.com/$_githubOwner/$_githubRepo/releases';
              await _openUrl(context, url);
            },
            label: Text(latest.apkUrl != null ? 'Update Now' : 'View Release'),
          ),
        ],
      ),
    );
  }

  void _showInstalledReleaseNotesDialog({
    required BuildContext context,
    required String installedVersion,
    required _ReleaseInfo? release,
  }) {
    final releaseNotes = release?.notes;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.celebration_outlined, color: Colors.green),
            SizedBox(width: 8),
            Text('App Updated'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('You are now running version $installedVersion.'),
              if (releaseNotes != null && releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'What\'s New:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _trimReleaseNotes(releaseNotes),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open update page')),
      );
    }
  }

  Widget _versionRow(String label, String version, {required bool isOld}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
          Flexible(
            child: Text(
              version,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isOld ? Colors.orange : Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _trimReleaseNotes(String notes) {
    const maxLength = 1200;
    final trimmed = notes.trim();
    if (trimmed.length <= maxLength) return trimmed;
    return '${trimmed.substring(0, maxLength).trimRight()}...';
  }

  String? _asString(Object? value) {
    if (value == null) return null;
    return value.toString();
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class _InstalledVersion {
  const _InstalledVersion({required this.version, required this.buildNumber});

  final String version;
  final int? buildNumber;

  static Future<_InstalledVersion> current() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return _InstalledVersion(
      version: packageInfo.version,
      buildNumber: int.tryParse(packageInfo.buildNumber),
    );
  }

  String get displayName =>
      buildNumber == null ? version : '$version+$buildNumber';

  String get storageKey => displayName;
}

class _ReleaseInfo {
  const _ReleaseInfo({
    required this.version,
    required this.buildNumber,
    required this.notes,
    required this.releaseUrl,
    required this.apkUrl,
  });

  final String version;
  final int? buildNumber;
  final String? notes;
  final String? releaseUrl;
  final String? apkUrl;

  String get displayName =>
      buildNumber == null ? version : '$version+$buildNumber';

  bool isNewerThan(_InstalledVersion current) {
    if (buildNumber != null && current.buildNumber != null) {
      return buildNumber! > current.buildNumber!;
    }
    return _compareSemantic(version, current.version) > 0;
  }

  bool matches(_InstalledVersion installed) {
    if (buildNumber != null && installed.buildNumber != null) {
      return buildNumber == installed.buildNumber;
    }
    return _compareSemantic(version, installed.version) == 0;
  }

  int compareTo(_ReleaseInfo other) {
    if (buildNumber != null && other.buildNumber != null) {
      final buildCompare = buildNumber!.compareTo(other.buildNumber!);
      if (buildCompare != 0) return buildCompare;
    }
    return _compareSemantic(version, other.version);
  }
}

class _VersionParts {
  const _VersionParts({
    required this.semanticVersion,
    required this.buildNumber,
  });

  final String semanticVersion;
  final int? buildNumber;

  static _VersionParts parse(String raw) {
    final cleaned = raw.trim().replaceFirst(
      RegExp(r'^v', caseSensitive: false),
      '',
    );
    final match = RegExp(
      r'^([0-9]+(?:\.[0-9]+){0,2})(?:[+-]([0-9]+))?',
    ).firstMatch(cleaned);

    if (match == null) {
      return _VersionParts(semanticVersion: cleaned, buildNumber: null);
    }

    return _VersionParts(
      semanticVersion: match.group(1) ?? cleaned,
      buildNumber: int.tryParse(match.group(2) ?? ''),
    );
  }
}

int _compareSemantic(String a, String b) {
  final aParts = _semanticParts(a);
  final bParts = _semanticParts(b);
  for (var i = 0; i < 3; i++) {
    final diff = aParts[i].compareTo(bParts[i]);
    if (diff != 0) return diff;
  }
  return 0;
}

List<int> _semanticParts(String version) {
  final match = RegExp(r'[0-9]+(?:\.[0-9]+){0,2}').firstMatch(version);
  final value = match?.group(0) ?? '0.0.0';
  final parts = value
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList();
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts.take(3).toList();
}
