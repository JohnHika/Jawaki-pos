import 'package:axon_pos/features/billing/domain/billing_entitlement.dart';
import 'package:axon_pos/features/billing/presentation/providers/entitlement_provider.dart';
import 'package:axon_pos/features/billing/presentation/widgets/feature_locked.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _app(ClientLicense? license, Widget home) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => home),
      GoRoute(
        path: '/billing',
        builder: (_, __) => const Scaffold(body: Text('PLANS PAGE')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [licenseProvider.overrideWith((ref) => license)],
    child: MaterialApp.router(routerConfig: router),
  );
}

const _enforcedNoAnalytics = ClientLicense(
  enforced: true,
  features: {'analytics': false, 'customReports': true},
);

const _lockedTitle = "Sales analytics isn't included in your plan";

void main() {
  testWidgets('FeatureGate shows the child when the module is licensed',
      (tester) async {
    await tester.pumpWidget(_app(
      _enforcedNoAnalytics,
      const Scaffold(
        body: FeatureGate(
          feature: LicensedFeature.customReports,
          child: Text('CUSTOM REPORTS'),
        ),
      ),
    ));
    expect(find.text('CUSTOM REPORTS'), findsOneWidget);
  });

  testWidgets('FeatureGate replaces an unlicensed module with the lock',
      (tester) async {
    await tester.pumpWidget(_app(
      _enforcedNoAnalytics,
      const Scaffold(
        body: FeatureGate(
          feature: LicensedFeature.analytics,
          child: Text('ANALYTICS'),
        ),
      ),
    ));
    expect(find.text('ANALYTICS'), findsNothing);
    expect(find.text(_lockedTitle), findsOneWidget);
    await tester.tap(find.text('See plans'));
    await tester.pumpAndSettle();
    expect(find.text('PLANS PAGE'), findsOneWidget);
  });

  testWidgets('fails open until the licence is known', (tester) async {
    await tester.pumpWidget(_app(
      null,
      const Scaffold(
        body: FeatureGate(
          feature: LicensedFeature.analytics,
          child: Text('ANALYTICS'),
        ),
      ),
    ));
    expect(find.text('ANALYTICS'), findsOneWidget);
  });

  testWidgets('ensureFeature opens the sheet and returns false when locked',
      (tester) async {
    bool? result;
    await tester.pumpWidget(_app(
      _enforcedNoAnalytics,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async {
              result = await ensureFeature(
                context,
                ref,
                LicensedFeature.analytics,
              );
            },
            child: const Text('TAP'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('TAP'));
    await tester.pumpAndSettle();
    // The sheet is up and the call has not returned yet.
    expect(find.text(_lockedTitle), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('ensureFeature lets a licensed module straight through',
      (tester) async {
    bool? result;
    await tester.pumpWidget(_app(
      _enforcedNoAnalytics,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async {
              result = await ensureFeature(
                context,
                ref,
                LicensedFeature.customReports,
              );
            },
            child: const Text('TAP'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('TAP'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('See plans'), findsNothing);
  });
}
