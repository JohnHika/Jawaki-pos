import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/features/auth/presentation/screens/company_choice_screen.dart';

Future<void> _pumpWelcome(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const CompanyChoiceScreen(),
      ),
      GoRoute(
        path: '/company-setup',
        builder: (context, state) => Scaffold(
          body: Text(
            state.uri.queryParameters['join'] == '1'
                ? 'join destination'
                : 'new shop destination',
          ),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Text('login destination')),
      ),
      GoRoute(
        path: '/legal/terms',
        builder: (context, state) =>
            const Scaffold(body: Text('terms destination')),
      ),
      GoRoute(
        path: '/legal/privacy',
        builder: (context, state) =>
            const Scaffold(body: Text('privacy destination')),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

void main() {
  testWidgets('welcome offers three doors and the Counterbase mark',
      (tester) async {
    await _pumpWelcome(tester);

    expect(
      find.text('Run your counter, stock and daily sales.'),
      findsOneWidget,
    );
    expect(find.text('Counterbase'), findsOneWidget);
    expect(find.text('by Arche Axon'), findsOneWidget);
    expect(find.text('Start a new shop'), findsOneWidget);
    expect(find.text('Add this phone to my shop'), findsOneWidget);
    expect(find.text('Sign in to my account'), findsOneWidget);
  });

  testWidgets('start a new shop opens the setup flow', (tester) async {
    await _pumpWelcome(tester);

    await tester.tap(find.text('Start a new shop'));
    await tester.pumpAndSettle();

    expect(find.text('new shop destination'), findsOneWidget);
  });

  testWidgets('add this phone opens setup in join mode', (tester) async {
    await _pumpWelcome(tester);

    await tester.tap(find.text('Add this phone to my shop'));
    await tester.pumpAndSettle();

    expect(find.text('join destination'), findsOneWidget);
  });

  testWidgets('sign in to my account opens the account screen',
      (tester) async {
    await _pumpWelcome(tester);

    await tester.tap(find.text('Sign in to my account'));
    await tester.pumpAndSettle();

    expect(find.text('login destination'), findsOneWidget);
  });

  testWidgets('terms and privacy links are on the welcome screen',
      (tester) async {
    await _pumpWelcome(tester);

    await tester.tap(find.text('Terms of Service'));
    await tester.pumpAndSettle();
    expect(find.text('terms destination'), findsOneWidget);

    // Back to the welcome screen, then the privacy link.
    await _pumpWelcome(tester);
    await tester.tap(find.text('Privacy Notice'));
    await tester.pumpAndSettle();
    expect(find.text('privacy destination'), findsOneWidget);
  });
}
