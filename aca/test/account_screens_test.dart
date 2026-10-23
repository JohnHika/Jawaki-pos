import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aca/core/config.dart';
import 'package:aca/core/theme.dart';
import 'package:aca/data/api_client.dart';
import 'package:aca/data/models.dart';
import 'package:aca/data/repository.dart';
import 'package:aca/features/account/account_screen.dart';
import 'package:aca/state/session.dart';

// Test-only fixtures. The app itself never contains sample data.

const _secret = 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP';
const _backupCodes = [
  'AAAA-1111', 'BBBB-2222', 'CCCC-3333', 'DDDD-4444', 'EEEE-5555', 'FFFF-6666', 'GGGG-7777', 'HHHH-8888',
];

StaffProfile profile({bool twoFactor = false}) => StaffProfile(
      id: 'me',
      email: 'me@archeaxon.com',
      name: 'Me Myself',
      phone: '+254 700 000 000',
      role: 'OWNER',
      status: 'ACTIVE',
      permissions: const ['dashboard.view'],
      mustChangePassword: false,
      twoFactorEnabled: twoFactor,
      lastLoginAt: null,
      createdAt: DateTime(2026, 1, 1),
    );

SessionInfo device(String id, String label, {bool current = false}) => SessionInfo(
      id: id,
      deviceLabel: label,
      userAgent: null,
      ipAddress: '41.80.1.2',
      createdAt: null,
      lastUsedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      expiresAt: null,
      current: current,
    );

class FakeRepo extends AcaRepository {
  FakeRepo() : super(AcaApi(store: TokenStore()));

  final calls = <String>[];
  Object? changePasswordError;
  List<SessionInfo> sessions = [
    device('s0', 'Pixel 7 · ACA 1.0.0', current: true),
    device('s1', 'Galaxy A54 · ACA 1.0.0'),
    device('s2', 'Tecno Spark · ACA 1.0.0'),
  ];

  @override
  Future<List<SessionInfo>> mySessions() async => List.of(sessions);

  @override
  Future<void> revokeMySession(String sessionId) async {
    calls.add('revoke:$sessionId');
    sessions = sessions.where((s) => s.id != sessionId).toList();
  }

  @override
  Future<int> revokeMyOtherSessions() async {
    calls.add('revokeOthers');
    final n = sessions.where((s) => !s.current).length;
    sessions = sessions.where((s) => s.current).toList();
    return n;
  }

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    calls.add('changePassword:$currentPassword:$newPassword');
    if (changePasswordError != null) throw changePasswordError!;
  }

  @override
  Future<TwoFactorSetup> startTwoFactorSetup() async {
    calls.add('startSetup');
    return TwoFactorSetup(
      secret: _secret,
      otpauthUri: 'otpauth://totp/ACA%20Counterbase:me@archeaxon.com?secret=$_secret&issuer=ACA%20Counterbase',
    );
  }

  @override
  Future<List<String>> enableTwoFactor(String code) async {
    calls.add('enable:$code');
    if (code != '123456') throw ApiException(400, 'That code is not valid. Check the time on your phone and try again.');
    return _backupCodes;
  }

  @override
  Future<void> disableTwoFactor({required String password, required String code}) async {
    calls.add('disable:$password:$code');
  }
}

class FakeSession extends SessionController {
  FakeSession({required super.api, required super.repo, required super.prefs});

  /// What the profile becomes on the next reloadProfile (the server's new truth).
  StaffProfile? next;
  bool signedOut = false;

  @override
  Future<void> reloadProfile() async {
    if (next != null) me = next;
    notifyListeners();
  }

