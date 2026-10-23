import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aca/core/permissions.dart';
import 'package:aca/core/theme.dart';
import 'package:aca/data/api_client.dart';
import 'package:aca/data/models.dart';
import 'package:aca/data/repository.dart';
import 'package:aca/features/team/roles_screen.dart';
import 'package:aca/features/team/staff_detail_screen.dart';
import 'package:aca/features/team/team_screen.dart';
import 'package:aca/state/session.dart';

// ------------------------------------------------------------------ fixtures
// Test-only data. The app itself never contains sample data.

const _ranks = {'OWNER': 100, 'ADMIN': 80, 'SECURITY': 60, 'FINANCE': 50, 'SUPPORT': 40, 'VIEWER': 10};
const _descriptions = {
  'OWNER': 'Full control of Counterbase, including the team and ownership.',
  'ADMIN': 'Runs day-to-day operations and manages non-admin staff.',
  'SECURITY': 'Monitors sign-ins, audits activity and locks down accounts and devices.',
  'FINANCE': 'Handles invoices, payments and credits.',
  'SUPPORT': 'Helps clients: subscription extensions, notes and staff look-ups.',
  'VIEWER': 'Read-only access to dashboards, clients and billing.',
};
const _all = [
  Perm.dashboardView, Perm.tenantsView, Perm.tenantsManage, Perm.tenantsSuspend, Perm.tenantsLicense,
  Perm.tenantsUsers, Perm.tenantsSecurity, Perm.billingView, Perm.billingManage, Perm.teamView,
  Perm.teamManage, Perm.securityView, Perm.securityManage, Perm.auditView,
];
const _rolePerms = <String, List<String>>{
  'OWNER': _all,
  'ADMIN': _all,
  'SECURITY': [Perm.dashboardView, Perm.tenantsView, Perm.tenantsSuspend, Perm.tenantsUsers, Perm.tenantsSecurity, Perm.teamView, Perm.securityView, Perm.securityManage, Perm.auditView],
  'FINANCE': [Perm.dashboardView, Perm.tenantsView, Perm.billingView, Perm.billingManage, Perm.auditView],
  'SUPPORT': [Perm.dashboardView, Perm.tenantsView, Perm.tenantsManage, Perm.tenantsUsers, Perm.billingView],
  'VIEWER': [Perm.dashboardView, Perm.tenantsView, Perm.billingView],
};

List<RoleInfo> catalogFor(String actor) => [
      for (final r in Roles.all)
        RoleInfo(
          role: r,
          rank: _ranks[r]!,
          description: _descriptions[r]!,
          permissions: _rolePerms[r]!,
          assignable: actor == 'OWNER' || (actor == 'ADMIN' && _ranks[r]! < 80),
        ),
    ];

StaffMember staff(
  String id,
  String name,
  String role, {
  String status = 'ACTIVE',
  bool twoFactor = false,
  bool locked = false,
  bool invite = false,
  int sessions = 0,
  String? phone,
  DateTime? lastLogin,
  List<AuditEntry> activity = const [],
}) =>
    StaffMember(
      id: id,
      email: '${name.split(' ').first.toLowerCase()}@archeaxon.com',
      name: name,
      phone: phone,
      role: role,
      status: status,
      permissions: _rolePerms[role]!,
      mustChangePassword: invite,
      twoFactorEnabled: twoFactor,
      lastLoginAt: lastLogin,
      createdAt: DateTime(2026, 3, 1),
      locked: locked,
      lockedUntil: locked ? DateTime.now().add(const Duration(minutes: 10)) : null,
      failedLoginAttempts: locked ? 5 : 0,
      lastLoginIp: lastLogin == null ? null : '41.80.1.2',
      activeSessions: sessions,
      passwordChangedAt: invite ? null : DateTime(2026, 3, 2, 10),
      recentActivity: activity,
    );

