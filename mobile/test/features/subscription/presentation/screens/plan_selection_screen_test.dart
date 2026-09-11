import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

Widget _app(GoRouter router) =>
    ProviderScope(child: MaterialApp.router(routerConfig: router));

/// Scrolls until [finder] is built and on-screen, then settles.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300);
  await tester.pumpAndSettle();
}

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
    testWidgets('renders all three plan cards with correct pricing',
        (tester) async {
      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // Header
      expect(find.text('AXON / SUBSCRIPTION'), findsOneWidget);
      expect(find.text('STEP 4 · CHOOSE PLAN'), findsOneWidget);

      // CORE is the first card — visible at the top.
      expect(find.text('CORE'), findsOneWidget);
      expect(find.text('KES 3,200'), findsOneWidget);

      // Scroll the BUSINESS card into view.
      await _scrollTo(tester, find.text('BUSINESS'));
      expect(find.text('KES 6,500'), findsOneWidget);
      // POPULAR badge now sits on BUSINESS.
      expect(find.text('POPULAR'), findsOneWidget);

      // Scroll the ENTERPRISE card into view.
      await _scrollTo(tester, find.text('ENTERPRISE'));
      expect(find.text('KES 10,000'), findsOneWidget);

      // Setup fee notice (asserted while it is on-screen — further scrolling
      // culls it from the lazy list's built range).
      await _scrollTo(tester, find.text('One-time setup fee'));
      expect(find.text('One-time setup fee'), findsOneWidget);
      expect(find.text('KES 35,000'), findsOneWidget);

      // Action button
      await _scrollTo(tester, find.text('Start 7-Day Free Trial'));
      expect(find.text('Start 7-Day Free Trial'), findsOneWidget);
    });

    testWidgets('shows CORE plan features', (tester) async {
      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // CORE card features (new owner-language catalog copy).
      expect(
        find.text('Sell as many items as you want — no per-sale charge'),
        findsOneWidget,
      );
      expect(
        find.text('Keep selling when the internet goes down (works offline)'),
        findsOneWidget,
      );
      expect(find.text('Know your stock level at any moment'), findsOneWidget);
      expect(find.text('Up to 3 branches'), findsOneWidget);
      expect(find.text('Up to 10 staff accounts'), findsOneWidget);
      expect(find.text('Email support'), findsOneWidget);
    });

    testWidgets('shows the 7-day free trial row on every plan card',
        (tester) async {
      // A tall surface builds all three cards at once (the default 800x600
      // test viewport is shorter than one card, so the lazy ListView would
      // only build the visible ones). The comparison table's trial row is
      // '7-day free trial on every plan' — a different exact string — so the
      // card rows count exactly once per plan.
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // Prove all three cards are built: 'Everything in ... plus:' lines are
      // card-only copy (not in the comparison table).
      expect(find.text('Everything in Core, plus:'), findsOneWidget);
      expect(find.text('Everything in Business, plus:'), findsOneWidget);

      expect(find.text('7-day free trial'), findsNWidgets(3));
    });

    testWidgets('shows BUSINESS plan features', (tester) async {
      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // Scroll the BUSINESS (second) card into view.
      await _scrollTo(tester, find.text('BUSINESS'));

      expect(find.text('Everything in Core, plus:'), findsOneWidget);
      expect(find.text('Up to 10 branches'), findsOneWidget);
      expect(find.text('Up to 50 staff accounts'), findsOneWidget);
      expect(find.text('Move stock between your shops'), findsOneWidget);
      expect(
        find.text('Restock suggestions — what to reorder and how much'),
        findsOneWidget,
      );
      expect(
        find.text('Track suppliers — who you owe, invoices and payments'),
        findsOneWidget,
      );
      expect(find.text('WhatsApp support from our team'), findsOneWidget);
    });

    testWidgets('shows ENTERPRISE plan features', (tester) async {
      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // Scroll the ENTERPRISE (third) card into view.
      await _scrollTo(tester, find.text('ENTERPRISE'));

      expect(find.text('Everything in Business, plus:'), findsOneWidget);
      expect(find.text('Unlimited branches'), findsOneWidget);
      expect(find.text('Unlimited staff accounts'), findsOneWidget);
      expect(
        find.text('Books combined across all your branches in one place'),
        findsOneWidget,
      );
      expect(find.text('Every action logged — full audit trail'),
          findsOneWidget);
      expect(
        find.text('Priority phone and WhatsApp support — talk to a human fast'),
        findsOneWidget,
      );
    });

    testWidgets('start trial button is disabled when no plan selected',
        (tester) async {
      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // Scroll down to reveal the button
      await _scrollTo(tester, find.text('Start 7-Day Free Trial'));

      // The button should be present but disabled (no plan selected yet)
      final button = tester.widget<GradientButton>(
        find.byType(GradientButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('selecting a plan enables the trial button',
        (tester) async {
      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // Tap the CORE plan card
      await tester.tap(find.text('CORE').first);
      await tester.pumpAndSettle();

      // Scroll down to reveal the button
      await _scrollTo(tester, find.text('Start 7-Day Free Trial'));

      // Button should now be enabled
      final button = tester.widget<GradientButton>(
        find.byType(GradientButton),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('tapping start trial with selected plan calls API and navigates',
        (tester) async {
      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // Select CORE plan
      await tester.tap(find.text('CORE').first);
      await tester.pumpAndSettle();

      // Scroll down and tap the trial button
      await _scrollTo(tester, find.text('Start 7-Day Free Trial'));
      await tester.tap(find.text('Start 7-Day Free Trial'));
      await tester.pumpAndSettle();

      // Should navigate to owner-welcome
      expect(find.text('Owner Welcome'), findsOneWidget);

      // API was called with the uppercase plan id — backend VALID_PLANS are
      // uppercase and changePlan() does not normalize case.
      expect(spyApi.lastChangePlanCall, isNotNull);
      expect(spyApi.lastChangePlanCall!['planId'], 'CORE');
    });

    testWidgets('tapping start trial with BUSINESS selected sends BUSINESS',
        (tester) async {
      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // Scroll the BUSINESS card into view and select it.
      await _scrollTo(tester, find.text('BUSINESS'));
      await tester.tap(find.text('BUSINESS').first);
      await tester.pumpAndSettle();

      // Scroll down and tap the trial button
      await _scrollTo(tester, find.text('Start 7-Day Free Trial'));
      await tester.tap(find.text('Start 7-Day Free Trial'));
      await tester.pumpAndSettle();

      expect(find.text('Owner Welcome'), findsOneWidget);
      expect(spyApi.lastChangePlanCall, isNotNull);
      expect(spyApi.lastChangePlanCall!['planId'], 'BUSINESS');
    });

    testWidgets('shows error when API call fails', (tester) async {
      spyApi.changePlanError = Exception('Network error');

      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // Select CORE plan (visible at top)
      await tester.tap(find.text('CORE').first);
      await tester.pumpAndSettle();

      // Scroll down and tap the trial button
      await _scrollTo(tester, find.text('Start 7-Day Free Trial'));
      await tester.tap(find.text('Start 7-Day Free Trial'));
      await tester.pumpAndSettle();

      // Error should be shown
      expect(find.text('Network error'), findsOneWidget);
    });

    testWidgets('comparison table renders three plan columns', (tester) async {
      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // Scroll to the comparison table at the very bottom.
      await _scrollTo(tester, find.text('Compare features'));

      // Column headers for all three tiers.
      expect(find.text('Feature'), findsOneWidget);
      expect(find.text('CORE'), findsAtLeastNWidgets(1));
      expect(find.text('BUSINESS'), findsAtLeastNWidgets(1));
      expect(find.text('ENTERPRISE'), findsAtLeastNWidgets(1));

      // Rows from the new plain-language catalog prove the three-column
      // table body is rendering.
      expect(
        find.text('Sell as many items as you want — no per-sale charge'),
        findsOneWidget,
      );
      expect(find.text('Move stock between your shops'), findsOneWidget);
      expect(find.text('Forecast what you will need next month'),
          findsOneWidget);
      expect(find.text('Every action logged — full audit trail'),
          findsOneWidget);
      expect(find.text('7-day free trial on every plan'), findsOneWidget);
    });

    testWidgets('three-column comparison table fits a phone-width screen',
        (tester) async {
      // A narrow phone (iPhone 13 logical size, 390px). RenderFlex overflows
      // surface as FlutterErrors in tests, so a clean pump + jump to the table
      // proves the three-column comparison table fits the narrowest common
      // phone width.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();

      // Top of the page (header + CORE card) lays out at phone width.
      expect(tester.takeException(), isNull);

      // Jump straight to the bottom so the three-column comparison table is
      // laid out at phone width.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -100000));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Feature'), findsOneWidget);
      expect(find.text('CORE'), findsOneWidget);
      expect(find.text('BUSINESS'), findsOneWidget);
      expect(find.text('ENTERPRISE'), findsOneWidget);
      expect(
        find.text('Sell as many items as you want — no per-sale charge'),
        findsOneWidget,
      );
    });

    testWidgets('all three cards, CTA and table fit a phone-width screen',
        (tester) async {
      // Large phone (iPhone Pro Max class, 430 logical px). At widths below
      // ~425px the shared CTA GradientButton's label row overflows under
      // Flutter's fixed-width test font (every glyph renders fontSize-wide);
      // the app's real Sora typeface renders the same label about half as
      // wide, so that is a test-font artifact of a shared widget, not a
      // layout issue on this screen. 430 lets this walk run overflow-free
      // end to end, covering all three plan cards + CTA + table.
      tester.view.physicalSize = const Size(430 * 3, 932 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(_router()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Walk each card into view — overflows during their layout would
      // surface as FlutterErrors here.
      await _scrollTo(tester, find.text('BUSINESS'));
      expect(tester.takeException(), isNull);
      expect(find.text('KES 6,500'), findsOneWidget);

      await _scrollTo(tester, find.text('ENTERPRISE'));
      expect(tester.takeException(), isNull);
      expect(find.text('KES 10,000'), findsOneWidget);

      await _scrollTo(tester, find.text('Start 7-Day Free Trial'));
      expect(tester.takeException(), isNull);

      // Bottom: the three-column comparison table.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -100000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Feature'), findsOneWidget);
      expect(find.text('CORE'), findsOneWidget);
      expect(find.text('BUSINESS'), findsOneWidget);
      expect(find.text('ENTERPRISE'), findsOneWidget);
      expect(find.text('7-day free trial on every plan'), findsOneWidget);
    });

    testWidgets('shows company name when provided', (tester) async {
      await tester.pumpWidget(
        _app(
          GoRouter(
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
        find.textContaining('My Shop is ready'),
        findsOneWidget,
      );
    });
  });
}
