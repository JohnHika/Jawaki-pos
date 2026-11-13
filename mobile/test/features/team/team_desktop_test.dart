import 'package:axon_pos/core/desktop/desktop_widgets.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/features/team/presentation/desktop/invitations_desktop_page.dart';
import 'package:axon_pos/features/team/presentation/desktop/invite_staff_panel.dart';
import 'package:axon_pos/features/users/data/models/permission_catalog.dart';
import 'package:axon_pos/features/users/presentation/desktop/permission_matrix.dart';
import 'package:axon_pos/features/users/presentation/desktop/roles_desktop_page.dart';
import 'package:axon_pos/features/users/presentation/desktop/team_desktop_widgets.dart';
import 'package:axon_pos/features/users/presentation/desktop/users_desktop_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import '../../support/shot.dart';
import '../settings/support/desktop_host.dart';

Map<String, dynamic> _user(
  String id,
  String first,
  String last,
  String role, {
  bool active = true,
  String? lastLogin,
  String branch = 'Kamukunji main',
}) =>
    {
      'id': id,
      'firstName': first,
      'lastName': last,
      'email': '${first.toLowerCase()}.${last.toLowerCase()}@mamanjeri.co.ke',
      'phone': '0712 345 678',
      'isActive': active,
      'lastLoginAt': lastLogin,
      'roles': [
        {'id': 'r-$role', 'name': role}
      ],
      'branches': [
        {'id': 'b1', 'name': branch, 'isPrimary': true}
      ],
    };

final _now = DateTime.now();
String _ago(Duration d) => _now.subtract(d).toUtc().toIso8601String();

final _users = [
  for (final u in [
    _user('1', 'Wanjiku', 'Kamau', 'Owner',
        lastLogin: _ago(const Duration(minutes: 3))),
    _user('2', 'Otieno', 'Odhiambo', 'Manager',
        lastLogin: _ago(const Duration(hours: 5))),
    _user('3', 'Akinyi', 'Achieng', 'Cashier',
        lastLogin: _ago(const Duration(days: 1))),
    _user('4', 'Mwangi', 'Gathogo', 'Cashier',
        lastLogin: _ago(const Duration(days: 3)), branch: 'Githurai'),
    _user('5', 'Halima', 'Abdalla', 'Stock clerk',
        lastLogin: _ago(const Duration(days: 20))),
    _user('6', 'Kiprono', 'Chebet', 'Cashier',
        active: false, lastLogin: _ago(const Duration(days: 90))),
    _user('7', 'Naserian', 'Lekishon', 'Cashier'),
  ])
    DesktopTeamUser.fromJson(u),
];

List<PermissionFeatureGroup> _catalog() {
  PermissionDef d(String feature, String action, String label) => PermissionDef(
        key: '$feature.$action',
        feature: feature,
        action: action,
        label: label,
      );
  return [
    PermissionFeatureGroup(feature: 'sales', permissions: [
      d('sales', 'view', 'See sales'),
      d('sales', 'create', 'Make a sale'),
      d('sales', 'void', 'Void a sale'),
      d('sales', 'refund', 'Refund a sale'),
      d('sales', 'discount', 'Give a discount'),
    ]),
    PermissionFeatureGroup(feature: 'products', permissions: [
      d('products', 'view', 'See products'),
      d('products', 'create', 'Add products'),
      d('products', 'update', 'Edit products'),
      d('products', 'delete', 'Delete products'),
    ]),
    PermissionFeatureGroup(feature: 'expenses', permissions: [
      d('expenses', 'view', 'See expenses'),
      d('expenses', 'create', 'Record expenses'),
      d('expenses', 'update', 'Edit expenses'),
      d('expenses', 'delete', 'Delete expenses'),
      d('expenses', 'approve', 'Approve expenses'),
      d('expenses', 'mark_paid', 'Mark expenses paid'),
    ]),
    PermissionFeatureGroup(feature: 'customers', permissions: [
      d('customers', 'view', 'See customers'),
      d('customers', 'create', 'Add customers'),
      d('customers', 'update', 'Edit customers'),
      d('customers', 'credit_view', 'See customer credit'),
    ]),
    PermissionFeatureGroup(feature: 'cash_flow', permissions: [
      d('cash_flow', 'settings_view', 'See cash flow settings'),
      d('cash_flow', 'settings_update', 'Change cash flow settings'),
    ]),
  ];
}

