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

  Map<String, dynamic> planData = {
    'planId': 'core',
    'planName': 'CORE',
    'status': 'TRIAL',
    'trialEndsAt': '2026-09-04T00:00:00Z',
    'nextBillingDate': '2026-09-04T00:00:00Z',
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
    planData['planId'] = planId;
    planData['planName'] = planId == 'enterprise' ? 'ENTERPRISE' : 'CORE';
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
        'planId': 'enterprise',
        'planName': 'ENTERPRISE',
        'status': 'ACTIVE',
        'nextBillingDate': '2026-09-04T00:00:00Z',
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
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Tap Change Plan
      await tester.tap(find.text('Change Plan'));
      await tester.pumpAndSettle();

      // Select ENTERPRISE
      await tester.tap(find.text('ENTERPRISE').last);
      await tester.pumpAndSettle();

      // The GradientButton is in the dialog — tap by its label text
      // Pump a few frames to let the dialog layout settle
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.tap(find.text('Change to ENTERPRISE'));
      await tester.pumpAndSettle();

      // API was called
      expect(spyApi.lastChangePlanCall, isNotNull);
      expect(spyApi.lastChangePlanCall!['planId'], 'enterprise');
    });
  });
}
