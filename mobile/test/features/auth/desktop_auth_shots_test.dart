import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/features/auth/presentation/screens/company_choice_screen.dart';
import 'package:axon_pos/features/auth/presentation/screens/login_screen.dart';
import 'package:axon_pos/features/auth/presentation/screens/pin_login_screen.dart';

import '../../support/shot.dart';
import 'desktop_auth_test_support.dart';

/// Writes the computer sign-in screens to build/shots/auth-*.png for review,
/// at the three window sizes and in both themes, and checks nothing overflows.
void main() {
  setUpAll(loadShotFonts);

  setUp(() {
    DesktopLayout.debugIsDesktopPlatform = true;
    PackageInfo.setMockInitialValues(
      appName: 'Counterbase',
      packageName: 'app.counterbase',
      version: '1.0.82',
      buildNumber: '2125',
      buildSignature: '',
    );
    getIt.pushNewScope();
    getIt.registerSingleton<UpdateCheckService>(FakeUpdates());
    getIt.registerSingleton<ApiClient>(FakeCompanyApi());
  });

  tearDown(() async {
    DesktopLayout.debugIsDesktopPlatform = null;
    await getIt.popScope();
  });

  for (final entry in authShotSizes.entries) {
    for (final dark in [false, true]) {
      final label = '${entry.key} ${dark ? 'dark' : 'light'}';

      testWidgets('sign-in, empty ($label)', (tester) async {
        getIt.registerSingleton<StorageService>(FakeAuthStorage());
        getIt.registerSingleton<AuthService>(FakeAuthService());
        final boundary = GlobalKey();
        await pumpAuthPage(tester, const LoginScreen(),
            size: entry.value, dark: dark, boundary: boundary);
        await saveShot(tester, boundary, shotName('signin-empty', dark, entry.key));
        expect(tester.takeException(), isNull);
      });

      testWidgets('sign-in, wrong password ($label)', (tester) async {
        getIt.registerSingleton<StorageService>(FakeAuthStorage(
          rememberedSlug: 'evisa-ventures',
          rememberedEmail: 'mercy@evisa.co.ke',
        ));
        getIt.registerSingleton<AuthService>(FakeAuthService());
        final boundary = GlobalKey();
        await pumpAuthPage(tester, const LoginScreen(),
            size: entry.value, dark: dark, boundary: boundary);
        await tester.pump(const Duration(seconds: 1));
        await tester.enterText(
            find.byKey(const ValueKey('auth-password')), 'wrongpass1');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await saveShot(tester, boundary, shotName('signin-error', dark, entry.key));
        expect(find.text('Invalid email or password.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('PIN keypad ($label)', (tester) async {
        getIt.registerSingleton<StorageService>(FakeAuthStorage(
          local: true,
          pinLength: 6,
        ));
        getIt.registerSingleton<AuthService>(FakeAuthService(locked: true));
        final boundary = GlobalKey();
        await pumpAuthPage(tester, const PinLoginScreen(),
            size: entry.value, dark: dark, boundary: boundary);
        await tester.pump(const Duration(milliseconds: 100));
        for (final key in [
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit8,
          LogicalKeyboardKey.digit2,
        ]) {
          await tester.sendKeyEvent(key);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await saveShot(tester, boundary, shotName('pin', dark, entry.key));
        expect(tester.takeException(), isNull);
      });

      testWidgets('PIN, who is at the till ($label)', (tester) async {
        getIt.registerSingleton<StorageService>(FakeAuthStorage(
          local: true,
          staff: const [
            {'id': 's1', 'name': 'Otieno Brian', 'role': 'cashier'},
            {'id': 's2', 'name': 'Achieng Faith', 'role': 'stock_keeper'},
            {'id': 's3', 'name': 'Kamau Peter', 'role': 'manager'},
          ],
        ));
        getIt.registerSingleton<AuthService>(FakeAuthService(locked: true));
        final boundary = GlobalKey();
        await pumpAuthPage(tester, const PinLoginScreen(),
            size: entry.value, dark: dark, boundary: boundary);
        await tester.pump(const Duration(milliseconds: 100));
        await saveShot(tester, boundary, shotName('pin-people', dark, entry.key));
        expect(tester.takeException(), isNull);
      });

      testWidgets('company choice ($label)', (tester) async {
        final boundary = GlobalKey();
        await pumpAuthPage(tester, const CompanyChoiceScreen(),
            size: entry.value, dark: dark, boundary: boundary);
        await saveShot(tester, boundary, shotName('choice', dark, entry.key));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
