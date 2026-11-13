import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/features/auth/presentation/desktop/auth_desktop_kit.dart';
import 'package:axon_pos/features/auth/presentation/desktop/company_setup_desktop.dart';
import 'package:axon_pos/features/auth/presentation/screens/company_setup_screen.dart';

import '../../support/shot.dart';
import 'desktop_auth_test_support.dart';

/// Shop set-up in a computer window: step list on the left, dialogs, keyboard.
void main() {
  setUpAll(loadShotFonts);

  setUp(() {
    DesktopLayout.debugIsDesktopPlatform = true;
    getIt.pushNewScope();
    getIt.registerSingleton<AuthService>(FakeAuthService());
  });

  tearDown(() async {
    DesktopLayout.debugIsDesktopPlatform = null;
    await getIt.popScope();
  });

  Future<void> pumpSetup(
    WidgetTester tester, {
    Size size = const Size(1366, 768),
    bool dark = false,
    bool join = false,
    GlobalKey? boundary,
  }) async {
    await pumpAuthPage(tester, CompanySetupScreen(join: join),
        size: size, dark: dark, boundary: boundary ?? GlobalKey());
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> fillBusiness(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'Mama Njeri Mini Mart');
    await tester.enterText(find.byType(TextFormField).at(1), 'Njeri');
    await tester.enterText(find.byType(TextFormField).at(2), 'Wanjiku');
  }

  testWidgets('the steps are listed on the left, not in a progress bar',
      (tester) async {
    await pumpSetup(tester);
    expect(find.byType(AuthDesktopShell), findsOneWidget);
    expect(find.byType(AuthStepList), findsOneWidget);
    for (final label in ['Your business', 'How you sell', 'Owner PIN']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Team'), findsNothing);
    // No phone-style header with "Step 1 of 3".
    expect(find.text('Step 1 of 3'), findsNothing);
    expect(find.text('Tell us about your shop'), findsOneWidget);
    expect(find.text('Set up your shop on this computer.'), findsOneWidget);
  });

  testWidgets('the first field has the cursor and Enter on the last field continues',
      (tester) async {
    await pumpSetup(tester);
    final first = tester.widget<EditableText>(
        find.byType(EditableText).first);
    expect(first.focusNode.hasFocus, isTrue);

    await fillBusiness(tester);
    await tester.enterText(find.byType(TextFormField).at(3), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('How will you sell?'), findsOneWidget);
    expect(find.text('A team on this computer'), findsOneWidget);
    expect(find.text('Several computers'), findsOneWidget);
    expect(find.text('Just me'), findsOneWidget);
  });

  testWidgets('Esc goes back one step, then Back and Continue work',
      (tester) async {
    await pumpSetup(tester);
    await fillBusiness(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('How will you sell?'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Tell us about your shop'), findsOneWidget);

    // Done steps can be clicked in the list.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Set your owner PIN'), findsOneWidget);
    await tester.tap(find.text('Your business'));
    await tester.pumpAndSettle();
    expect(find.text('Tell us about your shop'), findsOneWidget);
  });

  testWidgets('a team adds a Your team step and a dialog adds a person',
      (tester) async {
    await pumpSetup(tester);
    await fillBusiness(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A team on this computer'));
    await tester.pumpAndSettle();
    expect(find.text('Your team'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Who works at the till?'), findsOneWidget);

    await tester.tap(find.text('Add a person'));
    await tester.pumpAndSettle();
    // A dialog on a computer, not a bottom sheet.
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name of at least 2 letters.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Brian Otieno');
    await tester.enterText(find.byType(TextFormField).at(1), '482193');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Brian Otieno'), findsOneWidget);
    expect(find.text('Cashier'), findsOneWidget);
  });

  testWidgets('the shop type is picked in a dialog and Esc closes it',
      (tester) async {
    await pumpSetup(tester);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Choose your shop type'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'pharm');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Pharmacy & health shop'), findsOneWidget);
  });

  testWidgets('the owner PIN step explains where records stay', (tester) async {
    await pumpSetup(tester);
    await fillBusiness(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Create my shop'), findsOneWidget);
    expect(
      find.textContaining('my sales and stock stay on this computer'),
      findsOneWidget,
    );
    expect(find.textContaining('phone'), findsNothing);
  });

  testWidgets('the ready screen lists what to do next', (tester) async {
    await pumpAuthPage(
      tester,
      SetupReadyDesktopView(
        shopName: 'Mama Njeri Mini Mart',
        stepLabels: const ['Your business', 'How you sell', 'Owner PIN'],
        teamIssues: const [],
        onOpen: () {},
        next: [
          SetupNextItem(
              icon: Icons.inventory_2_outlined,
              title: 'Add your products',
              detail: 'Type them in, scan, or import a list.',
              onTap: () {}),
        ],
      ),
      size: const Size(1366, 768),
      dark: false,
      boundary: GlobalKey(),
    );
    expect(find.text('Your shop is ready'), findsOneWidget);
    expect(find.text('Open my shop'), findsOneWidget);
  });

  for (final entry in authShotSizes.entries) {
    for (final dark in [false, true]) {
      final label = '${entry.key} ${dark ? 'dark' : 'light'}';

      testWidgets('shot: business step ($label)', (tester) async {
        final boundary = GlobalKey();
        await pumpSetup(tester,
            size: entry.value, dark: dark, boundary: boundary);
        await fillBusiness(tester);
        await tester.pump(const Duration(milliseconds: 300));
        await saveShot(tester, boundary, shotName('setup-business', dark, entry.key));
        expect(tester.takeException(), isNull);
      });

      testWidgets('shot: sell step ($label)', (tester) async {
        final boundary = GlobalKey();
        await pumpSetup(tester,
            size: entry.value, dark: dark, boundary: boundary);
        await fillBusiness(tester);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await saveShot(tester, boundary, shotName('setup-sell', dark, entry.key));
        expect(tester.takeException(), isNull);
      });

      testWidgets('shot: owner PIN step ($label)', (tester) async {
        final boundary = GlobalKey();
        await pumpSetup(tester,
            size: entry.value, dark: dark, boundary: boundary);
        await fillBusiness(tester);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await saveShot(tester, boundary, shotName('setup-pin', dark, entry.key));
        expect(tester.takeException(), isNull);
      });

      testWidgets('shot: ready ($label)', (tester) async {
        final boundary = GlobalKey();
        await pumpAuthPage(
          tester,
          SetupReadyDesktopView(
            shopName: 'Mama Njeri Mini Mart',
            stepLabels: const ['Your business', 'How you sell', 'Owner PIN'],
            onOpen: () {},
            next: [
              SetupNextItem(
                  icon: Icons.inventory_2_outlined,
                  title: 'Add your products',
                  detail: 'Type them in, scan, or import a list.',
                  onTap: () {}),
              SetupNextItem(
                  icon: Icons.payments_outlined,
                  title: 'Choose how customers pay',
                  detail: 'Cash and M-Pesa at the counter.',
                  onTap: () {}),
              SetupNextItem(
                  icon: Icons.image_outlined,
                  title: 'Add your logo',
                  detail: 'Your own logo replaces the Counterbase mark.',
                  onTap: () {}),
            ],
          ),
          size: entry.value,
          dark: dark,
          boundary: boundary,
        );
        await saveShot(tester, boundary, shotName('setup-ready', dark, entry.key));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
