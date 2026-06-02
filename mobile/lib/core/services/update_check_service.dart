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
import 'package:url_launcher/url_launcher.dart';

import '../network/api_client.dart';
import 'update_version_utils.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    required this.minSupportedVersion,
    required this.forceUpdate,
    required this.apkUrl,
    required this.releaseNotes,
    this.publishedAt,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      latestVersion: (json['latestVersion'] ?? '').toString(),
      minSupportedVersion: (json['minSupportedVersion'] ?? '').toString(),
      forceUpdate: json['forceUpdate'] == true,
      apkUrl: (json['apkUrl'] ?? '').toString(),
      releaseNotes: (json['releaseNotes'] ?? '').toString(),
      publishedAt: json['publishedAt'] == null ||
              json['publishedAt'].toString().trim().isEmpty
          ? null
          : DateTime.tryParse(json['publishedAt'].toString()),
    );
  }

  final String latestVersion;
  final String minSupportedVersion;
  final bool forceUpdate;
  final String apkUrl;
  final String releaseNotes;
  final DateTime? publishedAt;
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
  String? _errorMessage;
  String? _currentVersion;
  String? _downloadedApkPath;
  AppUpdateInfo? _cachedUpdate;
  AppUpdateInfo? _requiredUpdate;
  AppUpdateInfo? _optionalUpdate;

  bool get hasOptionalUpdateAvailable => _optionalUpdate != null;
  bool get isForceUpdateRequired => _requiredUpdate != null;
  bool get isDownloading => _isDownloading;
  bool get isInstalling => _isInstalling;
  bool get requiresInstallerPermission => _requiresInstallerPermission;
  double? get downloadProgress => _downloadProgress;
  String? get errorMessage => _errorMessage;
  String? get currentVersion => _currentVersion;
  String? get downloadedApkPath => _downloadedApkPath;
  AppUpdateInfo? get requiredUpdate => _requiredUpdate;
  AppUpdateInfo? get optionalUpdate => _optionalUpdate;

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
      final manifest =
          AppUpdateInfo.fromJson(await _apiClient.getLatestAndroidUpdate());
      _cachedUpdate = manifest;
      _applyManifest(manifest, currentVersion);
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

  Future<void> showCachedOptionalUpdateDialog(BuildContext context) async {
    final optionalUpdate = _optionalUpdate;
    if (optionalUpdate == null) return;

    final currentVersion = _currentVersion ?? await _resolveCurrentVersion();
    if (!context.mounted) return;

    await _showOptionalUpdateDialog(
      context: context,
      currentVersion: currentVersion,
      update: optionalUpdate,
    );
  }

  Future<void> downloadAndInstallRequiredUpdate() async {
    await _downloadAndInstall(_requiredUpdate);
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
    final update = _requiredUpdate ?? _optionalUpdate;
    if (update == null || update.apkUrl.trim().isEmpty) {
      _errorMessage = 'No fallback download link is configured for this update.';
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
    _isDownloading = true;
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

      if (result.type != ResultType.done) {
        final message = result.message;
        _errorMessage = message.isNotEmpty
            ? message
            : 'Android installer could not be opened automatically. Use the fallback download link if needed.';
      }
      notifyListeners();
    } catch (error) {
      _isDownloading = false;
      _isInstalling = false;
      _downloadProgress = null;
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
        update.latestVersion.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
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
        if (total <= 0) return;
        _downloadProgress = received / total;
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

    final hasNewerVersion =
      isNewerAppVersion(update.latestVersion, currentVersion);
    final belowMinimum =
      isNewerAppVersion(update.minSupportedVersion, currentVersion);
    final isRequired = hasNewerVersion && (belowMinimum || update.forceUpdate);

    _requiredUpdate = isRequired ? update : null;
    _optionalUpdate = hasNewerVersion && !isRequired ? update : null;

    if (_requiredUpdate == null) {
      _requiresInstallerPermission = false;
      _isDownloading = false;
      _isInstalling = false;
      _downloadProgress = null;
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
  Future<void> _showOptionalUpdateDialog({
    required BuildContext context,
    required String currentVersion,
    required AppUpdateInfo update,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update_alt_rounded, color: Colors.green),
            SizedBox(width: 8),
            Text('Update Available'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('A newer POS version is available for this device.'),
              const SizedBox(height: 12),
              _versionRow('Current', currentVersion, isOld: true),
              _versionRow('Latest', update.latestVersion, isOld: false),
              if (update.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'What\'s New:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  update.releaseNotes,
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
            icon: const Icon(Icons.download),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _downloadAndInstall(update);
            },
            label: const Text('Download Update'),
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

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
}
