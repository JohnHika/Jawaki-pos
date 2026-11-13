import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_version_utils.dart';

/// Where the release list comes from. A build made with
/// `--dart-define=COUNTERBASE_UPDATE_FEED=<url>` reads that URL instead, which
/// is how an update is rehearsed on one computer without publishing anything.
/// It is a compile-time value, so an installed copy can never be redirected.
const String _feedOverride =
    String.fromEnvironment('COUNTERBASE_UPDATE_FEED', defaultValue: '');
const String _releasesApi =
    'https://api.github.com/repos/JohnHika/Jawaki-pos/releases?per_page=30';
const String desktopInstallerAssetName = 'Counterbase-Setup.exe';

const String _pendingKey = 'desktop_update_pending';
const String _snoozeKey = 'desktop_update_snooze_until';

/// One Windows release that can be installed over the running copy.
class DesktopUpdateInfo {
  const DesktopUpdateInfo({
    required this.version,
    required this.build,
    required this.tag,
    required this.installerUrl,
    this.notes = '',
    this.publishedAt,
    this.sizeBytes,
    this.sha256,
  });

  /// "1.0.181", the number people see.
  final String version;

  /// "2224", the internal build that decides what is newer.
  final int build;
  final String tag;
  final Uri installerUrl;

  /// The release body as written on the release page.
  final String notes;
  final DateTime? publishedAt;
  final int? sizeBytes;

  /// Lower-case hex digest GitHub computed when the installer was uploaded.
  final String? sha256;

  String get label => 'Counterbase $version';
  String get noticeKey => '$version#$build';
}

enum DesktopUpdateStage { idle, download, verify, install, restart, error }

enum DesktopNoticeKind { available, updated, failed }

/// A short, non-blocking message about the updater (the toast in the corner).
class DesktopUpdateNotice {
  const DesktopUpdateNotice(this.kind, {this.version});

  final DesktopNoticeKind kind;
  final String? version;
}

typedef DesktopReleaseLoader = Future<DesktopUpdateInfo?> Function();
typedef DesktopInstallerDownloader = Future<void> Function(
  Uri url,
  String savePath,
  CancelToken cancelToken,
  void Function(int received, int total) onProgress,
);
typedef DesktopInstallerLauncher = Future<void> Function(
  String installerPath,
  List<String> arguments,
);

/// Whether [raw] is the installer of a release of this app, nothing else.
bool isTrustedInstallerUrl(String raw, {String? tag, Uri? feedOverride}) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.userInfo.isNotEmpty) return false;
  if (feedOverride != null &&
      uri.scheme == feedOverride.scheme &&
      uri.host == feedOverride.host &&
      uri.port == feedOverride.port) {
    return true;
  }
  if (uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  final s = uri.pathSegments;
  return s.length == 6 &&
      s[0] == 'JohnHika' &&
      s[1] == 'Jawaki-pos' &&
      s[2] == 'releases' &&
      s[3] == 'download' &&
      s[4].isNotEmpty &&
      (tag == null || s[4] == tag) &&
      s[5] == desktopInstallerAssetName;
}

/// The newest production release that carries a Windows installer.
///
/// Releases made for phones only have no installer and are skipped, so the
/// computer stays on its build until a release that includes it comes out.
DesktopUpdateInfo? pickLatestDesktopRelease(
  Object? payload, {
  Uri? feedOverride,
}) {
  if (payload is! List) return null;
  DesktopUpdateInfo? best;
  for (final release in payload) {
    if (release is! Map ||
        release['draft'] == true ||
        release['prerelease'] == true) {
      continue;
    }
    final tag = release['tag_name']?.toString().trim() ?? '';
    final match = RegExp(r'^v?(\d+\.\d+\.\d+)[-+](\d+)$').firstMatch(tag);
    if (match == null) continue;
    final build = int.parse(match.group(2)!);

    final assets = release['assets'];
    if (assets is! List) continue;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name']?.toString() ?? '';
      if (name.toLowerCase() != desktopInstallerAssetName.toLowerCase()) {
        continue;
      }
      final url = asset['browser_download_url']?.toString() ?? '';
      if (!isTrustedInstallerUrl(url, tag: tag, feedOverride: feedOverride)) {
        continue;
      }
      final digest = asset['digest']?.toString().trim().toLowerCase() ?? '';
      final sha = digest.startsWith('sha256:') && digest.length == 71
          ? digest.substring(7)
          : null;
      final size = asset['size'];
      final candidate = DesktopUpdateInfo(
        version: match.group(1)!,
        build: build,
        tag: tag,
        installerUrl: Uri.parse(url),
        notes: release['body']?.toString().trim() ?? '',
        publishedAt: DateTime.tryParse(release['published_at']?.toString() ?? ''),
        sizeBytes: size is int && size > 0 ? size : null,
        sha256: sha,
      );
      if (best == null || candidate.build > best.build) best = candidate;
      break;
    }
  }
  return best;
}

