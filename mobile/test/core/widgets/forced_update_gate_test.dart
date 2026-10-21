import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/core/widgets/forced_update_gate.dart';

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUpdates extends UpdateCheckService {
  _FakeUpdates({this.downloading = false, this.error})
      : super(apiClient: _NoApi());

  final bool downloading;
  final String? error;

  @override
  AppUpdateInfo? get activeGateUpdate => const AppUpdateInfo(
        latestVersion: '1.0.54',
        buildNumber: 2097,
        minSupportedVersion: '1.0.0',
        forceUpdate: true,
        apkUrl: 'https://example.com/axon.apk',
        releaseNotes: '- Faster scanning\n- Trade Partners\n- Notification centre',
      );

  @override
  String? get currentVersion => '1.0.50+2090';

  @override
  bool get isDownloading => downloading;

  @override
  double? get downloadProgress => downloading ? 0.42 : null;

  @override
  int? get downloadedBytes => downloading ? 22 * 1024 * 1024 : null;

  @override
  int? get totalBytes => downloading ? 52 * 1024 * 1024 : null;

  @override
  String? get errorMessage => error;
}

void main() {
  Future<void> pumpGate(
    WidgetTester tester,
    UpdateCheckService service,
    Size size,
  ) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ForcedUpdateGate(updateService: service)),
    );
    await tester.pump(const Duration(milliseconds: 900));
  }

  for (final size in const [Size(360, 640), Size(411, 891)]) {
    testWidgets('gate lays out without overflow when idle at $size',
        (tester) async {
      await pumpGate(tester, _FakeUpdates(), size);
      expect(find.text('Update Required'), findsOneWidget);
      expect(find.text('Download & install update'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('gate lays out without overflow while downloading at $size',
        (tester) async {
      await pumpGate(tester, _FakeUpdates(downloading: true), size);
      expect(find.text('Updating Counterbase'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('gate shows an error banner without overflow', (tester) async {
    await pumpGate(
      tester,
      _FakeUpdates(error: 'Download failed. Check your connection and retry.'),
      const Size(360, 640),
    );
    expect(find.textContaining('Download failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
