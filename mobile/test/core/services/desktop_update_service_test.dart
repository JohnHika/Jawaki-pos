import 'dart:async';
import 'dart:io';

import 'package:axon_pos/core/services/desktop_update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _repo = 'https://github.com/JohnHika/Jawaki-pos/releases/download';

Map<String, dynamic> _release(
  String tag, {
  bool installer = true,
  bool draft = false,
  bool prerelease = false,
  String? url,
  String? digest,
  int size = 1024,
  String body = '- Faster checkout',
}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'body': body,
      'published_at': '2026-11-09T09:37:31Z',
      'assets': [
        {
          'name': 'app-release.apk',
          'browser_download_url': '$_repo/$tag/app-release.apk',
          'size': 64000000,
        },
        if (installer)
          {
            'name': 'Counterbase-Setup.exe',
            'browser_download_url': url ?? '$_repo/$tag/Counterbase-Setup.exe',
            'size': size,
            if (digest != null) 'digest': digest,
          },
      ],
    };

void _runningBuild(int build, {String version = '1.0.180'}) {
  PackageInfo.setMockInitialValues(
    appName: 'Counterbase',
    packageName: 'com.archeaxon.axonpos',
    version: version,
    buildNumber: '$build',
    buildSignature: '',
  );
}

DesktopUpdateInfo _info({
  int build = 2224,
  String version = '1.0.181',
  int? size,
  String? sha256,
}) =>
    DesktopUpdateInfo(
      version: version,
      build: build,
      tag: 'v$version-$build',
      installerUrl:
          Uri.parse('$_repo/v$version-$build/Counterbase-Setup.exe'),
      notes: '- Faster checkout',
      sizeBytes: size,
      sha256: sha256,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory work;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _runningBuild(2223);
    work = await Directory.systemTemp.createTemp('cb-update-test');
  });

  tearDown(() async {
    if (await work.exists()) await work.delete(recursive: true);
  });

  group('trusted installer address', () {
    test('accepts this app\'s release installer only', () {
      expect(
          isTrustedInstallerUrl('$_repo/v1.0.181-2224/Counterbase-Setup.exe',
              tag: 'v1.0.181-2224'),
          isTrue);
      // Another repository, another host, another file, another tag.
      expect(
          isTrustedInstallerUrl(
              'https://github.com/someone/else/releases/download/v1/Counterbase-Setup.exe'),
          isFalse);
      expect(
          isTrustedInstallerUrl(
              'https://evil.example/JohnHika/Jawaki-pos/releases/download/v1/Counterbase-Setup.exe'),
          isFalse);
      expect(isTrustedInstallerUrl('$_repo/v1.0.181-2224/app-release.apk'),
          isFalse);
      expect(
          isTrustedInstallerUrl('$_repo/v9.9.9-9999/Counterbase-Setup.exe',
              tag: 'v1.0.181-2224'),
          isFalse);
      expect(
          isTrustedInstallerUrl(
              'http://github.com/JohnHika/Jawaki-pos/releases/download/v1/Counterbase-Setup.exe'),
          isFalse);
      expect(isTrustedInstallerUrl('$_repo/v1/Counterbase-Setup.exe?x=1'),
          isFalse);
    });

    test('a rehearsal feed may serve from its own address', () {
      final feed = Uri.parse('http://127.0.0.1:8099/releases.json');
      expect(
          isTrustedInstallerUrl('http://127.0.0.1:8099/Counterbase-Setup.exe',
              feedOverride: feed),
          isTrue);
      expect(
          isTrustedInstallerUrl('http://127.0.0.1:9999/Counterbase-Setup.exe',
              feedOverride: feed),
          isFalse);
    });
  });

  group('choosing the release', () {
    test('takes the newest release that has an installer', () {
      final picked = pickLatestDesktopRelease([
        _release('v1.0.182-2225', installer: false), // phone only
        _release('v1.0.181-2224'),
        _release('v1.0.180-2223'),
      ]);
      expect(picked?.build, 2224);
      expect(picked?.version, '1.0.181');
      expect(picked?.label, 'Counterbase 1.0.181');
    });

    test('skips drafts, previews and malformed tags', () {
      final picked = pickLatestDesktopRelease([
        _release('v1.0.185-2230', draft: true),
        _release('v1.0.184-2229', prerelease: true),
        _release('nightly'),
        _release('v1.0.180-2223'),
      ]);
      expect(picked?.build, 2223);
    });

    test('ignores an installer from the wrong place', () {
      final picked = pickLatestDesktopRelease([
        _release('v1.0.181-2224',
            url:
                'https://github.com/other/repo/releases/download/v1.0.181-2224/Counterbase-Setup.exe'),
      ]);
      expect(picked, isNull);
    });

    test('reads the size and the checksum GitHub published', () {
      final sha = 'a' * 64;
      final picked = pickLatestDesktopRelease([
        _release('v1.0.181-2224', digest: 'sha256:$sha', size: 19777895),
      ]);
      expect(picked?.sha256, sha);
      expect(picked?.sizeBytes, 19777895);
      expect(picked?.installerUrl.pathSegments.last, 'Counterbase-Setup.exe');
    });

    test('a digest of another kind is not mistaken for sha256', () {
      final picked = pickLatestDesktopRelease([
        _release('v1.0.181-2224', digest: 'md5:abcd'),
      ]);
      expect(picked?.sha256, isNull);
    });

    test('anything that is not a release list finds nothing', () {
      expect(pickLatestDesktopRelease(null), isNull);
      expect(pickLatestDesktopRelease({'message': 'rate limited'}), isNull);
      expect(pickLatestDesktopRelease(<dynamic>[]), isNull);
    });
  });

  group('looking for an update', () {
    DesktopUpdateService service(
      DesktopReleaseLoader loader, {
      bool supported = true,
      DateTime Function()? clock,
    }) =>
        DesktopUpdateService(
          releaseLoader: loader,
          supported: supported,
          clock: clock,
          workDirectory: () async => work,
        );

    test('a newer build is offered and announced once', () async {
      final s = service(() async => _info());
      await s.checkForUpdates();

      expect(s.hasChecked, isTrue);
      expect(s.updateAvailable, isTrue);
      expect(s.available?.build, 2224);
      expect(s.currentVersion, '1.0.180');
      expect(s.notice?.kind, DesktopNoticeKind.available);
      expect(s.notice?.version, '1.0.181');

      s.dismissNotice();
      await s.checkForUpdates(force: true);
      expect(s.notice, isNull, reason: 'the same update is not announced twice');
      expect(s.updateAvailable, isTrue);
    });

    test('the build already installed is not an update', () async {
      final s = service(() async => _info(build: 2223, version: '1.0.180'));
      await s.checkForUpdates();
      expect(s.hasChecked, isTrue);
      expect(s.updateAvailable, isFalse);
      expect(s.notice, isNull);
      expect(s.lastCheckedAt, isNotNull);
    });

    test('an older build is not an update', () async {
      final s = service(() async => _info(build: 2100, version: '1.0.90'));
      await s.checkForUpdates();
      expect(s.updateAvailable, isFalse);
    });

    test('no release with an installer means nothing to do', () async {
      final s = service(() async => null);
      await s.checkForUpdates();
      expect(s.updateAvailable, isFalse);
      expect(s.checkError, isNull);
    });

    test('an unreachable server is reported, not thrown', () async {
      final s = service(() async => throw DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionError,
          ));
      await s.checkForUpdates();
      expect(s.hasChecked, isTrue);
      expect(s.checkError, contains('couldn’t reach the update server'));
      expect(s.updateAvailable, isFalse);
    });

    test('a refused request says the server is busy', () async {
      final s = service(() async => throw DioException(
            requestOptions: RequestOptions(path: '/'),
            response: Response(
                requestOptions: RequestOptions(path: '/'), statusCode: 403),
            type: DioExceptionType.badResponse,
          ));
      await s.checkForUpdates();
      expect(s.checkError, contains('busy'));
    });

    test('a failed check keeps an update found earlier out of the way',
        () async {
      var fail = false;
      final s = service(() async {
        if (fail) throw StateError('offline');
        return _info();
      });
      await s.checkForUpdates();
      expect(s.updateAvailable, isTrue);
      fail = true;
      await s.checkForUpdates(force: true);
      expect(s.checkError, isNotNull);
      expect(s.available, isNotNull,
          reason: 'what was found stays available while offline');
    });

    test('checks closer than two minutes apart reuse the last answer',
        () async {
      var calls = 0;
      var now = DateTime(2026, 11, 9, 12);
      final s = service(() async {
        calls++;
        return _info();
      }, clock: () => now);
      await s.checkForUpdates();
      now = now.add(const Duration(seconds: 30));
      await s.checkForUpdates();
      expect(calls, 1);
      await s.checkForUpdates(force: true);
      expect(calls, 2);
      now = now.add(const Duration(minutes: 3));
      await s.checkForUpdates();
      expect(calls, 3);
    });

    test('two checks at once make one request', () async {
      var calls = 0;
      final gate = Completer<void>();
      final s = service(() async {
        calls++;
        await gate.future;
        return _info();
      });
      final a = s.checkForUpdates();
      final b = s.checkForUpdates();
      expect(s.checking, isTrue);
      gate.complete();
      await Future.wait([a, b]);
      expect(calls, 1);
      expect(s.checking, isFalse);
    });

    test('a snoozed update is not announced but is still offered', () async {
      final now = DateTime(2026, 11, 9, 12);
      final s = service(() async => _info(), clock: () => now);
      await s.snooze();
      await s.checkForUpdates();
      expect(s.updateAvailable, isTrue);
      expect(s.notice, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('desktop_update_snooze_until'),
          now.add(DesktopUpdateService.snoozeFor).millisecondsSinceEpoch);
    });

    test('anything but Windows does nothing at all', () async {
      var calls = 0;
      final s = service(() async {
        calls++;
        return _info();
      }, supported: false);
      await s.initialize();
      await s.checkForUpdates();
      s.openOverlay();
      await s.startUpdate();
      expect(calls, 0);
      expect(s.overlayOpen, isFalse);
      expect(s.hasChecked, isFalse);
    });

    test('opening the window looks for an update, once', () async {
      var calls = 0;
      final s = service(() async {
        calls++;
        return _info();
      });
      s.openOverlay();
      await Future<void>.delayed(Duration.zero);
      await s.checkForUpdates();
      expect(s.overlayOpen, isTrue);
      expect(calls, 1);
      s.closeOverlay();
      expect(s.overlayOpen, isFalse);

      s.openOverlay(recheck: true);
      await Future<void>.delayed(Duration.zero);
      await s.checkForUpdates();
      expect(calls, 2);
    });
  });

  group('installing', () {
    List<int> installerBytes() => List<int>.generate(4096, (i) => i % 251);

    DesktopUpdateService build({
      required DesktopInstallerDownloader downloader,
      required List<(String, List<String>)> launched,
      required List<String> events,
      DesktopInstallerLauncher? launcher,
      DesktopUpdateInfo? info,
    }) {
      final bytes = installerBytes();
      final target = info ??
          _info(size: bytes.length, sha256: sha256.convert(bytes).toString());
      return DesktopUpdateService(
        supported: true,
        releaseLoader: () async => target,
        downloader: downloader,
        launchInstaller: launcher ??
            (path, args) async {
              events.add('launch');
              launched.add((path, args));
            },
        exitApp: () async => events.add('exit'),
        workDirectory: () async => work,
        restartPause: Duration.zero,
      );
    }

    Future<void> fakeDownload(
      Uri url,
      String savePath,
      CancelToken token,
      void Function(int, int) onProgress,
    ) async {
      final bytes = installerBytes();
      await File(savePath).writeAsBytes(bytes);
      onProgress(bytes.length ~/ 2, bytes.length);
      onProgress(bytes.length, bytes.length);
    }

    test('downloads, checks, hands over to the installer, then closes',
        () async {
      final launched = <(String, List<String>)>[];
      final events = <String>[];
      final s = build(
          downloader: fakeDownload, launched: launched, events: events);
      await s.checkForUpdates();
      final stages = <DesktopUpdateStage>[];
      s.addListener(() {
        if (stages.isEmpty || stages.last != s.stage) stages.add(s.stage);
      });

      await s.startUpdate();

      expect(stages, [
        DesktopUpdateStage.download,
        DesktopUpdateStage.verify,
        DesktopUpdateStage.install,
        DesktopUpdateStage.restart,
      ]);
      expect(launched, hasLength(1));
      final (path, args) = launched.single;
      expect(p.basename(path), 'Counterbase-Setup-1.0.181-2224.exe');
      expect(await File(path).exists(), isTrue);
      expect(args, containsAll(['/SILENT', '/NOCANCEL', '/NORESTART']));
      expect(args, contains('/RELAUNCH=1'));
      expect(args.any((a) => a.startsWith('/LOG=')), isTrue);
      // The app closes after the installer has been started, not before.
      expect(events, ['launch', 'exit']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('desktop_update_pending'), '2224|1.0.181');
    });

    test('reports download progress', () async {
      final seen = <double?>[];
      final s = build(
        downloader: fakeDownload,
        launched: [],
        events: [],
      );
      s.addListener(() {
        if (s.stage == DesktopUpdateStage.download) seen.add(s.progress);
      });
      await s.checkForUpdates();
      await s.startUpdate();
      expect(seen, contains(0.5));
      expect(seen.where((v) => v == 1.0), isNotEmpty);
    });

    test('a download that does not match the checksum is thrown away',
        () async {
      final launched = <(String, List<String>)>[];
      final s = build(
        downloader: (url, path, token, progress) async {
          await File(path).writeAsBytes(List<int>.filled(4096, 7));
        },
        launched: launched,
        events: [],
      );
      await s.checkForUpdates();
      await s.startUpdate();

      expect(s.stage, DesktopUpdateStage.error);
      expect(s.applyError, contains('didn’t arrive intact'));
      expect(launched, isEmpty);
      final dir = Directory(p.join(work.path, 'counterbase-update'));
      expect(
          dir.listSync().whereType<File>().where((f) => f.path.endsWith('.exe')),
          isEmpty);
    });

    test('a truncated download fails the size check', () async {
      final s = build(
        downloader: (url, path, token, progress) async {
          await File(path).writeAsBytes(installerBytes().sublist(0, 100));
        },
        launched: [],
        events: [],
      );
      await s.checkForUpdates();
      await s.startUpdate();
      expect(s.stage, DesktopUpdateStage.error);
    });

    test('Try again after a failure works and clears the error', () async {
      var attempt = 0;
      final launched = <(String, List<String>)>[];
      final s = build(
        downloader: (url, path, token, progress) async {
          attempt++;
          if (attempt == 1) {
            throw DioException(
              requestOptions: RequestOptions(path: '/'),
              type: DioExceptionType.connectionError,
            );
          }
          await fakeDownload(url, path, token, progress);
        },
        launched: launched,
        events: [],
      );
      await s.checkForUpdates();
      await s.startUpdate();
      expect(s.stage, DesktopUpdateStage.error);
      expect(s.applyError, contains('couldn’t reach the update server'));

      s.resetApplyState();
      expect(s.stage, DesktopUpdateStage.idle);
      expect(s.applyError, isNull);
      await s.startUpdate();
      expect(launched, hasLength(1));
    });

    test('a missing file on the server is explained', () async {
      final s = build(
        downloader: (url, path, token, progress) async => throw DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response(
              requestOptions: RequestOptions(path: '/'), statusCode: 404),
          type: DioExceptionType.badResponse,
        ),
        launched: [],
        events: [],
      );
      await s.checkForUpdates();
      await s.startUpdate();
      expect(s.applyError, contains('isn’t available yet'));
    });

    test('an installer Windows will not open ends in a clear error', () async {
      final events = <String>[];
      final s = build(
        downloader: fakeDownload,
        launched: [],
        events: events,
        launcher: (path, args) async =>
            throw const ProcessException('x', [], 'blocked', 5),
      );
      await s.checkForUpdates();
      await s.startUpdate();
      expect(s.stage, DesktopUpdateStage.error);
      expect(s.applyError, contains('Windows wouldn’t open the update'));
      expect(events, isNot(contains('exit')),
          reason: 'the app stays open when the installer did not start');
    });

    test('cancelling a download goes back to the start without an error',
        () async {
      final s = build(
        downloader: (url, path, token, progress) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          // Waits until cancelled, like a real transfer would.
          final done = Completer<void>();
          token.whenCancel.then((e) => done.completeError(e));
          await done.future;
        },
        launched: [],
        events: [],
      );
      await s.checkForUpdates();
      final run = s.startUpdate();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(s.stage, DesktopUpdateStage.download);
      s.cancelDownload();
      await run;
      expect(s.stage, DesktopUpdateStage.idle);
      expect(s.applyError, isNull);
      expect(s.updateAvailable, isTrue);
    });

    test('the window cannot be closed while installing', () async {
      final gate = Completer<void>();
      final s = build(
        downloader: (url, path, token, progress) async {
          await gate.future;
          await fakeDownload(url, path, token, progress);
        },
        launched: [],
        events: [],
      );
      await s.checkForUpdates();
      s.openOverlay();
      final run = s.startUpdate();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(s.applying, isTrue);
      s.closeOverlay();
      expect(s.overlayOpen, isTrue);
      gate.complete();
      await run;
    });

    test('a finished download is reused on the next try', () async {
      var downloads = 0;
      final s = build(
        downloader: (url, path, token, progress) async {
          downloads++;
          await fakeDownload(url, path, token, progress);
        },
        launched: [],
        events: [],
        launcher: (path, args) async =>
            throw const ProcessException('x', [], 'blocked', 5),
      );
      await s.checkForUpdates();
      await s.startUpdate(); // downloads, installer refused
      s.resetApplyState();
      await s.startUpdate(); // reuses the file
      expect(downloads, 1);
    });
  });

  group('after an update', () {
    DesktopUpdateService fresh() => DesktopUpdateService(
          supported: true,
          releaseLoader: () async => null,
          workDirectory: () async => work,
        );

    test('the new build confirms it worked', () async {
      SharedPreferences.setMockInitialValues(
          {'desktop_update_pending': '2223|1.0.180'});
      final s = fresh();
      await s.initialize();
      expect(s.notice?.kind, DesktopNoticeKind.updated);
      expect(s.updatedTo, '1.0.180');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('desktop_update_pending'), isNull);
    });

    test('the old build still running means the update did not finish',
        () async {
      SharedPreferences.setMockInitialValues(
          {'desktop_update_pending': '2224|1.0.181'});
      final s = fresh();
      await s.initialize();
      expect(s.notice?.kind, DesktopNoticeKind.failed);
      expect(s.previousAttemptFailed, isTrue);
    });

    test('nothing pending means nothing to say', () async {
      final s = fresh();
      await s.initialize();
      expect(s.notice, isNull);
    });
  });
}
