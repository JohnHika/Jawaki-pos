import 'package:flutter_test/flutter_test.dart';

import 'package:aca/core/permissions.dart';
import 'package:aca/features/team/permission_labels.dart';

const _allKeys = [
  Perm.dashboardView,
  Perm.tenantsView,
  Perm.tenantsManage,
  Perm.tenantsSuspend,
  Perm.tenantsLicense,
  Perm.tenantsUsers,
  Perm.tenantsSecurity,
  Perm.billingView,
  Perm.billingManage,
  Perm.teamView,
  Perm.teamManage,
  Perm.securityView,
  Perm.securityManage,
  Perm.auditView,
];

void main() {
  test('every platform permission has a plain-language label', () {
    for (final k in _allKeys) {
      final label = permissionLabel(k);
      expect(label, isNotEmpty, reason: k);
      expect(label.contains('.'), isFalse, reason: '$k fell back to the raw key');
    }
    expect(permissionLabel('team.manage'), 'Add, edit, disable and reset staff');
    expect(permissionLabel('dashboard.view'), 'See the overview dashboard');
  });

  test('labels are unique so a checklist never shows two identical lines', () {
    final labels = _allKeys.map(permissionLabel).toList();
    expect(labels.toSet().length, labels.length);
  });

  test('unknown keys fall back to a readable phrase', () {
    expect(permissionLabel('reports.export'), 'Reports export');
  });

  test('groups cover every permission exactly once', () {
    final grouped = [for (final g in permissionGroups) ...g.keys];
    expect(grouped.toSet(), _allKeys.toSet());
    expect(grouped.length, _allKeys.length);
    expect(permissionGroups.map((g) => g.title), ['Companies', 'Billing', 'Team', 'Security & audit']);
  });

  test('permissionSections flags granted and missing permissions', () {
    final sections = permissionSections(const [Perm.dashboardView, Perm.tenantsView, Perm.billingView]);
    expect(sections.map((s) => s.title), ['Companies', 'Billing', 'Team', 'Security & audit']);
    final companies = sections.first;
    expect(companies.lines.where((l) => l.granted).map((l) => l.key), [Perm.dashboardView, Perm.tenantsView]);
    expect(companies.grantedCount, 2);
    expect(companies.lines.length, 7);
    expect(sections[1].grantedCount, 1);
    expect(sections[2].grantedCount, 0);
    expect(sections[3].grantedCount, 0);
  });

  test('a role with every permission shows everything granted', () {
    final sections = permissionSections(_allKeys);
    expect(sections.every((s) => s.grantedCount == s.lines.length), isTrue);
    expect(sections.length, 4);
  });

  test('granted permissions this app does not know are listed under Other', () {
    final sections = permissionSections(const [Perm.teamView, 'reports.export']);
    expect(sections.last.title, 'Other');
    expect(sections.last.lines.single.key, 'reports.export');
    expect(sections.last.lines.single.granted, isTrue);
  });

  test('an empty grant list is all unchecked', () {
    final sections = permissionSections(const []);
    expect(sections.every((s) => s.grantedCount == 0), isTrue);
  });
}
