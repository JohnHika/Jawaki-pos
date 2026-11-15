import 'dart:convert';
import 'dart:io';

import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/core/widgets/optional_update_prompt_host.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// These use the real [UpdateCheckService] state machine, not a fake that
/// pretends to open the update screen, because the bug customers hit was in
/// the wiring between the service and the screen: "Update now" changed the
/// service and nothing was ever drawn.
void main() {
  group('update screen wiring', () {
    testWidgets('Update now from Settings opens the update screen and Not now closes it',
        (tester) async {
      final service = _Service();
      await _pumpHost(tester, service);

      service.beginOptionalUpdateNow(_update());
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Download & install update'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(find.text('Download & install update'), findsNothing);
      expect(find.text('App content'), findsOneWidget);
    });

    testWidgets('the screen redraws itself while a download runs and hides Not now',
        (tester) async {
      final service = _Service();
      await _pumpHost(tester, service);
      service.beginOptionalUpdateNow(_update());
      await tester.pumpAndSettle();

      service.setDownload(busy: true, progress: 0.25, downloaded: 16000000, total: 64000000);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Updating Counterbase'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('Not now'), findsNothing);

      service.setDownload(busy: true, progress: 0.75, downloaded: 48000000, total: 64000000);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('75%'), findsOneWidget);

      // The busy animation never settles; drop the tree so no timer outlives it.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a failed update offers retry and the website download',
        (tester) async {
      final service = _Service();
      await _pumpHost(tester, service);
      service.beginOptionalUpdateNow(_update());
      await tester.pumpAndSettle();

      service.setError('Could not download the update. Check your internet and tap retry.');
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpAndSettle();

      expect(find.text('Retry download'), findsOneWidget);
      expect(find.text('Download from the website instead'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('a required update cannot be dismissed', (tester) async {
      final service = _Service()..requireNow(_update());
      await _pumpHost(tester, service);
      await tester.pumpAndSettle();

      expect(find.text('Update Required'), findsOneWidget);
      expect(find.text('Not now'), findsNothing);
      service.dismissOptionalGate();
      await tester.pumpAndSettle();
      expect(find.text('Update Required'), findsOneWidget);
    });
  });

  group('downloaded file check', () {
    late Directory dir;
    late File apk;
    late String sha;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('update_check_test');
      apk = File('${dir.path}/app-release.apk');
      await apk.writeAsBytes(utf8.encode('pretend this is an apk' * 100));
      sha = sha256.convert(await apk.readAsBytes()).toString();
    });

    tearDown(() async => dir.delete(recursive: true));

    final service = _Service();

    test('accepts the file the release built', () async {
      final update = _update(sha: sha, size: await apk.length());
      expect(await service.matchesManifestForTest(apk, update), isTrue);
    });

    test('accepts a manifest from before checksums existed', () async {
      expect(await service.matchesManifestForTest(apk, _update()), isTrue);
    });

    test('rejects a file that was cut short', () async {
      final update = _update(sha: sha, size: await apk.length() + 10);
      expect(await service.matchesManifestForTest(apk, update), isFalse);
    });

    test('rejects a file with the right size but different content', () async {
      final update = _update(sha: 'a' * 64, size: await apk.length());
      expect(await service.matchesManifestForTest(apk, update), isFalse);
    });

    test('rejects an empty file', () async {
      final empty = File('${dir.path}/empty.apk')..writeAsBytesSync(<int>[]);
      expect(await service.matchesManifestForTest(empty, _update()), isFalse);
    });
  });

  test('the manifest checksum and size are read, in either letter case', () {
    final info = AppUpdateInfo.fromJson({
      'latestVersion': '1.0.223',
      'buildNumber': 2226,
      'minSupportedVersion': '0.0.0',
      'apkUrl': 'https://github.com/JohnHika/Jawaki-pos/releases/download/v1.0.183-2226/app-release.apk',
      'releaseNotes': 'x',
      'apkSha256': 'ABCDEF${'0' * 58}',
      'apkSizeBytes': 64254033,
    });
    expect(info.apkSha256, 'abcdef${'0' * 58}');
    expect(info.apkSizeBytes, 64254033);
  });
}

Future<void> _pumpHost(WidgetTester tester, UpdateCheckService service) {
  // Tall enough that every button is on screen and tappable.
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => OptionalUpdatePromptHost(
        updateService: service,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(body: Center(child: Text('App content'))),
    ),
  );
}

AppUpdateInfo _update({String? sha, int? size}) => AppUpdateInfo(
      latestVersion: '1.0.223',
      releaseName: 'Counterbase 1.0.183',
      buildNumber: 2226,
      minSupportedVersion: '0.0.0',
      forceUpdate: false,
      apkUrl: 'https://github.com/JohnHika/Jawaki-pos/releases/download/v1.0.183-2226/app-release.apk',
      releaseNotes: 'Updates now install from the phone.',
      apkSha256: sha,
      apkSizeBytes: size,
    );

/// The real service with its network-facing state steered by the test.
class _Service extends UpdateCheckService {
  _Service() : super(apiClient: ApiClient(Dio()));

  bool _busy = false;
  double? _progress;
  int? _downloaded;
  int? _total;
  String? _error;
  AppUpdateInfo? _required;

  void requireNow(AppUpdateInfo update) => _required = update;

  void setDownload({
    required bool busy,
    double? progress,
    int? downloaded,
    int? total,
  }) {
    _busy = busy;
    _progress = progress;
    _downloaded = downloaded;
    _total = total;
    notifyListeners();
  }

  void setError(String message) {
    _error = message;
    notifyListeners();
  }

  @override
  AppUpdateInfo? get requiredUpdate => _required;

  @override
  AppUpdateInfo? get activeGateUpdate => _required ?? super.activeGateUpdate;

  @override
  bool get isForceUpdateRequired => _required != null;

  @override
  bool get isDownloading => _busy;

  @override
  double? get downloadProgress => _progress;

  @override
  int? get downloadedBytes => _downloaded;

  @override
  int? get totalBytes => _total;

  @override
  String? get errorMessage => _error;
}
