import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/api_client.dart';
import '../widgets/update_available_dialog.dart';
import 'update_version_utils.dart';

// GitHub Packages configuration
const String _githubPackagesTokenEnv = 'GITHUB_TOKEN';
const String _githubPackagesReleaseApi =
    'https://api.github.com/repos/JohnHika/Jawaki-pos/releases';

class UpdateSource {
  const UpdateSource({
    required this.name,
    required this.url,
    required this.priority,
  });

  factory UpdateSource.fromJson(Map<String, dynamic> json) {
    return UpdateSource(
      name: (json['name'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      priority: (json['priority'] ?? 'primary').toString() == 'primary'
          ? 'primary'
          : 'secondary',
    );
  }

  final String name;
  final String url;
  final String priority;
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    this.releaseName,
    this.buildNumber,
    required this.minSupportedVersion,
    this.minSupportedBuildNumber,
    required this.forceUpdate,
    required this.apkUrl,
    required this.releaseNotes,
    this.publishedAt,
    this.updateSources,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    List<UpdateSource>? sources;
    final sourcesJson = json['updateSources'];
    if (sourcesJson is List) {
      sources = sourcesJson
          .map((e) => UpdateSource.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return AppUpdateInfo(
      latestVersion: (json['latestVersion'] ?? '').toString(),
      releaseName: _readOptionalString(json['releaseName']) ??
          _readOptionalString(json['displayVersion']),
      buildNumber: _readOptionalInt(json['buildNumber']),
      minSupportedVersion: (json['minSupportedVersion'] ?? '').toString(),
      minSupportedBuildNumber:
          _readOptionalInt(json['minSupportedBuildNumber']),
      forceUpdate: json['forceUpdate'] == true,
      apkUrl: (json['apkUrl'] ?? '').toString(),
      releaseNotes: (json['releaseNotes'] ?? '').toString(),
      publishedAt: json['publishedAt'] == null ||
              json['publishedAt'].toString().trim().isEmpty
          ? null
          : DateTime.tryParse(json['publishedAt'].toString()),
      updateSources: sources,
    );
  }

  final String latestVersion;
  final String? releaseName;
  final int? buildNumber;
  final String minSupportedVersion;
  final int? minSupportedBuildNumber;
  final bool forceUpdate;
  final String apkUrl;
  final String releaseNotes;
  final DateTime? publishedAt;
  final List<UpdateSource>? updateSources;

  String get displayVersion {
    final name = releaseName?.trim();
    return name == null || name.isEmpty ? latestVersion : name;
  }

  String get noticeKey {
    final build = buildNumber;
    return build == null ? displayVersion : '$displayVersion#$build';
  }

  static String? _readOptionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _readOptionalInt(Object? value) {
    if (value == null) return null;
    final parsed = int.tryParse(value.toString().trim());
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

class UpdateCheckService extends ChangeNotifier {
  UpdateCheckService({required ApiClient apiClient}) : _apiClient = apiClient;

  static const MethodChannel _installerChannel =
      MethodChannel('pos_mobile/installer');
  static const Duration _checkInterval = Duration(hours: 6);

  final ApiClient _apiClient;

  DateTime? _lastCheckTime;
  bool _isChecking = false;
  bool _isDownloading = false;
  bool _isInstalling = false;
  bool _requiresInstallerPermission = false;
  double? _downloadProgress;
  int? _downloadedBytes;
  int? _totalBytes;
  String? _errorMessage;
  String? _currentVersion;
  String? _downloadedApkPath;
  AppUpdateInfo? _cachedUpdate;
  AppUpdateInfo? _requiredUpdate;
  AppUpdateInfo? _optionalUpdate;
  AppUpdateInfo? _installedUpdateNotice;
  final Stopwatch _downloadDuration = Stopwatch();

  // Set by checkAfterLogin() — deliberately independent of _requiredUpdate
  // (which stays reserved for the existing forceUpdate/minSupportedVersion
  // floor check on resume/cold-start). Any update at all is treated as
  // required immediately after a fresh login, per product decision.
  AppUpdateInfo? _postLoginUpdate;

  bool get hasOptionalUpdateAvailable => _optionalUpdate != null;
  bool get isForceUpdateRequired => _requiredUpdate != null;
  bool get isPostLoginUpdateRequired => _postLoginUpdate != null;
  bool get isDownloading => _isDownloading;
  bool get isInstalling => _isInstalling;
  bool get requiresInstallerPermission => _requiresInstallerPermission;
  double? get downloadProgress => _downloadProgress;
  int? get downloadedBytes => _downloadedBytes;
  int? get totalBytes => _totalBytes;
  Duration get downloadElapsed => _downloadDuration.elapsed;
  String? get errorMessage => _errorMessage;
  String? get currentVersion => _currentVersion;
  String? get downloadedApkPath => _downloadedApkPath;
  AppUpdateInfo? get requiredUpdate => _requiredUpdate;
  AppUpdateInfo? get optionalUpdate => _optionalUpdate;
  AppUpdateInfo? get installedUpdateNotice => _installedUpdateNotice;

  /// The update that should be shown by the (unified) full-screen gate,
  /// whichever trigger source it came from — the gate itself doesn't need
  /// to know or care why it's showing.
  AppUpdateInfo? get activeGateUpdate => _requiredUpdate ?? _postLoginUpdate;

  Future<bool> checkForUpdates({
    bool force = false,
  }) async {
    if (_isChecking) return isForceUpdateRequired || hasOptionalUpdateAvailable;

    final now = DateTime.now();
    if (!force &&
        _cachedUpdate != null &&
        _lastCheckTime != null &&
        now.difference(_lastCheckTime!) < _checkInterval) {
      final currentVersion = await _resolveCurrentVersion();
      _applyManifest(_cachedUpdate!, currentVersion);
      return isForceUpdateRequired || hasOptionalUpdateAvailable;
    }

    _isChecking = true;
    try {
      final currentVersion = await _resolveCurrentVersion();
      AppUpdateInfo? primaryUpdate;
      AppUpdateInfo? secondaryUpdate;

      // Step 1: Try Cloudflare R2 (primary source)
      try {
        final manifest =
            AppUpdateInfo.fromJson(await _apiClient.getLatestAndroidUpdate());
        primaryUpdate = manifest;
        if (!kReleaseMode) {
          debugPrint(
              '[UpdateCheck] Found primary update from Cloudflare: ${manifest.displayVersion}');
        }
      } catch (error) {
        if (!kReleaseMode) {
          debugPrint('[UpdateCheck] Cloudflare R2 update check failed: $error');
        }
      }

      // Step 2: Check GitHub Packages (secondary source) if Cloudflare fails or no update found
      if (primaryUpdate == null ||
          !_hasNewerBuildOrVersion(
            latestBuildNumber: primaryUpdate.buildNumber,
            currentBuildNumber: _currentBuildNumber(currentVersion),
            latestVersion: primaryUpdate.latestVersion,
            currentVersion: currentVersion,
          )) {
        try {
          final githubUpdate = await _getLatestGitHubPackagesUpdate();
          if (githubUpdate != null) {
            secondaryUpdate = githubUpdate;
            if (!kReleaseMode) {
              debugPrint(
                  '[UpdateCheck] Found secondary update from GitHub Packages: ${githubUpdate.latestVersion}');
            }
          }
        } catch (error) {
          if (!kReleaseMode) {
            debugPrint(
                '[UpdateCheck] GitHub Packages update check failed: $error');
          }
        }
      }

      // Step 3: Use primary update if available, otherwise use secondary
      final manifest = primaryUpdate ?? secondaryUpdate;
      if (manifest != null) {
        _cachedUpdate = manifest;
        _applyManifest(manifest, currentVersion);
      }

      // Fall back to a locally-persisted "just installed this build" notice
      // when the live manifest didn't already arm one (see
      // _persistPendingInstalledNotice) — covers the normal case where the
      // manifest has since moved on to describe a newer release, or the
      // network is unavailable right after the update relaunch.
      if (_installedUpdateNotice == null) {
        await _applyPendingInstalledNoticeIfMatches(currentVersion);
        if (_installedUpdateNotice != null) {
          notifyListeners();
        }
      }

      return isForceUpdateRequired || hasOptionalUpdateAvailable;
    } catch (error) {
      if (!kReleaseMode) {
        debugPrint('[UpdateCheck] Error: $error');
      }

      if (_requiredUpdate != null) {
        _errorMessage =
            'Could not refresh update status. Check your internet connection and try again.';
        notifyListeners();
        return true;
      }
    } finally {
      _isChecking = false;
      _lastCheckTime = now;
    }

    return false;
  }

  /// Called right after a successful login. Unlike the passive
  /// resume/cold-start check (which only blocks when a version falls
  /// below `minSupportedVersion` or the manifest sets `forceUpdate`),
  /// this treats ANY newer version as required — the user should not be
  /// able to keep using an outdated build simply because it still meets
  /// the historical floor.
  Future<void> checkAfterLogin() async {
    await checkForUpdates(force: true);

    final newer = _optionalUpdate ?? _requiredUpdate;
    if (newer != null) {
      _postLoginUpdate = newer;
      notifyListeners();
    }
  }

  /// Get the latest Android update from GitHub Packages releases
  Future<AppUpdateInfo?> _getLatestGitHubPackagesUpdate() async {
    try {
      // Use GitHub API to get the latest release
      final dio = Dio();
      final response = await dio.get(_githubPackagesReleaseApi,
          options: Options(
            headers: {
              'Accept': 'application/vnd.github.v3+json',
              if (_githubPackagesTokenEnv.isNotEmpty)
                'Authorization': 'token $_githubPackagesTokenEnv',
            },
          ));

      if (response.statusCode != 200 || response.data == null) {
        if (!kReleaseMode) {
          debugPrint(
              '[UpdateCheck] GitHub API returned status ${response.statusCode}');
        }
        return null;
      }

      // Parse the releases and find the latest APK
      final releases = response.data as List;
      for (final release in releases) {
        final assets = release['assets'] as List?;
        if (assets == null || assets.isEmpty) continue;

        final tagName = release['tag_name'] as String?;
        final body = release['body'] as String?;
        final publishedAt = release['published_at'] as String?;

        if (tagName == null) continue;

        // Look for APK asset
        for (final asset in assets) {
          final name = asset['name'] as String?;
          final browserDownloadUrl = asset['browser_download_url'] as String?;

          if (name != null &&
              browserDownloadUrl != null &&
              name.endsWith('.apk')) {
            // Extract version from tag_name (e.g., "v1.0.3+2004" or "1.0.3+2004")
            final version =
                tagName.startsWith('v') ? tagName.substring(1) : tagName;

            final apkUrl = _resolveGitHubPackagesApkUrl(browserDownloadUrl);

            return AppUpdateInfo(
              latestVersion: version,
              releaseName: 'Axon POS ${_stripBuildSuffix(version)}',
              buildNumber: _extractBuildNumber(version),
              minSupportedVersion:
                  '0.0.0', // GitHub Packages doesn't support min version
              forceUpdate:
                  false, // GitHub Packages always allows optional updates
              apkUrl: apkUrl,
              releaseNotes: body?.trim() ?? '',
              publishedAt:
                  publishedAt != null ? DateTime.parse(publishedAt) : null,
            );
          }
        }
      }

      if (!kReleaseMode) {
        debugPrint('[UpdateCheck] No APK found in GitHub Packages releases');
      }
      return null;
    } catch (error) {
      if (!kReleaseMode) {
        debugPrint(
            '[UpdateCheck] Error fetching GitHub Packages update: $error');
      }
      return null;
    }
  }

  String _resolveGitHubPackagesApkUrl(String rawUrl) {
    final parsed = Uri.tryParse(rawUrl.trim());
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }

    // If it's a relative URL, use GitHub's base URL
    final baseUri = Uri.parse('https://github.com');
    final normalizedPath = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
    return baseUri.resolve(normalizedPath).toString();
  }

  /// A lighter, genuinely dismissible first touchpoint for an update that
  /// isn't required yet (e.g. a manual "Check for updates" tap in
  /// Settings while the app is still above its minimum supported
  /// version). Choosing to update hands off to the same full-screen
  /// [ForcedUpdateGate] flow via [beginOptionalUpdateNow] — there is only
  /// one real download/install experience in the app.
  Future<void> showCachedOptionalUpdateDialog(BuildContext context) async {
    final optionalUpdate = _optionalUpdate;
    if (optionalUpdate == null) return;
    if (!context.mounted) return;

    await showUpdateAvailableDialog(context: context, update: optionalUpdate);
  }

  /// Whether the "you're up to date" screen still needs to be shown for
  /// the currently-installed version (i.e. this exact build hasn't
  /// already had its notice acknowledged). Pure state check — actually
  /// presenting the screen is the caller's job (see
  /// OptionalUpdatePromptHost), so this service stays UI-free.
  Future<AppUpdateInfo?> consumeInstalledUpdateNoticeIfDue() async {
    final update = _installedUpdateNotice;
    if (update == null || update.releaseNotes.trim().isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final noticeKey = update.noticeKey;
    if (prefs.getString('last_seen_update_notice') == noticeKey) return null;

    await prefs.setString('last_seen_update_notice', noticeKey);
    return update;
  }

  static const _pendingNoticeBuildKey = 'pending_update_notice_build';
  static const _pendingNoticeVersionKey = 'pending_update_notice_version';
  static const _pendingNoticeReleaseNotesKey =
      'pending_update_notice_release_notes';

  /// Records that this update's notice should be shown once the app
  /// relaunches on the new build, independent of whether a later live
  /// manifest fetch happens to report the same version (see
  /// _applyPendingInstalledNoticeIfMatches). Keyed on build number (the
  /// authoritative, unambiguous identifier for "did this exact install
  /// actually take effect"), since displayVersion/noticeKey may be a
  /// human-readable release name rather than the raw installed version.
  Future<void> _persistPendingInstalledNotice(AppUpdateInfo update) async {
    if (update.releaseNotes.trim().isEmpty) return;
    final buildNumber = update.buildNumber;
    if (buildNumber == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pendingNoticeBuildKey, buildNumber);
    await prefs.setString(_pendingNoticeVersionKey, update.displayVersion);
    await prefs.setString(_pendingNoticeReleaseNotesKey, update.releaseNotes);
  }

  /// Checks for a notice persisted by _persistPendingInstalledNotice and, if
  /// the app is now actually running that exact build (confirming the
  /// install completed rather than being cancelled), arms it as the
  /// installed-update notice. Always clears the stored flag either way, so a
  /// cancelled/failed install doesn't leave a stale pending notice around
  /// forever waiting for a build that will never launch.
  Future<void> _applyPendingInstalledNoticeIfMatches(
    String currentVersion,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingBuild = prefs.getInt(_pendingNoticeBuildKey);
    if (pendingBuild == null) return;

    final pendingVersion = prefs.getString(_pendingNoticeVersionKey) ?? '';
    final pendingNotes = prefs.getString(_pendingNoticeReleaseNotesKey) ?? '';
    await prefs.remove(_pendingNoticeBuildKey);
    await prefs.remove(_pendingNoticeVersionKey);
    await prefs.remove(_pendingNoticeReleaseNotesKey);

    final currentBuildNumber = _currentBuildNumber(currentVersion);
    if (currentBuildNumber == null ||
        pendingBuild != currentBuildNumber ||
        pendingNotes.trim().isEmpty) {
      return;
    }

    _installedUpdateNotice = AppUpdateInfo(
      latestVersion: _stripBuildSuffix(currentVersion),
      releaseName: pendingVersion.isEmpty ? null : pendingVersion,
      buildNumber: currentBuildNumber,
      minSupportedVersion: _stripBuildSuffix(currentVersion),
      forceUpdate: false,
      apkUrl: '',
      releaseNotes: pendingNotes,
    );
  }

  Future<void> downloadAndInstallRequiredUpdate() async {
    await _downloadAndInstall(activeGateUpdate);
  }

  Future<void> openInstallerPermissionSettings() async {
    if (!_isAndroid) return;

    try {
      await _installerChannel.invokeMethod('openUnknownSourcesSettings');
    } catch (error) {
      _errorMessage =
          'Could not open Android install settings automatically. Please enable “Install unknown apps” for this POS app in Settings.';
      notifyListeners();
      if (!kReleaseMode) {
        debugPrint('[UpdateCheck] Failed to open installer settings: $error');
      }
    }
  }

  Future<void> openDownloadFallback() async {
    final update = activeGateUpdate ?? _optionalUpdate;
    if (update == null || update.apkUrl.trim().isEmpty) {
      _errorMessage =
          'No fallback download link is configured for this update.';
      notifyListeners();
      return;
    }

    final resolvedUrl = _resolveDownloadUrl(update.apkUrl);
    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null) {
      _errorMessage = 'The configured update download link is invalid.';
      notifyListeners();
      return;
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _errorMessage = 'Could not open the fallback download link.';
      notifyListeners();
    }
  }

  Future<void> _downloadAndInstall(AppUpdateInfo? update) async {
    if (update == null) return;
    if (update.apkUrl.trim().isEmpty) {
      _errorMessage = 'No APK download URL is configured for this update.';
      notifyListeners();
      return;
    }

    final canInstall = await _canRequestPackageInstalls();
    if (!canInstall) {
      _requiresInstallerPermission = true;
      _errorMessage =
          'Android needs one-time permission to install updates from this POS app.';
      notifyListeners();
      return;
    }

    _requiresInstallerPermission = false;
    _errorMessage = null;
    _downloadProgress = 0;
    _downloadedBytes = null;
    _totalBytes = null;
    _isDownloading = true;
    _downloadDuration
      ..reset()
      ..start();
    notifyListeners();

    try {
      final file = await _downloadApk(update);
      _downloadedApkPath = file.path;
      _isDownloading = false;
      _isInstalling = true;
      notifyListeners();

      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );

      _isInstalling = false;
      _downloadProgress = null;
      _downloadDuration.stop();

      if (result.type != ResultType.done) {
        final message = result.message;
        _errorMessage = message.isNotEmpty
            ? message
            : 'Android installer could not be opened automatically. Use the fallback download link if needed.';
      } else {
        // The OS installer takes over from here and this process may be
        // killed before the app relaunches on the new build, so the
        // what's-new notice can't rely on a later live manifest re-fetch
        // happening to match this exact version by coincidence — persist
        // it now, before handing off, so it survives the relaunch.
        await _persistPendingInstalledNotice(update);
      }
      notifyListeners();
    } catch (error) {
      _isDownloading = false;
      _isInstalling = false;
      _downloadProgress = null;
      _downloadDuration.stop();
      _errorMessage = 'Update download failed: $error';
      notifyListeners();

      if (!kReleaseMode) {
        debugPrint('[UpdateCheck] Download/install error: $error');
      }
    }
  }

  Future<File> _downloadApk(AppUpdateInfo update) async {
    final tempDir = await getTemporaryDirectory();
    final safeVersion =
        update.displayVersion.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final filePath = p.join(tempDir.path, 'pos-update-$safeVersion.apk');
    final resolvedUrl = _resolveDownloadUrl(update.apkUrl);

    final downloader = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    await downloader.download(
      resolvedUrl,
      filePath,
      deleteOnError: true,
      onReceiveProgress: (received, total) {
        _downloadedBytes = received;
        if (total > 0) {
          _totalBytes = total;
          _downloadProgress = received / total;
        }
        notifyListeners();
      },
    );

    return File(filePath);
  }

  Future<String> _resolveCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    _currentVersion = composeComparableVersion(
      packageInfo.version,
      packageInfo.buildNumber,
    );
    return _currentVersion!;
  }

  Future<bool> _canRequestPackageInstalls() async {
    if (!_isAndroid) return true;

    try {
      final result = await _installerChannel
          .invokeMethod<bool>('canRequestPackageInstalls');
      return result ?? false;
    } catch (_) {
      // Fall back optimistically; installer launch will surface a better error.
      return true;
    }
  }

  void _applyManifest(AppUpdateInfo update, String currentVersion) {
    _currentVersion = currentVersion;

    final currentBuildNumber = _currentBuildNumber(currentVersion);
    final hasNewerVersion = _hasNewerBuildOrVersion(
      latestBuildNumber: update.buildNumber,
      currentBuildNumber: currentBuildNumber,
      latestVersion: update.latestVersion,
      currentVersion: currentVersion,
    );
    final belowMinimum = _isBelowMinimum(
      minSupportedBuildNumber: update.minSupportedBuildNumber,
      currentBuildNumber: currentBuildNumber,
      minSupportedVersion: update.minSupportedVersion,
      currentVersion: currentVersion,
    );
    final isRequired = hasNewerVersion && (belowMinimum || update.forceUpdate);

    _requiredUpdate = isRequired ? update : null;
    _optionalUpdate = hasNewerVersion && !isRequired ? update : null;
    _installedUpdateNotice =
        !hasNewerVersion && _sameBuildOrVersion(update, currentVersion)
            ? update
            : null;

    // Once the running app is no longer behind (e.g. right after the
    // freshly-installed build relaunches and re-checks), there's nothing
    // left for the post-login gate to require.
    if (!hasNewerVersion) {
      _postLoginUpdate = null;
    }

    if (_requiredUpdate == null) {
      _requiresInstallerPermission = false;
      _isDownloading = false;
      _isInstalling = false;
      _downloadProgress = null;
      _downloadDuration.stop();
      _errorMessage = null;
      _downloadedApkPath = null;
    }

    notifyListeners();
  }

  String _resolveDownloadUrl(String rawUrl) {
    final parsed = Uri.tryParse(rawUrl.trim());
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }

    final baseUri = Uri.parse(_apiClient.baseUrl);
    final origin = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
    );

    final normalizedPath = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
    return origin.resolve(normalizedPath).toString();
  }

