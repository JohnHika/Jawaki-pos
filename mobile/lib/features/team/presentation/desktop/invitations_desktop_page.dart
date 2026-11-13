import 'package:flutter/material.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../settings/presentation/desktop/settings_desktop_widgets.dart'
    show desktopOutlinedStyle;
import '../../../users/presentation/desktop/team_desktop_widgets.dart';

/// One invitation on the table, read from the staff-invitations response.
class DesktopInvitationRow {
  const DesktopInvitationRow({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.role,
    required this.branch,
    required this.invitedBy,
    required this.sentAt,
  });

  factory DesktopInvitationRow.fromJson(Map<String, dynamic> json, int index) {
    String nameOf(Object? m) =>
        m is Map ? '${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'.trim() : '';
    final first = json['firstName']?.toString() ?? '';
    final last = json['lastName']?.toString() ?? '';
    final email = json['email']?.toString() ?? '';
    final name = '$first $last'.trim();
    final role = json['role'];
    final branch = json['branch'];
    final by = nameOf(json['createdBy']);
    return DesktopInvitationRow(
      id: json['id']?.toString() ?? 'invitation-$index',
      name: name.isEmpty ? email : name,
      email: email,
      status: json['status']?.toString() ?? 'PENDING',
      role: role is Map ? role['name']?.toString() ?? '—' : '—',
      branch: branch is Map ? branch['name']?.toString() ?? '—' : '—',
      invitedBy: by.isEmpty ? '—' : by,
      sentAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
    );
  }

  final String id;
  final String name;
  final String email;
  final String status;
  final String role;
  final String branch;
  final String invitedBy;
  final DateTime? sentAt;

  String get statusLabel => switch (status) {
        'ACCEPTED' => 'Accepted',
        'EXPIRED' => 'Expired',
        _ => 'Pending',
      };

  Color get statusColor => switch (status) {
        'ACCEPTED' => DesignColors.success,
        'EXPIRED' => DesignColors.error,
        _ => DesignColors.warning,
      };
}

/// The Invitations tab: who was invited, to what role and branch, and whether
/// they have accepted.
class DesktopInvitationsPage extends StatelessWidget {
  const DesktopInvitationsPage({
    super.key,
    required this.invitations,
    required this.onTab,
    required this.onRefresh,
    this.loading = false,
    this.failed = false,
    this.canManageRoles = false,
    this.onInvite,
  });

  final List<DesktopInvitationRow> invitations;
  final bool loading;

  /// The last refresh failed; saved rows (if any) stay visible.
  final bool failed;
  final bool canManageRoles;
  final ValueChanged<DesktopTeamTab> onTab;
  final VoidCallback onRefresh;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final pending = invitations.where((i) => i.status == 'PENDING').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopTeamHeader(
          current: DesktopTeamTab.invitations,
          onTab: onTab,
          showRoles: canManageRoles,
          subtitle: loading
              ? null
              : '${invitations.length} sent · $pending waiting for an answer',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
            if (onInvite != null)
              FilledButton.icon(
                key: const ValueKey('team-invite-button'),
                onPressed: onInvite,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Invite user'),
              ),
          ],
        ),
        if (failed && invitations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesktopTokens.gutter,
              0,
              DesktopTokens.gutter,
              8,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 16,
                  color: DesignColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Could not refresh. Some details may be out of date.',
                    style: TextStyle(color: p.textMuted, fontSize: 12.5),
                  ),
                ),
                TextButton(onPressed: onRefresh, child: const Text('Retry')),
              ],
            ),
          ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: failed && invitations.isEmpty && !loading
              ? DesktopEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load invitations',
                  message: 'Check your internet connection and try again.',
                  action: OutlinedButton(
                    style: desktopOutlinedStyle(context),
                    onPressed: onRefresh,
                    child: const Text('Try again'),
                  ),
                )
              : DesktopDataTable<DesktopInvitationRow>(
                  key: const ValueKey('team-invitations-table'),
                  loading: loading,
                  rows: invitations,
                  rowId: (i) => i.id,
                  minWidth: 720,
                  columns: [
                    DesktopColumn<DesktopInvitationRow>(
                      label: 'Person',
                      flex: 3,
                      minWidth: 200,
                      sortBy: (i) => i.name.toLowerCase(),
                      cell: (context, i) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DesktopCellText(i.name, strong: true),
                          if (i.email != i.name)
                            DesktopCellText(i.email, muted: true),
                        ],
                      ),
                    ),
                    DesktopColumn<DesktopInvitationRow>(
                      label: 'Role',
                      flex: 2,
                      minWidth: 100,
                      sortBy: (i) => i.role.toLowerCase(),
                      cell: (context, i) => DesktopCellText(i.role),
                    ),
                    DesktopColumn<DesktopInvitationRow>(
                      label: 'Branch',
                      flex: 2,
                      minWidth: 100,
                      sortBy: (i) => i.branch.toLowerCase(),
                      cell: (context, i) =>
                          DesktopCellText(i.branch, muted: true),
                    ),
                    DesktopColumn<DesktopInvitationRow>(
                      label: 'Invited by',
                      flex: 2,
                      minWidth: 100,
                      cell: (context, i) =>
                          DesktopCellText(i.invitedBy, muted: true),
                    ),
                    DesktopColumn<DesktopInvitationRow>(
                      label: 'Sent',
                      width: 120,
                      sortBy: (i) => i.sentAt?.millisecondsSinceEpoch ?? 0,
                      cell: (context, i) => DesktopCellText(
                        lastActiveLabel(i.sentAt),
                        muted: true,
                      ),
                    ),
                    DesktopColumn<DesktopInvitationRow>(
                      label: 'Status',
                      width: 100,
                      sortBy: (i) => i.statusLabel,
                      cell: (context, i) => DesktopStatusChip(
                        label: i.statusLabel,
                        color: i.statusColor,
                      ),
                    ),
                  ],
                  empty: DesktopEmptyState(
                    icon: Icons.mail_outline_rounded,
                    title: 'No invitations sent yet',
                    message: 'Invite the people who work in your shop. They '
                        'get a code by email to join.',
                    action: onInvite == null
                        ? null
                        : FilledButton.icon(
                            onPressed: onInvite,
                            icon: const Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 18,
                            ),
                            label: const Text('Invite user'),
                          ),
                  ),
                ),
        ),
      ],
    );
  }
}
