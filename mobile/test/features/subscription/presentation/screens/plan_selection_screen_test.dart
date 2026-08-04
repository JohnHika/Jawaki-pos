import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/subscription/presentation/screens/plan_selection_screen.dart';

/// A manual ApiClient spy that records calls and returns canned data.
class _SpyApiClient extends ApiClient {
  _SpyApiClient() : super(Dio());

  Object? changePlanError;
  Map<String, dynamic>? lastChangePlanCall;

  @override
  Future<Map<String, dynamic>> changeSubscriptionPlan({
    required String planId,
  }) async {
    if (changePlanError != null) throw changePlanError!;
    lastChangePlanCall = {'planId': planId};
    return {'planId': planId, 'status': 'TRIAL'};
  }
}

GoRouter _router() => GoRouter(
      initialLocation: '/plan-selection',
      routes: [
        GoRoute(
          path: '/plan-selection',
          builder: (context, state) => PlanSelectionScreen(
            companyName: state.extra as String?,
          ),
        ),
        GoRoute(
          path: '/owner-welcome',
          builder: (context, state) => const Scaffold(
            body: Text('Owner Welcome'),
          ),
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

  tearDown(() {
    // Leave getIt as-is for other tests
  });

  group('PlanSelectionScreen', () {
    testWidgets('renders both plan cards with correct pricing',
        (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Header
      expect(find.text('AXON / SUBSCRIPTION'), findsOneWidget);
      expect(find.text('Choose your plan'), findsOneWidget);

      // Plan names
      expect(find.text('CORE'), findsOneWidget);
      expect(find.text('ENTERPRISE'), findsOneWidget);

      // Pricing — CORE plan shows KES 1500 (no comma from toStringAsFixed)
      expect(find.text('KES 3200'), findsOneWidget);
      expect(find.text('KES 5000'), findsOneWidget);

      // Popular badge
      expect(find.text('POPULAR'), findsOneWidget);

      // Scroll down to see the setup fee notice and button
      // Use the Scrollable finder to drag
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1000));
      await tester.pumpAndSettle();

      // Setup fee notice
      expect(find.text('One-time setup fee'), findsOneWidget);
      expect(find.text('KES 35,000'), findsOneWidget);

      // Action button
      expect(find.text('Start 14-Day Free Trial'), findsOneWidget);
    });

    testWidgets('shows CORE plan features', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // CORE features
      expect(find.text('Up to 1 branch'), findsOneWidget);
      expect(find.text('Up to 3 staff accounts'), findsOneWidget);
      expect(find.text('Basic sales & inventory'), findsOneWidget);
      expect(find.text('Daily sales reports'), findsOneWidget);
      expect(find.text('Email support'), findsOneWidget);
    });

    testWidgets('shows ENTERPRISE plan features', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // ENTERPRISE features
      expect(find.text('Unlimited branches'), findsOneWidget);
      expect(find.text('Unlimited staff accounts'), findsOneWidget);
      expect(find.text('Advanced inventory management'), findsOneWidget);
      expect(find.text('Analytics dashboard & forecasting'), findsOneWidget);
      expect(find.text('AI-powered insights'), findsOneWidget);
      expect(find.text('Priority phone & email support'), findsOneWidget);
      expect(find.text('Custom reports & data export'), findsOneWidget);
    });

    testWidgets('start trial button is disabled when no plan selected',
        (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Scroll down to reveal the button
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1000));
      await tester.pumpAndSettle();

      // The button should be present but disabled (no plan selected yet)
      final button = tester.widget<GradientButton>(
        find.byType(GradientButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('selecting a plan enables the trial button',
        (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Tap the CORE plan card
      await tester.tap(find.text('CORE').first);
      await tester.pumpAndSettle();

      // Scroll down to reveal the button
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1000));
      await tester.pumpAndSettle();

      // Button should now be enabled
      final button = tester.widget<GradientButton>(
        find.byType(GradientButton),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('tapping start trial with selected plan calls API and navigates',
        (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Select CORE plan
      await tester.tap(find.text('CORE').first);
      await tester.pumpAndSettle();

      // Scroll down and tap the trial button
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start 14-Day Free Trial'));
      await tester.pumpAndSettle();

      // Should navigate to owner-welcome
      expect(find.text('Owner Welcome'), findsOneWidget);

      // API was called with the correct plan
      expect(spyApi.lastChangePlanCall, isNotNull);
      expect(spyApi.lastChangePlanCall!['planId'], 'core');
    });

    testWidgets('shows error when API call fails', (tester) async {
      spyApi.changePlanError = Exception('Network error');

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      // Select CORE plan (visible at top)
      await tester.tap(find.text('CORE').first);
      await tester.pumpAndSettle();

      // Scroll down and tap the trial button
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start 14-Day Free Trial'));
      await tester.pumpAndSettle();

      // Error should be shown
      expect(find.text('Network error'), findsOneWidget);
    });

    testWidgets('shows company name when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/plan-selection',
            routes: [
              GoRoute(
                path: '/plan-selection',
                builder: (context, state) => const PlanSelectionScreen(
                  companyName: 'My Shop',
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('My Shop is ready. Pick a plan to begin your free trial.'),
        findsOneWidget,
      );
    });
  });
}
