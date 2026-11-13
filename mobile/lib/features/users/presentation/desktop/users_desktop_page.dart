import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../settings/presentation/desktop/settings_desktop_widgets.dart'
    show desktopOutlinedStyle;
import 'team_desktop_widgets.dart';

enum _StatusFilter { all, active, inactive }

/// The Users tab on a computer: a table of everyone on the team, a search box
/// and status filters above it, and an inspector on the right for the person
/// picked. Takes plain data; the screen decides where it comes from.
class DesktopUsersPage extends StatefulWidget {
  const DesktopUsersPage({
    super.key,
    required this.users,
    required this.onTab,
    required this.onRefresh,
    this.loading = false,
    this.error,
    this.canInvite = false,
    this.canManageRoles = false,
    this.onInvite,
    this.onEditPermissions,
  });

  final List<DesktopTeamUser> users;
  final bool loading;

  /// A plain sentence about what went wrong; shows the error state.
  final String? error;
  final bool canInvite;
  final bool canManageRoles;
  final ValueChanged<DesktopTeamTab> onTab;
  final VoidCallback onRefresh;
  final VoidCallback? onInvite;
  final ValueChanged<DesktopTeamUser>? onEditPermissions;

  @override
  State<DesktopUsersPage> createState() => _DesktopUsersPageState();
}

class _DesktopUsersPageState extends State<DesktopUsersPage> {
  final _search = TextEditingController();
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;
  String? _selectedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DesktopTeamUser> get _visible {
    final q = _query.trim().toLowerCase();
    return [
      for (final u in widget.users)
        if ((_filter == _StatusFilter.all ||
                (_filter == _StatusFilter.active) == u.isActive) &&
            (q.isEmpty ||
                u.name.toLowerCase().contains(q) ||
                u.email.toLowerCase().contains(q) ||
                u.roleLabel.toLowerCase().contains(q)))
          u,
    ];
  }

