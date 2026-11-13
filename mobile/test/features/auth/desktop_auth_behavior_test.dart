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
import 'package:axon_pos/features/auth/presentation/desktop/auth_desktop_kit.dart';
import 'package:axon_pos/features/auth/presentation/screens/company_choice_screen.dart';
import 'package:axon_pos/features/auth/presentation/screens/login_screen.dart';
import 'package:axon_pos/features/auth/presentation/screens/pin_login_screen.dart';
import 'package:axon_pos/features/auth/presentation/widgets/sign_in_kit.dart';
import 'package:axon_pos/features/legal/presentation/screens/legal_document_screen.dart';

import 'desktop_auth_test_support.dart';

/// Keyboard and layout behaviour of the computer sign-in screens.
void main() {
  late FakeAuthService auth;

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
    auth = FakeAuthService();
    getIt.registerSingleton<UpdateCheckService>(FakeUpdates());
    getIt.registerSingleton<ApiClient>(FakeCompanyApi());
    getIt.registerSingleton<AuthService>(auth);
  });

  tearDown(() async {
    DesktopLayout.debugIsDesktopPlatform = null;
    await getIt.popScope();
  });

  bool hasFocus(WidgetTester tester, Key fieldKey) {
    final editable = find.descendant(
      of: find.byKey(fieldKey),
      matching: find.byType(EditableText),
    );
    return tester.widget<EditableText>(editable).focusNode.hasFocus;
  }

  group('sign-in on a computer', () {
    Future<void> pumpLogin(
      WidgetTester tester, {
      StorageService? storage,
      Size size = const Size(1366, 768),
    }) async {
      getIt.registerSingleton<StorageService>(storage ?? FakeAuthStorage());
      await pumpAuthPage(tester, const LoginScreen(),
          size: size, dark: false, boundary: GlobalKey());
    }

    testWidgets('is the split layout on a wide window and a phone page on a narrow one',
        (tester) async {
      await pumpLogin(tester);
      expect(find.byType(AuthDesktopShell), findsOneWidget);
      // No dark header with a back arrow, no curved sheet.
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.text('Sign in to your shop'), findsOneWidget);
      expect(find.text('Run your counter, stock and daily sales.'),
          findsOneWidget);
    });

    testWidgets('a narrow window keeps the phone layout', (tester) async {
      await pumpLogin(tester, size: const Size(430, 900));
      expect(find.byType(AuthDesktopShell), findsNothing);
      expect(find.text('Sign in to your shop'), findsOneWidget);
      expect(find.text('Staff sign in'), findsOneWidget);
    });

    testWidgets('starts on the company code, then the first empty field',
        (tester) async {
      await pumpLogin(tester);
      expect(hasFocus(tester, const ValueKey('auth-company-code')), isTrue);
    });

    testWidgets('with a remembered company and email it starts on the password',
        (tester) async {
      await pumpLogin(
        tester,
        storage: FakeAuthStorage(
          rememberedSlug: 'evisa-ventures',
          rememberedEmail: 'mercy@evisa.co.ke',
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(hasFocus(tester, const ValueKey('auth-password')), isTrue);
      // The business is recognised, so its name replaces the code field.
      expect(find.text('Evisa Ventures'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-company-code')), findsNothing);
    });

    testWidgets('Tab moves company, email, password and Enter signs in',
        (tester) async {
      await pumpLogin(tester);
      await tester.enterText(
          find.byKey(const ValueKey('auth-company-code')), 'evisa-ventures');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(hasFocus(tester, const ValueKey('auth-email')), isTrue);
      await tester.enterText(
          find.byKey(const ValueKey('auth-email')), 'mercy@evisa.co.ke');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(hasFocus(tester, const ValueKey('auth-password')), isTrue);

      await tester.enterText(
          find.byKey(const ValueKey('auth-password')), 'Secret123');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(auth.logins.single['email'], 'mercy@evisa.co.ke');
      expect(auth.logins.single['tenant'], 'evisa-ventures');
      expect(find.text('Invalid email or password.'), findsOneWidget);
    });

    testWidgets('Enter on an empty form shows what is missing, no request',
        (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.byKey(const ValueKey('auth-password')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Please enter your company code'), findsOneWidget);
      expect(find.text('Please enter your email'), findsOneWidget);
      expect(auth.logins, isEmpty);
    });

    testWidgets('show password is a button you can reach with Tab',
        (tester) async {
      await pumpLogin(tester);
      final field = tester.widget<TextField>(find.descendant(
        of: find.byKey(const ValueKey('auth-password')),
        matching: find.byType(TextField),
      ));
      expect(field.obscureText, isTrue);

      await tester.tap(find.byKey(const ValueKey('auth-password')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      final revealed = tester.widget<TextField>(find.descendant(
        of: find.byKey(const ValueKey('auth-password')),
        matching: find.byType(TextField),
      ));
      expect(revealed.obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('warns when Caps Lock is on while typing the password',
        (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.byKey(const ValueKey('auth-password')));
      await tester.pump();
      expect(find.text('Caps Lock is on'), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.capsLock);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.capsLock);
      await tester.pump();
      expect(find.text('Caps Lock is on'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.capsLock);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.capsLock);
      await tester.pump();
      expect(find.text('Caps Lock is on'), findsNothing);
    });

    testWidgets('Esc goes back to the first screen', (tester) async {
      await pumpLogin(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('/company-choice'), findsOneWidget);
    });

    testWidgets('offers the phone QR sign-in, invitation and new business',
        (tester) async {
      await pumpLogin(tester);
      expect(find.text('Sign in with your phone'), findsOneWidget);
      expect(find.text('Have an invitation code?'), findsOneWidget);
      expect(find.text('Create a new business account'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Stay signed in'), findsOneWidget);
    });
  });

  group('PIN sign-in on a computer', () {
    Future<void> pumpPin(WidgetTester tester, {StorageService? storage}) async {
      getIt.unregister<AuthService>();
      auth = FakeAuthService(locked: true);
      getIt.registerSingleton<AuthService>(auth);
      getIt.registerSingleton<StorageService>(
          storage ?? FakeAuthStorage(local: true, pinLength: 6));
      await pumpAuthPage(tester, const PinLoginScreen(),
          size: const Size(1366, 768), dark: false, boundary: GlobalKey());
      await tester.pump(const Duration(milliseconds: 100));
    }

    int filled(WidgetTester tester) =>
        tester.widget<PinDots>(find.byType(PinDots)).filled;

    testWidgets('digits and Backspace on the keyboard fill and clear the dots',
        (tester) async {
      await pumpPin(tester);
      expect(tester.widget<PinDots>(find.byType(PinDots)).length, 6);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad2);
      await tester.pump();
      expect(filled(tester), 3);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(filled(tester), 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(filled(tester), 0);
    });

    testWidgets('the on-screen keys work with the mouse too', (tester) async {
      await pumpPin(tester);
      await tester.tap(find.text('5'));
      await tester.tap(find.text('7'));
      await tester.pump();
      expect(filled(tester), 2);
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(filled(tester), 1);
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(filled(tester), 0);
    });

    testWidgets('Enter with too few digits says so; with all digits it signs in',
        (tester) async {
      await pumpPin(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Enter all 6 digits to continue.'), findsOneWidget);
      expect(auth.pins, isEmpty);
      // The one digit stays; clear it, then type the whole PIN.
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);

      for (final key in [
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit9,
        LogicalKeyboardKey.digit3,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(auth.pins.single, '482193');
    });

    testWidgets('on a team computer, choose your name first, then Esc goes back',
        (tester) async {
      await pumpPin(
        tester,
        storage: FakeAuthStorage(
          local: true,
          staff: const [
            {'id': 's1', 'name': 'Otieno Brian', 'role': 'cashier'},
          ],
        ),
      );
      expect(find.text('Who is at the till?'), findsOneWidget);
      await tester.tap(find.text('Otieno Brian'));
      await tester.pump();
      expect(find.text('Cashier · enter your PIN'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      expect(filled(tester), 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Who is at the till?'), findsOneWidget);
    });

    testWidgets('an online workspace offers Use password instead',
        (tester) async {
      await pumpPin(tester, storage: FakeAuthStorage());
      expect(find.text('Use password instead'), findsOneWidget);
      // Offline is only promised for a workspace kept on this computer.
      expect(find.text('Works offline on this computer'), findsNothing);
    });

    testWidgets('a workspace kept on this computer says it works offline',
        (tester) async {
      await pumpPin(tester);
      expect(find.text('Works offline on this computer'), findsOneWidget);
      expect(find.text('Use password instead'), findsNothing);
    });
  });

  group('first screen on a computer', () {
    testWidgets('Enter starts a new shop and the labels say computer',
        (tester) async {
      await pumpAuthPage(tester, const CompanyChoiceScreen(),
          size: const Size(1366, 768), dark: false, boundary: GlobalKey());
      expect(find.text('Add this computer to my shop'), findsOneWidget);
      expect(find.text('Works without internet'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('/company-setup'), findsOneWidget);
    });

    testWidgets('a narrow window keeps the phone layout', (tester) async {
      await pumpAuthPage(tester, const CompanyChoiceScreen(),
          size: const Size(430, 900), dark: false, boundary: GlobalKey());
      expect(find.byType(AuthDesktopShell), findsNothing);
      expect(find.text('Add this phone to my shop'), findsOneWidget);
    });
  });

  group('legal documents on a computer', () {
    testWidgets('a document stops at a reading width and Esc goes back',
        (tester) async {
      await pumpAuthPage(tester, const LegalDocumentScreen(documentSlug: 'terms'),
          size: const Size(1920, 1080), dark: false, boundary: GlobalKey());
      final body = find.byType(ListView).first;
      expect(tester.getSize(body).width, lessThanOrEqualTo(760));
    });

    testWidgets('a narrow window keeps the full-width document', (tester) async {
      await pumpAuthPage(tester, const LegalDocumentScreen(documentSlug: 'terms'),
          size: const Size(430, 900), dark: false, boundary: GlobalKey());
      expect(tester.getSize(find.byType(ListView).first).width, 430);
    });
  });
}
