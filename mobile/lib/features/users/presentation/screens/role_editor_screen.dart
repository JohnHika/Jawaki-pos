import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/permission_catalog.dart';
import '../providers/user_management_provider.dart';

/// Lists roles for the tenant; tapping one opens the editor. Also the
/// entry point for creating a new role.
class RoleListScreen extends ConsumerWidget {
  const RoleListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionsProvider);
    if (!permissions.canManageRoles) {
      return const Scaffold(
        appBar: BrandedAppBar(title: 'Roles', showBackButton: true),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Restricted',
          subtitle: 'You do not have permission to manage roles.',
        ),
      );
    }

    final rolesAsync = ref.watch(tenantRolesProvider);

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Roles',
        showBackButton: true,
        actions: [
          IconButton(
            tooltip: 'New role',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/users/roles/new'),
          ),
        ],
      ),
      body: rolesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load roles',
          subtitle: err.toString(),
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(tenantRolesProvider),
        ),
        data: (roles) => PageContainer(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: roles.length,
            itemBuilder: (context, index) {
              final role = roles[index];
              final isSystem = role['isSystem'] as bool? ?? false;
              final keyCount = (role['permissionKeys'] as List<dynamic>? ?? []).length;
              final userCount = role['userCount'] as int? ?? 0;

              return GroupedCard(
                margin: const EdgeInsets.only(bottom: 10),
                children: [
                  SettingsRow(
                    icon: isSystem ? Icons.verified_user_rounded : Icons.badge_outlined,
                    title: role['name'] as String,
                    subtitle:
                        '$keyCount permission${keyCount == 1 ? '' : 's'} · $userCount user${userCount == 1 ? '' : 's'}${isSystem ? ' · System' : ''}',
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () => context.push('/users/roles/${role['id']}'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Edits one role: name/description plus a checklist of every permission
/// key grouped by feature. Saving does a full-set PATCH — the checked
/// state at save time becomes the role's entire permission set.
class RoleEditorScreen extends ConsumerStatefulWidget {
  final String? roleId; // null = creating a new role

  const RoleEditorScreen({super.key, this.roleId});

  @override
  ConsumerState<RoleEditorScreen> createState() => _RoleEditorScreenState();
}

class _RoleEditorScreenState extends ConsumerState<RoleEditorScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final Set<String> _selectedKeys = {};
  bool _isSystem = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  bool get _isNew => widget.roleId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isNew) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final role = await getIt<ApiClient>().getRole(widget.roleId!);
      _nameController.text = role['name'] as String? ?? '';
      _descriptionController.text = role['description'] as String? ?? '';
      _isSystem = role['isSystem'] as bool? ?? false;
      _selectedKeys
        ..clear()
        ..addAll((role['permissionKeys'] as List<dynamic>? ?? []).cast<String>());
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final api = getIt<ApiClient>();
      if (_isNew) {
        await api.createRole(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          permissionKeys: _selectedKeys.toList(),
        );
      } else {
        await api.updateRole(
          widget.roleId!,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          permissionKeys: _selectedKeys.toList(),
        );
      }
      ref.invalidate(tenantRolesProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    if (_isNew) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete role?'),
        content: Text('Delete "${_nameController.text}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: DesignColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await getIt<ApiClient>().deleteRole(widget.roleId!);
      ref.invalidate(tenantRolesProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(permissionCatalogProvider);

    return Scaffold(
      appBar: BrandedAppBar(
        title: _isNew ? 'New Role' : 'Edit Role',
        showBackButton: true,
        actions: [
          if (!_isNew && !_isSystem)
            IconButton(
              tooltip: 'Delete role',
              icon: const Icon(Icons.delete_outline_rounded, color: DesignColors.error),
              onPressed: _delete,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load role',
                  subtitle: _error,
                )
              : catalogAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load permission catalog',
                    subtitle: err.toString(),
                  ),
                  data: (groups) => _buildForm(groups),
                ),
      bottomNavigationBar: _isLoading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SettingsPrimaryButton(
                  label: _isSaving ? 'Saving...' : 'Save Role',
                  onPressed: _isSaving ? null : _save,
                ),
              ),
            ),
    );
  }

  Widget _buildForm(List<PermissionFeatureGroup> groups) {
    return PageContainer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (_isSystem)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: StatusBadge(
                label: 'System role — name is locked, permissions are editable',
                color: DesignColors.info,
              ),
            ),
          GroupedCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _nameController,
                  enabled: !_isSystem,
                  decoration: const InputDecoration(
                    labelText: 'Role name',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          GroupedCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _descriptionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SectionHeader(
            title: 'Permissions',
            subtitle: '${_selectedKeys.length} selected across ${groups.length} categories',
            icon: Icons.checklist_rounded,
          ),
          for (final group in groups) _FeatureAccordion(
            group: group,
            selectedKeys: _selectedKeys,
            onChanged: (key, checked) {
              setState(() {
                if (checked) {
                  _selectedKeys.add(key);
                } else {
                  _selectedKeys.remove(key);
                }
              });
            },
          ),
        ],
      ),
    );
  }
}

class _FeatureAccordion extends StatelessWidget {
  final PermissionFeatureGroup group;
  final Set<String> selectedKeys;
  final void Function(String key, bool checked) onChanged;

  const _FeatureAccordion({
    required this.group,
    required this.selectedKeys,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedInGroup = group.permissions.where((p) => selectedKeys.contains(p.key)).length;

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
        subtitle: Text('$selectedInGroup / ${group.permissions.length} selected'),
        children: [
          for (final perm in group.permissions)
            CheckboxListTile(
              value: selectedKeys.contains(perm.key),
              onChanged: (v) => onChanged(perm.key, v ?? false),
              title: Text(perm.label, style: const TextStyle(fontSize: 14)),
              subtitle: Text(perm.key, style: const TextStyle(fontSize: 11)),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ),
    );
  }
}
