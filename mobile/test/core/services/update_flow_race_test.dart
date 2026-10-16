import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ManifestApi extends ApiClient {
  _ManifestApi(this.manifest) : super(Dio());
  final Map<String, dynamic> manifest;

  @override
  Future<Map<String, dynamic>> getLatestAndroidUpdate() async => manifest;
}

Map<String, dynamic> _manifest({required int build, String version = '1.0.56'}) => {
      'latestVersion': version,
      'buildNumber': build,
      'minSupportedVersion': '1.0.0',
      'forceUpdate': false,
      'apkUrl': 'https://example.com/app.apk',
      'releaseNotes': '- Faster checkout',
    };

void _runningBuild(int build, {String version = '1.0.55'}) {
  PackageInfo.setMockInitialValues(
    appName: 'Axon POS',
    packageName: 'com.archeaxon.axonpos',
    version: version,
    buildNumber: '$build',
    buildSignature: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sign-in vs update race', () {
    test('the update answer is known before checkAfterLogin returns',
        () async {
      _runningBuild(2098);
      final updates =
          UpdateCheckService(apiClient: _ManifestApi(_manifest(build: 2099)));

      updates.beginPostLoginCheck();
      expect(updates.isSettlingAfterLogin, isTrue);

      await updates.checkAfterLogin();

      // The login screen only navigates home after this point, so the
      // dashboard can never appear first and then get covered.
      expect(updates.isPostLoginUpdateRequired, isTrue);
      expect(updates.activeGateUpdate?.buildNumber, 2099);
      expect(updates.isSettlingAfterLogin, isFalse);
    });

    test('an up-to-date build lets the user straight in and clears the splash',
        () async {
      _runningBuild(2099, version: '1.0.56');
      final updates =
          UpdateCheckService(apiClient: _ManifestApi(_manifest(build: 2099)));

      updates.beginPostLoginCheck();
      await updates.checkAfterLogin();

      expect(updates.isPostLoginUpdateRequired, isFalse);
      expect(updates.isSettlingAfterLogin, isFalse);
    });

    test('a failed sign-in cannot leave the settling splash up', () async {
      _runningBuild(2098);
      final updates =
          UpdateCheckService(apiClient: _ManifestApi(_manifest(build: 2099)));

      updates.beginPostLoginCheck();
      expect(updates.isSettlingAfterLogin, isTrue);
      updates.cancelPostLoginCheck();
      expect(updates.isSettlingAfterLogin, isFalse);
    });
  });

  group('first launch after an installed update', () {
    Future<UpdateCheckService> launch({
      required Map<String, Object> prefs,
      required List<String> log,
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      _runningBuild(2099, version: '1.0.56');
      final updates =
          UpdateCheckService(apiClient: _ManifestApi(_manifest(build: 2099)));
      await updates.prepareLaunch(endSession: () async => log.add('signed out'));
      return updates;
    }

    test('signs out before the first frame, once, so the dashboard never shows',
        () async {
      final log = <String>[];
      final updates = await launch(log: log, prefs: {
        // An earlier build ran here and this update was installed in-app.
        'last_launched_build': 2098,
        'pending_update_notice_build': 2099,
        'pending_update_notice_version': '1.0.56',
        'pending_update_notice_release_notes': '- Faster checkout',
      });

      expect(log, ['signed out']);
      expect(updates.sessionResetForUpdate, isTrue);
    });

    test('an ordinary launch keeps the session', () async {
      final log = <String>[];
      final updates = await launch(log: log, prefs: {'last_launched_build': 2099});

      expect(log, isEmpty);
      expect(updates.sessionResetForUpdate, isFalse);
    });

    test('a failing server sign-out still counts as signed out locally',
        () async {
      SharedPreferences.setMockInitialValues({
        'last_launched_build': 2098,
        'pending_update_notice_build': 2099,
        'pending_update_notice_version': '1.0.56',
        'pending_update_notice_release_notes': '',
      });
      _runningBuild(2099, version: '1.0.56');
      final updates =
          UpdateCheckService(apiClient: _ManifestApi(_manifest(build: 2099)));

      await updates.prepareLaunch(
        endSession: () async => throw Exception('offline'),
      );

      expect(updates.sessionResetForUpdate, isTrue);
    });
  });
}