  @override
  Future<void> signOut({bool remote = true}) async {
    signedOut = true;
    me = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}

Future<void> loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final loader = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
    final file = File('$root/bin/cache/artifacts/material_fonts/$f');
    if (file.existsSync()) loader.addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

Future<(FakeRepo, FakeSession)> setup(WidgetTester tester, {bool twoFactor = false}) async {
  SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
    appName: 'ACA',
    packageName: 'xyz.arche_axon.aca',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );
  final prefs = await SharedPreferences.getInstance();
  final repo = FakeRepo();
  final session = FakeSession(api: repo.api, repo: repo, prefs: prefs)..me = profile(twoFactor: twoFactor);
  tester.view
    ..physicalSize = const Size(360 * 3, 740 * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  return (repo, session);
}

Widget app(FakeRepo repo, FakeSession session, Widget home) => MultiProvider(
      providers: [
        Provider<AcaApi>.value(value: repo.api),
        Provider<AcaRepository>.value(value: repo),
        ChangeNotifierProvider<SessionController>.value(value: session),
      ],
      child: MaterialApp(
        theme: AcaTheme.darkTheme,
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
        home: home,
      ),
    );

/// Lets animations run without waiting long enough for a snackbar to auto-dismiss.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  setUpAll(loadRoboto);

