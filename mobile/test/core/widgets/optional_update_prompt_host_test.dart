import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/core/widgets/optional_update_prompt_host.dart';

void main() {
  testWidgets(
    'shows optional update dialog above pre-login content when an update becomes available',
    (tester) async {
      final updateService = _FakeUpdateCheckService();

      await tester.pumpWidget(
        MaterialApp(
          home: OptionalUpdatePromptHost(
            updateService: updateService,
            child: const Scaffold(
              body: Center(
                child: Text('Login Screen'),
              ),
            ),
          ),
        ),
      );

      updateService.setOptionalUpdate(_optionalUpdate('1.0.3'));

      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Login Screen'), findsOneWidget);
    },
  );

  testWidgets(
    'does not reopen the same optional update twice in one app launch',
    (tester) async {
      final updateService = _FakeUpdateCheckService();
      final sameUpdate = _optionalUpdate('1.0.3');

      await tester.pumpWidget(
        MaterialApp(
          home: OptionalUpdatePromptHost(
            updateService: updateService,
            child: const Scaffold(
              body: Center(
                child: Text('Company Setup'),
              ),
            ),
          ),
        ),
      );

      updateService.setOptionalUpdate(sameUpdate);
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      updateService.setOptionalUpdate(sameUpdate);
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
    },
  );

  testWidgets(
    'shows installed update notice once when the current build has release notes',
    (tester) async {
      final updateService = _FakeUpdateCheckService();

      await tester.pumpWidget(
        MaterialApp(
          home: OptionalUpdatePromptHost(
            updateService: updateService,
            child: const Scaffold(
              body: Center(
                child: Text('Dashboard'),
              ),
            ),
          ),
        ),
      );

      updateService.setInstalledNotice(
        _optionalUpdate(
          '1.0.0',
          releaseName: 'Axon POS 1.0',
          buildNumber: 2014,
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text("You're up to date"), findsOneWidget);
      expect(updateService.installedNoticeConsumeCount, 1);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      updateService.setInstalledNotice(
        _optionalUpdate(
          '1.0.0',
          releaseName: 'Axon POS 1.0',
          buildNumber: 2014,
        ),
      );
      await tester.pumpAndSettle();

      // Same notice was already consumed once — the fake service's
      // consumeInstalledUpdateNoticeIfDue mirrors the real de-dupe
      // behaviour by returning null for an already-seen noticeKey.
      expect(updateService.installedNoticeConsumeCount, 1);
      expect(find.text("You're up to date"), findsNothing);
    },
  );
}

AppUpdateInfo _optionalUpdate(
  String latestVersion, {
  String? releaseName,
  int? buildNumber,
}) {
  return AppUpdateInfo(
    latestVersion: latestVersion,
    releaseName: releaseName,
    buildNumber: buildNumber,
    minSupportedVersion: '1.0.0',
    forceUpdate: false,
    apkUrl: '/downloads/pos.apk',
    releaseNotes: 'Optional update notes',
  );
}

class _FakeUpdateCheckService extends UpdateCheckService {
  _FakeUpdateCheckService() : super(apiClient: ApiClient(Dio()));

  AppUpdateInfo? _optional;
  AppUpdateInfo? _installedNotice;
  bool _forceUpdate = false;
  int installedNoticeConsumeCount = 0;
  String? _lastConsumedNoticeKey;

  @override
  bool get hasOptionalUpdateAvailable => _optional != null;

  @override
  bool get isForceUpdateRequired => _forceUpdate;

  @override
  AppUpdateInfo? get optionalUpdate => _optional;

  @override
  AppUpdateInfo? get installedUpdateNotice => _installedNotice;

  void setOptionalUpdate(AppUpdateInfo? update, {bool forceUpdate = false}) {
    _optional = update;
    _forceUpdate = forceUpdate;
    notifyListeners();
  }

  void setInstalledNotice(AppUpdateInfo? update) {
    _installedNotice = update;
    notifyListeners();
  }

  @override
  Future<AppUpdateInfo?> consumeInstalledUpdateNoticeIfDue() async {
    final update = _installedNotice;
    if (update == null) return null;
    if (update.noticeKey == _lastConsumedNoticeKey) return null;

    _lastConsumedNoticeKey = update.noticeKey;
    installedNoticeConsumeCount += 1;
    return update;
  }
}
