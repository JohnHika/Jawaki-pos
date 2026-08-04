import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/core/network/api_client.dart';
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
    testWidgets('shows loading indicator on init', (tester) async {
      spyApi.planCompleter = Completer(); // never completes

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
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

      // Invoice history section
      expect(find.text('INVOICE HISTORY'), findsOneWidget);
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
          'monthlyAmountKes': 5000,
          'trialDays': 7,
        },
        'availablePlans': [],
      };

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      expect(find.text('ENTERPRISE'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('KES 5,000'), findsOneWidget);
      expect(find.textContaining('Next billing'), findsOneWidget);
    });

    testWidgets('shows error state when API fails', (tester) async {
      spyApi.planError = Exception('Could not load subscription');

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      expect(find.text('Could not load subscription'), findsOneWidget);
    });

    testWidgets('shows empty invoice state', (tester) async {
      spyApi.invoices = [];

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

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

      expect(find.text('CORE - Aug 2026'), findsOneWidget);
      expect(find.text('CORE - Sep 2026'), findsOneWidget);
      expect(find.text('PAID'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
    });

    testWidgets('change plan dialog opens and shows plan options',
        (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Tap Change Plan
      await tester.tap(find.text('Change Plan'));
      await tester.pumpAndSettle();

      // Dialog should show plan options
      expect(find.text('Change Plan'), findsNWidgets(2)); // title + button
      expect(find.text('CURRENT'), findsOneWidget);
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

      // API was called
      expect(spyApi.lastChangePlanCall, isNotNull);
      expect(spyApi.lastChangePlanCall!['planId'], 'enterprise');
    });
  });
}
