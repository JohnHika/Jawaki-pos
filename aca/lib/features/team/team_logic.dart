import 'package:flutter/foundation.dart' show immutable;

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../account/account_logic.dart' show plural;

/// Pure rules for the Team screens: grouping, status pills, who may manage whom.
/// The server enforces all of it (`platform-team.service.ts`); the app only hides
/// what the signed-in person cannot do. Covered by `test/team_logic_test.dart`.

// ------------------------------------------------------------ status pills

enum StaffFlagKind { disabled, locked, invitePending, twoFactorOn, noTwoFactor }

@immutable
class StaffFlag {
  const StaffFlag(this.kind, this.label, this.tone);
  final StaffFlagKind kind;
  final String label;
  final Tone tone;

  @override
  bool operator ==(Object other) =>
      other is StaffFlag && other.kind == kind && other.label == label && other.tone == tone;

  @override
  int get hashCode => Object.hash(kind, label, tone);
}

/// Compact status pills for a staff row, most important first. A disabled
/// account never gets the "No 2FA" warning: nobody can sign in with it anyway.
List<StaffFlag> staffFlags(StaffMember m) {
  final disabled = !m.isActive;
  return [
    if (disabled) const StaffFlag(StaffFlagKind.disabled, 'Disabled', Tone.neutral),
    if (m.locked) const StaffFlag(StaffFlagKind.locked, 'Locked', Tone.danger),
    if (m.mustChangePassword) const StaffFlag(StaffFlagKind.invitePending, 'Invite pending', Tone.info),
    if (m.twoFactorEnabled)
      const StaffFlag(StaffFlagKind.twoFactorOn, '2FA on', Tone.success)
    else if (!disabled)
      const StaffFlag(StaffFlagKind.noTwoFactor, 'No 2FA', Tone.warning),
  ];
}

// ---------------------------------------------------------------- grouping

/// Position of a role on the ladder (OWNER first). Unknown roles sort last.
int roleOrder(String role) {
  final i = Roles.all.indexOf(role);
  return i < 0 ? Roles.all.length : i;
}

@immutable
class StaffGroups {
  const StaffGroups({required this.active, required this.disabled});
  final List<StaffMember> active;
  final List<StaffMember> disabled;
}

/// Active staff first, then disabled; inside each group by role (Owner first),
/// then by name.
StaffGroups groupStaff(List<StaffMember> all) {
  int byRoleThenName(StaffMember a, StaffMember b) {
    final r = roleOrder(a.role).compareTo(roleOrder(b.role));
    if (r != 0) return r;
    final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return n != 0 ? n : a.email.toLowerCase().compareTo(b.email.toLowerCase());
  }

  return StaffGroups(
    active: all.where((m) => m.isActive).toList()..sort(byRoleThenName),
    disabled: all.where((m) => !m.isActive).toList()..sort(byRoleThenName),
  );
}

// -------------------------------------------------------------- row texts

/// "Signed in 2 h ago" / "Never signed in".
String lastSignInText(DateTime? at, {DateTime? now}) =>
    at == null ? 'Never signed in' : 'Signed in ${Fmt.ago(at, now: now)}';

/// "3 active sessions" / "No active sessions".
String sessionsText(int n) => n <= 0 ? 'No active sessions' : plural(n, 'active session');

/// "Locked until 14:30" (same day) or "Locked until 22 Oct 2026, 14:30".
String lockedUntilText(DateTime? until, {DateTime? now}) {
  if (until == null) return 'Locked';
  final u = until.toLocal();
  final n = now ?? DateTime.now();
  final sameDay = u.year == n.year && u.month == n.month && u.day == n.day;
  return sameDay ? 'Locked until ${Fmt.time(u)}' : 'Locked until ${Fmt.dateTime(u)}';
}

/// Row on the Security card: when the password last changed, or that it is still temporary.
String passwordChangedText(StaffMember m) {
  if (m.mustChangePassword) return 'Not yet. Still on a temporary password';
  return m.passwordChangedAt == null ? '—' : Fmt.dateTime(m.passwordChangedAt);
}

