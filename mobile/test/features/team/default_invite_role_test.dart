import 'package:axon_pos/features/team/presentation/screens/invite_staff_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an invite starts on the least-privileged role, not the first one', () {
    final roles = [
      {'id': 'r1', 'name': 'Admin'},
      {'id': 'r2', 'name': 'Manager'},
      {'id': 'r3', 'name': 'Cashier'},
    ];
    expect(defaultInviteRoleId(roles), 'r3');
  });

  test('role names match whatever their case', () {
    expect(
      defaultInviteRoleId([
        {'id': 'a', 'name': 'ADMIN'},
        {'id': 'b', 'name': ' seller '},
      ]),
      'b',
    );
  });

  test('with no everyday role the choice is left empty, never Admin', () {
    expect(
      defaultInviteRoleId([
        {'id': 'a', 'name': 'Admin'},
        {'id': 'b', 'name': 'Owner'},
      ]),
      isNull,
    );
    expect(defaultInviteRoleId([]), isNull);
  });
}
