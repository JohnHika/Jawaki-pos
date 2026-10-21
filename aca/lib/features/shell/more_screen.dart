import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../state/session.dart';
import '../account/account_screen.dart';
import '../security/audit_screen.dart';
import '../team/team_screen.dart';

/// The "More" tab: who you are, plus everything that isn't a main tab.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final session = context.watch<SessionController>();
    final me = session.me;

    void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          AcaCard(
            onTap: () => open(const AccountScreen()),
            child: Row(
              children: [
                Avatar(me?.name, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me?.name ?? '—', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(me?.email ?? '', style: TextStyle(color: p.textMuted, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(children: [
                        StatusPill(Fmt.label(me?.role), tone: StatusTone.role(me?.role ?? ''), dense: true),
                        const SizedBox(width: 6),
                        StatusPill(
                          me?.twoFactorEnabled == true ? '2FA on' : '2FA off',
                          tone: me?.twoFactorEnabled == true ? Tone.success : Tone.warning,
                          icon: me?.twoFactorEnabled == true ? Icons.verified_user_rounded : Icons.warning_amber_rounded,
                          dense: true,
                        ),
                      ]),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: p.textFaint),
              ],
            ),
          ),
          const SectionHeader('Workspace'),
          AcaCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Gate(
                  permission: Perm.teamView,
                  child: _Row(
                    icon: Icons.groups_rounded,
                    title: 'Team & roles',
                    subtitle: 'Staff, roles and who is signed in',
                    onTap: () => open(const TeamScreen()),
                  ),
                ),
                Gate(
                  permission: Perm.auditView,
                  child: _Row(
                    icon: Icons.history_rounded,
                    title: 'Audit log',
                    subtitle: 'Who did what, and when',
                    onTap: () => open(const AuditScreen()),
                  ),
                ),
                _Row(
                  icon: Icons.manage_accounts_rounded,
                  title: 'Account & security',
                  subtitle: 'Password, 2FA, devices, app lock',
                  onTap: () => open(const AccountScreen()),
                  last: true,
                ),
              ],
            ),
          ),
          const SectionHeader('About'),
          AcaCard(
            child: Column(
              children: [
                KeyValueRow('Product', AcaConfig.appFullName),
                KeyValueRow('Connected to', AcaConfig.serverLabel),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (_, snap) => KeyValueRow(
                    'Version',
                    snap.hasData ? '${snap.data!.version} (${snap.data!.buildNumber})' : '…',
                  ),
                ),
                if (!AcaConfig.isProduction) KeyValueRow('Build', 'QA · not production', valueWidget: const StatusPill('QA', tone: Tone.warning, dense: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.subtitle, required this.onTap, this.last = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: p.brand, size: 22),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
          trailing: Icon(Icons.chevron_right_rounded, color: p.textFaint),
        ),
        if (!last) Divider(indent: 72, color: p.border),
      ],
    );
  }
}
