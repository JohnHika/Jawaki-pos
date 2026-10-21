import 'package:aca/core/permissions.dart';
import 'package:aca/data/api_client.dart';
import 'package:aca/data/models.dart';
import 'package:aca/features/overview/overview_screen.dart';
import 'package:aca/features/tenants/tenant_changes.dart';
import 'package:aca/features/tenants/tenant_detail_screen.dart';
import 'package:aca/features/tenants/tenants_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tenants_screen_test.dart' show TestEnv, detailJson, harness, makeEnv, settle, tenantJson, usePhone;

Map<String, dynamic> overviewJson({
  num collected30 = 3200,
  num collectedPrev30 = 38200,
  List<num> months = const [0, 0, 0, 3200, 38200, 3200],
  bool withAttention = true,
  bool withExpiring = true,
  bool withPayments = true,
  Map<String, int>? versions,
  int devices = 12,
  int active24h = 9,
}) {
  final labels = ['2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10'];
  final ver = versions ?? {'1.0.74': 7, '1.0.70': 3, '1.0.9': 1, 'unknown': 1};
  return {
    'generatedAt': DateTime.now().subtract(const Duration(minutes: 2)).toUtc().toIso8601String(),
    'tenants': {
      'total': 27,
      'byStatus': {'ACTIVE': 20, 'TRIAL': 3, 'PAST_DUE': 2, 'SUSPENDED': 0, 'CANCELLED': 2},
      'newLast30Days': 3,
      'byActivation': {'PAID': 24, 'PENDING': 3},
    },
    'revenue': {
      'mrrKes': 3200,
      'arrKes': 38400,
      'collectedLast30DaysKes': collected30,
      'collectedPrevious30DaysKes': collectedPrev30,
      'monthly': [
        for (var i = 0; i < months.length; i++) {'month': labels[i], 'amountKes': months[i]},
      ],
    },
    'billing': {
      'pendingInvoices': 4,
      'overdueInvoices': 1,
      'pendingClaims': 2,
      'recentPayments': withPayments
          ? [
              {
                'id': 'p1',
                'tenantId': 'tenant-1',
                'tenantName': 'Mart Fixture',
                'plan': 'CREDIT',
                'amount': '-100',
                'paidAt': DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
                'provider': 'CREDIT',
                'reference': 'CREDIT:goodwill',
              },
              {
                'id': 'p2',
                'tenantId': 'tenant-2',
                'tenantName': 'Pharmacy Fixture With A Pretty Long Registered Name',
                'plan': 'CORE',
                'amount': '35000',
                'paidAt': DateTime.now().subtract(const Duration(days: 3)).toUtc().toIso8601String(),
                'provider': 'PAYSTACK',
                'reference': 'REF',
              },
            ]
          : [],
    },
    'expiringSoon': withExpiring
        ? [
            {
              'id': 'tenant-3',
              'name': 'Hardware Fixture',
              'plan': 'TRIAL',
              'subscriptionStatus': 'TRIAL',
              'currentPeriodEnd': DateTime.now().add(const Duration(days: 5)).toUtc().toIso8601String(),
              'daysLeft': 5,
            },
          ]
        : [],
    'needsAttention': withAttention
        ? [
            {
              'id': 'tenant-2',
              'name': 'Pharmacy Fixture With A Pretty Long Registered Name',
              'plan': 'CORE',
              'subscriptionStatus': 'PAST_DUE',
              'currentPeriodEnd': DateTime.now().subtract(const Duration(days: 3)).toUtc().toIso8601String(),
              'daysLeft': 0,
            },
          ]
        : [],
    'fleet': {
      'devices': devices,
      'activeLast24h': active24h,
      'appVersions': [
        for (final e in ver.entries) {'version': e.key, 'devices': e.value},
      ],
    },
  };
}

