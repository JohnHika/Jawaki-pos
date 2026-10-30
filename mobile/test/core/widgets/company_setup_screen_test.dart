import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/auth/presentation/screens/company_setup_screen.dart';

void main() {
  testWidgets('registration is a guided four-step flow', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CompanySetupScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.textContaining('Step 1 of 4'), findsOneWidget);
    expect(find.text('Build your workspace'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Admin Account'), findsNothing);

    await tester.enterText(find.byType(TextFormField), 'Acme Retail');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Step 2 of 4'), findsOneWidget);
    // Renamed from "Meet the owner" in a8bef26.
    expect(find.text('About the owner'), findsOneWidget);
    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('verification follows business, owner, and branch details',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CompanySetupScreen()));
    await tester.pump(const Duration(milliseconds: 450));

    await tester.enterText(find.byType(TextFormField), 'Acme Retail');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'Lovelace');
    await tester.enterText(find.byType(TextFormField).at(2), 'ada@acme.test');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Main Store');
    await tester.enterText(find.byType(TextFormField).at(1), 'MAIN');
    await tester.ensureVisible(find.text('Continue'));
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

    await tester.enterText(find.byType(TextFormField), 'Acme%20Retail');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Only letters, numbers, spaces, &, ' and - are allowed",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Step 1 of 4'), findsOneWidget);
  });

}