class _Spy extends ApiClient {
  _Spy() : super(Dio());

  Map<String, dynamic>? sent;
  Object? failSend;

  @override
  Future<List<dynamic>> getStaffInvitationRoles() async => [
        {'id': 'r1', 'name': 'Manager'},
        {'id': 'r2', 'name': 'Cashier'},
      ];

  @override
  Future<List<dynamic>> getBranches() async => [
        {'id': 'b1', 'name': 'Kamukunji main'},
      ];

  @override
  Future<Map<String, dynamic>> createStaffInvitation({
    required String email,
    required String firstName,
    required String lastName,
    required String roleId,
    required String branchId,
  }) async {
    if (failSend != null) throw failSend!;
    sent = {
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'roleId': roleId,
      'branchId': branchId,
    };
    return {};
  }
}

Widget _usersPage({
  List<DesktopTeamUser>? users,
  bool loading = false,
  String? error,
  List<String>? log,
}) =>
    Scaffold(
      body: DesktopUsersPage(
        users: users ?? _users,
        loading: loading,
        error: error,
        canInvite: true,
        canManageRoles: true,
        onTab: (t) => log?.add('tab:${t.name}'),
        onRefresh: () => log?.add('refresh'),
        onInvite: () => log?.add('invite'),
        onEditPermissions: (u) => log?.add('permissions:${u.id}'),
      ),
    );

class _EditorHost extends StatefulWidget {
  const _EditorHost({this.initial = const {}, this.readLog});

  final Set<String> initial;
  final void Function(Set<String>)? readLog;

  @override
  State<_EditorHost> createState() => _EditorHostState();
}

class _EditorHostState extends State<_EditorHost> {
  late final Set<String> keys = {...widget.initial};
  final name = TextEditingController(text: 'Shift supervisor');
  final description =
      TextEditingController(text: 'Runs the till and closes the day');
  int saves = 0;

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.readLog?.call(keys);
    return Scaffold(
      body: DesktopRoleEditorView(
        isNew: false,
        isSystem: false,
        nameController: name,
        descriptionController: description,
        groups: _catalog(),
        selectedKeys: keys,
        onChanged: (ks, v) => setState(() {
          if (v) {
            keys.addAll(ks);
          } else {
            keys.removeAll(ks);
          }
        }),
        onSave: () => saves++,
        onBack: () {},
        onDelete: () {},
      ),
    );
  }
}

