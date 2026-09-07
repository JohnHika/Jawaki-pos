import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/features/billing/domain/billing_entitlement.dart';
import 'package:axon_pos/features/billing/presentation/providers/entitlement_provider.dart';
import 'package:axon_pos/features/billing/presentation/widgets/subscription_entitlement_host.dart';

BillingEntitlement _entitlement({
  String status = 'ACTIVE',
  bool restricted = false,
  int? daysRemaining = 30,
}) {
  return BillingEntitlement(
    plan: 'CORE',
    status: status,
    daysRemaining: daysRemaining,
    restrictedMode: restricted,
  );
}

Widget _host(BillingEntitlement entitlement) {
  return ProviderScope(
    overrides: [
      entitlementProvider.overrideWith((ref) async => entitlement),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/pos',
        routes: [
          GoRoute(
            path: '/pos',
            builder: (context, state) => const SubscriptionEntitlementHost(
              child: Scaffold(body: Text('POS CONTENT')),
            ),
          ),
          GoRoute(
            path: '/billing',
            builder: (context, state) =>
                const Scaffold(body: Text('BILLING_SCREEN')),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('no entitlement resolved → no banner, child shown',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          entitlementProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(
          home: SubscriptionEntitlementHost(
            child: Scaffold(body: Text('POS CONTENT')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('POS CONTENT'), findsOneWidget);
    expect(find.text('Subscription paused'), findsNothing);
    expect(find.textContaining('expires'), findsNothing);
  });

  testWidgets('restrictedMode → red banner with pause copy and renew button',
      (tester) async {
    await tester.pumpWidget(
        _host(_entitlement(status: 'RESTRICTED', restricted: true)));
    await tester.pumpAndSettle();

    expect(find.text('Subscription paused'), findsOneWidget);
    expect(
      find.text(
          'You can still view past sales and export reports. Creating new sales is paused until payment.'),
      findsOneWidget,
    );
    expect(find.text('Renew Subscription'), findsOneWidget);

    // Banner navigates to the billing screen; never blocks data screens.
    await tester.tap(find.text('Renew Subscription'));
    await tester.pumpAndSettle();
    expect(find.text('BILLING_SCREEN'), findsOneWidget);
  });

  testWidgets('restricted banner is dismissible', (tester) async {
    await tester.pumpWidget(
        _host(_entitlement(status: 'RESTRICTED', restricted: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Subscription paused'), findsNothing);
    expect(find.text('POS CONTENT'), findsOneWidget);
  });

  testWidgets('daysRemaining <= 7 → amber expiry reminder', (tester) async {
    await tester.pumpWidget(_host(_entitlement(daysRemaining: 5)));
    await tester.pumpAndSettle();

    expect(find.text('Subscription expires in 5 days'), findsOneWidget);
    expect(find.text('Renew'), findsOneWidget);
  });

  testWidgets('daysRemaining > 7 → no banner', (tester) async {
    await tester.pumpWidget(_host(_entitlement(daysRemaining: 20)));
    await tester.pumpAndSettle();

    expect(find.textContaining('expires'), findsNothing);
    expect(find.text('Subscription paused'), findsNothing);
  });

  testWidgets('grace period (PAST_DUE without restriction) → reminder, '
      'not blocked', (tester) async {
    await tester.pumpWidget(
        _host(_entitlement(status: 'PAST_DUE', daysRemaining: 0)));
    await tester.pumpAndSettle();

    // In grace the client shows the expiry reminder (amber), never the
    // red pause banner unless the server flips restrictedMode.
    expect(find.text('Subscription paused'), findsNothing);
  });
}