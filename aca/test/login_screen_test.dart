import 'package:flutter_test/flutter_test.dart';

import 'package:aca/features/auth/login_screen.dart';

import 'account_screens_test.dart' show app, setup, settle;

void main() {
  testWidgets('ACA sign-in has a branded hero, clear staff form and trust footer at phone size', (tester) async {
    final (repo, session) = await setup(tester);
    await tester.pumpWidget(app(repo, session, const LoginScreen()));
    await settle(tester);

    expect(find.text('AXON COUNTERBASE ADMIN'), findsOneWidget);
    expect(find.text('STAFF'), findsOneWidget);
    expect(find.text('Run Counterbase.\nWith confidence.'), findsOneWidget);
    expect(find.text('Staff sign-in'), findsOneWidget);
    expect(find.text('Work email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in securely'), findsOneWidget);
    expect(find.text('LIVE COUNTERBASE'), findsOneWidget);
    expect(find.text('Role-based access  ·  Admin actions are audited'), findsOneWidget);
  });
}
