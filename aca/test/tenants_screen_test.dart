import 'package:aca/core/permissions.dart';
import 'package:aca/core/theme.dart';
import 'package:aca/data/api_client.dart';
import 'package:aca/data/models.dart';
import 'package:aca/data/repository.dart';
import 'package:aca/features/tenants/tenants_screen.dart';
import 'package:aca/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -------------------------------------------------------------------------
// Shared test support (also imported by the Overview and detail widget tests).
// Everything below is throwaway test data; the app itself never contains any.
// -------------------------------------------------------------------------

const allTenantPerms = [
  Perm.dashboardView,
  Perm.tenantsView,
  Perm.tenantsManage,
  Perm.tenantsSuspend,
  Perm.tenantsLicense,
  Perm.tenantsUsers,
  Perm.tenantsSecurity,
  Perm.billingView,
  Perm.billingManage,
  Perm.auditView,
];

Map<String, dynamic> tenantJson(
  int i, {
  String? name,
  String plan = 'CORE',
  String status = 'ACTIVE',
  bool isActive = true,
  int daysLeft = 20,
}) =>
    {
      'id': 'tenant-$i',
      'name': name ?? 'Company $i',
      'slug': 'company-$i',
      'plan': plan,
      'subscriptionStatus': status,
      'currentPeriodEnd': DateTime.now().add(Duration(days: daysLeft)).toUtc().toIso8601String(),
      'createdAt': '2026-09-01T10:00:00.000Z',
      'invoiceCount': 2,
      'userCount': 3,
      'branchCount': 1,
      'isActive': isActive,
      'activationStatus': 'PAID',
    };

Paged<TenantSummary> pageOf(List<Map<String, dynamic>> all, int page, {int pageSize = 20}) {
  final start = (page - 1) * pageSize;
  final slice = start >= all.length ? <Map<String, dynamic>>[] : all.sublist(start, (start + pageSize).clamp(0, all.length));
  return Paged.fromJson({
    'items': slice,
    'total': all.length,
    'page': page,
    'pageSize': pageSize,
    'totalPages': (all.length / pageSize).ceil().clamp(1, 1 << 20),
  }, TenantSummary.fromJson);
}

Map<String, dynamic> detailJson({
  String id = 'tenant-1',
  String name = 'Mart Fixture',
  String status = 'ACTIVE',
  bool isActive = true,
  List<Map<String, dynamic>> claims = const [],
  int invoiceCount = 4,
  String? billingPhone = '+254 700 000111',
}) =>
    {
      'id': id,
      'name': name,
      'slug': 'mart-fixture',
      'plan': 'CORE',
      'subscriptionStatus': status,
      'currentPeriodStart': '2026-09-30T16:25:00.278Z',
      'currentPeriodEnd': DateTime.now().add(const Duration(days: 11)).toUtc().toIso8601String(),
      'maxBranches': 1,
      'maxUsers': 3,
      'autoRenewEnabled': true,
      'billingPhone': billingPhone,
      'activationStatus': 'PAID',
      'activationPaidAt': '2026-09-01T10:00:00.000Z',
      'setupFeePaidAt': null,
      'isActive': isActive,
      'subscriptionProvider': 'PAYSTACK',
      'createdAt': '2026-09-01T10:00:00.000Z',
      'owner': {'id': 'o1', 'email': 'owner@mart.test', 'firstName': 'Owen', 'lastName': 'Fixture'},
      'counts': {'branches': 1, 'users': 2, 'invoices': invoiceCount},
      'last5Invoices': [
        {
          'id': 'inv-credit',
          'tenantId': id,
          'plan': 'CREDIT',
          'amount': '-100',
          'currency': 'KES',
          'status': 'PAID',
          'provider': 'CREDIT',
          'reference': 'CREDIT:Downtime in October',
          'paidAt': '2026-10-21T16:36:54.728Z',
          'createdAt': '2026-10-21T16:36:54.729Z',
        },
        {
          'id': 'inv-1',
          'tenantId': id,
          'plan': 'CORE',
          'amount': '3200',
          'currency': 'KES',
          'status': 'PAID',
          'provider': 'PAYSTACK',
          'reference': 'REF-1',
          'periodStart': '2026-09-16T16:25:00.278Z',
          'periodEnd': '2026-10-16T16:25:00.278Z',
          'paidAt': '2026-09-16T16:25:00.278Z',
          'createdAt': '2026-09-16T16:25:00.278Z',
        },
      ],
      'claims': claims,
    };