/// Updates Counterbase on Windows: finds a newer release, downloads its
/// installer, checks it, hands over to it and reopens the app.
///
/// The phone app is updated by [UpdateCheckService]; this class only does the
/// computer. It never touches the shop's data, which lives outside the
/// install folder.
class DesktopUpdateService extends ChangeNotifier {
  DesktopUpdateService({
    Dio? dio,
    DesktopReleaseLoader? releaseLoader,
    DesktopInstallerDownloader? downloader,
    DesktopInstallerLauncher? launchInstaller,
    Future<void> Function()? exitApp,
    Future<PackageInfo> Function()? packageInfo,
    Future<Directory> Function()? workDirectory,
    DateTime Function()? clock,
    bool? supported,
    Duration restartPause = const Duration(milliseconds: 1600),
  })  : _dio = dio,
        _releaseLoader = releaseLoader,
        _downloader = downloader,
        _launchInstaller = launchInstaller,
        _exitApp = exitApp,
        _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
        _workDirectory = workDirectory,
        _clock = clock ?? DateTime.now,
        supported = supported ?? (!kIsWeb && Platform.isWindows),
        _restartPause = restartPause;

  /// False everywhere but Windows, where nothing here does anything.
  final bool supported;

  static const Duration checkEvery = Duration(hours: 6);
  static const Duration snoozeFor = Duration(hours: 24);
  static const Duration _minGapBetweenChecks = Duration(minutes: 2);

  final Dio? _dio;
  final DesktopReleaseLoader? _releaseLoader;
  final DesktopInstallerDownloader? _downloader;
  final DesktopInstallerLauncher? _launchInstaller;
  final Future<void> Function()? _exitApp;
  final Future<PackageInfo> Function() _packageInfo;
  final Future<Directory> Function()? _workDirectory;
  final DateTime Function() _clock;
  final Duration _restartPause;

  Timer? _timer;
  Timer? _firstCheck;
  bool _disposed = false;

  // What is installed.
  String? _currentVersion;
  int? _currentBuild;

  // The last look at the release list.
  bool _checking = false;
  Completer<void>? _checkDone;
  bool _hasChecked = false;
  DateTime? _lastCheckedAt;
  DesktopUpdateInfo? _available;
  String? _checkError;

  // The install in progress.
  DesktopUpdateStage _stage = DesktopUpdateStage.idle;
  int _receivedBytes = 0;
  int? _totalBytes;
  String? _applyError;
  CancelToken? _cancelToken;

  // Window and corner notices.
  bool _overlayOpen = false;
  DesktopUpdateNotice? _notice;
  String? _lastNoticeKey;
  DateTime? _snoozeUntil;
  String? _updatedTo;
  bool _previousAttemptFailed = false;

  String? get currentVersion => _currentVersion;
  int? get currentBuild => _currentBuild;
  bool get checking => _checking;
  bool get hasChecked => _hasChecked;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  DesktopUpdateInfo? get available => _available;
  bool get updateAvailable => _available != null;
  String? get checkError => _checkError;

  DesktopUpdateStage get stage => _stage;
  bool get applying =>
      _stage != DesktopUpdateStage.idle && _stage != DesktopUpdateStage.error;
  String? get applyError => _applyError;
  int get receivedBytes => _receivedBytes;
  int? get totalBytes => _totalBytes;

  /// 0 to 1 while a size is known, null while it is not.
  double? get progress {
    switch (_stage) {
      case DesktopUpdateStage.download:
        final total = _totalBytes;
        if (total == null || total <= 0) return null;
        return (_receivedBytes / total).clamp(0.0, 1.0);
      case DesktopUpdateStage.verify:
      case DesktopUpdateStage.install:
      case DesktopUpdateStage.restart:
        return 1.0;
      case DesktopUpdateStage.idle:
      case DesktopUpdateStage.error:
        return null;
    }
  }

  bool get overlayOpen => _overlayOpen;
  DesktopUpdateNotice? get notice => _notice;