void main() {
  setUpAll(loadShotFonts);
  setUp(pretendToBeAComputer);

  group('users table', () {
    for (final dark in [false, true]) {
      for (final size in [laptop, laptopScaled]) {
        final mode = dark ? 'dark' : 'light';
        testWidgets('screenshot $mode ${size.width.toInt()}', (tester) async {
          useWindow(tester, size);
          final key = GlobalKey();
          await tester.pumpWidget(desktopHost(
            boundary: key,
            dark: dark,
            location: '/users',
            page: _usersPage(),
          ));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('Akinyi Achieng'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await saveShot(tester, key,
              'build/shots/settings-users-$mode-${size.width.toInt()}.png');
        });
      }
    }

    testWidgets('lists name, role, last active and status', (tester) async {
      useWindow(tester, laptop);
      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(), location: '/users', page: _usersPage()));
      await tester.pump(const Duration(milliseconds: 300));
      for (final text in [
        'Name',
        'Role',
        'Branch',
        'Last active',
        'Status',
        'Wanjiku Kamau',
        'Never signed in',
        '3 min ago',
        'Inactive',
        'Invite user',
        '7 people · 1 inactive',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.text('Users'), findsWidgets);
      expect(find.text('Roles'), findsOneWidget);
      expect(find.text('Invitations'), findsOneWidget);
    });

    testWidgets('search and status filter narrow the table', (tester) async {
      useWindow(tester, laptop);
      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(), location: '/users', page: _usersPage()));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(
          find.byKey(const ValueKey('team-search')), 'cashier');
      await tester.pump();
      expect(find.text('Akinyi Achieng'), findsOneWidget);
      expect(find.text('Otieno Odhiambo'), findsNothing);
      expect(find.text('Showing 4 of 7'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('team-search')), '');
      await tester.tap(find.widgetWithText(DesktopFilterChip, 'Inactive'));
      await tester.pump();
      expect(find.text('Kiprono Chebet'), findsOneWidget);
      expect(find.text('Akinyi Achieng'), findsNothing);
    });

    testWidgets('a row opens the inspector; the button edits permissions',
        (tester) async {
      final log = <String>[];
      useWindow(tester, laptop);
      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(),
          location: '/users',
          page: _usersPage(log: log)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('team-edit-permissions')), findsNothing);

      await tester.tap(find.text('Mwangi Gathogo'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('team-edit-permissions')), findsOneWidget);
      expect(find.text('Githurai'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('team-edit-permissions')));
      expect(log, ['permissions:4']);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('team-edit-permissions')), findsNothing);
    });

    testWidgets('invite and tabs call back', (tester) async {
      final log = <String>[];
      useWindow(tester, laptop);
      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(),
          location: '/users',
          page: _usersPage(log: log)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('team-invite-button')));
      await tester.tap(find.byKey(const ValueKey('team-tab-roles')));
      await tester.tap(find.byKey(const ValueKey('team-tab-invitations')));
      expect(log, ['invite', 'tab:roles', 'tab:invitations']);
    });

    testWidgets('empty, loading and error states teach the page',
        (tester) async {
      useWindow(tester, laptop);
      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(),
          location: '/users',
          page: _usersPage(users: const [])));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No team members yet'), findsOneWidget);

      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(),
          location: '/users',
          page: _usersPage(users: const [], loading: true)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No team members yet'), findsNothing);

      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(),
          location: '/users',
          page: _usersPage(
              users: const [],
              error: 'Something went wrong. Please try again.')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Could not load your team'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('300 people stay smooth', (tester) async {
      useWindow(tester, laptop);
      final many = [
        for (var i = 0; i < 300; i++)
          DesktopTeamUser.fromJson(
              _user('u$i', 'Person', 'Number$i', 'Cashier')),
      ];
      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(),
          location: '/users',
          page: _usersPage(users: many)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('300 people'), findsWidgets);
    });
  });

  group('permission matrix', () {
    for (final dark in [false, true]) {
      for (final size in [laptop, laptopScaled]) {
        final mode = dark ? 'dark' : 'light';
        testWidgets('role editor screenshot $mode ${size.width.toInt()}',
            (tester) async {
          useWindow(tester, size);
          final key = GlobalKey();
          await tester.pumpWidget(desktopHost(
            boundary: key,
            dark: dark,
            location: '/users',
            page: const _EditorHost(initial: {
              'sales.view',
              'sales.create',
              'sales.discount',
              'products.view',
              'expenses.view',
              'expenses.create',
              'customers.view',
              'customers.create',
              'customers.update',
            }),
          ));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byKey(const ValueKey('matrix-more-sales')));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await saveShot(tester, key,
              'build/shots/settings-roles-$mode-${size.width.toInt()}.png');
        });
      }
    }

    testWidgets('a cell toggles one permission', (tester) async {
      Set<String> keys = {};
      useWindow(tester, laptop);
      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(),
          location: '/users',
          page: _EditorHost(readLog: (k) => keys = k)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('matrix-products-edit')));
      await tester.pump();
      expect(keys, {'products.update'});
      await tester.tap(find.byKey(const ValueKey('matrix-products-edit')));
      await tester.pump();
      expect(keys, isEmpty);
    });

    testWidgets('the row box and the column header switch many at once',
        (tester) async {
      Set<String> keys = {};
      useWindow(tester, laptop);
      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(),
          location: '/users',
          page: _EditorHost(readLog: (k) => keys = k)));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('matrix-all-products')));
      await tester.pump();
      expect(keys, {
        'products.view',
        'products.create',
        'products.update',
        'products.delete',
      });

      // The View column header turns every View permission on.
      await tester.tap(find.text('View').first);
      await tester.pump();
      expect(
          keys.containsAll([
            'sales.view',
            'products.view',
            'expenses.view',
            'customers.view',
          ]),
          isTrue);
      // ...and a second tap turns them all off again.
      await tester.tap(find.text('View').first);
      await tester.pump();
      expect(keys.contains('sales.view'), isFalse);
      expect(keys.contains('products.create'), isTrue);
    });

    testWidgets('More opens permissions that are not View, Create, Edit...',
        (tester) async {
      Set<String> keys = {};
      useWindow(tester, laptop);
      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(),
          location: '/users',
          page: _EditorHost(readLog: (k) => keys = k)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Void a sale'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('matrix-more-sales')));
      await tester.pump();
      expect(find.text('Void a sale'), findsOneWidget);
      await tester.tap(find.text('Void a sale'));
      await tester.pump();
      expect(keys, {'sales.void'});
    });

    testWidgets('Ctrl+S saves', (tester) async {
      useWindow(tester, laptop);
      await tester.pumpWidget(desktopHost(
          boundary: GlobalKey(),
          location: '/users',
          page: const _EditorHost()));
      await tester.pump(const Duration(milliseconds: 300));
      final state = tester.state<_EditorHostState>(find.byType(_EditorHost));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      expect(state.saves, 1);
    });

    test('actions map to the five columns', () {
      PermissionDef def(String a) =>
          PermissionDef(key: 'x.$a', feature: 'x', action: a, label: a);
      expect(MatrixColumn.of(def('view')), MatrixColumn.view);
      expect(MatrixColumn.of(def('update')), MatrixColumn.edit);
      expect(MatrixColumn.of(def('approve')), MatrixColumn.approve);
      expect(MatrixColumn.of(def('void')), isNull);
      expect(MatrixColumn.of(def('view_all')), isNull);
    });
  });

  group('roles table', () {
    testWidgets('lists roles with counts and opens one', (tester) async {
      DesktopRoleRow? opened;
      useWindow(tester, laptop);
      await tester.pumpWidget(desktopHost(
        boundary: GlobalKey(),
        location: '/users/roles',
        page: Scaffold(
          body: DesktopRolesPage(
            roles: [
              for (final r in [
                {
                  'id': 'a',
                  'name': 'Admin',
                  'isSystem': true,
                  'permissionKeys': List.filled(40, 'x'),
                  'userCount': 1
                },
                {
                  'id': 'b',
                  'name': 'Cashier',
                  'isSystem': true,
                  'permissionKeys': List.filled(6, 'x'),
                  'userCount': 4
                },
                {
                  'id': 'c',
                  'name': 'Shift supervisor',
                  'isSystem': false,
                  'permissionKeys': List.filled(18, 'x'),
                  'userCount': 2
                },
              ])
                DesktopRoleRow.fromJson(r),
            ],
            canCreate: true,
            canEdit: true,
            canInvite: true,
            onTab: (_) {},
            onRefresh: () {},
            onNewRole: () {},
            onOpenRole: (r) => opened = r,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Shift supervisor'), findsOneWidget);
      expect(find.text('Built in'), findsNWidgets(2));
      expect(find.text('New role'), findsOneWidget);
      await tester.tap(find.text('Shift supervisor'));
      expect(opened?.id, 'c');
    });
  });

  group('invitations table', () {
    testWidgets('shows status, and an empty page invites', (tester) async {
      useWindow(tester, laptop);
      await tester.pumpWidget(desktopHost(
        boundary: GlobalKey(),
        location: '/users/invitations',
        page: Scaffold(
          body: DesktopInvitationsPage(
            invitations: [
              DesktopInvitationRow.fromJson({
                'id': 'i1',
                'firstName': 'Naserian',
                'lastName': 'Lekishon',
                'email': 'naserian@mamanjeri.co.ke',
                'status': 'PENDING',
                'role': {'name': 'Cashier'},
                'branch': {'name': 'Kamukunji main'},
                'createdBy': {'firstName': 'Wanjiku', 'lastName': 'Kamau'},
                'createdAt': _ago(const Duration(hours: 2)),
              }, 0),
              DesktopInvitationRow.fromJson({
                'id': 'i2',
                'firstName': 'Halima',
                'lastName': 'Abdalla',
                'email': 'halima@mamanjeri.co.ke',
                'status': 'ACCEPTED',
                'role': {'name': 'Stock clerk'},
                'branch': {'name': 'Githurai'},
                'createdBy': {'firstName': 'Wanjiku', 'lastName': 'Kamau'},
                'createdAt': _ago(const Duration(days: 20)),
              }, 1),
            ],
            canManageRoles: true,
            onTab: (_) {},
            onRefresh: () {},
            onInvite: () {},
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('2 sent · 1 waiting for an answer'), findsOneWidget);

      await tester.pumpWidget(desktopHost(
        boundary: GlobalKey(),
        location: '/users/invitations',
        page: Scaffold(
          body: DesktopInvitationsPage(
            invitations: const [],
            onTab: (_) {},
            onRefresh: () {},
            onInvite: () {},
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No invitations sent yet'), findsOneWidget);
    });
  });

  group('invite panel', () {
    late _Spy spy;

    setUp(() {
      spy = _Spy();
      final getIt = GetIt.instance;
      if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
      getIt.registerSingleton<ApiClient>(spy);
    });

    Future<void> open(WidgetTester tester, GlobalKey key,
        {bool dark = false}) async {
      await tester.pumpWidget(desktopHost(
        boundary: key,
        dark: dark,
        location: '/users',
        page: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showInviteStaffPanel(context),
                child: const Text('open panel'),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('open panel'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('opens as a side panel, validates, sends and closes',
        (tester) async {
      useWindow(tester, laptop);
      final key = GlobalKey();
      await open(tester, key);
      expect(find.text('Invite user'), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-email')), findsOneWidget);
      expect(tester.getTopLeft(find.text('Invite user')).dx, greaterThan(800));
      // Cashier is preselected, never the first (Manager).
      expect(find.text('Cashier'), findsOneWidget);
      await saveShot(tester, key, 'build/shots/settings-invite-light-1366.png');

      await tester.tap(find.byKey(const ValueKey('invite-send')));
      await tester.pump();
      expect(find.text('Required'), findsWidgets);
      expect(spy.sent, isNull);

      await tester.enterText(
          find.byKey(const ValueKey('invite-first-name')), 'Naserian');
      await tester.enterText(
          find.byKey(const ValueKey('invite-last-name')), 'Lekishon');
      await tester.enterText(
          find.byKey(const ValueKey('invite-email')), 'not an email');
      await tester.tap(find.byKey(const ValueKey('invite-send')));
      await tester.pump();
      expect(find.text('Enter a valid email address'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('invite-email')),
          'naserian@mamanjeri.co.ke');
      await tester.tap(find.byKey(const ValueKey('invite-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(spy.sent, {
        'email': 'naserian@mamanjeri.co.ke',
        'firstName': 'Naserian',
        'lastName': 'Lekishon',
        'roleId': 'r2',
        'branchId': 'b1',
      });
      expect(find.text('Invite user'), findsNothing);
    });

    testWidgets('says what went wrong when sending fails', (tester) async {
      spy.failSend = Exception('boom');
      useWindow(tester, laptopScaled);
      await open(tester, GlobalKey(), dark: true);
      await tester.enterText(
          find.byKey(const ValueKey('invite-first-name')), 'A');
      await tester.enterText(
          find.byKey(const ValueKey('invite-last-name')), 'B');
      await tester.enterText(
          find.byKey(const ValueKey('invite-email')), 'a.b@example.com');
      await tester.tap(find.byKey(const ValueKey('invite-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('We could not send the invitation'),
          findsOneWidget);
      expect(find.text('Invite user'), findsOneWidget);
    });
  });

  test('last active reads in the shop owner\'s words', () {
    final now = DateTime(2026, 11, 10, 12);
    expect(lastActiveLabel(null, now: now), 'Never signed in');
    expect(lastActiveLabel(now, now: now), 'Just now');
    expect(lastActiveLabel(now.subtract(const Duration(minutes: 5)), now: now),
        '5 min ago');
    expect(lastActiveLabel(now.subtract(const Duration(days: 1)), now: now),
        'Yesterday');
    expect(lastActiveLabel(DateTime(2026, 10, 4), now: now), '4 Oct 2026');
  });
}
