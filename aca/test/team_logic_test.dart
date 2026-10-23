import 'package:flutter_test/flutter_test.dart';

import 'package:aca/core/permissions.dart';
import 'package:aca/core/theme.dart';
import 'package:aca/data/models.dart';
import 'package:aca/features/team/team_logic.dart';

const _ranks = {'OWNER': 100, 'ADMIN': 80, 'SECURITY': 60, 'FINANCE': 50, 'SUPPORT': 40, 'VIEWER': 10};

/// Role catalogue as `GET /team/roles` returns it for [actorRole]
/// (assignable = what `assignableRoles()` in the backend yields).
List<RoleInfo> catalog(String actorRole) {
  bool assignable(String r) {
    if (actorRole == 'OWNER') return true;
    if (actorRole == 'ADMIN') return _ranks[r]! < _ranks['ADMIN']!;
    return false;
  }

  return [
    for (final r in Roles.all)
      RoleInfo(role: r, rank: _ranks[r]!, description: '$r description', permissions: const [], assignable: assignable(r)),
  ];
}

StaffMember member({
  String id = 'u1',
  String name = 'Amina Wanjiru',
  String email = 'amina@archeaxon.com',
  String role = 'SUPPORT',
  String status = 'ACTIVE',
  bool mustChangePassword = false,
  bool twoFactor = false,
  bool locked = false,
  DateTime? lockedUntil,
  DateTime? lastLoginAt,
  DateTime? passwordChangedAt,
  int sessions = 0,
}) =>
    StaffMember(
      id: id,
      email: email,
      name: name,
      phone: null,
      role: role,
      status: status,
      permissions: const [],
      mustChangePassword: mustChangePassword,
      twoFactorEnabled: twoFactor,
      lastLoginAt: lastLoginAt,
      createdAt: null,
      locked: locked,
      lockedUntil: lockedUntil,
      failedLoginAttempts: 0,
      lastLoginIp: null,
      activeSessions: sessions,
      passwordChangedAt: passwordChangedAt,
    );

bool Function(String) perms(List<String> held) => held.toSet().contains;