  // ── Starting up ────────────────────────────────────────────────────────

  /// Reads what is installed and works out how the last update went. Safe to
  /// call more than once.
  Future<void> initialize() async {
    if (!supported) return;
    try {
      await _resolveCurrent();
      final prefs = await SharedPreferences.getInstance();
      final snooze = prefs.getInt(_snoozeKey);
      if (snooze != null) {
        _snoozeUntil = DateTime.fromMillisecondsSinceEpoch(snooze);
      }
      final pending = prefs.getString(_pendingKey);
      if (pending != null) {
        await prefs.remove(_pendingKey);
        final parts = pending.split('|');
        final pendingBuild = int.tryParse(parts.first);
        final pendingVersion = parts.length > 1 ? parts[1] : null;
        if (pendingBuild != null && (_currentBuild ?? 0) >= pendingBuild) {
          _updatedTo = pendingVersion ?? _currentVersion;
          _notice = DesktopUpdateNotice(DesktopNoticeKind.updated,
              version: _updatedTo);
        } else if (pendingBuild != null) {
          _previousAttemptFailed = true;
          _notice = const DesktopUpdateNotice(DesktopNoticeKind.failed);
        }
        _notify();
      }
    } catch (error) {
      if (!kReleaseMode) debugPrint('[DesktopUpdate] initialize: $error');
    }
  }

