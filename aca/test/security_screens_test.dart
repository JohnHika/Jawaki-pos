// Render + interaction checks for the Security centre and the Audit log
// against an in-memory repository (no network): layout at 360 dp / 1.3x font,
// permission gating, filters + debounce + pagination wiring.
import 'package:aca/core/permissions.dart';
import 'package:aca/core/theme.dart';
import 'package:aca/data/api_client.dart';
import 'package:aca/data/models.dart';
import 'package:aca/data/repository.dart';
import 'package:aca/features/security/audit_screen.dart';
import 'package:aca/features/security/security_screen.dart';
import 'package:aca/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryTokens extends TokenStore {
  _MemoryTokens();
  @override
  Future<AuthTokens?> read() async => null;
  @override
  Future<void> write(AuthTokens t) async {}
  @override
  Future<void> clear() async {}
}

class _AuditCall {
  _AuditCall({this.category, this.severity, this.actorId, this.tenantId, this.search, required this.page});
  final String? category;
  final String? severity;
  final String? actorId;
  final String? tenantId;
  final String? search;
  final int page;
}

class _FakeRepo extends AcaRepository {
  _FakeRepo({this.securityJson, this.auditPages = const []}) : super(AcaApi(store: _MemoryTokens()));

  final Map<String, dynamic>? securityJson;

  /// Pages of audit rows; index 0 = page 1.
  final List<List<Map<String, dynamic>>> auditPages;
  final List<String> unlocked = [];
  final List<_AuditCall> auditCalls = [];

  @override
  Future<SecurityOverview> securityOverview() async => SecurityOverview.fromJson(securityJson ?? const {});

  @override
  Future<void> unlockStaff(String id) async => unlocked.add(id);

  @override
  Future<Paged<AuditEntry>> audit({
    String? category,
    String? severity,
    String? actorId,
    String? tenantId,
    String? search,
    String? since,
    int page = 1,
    int pageSize = 30,
  }) async {
    auditCalls.add(_AuditCall(
      category: category,
      severity: severity,
      actorId: actorId,
      tenantId: tenantId,
      search: search,
      page: page,
    ));
    final rows = page <= auditPages.length ? auditPages[page - 1] : <Map<String, dynamic>>[];
    // Filters are applied by the real server; this fake only honours a
    // search that matches nothing so the empty state can be exercised.
    final matching = search == 'nothing-matches' ? <Map<String, dynamic>>[] : rows;
    return Paged<AuditEntry>(
      items: matching.map(AuditEntry.fromJson).toList(),
      total: auditPages.fold<int>(0, (n, p) => n + p.length),
      page: page,
      pageSize: pageSize,
      totalPages: auditPages.isEmpty ? 1 : auditPages.length,
    );
  }
}

Map<String, dynamic> _event(
  String id, {
  String? summary,
  String action = 'TEAM_STAFF_DISABLED',
  String category = 'TEAM',
  String severity = 'WARN',
  String? actorEmail = 'admin@example.test',
  String? tenantId,
  Map<String, dynamic>? metadata,
  DateTime? at,
}) =>
    {
      'id': id,
      'actorId': actorEmail == null ? null : 'actor-1',
      'actorEmail': actorEmail,
      'actorRole': actorEmail == null ? null : 'ADMIN',
      'action': action,
      'category': category,
      'severity': severity,
      'targetType': 'PlatformAdmin',
      'targetId': 'target-1',
      'tenantId': tenantId,
      'summary': summary,
      'metadata': metadata,
      'ipAddress': '203.0.113.9',
      'userAgent': 'ACA/1.0 (Android 14; Pixel)',
      'createdAt': (at ?? DateTime.now().subtract(const Duration(minutes: 5))).toIso8601String(),
    };

Map<String, dynamic> _overview({
  List<Map<String, dynamic>> locked = const [],
  List<Map<String, dynamic>> without2fa = const [],
  List<Map<String, dynamic>> ips = const [],
  List<Map<String, dynamic>> events = const [],
  int coverage = 17,
}) =>
    {
      'failedLogins24h': 6,
      'successfulLogins24h': 12,
      'critical7d': 4,
      'warn7d': 14,
      'activeSessions': 9,
      'lockedAccounts': locked,
      'staff': {
        'active': 6,
        'disabled': 1,
        'twoFactorCoveragePercent': coverage,
        'withoutTwoFactor': without2fa,
      },
      'topFailedIps': ips,
      'recentEvents': events,
    };