void main() {
  group('staffFlags', () {
    test('an active account without 2FA gets the warning', () {
      expect(staffFlags(member()).map((f) => f.label), ['No 2FA']);
      expect(staffFlags(member()).single.tone, Tone.warning);
    });

    test('2FA on is a success pill', () {
      final f = staffFlags(member(twoFactor: true)).single;
      expect((f.label, f.tone), ('2FA on', Tone.success));
    });

    test('shows every problem, most important first', () {
      final labels = staffFlags(member(locked: true, mustChangePassword: true)).map((f) => f.label).toList();
      expect(labels, ['Locked', 'Invite pending', 'No 2FA']);
    });

    test('disabled accounts say so and skip the No 2FA warning', () {
      expect(staffFlags(member(status: 'DISABLED')).map((f) => f.label), ['Disabled']);
      expect(staffFlags(member(status: 'DISABLED', twoFactor: true)).map((f) => f.label), ['Disabled', '2FA on']);
    });

    test('flags carry a kind for icons', () {
      expect(staffFlags(member(locked: true)).first.kind, StaffFlagKind.locked);
      expect(staffFlags(member(mustChangePassword: true, twoFactor: true)).first.kind, StaffFlagKind.invitePending);
    });
  });

  group('groupStaff', () {
    test('active first, disabled separate, each by role then name', () {
      final groups = groupStaff([
        member(id: '1', name: 'zed', role: 'VIEWER'),
        member(id: '2', name: 'Bea', role: 'ADMIN'),
        member(id: '3', name: 'adam', role: 'ADMIN'),
        member(id: '4', name: 'Old Owner', role: 'OWNER', status: 'DISABLED'),
        member(id: '5', name: 'Cy', role: 'OWNER'),
        member(id: '6', name: 'Dee', role: 'SUPPORT', status: 'DISABLED'),
      ]);
      expect(groups.active.map((m) => m.id), ['5', '3', '2', '1']);
      expect(groups.disabled.map((m) => m.id), ['4', '6']);
    });

    test('unknown roles sort last and an empty list is fine', () {
      final groups = groupStaff([member(id: 'x', role: 'MYSTERY'), member(id: 'y', role: 'VIEWER')]);
      expect(groups.active.map((m) => m.id), ['y', 'x']);
      expect(groupStaff([]).active, isEmpty);
      expect(groupStaff([]).disabled, isEmpty);
    });

    test('does not mutate the input list', () {
      final input = [member(id: '1', role: 'VIEWER'), member(id: '2', role: 'OWNER')];
      groupStaff(input);
      expect(input.map((m) => m.id), ['1', '2']);
    });
  });

  group('row texts', () {
    final now = DateTime(2026, 10, 21, 12, 0);

    test('lastSignInText', () {
      expect(lastSignInText(null), 'Never signed in');
      expect(lastSignInText(now.subtract(const Duration(hours: 3)), now: now), 'Signed in 3 h ago');
      expect(lastSignInText(now.subtract(const Duration(seconds: 5)), now: now), 'Signed in just now');
    });

    test('sessionsText', () {
      expect(sessionsText(0), 'No active sessions');
      expect(sessionsText(1), '1 active session');
      expect(sessionsText(4), '4 active sessions');
    });

    test('lockedUntilText uses the time today and the date otherwise', () {
      expect(lockedUntilText(null), 'Locked');
      expect(lockedUntilText(DateTime(2026, 10, 21, 14, 30), now: now), 'Locked until 14:30');
      expect(lockedUntilText(DateTime(2026, 10, 22, 8, 5), now: now), 'Locked until 22 Oct 2026, 08:05');
    });

    test('passwordChangedText', () {
      expect(passwordChangedText(member(mustChangePassword: true)), contains('temporary'));
      expect(passwordChangedText(member(passwordChangedAt: DateTime(2026, 3, 12, 9, 15))), '12 Mar 2026, 09:15');
      expect(passwordChangedText(member()), '—');
    });
  });

  group('roles', () {
    test('assignableRoles is most powerful first and only what the server allowed', () {
      expect(assignableRoles(catalog('OWNER')).map((r) => r.role), ['OWNER', 'ADMIN', 'SECURITY', 'FINANCE', 'SUPPORT', 'VIEWER']);
      expect(assignableRoles(catalog('ADMIN')).map((r) => r.role), ['SECURITY', 'FINANCE', 'SUPPORT', 'VIEWER']);
      expect(assignableRoles(catalog('SECURITY')), isEmpty);
    });

    test('defaultNewStaffRole is the least powerful assignable role', () {
      expect(defaultNewStaffRole(assignableRoles(catalog('OWNER')))?.role, 'VIEWER');
      expect(defaultNewStaffRole(assignableRoles(catalog('ADMIN')))?.role, 'VIEWER');
      expect(defaultNewStaffRole(const []), isNull);
    });

    test('rankOf falls back to 0 for unknown roles', () {
      expect(rankOf(catalog('OWNER'), 'ADMIN'), 80);
      expect(rankOf(catalog('OWNER'), 'MYSTERY'), 0);
    });

    test('canAddStaff needs team.manage and something to assign', () {
      expect(canAddStaff(can: perms([Perm.teamManage]), roles: catalog('OWNER')), isTrue);
      expect(canAddStaff(can: perms([Perm.teamView]), roles: catalog('OWNER')), isFalse);
      expect(canAddStaff(can: perms([Perm.teamManage]), roles: catalog('SECURITY')), isFalse);
      expect(canAddStaff(can: perms([Perm.teamManage]), roles: const []), isFalse);
    });
  });

  group('canSecureStaff (mirrors canSecureTarget)', () {
    final roles = catalog('OWNER');
    bool secure(String me, String target, {String? targetId}) => canSecureStaff(
          myId: 'me',
          myRole: me,
          targetId: targetId ?? 'other',
          targetRole: target,
          roles: roles,
        );

    test('owner may act on anyone', () {
      for (final r in Roles.all) {
        expect(secure('OWNER', r), isTrue);
      }
    });

    test('everyone else only on strictly lower ranks', () {
      expect(secure('SECURITY', 'FINANCE'), isTrue);
      expect(secure('SECURITY', 'SECURITY'), isFalse);
      expect(secure('SECURITY', 'ADMIN'), isFalse);
      expect(secure('ADMIN', 'ADMIN'), isFalse);
      expect(secure('ADMIN', 'OWNER'), isFalse);
      expect(secure('ADMIN', 'SECURITY'), isTrue);
      expect(secure('VIEWER', 'VIEWER'), isFalse);
    });

    test('anyone may act on their own account', () {
      expect(secure('VIEWER', 'VIEWER', targetId: 'me'), isTrue);
    });
  });

  group('staffRights', () {
    StaffRights rights({
      required String myRole,
      required List<String> held,
      required StaffMember target,
      String myId = 'me',
    }) =>
        staffRights(can: perms(held), myId: myId, myRole: myRole, target: target, roles: catalog(myRole));

    const ownerPerms = [Perm.teamView, Perm.teamManage, Perm.securityView, Perm.securityManage, Perm.auditView];

    test('owner can do everything to an admin', () {
      final r = rights(myRole: 'OWNER', held: ownerPerms, target: member(role: 'ADMIN', locked: true, sessions: 2));
      expect(r.editProfile && r.changeRole && r.setStatus && r.resetPassword && r.unlock && r.signOutEverywhere, isTrue);
    });

    test('admin manages staff below admin but not admins or owners', () {
      for (final role in ['SECURITY', 'FINANCE', 'SUPPORT', 'VIEWER']) {
        final r = rights(myRole: 'ADMIN', held: ownerPerms, target: member(role: role));
        expect(r.editProfile && r.changeRole && r.setStatus && r.resetPassword, isTrue, reason: role);
      }
      for (final role in ['ADMIN', 'OWNER']) {
        final r = rights(myRole: 'ADMIN', held: ownerPerms, target: member(role: role, locked: true, sessions: 3));
        expect(r.editProfile, isFalse, reason: role);
        expect(r.changeRole, isFalse, reason: role);
        expect(r.setStatus, isFalse, reason: role);
        expect(r.resetPassword, isFalse, reason: role);
        expect(r.unlock, isFalse, reason: '$role outranks or equals an admin');
        expect(r.signOutEverywhere, isFalse, reason: role);
        expect(r.any, isFalse, reason: role);
      }
    });

    test('nobody changes their own role, status or password through the team page', () {
      final self = member(id: 'me', role: 'OWNER', sessions: 1);
      final r = rights(myRole: 'OWNER', held: ownerPerms, target: self);
      expect(r.editProfile, isTrue, reason: 'owners may edit their own name and phone');
      expect(r.changeRole, isFalse);
      expect(r.setStatus, isFalse);
      expect(r.resetPassword, isFalse);
      expect(r.signOutEverywhere, isFalse, reason: 'only this session exists');
      expect(rights(myRole: 'OWNER', held: ownerPerms, target: member(id: 'me', role: 'OWNER', sessions: 3)).signOutEverywhere, isTrue);
    });

    test('an admin cannot edit their own profile (the server forbids managing an admin)', () {
      final r = rights(myRole: 'ADMIN', held: ownerPerms, target: member(id: 'me', role: 'ADMIN'));
      expect(r.editProfile, isFalse);
    });

    test('security staff can unlock and sign out lower ranks but never manage', () {
      const held = [Perm.teamView, Perm.securityView, Perm.securityManage, Perm.auditView];
      final r = rights(myRole: 'SECURITY', held: held, target: member(role: 'SUPPORT', locked: true, sessions: 1));
      expect(r.unlock, isTrue);
      expect(r.signOutEverywhere, isTrue);
      expect(r.editProfile || r.changeRole || r.setStatus || r.resetPassword, isFalse);
      final peer = rights(myRole: 'SECURITY', held: held, target: member(role: 'SECURITY', locked: true, sessions: 1));
      expect(peer.unlock || peer.signOutEverywhere, isFalse);
    });

    test('unlock only appears for a locked account; sign-out only when there is a session', () {
      final r = rights(myRole: 'OWNER', held: ownerPerms, target: member(role: 'SUPPORT'));
      expect(r.unlock, isFalse);
      expect(r.signOutEverywhere, isFalse);
    });

    test('a read-only role gets no actions', () {
      final r = rights(myRole: 'VIEWER', held: const [Perm.teamView], target: member(role: 'VIEWER', locked: true, sessions: 2));
      expect(r.any, isFalse);
    });

    test('permissions are required even when the rank would allow it', () {
      final r = rights(myRole: 'OWNER', held: const [Perm.teamView], target: member(role: 'SUPPORT', locked: true, sessions: 2));
      expect(r.any, isFalse);
    });
  });

  group('form validation', () {
    test('name', () {
      expect(validateStaffName(''), isNotNull);
      expect(validateStaffName('   '), isNotNull);
      expect(validateStaffName(null), isNotNull);
      expect(validateStaffName('Amina Wanjiru'), isNull);
      expect(validateStaffName('x' * 81), isNotNull);
      expect(validateStaffName('x' * 80), isNull);
    });

    test('email', () {
      expect(validateStaffEmail(''), isNotNull);
      expect(validateStaffEmail('amina'), isNotNull);
      expect(validateStaffEmail('amina@'), isNotNull);
      expect(validateStaffEmail('amina@arche'), isNotNull);
      expect(validateStaffEmail('a mina@archeaxon.com'), isNotNull);
      expect(validateStaffEmail(' amina@archeaxon.com '), isNull);
      expect(validateStaffEmail('${'a' * 160}@x.io'), isNotNull);
    });

    test('phone is optional but bounded', () {
      expect(validateStaffPhone(''), isNull);
      expect(validateStaffPhone(null), isNull);
      expect(validateStaffPhone('+254 700 000 000'), isNull);
      expect(validateStaffPhone('7' * 31), isNotNull);
    });
  });
}