  /// Looks soon after launch, then every few hours while the app stays open.
  void startBackgroundChecks({
    Duration firstDelay = const Duration(seconds: 20),
  }) {
    if (!supported) return;
    _firstCheck?.cancel();
    _timer?.cancel();
    _firstCheck = Timer(firstDelay, () => unawaited(checkForUpdates()));
    _timer = Timer.periodic(checkEvery, (_) => unawaited(checkForUpdates()));
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _firstCheck?.cancel();
    _cancelToken?.cancel('disposed');
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Looking for an update ──────────────────────────────────────────────

  Future<void> checkForUpdates({bool force = false}) async {
    if (!supported || applying) return;
    if (_checking) {
      await _checkDone?.future;
      return;
    }
    final last = _lastCheckedAt;
    if (!force &&
        last != null &&
        _clock().difference(last) < _minGapBetweenChecks) {
      return;
    }

    _checking = true;
    _checkError = null;
    final done = Completer<void>();
    _checkDone = done;
    _notify();
    try {
      await _resolveCurrent();
      final latest = await (_releaseLoader ?? _loadFromFeed)();
      _lastCheckedAt = _clock();
      _hasChecked = true;
      if (latest != null && _isNewer(latest)) {
        _available = latest;
        _raiseAvailableNotice(latest);
      } else {
        _available = null;
        if (_notice?.kind == DesktopNoticeKind.available) _notice = null;
      }
    } catch (error) {
      _hasChecked = true;
      _lastCheckedAt = _clock();
      _checkError = _friendlyCheckError(error);
      if (!kReleaseMode) debugPrint('[DesktopUpdate] check failed: $error');
    } finally {
      _checking = false;
      if (!done.isCompleted) done.complete();
      _notify();
    }
  }

  bool _isNewer(DesktopUpdateInfo latest) {
    final build = _currentBuild;
    if (build != null) return latest.build > build;
    return isNewerAppVersion(latest.version, _currentVersion ?? '0.0.0');
  }

  void _raiseAvailableNotice(DesktopUpdateInfo latest) {
    if (_lastNoticeKey == latest.noticeKey) return;
    _lastNoticeKey = latest.noticeKey;
    final snoozed = _snoozeUntil;
    if (snoozed != null && _clock().isBefore(snoozed)) return;
    if (_overlayOpen || applying) return;
    _notice = DesktopUpdateNotice(DesktopNoticeKind.available,
        version: latest.version);
  }

  Future<DesktopUpdateInfo?> _loadFromFeed() async {
    final override =
        _feedOverride.isEmpty ? null : Uri.tryParse(_feedOverride);
    final uri = override ?? Uri.parse(_releasesApi);
    final response = await (_dio ?? _newDio()).getUri<Object?>(
      uri,
      options: Options(
        headers: const {'Accept': 'application/vnd.github+json'},
        responseType: ResponseType.plain,
      ),
    );
    final body = response.data;
    final payload = body is String ? jsonDecode(body) : body;
    return pickLatestDesktopRelease(payload, feedOverride: override);
  }

  Dio _newDio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ));

  Future<void> _resolveCurrent() async {
    if (_currentBuild != null && _currentVersion != null) return;
    final info = await _packageInfo();
    _currentVersion = info.version;
    _currentBuild = int.tryParse(info.buildNumber.trim());
  }

  String _friendlyCheckError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 403 || status == 429) {
        return 'The update server is busy right now. Try again in a few minutes.';
      }
    }
    return 'Counterbase couldn’t reach the update server. Check your internet connection and try again.';
  }

  // ── Window and notices ─────────────────────────────────────────────────

  /// Opens the update window. With [recheck] it also looks again, which is
  /// what "Check for updates" in Settings means.
  void openOverlay({bool recheck = false}) {
    if (!supported) return;
    _overlayOpen = true;
    _notice = null;
    _notify();
    if (recheck) {
      unawaited(checkForUpdates(force: true));
    } else if (!_hasChecked && !_checking) {
      unawaited(checkForUpdates());
    }
  }

  /// Closes the window unless an update is being installed. A finished or
  /// failed attempt is forgotten so the next opening starts clean.
  void closeOverlay() {
    if (applying) return;
    if (_stage == DesktopUpdateStage.error) resetApplyState();
    _overlayOpen = false;
    _notify();
  }

  /// "Maybe later" and the close button on the corner notice: stay quiet
  /// about this for a day. The window and Settings still show the update.
  Future<void> snooze() async {
    _notice = null;
    final until = _clock().add(snoozeFor);
    _snoozeUntil = until;
    _notify();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_snoozeKey, until.millisecondsSinceEpoch);
    } catch (_) {
      // A snooze that is not remembered only means the notice shows again.
    }
  }

  void dismissNotice() {
    if (_notice == null) return;
    _notice = null;
    _notify();
  }

  void resetApplyState() {
    if (applying) return;
    _stage = DesktopUpdateStage.idle;
    _applyError = null;
    _receivedBytes = 0;
    _totalBytes = null;
    _notify();
  }

  bool get previousAttemptFailed => _previousAttemptFailed;
  String? get updatedTo => _updatedTo;

  // ── Installing ─────────────────────────────────────────────────────────

  /// Downloads the update, checks it, then closes this copy and lets the
  /// installer replace it. The installer reopens Counterbase when it is done.
  Future<void> startUpdate() async {
    final info = _available;
    if (!supported || info == null || applying) return;

    _applyError = null;
    _receivedBytes = 0;
    _totalBytes = info.sizeBytes;
    _previousAttemptFailed = false;
    _notice = null;
    _stage = DesktopUpdateStage.download;
    _notify();

    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      final file = await _fetchInstaller(info, cancelToken);

      _setStage(DesktopUpdateStage.verify);
      await _verify(file, info);

      _setStage(DesktopUpdateStage.install);
      await _rememberPending(info);

      _setStage(DesktopUpdateStage.restart);
      await Future<void>.delayed(_restartPause);
      await _handOver(file);
      // The installer is running on its own now. Close this copy so it can
      // replace the files; it opens the app again when it finishes.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await (_exitApp ?? _exitWindowsApp)();
    } on _UpdateFailure catch (failure) {
      _fail(failure.message);
    } catch (error) {
      if (error is DioException && CancelToken.isCancel(error)) {
        _stage = DesktopUpdateStage.idle;
        _applyError = null;
        _notify();
      } else {
        if (!kReleaseMode) debugPrint('[DesktopUpdate] failed: $error');
        _fail(_friendlyDownloadError(error));
      }
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
  }

  /// Stops a download in progress. Nothing else can be stopped once the
  /// installer has been handed over.
  void cancelDownload() {
    if (_stage != DesktopUpdateStage.download) return;
    _cancelToken?.cancel('cancelled');
  }

  void _setStage(DesktopUpdateStage stage) {
    _stage = stage;
    _notify();
  }

  void _fail(String message) {
    _stage = DesktopUpdateStage.error;
    _applyError = message;
    _notify();
  }

  Future<File> _fetchInstaller(
    DesktopUpdateInfo info,
    CancelToken cancelToken,
  ) async {
    final dir = await _updateDirectory();
    final target = File(p.join(
        dir.path, 'Counterbase-Setup-${info.version}-${info.build}.exe'));

    // A finished download that is still intact is reused after a retry.
    if (await target.exists() && await _isIntact(target, info, reuse: true)) {
      _receivedBytes = _totalBytes ?? await target.length();
      return target;
    }

    final part = File('${target.path}.part');
    if (await part.exists()) await part.delete();
    await (_downloader ?? _downloadWithDio)(
      info.installerUrl,
      part.path,
      cancelToken,
      (received, total) {
        _receivedBytes = received;
        if (total > 0) _totalBytes = total;
        _notify();
      },
    );
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
    return target;
  }

  Future<void> _downloadWithDio(
    Uri url,
    String savePath,
    CancelToken cancelToken,
    void Function(int received, int total) onProgress,
  ) async {
    await (_dio ?? _newDio()).downloadUri(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
      options: Options(
        receiveTimeout: const Duration(minutes: 2),
        headers: const {'Accept': 'application/octet-stream'},
      ),
    );
  }

  /// Whether [file] is the installer the release lists. [reuse] is for a
  /// download left from an earlier try: with nothing to compare against it is
  /// not trusted, whereas a fresh download from the release page is.
  Future<bool> _isIntact(
    File file,
    DesktopUpdateInfo info, {
    required bool reuse,
  }) async {
    final size = info.sizeBytes;
    if (size != null && await file.length() != size) return false;
    final expected = info.sha256;
    if (expected != null) {
      final actual = (await sha256.bind(file.openRead()).first).toString();
      return actual == expected;
    }
    return !reuse || size != null;
  }

  Future<void> _verify(File file, DesktopUpdateInfo info) async {
    if (!await _isIntact(file, info, reuse: false)) {
      try {
        await file.delete();
      } catch (_) {}
      throw const _UpdateFailure(
          'The download didn’t arrive intact, so it was thrown away. Try again and Counterbase will fetch it fresh.');
    }
  }

  Future<void> _rememberPending(DesktopUpdateInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingKey, '${info.build}|${info.version}');
    } catch (_) {
      // Only the "updated" confirmation after relaunch depends on this.
    }
  }

  Future<void> _handOver(File installer) async {
    final dir = installer.parent.path;
    final args = <String>[
      // The installer's own small progress window stays visible: it is the
      // "updater takes over" moment, so the screen is never silently empty.
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/NOCANCEL',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      // Read by installer.iss: open Counterbase again once files are in.
      '/RELAUNCH=1',
      '/LOG=${p.join(dir, 'update.log')}',
    ];
    try {
      await (_launchInstaller ?? _launchDetached)(installer.path, args);
    } catch (error) {
      if (!kReleaseMode) debugPrint('[DesktopUpdate] launch failed: $error');
      throw const _UpdateFailure(
          'Windows wouldn’t open the update. Try again, or download the newest version from archeaxon.com/download/counterbase/windows.');
    }
  }

  static Future<void> _launchDetached(String path, List<String> args) async {
    await Process.start(path, args, mode: ProcessStartMode.detached);
  }

  Future<void> _exitWindowsApp() async {
    // A clean quit lets the window and the shop's database close properly.
    // If it is somehow refused, end the process so the installer is not left
    // waiting on a copy that never goes away.
    Timer(const Duration(seconds: 5), () => exit(0));
    await ServicesBinding.instance.exitApplication(ui.AppExitType.required);
  }

  Future<Directory> _updateDirectory() async {
    final base = await (_workDirectory ?? getTemporaryDirectory)();
    final dir = Directory(p.join(base.path, 'counterbase-update'));
    await dir.create(recursive: true);
    await _clearOldInstallers(dir);
    return dir;
  }

  Future<void> _clearOldInstallers(Directory dir) async {
    final keep = _available == null
        ? null
        : 'Counterbase-Setup-${_available!.version}-${_available!.build}.exe';
    try {
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final name = p.basename(entry.path);
        if (name == keep || name == 'update.log') continue;
        if (name.startsWith('Counterbase-Setup-')) {
          await entry.delete();
        }
      }
    } catch (_) {
      // Leftovers cost disk space, nothing more.
    }
  }

  String _friendlyDownloadError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 404) {
        return 'The update file isn’t available yet. Try again in a few minutes.';
      }
      if (status != null && status >= 500) {
        return 'The update server is having a problem. Try again shortly.';
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Counterbase couldn’t reach the update server. Check your internet connection and try again.';
      }
    }
    if (error is FileSystemException) {
      return 'Counterbase couldn’t save the update on this computer. Free up some space and try again.';
    }
    return 'The update didn’t download. Check your internet connection and try again.';
  }
}

class _UpdateFailure implements Exception {
  const _UpdateFailure(this.message);
  final String message;
}