  /// Promotes an optional (not-yet-required) update into the same
  /// required-update path the full-screen [ForcedUpdateGate] renders —
  /// so there is exactly one download/progress/error/permission
  /// experience in the app, not a second parallel implementation.
  void beginOptionalUpdateNow(AppUpdateInfo update) {
    _postLoginUpdate = update;
    notifyListeners();
  }

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  int? _currentBuildNumber(String currentVersion) {
    final plusIndex = currentVersion.indexOf('+');
    if (plusIndex < 0 || plusIndex == currentVersion.length - 1) return null;
    return int.tryParse(currentVersion.substring(plusIndex + 1));
  }

  int? _extractBuildNumber(String version) {
    final match = RegExp(r'(?:\+|-)(\d+)$').firstMatch(version.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String _stripBuildSuffix(String version) {
    return version.trim().replaceFirst(RegExp(r'(?:\+|-)\d+$'), '');
  }

  bool _hasNewerBuildOrVersion({
    required int? latestBuildNumber,
    required int? currentBuildNumber,
    required String latestVersion,
    required String currentVersion,
  }) {
    if (latestBuildNumber != null && currentBuildNumber != null) {
      return latestBuildNumber > currentBuildNumber;
    }

    return isNewerAppVersion(latestVersion, currentVersion);
  }

  bool _isBelowMinimum({
    required int? minSupportedBuildNumber,
    required int? currentBuildNumber,
    required String minSupportedVersion,
    required String currentVersion,
  }) {
    if (minSupportedBuildNumber != null && currentBuildNumber != null) {
      return minSupportedBuildNumber > currentBuildNumber;
    }

    return isNewerAppVersion(minSupportedVersion, currentVersion);
  }

  bool _sameBuildOrVersion(AppUpdateInfo update, String currentVersion) {
    final currentBuildNumber = _currentBuildNumber(currentVersion);
    if (update.buildNumber != null && currentBuildNumber != null) {
      return update.buildNumber == currentBuildNumber;
    }

    return !isNewerAppVersion(update.latestVersion, currentVersion) &&
        !isNewerAppVersion(currentVersion, update.latestVersion);
  }
}
