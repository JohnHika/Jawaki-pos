import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/features/auth/presentation/screens/company_choice_screen.dart';

void main() {
  // a8bef26 made the first-launch screen local-first: it offers workspace
  // creation only, with no cloud "Join an existing business" route.
  testWidgets('entry screen presents a motion launchpad and clear next steps',
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
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.textContaining('Your business,'), findsOneWidget);
    expect(find.text('Create your workspace'), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-motion-field')), findsOneWidget);
    // The local-first edition has no second (join) card.
    expect(find.text('Join an existing business'), findsNothing);

    await tester.tap(find.text('Create your workspace'));
    await tester.pumpAndSettle();

    expect(find.text('company setup destination'), findsOneWidget);
  });

  testWidgets('local-only note explains records stay on the device',
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
    await tester.pump(const Duration(milliseconds: 450));

    expect(
      find.textContaining('stored locally on this device'),
      findsOneWidget,
    );
  });
}
