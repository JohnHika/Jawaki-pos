import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import 'permission_labels.dart';
import 'team_logic.dart';

/// "Roles & access": every role, what it can do, which one is yours, and which
/// ones you may hand out.
class RolesScreen extends StatelessWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AcaRepository>();
    final myRole = context.select<SessionController, String?>((s) => s.me?.role);
    return Scaffold(
      appBar: AppBar(title: const Text('Roles & access')),
      body: LoadBuilder<List<RoleInfo>>(
        load: repo.roles,
        emptyWhen: (r) => r.isEmpty,
        empty: const EmptyState(
          icon: Icons.admin_panel_settings_outlined,
          title: 'No roles found',
          message: 'The server did not return any roles.',
        ),
        builder: (context, roles, reload) {
          final ordered = [...roles]..sort((a, b) => b.rank.compareTo(a.rank));
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _YourAccess(myRole: myRole, roles: roles),
              const SizedBox(height: 14),
              for (final r in ordered) ...[
                _RoleCard(role: r, isMine: r.role == myRole),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _YourAccess extends StatelessWidget {
  const _YourAccess({required this.myRole, required this.roles});

  final String? myRole;
  final List<RoleInfo> roles;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final assignable = assignableRoles(roles);
    final mine = myRole == null ? 'your role' : 'the ${Fmt.label(myRole)} role';
    final text = assignable.isEmpty
        ? 'You are signed in with $mine. It cannot add staff or change anyone\'s role.'
        : 'You are signed in with $mine. You can give out: ${assignable.map((r) => Fmt.label(r.role)).join(', ')}.';
    return AcaCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.badge_outlined, color: p.brand),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: p.textMuted, height: 1.45))),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.isMine});

  final RoleInfo role;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final tone = StatusTone.role(role.role);
    final sections = permissionSections(role.permissions);
    return AcaCard(
      tone: isMine ? Tone.brand : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(Fmt.label(role.role),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.toneColor(tone))),
              if (isMine) const StatusPill('Your role', tone: Tone.brand, dense: true),
              if (role.assignable)
                const StatusPill('You can assign', tone: Tone.success, icon: Icons.check_rounded, dense: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(role.description, style: TextStyle(color: p.textMuted, height: 1.4)),
          for (final s in sections) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.title.toUpperCase(),
                    style: TextStyle(fontSize: 11.5, letterSpacing: 1, fontWeight: FontWeight.w700, color: p.textMuted),
                  ),
                ),
                Text('${s.grantedCount} of ${s.lines.length}', style: TextStyle(fontSize: 11.5, color: p.textFaint)),
              ],
            ),
            const SizedBox(height: 4),
            for (final l in s.lines) _PermissionRow(line: l),
          ],
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.line});
  final PermissionLine line;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final granted = line.granted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            granted ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
            size: 18,
            color: granted ? p.success : p.textFaint,
            semanticLabel: granted ? 'Allowed' : 'Not allowed',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              line.label,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.3,
                color: granted ? p.text : p.textFaint,
                decoration: granted ? null : TextDecoration.lineThrough,
                decorationColor: p.textFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
