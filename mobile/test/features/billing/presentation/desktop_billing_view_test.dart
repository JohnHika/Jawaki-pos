import 'dart:async';

import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/billing/domain/entitlement_service.dart';
import 'package:axon_pos/features/billing/presentation/desktop/desktop_billing_view.dart';
import 'package:axon_pos/features/billing/presentation/screens/subscription_billing_screen.dart';
import 'package:axon_pos/features/finance/presentation/desktop/desktop_figures_row.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/desktop_harness.dart';
import '../../../support/shot.dart';

DesktopBillingInvoice _invoice(
  String id,
  String date, {
  double amount = 3000,
  String status = 'Paid',
  Color color = DesignColors.success,
  String method = 'M-Pesa',
  String? reference,
  DesktopBillingAction? check,
}) =>
    DesktopBillingInvoice(
      id: id,
      description: 'CORE subscription',
      dateLabel: date,
      date: DateTime.parse(date.length == 10 ? date : '2026-01-01'),
      amount: amount,
      amountLabel: 'KES ${amount.toStringAsFixed(0)}',
      statusLabel: status,
      statusColor: color,
      method: method,
      reference: reference,
      check: check,
    );

Widget _view({
  List<DesktopBillingInvoice>? invoices,
  VoidCallback? onCheck,
  bool admin = true,
}) {
  return DesktopBillingView(
    onRefresh: () {},
    figures: const [
      DesktopFigure(label: 'Plan', value: 'CORE', hint: 'KES 3,000 a month'),
      DesktopFigure(label: 'Status', value: 'Active'),
      DesktopFigure(label: 'Next payment', value: 'Sep 20, 2026', hint: '13 days left'),
      DesktopFigure(
        label: 'Branches and users',
        value: '3 branches',
        hint: '10 users',
      ),
    ],
    notices: const [
      DesktopBillingNotice(
        'Showing saved billing details. Reconnect to confirm your current status.',
      ),
    ],
    renewal: const DesktopBillingRenewal(
      message:
          'A subscription payment is due. Pay securely by card or M-Pesa to keep every feature on.',
      primary: DesktopBillingAction(
        label: 'Pay subscription securely',
        icon: Icons.lock_rounded,
        onPressed: _noop,
      ),
      note:
          'Subscription payer email: owner@shop.co.ke. This is the signed-in shop account email.',
    ),
    planSummary: admin ? 'CORE · active subscription' : null,
    licence: admin
        ? const DesktopBillingLicence(
            modules: [
              (label: 'Sales and receipts', allowed: true),
              (label: 'Stock control', allowed: true),
              (label: 'Customer credit', allowed: true),
              (label: 'Multi-branch', allowed: false),
              (label: 'Reports', allowed: true),
              (label: 'AI assistant', allowed: false),
            ],
            limits: 'Up to 3 branches · 10 users',
            licenceKey: 'CB-1234-5678',
          )
        : null,
    autoRenew: admin
        ? DesktopBillingAutoRenew(
            enabled: true,
            summary: 'On — 254712345678',
            onConfigure: () {},
          )
        : null,
    onFreeDays: admin ? () {} : null,
    invoices: invoices ??
        [
          _invoice('inv-4', '2026-09-01',
              status: 'Pending',
              color: DesignColors.warning,
              method: 'Card',
              reference: 'PS-8842',
              check: DesktopBillingAction(
                label: 'Check payment',
                icon: Icons.refresh_rounded,
                onPressed: onCheck,
              )),
          _invoice('inv-3', '2026-08-01', reference: 'QGH7XY92K1'),
          _invoice('inv-2', '2026-07-01', reference: 'QFA1XY22K9'),
          _invoice('inv-1', '2026-06-01', reference: 'QCC9XY11K2'),
        ],
  );
}

void _noop() {}

class _FakeAuthService extends Fake implements AuthService {
  @override
  bool get isAuthenticated => true;
  @override
  bool get isLocked => false;
  @override
  bool get isLocalWorkspace => false;
  @override
  Map<String, dynamic>? get currentUser =>
      {'role': 'ADMIN', 'email': 'owner@shop.co.ke'};

  final _statusController = StreamController<AuthStatus>.broadcast();

  @override
  Stream<AuthStatus> get authStatusStream => _statusController.stream;
}

class _SpyApiClient extends ApiClient {
  _SpyApiClient() : super(Dio());