Map<String, dynamic> licenseJson({String enforcement = 'off', Map<String, dynamic>? features, Map<String, dynamic>? limits}) => {
      'plan': 'CORE',
      'enforcement': enforcement,
      'enforced': enforcement == 'enforce',
      'features': features ??
          {
            'analytics': {'allowed': true, 'source': 'plan'},
            'customReports': {'allowed': false, 'source': 'plan'},
            'aiAssistant': {'allowed': false, 'source': 'plan'},
            'multiCurrency': {'allowed': false, 'source': 'plan'},
            'prioritySupport': {'allowed': false, 'source': 'plan'},
          },
      'limits': limits ?? {'maxBranches': 3, 'maxUsers': 10},
      'validUntil': null,
      'expired': false,
      'licenseKey': 'AXON-ABCD-EFGH-JKLM',
      'note': null,
      'unknownPlan': false,
    };

Map<String, dynamic> userJson(String id, String first, {String role = 'ADMIN', bool isActive = true, int sessions = 0}) => {
      'id': id,
      'email': '${first.toLowerCase()}@mart.test',
      'phone': null,
      'firstName': first,
      'lastName': 'Fixture',
      'role': role,
      'isActive': isActive,
      'lastLoginAt': DateTime.now().subtract(const Duration(hours: 3)).toUtc().toIso8601String(),
      'createdAt': '2026-09-01T10:00:00.000Z',
      'activeSessions': sessions,
    };

Map<String, dynamic> deviceJson(String id, String name, String? version) => {
      'id': id,
      'name': name,
      'model': 'SM-A15',
      'osVersion': '14',
      'appVersion': version,
      'lastSyncAt': DateTime.now().subtract(const Duration(minutes: 40)).toUtc().toIso8601String(),
      'lastActiveAt': DateTime.now().subtract(const Duration(minutes: 50)).toUtc().toIso8601String(),
      'isActive': true,
      'registeredAt': '2026-09-01T10:00:00.000Z',
      'branchId': 'b1',
      'branchName': 'Main Branch',
    };

Map<String, dynamic> noteJson(String id, String body, {bool pinned = false, int minutesAgo = 5}) => {
      'id': id,
      'tenantId': 'tenant-1',
      'authorEmail': 'support@aca.test',
      'body': body,
      'pinned': pinned,
      'createdAt': DateTime.now().subtract(Duration(minutes: minutesAgo)).toUtc().toIso8601String(),
    };

/// A repository that answers from memory and records every call, so widget
/// tests never touch the network.
class FakeRepo extends AcaRepository {
  FakeRepo(super.api);

  final log = <String>[];

  // overview
  Overview? overviewData;
  Object? overviewError;
  int overviewCalls = 0;

  // tenants list
  List<Map<String, dynamic>> tenantRows = [];
  Object? Function(int page)? tenantsFailure;
  final tenantQueries = <({String? search, String? status, int page})>[];

  // detail
  Map<String, dynamic> detail = detailJson();
  Object? detailError;
  Map<String, dynamic> licenseData = licenseJson();
  Object? licenseError;
  final licensePatches = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> users = [];
  Object? usersError;
  List<Map<String, dynamic>> devices = [];
  List<Map<String, dynamic>> notes = [];
  List<Map<String, dynamic>> invoiceRows = [];

  @override
  Future<Overview> overview() async {
    overviewCalls++;
    if (overviewError != null) throw overviewError!;
    return overviewData!;
  }

