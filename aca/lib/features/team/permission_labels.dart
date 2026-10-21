import 'package:flutter/foundation.dart' show immutable;

import '../../core/format.dart';
import '../../core/permissions.dart';

/// Plain-language names for the platform permission keys
/// (`backend/src/platform-admin/rbac/platform-permissions.ts`), grouped the way
/// the Roles screen presents them. Pure data + functions: see `test/team_permissions_test.dart`.

@immutable
class PermissionGroup {
  const PermissionGroup(this.title, this.keys);
  final String title;
  final List<String> keys;
}

const List<PermissionGroup> permissionGroups = [
  PermissionGroup('Companies', [
    Perm.dashboardView,
    Perm.tenantsView,
    Perm.tenantsManage,
    Perm.tenantsSuspend,
    Perm.tenantsLicense,
    Perm.tenantsUsers,
    Perm.tenantsSecurity,
  ]),
  PermissionGroup('Billing', [Perm.billingView, Perm.billingManage]),
  PermissionGroup('Team', [Perm.teamView, Perm.teamManage]),
  PermissionGroup('Security & audit', [Perm.securityView, Perm.securityManage, Perm.auditView]),
];

const Map<String, String> _labels = {
  Perm.dashboardView: 'See the overview dashboard',
  Perm.tenantsView: 'View companies',
  Perm.tenantsManage: 'Extend subscriptions and add notes',
  Perm.tenantsSuspend: 'Suspend and reactivate companies',
  Perm.tenantsLicense: 'Edit licences, modules and seat limits',
  Perm.tenantsUsers: 'See a company\'s staff accounts and devices',
  Perm.tenantsSecurity: 'Lock company accounts, sign users out, lock a company out',
  Perm.billingView: 'View invoices and payments',
  Perm.billingManage: 'Mark invoices paid and issue credits',
  Perm.teamView: 'See the Counterbase team and roles',
  Perm.teamManage: 'Add, edit, disable and reset staff',
  Perm.securityView: 'See the security centre and staff devices',
  Perm.securityManage: 'Unlock accounts and sign staff out of devices',
  Perm.auditView: 'Read the audit log',
};

/// "team.manage" -> "Add, edit, disable and reset staff". Unknown keys (a newer
/// server) fall back to a readable version of the key rather than disappearing.
String permissionLabel(String key) {
  final known = _labels[key];
  if (known != null) return known;
  return Fmt.label(key.replaceAll('.', ' '));
}

@immutable
class PermissionLine {
  const PermissionLine({required this.key, required this.label, required this.granted});
  final String key;
  final String label;
  final bool granted;
}

@immutable
class PermissionSection {
  const PermissionSection(this.title, this.lines);
  final String title;
  final List<PermissionLine> lines;

  int get grantedCount => lines.where((l) => l.granted).length;
}

/// Every known permission, grouped, each flagged granted or not for [granted].
/// Granted keys this app does not know about are listed under "Other" so nothing
/// a role can do is ever hidden.
List<PermissionSection> permissionSections(Iterable<String> granted) {
  final have = granted.toSet();
  final known = <String>{for (final g in permissionGroups) ...g.keys};
  final sections = <PermissionSection>[
    for (final g in permissionGroups)
      PermissionSection(g.title, [
        for (final k in g.keys) PermissionLine(key: k, label: permissionLabel(k), granted: have.contains(k)),
      ]),
  ];
  final extras = have.difference(known).toList()..sort();
  if (extras.isNotEmpty) {
    sections.add(PermissionSection('Other', [
      for (final k in extras) PermissionLine(key: k, label: permissionLabel(k), granted: true),
    ]));
  }
  return sections;
}
