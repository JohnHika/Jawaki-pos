import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/features/billing/domain/entitlement_service.dart';
import 'package:axon_pos/features/billing/presentation/screens/subscription_billing_screen.dart';

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
    'manualPaybill': {'phone': '0742126582', 'accountFormat': 'COMPANY-<id>'},
  };
  Object? submitError;
  Map<String, dynamic>? lastSubmitCall;
  Map<String, dynamic>? lastUpdateSettingsCall;

  @override
  Future<Map<String, dynamic>> getBillingEntitlement() async {
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
  }) async {
    lastUpdateSettingsCall = {
      if (autoRenewEnabled != null) 'autoRenewEnabled': autoRenewEnabled,
      if (billingPhone != null) 'billingPhone': billingPhone,
    };
    settingsData = {
      ...settingsData,
      if (autoRenewEnabled != null) 'autoRenewEnabled': autoRenewEnabled,
      if (billingPhone != null) 'billingPhone': billingPhone,
    };
    return settingsData;
  }

  @override
  Future<Map<String, dynamic>> submitSubscriptionPayment({
    required String mpesaCode,
    double? amount,
  }) async {
    lastSubmitCall = {'mpesaCode': mpesaCode, 'amount': amount};
    if (submitError != null) throw submitError!;
    return {
      'claimId': 'claim-1',
      'status': 'PENDING_CONFIRMATION',
      'message': 'Payment code received.',
    };
  }
}

void main() {
  late _SpyApiClient spyApi;

  setUp(() {
    spyApi = _SpyApiClient();
    SubscriptionBillingScreen.overrideIsAdmin = true;
    SharedPreferences.setMockInitialValues({});
    final getIt = GetIt.instance;
    if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
    getIt.registerSingleton<ApiClient>(spyApi);
    if (getIt.isRegistered<EntitlementService>()) {
      getIt.unregister<EntitlementService>();
    }
    getIt.registerSingleton<EntitlementService>(EntitlementService());
  });

  tearDown(() {
    SubscriptionBillingScreen.overrideIsAdmin = null;
    final getIt = GetIt.instance;
    if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
    if (getIt.isRegistered<EntitlementService>()) {
      getIt.unregister<EntitlementService>();
    }
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
      await tester.pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      expect(find.text('CORE'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('KES 3,200'), findsOneWidget);
      expect(find.textContaining('Next payment'), findsOneWidget);
      expect(find.textContaining('13 days remaining'), findsOneWidget);
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

      await tester.pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      expect(find.text('Past Due'), findsOneWidget);
      expect(find.textContaining('grace period'), findsOneWidget);
      expect(find.textContaining('Due for renewal'), findsOneWidget);
    });

    testWidgets('Pay with M-Pesa sheet: invoice summary, then code entry '
        'and submit', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pay with M-Pesa'));
      await tester.pumpAndSettle();

      // Step 1: invoice summary is visible.
      expect(find.text('Subscription'), findsWidgets);
      expect(find.text('Amount due'), findsOneWidget);
      expect(find.text('Paybill'), findsOneWidget);

      // Step 2: manual code entry path.
      await tester.enterText(
        find.widgetWithText(TextField, 'M-Pesa confirmation code'),
        'QGH7XY92K1',
      );
      await tester.tap(find.text('Submit Payment Code'));
      await tester.pumpAndSettle();

      expect(spyApi.lastSubmitCall, isNotNull);
      expect(spyApi.lastSubmitCall!['mpesaCode'], 'QGH7XY92K1');
      // Sheet closed after submit.
      expect(find.text('Submit Payment Code'), findsNothing);
    });

    testWidgets('auto-renew tile visible for admin and opens sheet',
        (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      expect(find.text('Auto-Renew'), findsOneWidget);

      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('Set up Auto-Renew'), findsOneWidget);
      expect(find.byIcon(Icons.autorenew_rounded), findsWidgets);

      // Toggle on and save.
      await tester.tap(find.byType(SwitchListTile));
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
          'amount': 3200,
          'currency': 'KES',
          'status': 'PAID',
          'date': '2026-08-01T00:00:00Z',
          'reference': 'QGH7XY92K1',
        },
        {
          'id': 'inv-2',
          'plan': 'CORE',
          'amount': 3200,
          'currency': 'KES',
          'status': 'PENDING',
          'date': '2026-09-01T00:00:00Z',
        },
      ];

      await tester.pumpWidget(MaterialApp.router(routerConfig: billingTestRouter()));
      await tester.pumpAndSettle();

      // Entitlement card is at the top of the list and shows the plan
      // price before any scrolling.
      expect(find.text('KES 3,200'), findsOneWidget);

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
      expect(find.text('KES 3,200'), findsNWidgets(2));
    });
  });
}