// ------------------------------------------------------------------ roles

/// Roles the signed-in person may hand out, most powerful first.
List<RoleInfo> assignableRoles(List<RoleInfo> roles) =>
    roles.where((r) => r.assignable).toList()..sort((a, b) => b.rank.compareTo(a.rank));

/// The safest preset for a new account: the lowest-ranked role you may assign.
RoleInfo? defaultNewStaffRole(List<RoleInfo> assignable) {
  if (assignable.isEmpty) return null;
  return ([...assignable]..sort((a, b) => a.rank.compareTo(b.rank))).first;
}

int rankOf(List<RoleInfo> roles, String role) {
  for (final r in roles) {
    if (r.role == role) return r.rank;
  }
  return 0;
}

/// Whether the "Add staff" button should exist at all.
bool canAddStaff({required bool Function(String permission) can, required List<RoleInfo> roles}) =>
    can(Perm.teamManage) && roles.any((r) => r.assignable);

/// Mirrors `canSecureTarget` on the server: owners may act on anyone, everyone
/// else only on strictly lower-ranked staff (and on themselves).
bool canSecureStaff({
  required String myId,
  required String myRole,
  required String targetId,
  required String targetRole,
  required List<RoleInfo> roles,
}) {
  if (targetId == myId) return true;
  if (myRole == 'OWNER') return true;
  return rankOf(roles, myRole) > rankOf(roles, targetRole);
}

/// What the signed-in person may do to one staff member. Mirrors the server:
///  * managing (edit, role, disable, reset) needs `team.manage` AND the target's
///    role among the roles you may assign; role/status/reset never on yourself;
///  * unlock and sign-out need `security.manage` AND [canSecureStaff].
@immutable
class StaffRights {
  const StaffRights({
    required this.editProfile,
    required this.changeRole,
    required this.setStatus,
    required this.resetPassword,
    required this.unlock,
    required this.signOutEverywhere,
  });

  final bool editProfile;
  final bool changeRole;
  final bool setStatus;
  final bool resetPassword;
  final bool unlock;
  final bool signOutEverywhere;

  bool get any => editProfile || changeRole || setStatus || resetPassword || unlock || signOutEverywhere;
}

StaffRights staffRights({
  required bool Function(String permission) can,
  required String myId,
  required String myRole,
  required StaffMember target,
  required List<RoleInfo> roles,
}) {
  final isSelf = target.id == myId;
  final roleAssignable = roles.any((r) => r.role == target.role && r.assignable);
  final canManage = can(Perm.teamManage) && roleAssignable;
  final manageOther = canManage && !isSelf;
  final secure = can(Perm.securityManage) &&
      canSecureStaff(myId: myId, myRole: myRole, targetId: target.id, targetRole: target.role, roles: roles);
  // For yourself the server keeps this session; nothing to do when there are no others.
  final otherSessions = isSelf ? target.activeSessions - 1 : target.activeSessions;
  return StaffRights(
    editProfile: canManage,
    changeRole: manageOther && roles.any((r) => r.assignable && r.role != target.role),
    setStatus: manageOther,
    resetPassword: manageOther,
    unlock: secure && target.locked,
    signOutEverywhere: secure && otherSessions > 0,
  );
}

// ------------------------------------------------------------ form checks

final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

String? validateStaffName(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 'Enter their full name';
  if (s.length > 80) return 'Keep the name under 80 characters';
  return null;
}

String? validateStaffEmail(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 'Enter their work email';
  if (s.length > 160) return 'That email is too long';
  if (!_email.hasMatch(s)) return 'Enter a valid email address';
  return null;
}

/// Optional.
String? validateStaffPhone(String? v) {
  final s = (v ?? '').trim();
  if (s.length > 30) return 'Keep the phone number under 30 characters';
  return null;
}