void main() {
  late TestEnv env;

  Future<void> open(WidgetTester tester, Map<String, dynamic> json, {Widget? home}) async {
    usePhone(tester);
    env.repo.overviewData = Overview.fromJson(json);
    await tester.pumpWidget(harness(env, home ?? const OverviewScreen()));
    await settle(tester);
  }

  /// Scrolls the whole page so every section is built (the list is lazy).
  Future<void> scrollThrough(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await settle(tester);
    }
  }

  /// Scrolls the page until [finder] is on screen.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    await settle(tester);
  }

  setUp(() async {
    env = await makeEnv();
  });

  testWidgets('shows MRR, the collected delta and the greeting for the signed-in person', (tester) async {
    await open(tester, overviewJson());
    expect(find.text('KES 3,200'), findsWidgets);
    expect(find.text('KES 38,400 a year (ARR)'), findsOneWidget);
    expect(find.text('Collected last 30 days'), findsOneWidget);
    expect(find.text('−92%'), findsOneWidget);
    expect(find.text('Previous 30 days: KES 38,200'), findsOneWidget);
    expect(find.textContaining(RegExp(r'Good (morning|afternoon|evening), Amina$')), findsOneWidget);
    expect(find.textContaining('Wanjiku'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides the delta chip when there is no previous period to compare with', (tester) async {
    await open(tester, overviewJson(collected30: 5000, collectedPrev30: 0));
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('nothing to compare'), findsOneWidget);
  });

  testWidgets('every section renders at 360 dp and 1.3x text without overflowing', (tester) async {
    await open(tester, overviewJson());
    await scrollThrough(tester);
    expect(find.text('Updated 2 min ago'), findsOneWidget);
    expect(find.text('RECENT PAYMENTS'), findsOneWidget);
    expect(find.text('Credit · 2 h ago'), findsOneWidget);
    expect(find.text('−KES 100'), findsOneWidget);
    expect(find.text('KES 35,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('company tiles come from byStatus and a zero count is not alarming', (tester) async {
    await open(tester, overviewJson());
    expect(find.text('27'), findsOneWidget);
    expect(find.text('+3 new'), findsOneWidget);
    expect(find.text('in last 30 days'), findsOneWidget);
    expect(find.text('2 cancelled'), findsOneWidget);
    expect(find.text('20'), findsOneWidget); // active
    expect(find.text('Suspended'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('tapping a status tile opens the Clients list on that filter', (tester) async {
    env.repo.tenantRows = [tenantJson(1, status: 'PAST_DUE', name: 'Late Co'), tenantJson(2)];
    await open(tester, overviewJson());
    await reveal(tester, find.text('Past due').first);
    await tester.tap(find.text('Past due').first);
    await settle(tester);
    expect(find.byType(TenantsScreen), findsOneWidget);
    expect(env.repo.tenantQueries.first.status, 'PAST_DUE');
    expect(find.text('Late Co'), findsOneWidget);
  });

  testWidgets('without tenants.view the tiles are not tappable', (tester) async {
    env = await makeEnv(perms: [Perm.dashboardView, Perm.billingView]);
    await open(tester, overviewJson());
    await reveal(tester, find.text('Past due').first);
    await tester.tap(find.text('Past due').first);
    await settle(tester);
    expect(find.byType(TenantsScreen), findsNothing);
    expect(find.text('View all'), findsNothing);
  });

  testWidgets('all-zero revenue shows an honest empty state, not an empty chart', (tester) async {
    await open(tester, overviewJson(months: [0, 0, 0, 0, 0, 0]));
    await reveal(tester, find.text('No payments recorded in the last 6 months'));
    expect(find.text('No payments recorded in the last 6 months'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real revenue draws the bar chart with a total', (tester) async {
    await open(tester, overviewJson());
    await reveal(tester, find.byType(BarChart));
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('No payments recorded in the last 6 months'), findsNothing);
    expect(find.textContaining('KES 44,600'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty lists say so instead of showing nothing', (tester) async {
    await open(tester, overviewJson(withAttention: false, withExpiring: false, withPayments: false, versions: {}, devices: 0, active24h: 0));
    for (final text in ['Every client is in good standing', 'Nothing expires soon', 'No device has registered yet.', 'No payments yet']) {
      await reveal(tester, find.text(text));
      expect(find.text(text), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('fleet: version bars flag devices behind the newest version', (tester) async {
    await open(tester, overviewJson());
    await scrollThrough(tester);
    expect(find.text('v1.0.74'), findsOneWidget);
    expect(find.text('v1.0.70'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('4 devices not on the newest version (1.0.74)'), findsOneWidget);
    expect(find.text('75% of devices'), findsOneWidget);
  });

  testWidgets('a needs-attention row opens that company', (tester) async {
    env.repo.detail = detailJson(id: 'tenant-2', name: 'Pharmacy Fixture With A Pretty Long Registered Name');
    await open(tester, overviewJson());
    await reveal(tester, find.text('3 days overdue'));
    expect(find.text('Past due'), findsWidgets);
    await tester.tap(find.text('3 days overdue'));
    await settle(tester);
    expect(find.byType(TenantDetailScreen), findsOneWidget);
    final screen = tester.widget<TenantDetailScreen>(find.byType(TenantDetailScreen));
    expect(screen.tenantId, 'tenant-2');
    expect(screen.tenantName, 'Pharmacy Fixture With A Pretty Long Registered Name');
  });

  testWidgets('the expiring list shows how long each subscription has left', (tester) async {
    await open(tester, overviewJson());
    await reveal(tester, find.text('5 days left'));
    expect(find.text('Hardware Fixture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recent payment opens that company', (tester) async {
    env.repo.detail = detailJson(id: 'tenant-1');
    await open(tester, overviewJson());
    await reveal(tester, find.text('Mart Fixture'));
    await tester.tap(find.text('Mart Fixture'));
    await settle(tester);
    expect(tester.widget<TenantDetailScreen>(find.byType(TenantDetailScreen)).tenantId, 'tenant-1');
  });

  testWidgets('a failed load shows the error with a working retry', (tester) async {
    env.repo.overviewError = ApiException(0, 'Can\'t reach the server');
    usePhone(tester);
    await tester.pumpWidget(harness(env, const OverviewScreen()));
    await settle(tester);
    expect(find.text('Can\'t reach Counterbase'), findsOneWidget);

    env.repo.overviewError = null;
    env.repo.overviewData = Overview.fromJson(overviewJson());
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Monthly recurring revenue'), findsOneWidget);
  });

  testWidgets('a role without dashboard access sees the not-allowed state', (tester) async {
    env.repo.overviewError = ApiException(403, 'Missing permission', code: 'MISSING_PERMISSION');
    usePhone(tester);
    await tester.pumpWidget(harness(env, const OverviewScreen()));
    await settle(tester);
    expect(find.text('Not allowed for your role'), findsOneWidget);
  });

  testWidgets('coming back to the app after a while quietly refreshes the numbers', (tester) async {
    usePhone(tester);
    env.repo.overviewData = Overview.fromJson(overviewJson());
    await tester.pumpWidget(harness(env, const OverviewScreen(staleAfter: Duration.zero)));
    await settle(tester);
    expect(env.repo.overviewCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    expect(env.repo.overviewCalls, 1, reason: 'nothing happens while it is in the background');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(env.repo.overviewCalls, 2);
    expect(find.text('Monthly recurring revenue'), findsOneWidget, reason: 'content stays on screen while it refreshes');
  });

  testWidgets('a fresh screen is not reloaded just because the app resumed', (tester) async {
    usePhone(tester);
    env.repo.overviewData = Overview.fromJson(overviewJson());
    await tester.pumpWidget(harness(env, const OverviewScreen()));
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(env.repo.overviewCalls, 1);
  });

  testWidgets('a company change elsewhere refreshes the Overview', (tester) async {
    usePhone(tester);
    env.repo.overviewData = Overview.fromJson(overviewJson());
    await tester.pumpWidget(harness(env, const OverviewScreen()));
    await settle(tester);
    expect(env.repo.overviewCalls, 1);
    tenantChanges.bump();
    await settle(tester);
    expect(env.repo.overviewCalls, 2);
  });
}
