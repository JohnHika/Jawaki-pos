import 'package:axon_pos/core/providers/tenant_provider.dart';
import 'package:axon_pos/features/onboarding/domain/setup_checklist.dart';
import 'package:axon_pos/features/onboarding/presentation/screens/setup_screen.dart';
import 'package:axon_pos/features/onboarding/presentation/setup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
  }

  Future<void> showSetup(WidgetTester tester, SetupFacts facts) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tenantIdentityProvider.overrideWithValue(const TenantIdentity(
          companyName: 'Levisa Ventures',
          logoUrl: null,
          userFirstName: 'Mathias',
          userFullName: 'Mathias',
          branchName: 'Main store',
          role: 'Owner',
        )),
        setupChecklistProvider
            .overrideWith((ref) async => SetupChecklist.from(facts)),
      ],
      child: const MaterialApp(home: SetupScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('names the next step and what is already done', (tester) async {
    phoneSize(tester);
    await showSetup(
      tester,
      const SetupFacts(hasReceiptDetails: true, productCount: 40),
    );

    expect(find.text('Get Levisa Ventures ready to sell'), findsOneWidget);
    expect(find.textContaining('2 of 7 done'), findsOneWidget);
    expect(find.text('NEXT UP'), findsOneWidget);
    expect(find.text('Add staff'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('40 products ready to sell.'), findsOneWidget);
  });

  testWidgets('says so when nothing is left to set up', (tester) async {
    phoneSize(tester);
    await showSetup(
      tester,
      const SetupFacts(
        hasReceiptDetails: true,
        productCount: 40,
        staffCount: 2,
        hasPaymentTill: true,
        hasLogo: true,
        saleCount: 5,
        notes: {'backup': 'DONE'},
      ),
    );

    expect(find.text('Levisa Ventures is ready to sell'), findsOneWidget);
    expect(find.text('Nothing left to set up'), findsOneWidget);
    expect(find.text('NEXT UP'), findsNothing);
  });
}