AuditEntry audit(String summary) => AuditEntry(
      id: summary,
      actorId: 'x',
      actorEmail: 'x@archeaxon.com',
      actorRole: 'ADMIN',
      action: 'TEAM_STAFF_UPDATED',
      category: 'TEAM',
      severity: 'INFO',
      targetType: null,
      targetId: null,
      tenantId: null,
      summary: summary,
      metadata: const {},
      ipAddress: null,
      userAgent: null,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

StaffProfile profileOf(String id, String role) => StaffProfile(
      id: id,
      email: 'me@archeaxon.com',
      name: 'Me Myself',
      phone: null,
      role: role,
      status: 'ACTIVE',
      permissions: _rolePerms[role]!,
      mustChangePassword: false,
      twoFactorEnabled: true,
      lastLoginAt: null,
      createdAt: DateTime(2026, 1, 1),
    );

// -------------------------------------------------------------------- fakes

class FakeRepo extends AcaRepository {
  FakeRepo({required this.me, required this.members}) : super(AcaApi(store: TokenStore()));

  final StaffProfile me;
  List<StaffMember> members;
  final calls = <String>[];
  Object? createError;
  Object? sessionsError;

  @override
  Future<List<StaffMember>> team() async => members;

  @override
  Future<StaffMember> staff(String id) async => members.firstWhere((m) => m.id == id);

  @override
  Future<List<RoleInfo>> roles() async => catalogFor(me.role);

  @override
  Future<List<SessionInfo>> staffSessions(String id) async {
    if (sessionsError != null) throw sessionsError!;
    return [
      SessionInfo(
        id: 's1',
        deviceLabel: 'Pixel 7 · ACA 1.0.0',
        userAgent: null,
        ipAddress: '41.80.1.2',
        createdAt: null,
        lastUsedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        expiresAt: null,
        current: false,
      ),
    ];
  }

  @override
  Future<TempCredential> createStaff({required String email, required String name, required String role, String? phone}) async {
    calls.add('create:$email:$name:$role:${phone ?? ''}');
    if (createError != null) throw createError!;
    return TempCredential(email: email, temporaryPassword: 'Zq7!mK2#pL9@vX4t');
  }

  @override
  Future<void> updateStaff(String id, {String? name, String? role, String? status, String? phone}) async {
    calls.add('update:$id:${name ?? ''}:${role ?? ''}:${status ?? ''}:${phone ?? ''}');
  }

  @override
  Future<TempCredential> resetStaffPassword(String id, {required String email}) async {
    calls.add('reset:$id');
    return TempCredential(email: email, temporaryPassword: 'Rt5#nB8!wQ3@cY6h');
  }

  @override
  Future<void> unlockStaff(String id) async => calls.add('unlock:$id');

  @override
  Future<int> revokeStaffSessions(String id) async {
    calls.add('revoke:$id');
    return 2;
  }
}

Future<(FakeRepo, SessionController)> setup(WidgetTester tester, {required String myRole, required List<StaffMember> members}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final me = profileOf('me', myRole);
  final repo = FakeRepo(me: me, members: members);
  final session = SessionController(api: repo.api, repo: repo, prefs: prefs)..me = me;
  tester.view
    ..physicalSize = const Size(360 * 3, 740 * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  return (repo, session);
}

Widget app(FakeRepo repo, SessionController session, Widget home) => MultiProvider(
      providers: [
        Provider<AcaApi>.value(value: repo.api),
        Provider<AcaRepository>.value(value: repo),
        ChangeNotifierProvider<SessionController>.value(value: session),
      ],
      child: MaterialApp(
        theme: AcaTheme.darkTheme,
        // The brief's quality bar: nothing may overflow at 360dp wide with 1.3x system text.
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
        home: home,
      ),
    );

/// Scrolls the page until [finder] is fully on screen (ListView builds lazily).
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Scrolls [finder] into view inside whatever scrollable holds it, then taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// flutter_test draws every glyph as a full-width square (the Ahem font), which makes
/// overflow checks absurdly pessimistic. Load the real Roboto from the SDK so layout
/// at 360dp / 1.3x text is judged with realistic text widths.
Future<void> loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final loader = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
    final file = File('$root/bin/cache/artifacts/material_fonts/$f');
    if (file.existsSync()) loader.addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadRoboto);

  final roster = [
    staff('me', 'Me Myself', 'OWNER', twoFactor: true, sessions: 2, lastLogin: DateTime.now().subtract(const Duration(minutes: 3))),
    staff('a1', 'Amina Wanjiru', 'ADMIN', twoFactor: true, sessions: 1, lastLogin: DateTime.now().subtract(const Duration(hours: 5))),
    staff('s1', 'Brian Otieno', 'SUPPORT', invite: true),
    staff('f1', 'Carol Njeri', 'FINANCE', locked: true, sessions: 0, lastLogin: DateTime.now().subtract(const Duration(days: 2))),
    staff('v1', 'Dan Kimani', 'VIEWER', status: 'DISABLED', lastLogin: DateTime.now().subtract(const Duration(days: 30))),
  ];

  group('TeamScreen', () {
    testWidgets('groups staff, flags problems and highlights the signed-in person', (tester) async {
      final (repo, session) = await setup(tester, myRole: 'OWNER', members: roster);
      await tester.pumpWidget(app(repo, session, const TeamScreen()));
      await settle(tester);

      expect(find.text('Team'), findsOneWidget);
      expect(find.text('ACTIVE · 4'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Amina Wanjiru'), findsOneWidget);
      await reveal(tester, find.text('Dan Kimani'));
      expect(find.text('DISABLED · 1'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Invite pending'), findsOneWidget);
      expect(find.textContaining('Never signed in'), findsWidgets);
      expect(find.byTooltip('Roles & access'), findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, 'Add staff'), findsOneWidget);
    });

    testWidgets('a role that can only view has no Add staff button', (tester) async {
      final (repo, session) = await setup(tester, myRole: 'SECURITY', members: roster);
      await tester.pumpWidget(app(repo, session, const TeamScreen()));
      await settle(tester);

      expect(find.text('Amina Wanjiru'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('someone without team.view sees a not-allowed state and no request is needed', (tester) async {
      final (repo, session) = await setup(tester, myRole: 'VIEWER', members: roster);
      await tester.pumpWidget(app(repo, session, const TeamScreen()));
      await settle(tester);

      expect(find.text('Not allowed for your role'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('an admin can only pick roles below admin when adding staff', (tester) async {
      final (repo, session) = await setup(tester, myRole: 'ADMIN', members: roster);
      await tester.pumpWidget(app(repo, session, const TeamScreen()));
      await settle(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add staff'));
      await settle(tester);

      final sheet = find.byType(BottomSheet);
      expect(find.descendant(of: sheet, matching: find.text('Security')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Viewer')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Owner')), findsNothing);
      expect(find.descendant(of: sheet, matching: find.text('Admin')), findsNothing);
      expect(find.descendant(of: sheet, matching: find.text(_descriptions['VIEWER']!)), findsOneWidget);
    });

    testWidgets('adding staff validates, shows the one-time password and keeps the sheet until Done', (tester) async {
      final (repo, session) = await setup(tester, myRole: 'OWNER', members: roster);
      await tester.pumpWidget(app(repo, session, const TeamScreen()));
      await settle(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add staff'));
      await settle(tester);

      final submit = find.widgetWithText(FilledButton, 'Add staff');
      await tapVisible(tester, submit);
      await settle(tester);
      expect(find.text('Enter their full name'), findsOneWidget);
      expect(find.text('Enter their work email'), findsOneWidget);
      expect(repo.calls, isEmpty);

      await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Grace Mwangi');
      await tester.enterText(find.widgetWithText(TextFormField, 'Work email'), 'grace@archeaxon.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Phone (optional)'), '0700 111 222');
      // Let the text fields finish scrolling their caret into view before we scroll elsewhere.
      await tester.pumpAndSettle();
      await tapVisible(tester, find.descendant(of: find.byType(BottomSheet), matching: find.text('Support')));
      await tester.pumpAndSettle();
      await tapVisible(tester, submit);
      await settle(tester);

      expect(repo.calls, ['create:grace@archeaxon.com:Grace Mwangi:SUPPORT:0700 111 222']);
      expect(find.text('Staff member added'), findsOneWidget);
      expect(find.text('Zq7!mK2#pL9@vX4t'), findsOneWidget);
      expect(find.text('grace@archeaxon.com'), findsOneWidget);
      expect(find.text('Will not be shown again'), findsOneWidget);
      expect(find.text('Copy password'), findsOneWidget);

      // The system back button must not close it.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Zq7!mK2#pL9@vX4t'), findsOneWidget);

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Done'));
      await settle(tester);
      expect(find.text('Zq7!mK2#pL9@vX4t'), findsNothing);
    });

    testWidgets('a server error stays inside the form so it is not hidden behind the sheet', (tester) async {
      final (repo, session) = await setup(tester, myRole: 'OWNER', members: roster);
      repo.createError = ApiException(409, 'A staff member with that email already exists.');
      await tester.pumpWidget(app(repo, session, const TeamScreen()));
      await settle(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add staff'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Grace Mwangi');
      await tester.enterText(find.widgetWithText(TextFormField, 'Work email'), 'amina@archeaxon.com');
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Add staff');
      await tapVisible(tester, submit);
      await settle(tester);

      expect(find.text('A staff member with that email already exists.'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Staff member added'), findsNothing);
    });
  });

  group('RolesScreen', () {
    testWidgets('lists every role with a permission checklist and marks yours', (tester) async {
      final (repo, session) = await setup(tester, myRole: 'ADMIN', members: roster);
      await tester.pumpWidget(app(repo, session, const RolesScreen()));
      await settle(tester);

      expect(find.text('Roles & access'), findsOneWidget);
      expect(find.textContaining('You can give out: Security, Finance, Support, Viewer.'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      await reveal(tester, find.text('Your role'));
      expect(find.text('Your role'), findsOneWidget);
      await reveal(tester, find.text(_descriptions['VIEWER']!));
      expect(find.text('You can assign'), findsWidgets);
    });
  });

  group('StaffDetailScreen', () {
    testWidgets('an owner sees the full set of actions, devices and activity for an admin', (tester) async {
      final members = [
        roster.first,
        staff('a1', 'Amina Wanjiru', 'ADMIN',
            twoFactor: true,
            locked: true,
            sessions: 1,
            phone: '+254 700 000 111',
            lastLogin: DateTime.now().subtract(const Duration(hours: 5)),
            activity: [audit('me@archeaxon.com updated amina@archeaxon.com')]),
      ];
      final (repo, session) = await setup(tester, myRole: 'OWNER', members: members);
      await tester.pumpWidget(app(repo, session, const StaffDetailScreen(staffId: 'a1', name: 'Amina Wanjiru')));
      await settle(tester);

      expect(find.text('amina@archeaxon.com'), findsWidgets);
      expect(find.text('+254 700 000 111'), findsOneWidget);
      for (final label in ['Edit details', 'Change role', 'Reset password', 'Unlock account', 'Sign out of all devices', 'Disable account']) {
        await reveal(tester, find.widgetWithText(ListTile, label));
        expect(find.widgetWithText(ListTile, label), findsOneWidget, reason: label);
      }
      await reveal(tester, find.text('Pixel 7 · ACA 1.0.0'));
      await reveal(tester, find.text('See everything this person did'));
      expect(find.text('me@archeaxon.com updated amina@archeaxon.com'), findsOneWidget);
    });

    testWidgets('an admin looking at an owner gets read-only information', (tester) async {
      final members = [staff('me', 'Me Myself', 'ADMIN', twoFactor: true), staff('o1', 'Olive Owner', 'OWNER', locked: true, sessions: 2)];
      final (repo, session) = await setup(tester, myRole: 'ADMIN', members: members);
      await tester.pumpWidget(app(repo, session, const StaffDetailScreen(staffId: 'o1', name: 'Olive Owner')));
      await settle(tester);

      expect(find.text('Olive Owner'), findsWidgets);
      expect(find.text('Actions'.toUpperCase()), findsNothing);
      expect(find.widgetWithText(ListTile, 'Reset password'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Unlock account'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Disable account'), findsNothing);
    });

    testWidgets('resetting a password confirms, calls the server and shows the one-time password', (tester) async {
      final members = [roster.first, staff('s1', 'Brian Otieno', 'SUPPORT', sessions: 1)];
      final (repo, session) = await setup(tester, myRole: 'OWNER', members: members);
      await tester.pumpWidget(app(repo, session, const StaffDetailScreen(staffId: 's1', name: 'Brian Otieno')));
      await settle(tester);

      final tile = find.widgetWithText(ListTile, 'Reset password');
      await reveal(tester, tile);
      await tester.tap(tile);
      await settle(tester);
      expect(find.textContaining('signed out on every device'), findsOneWidget);
      expect(repo.calls, isEmpty, reason: 'nothing happens before the confirmation');

      await tapVisible(tester, find.widgetWithText(FilledButton, 'Reset password'));
      await settle(tester);

      expect(repo.calls, ['reset:s1']);
      expect(find.text('Password reset'), findsOneWidget);
      expect(find.text('Rt5#nB8!wQ3@cY6h'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Done'));
      await settle(tester);
      expect(find.text('Rt5#nB8!wQ3@cY6h'), findsNothing);
    });

    testWidgets('changing a role only offers assignable roles and warns about the sign-out', (tester) async {
      final members = [staff('me', 'Me Myself', 'ADMIN', twoFactor: true), staff('s1', 'Brian Otieno', 'SUPPORT')];
      final (repo, session) = await setup(tester, myRole: 'ADMIN', members: members);
      await tester.pumpWidget(app(repo, session, const StaffDetailScreen(staffId: 's1', name: 'Brian Otieno')));
      await settle(tester);

      final tile = find.widgetWithText(ListTile, 'Change role');
      await reveal(tester, tile);
      await tester.tap(tile);
      await settle(tester);

      final sheet = find.byType(BottomSheet);
      expect(find.descendant(of: sheet, matching: find.text('Current role')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Owner')), findsNothing);
      expect(find.descendant(of: sheet, matching: find.text('Admin')), findsNothing);

      await tapVisible(tester, find.descendant(of: sheet, matching: find.text('Finance')));
      await settle(tester);
      expect(find.text('Change role to Finance?'), findsOneWidget);
      expect(find.textContaining('signed out of every device'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Change role'));
      await settle(tester);
      expect(repo.calls, ['update:s1::FINANCE::']);
    });

    testWidgets('your own page offers no role, status or reset actions', (tester) async {
      final members = [staff('me', 'Me Myself', 'OWNER', twoFactor: true, sessions: 1)];
      final (repo, session) = await setup(tester, myRole: 'OWNER', members: members);
      await tester.pumpWidget(app(repo, session, const StaffDetailScreen(staffId: 'me', name: 'Me Myself')));
      await settle(tester);

      expect(find.textContaining('This is your account'), findsOneWidget);
      await reveal(tester, find.widgetWithText(ListTile, 'Edit details'));
      expect(find.widgetWithText(ListTile, 'Edit details'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Change role'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Reset password'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Disable account'), findsNothing);
    });

    testWidgets('failing to load the devices does not break the page', (tester) async {
      final members = [roster.first, staff('s1', 'Brian Otieno', 'SUPPORT')];
      final (repo, session) = await setup(tester, myRole: 'OWNER', members: members);
      repo.sessionsError = ApiException(403, 'Your role cannot act on this staff member.');
      await tester.pumpWidget(app(repo, session, const StaffDetailScreen(staffId: 's1', name: 'Brian Otieno')));
      await settle(tester);

      await reveal(tester, find.text('Your role cannot act on this staff member.'));
      expect(find.text('Your role cannot act on this staff member.'), findsOneWidget);
    });
  });
}
