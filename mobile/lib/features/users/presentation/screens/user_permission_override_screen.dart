import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../data/models/permission_catalog.dart';
import '../providers/user_management_provider.dart';

enum _PermState { inherited, granted, revoked }

/// Manages one user's role assignments and per-permission overrides.
/// Three-state checklist per permission: inherited (greyed, from a role),
/// granted (green, explicit personal extra), revoked (red, explicit
/// personal denial that wins over any role grant).
class UserPermissionOverrideScreen extends ConsumerStatefulWidget {
  final String userId;
  const UserPermissionOverrideScreen({super.key, required this.userId});

  @override
  ConsumerState<UserPermissionOverrideScreen> createState() =>
      _UserPermissionOverrideScreenState();
}

class _UserPermissionOverrideScreenState
    extends ConsumerState<UserPermissionOverrideScreen> {
  bool _busy = false;

  Future<void> _toggleRole(String roleId, bool hasRole) async {
    setState(() => _busy = true);
    try {
      final api = getIt<ApiClient>();
      if (hasRole) {
        await api.removeUserRole(widget.userId, roleId);
      } else {
        await api.assignUserRole(widget.userId, roleId);
      }
      ref.invalidate(userPermissionBreakdownProvider(widget.userId));
      ref.invalidate(managedUsersProvider);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setOverride(String key, _PermState target) async {
    setState(() => _busy = true);
    try {
      final api = getIt<ApiClient>();
      if (target == _PermState.inherited) {
        await api.clearUserPermissionOverride(widget.userId, key);
      } else {
        await api.setUserPermissionOverride(
          widget.userId,
          permissionKey: key,
          grant: target == _PermState.granted,
        );
      }
      ref.invalidate(userPermissionBreakdownProvider(widget.userId));
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }

  @override
  Widget build(BuildContext context) {
    final breakdownAsync = ref.watch(userPermissionBreakdownProvider(widget.userId));
    final rolesAsync = ref.watch(tenantRolesProvider);
    final catalogAsync = ref.watch(permissionCatalogProvider);

    return Scaffold(
      appBar: const BrandedAppBar(title: 'User Permissions', showBackButton: true),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? 0.6 : 1,
          child: breakdownAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Could not load user permissions',
              subtitle: err.toString(),
            ),
            data: (breakdown) => rolesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load roles',
                subtitle: err.toString(),
              ),
              data: (allRoles) => catalogAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load permission catalog',
                  subtitle: err.toString(),
                ),
                data: (groups) => _buildBody(breakdown, allRoles, groups),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    Map<String, dynamic> breakdown,
    List<Map<String, dynamic>> allRoles,
    List<PermissionFeatureGroup> groups,
  ) {
    final assignedRoles = (breakdown['roles'] as List<dynamic>? ?? [])
        .map((r) => (r as Map<String, dynamic>)['id'] as String)
        .toSet();
    final fromRoles = (breakdown['fromRoles'] as List<dynamic>? ?? []).cast<String>().toSet();
    final granted = (breakdown['granted'] as List<dynamic>? ?? []).cast<String>().toSet();
    final revoked = (breakdown['revoked'] as List<dynamic>? ?? []).cast<String>().toSet();

    _PermState stateOf(String key) {
      if (revoked.contains(key)) return _PermState.revoked;
      if (granted.contains(key)) return _PermState.granted;
      return _PermState.inherited;
    }

    return PageContainer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const SectionHeader(
            title: 'Assigned Roles',
            subtitle: 'A user can hold multiple roles at once',
            icon: Icons.badge_outlined,
          ),
          GroupedCard(
            children: [
              for (final role in allRoles)
                SettingsRow(
                  icon: Icons.verified_user_rounded,
                  title: role['name'] as String,
                  trailing: Switch(
                    value: assignedRoles.contains(role['id']),
                    onChanged: (_) =>
                        _toggleRole(role['id'] as String, assignedRoles.contains(role['id'])),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const SectionHeader(
            title: 'Permission Overrides',
            subtitle: 'Grant an extra permission, or revoke one this user would otherwise get from their roles',
            icon: Icons.tune_rounded,
          ),
          for (final group in groups)
            _OverrideFeatureAccordion(
              group: group,
              fromRoles: fromRoles,
              stateOf: stateOf,
              onSetState: _setOverride,
            ),
        ],
      ),
    );
  }
}

class _OverrideFeatureAccordion extends StatelessWidget {
  final PermissionFeatureGroup group;
  final Set<String> fromRoles;
  final _PermState Function(String key) stateOf;
  final void Function(String key, _PermState target) onSetState;

  const _OverrideFeatureAccordion({
    required this.group,
    required this.fromRoles,
    required this.stateOf,
    required this.onSetState,
  });

  @override
  Widget build(BuildContext context) {
    final overriddenCount =
        group.permissions.where((p) => stateOf(p.key) != _PermState.inherited).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? DesignColors.darkBorder
              : DesignColors.surfaceBorder,
        ),
      ),
      child: ExpansionTile(
        title: Text(group.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          overriddenCount == 0 ? 'No overrides' : '$overriddenCount override${overriddenCount == 1 ? '' : 's'}',
        ),
        children: [
          for (final perm in group.permissions)
            _OverrideRow(
              permKey: perm.key,
              label: perm.label,
              hasFromRole: fromRoles.contains(perm.key),
              state: stateOf(perm.key),
              onSetState: (target) => onSetState(perm.key, target),
            ),
        ],
      ),
    );
  }
}

class _OverrideRow extends StatelessWidget {
  final String permKey;
  final String label;
  final bool hasFromRole;
  final _PermState state;
  final void Function(_PermState target) onSetState;

  const _OverrideRow({
    required this.permKey,
    required this.label,
    required this.hasFromRole,
    required this.state,
    required this.onSetState,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _PermState.granted => DesignColors.success,
      _PermState.revoked => DesignColors.error,
      _PermState.inherited => hasFromRole ? DesignColors.info : DesignColors.textTertiary,
    };
    final label2 = switch (state) {
      _PermState.granted => 'Granted',
      _PermState.revoked => 'Revoked',
      _PermState.inherited => hasFromRole ? 'From role' : 'None',
    };

    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(permKey, style: const TextStyle(fontSize: 11)),
      trailing: PopupMenuButton<_PermState>(
        initialValue: state,
        onSelected: onSetState,
        itemBuilder: (context) => const [
          PopupMenuItem(value: _PermState.inherited, child: Text('Inherit from role')),
          PopupMenuItem(value: _PermState.granted, child: Text('Grant (extra)')),
          PopupMenuItem(value: _PermState.revoked, child: Text('Revoke')),
        ],
        child: StatusBadge(label: label2, color: color),
      ),
    );
  }
}
