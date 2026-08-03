import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/features/auth/presentation/screens/owner_welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('verified workspace request never includes an owner password', () {
    const request = WorkspaceCreationRequest(
      companyName: 'Acme Retail',
      firstName: 'Ada',
      lastName: 'Lovelace',
      deviceId: 'a1d1d38f-f50c-4a3e-9089-929999999999',
      branch: WorkspaceBranchDetails(name: 'Main Store', code: 'MAIN'),
    );

    expect(request.toJson().containsKey('password'), isFalse);
    expect(request.toJson(), {
      'companyName': 'Acme Retail',
      'firstName': 'Ada',
      'lastName': 'Lovelace',
      'deviceId': 'a1d1d38f-f50c-4a3e-9089-929999999999',
      'branch': {'name': 'Main Store', 'code': 'MAIN'},
    });
  });

  testWidgets('owner onboarding renders server progress and next actions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OwnerWelcomeScreen(
          companyName: 'Acme Retail',
          onboardingLoader: () async => {
            'steps': [
              {'key': 'confirm_business', 'status': 'COMPLETED'},
              {'key': 'configure_branch', 'status': 'COMPLETED'},
              {'key': 'invite_staff', 'status': 'PENDING'},
              {'key': 'add_catalog', 'status': 'PENDING'},
              {'key': 'activate_payment', 'status': 'DEFERRED'},
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 of 5 completed'), findsOneWidget);
    expect(find.text('Invite your team'), findsOneWidget);
    expect(find.text('Set up payments'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Add Your First Product'),
      180,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Add Your First Product'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Finish later'),
      120,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Finish later'), findsOneWidget);
  });
}