  List<dynamic> invoices = [
    {
      'id': 'inv-2',
      'plan': 'CORE',
      'amount': '3000.00',
      'currency': 'KES',
      'status': 'PENDING',
      'provider': 'PAYSTACK',
      'authorizationUrl': 'https://checkout.paystack.com/x',
      'date': '2026-09-01T00:00:00Z',
      'reference': 'PS-8842',
    },
    {
      'id': 'inv-1',
      'plan': 'CORE',
      'amount': 3000,
      'currency': 'KES',
      'status': 'PAID',
      'date': '2026-08-01T00:00:00Z',
      'reference': 'QGH7XY92K1',
    },
  ];
  final verified = <String>[];

  @override
  Future<Map<String, dynamic>> getBillingEntitlement() async => {
        'plan': 'CORE',
        'status': 'ACTIVE',
        'paidUntil': '2026-09-20T00:00:00Z',
        'daysRemaining': 13,
        'graceUntil': '2026-09-23T00:00:00Z',
        'features': {'maxBranches': 3, 'maxUsers': 10},
        'restrictedMode': false,
      };

  @override
  Future<List<dynamic>> getBillingInvoices() async => invoices;

  @override
  Future<Map<String, dynamic>> getBillingSettings() async => {
        'plan': 'CORE',
        'autoRenewEnabled': true,
        'billingPhone': '254712345678',
      };

  @override
  Future<Map<String, dynamic>> verifyPaystackSubscriptionPayment(
    String reference,
  ) async {
    verified.add(reference);
    return {'status': 'PENDING'};
  }
}

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('billing-desktop', () => _view(onCheck: () {}));
  shotMatrix('billing-desktop-staff', () => _view(admin: false));

  testWidgets('a row opens the invoice panel, Esc closes it', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    var checked = 0;
    await tester.pumpWidget(desktopApp(_view(onCheck: () => checked++)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('billing-invoice-inv-4')), findsNothing);
    await tester.ensureVisible(find.textContaining('PS-8842').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('PS-8842').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('billing-invoice-inv-4')), findsOneWidget);

    await tester.tap(find.text('Check payment'));
    expect(checked, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('billing-invoice-inv-4')), findsNothing);
  });

  testWidgets('an empty history says so and an error offers a retry',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_view(invoices: const [])));
    await tester.pumpAndSettle();
    expect(find.text('No invoices yet'), findsOneWidget);

    var retried = false;
    await tester.pumpWidget(desktopApp(DesktopBillingView(
      figures: const [],
      renewal: const DesktopBillingRenewal(message: 'x'),
      invoices: const [],
      invoiceError: 'Offline',
      onRetryInvoices: () => retried = true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  group('SubscriptionBillingScreen on a computer', () {
    late _SpyApiClient api;

    setUp(() {
      api = _SpyApiClient();
      SubscriptionBillingScreen.overrideIsAdmin = true;
      SharedPreferences.setMockInitialValues({});
      final getIt = GetIt.instance;
      if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
      getIt.registerSingleton<ApiClient>(api);
      if (getIt.isRegistered<EntitlementService>()) {
        getIt.unregister<EntitlementService>();
      }
      getIt.registerSingleton<EntitlementService>(EntitlementService());
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

    Widget screen() => const DesktopScope(
          sidebarCollapsed: true,
          child: ProviderScope(child: SubscriptionBillingScreen()),
        );

    testWidgets('shows figures, invoices and checks a pending card payment',
        (tester) async {
      useWindow(tester, desktopSizes['1366']!);
      await tester.pumpWidget(desktopApp(screen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Plan & billing'), findsOneWidget);
      expect(find.text('CORE'), findsWidgets);
      expect(find.text('13 days left'), findsOneWidget);
      expect(find.text('Up to 3 branches'), findsOneWidget);
      // A table, not phone cards: the string amount parsed and formatted.
      expect(find.text('KES 3,000'), findsWidgets);
      expect(find.text('Auto-renew'), findsOneWidget);
      expect(find.text('Pay subscription securely'), findsOneWidget);

      await tester.tap(find.textContaining('PS-8842').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check payment'));
      await tester.pumpAndSettle();
      expect(api.verified, ['PS-8842']);
    });

    testWidgets('fits the 125% laptop window without overflow',
        (tester) async {
      useWindow(tester, desktopSizes['1093']!);
      await tester.pumpWidget(desktopApp(screen(), dark: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
