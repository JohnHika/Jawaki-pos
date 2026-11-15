import 'package:axon_pos/features/users/data/models/permission_catalog.dart';
import 'package:axon_pos/features/users/presentation/desktop/desktop_local_staff_view.dart';
import 'package:axon_pos/features/users/presentation/desktop/desktop_user_permissions_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

const _roles = [
  DesktopStaffRole(
    name: 'Cashier',
    description: 'Sells and records payments. Cannot change prices.',
  ),
  DesktopStaffRole(
    name: 'Stock keeper',
    description: 'Counts and adjusts stock. Cannot sell.',
  ),
  DesktopStaffRole(
    name: 'Manager',
    description: 'Everything a cashier and stock keeper can do, plus voids.',
  ),
];

const _staff = [
  DesktopLocalStaff(id: '1', name: 'Achieng Otieno', role: 'Cashier', active: true),
  DesktopLocalStaff(id: '2', name: 'Brian Kamau', role: 'Stock keeper', active: true),
  DesktopLocalStaff(id: '3', name: 'Faith Njeri', role: 'Manager', active: false),
];

Widget _staffView({
  bool isOwner = true,
  List<DesktopLocalStaff> staff = _staff,
  VoidCallback? onAdd,
  ValueChanged<DesktopLocalStaff>? onEdit,
  ValueChanged<DesktopLocalStaff>? onToggle,
}) =>
    DesktopLocalStaffView(
      isOwner: isOwner,
      staff: staff,
      roles: _roles,
      saving: false,
      onAdd: onAdd ?? () {},
      onEdit: onEdit ?? (_) {},
      onToggle: onToggle ?? (_) {},
    );

const _catalog = [
  PermissionFeatureGroup(feature: 'sales', permissions: [
    PermissionDef(key: 'sales.view', feature: 'sales', action: 'view', label: 'View sales'),
    PermissionDef(key: 'sales.void', feature: 'sales', action: 'void', label: 'Void a sale'),
    PermissionDef(key: 'sales.discount', feature: 'sales', action: 'discount', label: 'Give discounts'),
  ]),
  PermissionFeatureGroup(feature: 'cash_flow', permissions: [
    PermissionDef(key: 'cash_flow.view', feature: 'cash_flow', action: 'view', label: 'View cash flow'),
    PermissionDef(key: 'cash_flow.close', feature: 'cash_flow', action: 'close', label: 'Close the day'),
  ]),
];

Widget _permView({
  void Function(DesktopRoleToggle)? onRole,
  void Function(String, DesktopPermState)? onOverride,
}) =>
    DesktopUserPermissionsView(
      userLabel: 'Achieng Otieno · achieng@example.com',
      roles: const [
        DesktopRoleToggle(id: 'r1', name: 'Cashier', assigned: true),
        DesktopRoleToggle(id: 'r2', name: 'Manager', assigned: false),
        DesktopRoleToggle(id: 'r3', name: 'Stock keeper', assigned: false),
      ],
      groups: _catalog,
      fromRoles: const {'sales.view', 'sales.discount', 'cash_flow.view'},
      granted: const {'cash_flow.close'},
      revoked: const {'sales.discount'},
      onToggleRole: onRole ?? (_) {},
      onSetOverride: onOverride ?? (_, __) {},
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('local-staff', () => _staffView());
  shotMatrix('local-staff-open', () => _staffView(),
      beforeShot: (tester) async {
    await tester.tap(find.text('Brian Kamau'));
    await tester.pumpAndSettle();
  });
  shotMatrix('user-permissions', () => _permView());

  testWidgets('staff: the guide shows until a person is opened',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_staffView()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local-staff-guide')), findsOneWidget);
    await tester.tap(find.text('Faith Njeri'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local-staff-inspector')), findsOneWidget);
    expect(find.text('Enable access'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local-staff-guide')), findsOneWidget);
  });

  testWidgets('staff: add, edit and pause call back with the person',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    var added = 0;
    String? edited;
    String? toggled;
    await tester.pumpWidget(desktopApp(_staffView(
      onAdd: () => added++,
      onEdit: (s) => edited = s.id,
      onToggle: (s) => toggled = s.id,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('local-staff-add')));
    expect(added, 1);
    await tester.tap(find.text('Achieng Otieno'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('local-staff-edit')));
    await tester.tap(find.byKey(const ValueKey('local-staff-toggle')));
    expect(edited, '1');
    expect(toggled, '1');
  });

  testWidgets('staff: not the owner means no staff list', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_staffView(isOwner: false)));
    await tester.pumpAndSettle();
    expect(find.text('Owner access required'), findsOneWidget);
    expect(find.byKey(const ValueKey('local-staff-add')), findsNothing);
  });

  testWidgets('staff: an empty team invites the first member', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_staffView(staff: const [])));
    await tester.pumpAndSettle();
    expect(find.text('No staff profiles yet'), findsOneWidget);
  });

  testWidgets('permissions: roles and overrides call back', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    String? role;
    String? override;
    await tester.pumpWidget(desktopApp(_permView(
      onRole: (r) => role = '${r.id}:${r.assigned}',
      onOverride: (k, s) => override = '$k:${s.name}',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perm-role-r1')));
    expect(role, 'r1:true');
    await tester.tap(find.byKey(const ValueKey('perm-sales.void-granted')));
    expect(override, 'sales.void:granted');
    await tester.tap(find.byKey(const ValueKey('perm-sales.discount-inherited')));
    expect(override, 'sales.discount:inherited');
  });

  testWidgets('permissions: search and overrides-only narrow the list',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_permView()));
    await tester.pumpAndSettle();
    expect(find.text('Void a sale'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'cash');
    await tester.pumpAndSettle();
    expect(find.text('Void a sale'), findsNothing);
    expect(find.text('Close the day'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byKey(const ValueKey('perm-only-overrides')));
    await tester.pumpAndSettle();
    expect(find.text('Give discounts'), findsOneWidget);
    expect(find.text('Close the day'), findsOneWidget);
    expect(find.text('View sales'), findsNothing);
  });
}
