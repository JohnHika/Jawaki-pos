import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/subscription/presentation/screens/subscription_settings_screen.dart';

/// A manual ApiClient spy that records calls and returns canned data.
class _SpyApiClient extends ApiClient {
  _SpyApiClient() : super(Dio());

  /// If set, getSubscriptionPlan returns this completer's future instead.
  Completer<Map<String, dynamic>>? planCompleter;

  /// Mock data matching the real backend response format.
  /// Backend returns: plan, subscriptionStatus, currentPeriodStart, currentPeriodEnd,
  /// setupFeePaidAt, maxBranches, maxUsers, activationStatus, activationPaidAt,
  /// planMeta (with planId, name, monthlyAmountKes, trialDays, features),
  /// availablePlans (array of plan pricing objects).
  Map<String, dynamic> planData = {
    'plan': 'CORE',
    'subscriptionStatus': 'TRIAL',
    'currentPeriodStart': '2026-08-04T00:00:00Z',
    'currentPeriodEnd': '2026-09-04T00:00:00Z',
    'setupFeePaidAt': '2026-08-04T00:00:00Z',
    'maxBranches': 3,
    'maxUsers': 10,
    'activationStatus': 'ACTIVE',
    'activationPaidAt': '2026-08-04T00:00:00Z',
    'planMeta': {
      'planId': 'CORE',
      'name': 'Core',
      'monthlyAmountKes': 3200,
      'trialDays': 7,
      'features': {
        'maxBranches': 3,
        'maxUsers': 10,
        'analytics': true,
        'prioritySupport': false,
        'aiAssistant': false,
        'customReports': false,
        'multiCurrency': false,
      },
    },
    'availablePlans': [
      {
        'planId': 'TRIAL',
        'name': 'Trial',
        'monthlyAmountKes': 0,
        'trialDays': 7,
      },
      {
        'planId': 'CORE',
        'name': 'Core',
        'monthlyAmountKes': 3200,
        'trialDays': 7,
      },
      {
        'planId': 'ENTERPRISE',
        'name': 'Enterprise',
        'monthlyAmountKes': 5000,
        'trialDays': 7,
      },
    ],
  };
  List<dynamic> invoices = [];
  Object? planError;
  Object? changePlanError;
  Map<String, dynamic>? lastChangePlanCall;

  @override
  Future<Map<String, dynamic>> getSubscriptionPlan() async {
    if (planCompleter != null) await planCompleter!.future;
    if (planError != null) throw planError!;
    return planData;
  }

  @override
  Future<List<dynamic>> getSubscriptionInvoices() async {
    return invoices;
  }

  @override
  Future<Map<String, dynamic>> changeSubscriptionPlan({
    required String planId,
  }) async {
    if (changePlanError != null) throw changePlanError!;
    lastChangePlanCall = {'planId': planId};
    planData['plan'] = planId.toUpperCase();
    planData['subscriptionStatus'] = 'ACTIVE';
    return planData;
  }
}

GoRouter _router() => GoRouter(
      initialLocation: '/settings/subscription',
      routes: [
        GoRoute(
          path: '/settings/subscription',
          builder: (context, state) => const SubscriptionSettingsScreen(),
        ),
      ],
    );

