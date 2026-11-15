import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/billing/domain/billing_entitlement.dart';
import 'package:axon_pos/features/billing/domain/billing_snapshot.dart';
import 'package:axon_pos/features/billing/domain/entitlement_service.dart';
import 'package:axon_pos/features/billing/presentation/providers/entitlement_provider.dart';
import 'package:axon_pos/features/billing/presentation/screens/subscription_billing_screen.dart';
import 'package:axon_pos/features/subscription/domain/subscription_plans.dart';

class _FakeAuthService extends Fake implements AuthService {
  @override
  bool get isAuthenticated => true;
  @override
  bool get isLocked => false;
  // Cloud workspace: refreshEntitlement must do the live fetch.
  @override
  bool get isLocalWorkspace => false;
  @override
  Map<String, dynamic>? get currentUser => {'role': 'ADMIN'};

  final _statusController = StreamController<AuthStatus>.broadcast();

  @override
  Stream<AuthStatus> get authStatusStream => _statusController.stream;
}

/// Manual ApiClient spy that records calls and returns canned data.
class _SpyApiClient extends ApiClient {
  _SpyApiClient() : super(Dio());

  Map<String, dynamic> entitlementData = {
    'plan': 'CORE',
    'status': 'ACTIVE',
    'paidUntil': '2026-09-20T00:00:00Z',
    'daysRemaining': 13,
    'graceUntil': '2026-09-23T00:00:00Z',
    'features': {'maxBranches': 3, 'maxUsers': 10},
    'restrictedMode': false,
  };
  List<dynamic> invoices = [];
  Map<String, dynamic> settingsData = {
    'plan': 'CORE',
    'autoRenewEnabled': false,
    'billingPhone': '254712345678',
    'subscriptionStatus': 'ACTIVE',
    'currentPeriodEnd': '2026-09-20T00:00:00Z',
    'graceDays': 3,
  };
  Map<String, dynamic>? lastUpdateSettingsCall;
  Map<String, dynamic> paystackVerificationResult = {'status': 'PENDING'};

  @override
  Future<Map<String, dynamic>> verifyPaystackSubscriptionPayment(
    String reference,
  ) async {
    if (paystackVerificationResult['status'] == 'NEEDS_REVIEW') {
      invoices = invoices.map((rawInvoice) {
        final invoice = Map<String, dynamic>.from(rawInvoice as Map);
        if (invoice['reference'] == reference) {
          invoice['status'] = 'NEEDS_REVIEW';
          invoice['authorizationUrl'] = null;
        }
        return invoice;
      }).toList();
    }
    return paystackVerificationResult;
  }

  Map<String, dynamic> planData = {
    'plan': 'CORE',
    'subscriptionStatus': 'ACTIVE',
    'pendingChange': null,
    'availablePlans': [
      {'planId': 'TRIAL', 'monthlyAmountKes': 0},
      {'planId': 'CORE', 'monthlyAmountKes': 3000},
      {'planId': 'BUSINESS', 'monthlyAmountKes': 5000},
      {'planId': 'ENTERPRISE', 'monthlyAmountKes': 9999},
    ],
  };
  int entitlementCalls = 0;
  Completer<void>? entitlementGate;
  Object? entitlementError;
  final List<String> changedTo = [];
  int cancelCalls = 0;

  int checkoutRequests = 0;

  @override
  Future<Map<String, dynamic>> initializePaystackSubscriptionPayment() async {
    checkoutRequests++;
    // A link that is not the hosted checkout, as a dead one would be.
    return {'status': 'PENDING', 'authorizationUrl': 'http://example.invalid/x'};
  }

  @override
  Future<Map<String, dynamic>> getSubscriptionPlan() async => planData;

  @override
  Future<Map<String, dynamic>> acceptLegalPolicy({
    required String policyType,
    required String policyVersion,
  }) async =>
      {};

  @override
  Future<Map<String, dynamic>> changeSubscriptionPlan({
    required String planId,
  }) async {
    changedTo.add(planId);
    return {'pendingPlan': planId};
  }

  @override
  Future<Map<String, dynamic>> cancelSubscriptionPlanChange() async {
    cancelCalls++;
    planData = {...planData, 'pendingChange': null};
    return {'pendingChange': null};
  }

