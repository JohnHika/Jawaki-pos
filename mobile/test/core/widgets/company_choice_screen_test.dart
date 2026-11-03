import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/features/auth/presentation/screens/company_choice_screen.dart';

void main() {
  // The first-launch screen offers cloud sign-in first and device-only
  // setup second, plus a highlighted terms link.
  testWidgets('entry screen presents sign-in and device-only setup',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const CompanyChoiceScreen(),
        ),
        GoRoute(
          path: '/company-setup',
          builder: (context, state) => const Scaffold(
            body: Text('company setup destination'),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(
            body: Text('login destination'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    expect(find.text('Welcome to Counterbase'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Set up on this device only'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('login destination'), findsOneWidget);
  });

  testWidgets('device-only setup opens the workspace setup flow',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const CompanyChoiceScreen(),
        ),
        GoRoute(
          path: '/company-setup',
          builder: (context, state) => const Scaffold(
            body: Text('company setup destination'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    await tester.tap(find.text('Set up on this device only'));
    await tester.pumpAndSettle();

    expect(find.text('company setup destination'), findsOneWidget);
  });

  testWidgets('terms and conditions link is present and highlighted',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const CompanyChoiceScreen(),
        ),
        GoRoute(
          path: '/legal/terms',
          builder: (context, state) => const Scaffold(
            body: Text('legal destination'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    final link = tester.widget<Text>(
      find.text('Terms & conditions'),
    );
    expect(link.style?.color, isNotNull);
    expect(link.style?.decoration, TextDecoration.underline);
  });
}