  @override
  Future<Paged<TenantSummary>> tenants({String? search, String? status, int page = 1, int pageSize = 20}) async {
    tenantQueries.add((search: search, status: status, page: page));
    final fail = tenantsFailure?.call(page);
    if (fail != null) throw fail;
    var rows = tenantRows;
    if (status != null) rows = rows.where((r) => r['subscriptionStatus'] == status).toList();
    if (search != null) rows = rows.where((r) => (r['name'] as String).toLowerCase().contains(search.toLowerCase())).toList();
    return pageOf(rows, page, pageSize: pageSize);
  }

  @override
  Future<TenantDetail> tenant(String id) async {
    if (detailError != null) throw detailError!;
    return TenantDetail.fromJson(detail);
  }

  @override
  Future<Map<String, dynamic>> license(String id) async {
    if (licenseError != null) throw licenseError!;
    return licenseData;
  }

  @override
  Future<Map<String, dynamic>> updateLicense(String id, Map<String, dynamic> patch) async {
    licensePatches.add(patch);
    return licenseData;
  }

  @override
  Future<List<TenantUser>> tenantUsers(String id) async {
    if (usersError != null) throw usersError!;
    return users.map(TenantUser.fromJson).toList();
  }

  @override
  Future<List<TenantDevice>> tenantDevices(String id) async => devices.map(TenantDevice.fromJson).toList();

  @override
  Future<List<TenantNote>> tenantNotes(String id) async => notes.map(TenantNote.fromJson).toList();

  @override
  Future<TenantNote> addTenantNote(String id, String body, {bool pinned = false}) async {
    log.add('addNote:$body:$pinned');
    return TenantNote.fromJson(noteJson('new', body, pinned: pinned));
  }

  @override
  Future<void> deleteTenantNote(String tenantId, String noteId) async => log.add('deleteNote:$noteId');

  @override
  Future<Paged<Invoice>> invoices({String? status, String? tenantId, int page = 1, int pageSize = 20}) async {
    log.add('invoices:$tenantId:$page:$pageSize');
    return Paged.fromJson({
      'items': invoiceRows,
      'total': invoiceRows.length,
      'page': page,
      'pageSize': pageSize,
      'totalPages': 1,
    }, Invoice.fromJson);
  }

  @override
  Future<DateTime?> extendTenant(String id, int days) async {
    log.add('extend:$id:$days');
    return DateTime(2026, 12, 1);
  }

  @override
  Future<void> suspendTenant(String id) async => log.add('suspend:$id');

  @override
  Future<void> reactivateTenant(String id) async => log.add('reactivate:$id');

  @override
  Future<void> creditTenant(String id, {required num amountKes, required String reason}) async =>
      log.add('credit:$id:$amountKes:$reason');

  @override
  Future<int> forceTenantLogout(String tenantId) async {
    log.add('forceLogout:$tenantId');
    return 3;
  }

  @override
  Future<void> lockTenantOut(String tenantId, {String? reason}) async => log.add('lockout:$tenantId:${reason ?? ''}');

  @override
  Future<void> liftTenantLockout(String tenantId, {String? reason}) async => log.add('lift:$tenantId:${reason ?? ''}');

  @override
  Future<void> setTenantUserActive(String tenantId, String userId, {required bool active}) async =>
      log.add('userActive:$userId:$active');

  @override
  Future<int> revokeTenantUserSessions(String tenantId, String userId) async {
    log.add('revokeUser:$userId');
    return 2;
  }
}

class TestEnv {
  TestEnv(this.api, this.repo, this.session);
  final AcaApi api;
  final FakeRepo repo;
  final SessionController session;
}

Future<TestEnv> makeEnv({List<String> perms = allTenantPerms, String name = 'Amina Wanjiku'}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = AcaApi(store: TokenStore());
  final repo = FakeRepo(api);
  final session = SessionController(api: api, repo: repo, prefs: prefs);
  session.me = StaffProfile(
    id: 'staff-1',
    email: 'amina@aca.test',
    name: name,
    phone: null,
    role: 'OWNER',
    status: 'ACTIVE',
    permissions: perms,
    mustChangePassword: false,
    twoFactorEnabled: true,
    lastLoginAt: null,
    createdAt: null,
  );
  return TestEnv(api, repo, session);
}

