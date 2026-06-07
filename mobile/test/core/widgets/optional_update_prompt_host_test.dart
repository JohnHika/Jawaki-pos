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

      await tester.pump();
      await tester.pump();

      expect(find.text('Optional Update Ready'), findsOneWidget);
      expect(find.text('Login Screen'), findsOneWidget);
      expect(updateService.dialogShowCount, 1);
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
      await tester.pump();
      await tester.pump();

      expect(updateService.dialogShowCount, 1);
      expect(find.text('Optional Update Ready'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      updateService.setOptionalUpdate(sameUpdate);
      await tester.pump();
      await tester.pump();

      expect(updateService.dialogShowCount, 1);
      expect(find.text('Optional Update Ready'), findsNothing);
    },
  );
}

AppUpdateInfo _optionalUpdate(String latestVersion) {
  return AppUpdateInfo(
    latestVersion: latestVersion,
    minSupportedVersion: '1.0.0',
    forceUpdate: false,
    apkUrl: '/downloads/pos.apk',
    releaseNotes: 'Optional update notes',
  );
}

class _FakeUpdateCheckService extends UpdateCheckService {
  _FakeUpdateCheckService() : super(apiClient: ApiClient(Dio()));

  AppUpdateInfo? _optional;
  bool _forceUpdate = false;
  int dialogShowCount = 0;

  @override
  bool get hasOptionalUpdateAvailable => _optional != null;

  @override
  bool get isForceUpdateRequired => _forceUpdate;

  @override
  AppUpdateInfo? get optionalUpdate => _optional;

  void setOptionalUpdate(AppUpdateInfo? update, {bool forceUpdate = false}) {
    _optional = update;
    _forceUpdate = forceUpdate;
    notifyListeners();
  }

  @override
  Future<void> showCachedOptionalUpdateDialog(BuildContext context) async {
    dialogShowCount += 1;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Optional Update Ready'),
        content: Text(optionalUpdate?.latestVersion ?? 'unknown'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
        ],
      ),
    );
  }
}