  @override
  Future<Map<String, dynamic>> getBillingEntitlement() async {
    entitlementCalls++;
    final gate = entitlementGate;
    if (gate != null) await gate.future;
    final err = entitlementError;
    if (err != null) throw err;
    return entitlementData;
  }

  @override
  Future<List<dynamic>> getBillingInvoices() async => invoices;

  @override
  Future<Map<String, dynamic>> getBillingSettings() async => settingsData;

  @override
  Future<Map<String, dynamic>> updateBillingSettings({
    bool? autoRenewEnabled,
    String? billingPhone,
    String? autoRenewAuthorizationVersion,
  }) async {
    lastUpdateSettingsCall = {
      if (autoRenewEnabled != null) 'autoRenewEnabled': autoRenewEnabled,
      if (billingPhone != null) 'billingPhone': billingPhone,
      if (autoRenewAuthorizationVersion != null)
        'autoRenewAuthorizationVersion': autoRenewAuthorizationVersion,
    };
    settingsData = {
      ...settingsData,
      if (autoRenewEnabled != null) 'autoRenewEnabled': autoRenewEnabled,
      if (billingPhone != null) 'billingPhone': billingPhone,
    };
    return settingsData;
  }
}

void main() {
  late _SpyApiClient spyApi;

  setUp(() {
    spyApi = _SpyApiClient();
    SubscriptionBillingScreen.overrideIsAdmin = true;
    SharedPreferences.setMockInitialValues({});
    resetEntitlementMemory();
    PlanPrices.reset();
    final getIt = GetIt.instance;
    if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
    getIt.registerSingleton<ApiClient>(spyApi);
    if (getIt.isRegistered<EntitlementService>()) {
      getIt.unregister<EntitlementService>();
    }
    getIt.registerSingleton<EntitlementService>(EntitlementService());
    // a8bef26: refreshEntitlement() checks AuthService.isLocalWorkspace
    // before fetching; register a cloud-workspace fake so the live fetch runs.
    if (getIt.isRegistered<AuthService>()) getIt.unregister<AuthService>();
    getIt.registerSingleton<AuthService>(_FakeAuthService());
  });

  tearDown(() {
    SubscriptionBillingScreen.overrideIsAdmin = null;
    final getIt = GetIt.instance;
    if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
    if (getIt.isRegistered<EntitlementService>()) {
      getIt.unregister<EntitlementService>();
    }
    if (getIt.isRegistered<AuthService>()) getIt.unregister<AuthService>();
  });

  GoRouter billingTestRouter() => GoRouter(
        initialLocation: '/billing',
        routes: [
          GoRoute(
            path: '/billing',
            builder: (context, state) =>
                const ProviderScope(child: SubscriptionBillingScreen()),
          ),
        ],
      );

  group('SubscriptionBillingScreen', () {
    testWidgets('shows plan, status badge and days remaining after load',
        (tester) async {
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      expect(find.text('CORE'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('KES 3,000'), findsOneWidget);
      expect(find.textContaining('Next payment'), findsOneWidget);
      // Shown once, in the progress bar (no duplicate text row).
      expect(find.textContaining('13 days remaining'), findsNothing);
      expect(find.text('13'), findsOneWidget);
      expect(find.text('DAYS REMAINING'), findsOneWidget);
    });

    testWidgets('shows PAST_DUE grace notice for past-due status',
        (tester) async {
      spyApi.entitlementData = {
        ...spyApi.entitlementData,
        'status': 'PAST_DUE',
        'daysRemaining': -2,
        'restrictedMode': false,
      };

      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      expect(find.text('Past Due'), findsOneWidget);
      expect(find.textContaining('grace period'), findsOneWidget);
      // An older server sent -2 here. It must never reach the screen.
      expect(find.textContaining('Overdue by 2 days'), findsOneWidget);
      expect(find.text('OVERDUE'), findsOneWidget);
      expect(find.text('-2'), findsNothing);
      expect(find.text('DAYS REMAINING'), findsNothing);
    });

    testWidgets(
        'a lapsed period from the current server reads as overdue, not negative',
        (tester) async {
      spyApi.entitlementData = {
        ...spyApi.entitlementData,
        'status': 'PAST_DUE',
        'daysRemaining': 0,
        'daysOverdue': 1,
        'restrictedMode': false,
      };

      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Overdue by 1 day'), findsOneWidget);
      expect(find.textContaining('Overdue by 1 days'), findsNothing);
    });

    testWidgets(
        'overdue subscriptions use provider checkout without manual code entry',
        (tester) async {
      spyApi.entitlementData = {
        ...spyApi.entitlementData,
        'status': 'PAST_DUE',
        'daysRemaining': -1,
        'restrictedMode': true,
      };
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      expect(find.text('Pay subscription securely'), findsOneWidget);
      expect(find.text('M-Pesa confirmation code'), findsNothing);
      expect(find.text('Paybill'), findsNothing);
      expect(find.text('Submit Payment Code'), findsNothing);
    });

    testWidgets(
        'a payment held for review cannot be retried from the billing page',
        (tester) async {
      spyApi.invoices = [
        {
          'id': 'inv-review',
          'plan': 'CORE',
          'amount': 3000,
          'currency': 'KES',
          'status': 'NEEDS_REVIEW',
          'provider': 'PAYSTACK',
          'reference': 'AXON-SUB-review',
        },
      ];

      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      expect(
          find.textContaining('on hold for a payment review'), findsOneWidget);
      expect(find.text('Pay subscription securely'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('NEEDS REVIEW'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('NEEDS REVIEW'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('verification reports a mismatch as a review hold, not pending',
        (tester) async {
      spyApi.paystackVerificationResult = {'status': 'NEEDS_REVIEW'};
      spyApi.invoices = [
        {
          'id': 'inv-pending-review',
          'plan': 'CORE',
          'amount': 3000,
          'currency': 'KES',
          'status': 'PENDING',
          'provider': 'PAYSTACK',
          'authorizationUrl': 'https://checkout.paystack.com/example',
          'reference': 'AXON-SUB-review-check',
        },
      ];

      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Check payment'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Check payment'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Payment is on hold for a billing review'),
        findsOneWidget,
      );
      expect(
          find.text(
              'Payment is still being confirmed. Refresh again in a moment.'),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('auto-renew tile visible for admin and opens sheet',
        (tester) async {
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      // Below the fold on the small test viewport, so bring it into view.
      await tester.scrollUntilVisible(find.text('Auto-Renew'), 200);
      expect(find.text('Auto-Renew'), findsOneWidget);

      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('Set up Auto-Renew'), findsOneWidget);
      expect(find.byIcon(Icons.autorenew_rounded), findsWidgets);

      // Toggle on and save.
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining('I authorize monthly M-Pesa STK prompts'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(spyApi.lastUpdateSettingsCall, isNotNull);
      expect(spyApi.lastUpdateSettingsCall!['autoRenewEnabled'], isTrue);
    });

    testWidgets('invoice history renders with status chip and M-Pesa ref',
        (tester) async {
      spyApi.invoices = [
        {
          'id': 'inv-1',
          'plan': 'CORE',
          'amount': 3000,
          'currency': 'KES',
          'status': 'PAID',
          'date': '2026-08-01T00:00:00Z',
          'reference': 'QGH7XY92K1',
        },
        {
          'id': 'inv-2',
          'plan': 'CORE',
          'amount': 3000,
          'currency': 'KES',
          'status': 'PENDING',
          'date': '2026-09-01T00:00:00Z',
        },
      ];

      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      // Entitlement card is at the top of the list and shows the plan
      // price before any scrolling.
      expect(find.text('KES 3,000'), findsOneWidget);

      // Status chips and the M-Pesa reference render inside the invoice
      // list; scroll the invoice section into view — the added Plan and
      // Renewal sections push it below the fold in the test viewport,
      // which also scrolls the entitlement card (and its price) out of
      // the built widget tree.
      await tester.scrollUntilVisible(
        find.text('PAID'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('PAID'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('PENDING'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.textContaining('QGH7XY92K1'), findsOneWidget);
      // Both invoice rows show the plan price (entitlement card is
      // scrolled out of view by this point).
      expect(find.text('KES 3,000'), findsNWidgets(2));
    });

    // The live server serialises money (Prisma Decimal) as a string such as
    // "3000.00". Casting that to a number threw while building the list, and a
    // release build paints a build error as a plain grey screen.
    testWidgets('invoice amounts sent as strings render instead of crashing',
        (tester) async {
      spyApi.invoices = [
        {
          'id': 'inv-1',
          'plan': 'CORE',
          'amount': '3000.00',
          'currency': 'KES',
          'status': 'PAID',
          'createdAt': '2026-08-01T00:00:00.000Z',
          'mpesaReference': 'QGH7XY92K1',
        },
        {
          'id': 'inv-2',
          'plan': 'CORE',
          'amount': '3000.00',
          'currency': 'KES',
          'status': 'PENDING',
          'createdAt': '2026-09-01T00:00:00.000Z',
        },
      ];

      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('PAID'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('PAID'), findsOneWidget);
      expect(find.text('KES 3,000'), findsWidgets);
    });
  });

  group('loading without racing', () {
    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets(
        'shows a skeleton, never "reconnect", while the first load is running',
        (tester) async {
      tall(tester);
      spyApi.entitlementGate = Completer<void>();
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('billing-skeleton')), findsOneWidget);
      expect(find.textContaining('Reconnect'), findsNothing);
      expect(find.textContaining('could not load your plan'), findsNothing);

      spyApi.entitlementGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('billing-skeleton')), findsNothing);
      expect(find.text('CORE'), findsWidgets);
      expect(find.textContaining('Reconnect'), findsNothing);
    });

    testWidgets('a failed refresh keeps the plan that was already on screen',
        (tester) async {
      tall(tester);
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();
      expect(find.text('Active'), findsOneWidget);

      spyApi.entitlementError = DioException(
        requestOptions: RequestOptions(path: '/billing/entitlement'),
        type: DioExceptionType.connectionError,
      );
      // Pull to refresh.
      unawaited(tester
          .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
          .show());
      await tester.pumpAndSettle();
      expect(spyApi.entitlementCalls, 2);

      // Still the confirmed plan, now marked as saved, with a Retry.
      expect(find.text('CORE'), findsWidgets);
      expect(find.text('Active'), findsOneWidget);
      expect(find.textContaining('last saved billing details'), findsOneWidget);
      expect(find.byKey(const ValueKey('billing-notice-retry')), findsOneWidget);
      expect(find.textContaining('could not load your plan'), findsNothing);
    });

    test('simultaneous refreshes share one request', () async {
      spyApi.entitlementGate = Completer<void>();
      final first = refreshEntitlement();
      final second = refreshEntitlement();
      spyApi.entitlementGate!.complete();
      final results = await Future.wait([first, second]);

      expect(spyApi.entitlementCalls, 1);
      expect(results[0]!.plan, 'CORE');
      expect(results[1]!.plan, 'CORE');
    });

    test('a failed refresh falls back to the last confirmed answer, not null',
        () async {
      await refreshEntitlement();
      spyApi.entitlementError = DioException(
        requestOptions: RequestOptions(path: '/billing/entitlement'),
        response: Response(
          requestOptions: RequestOptions(path: '/billing/entitlement'),
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );

      final again = await refreshEntitlement();

      expect(again, isNotNull);
      expect(again!.plan, 'CORE');
      expect(again.source, EntitlementSource.offlineCache);
    });

    test('the signed offline copy is readable after a live fetch', () async {
      final now = DateTime.now();
      spyApi.entitlementData = {
        ...spyApi.entitlementData,
        'paidUntil': now.add(const Duration(days: 13)).toUtc().toIso8601String(),
        'graceUntil': now.add(const Duration(days: 16)).toUtc().toIso8601String(),
      };
      await refreshEntitlement();
      // Cold start with the network down: nothing in memory, only the disk.
      resetEntitlementMemory();
      spyApi.entitlementError = DioException(
        requestOptions: RequestOptions(path: '/billing/entitlement'),
        type: DioExceptionType.connectionError,
      );

      final offline = await refreshEntitlement();

      expect(offline, isNotNull);
      expect(offline!.plan, 'CORE');
      expect(offline.status, 'ACTIVE');
      expect(offline.maxBranches, 3);
      expect(offline.source, EntitlementSource.offlineCache);
    });

    testWidgets('a young saved copy paints at once and needs no request',
        (tester) async {
      tall(tester);
      await const BillingSnapshotStore().save(
        null,
        BillingSnapshot(
          savedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          entitlement: BillingEntitlement.fromMap(spyApi.entitlementData).toMap(),
          plan: spyApi.planData,
        ),
      );
      spyApi.entitlementGate = Completer<void>();

      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('CORE'), findsWidgets);
      expect(find.text('Active'), findsOneWidget);
      expect(spyApi.entitlementCalls, 0);
      await tester.pumpAndSettle();
      expect(spyApi.entitlementCalls, 0);
    });

    testWidgets('an older saved copy shows first, then refreshes behind it',
        (tester) async {
      tall(tester);
      await const BillingSnapshotStore().save(
        null,
        BillingSnapshot(
          savedAt: DateTime.now().subtract(const Duration(minutes: 30)),
          entitlement: BillingEntitlement.fromMap(spyApi.entitlementData).toMap(),
          plan: spyApi.planData,
        ),
      );
      spyApi.entitlementGate = Completer<void>();

      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pump(const Duration(milliseconds: 100));

      // On screen before the server has answered.
      expect(find.text('CORE'), findsWidgets);
      expect(find.byKey(const ValueKey('billing-skeleton')), findsNothing);
      expect(spyApi.entitlementCalls, 1);

      spyApi.entitlementGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('CORE'), findsWidgets);
    });
  });

  group('managing the plan', () {
    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('Manage plan opens the other plans on an active subscription',
        (tester) async {
      tall(tester);
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('manage-plan-tile')));
      await tester.pumpAndSettle();

      expect(find.text('Change your plan'), findsOneWidget);
      expect(find.text('Current plan'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-tile-business')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-tile-enterprise')), findsOneWidget);
      // Prices come from the server's table.
      expect(find.text('KES 5,000'), findsOneWidget);
      expect(find.text('KES 9,999'), findsOneWidget);
    });

    testWidgets('an upgrade says when it takes effect and then confirms it',
        (tester) async {
      tall(tester);
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('manage-plan-tile')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('plan-tile-business')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Takes effect at your next renewal on'),
        findsOneWidget,
      );
      // Nothing is saved until the terms are accepted.
      final confirm = find.byKey(const ValueKey('plan-change-confirm'));
      expect(tester.widget<SettingsPrimaryButton>(confirm).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('plan-terms-checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(spyApi.changedTo, ['BUSINESS']);
      expect(find.byKey(const ValueKey('plan-change-done')), findsOneWidget);
      expect(find.text('Upgrade to BUSINESS scheduled'), findsOneWidget);
    });

    testWidgets('a lower plan is offered as a downgrade', (tester) async {
      tall(tester);
      spyApi.entitlementData = {...spyApi.entitlementData, 'plan': 'BUSINESS'};
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('manage-plan-tile')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('plan-tile-core')));
      await tester.pumpAndSettle();

      expect(find.text('Downgrade to CORE'), findsOneWidget);
      expect(find.textContaining('You keep BUSINESS until then'), findsOneWidget);
    });

    testWidgets('a scheduled change shows a banner that can be cancelled',
        (tester) async {
      tall(tester);
      spyApi.entitlementData = {...spyApi.entitlementData, 'plan': 'BUSINESS'};
      spyApi.planData = {
        ...spyApi.planData,
        'plan': 'BUSINESS',
        'pendingChange': {
          'plan': 'CORE',
          'effectiveAt': '2026-12-01T00:00:00.000Z',
          'direction': 'DOWNGRADE',
        },
      };
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('scheduled-change-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('Switching to CORE'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('cancel-scheduled-change')));
      await tester.pumpAndSettle();

      expect(spyApi.cancelCalls, 1);
      expect(
        find.byKey(const ValueKey('scheduled-change-banner')),
        findsNothing,
      );
    });

    testWidgets('a checkout that cannot be opened offers a fresh link',
        (tester) async {
      tall(tester);
      spyApi.entitlementData = {
        ...spyApi.entitlementData,
        'status': 'PAST_DUE',
        'restrictedMode': true,
      };
      await tester
          .pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pay subscription securely'));
      await tester.pumpAndSettle();

      expect(spyApi.checkoutRequests, 1);
      expect(find.textContaining('could not open the secure checkout'),
          findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      // Asking again is what fetches the replacement link.
      expect(spyApi.checkoutRequests, 2);
    });
  });
}
