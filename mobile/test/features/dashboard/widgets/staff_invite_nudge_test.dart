import 'dart:async';

import 'package:axon_pos/features/dashboard/presentation/widgets/staff_invite_nudge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('StaffInviteNudge', () {
    testWidgets('shows nudge when invite_staff step is PENDING',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffInviteNudge(
              onboardingLoader: () async => {
                'steps': [
                  {'key': 'confirm_business', 'status': 'COMPLETED'},
                  {'key': 'configure_branch', 'status': 'COMPLETED'},
                  {'key': 'invite_staff', 'status': 'PENDING'},
                  {'key': 'add_catalog', 'status': 'PENDING'},
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invite your team'), findsOneWidget);
      expect(find.text('Invite Staff Now'), findsOneWidget);
      expect(find.text('Remind Later'), findsOneWidget);
    });

    testWidgets('shows nudge when invite_staff step is DEFERRED',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffInviteNudge(
              onboardingLoader: () async => {
                'steps': [
                  {'key': 'invite_staff', 'status': 'DEFERRED'},
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invite your team'), findsOneWidget);
      expect(find.text('Invite Staff Now'), findsOneWidget);
    });

    testWidgets('hides nudge when invite_staff step is COMPLETED',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffInviteNudge(
              onboardingLoader: () async => {
                'steps': [
                  {'key': 'confirm_business', 'status': 'COMPLETED'},
                  {'key': 'invite_staff', 'status': 'COMPLETED'},
                  {'key': 'add_catalog', 'status': 'PENDING'},
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invite your team'), findsNothing);
      expect(find.text('Invite Staff Now'), findsNothing);
    });

    testWidgets('shows nudge when invite_staff step is absent from steps list',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffInviteNudge(
              onboardingLoader: () async => {
                'steps': [
                  {'key': 'confirm_business', 'status': 'COMPLETED'},
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // When the step is absent, status is empty string — not COMPLETED,
      // so the nudge should show.
      expect(find.text('Invite your team'), findsOneWidget);
    });

    testWidgets('hides nudge while loading', (tester) async {
      // Use a Completer that never completes during the test.
      // We pump a few frames but never resolve the future, so the widget
      // stays in loading state.  The completer is cleaned up in tearDown.
      final completer = Completer<Map<String, dynamic>>();
      addTearDown(() => completer.complete({}));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffInviteNudge(onboardingLoader: () => completer.future),
          ),
        ),
      );
      // Pump a few frames — the future is still pending, so the widget
      // should show nothing (loading state returns SizedBox.shrink).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Invite your team'), findsNothing);
      expect(find.text('Invite Staff Now'), findsNothing);
    });

    testWidgets('hides nudge on load error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffInviteNudge(
              onboardingLoader: () async => throw Exception('Network error'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invite your team'), findsNothing);
      expect(find.text('Invite Staff Now'), findsNothing);
    });

    testWidgets('"Remind Later" dismisses nudge for the session',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaffInviteNudge(
              onboardingLoader: () async => {
                'steps': [
                  {'key': 'invite_staff', 'status': 'PENDING'},
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nudge is visible
      expect(find.text('Invite your team'), findsOneWidget);

      // Tap "Remind Later"
      await tester.tap(find.text('Remind Later'));
      await tester.pumpAndSettle();

      // Nudge is dismissed
      expect(find.text('Invite your team'), findsNothing);
      expect(find.text('Invite Staff Now'), findsNothing);
    });

    testWidgets('"Invite Staff Now" button navigates to /users',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
              body: StaffInviteNudge(
                onboardingLoader: () async => {
                  'steps': [
                    {'key': 'invite_staff', 'status': 'PENDING'},
                  ],
                },
              ),
            ),
          ),
          GoRoute(
            path: '/users',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('User Management'))),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
      ));
      await tester.pumpAndSettle();

      // Tap "Invite Staff Now"
      await tester.tap(find.text('Invite Staff Now'));
      await tester.pumpAndSettle();

      // Should have navigated to /users
      expect(find.text('User Management'), findsOneWidget);
    });

    testWidgets('nudge reappears on rebuild after Remind Later',
        (tester) async {
      // Shared loader factory so both widget instances behave identically.
      Map<String, dynamic> Function() makeData = () => {
            'steps': [
              {'key': 'invite_staff', 'status': 'PENDING'},
            ],
          };

      Widget buildNudge(Key key) => MaterialApp(
            home: Scaffold(
              body: StaffInviteNudge(
                key: key,
                onboardingLoader: () async => makeData(),
              ),
            ),
          );

      // First instance
      await tester.pumpWidget(buildNudge(const ValueKey('first')));
      await tester.pumpAndSettle();
      expect(find.text('Invite your team'), findsOneWidget);

      // Dismiss
      await tester.tap(find.text('Remind Later'));
      await tester.pumpAndSettle();
      expect(find.text('Invite your team'), findsNothing);

      // Second instance with a different key — simulates new session / app
      // launch where the widget is a fresh StatefulWidget instance.
      await tester.pumpWidget(buildNudge(const ValueKey('second')));
      await tester.pumpAndSettle();

      // Nudge should reappear because it's a new widget instance
      expect(find.text('Invite your team'), findsOneWidget);
    });
  });
}
