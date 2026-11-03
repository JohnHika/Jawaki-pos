import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/auth/presentation/screens/company_setup_screen.dart';

void main() {
  testWidgets('registration is a guided two-step flow', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CompanySetupScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.textContaining('Step 1 of 2'), findsOneWidget);
    expect(find.text('Build your workspace'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    // Owner details moved onto the first step when the wizard was shortened;
    // they must be present there, not on a later step.
    expect(find.text('Last name'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Acme Retail');
    await tester.enterText(find.byType(TextFormField).at(1), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(2), 'Lovelace');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Step 2 of 2'), findsOneWidget);
    expect(find.text('Secure this device'), findsOneWidget);
    expect(find.text('Owner PIN · 6 digits'), findsOneWidget);
  });

  testWidgets('verification follows business and owner details',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CompanySetupScreen()));
    await tester.pump(const Duration(milliseconds: 450));

    await tester.enterText(find.byType(TextFormField).first, 'Acme Retail');
    await tester.enterText(find.byType(TextFormField).at(1), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(2), 'Lovelace');
    // Owner email is optional; leaving it empty must not block the step.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Secure this device'), findsOneWidget);
    expect(find.text('Owner PIN · 6 digits'), findsOneWidget);
    expect(find.text('Confirm owner PIN'), findsOneWidget);
    expect(
      find.text(
        'The workspace is created locally. No account, online POS server, or internet connection is needed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('company name rejects unsupported characters on step one',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CompanySetupScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));

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
    expect(find.textContaining('Step 1 of 2'), findsOneWidget);
  });
}