  group('AccountScreen', () {
    testWidgets('shows who you are, the security options and the connection', (tester) async {
      final (repo, session) = await setup(tester, twoFactor: true);
      await tester.pumpWidget(app(repo, session, const AccountScreen()));
      await settle(tester);

      expect(find.text('Account & security'), findsOneWidget);
      expect(find.text('Me Myself'), findsOneWidget);
      expect(find.text('me@archeaxon.com'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Member since 1 Jan 2026'), findsOneWidget);
      expect(find.text('Change password'), findsOneWidget);
      expect(find.text('Two-step verification'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);

      // No screen lock on the test device: the switch is disabled and says why.
      await reveal(tester, find.text('App lock'));
      expect(find.text('Set up a screen lock or fingerprint on this phone first'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'App lock')).onChanged, isNull);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'App lock')).value, isFalse);

      await reveal(tester, find.text('Hide ACA in screenshots and recent apps'));
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Hide ACA in screenshots and recent apps')).onChanged, isNotNull);

      await reveal(tester, find.text('Devices signed in'.toUpperCase()));
      await reveal(tester, find.text('Galaxy A54 · ACA 1.0.0'));
      expect(find.text('This device'), findsOneWidget);

      await reveal(tester, find.text('Connected to'));
      expect(find.text(AcaConfig.serverLabel), findsOneWidget);
      expect(find.text('1.2.3 (45)'), findsOneWidget);
      await reveal(tester, find.widgetWithText(OutlinedButton, 'Sign out'));
    });

    testWidgets('hide-in-screenshots switch is wired to the session', (tester) async {
      final (repo, session) = await setup(tester);
      await tester.pumpWidget(app(repo, session, const AccountScreen()));
      await settle(tester);

      final before = session.hideContent;
      final tile = find.widgetWithText(SwitchListTile, 'Hide ACA in screenshots and recent apps');
      await reveal(tester, tile);
      await tester.tap(tile);
      await settle(tester);
      expect(session.hideContent, !before);
    });

    testWidgets('signing out another device asks first, then removes it', (tester) async {
      final (repo, session) = await setup(tester);
      await tester.pumpWidget(app(repo, session, const AccountScreen()));
      await settle(tester);

      await reveal(tester, find.text('Galaxy A54 · ACA 1.0.0'));
      expect(find.byTooltip('Device options'), findsNWidgets(2), reason: 'the current device has no menu');
      await tester.tap(find.byTooltip('Device options').first);
      await settle(tester);
      await tester.tap(find.text('Sign out this device'));
      await settle(tester);
      expect(find.text('Sign out Galaxy A54 · ACA 1.0.0?'), findsOneWidget);
      expect(repo.calls, isEmpty);

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Sign out device'));
      await settle(tester);
      expect(repo.calls, ['revoke:s1']);
      expect(find.text('Device signed out'), findsOneWidget);
      expect(find.text('Galaxy A54 · ACA 1.0.0'), findsNothing);
    });

    testWidgets('sign out all other devices confirms and reports the count', (tester) async {
      final (repo, session) = await setup(tester);
      await tester.pumpWidget(app(repo, session, const AccountScreen()));
      await settle(tester);

      await tapVisibleAfterReveal(tester, find.widgetWithText(OutlinedButton, 'Sign out all other devices'));
      await settle(tester);
      expect(find.text('2 other devices will be signed out straight away. This phone stays signed in.'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Sign out other devices'));
      await settle(tester);

      expect(repo.calls, ['revokeOthers']);
      expect(find.text('Signed out 2 other devices'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Sign out all other devices'), findsNothing);
    });

    testWidgets('sign out ends the session and returns to the first screen', (tester) async {
      final (repo, session) = await setup(tester);
      await tester.pumpWidget(app(
        repo,
        session,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
                child: const Text('open account'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open account'));
      await settle(tester);
      expect(find.text('Account & security'), findsOneWidget);

      await tapVisibleAfterReveal(tester, find.widgetWithText(OutlinedButton, 'Sign out'));
      await settle(tester);
      expect(find.text('Sign out of ACA?'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Sign out'));
      await settle(tester);

      expect(session.signedOut, isTrue);
      expect(find.text('Account & security'), findsNothing);
      expect(find.text('open account'), findsOneWidget);
    });
  });

  group('Change password', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(ListTile, 'Change password'));
      await settle(tester);
    }

    testWidgets('live checklist turns green and the button needs a valid, confirmed password', (tester) async {
      final (repo, session) = await setup(tester);
      await tester.pumpWidget(app(repo, session, const AccountScreen()));
      await settle(tester);
      await open(tester);

      final submit = find.widgetWithText(FilledButton, 'Change password');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Current password'), 'Old-Passw0rd!x');
      await tester.enterText(find.widgetWithText(TextField, 'New password'), 'Correct-Horse9');
      await tester.pump();
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(5));

      await tester.enterText(find.widgetWithText(TextField, 'New password'), 'correct horse');
      await tester.pump();
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3), reason: 'length, lower-case and the space (a symbol) are met');

      await tester.enterText(find.widgetWithText(TextField, 'New password'), 'Correct-Horse9');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm new password'), 'Correct-Horse');
      await tester.pump();
      expect(find.text('The passwords do not match'), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Confirm new password'), 'Correct-Horse9');
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    });

    testWidgets('show/hide toggles all three fields', (tester) async {
      final (repo, session) = await setup(tester);
      await tester.pumpWidget(app(repo, session, const AccountScreen()));
      await settle(tester);
      await open(tester);

      bool obscured(String label) => tester.widget<TextField>(find.widgetWithText(TextField, label)).obscureText;
      expect(obscured('Current password'), isTrue);
      await tester.tap(find.byTooltip('Show passwords').first);
      await tester.pump();
      expect(obscured('Current password'), isFalse);
      expect(obscured('New password'), isFalse);
      expect(obscured('Confirm new password'), isFalse);
    });

    testWidgets('success closes the sheet and says other devices were signed out', (tester) async {
      final (repo, session) = await setup(tester);
      await tester.pumpWidget(app(repo, session, const AccountScreen()));
      await settle(tester);
      await open(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Current password'), 'Old-Passw0rd!x');
      await tester.enterText(find.widgetWithText(TextField, 'New password'), 'Correct-Horse9');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm new password'), 'Correct-Horse9');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Change password'));
      await settle(tester);

      expect(repo.calls, ['changePassword:Old-Passw0rd!x:Correct-Horse9']);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Password changed. Your other devices were signed out.'), findsOneWidget);
    });

    testWidgets('a wrong current password is reported inside the sheet', (tester) async {
      final (repo, session) = await setup(tester);
      repo.changePasswordError = ApiException(401, 'Current password is incorrect');
      await tester.pumpWidget(app(repo, session, const AccountScreen()));
      await settle(tester);
      await open(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Current password'), 'wrong');
      await tester.enterText(find.widgetWithText(TextField, 'New password'), 'Correct-Horse9');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm new password'), 'Correct-Horse9');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Change password'));
      await settle(tester);

      expect(find.text('Current password is incorrect'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('Two-step verification', () {
    testWidgets('enable flow: QR + key, code check, backup codes that must be acknowledged', (tester) async {
      final (repo, session) = await setup(tester);
      session.next = profile(twoFactor: true);
      await tester.pumpWidget(app(repo, session, const AccountScreen()));
      await settle(tester);

      expect(find.text('Off'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Two-step verification'));
      await settle(tester);

      // Step 1: QR (always black on white) and the manual key.
      expect(repo.calls, ['startSetup']);
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.backgroundColor, Colors.white);
      expect(qr.eyeStyle.color, Colors.black);
      expect(qr.dataModuleStyle.color, Colors.black);
      expect(find.text('JBSW Y3DP EHPK 3PXP JBSW Y3DP EHPK 3PXP'), findsOneWidget);
      expect(find.text('Can\'t scan? Enter this key'), findsOneWidget);
      expect(find.text('Copy key'), findsOneWidget);

      // Step 2: the button stays off until six digits are typed; a wrong code shows inline.
      final turnOn = find.widgetWithText(FilledButton, 'Turn on two-step verification');
      await reveal(tester, turnOn);
      expect(tester.widget<FilledButton>(turnOn).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '000000');
      await tester.pump();
      await tapVisible(tester, turnOn);
      await settle(tester);
      expect(find.textContaining('That code is not valid'), findsOneWidget);
      expect(find.text('Backup codes'), findsNothing, reason: 'a wrong code must not advance');

      await tester.enterText(find.byType(TextField), '123 456');
      await tester.pump();
      await tapVisible(tester, turnOn);
      await settle(tester);
      expect(repo.calls, ['startSetup', 'enable:000000', 'enable:123456']);

      // Backup codes: all eight shown, cannot leave until acknowledged.
      expect(find.text('Backup codes'), findsOneWidget);
      for (final c in _backupCodes) {
        expect(find.text(c), findsOneWidget, reason: c);
      }
      expect(find.text('Copy all'), findsOneWidget);
      final done = find.widgetWithText(FilledButton, 'Done');
      expect(tester.widget<FilledButton>(done).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Backup codes'), findsOneWidget, reason: 'back is blocked until the codes are saved');
      expect(find.text('Save your backup codes first, then tick the box to continue.'), findsOneWidget);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(tester.widget<FilledButton>(done).onPressed, isNotNull);
      await tester.tap(done);
      await settle(tester);

      expect(find.text('Backup codes'), findsNothing);
      expect(find.text('Account & security'), findsOneWidget);
      expect(find.text('Two-step verification is on'), findsOneWidget);
      expect(find.text('On'), findsOneWidget, reason: 'the profile was reloaded');
    });

    testWidgets('disable flow warns, needs password and code, then reloads', (tester) async {
      final (repo, session) = await setup(tester, twoFactor: true);
      session.next = profile(twoFactor: false);
      await tester.pumpWidget(app(repo, session, const AccountScreen()));
      await settle(tester);

      await tester.tap(find.widgetWithText(ListTile, 'Two-step verification'));
      await settle(tester);
      expect(find.text('Turn off two-step verification?'), findsOneWidget);
      expect(find.textContaining('anyone who learns your password'), findsOneWidget);

      final off = find.widgetWithText(FilledButton, 'Turn off');
      await tester.ensureVisible(off);
      await tester.pump();
      expect(tester.widget<FilledButton>(off).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Your password'), 'Old-Passw0rd!x');
      await tester.enterText(find.widgetWithText(TextField, 'Authenticator or backup code'), 'k7qd-9mxa');
      await tester.pumpAndSettle();
      await tapVisible(tester, off);
      await settle(tester);

      expect(repo.calls, ['disable:Old-Passw0rd!x:k7qd-9mxa']);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Two-step verification is off'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
    });
  });
}

Future<void> tapVisibleAfterReveal(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
}