StaffProfile _staff(List<String> permissions) => StaffProfile(
      id: 'me',
      email: 'me@example.test',
      name: 'Me',
      phone: null,
      role: 'SECURITY',
      status: 'ACTIVE',
      permissions: permissions,
      mustChangePassword: false,
      twoFactorEnabled: true,
      lastLoginAt: null,
      createdAt: null,
    );

Future<void> _pump(
  WidgetTester tester,
  _FakeRepo repo,
  Widget screen, {
  required List<String> permissions,
  double textScale = 1.0,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final session = SessionController(api: repo.api, repo: repo, prefs: prefs)..me = _staff(permissions);

  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AcaRepository>.value(value: repo),
        ChangeNotifierProvider<SessionController>.value(value: session),
      ],
      child: MaterialApp(
        theme: AcaTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drags the page until [target] is on screen (more predictable than
/// `scrollUntilVisible` for long lists whose rows are built lazily).
Future<void> _reveal(WidgetTester tester, Finder target, {Finder? list, bool last = false}) async {
  final scrollable = list ?? (last ? find.byType(Scrollable).last : find.byType(Scrollable).first);
  for (var i = 0; i < 40 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -200));
    await tester.pump();
  }
  expect(target.hitTestable().evaluate(), isNotEmpty, reason: 'could not scroll $target into view');
}

const _lockedAccount = {
  'id': 'staff-locky',
  'email': 'locky@example.test',
  'name': 'Locky Longname Of The Operations Desk',
  'role': 'VIEWER',
};

void main() {
  const securityTeam = [Perm.securityView, Perm.securityManage, Perm.auditView, Perm.teamView, Perm.tenantsView];

  group('SecurityScreen', () {
    testWidgets('renders every section at 360dp / 1.3x font without overflow', (tester) async {
      final repo = _FakeRepo(
        securityJson: _overview(
          locked: [
            {..._lockedAccount, 'lockedUntil': DateTime.now().add(const Duration(minutes: 12)).toUtc().toIso8601String()},
          ],
          without2fa: [
            {'id': 's1', 'email': 'support@example.test', 'name': 'QA Support', 'role': 'SUPPORT'},
            {'id': 's2', 'email': 'a.very.long.address.for.layout.testing@example.test', 'name': '', 'role': 'ADMIN'},
          ],
          ips: [
            {'ip': '203.0.113.9', 'attempts': 6},
            {'ip': '2001:db8:85a3:0:0:8a2e:370:7334', 'attempts': 1},
          ],
          events: [
            _event('e1', summary: 'admin@example.test updated viewer@example.test'),
            _event('e2', severity: 'CRITICAL', category: 'SECURITY', action: 'AUTH_ACCOUNT_LOCKED', summary: null),
          ],
        ),
      );
      await _pump(tester, repo, const SecurityScreen(), permissions: securityTeam, textScale: 1.3);

      final list = find.byType(Scrollable).first;
      expect(find.text('17%'), findsOneWidget);
      expect(find.text('Failed sign-ins'), findsOneWidget);
      // Walk down the whole page so every section is laid out at least once.
      for (final text in [
        'Successful sign-ins',
        'Critical alerts',
        'Warnings',
        'LOCKED ACCOUNTS (1)',
        'Unlock',
        'STAFF WITHOUT TWO-STEP SIGN-IN (2)',
        'QA Support',
        'MOST FAILED SIGN-INS BY IP (24 H)',
        '203.0.113.9',
        '2001:db8:85a3:0:0:8a2e:370:7334',
        'RECENT ALERTS',
        'Open full audit log',
      ]) {
        await _reveal(tester, find.text(text), list: list);
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('unlock asks for confirmation then calls the API', (tester) async {
      final repo = _FakeRepo(
        securityJson: _overview(locked: [
          {..._lockedAccount, 'lockedUntil': DateTime.now().add(const Duration(minutes: 12)).toUtc().toIso8601String()},
        ]),
      );
      await _pump(tester, repo, const SecurityScreen(), permissions: securityTeam);

      await _reveal(tester, find.text('Unlock'), last: false);
      expect(find.textContaining('unlocks in'), findsOneWidget);
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(repo.unlocked, isEmpty); // nothing happens before confirming

      await tester.tap(find.text('Unlock account'));
      await tester.pumpAndSettle();
      expect(repo.unlocked, ['staff-locky']);
    });

    testWidgets('without security.manage there is no Unlock button; without audit.view no audit shortcut',
        (tester) async {
      final repo = _FakeRepo(
        securityJson: _overview(locked: [
          {..._lockedAccount, 'lockedUntil': DateTime.now().add(const Duration(minutes: 12)).toUtc().toIso8601String()},
        ]),
      );
      await _pump(tester, repo, const SecurityScreen(), permissions: const [Perm.securityView]);

      await _reveal(tester, find.textContaining('unlocks in'), last: false);
      expect(find.text('Unlock'), findsNothing);
      await _reveal(tester, find.text('RECENT ALERTS'), last: false);
      expect(find.text('Open full audit log'), findsNothing);
    });

    testWidgets('quiet states are explicit, failed-IP section is hidden when empty', (tester) async {
      final repo = _FakeRepo(securityJson: _overview(coverage: 100));
      await _pump(tester, repo, const SecurityScreen(), permissions: securityTeam);

      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Fully protected'), findsOneWidget);
      expect(find.text('No accounts are locked'), findsOneWidget);
      expect(find.textContaining('MOST FAILED SIGN-INS'), findsNothing);
      await _reveal(tester, find.text('RECENT ALERTS'), last: false);
      expect(find.textContaining('No warnings or critical events'), findsOneWidget);
    });

    testWidgets('a recent alert opens the audit entry sheet', (tester) async {
      final repo = _FakeRepo(
        securityJson: _overview(events: [
          _event('e1', summary: 'admin@example.test updated viewer@example.test', metadata: {
            'before': {'status': 'ACTIVE'},
            'after': {'status': 'DISABLED'},
          }),
        ]),
      );
      await _pump(tester, repo, const SecurityScreen(), permissions: securityTeam);

      await _reveal(tester, find.text('admin@example.test updated viewer@example.test'), last: false);
      await tester.tap(find.text('admin@example.test updated viewer@example.test'));
      await tester.pumpAndSettle();

      expect(find.text('TEAM_STAFF_DISABLED'), findsOneWidget);
      expect(find.text('After › Status'), findsOneWidget);
      expect(find.text('203.0.113.9'), findsOneWidget);
    });
  });

  group('AuditScreen', () {
    testWidgets('groups by day, shows severity pills and respects constructor filters', (tester) async {
      final repo = _FakeRepo(auditPages: [
        [
          _event('a', summary: 'admin@example.test updated viewer@example.test'),
          _event('b', severity: 'INFO', summary: null, action: 'AUTH_LOGIN_SUCCESS', category: 'AUTH'),
          _event('c', severity: 'CRITICAL', summary: 'Account locked', at: DateTime.now().subtract(const Duration(days: 1))),
        ],
      ]);
      await _pump(tester, repo, const AuditScreen(tenantId: 'tenant-9', actorId: 'actor-9', title: 'Company activity'),
          permissions: securityTeam, textScale: 1.3);

      expect(find.text('Company activity'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
      expect(find.text('Sign-in success'), findsOneWidget); // summary fallback = prettified action
      expect(find.text('Warning'), findsOneWidget);
      expect(find.text('Critical'), findsWidgets); // severity chip + pill

      expect(repo.auditCalls.first.tenantId, 'tenant-9');
      expect(repo.auditCalls.first.actorId, 'actor-9');
      expect(repo.auditCalls.first.page, 1);
    });

    testWidgets('search is debounced; category and severity chips combine with it and the constructor filters',
        (tester) async {
      final repo = _FakeRepo(auditPages: [
        [_event('a', summary: 'Something happened')],
      ]);
      await _pump(tester, repo, const AuditScreen(tenantId: 'tenant-9'), permissions: securityTeam);
      final initial = repo.auditCalls.length;

      await tester.enterText(find.byType(TextField), 'unlock');
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.auditCalls.length, initial, reason: 'still inside the 400 ms debounce window');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(repo.auditCalls.length, initial + 1);
      expect(repo.auditCalls.last.search, 'unlock');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Sign-in'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Critical'));
      await tester.pumpAndSettle();

      final last = repo.auditCalls.last;
      expect(last.category, 'AUTH');
      expect(last.severity, 'CRITICAL');
      expect(last.search, 'unlock');
      expect(last.tenantId, 'tenant-9');
      expect(last.page, 1);
    });

    testWidgets('typing quickly only searches once', (tester) async {
      final repo = _FakeRepo(auditPages: [
        [_event('a', summary: 'Something happened')],
      ]);
      await _pump(tester, repo, const AuditScreen(), permissions: securityTeam);
      final initial = repo.auditCalls.length;

      for (final text in ['u', 'un', 'unl', 'unlo']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(repo.auditCalls.length, initial + 1);
      expect(repo.auditCalls.last.search, 'unlo');
    });

    testWidgets('empty result with filters offers to clear them', (tester) async {
      final repo = _FakeRepo(auditPages: [
        [_event('a', summary: 'Something happened')],
      ]);
      await _pump(tester, repo, const AuditScreen(), permissions: securityTeam);

      await tester.enterText(find.byType(TextField), 'nothing-matches');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(find.text('Nothing matches'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('Something happened'), findsOneWidget);
      expect(repo.auditCalls.last.search, isNull);
    });

    testWidgets('scrolling to the end loads the next page', (tester) async {
      final repo = _FakeRepo(auditPages: [
        [for (var i = 0; i < 12; i++) _event('p1-$i', summary: 'First page row $i')],
        [for (var i = 0; i < 3; i++) _event('p2-$i', summary: 'Second page row $i')],
      ]);
      await _pump(tester, repo, const AuditScreen(), permissions: securityTeam);
      expect(repo.auditCalls.map((c) => c.page), [1]);

      await tester.fling(find.byType(Scrollable).last, const Offset(0, -3000), 4000);
      await tester.pumpAndSettle();

      expect(repo.auditCalls.map((c) => c.page), [1, 2]);
      expect(find.text('Second page row 2'), findsOneWidget);
    });

    testWidgets('entry sheet: pretty action + raw code, nested metadata as rows, company link per permission',
        (tester) async {
      final repo = _FakeRepo(auditPages: [
        [
          _event('a', summary: 'Company suspended', action: 'PLATFORM_ADMIN_TENANT_SUSPENDED', category: 'TENANT', tenantId: 'tenant-1', metadata: {
            'reason': 'Unpaid',
            'before': {'status': 'ACTIVE'},
            'twoFactor': false,
          }),
        ],
      ]);
      await _pump(tester, repo, const AuditScreen(), permissions: securityTeam, textScale: 1.3);

      await tester.tap(find.text('Company suspended'));
      await tester.pumpAndSettle();

      expect(find.text('Company suspended'), findsWidgets);
      expect(find.text('PLATFORM_ADMIN_TENANT_SUSPENDED'), findsOneWidget);
      expect(find.text('Before › Status'), findsOneWidget);
      expect(find.text('Two factor'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      await _reveal(tester, find.text('Open company'), last: true);
      expect(find.text('Open company'), findsOneWidget);
    });

    testWidgets('entry sheet hides the company link without tenants.view', (tester) async {
      final repo = _FakeRepo(auditPages: [
        [_event('a', summary: 'Company suspended', category: 'TENANT', tenantId: 'tenant-1')],
      ]);
      await _pump(tester, repo, const AuditScreen(), permissions: const [Perm.auditView]);

      await tester.tap(find.text('Company suspended'));
      await tester.pumpAndSettle();

      expect(find.text('Open company'), findsNothing);
      expect(find.text('Open staff member'), findsNothing);
    });

    testWidgets('an empty log explains itself', (tester) async {
      final repo = _FakeRepo();
      await _pump(tester, repo, const AuditScreen(), permissions: securityTeam);
      expect(find.text('No activity recorded yet'), findsOneWidget);
    });
  });
}
