import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aca/features/auth/login_screen.dart';

import 'account_screens_test.dart' show app, setup, settle;

void main() {
  testWidgets(
    'uses the current Counterbase mark, direct staff sign-in copy and secure footer at phone size',
    (tester) async {
      final (repo, session) = await setup(tester);
      await tester.pumpWidget(app(repo, session, const LoginScreen()));
      await settle(tester);

      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.semanticLabel == 'Counterbase',
        ),
        findsOneWidget,
      );
      expect(find.text('Counterbase'), findsOneWidget);
      expect(find.text('PLATFORM ADMIN'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Work email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('LIVE COUNTERBASE'), findsOneWidget);
      expect(
        find.text('Authorized staff only · Activity is recorded'),
        findsOneWidget,
      );
    },
  );
}
