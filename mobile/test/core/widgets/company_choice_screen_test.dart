import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/features/auth/presentation/screens/company_choice_screen.dart';

void main() {
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
    expect(find.text('Join an existing business'), findsOneWidget);
    expect(find.byKey(const ValueKey('entry-motion-field')), findsOneWidget);

    await tester.tap(find.text('Create your workspace'));
    await tester.pumpAndSettle();

    expect(find.text('company setup destination'), findsOneWidget);
  });

  testWidgets('Join existing business preserves a back route to start',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const CompanyChoiceScreen(),
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
    final joinAction = find.ancestor(
      of: find.text('Join an existing business'),
      matching: find.byType(InkWell),
    );
    await tester.tap(joinAction);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('login destination'), findsOneWidget);

    router.pop();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Create your workspace'), findsOneWidget);
  });
}