/// A 360 x 800 phone at the given system font scale.
void usePhone(WidgetTester tester, {double scale = 1.3}) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Widget harness(TestEnv env, Widget home) => MultiProvider(
      providers: [
        Provider<AcaApi>.value(value: env.api),
        Provider<AcaRepository>.value(value: env.repo),
        ChangeNotifierProvider<SessionController>.value(value: env.session),
      ],
      child: MaterialApp(theme: AcaTheme.darkTheme, home: home),
    );

/// Lets futures resolve and animations finish. (A skeleton pulses forever, so
/// pumpAndSettle alone would time out while one is on screen.)
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  group('Clients list', () {
    late TestEnv env;

    Future<void> open(WidgetTester tester, {String? initialStatus}) async {
      usePhone(tester);
      await tester.pumpWidget(harness(env, TenantsScreen(initialStatus: initialStatus)));
      await settle(tester);
    }

    setUp(() async {
      env = await makeEnv();
    });

    testWidgets('shows the total, status pills and the locked-out pill without overflowing', (tester) async {
      env.repo.tenantRows = [
        tenantJson(4, name: 'Locked Fixture', status: 'ACTIVE', isActive: false),
        tenantJson(2, name: 'Pharmacy Fixture', status: 'PAST_DUE', daysLeft: -3),
        tenantJson(3, name: 'Hardware Fixture With A Really Rather Long Company Name Indeed', status: 'TRIAL', plan: 'TRIAL'),
        tenantJson(1, name: 'Mart Fixture', status: 'ACTIVE'),
      ];
      await open(tester);

      expect(find.text('4 companies'), findsOneWidget);
      expect(find.text('Locked out'), findsOneWidget);
      expect(find.text('Locked Fixture'), findsOneWidget);
      expect(find.text('Pharmacy Fixture'), findsOneWidget);
      expect(find.text('Past due'), findsOneWidget); // the row's pill (the filter chip may be scrolled off-screen)
      expect(find.text('3 days overdue'), findsOneWidget);
      expect(find.text('3 users'), findsWidgets);
      expect(find.text('1 branch'), findsWidgets);

      // Scroll through the rest: nothing may overflow at 360 dp / 1.3x text.
      await tester.drag(find.byKey(const ValueKey('tenants-list')), const Offset(0, -600));
      await settle(tester);
      expect(find.textContaining('Hardware Fixture With A Really'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loads the next page near the end and does not repeat rows', (tester) async {
      env.repo.tenantRows = [for (var i = 1; i <= 45; i++) tenantJson(i)];
      await open(tester);
      expect(env.repo.tenantQueries.map((q) => q.page), [1]);
      expect(find.text('45 companies'), findsOneWidget);

      for (var i = 0; i < 12 && env.repo.tenantQueries.length < 3; i++) {
        await tester.fling(find.byKey(const ValueKey('tenants-list')), const Offset(0, -2500), 4000);
        await settle(tester);
      }
      expect(env.repo.tenantQueries.map((q) => q.page), [1, 2, 3]);

      // Scroll to the very end: every company exactly once, and the end-of-list note.
      for (var i = 0; i < 12; i++) {
        await tester.fling(find.byKey(const ValueKey('tenants-list')), const Offset(0, -2500), 4000);
        await settle(tester);
      }
      expect(find.text('Company 45'), findsOneWidget);
      expect(find.text('That\'s every company'), findsOneWidget);
      expect(env.repo.tenantQueries.length, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed next page shows a retry and recovers', (tester) async {
      env.repo.tenantRows = [for (var i = 1; i <= 30; i++) tenantJson(i)];
      var fail = true;
      env.repo.tenantsFailure = (page) => (page == 2 && fail) ? ApiException(0, 'Can\'t reach the server') : null;
      await open(tester);

      for (var i = 0; i < 8; i++) {
        await tester.fling(find.byKey(const ValueKey('tenants-list')), const Offset(0, -2500), 4000);
        await settle(tester);
      }
      expect(find.text('Couldn\'t load more companies'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Couldn\'t load more companies'), findsNothing);
      expect(env.repo.tenantQueries.where((q) => q.page == 2).length, 2);
    });

    testWidgets('search is debounced (~400 ms) and sent to the server', (tester) async {
      env.repo.tenantRows = [tenantJson(1, name: 'Pharmacy One'), tenantJson(2, name: 'Mart Two')];
      await open(tester);
      final before = env.repo.tenantQueries.length;

      await tester.enterText(find.byType(TextField), 'pha');
      await tester.pump(const Duration(milliseconds: 200));
      expect(env.repo.tenantQueries.length, before, reason: 'still inside the debounce window');
      await tester.enterText(find.byType(TextField), 'phar');
      await tester.pump(const Duration(milliseconds: 300));
      expect(env.repo.tenantQueries.length, before, reason: 'typing restarts the window');
      await tester.pump(const Duration(milliseconds: 150));
      await settle(tester);

      expect(env.repo.tenantQueries.length, before + 1);
      expect(env.repo.tenantQueries.last.search, 'phar');
      expect(find.text('1 company found'), findsOneWidget);
      expect(find.text('Pharmacy One'), findsOneWidget);
      expect(find.text('Mart Two'), findsNothing);
    });

    testWidgets('a search with no hits explains itself and can be cleared', (tester) async {
      env.repo.tenantRows = [tenantJson(1, name: 'Pharmacy One')];
      await open(tester);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 450));
      await settle(tester);
      expect(find.text('No companies match'), findsOneWidget);
      expect(find.textContaining('zzz'), findsWidgets);

      await tester.tap(find.text('Clear search and filters'));
      await settle(tester);
      expect(find.text('Pharmacy One'), findsOneWidget);
      expect(env.repo.tenantQueries.last.search, isNull);
    });

    testWidgets('an empty book of business gets its own empty state', (tester) async {
      env.repo.tenantRows = [];
      await open(tester);
      expect(find.text('No companies yet'), findsOneWidget);
    });

    testWidgets('tapping a status chip filters on the server', (tester) async {
      env.repo.tenantRows = [tenantJson(1, status: 'ACTIVE'), tenantJson(2, status: 'SUSPENDED', name: 'Frozen Co')];
      await open(tester);

      final chips = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.widgetWithText(ChoiceChip, 'Suspended'), 120, scrollable: chips);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Suspended'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Suspended'));
      await settle(tester);
      expect(env.repo.tenantQueries.last.status, 'SUSPENDED');
      expect(find.text('Frozen Co'), findsOneWidget);
      expect(find.text('Company 1'), findsNothing);
      expect(find.text('1 company found'), findsOneWidget);

      await tester.scrollUntilVisible(find.widgetWithText(ChoiceChip, 'All'), -120, scrollable: chips);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await settle(tester);
      expect(env.repo.tenantQueries.last.status, isNull);
    });

    testWidgets('initialStatus pre-selects the chip and the first request', (tester) async {
      env.repo.tenantRows = [tenantJson(1, status: 'PAST_DUE', name: 'Late Co'), tenantJson(2, status: 'ACTIVE')];
      await open(tester, initialStatus: 'past_due');

      expect(env.repo.tenantQueries.first.status, 'PAST_DUE');
      // The selected chip was scrolled into view on open.
      final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Past due'));
      expect(chip.selected, isTrue);
      expect(find.text('Late Co'), findsOneWidget);
    });

    testWidgets('a failed first load shows the error with retry', (tester) async {
      env.repo.tenantRows = [tenantJson(1)];
      var fail = true;
      env.repo.tenantsFailure = (_) => fail ? ApiException(500, 'Server is on fire') : null;
      await open(tester);
      expect(find.text('Couldn\'t load this'), findsOneWidget);
      expect(find.text('Server is on fire'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Company 1'), findsOneWidget);
    });

    testWidgets('a 403 renders the not-allowed state instead of crashing', (tester) async {
      env.repo.tenantsFailure = (_) => ApiException(403, 'Your role cannot do that', code: 'MISSING_PERMISSION');
      await open(tester);
      expect(find.text('Not allowed for your role'), findsOneWidget);
    });
  });
}