  DesktopTeamUser? get _selected {
    for (final u in widget.users) {
      if (u.id == _selectedId) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final active = widget.users.where((u) => u.isActive).length;
    final inactive = widget.users.length - active;
    final rows = _visible;
    final selected = _selected;

    return DesktopInspectorLayout(
      onClose: () => setState(() => _selectedId = null),
      inspector: selected == null
          ? null
          : _UserInspector(
              user: selected,
              onClose: () => setState(() => _selectedId = null),
              onEditPermissions: widget.onEditPermissions == null
                  ? null
                  : () => widget.onEditPermissions!(selected),
            ),
      main: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopTeamHeader(
            current: DesktopTeamTab.users,
            onTab: widget.onTab,
            showRoles: widget.canManageRoles,
            showInvitations: widget.canInvite,
            subtitle: widget.loading
                ? null
                : '${widget.users.length} '
                    '${widget.users.length == 1 ? 'person' : 'people'}'
                    '${inactive > 0 ? ' · $inactive inactive' : ''}',
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
              if (widget.canInvite && widget.onInvite != null)
                FilledButton.icon(
                  key: const ValueKey('team-invite-button'),
                  onPressed: widget.onInvite,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Invite user'),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesktopTokens.gutter,
              4,
              DesktopTokens.gutter,
              10,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DesktopSearchField(
                  key: const ValueKey('team-search'),
                  controller: _search,
                  hint: 'Search name, email or role',
                  width: 300,
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(width: 4),
                DesktopFilterChip(
                  label: 'All',
                  count: widget.users.length,
                  selected: _filter == _StatusFilter.all,
                  onTap: () => setState(() => _filter = _StatusFilter.all),
                ),
                DesktopFilterChip(
                  label: 'Active',
                  count: active,
                  selected: _filter == _StatusFilter.active,
                  onTap: () => setState(() => _filter = _StatusFilter.active),
                ),
                DesktopFilterChip(
                  label: 'Inactive',
                  count: inactive,
                  selected: _filter == _StatusFilter.inactive,
                  onTap: () => setState(() => _filter = _StatusFilter.inactive),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.border),
          Expanded(child: _body(context, rows)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, List<DesktopTeamUser> rows) {
    if (widget.error != null && widget.users.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not load your team',
        message: widget.error,
        action: OutlinedButton(
          style: desktopOutlinedStyle(context),
          onPressed: widget.onRefresh,
          child: const Text('Try again'),
        ),
      );
    }
    return DesktopDataTable<DesktopTeamUser>(
      key: const ValueKey('team-users-table'),
      loading: widget.loading,
      rows: rows,
      rowId: (u) => u.id,
      selectedId: _selectedId,
      onRowSelected: (u) => setState(() => _selectedId = u.id),
      initialSortColumn: 0,
      minWidth: 600,
      columns: [
        DesktopColumn<DesktopTeamUser>(
          label: 'Name',
          flex: 3,
          minWidth: 170,
          sortBy: (u) => u.name.toLowerCase(),
          cell: (context, u) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesktopCellText(u.name, strong: true),
              if (u.email != u.name) DesktopCellText(u.email, muted: true),
            ],
          ),
        ),
        DesktopColumn<DesktopTeamUser>(
          label: 'Role',
          flex: 2,
          minWidth: 100,
          sortBy: (u) => u.roleLabel.toLowerCase(),
          cell: (context, u) => DesktopCellText(u.roleLabel),
        ),
        DesktopColumn<DesktopTeamUser>(
          label: 'Branch',
          flex: 2,
          minWidth: 100,
          sortBy: (u) => u.branches.join(', ').toLowerCase(),
          cell: (context, u) => DesktopCellText(
            u.branches.isEmpty ? 'All branches' : u.branches.join(', '),
            muted: true,
          ),
        ),
        DesktopColumn<DesktopTeamUser>(
          label: 'Last active',
          width: 130,
          sortBy: (u) => u.lastLoginAt?.millisecondsSinceEpoch ?? 0,
          cell: (context, u) =>
              DesktopCellText(lastActiveLabel(u.lastLoginAt), muted: true),
        ),
        DesktopColumn<DesktopTeamUser>(
          label: 'Status',
          width: 100,
          sortBy: (u) => u.isActive ? 0 : 1,
          cell: (context, u) => DesktopStatusChip(
            label: u.isActive ? 'Active' : 'Inactive',
            color: u.isActive ? DesignColors.success : DesignColors.error,
          ),
        ),
      ],
      empty: DesktopEmptyState(
        icon: Icons.people_outline_rounded,
        title: widget.users.isEmpty ? 'No team members yet' : 'No one matches',
        message: widget.users.isEmpty
            ? 'Invite the people who work in your shop. Each person gets '
                'their own sign-in and only sees what their role allows.'
            : 'Try a different name, or switch the filter back to All.',
        action:
            widget.users.isEmpty && widget.canInvite && widget.onInvite != null
                ? FilledButton.icon(
                    onPressed: widget.onInvite,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Invite user'),
                  )
                : null,
      ),
      footer: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Text(
          rows.length == widget.users.length
              ? '${rows.length} ${rows.length == 1 ? 'person' : 'people'}'
              : 'Showing ${rows.length} of ${widget.users.length}',
          style: GoogleFonts.plusJakartaSans(
            color: context.desktop.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _UserInspector extends StatelessWidget {
  const _UserInspector({
    required this.user,
    required this.onClose,
    this.onEditPermissions,
  });

  final DesktopTeamUser user;
  final VoidCallback onClose;
  final VoidCallback? onEditPermissions;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return DesktopInspector(
      title: user.name,
      subtitle: user.email,
      onClose: onClose,
      footer: onEditPermissions == null
          ? null
          : FilledButton(
              key: const ValueKey('team-edit-permissions'),
              onPressed: onEditPermissions,
              child: const Text('Edit roles and permissions'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                DesktopStatusChip(
                  label: user.isActive ? 'Active' : 'Inactive',
                  color:
                      user.isActive ? DesignColors.success : DesignColors.error,
                ),
                for (final role in user.roles)
                  DesktopStatusChip(label: role, color: DesignColors.accent),
              ],
            ),
          ),
          DesktopFact(
            label: 'Last active',
            value: lastActiveLabel(user.lastLoginAt),
          ),
          DesktopFact(
            label: 'Branches',
            value: user.branches.isEmpty
                ? 'All branches'
                : user.branches.join(', '),
          ),
          DesktopFact(
            label: 'Phone',
            value: user.phone.isEmpty ? 'Not given' : user.phone,
          ),
          if (!user.isActive)
            Text(
              'This person can no longer sign in. Their past sales stay on '
              'the records.',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }
}
