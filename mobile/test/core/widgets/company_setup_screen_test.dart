import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/auth/presentation/screens/company_setup_screen.dart';

Future<void> _pumpSetup(WidgetTester tester, {bool join = false}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: CompanySetupScreen(join: join)));
  await tester.pump(const Duration(milliseconds: 450));
}

Future<void> _fillBusiness(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, 'Acme Retail');
  await tester.enterText(find.byType(TextFormField).at(1), 'Wanjiru');
  await tester.enterText(find.byType(TextFormField).at(2), 'Kamau');
}

void main() {
  testWidgets('a shop run by one person has three steps', (tester) async {
    await _pumpSetup(tester);

    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('Tell us about your shop'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    // Owner details sit on the first step.
    expect(find.text('Last name'), findsOneWidget);

    await _fillBusiness(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('How will you sell?'), findsOneWidget);
    expect(find.text('Just me'), findsOneWidget);
    expect(find.text('A team on this phone'), findsOneWidget);
    expect(find.text('Several phones'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text('Set your owner PIN'), findsOneWidget);
    expect(find.text('Create my shop'), findsOneWidget);
  });

  testWidgets('the owner PIN step explains where records stay and links the terms',
      (tester) async {
    await _pumpSetup(tester);
    await _fillBusiness(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Owner PIN'), findsOneWidget);
    expect(find.text('Confirm PIN'), findsOneWidget);
    expect(
      find.textContaining('my sales and stock stay on this phone'),
      findsOneWidget,
    );
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Notice'), findsOneWidget);
  });

  testWidgets('a team on one phone adds a skippable team step',
      (tester) async {
    await _pumpSetup(tester);
    await _fillBusiness(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('A team on this phone'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4'), findsOneWidget);
    expect(find.text('Who works at the till?'), findsOneWidget);
    // The owner is listed from the details already entered.
    expect(find.text('Wanjiru Kamau'), findsOneWidget);
    // Nothing added yet, so the action is a skip.
    expect(find.text('Skip for now'), findsOneWidget);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(find.text('Step 4 of 4'), findsOneWidget);
    expect(find.text('Set your owner PIN'), findsOneWidget);
  });

  testWidgets('a person can be added to the team before the shop exists',
      (tester) async {
    await _pumpSetup(tester);
    await _fillBusiness(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A team on this phone'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a person'));
    await tester.pumpAndSettle();

    // The sheet asks for a name, a role and a PIN.
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name of at least 2 letters.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Brian Otieno');
    await tester.enterText(find.byType(TextField).last, '48');
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
    expect(find.text('The PIN must be 4 to 6 digits.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '482193');
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();

    expect(find.text('Brian Otieno'), findsOneWidget);
    expect(find.text('Cashier'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Skip for now'), findsNothing);
  });

  testWidgets('several phones asks for a till name', (tester) async {
    await _pumpSetup(tester);
    await _fillBusiness(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Several phones'));
    await tester.pumpAndSettle();

    expect(find.text('Name this till'), findsOneWidget);
    expect(find.text('Front counter'), findsWidgets);
    expect(
      find.text(
        'Each phone keeps its own records for now. Move or combine them with a backup.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('adding a phone to an existing shop is labelled as such',
      (tester) async {
    await _pumpSetup(tester, join: true);

    expect(find.text('Add this phone'), findsOneWidget);
    expect(
      find.text('Use the same shop name as on your main phone.'),
      findsOneWidget,
    );
  });

  testWidgets('company name rejects unsupported characters on step one',
      (tester) async {
    await _pumpSetup(tester);

    // Target the business name field specifically: step one also carries the
    // owner fields, so a bare TextFormField finder would be ambiguous.
    final nameField = find.byType(TextFormField).first;
    await tester.enterText(nameField, 'Acme%20Retail');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Only letters, numbers, spaces, &, ' and - are allowed",
      ),
      findsOneWidget,
    );
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });
}
