import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../data/models/permission_catalog.dart';
import '../../../settings/presentation/desktop/settings_desktop_widgets.dart'
    show desktopOutlinedStyle;
import 'permission_matrix.dart';
import 'team_desktop_widgets.dart';

/// One role on the Roles table, read from the `/roles` response.
class DesktopRoleRow {
  const DesktopRoleRow({
    required this.id,
    required this.name,
    required this.permissionCount,
    required this.userCount,
    required this.isSystem,
    this.description = '',
  });

  factory DesktopRoleRow.fromJson(Map<String, dynamic> json) => DesktopRoleRow(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Unnamed role',
        permissionCount:
            (json['permissionKeys'] as List<dynamic>? ?? []).length,
        userCount: (json['userCount'] as num?)?.toInt() ?? 0,
        isSystem: json['isSystem'] as bool? ?? false,
        description: json['description']?.toString() ?? '',
      );

  final String id;
  final String name;
  final int permissionCount;
  final int userCount;
  final bool isSystem;
  final String description;
}

/// The Roles tab: every role with how many permissions it grants and how many
/// people use it. A click opens the role's permission matrix.
class DesktopRolesPage extends StatelessWidget {
  const DesktopRolesPage({
    super.key,
    required this.roles,
    required this.onTab,
    required this.onRefresh,
    this.loading = false,
    this.error,
    this.canInvite = false,
    this.canCreate = false,
    this.canEdit = false,
    this.onNewRole,
    this.onOpenRole,
  });

  final List<DesktopRoleRow> roles;
  final bool loading;
  final String? error;
  final bool canInvite;
  final bool canCreate;
  final bool canEdit;
  final ValueChanged<DesktopTeamTab> onTab;
  final VoidCallback onRefresh;
  final VoidCallback? onNewRole;
  final ValueChanged<DesktopRoleRow>? onOpenRole;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopTeamHeader(
          current: DesktopTeamTab.roles,
          onTab: onTab,
          showInvitations: canInvite,
          subtitle: loading
              ? null
              : 'A role decides what a person can see and do. Open one to '
                  'change its permissions.',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
            if (canCreate && onNewRole != null)
              FilledButton.icon(
                key: const ValueKey('team-new-role'),
                onPressed: onNewRole,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New role'),
              ),
          ],
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: error != null && roles.isEmpty
              ? DesktopEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load roles',
                  message: error,
                  action: OutlinedButton(
                    style: desktopOutlinedStyle(context),
                    onPressed: onRefresh,
                    child: const Text('Try again'),
                  ),
                )
              : DesktopDataTable<DesktopRoleRow>(
                  key: const ValueKey('team-roles-table'),
                  loading: loading,
                  rows: roles,
                  rowId: (r) => r.id,
                  onRowSelected: canEdit ? onOpenRole : null,
                  initialSortColumn: 0,
                  minWidth: 560,
                  columns: [
                    DesktopColumn<DesktopRoleRow>(
                      label: 'Role',
                      flex: 3,
                      minWidth: 200,
                      sortBy: (r) => r.name.toLowerCase(),
                      cell: (context, r) => Row(
                        children: [
                          Flexible(
                            child: DesktopCellText(r.name, strong: true),
                          ),
                          if (r.isSystem) ...[
                            const SizedBox(width: 8),
                            const DesktopStatusChip(
                              label: 'Built in',
                              color: DesignColors.info,
                            ),
                          ],
                        ],
                      ),
                    ),
                    DesktopColumn<DesktopRoleRow>(
                      label: 'Permissions',
                      width: 130,
                      numeric: true,
                      sortBy: (r) => r.permissionCount,
                      cell: (context, r) => DesktopCellText(
                        '${r.permissionCount}',
                        numeric: true,
                      ),
                    ),
                    DesktopColumn<DesktopRoleRow>(
                      label: 'People',
                      width: 110,
                      numeric: true,
                      sortBy: (r) => r.userCount,
                      cell: (context, r) => DesktopCellText(
                        '${r.userCount}',
                        numeric: true,
                      ),
                    ),
                  ],
                  empty: DesktopEmptyState(
                    icon: Icons.badge_outlined,
                    title: 'No roles yet',
                    message: 'Roles such as Cashier or Manager decide what '
                        'each person can do.',
                    action: canCreate && onNewRole != null
                        ? FilledButton.icon(
                            onPressed: onNewRole,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('New role'),
                          )
                        : null,
                  ),
                ),
        ),
      ],
    );
  }
}

/// One role's editor on a computer: name and description, then the permission
/// matrix filling the page. Ctrl+S saves. All the state stays in the screen
/// that owns it; this only draws it.
class DesktopRoleEditorView extends StatelessWidget {
  const DesktopRoleEditorView({
    super.key,
    required this.isNew,
    required this.isSystem,
    required this.nameController,
    required this.descriptionController,
    required this.groups,
    required this.selectedKeys,
    required this.onChanged,
    required this.onSave,
    required this.onBack,
    this.onDelete,
    this.saving = false,
    this.title,
  });

  final bool isNew;
  final bool isSystem;
  final String? title;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final List<PermissionFeatureGroup> groups;
  final Set<String> selectedKeys;
  final void Function(Iterable<String> keys, bool value) onChanged;
  final VoidCallback onSave;
  final VoidCallback onBack;
  final VoidCallback? onDelete;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (!saving) onSave();
        },
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: title ?? (isNew ? 'New role' : 'Edit role'),
              subtitle: 'Team  ›  Roles  ›  '
                  '${nameController.text.trim().isEmpty ? 'New role' : nameController.text.trim()}',
              leading: IconButton(
                tooltip: 'Back to roles',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
              ),
              actions: [
                if (onDelete != null)
                  OutlinedButton(
                    style: desktopOutlinedStyle(context, destructive: true),
                    key: const ValueKey('role-delete'),
                    onPressed: onDelete,
                    child: const Text('Delete role'),
                  ),
                Tooltip(
                  message: 'Save (Ctrl+S)',
                  child: FilledButton(
                    key: const ValueKey('role-save'),
                    onPressed: saving ? null : onSave,
                    child: Text(saving ? 'Saving…' : 'Save role'),
                  ),
                ),
              ],
            ),
            Divider(height: 1, color: p.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesktopTokens.gutter,
                16,
                DesktopTokens.gutter,
                12,
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      key: const ValueKey('role-name'),
                      controller: nameController,
                      enabled: !isSystem,
                      decoration: const InputDecoration(labelText: 'Role name'),
                    ),
                  ),
                  SizedBox(
                    width: 420,
                    child: TextField(
                      key: const ValueKey('role-description'),
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                      ),
                    ),
                  ),
                  if (isSystem)
                    const DesktopStatusChip(
                      label: 'Built-in role: the name is locked',
                      color: DesignColors.info,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesktopTokens.gutter,
                0,
                DesktopTokens.gutter,
                8,
              ),
              child: Text(
                '${selectedKeys.length} permissions on, across ${groups.length} areas. '
                'Use the boxes in the header or the first column to switch a '
                'whole column or area at once.',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesktopTokens.gutter,
                  0,
                  DesktopTokens.gutter,
                  DesktopTokens.gutter,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: p.dark ? p.panelAlt : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: DesktopPermissionMatrix(
                    groups: groups,
                    selectedKeys: selectedKeys,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