void main() {
  late _SpyApiClient spyApi;

  setUp(() {
    spyApi = _SpyApiClient();
    final getIt = GetIt.instance;
    if (getIt.isRegistered<ApiClient>()) {
      getIt.unregister<ApiClient>();
    }
    getIt.registerSingleton<ApiClient>(spyApi);
  });

  group('SubscriptionSettingsScreen', () {
    testWidgets('shows shimmer skeleton on init', (tester) async {
      spyApi.planCompleter = Completer(); // never completes

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pump();

      // Plan card + invoice rows render as shimmer skeletons — no spinner.
      expect(find.byType(ShimmerWidget), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows current plan details after loading', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Plan name
      expect(find.text('CORE'), findsOneWidget);

      // Status badge
      expect(find.text('Free Trial'), findsOneWidget);

      // Price
      expect(find.text('KES 3,200'), findsOneWidget);

      // Trial end date
      expect(find.textContaining('Trial ends'), findsOneWidget);

      // Change Plan button
      expect(find.text('Change Plan'), findsOneWidget);

      // Invoice history section (below the fold once the feature card
      // renders — scroll it into view).
      await tester.scrollUntilVisible(
        find.text('INVOICE HISTORY'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('INVOICE HISTORY'), findsOneWidget);
    });

    testWidgets('shows what the current plan includes', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // The "What's included" card lists the shared-catalog feature rows
      // instead of rendering an empty body.
      expect(find.text('What\u2019s included in CORE'), findsOneWidget);
      expect(find.text('Up to 3 branches'), findsOneWidget);
      expect(
        find.text('Sell as many items as you want — no per-sale charge'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
    });

    testWidgets('shows ENTERPRISE plan details', (tester) async {
      spyApi.planData = {
        'plan': 'ENTERPRISE',
        'subscriptionStatus': 'ACTIVE',
        'currentPeriodStart': '2026-08-04T00:00:00Z',
        'currentPeriodEnd': '2026-09-04T00:00:00Z',
        'setupFeePaidAt': '2026-08-04T00:00:00Z',
        'maxBranches': 10,
        'maxUsers': 50,
        'activationStatus': 'ACTIVE',
        'activationPaidAt': '2026-08-04T00:00:00Z',
        'planMeta': {
          'planId': 'ENTERPRISE',
          'name': 'Enterprise',
          'monthlyAmountKes': 10000,
          'trialDays': 7,
        },
        'availablePlans': [],
      };

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      expect(find.text('ENTERPRISE'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('KES 10,000'), findsOneWidget);
      expect(find.textContaining('Next billing'), findsOneWidget);
    });

    testWidgets('shows error state when API fails', (tester) async {
      spyApi.planError = Exception('Could not load subscription');

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      expect(find.text('Could not load subscription'), findsOneWidget);
    });

    testWidgets('error state offers retry that re-fetches the plan',
        (tester) async {
      spyApi.planError = Exception('Could not load subscription');

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      expect(find.text('Could not load subscription'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      // Recover the backend, then retry in place — no need to leave the
      // screen for the fetch to run again.
      spyApi.planError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load subscription'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('CORE'), findsOneWidget);
      expect(find.text('KES 3,200'), findsOneWidget);
    });

    testWidgets('shows empty invoice state', (tester) async {
      spyApi.invoices = [];

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('No invoices yet'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No invoices yet'), findsOneWidget);
    });

    testWidgets('shows invoice list when invoices exist', (tester) async {
      spyApi.invoices = [
        {
          'id': 'inv-1',
          'amount': 3200,
          'currency': 'KES',
          'status': 'PAID',
          'date': '2026-08-01T00:00:00Z',
          'description': 'CORE - Aug 2026',
        },
        {
          'id': 'inv-2',
          'amount': 3200,
          'currency': 'KES',
          'status': 'PENDING',
          'date': '2026-09-01T00:00:00Z',
          'description': 'CORE - Sep 2026',
        },
      ];

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Invoice section sits below the fold — scroll it into view.
      await tester.scrollUntilVisible(
        find.text('CORE - Sep 2026'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('CORE - Aug 2026'), findsOneWidget);
      expect(find.text('CORE - Sep 2026'), findsOneWidget);
      expect(find.text('PAID'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
    });

    testWidgets('change plan dialog opens and shows all three plan options',
        (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Tap Change Plan
      await tester.tap(find.text('Change Plan'));
      await tester.pumpAndSettle();

      // Dialog should show plan options
      expect(find.text('Change Plan'), findsNWidgets(2)); // title + button
      expect(find.text('CURRENT'), findsOneWidget);

      // All three tiers from the shared catalog, priced from the catalog.
      final dialogFinder = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialogFinder, matching: find.text('CORE')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialogFinder, matching: find.text('BUSINESS')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialogFinder, matching: find.text('ENTERPRISE')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: dialogFinder, matching: find.text('KES 3,200/mo')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: dialogFinder, matching: find.text('KES 6,500/mo')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: dialogFinder, matching: find.text('KES 10,000/mo')),
        findsOneWidget,
      );
    });

    testWidgets('change plan calls API with correct plan', (tester) async {
      spyApi.planData = {
        'plan': 'CORE',
        'subscriptionStatus': 'TRIAL',
        'currentPeriodEnd': '2026-09-04T00:00:00Z',
        'planMeta': {
          'planId': 'CORE',
          'name': 'Core',
          'monthlyAmountKes': 3200,
          'trialDays': 7,
        },
        'availablePlans': [],
      };

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Tap Change Plan
      await tester.tap(find.text('Change Plan'));
      await tester.pumpAndSettle();

      // Select ENTERPRISE (tap the plan name text inside the dialog)
      final dialogFinder = find.byType(AlertDialog);
      await tester.tap(
        find.descendant(of: dialogFinder, matching: find.text('ENTERPRISE').first),
      );
      await tester.pumpAndSettle();

      // The GradientButton is in the dialog — tap by its label text
      await tester.tap(
        find.descendant(
          of: dialogFinder,
          matching: find.text('Change to ENTERPRISE'),
        ),
      );
      await tester.pumpAndSettle();

      // API was called with the UPPERCASE plan id the backend expects
      // (VALID_PLANS is uppercase and matched with a strict includes()).
      expect(spyApi.lastChangePlanCall, isNotNull);
      expect(spyApi.lastChangePlanCall!['planId'], 'ENTERPRISE');
    });

    testWidgets('change plan to BUSINESS sends uppercase BUSINESS',
        (tester) async {
      spyApi.planData = {
        'plan': 'CORE',
        'subscriptionStatus': 'TRIAL',
        'currentPeriodEnd': '2026-09-04T00:00:00Z',
        'planMeta': {
          'planId': 'CORE',
          'name': 'Core',
          'monthlyAmountKes': 3200,
          'trialDays': 7,
        },
        'availablePlans': [],
      };

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change Plan'));
      await tester.pumpAndSettle();

      final dialogFinder = find.byType(AlertDialog);
      await tester.tap(
        find.descendant(of: dialogFinder, matching: find.text('BUSINESS').first),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: dialogFinder,
          matching: find.text('Change to BUSINESS'),
        ),
      );
      await tester.pumpAndSettle();

      expect(spyApi.lastChangePlanCall, isNotNull);
      expect(spyApi.lastChangePlanCall!['planId'], 'BUSINESS');
    });
  });
}
