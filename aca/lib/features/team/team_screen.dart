import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import 'add_staff_sheet.dart';
import 'credential_sheet.dart';
import 'roles_screen.dart';
import 'staff_detail_screen.dart';
import 'team_logic.dart';

class _TeamData {
  const _TeamData(this.staff, this.roles);
  final List<StaffMember> staff;
  final List<RoleInfo> roles;
}

/// The Counterbase team: who has access, what role, and whether their account is
/// healthy (locked, no 2FA, invite pending). Opens staff pages and "Roles & access".
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _loader = GlobalKey<LoadBuilderState<_TeamData>>();

  /// Last loaded role catalogue; decides whether the "Add staff" button exists.
  List<RoleInfo> _roles = const [];

  Future<_TeamData> _load() async {
    final repo = context.read<AcaRepository>();
    final r = await Future.wait<Object>([repo.team(), repo.roles()]);
    final data = _TeamData(r[0] as List<StaffMember>, r[1] as List<RoleInfo>);
    if (mounted) setState(() => _roles = data.roles);
    return data;
  }

  void _openRoles() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RolesScreen()));

  Future<void> _add() async {
    await showAddStaffSheet(
      context,
      roles: _roles,
      onCreated: (added) async {
        _loader.currentState?.reload();
        if (!mounted) return;
        await showCredentialSheet(context, credential: added.credential, kind: CredentialKind.created, name: added.name);
        if (mounted) toast(context, '${added.name} was added to the team');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final p = context.aca;
    final canView = session.can(Perm.teamView);
    final showAdd = canView && canAddStaff(can: session.can, roles: _roles);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team'),
        actions: [
          if (canView)
            IconButton(
              tooltip: 'Roles & access',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: _openRoles,
            ),
        ],
      ),
      floatingActionButton: showAdd
          ? FloatingActionButton.extended(
              onPressed: _add,
              backgroundColor: p.brand,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add staff'),
            )
          : null,
      body: !canView
          ? const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Not allowed for your role',
              message: 'Your role cannot see the Counterbase team.',
            )
          : LoadBuilder<_TeamData>(
              key: _loader,
              load: _load,
              emptyWhen: (d) => d.staff.isEmpty,
              empty: const EmptyState(
                icon: Icons.groups_rounded,
                title: 'No staff yet',
                message: 'People you add will appear here with their role and sign-in status.',
              ),
              builder: (context, data, reload) {
                final groups = groupStaff(data.staff);
                final meId = session.me?.id;

                Widget tile(StaffMember m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _StaffTile(
                        member: m,
                        isMe: m.id == meId,
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => StaffDetailScreen(staffId: m.id, name: m.name),
                          ));
                          // Role, status or lock state may have changed over there.
                          reload();
                        },
                      ),
                    );

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 0, 16, showAdd ? 96 : 24),
                  children: [
                    if (groups.active.isNotEmpty) ...[
                      SectionHeader('Active · ${groups.active.length}'),
                      for (final m in groups.active) tile(m),
                    ],
                    if (groups.disabled.isNotEmpty) ...[
                      SectionHeader('Disabled · ${groups.disabled.length}'),
                      for (final m in groups.disabled) tile(m),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({required this.member, required this.isMe, required this.onTap});

  final StaffMember member;
  final bool isMe;
  final VoidCallback onTap;

  static IconData _icon(StaffFlagKind k) {
    switch (k) {
      case StaffFlagKind.disabled:
        return Icons.block_rounded;
      case StaffFlagKind.locked:
        return Icons.lock_rounded;
      case StaffFlagKind.invitePending:
        return Icons.mark_email_unread_outlined;
      case StaffFlagKind.twoFactorOn:
        return Icons.verified_user_rounded;
      case StaffFlagKind.noTwoFactor:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final m = member;
    final faded = !m.isActive;
    return Opacity(
      opacity: faded ? 0.72 : 1,
      child: AcaCard(
        tone: isMe ? Tone.brand : null,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(m.name, size: 44, tone: faded ? Tone.neutral : StatusTone.role(m.role)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 8),
                        const StatusPill('You', tone: Tone.brand, dense: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(m.email,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusPill(Fmt.label(m.role), tone: StatusTone.role(m.role), dense: true),
                      for (final f in staffFlags(m)) StatusPill(f.label, tone: f.tone, icon: _icon(f.kind), dense: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${lastSignInText(m.lastLoginAt)} · ${sessionsText(m.activeSessions)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textFaint, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 4),
              child: Icon(Icons.chevron_right_rounded, color: p.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}
