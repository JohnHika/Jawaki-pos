import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import '../billing/sheet_parts.dart';
import '../team/staff_detail_screen.dart';
import 'audit_entry_card.dart';
import 'audit_screen.dart';
import 'security_logic.dart';

/// Security centre: how well the Counterbase team is protected right now, who
/// is locked out, what failed to sign in and which alerts need a look.
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AcaRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: LoadBuilder<SecurityOverview>(
        load: repo.securityOverview,
        skeleton: const _SecuritySkeleton(),
        builder: (context, data, reload) => _SecurityBody(overview: data, onReload: reload),
      ),
    );
  }
}

class _SecuritySkeleton extends StatelessWidget {
  const _SecuritySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: const [
        Skeleton(height: 150, radius: 16),
        SizedBox(height: 20),
        Row(children: [
          Expanded(child: Skeleton(height: 92, radius: 16)),
          SizedBox(width: 12),
          Expanded(child: Skeleton(height: 92, radius: 16)),
        ]),
        SizedBox(height: 12),
        Row(children: [
          Expanded(child: Skeleton(height: 92, radius: 16)),
          SizedBox(width: 12),
          Expanded(child: Skeleton(height: 92, radius: 16)),
        ]),
        SizedBox(height: 20),
        Skeleton(height: 76, radius: 16),
        SizedBox(height: 10),
        Skeleton(height: 76, radius: 16),
      ],
    );
  }
}

String _displayName(String name, String email) => name.trim().isEmpty ? email : name.trim();

void _openStaff(BuildContext context, String id, String name) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => StaffDetailScreen(staffId: id, name: name)),
  );
}

class _SecurityBody extends StatelessWidget {
  const _SecurityBody({required this.overview, required this.onReload});

  final SecurityOverview overview;
  final Future<void> Function() onReload;

  Future<void> _unlock(BuildContext context, LockedAccount account) async {
    final name = _displayName(account.name, account.email);
    final confirmed = await confirmSheet(
      context,
      title: 'Unlock $name?',
      message: '${account.email} will be able to sign in again straight away and the failed-attempt count is cleared. '
          'Only unlock if you are sure the lock was not caused by someone guessing the password.',
      confirmLabel: 'Unlock account',
    );
    if (!confirmed || !context.mounted) return;
    final repo = context.read<AcaRepository>();
    final done = await runAction(context, () => repo.unlockStaff(account.id), success: '$name unlocked');
    if (done) await onReload();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final o = overview;
    final canManage = session.can(Perm.securityManage);
    final canOpenStaff = session.can(Perm.teamView);
    final canOpenAudit = session.can(Perm.auditView);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _PostureCard(overview: o),

        const SectionHeader('Last 24 hours'),
        _TilePair(
          left: StatTile(
            label: 'Failed sign-ins',
            value: Fmt.number(o.failedLogins24h),
            icon: Icons.gpp_bad_outlined,
            tone: o.failedLogins24h > 0 ? Tone.danger : Tone.neutral,
          ),
          right: StatTile(
            label: 'Successful sign-ins',
            value: Fmt.number(o.successfulLogins24h),
            icon: Icons.login_rounded,
            tone: o.successfulLogins24h > 0 ? Tone.success : Tone.neutral,
          ),
        ),

        const SectionHeader('Last 7 days'),
        _TilePair(
          left: StatTile(
            label: 'Critical alerts',
            value: Fmt.number(o.critical7d),
            icon: Icons.report_gmailerrorred_rounded,
            tone: o.critical7d > 0 ? Tone.danger : Tone.neutral,
          ),
          right: StatTile(
            label: 'Warnings',
            value: Fmt.number(o.warn7d),
            icon: Icons.warning_amber_rounded,
            tone: o.warn7d > 0 ? Tone.warning : Tone.neutral,
          ),
        ),

        SectionHeader('Locked accounts${o.lockedAccounts.isEmpty ? '' : ' (${o.lockedAccounts.length})'}'),
        if (o.lockedAccounts.isEmpty)
          const _AllClearCard(icon: Icons.lock_open_rounded, text: 'No accounts are locked')
        else
          for (final a in o.lockedAccounts)
            _LockedAccountCard(
              account: a,
              onUnlock: canManage ? () => _unlock(context, a) : null,
              onTap: canOpenStaff ? () => _openStaff(context, a.id, _displayName(a.name, a.email)) : null,
            ),

        SectionHeader(
          'Staff without two-step sign-in${o.withoutTwoFactor.isEmpty ? '' : ' (${o.withoutTwoFactor.length})'}',
        ),
        if (o.withoutTwoFactor.isEmpty)
          _AllClearCard(
            icon: Icons.verified_user_outlined,
            text: o.activeStaff == 0
                ? 'There are no active staff accounts'
                : 'Every active staff member uses two-step sign-in',
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              'These accounts are protected by a password only. Ask them to turn on two-step sign-in from their Account screen.',
              style: TextStyle(color: context.aca.textMuted, fontSize: 13, height: 1.4),
            ),
          ),
          for (final s in o.withoutTwoFactor)
            _StaffRefCard(
              staff: s,
              onTap: canOpenStaff ? () => _openStaff(context, s.id, _displayName(s.name, s.email)) : null,
            ),
        ],

        if (o.topFailedIps.isNotEmpty) ...[
          const SectionHeader('Most failed sign-ins by IP (24 h)'),
          _FailedIpsCard(ips: o.topFailedIps),
        ],

        const SectionHeader('Recent alerts'),
        if (o.recentEvents.isEmpty)
          const _AllClearCard(icon: Icons.notifications_none_rounded, text: 'No warnings or critical events recorded')
        else
          for (final e in o.recentEvents) AuditEntryCard(entry: e, onTap: () => showAuditEntrySheet(context, e)),
        if (canOpenAudit) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AuditScreen()),
            ),
            icon: const Icon(Icons.history_rounded),
            label: const Text('Open full audit log'),
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------- posture

class _PostureCard extends StatelessWidget {
  const _PostureCard({required this.overview});

  final SecurityOverview overview;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final o = overview;
    final pct = o.twoFactorCoveragePercent.clamp(0, 100);
    final tone = coverageTone(pct);
    final color = p.toneColor(tone);
    final protectedCount = (o.activeStaff - o.withoutTwoFactor.length).clamp(0, o.activeStaff);

    final headline = switch (tone) {
      Tone.success => 'Fully protected',
      Tone.danger => 'No one uses two-step sign-in',
      _ => 'Not everyone is protected',
    };

    return AcaCard(
      tone: tone == Tone.danger ? Tone.danger : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CoverageRing(percent: pct, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Two-step sign-in coverage',
                      style: TextStyle(color: p.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(headline, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      o.activeStaff == 0
                          ? 'No active staff accounts.'
                          : '$protectedCount of ${o.activeStaff} active staff '
                              '${protectedCount == 1 ? 'uses' : 'use'} a verification code on top of their password.',
                      style: TextStyle(color: p.textMuted, fontSize: 13, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: p.border),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'Active staff', value: Fmt.number(o.activeStaff))),
              Expanded(child: _MiniStat(label: 'Disabled', value: Fmt.number(o.disabledStaff))),
              Expanded(child: _MiniStat(label: 'Active sessions', value: Fmt.number(o.activeSessions))),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoverageRing extends StatelessWidget {
  const _CoverageRing({required this.percent, required this.color});

  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: percent / 100),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => SizedBox(
        width: 92,
        height: 92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 9,
                strokeCap: value > 0 ? StrokeCap.round : null,
                backgroundColor: p.surfaceHigh,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            SizedBox(
              width: 58,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$percent%',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: p.textMuted),
        ),
      ],
    );
  }
}

class _TilePair extends StatelessWidget {
  const _TilePair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      ),
    );
  }
}

class _AllClearCard extends StatelessWidget {
  const _AllClearCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return AcaCard(
      child: Row(
        children: [
          Icon(icon, color: p.success),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- lists

class _LockedAccountCard extends StatelessWidget {
  const _LockedAccountCard({required this.account, required this.onUnlock, required this.onTap});

  final LockedAccount account;
  final VoidCallback? onUnlock;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final name = _displayName(account.name, account.email);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AcaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(name, tone: Tone.danger),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      Text(
                        account.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.textMuted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusPill(Fmt.label(account.role), tone: StatusTone.role(account.role), dense: true),
                StatusPill(
                  unlockLabel(account.lockedUntil),
                  tone: Tone.warning,
                  icon: Icons.lock_clock_rounded,
                  dense: true,
                ),
              ],
            ),
            if (onUnlock != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Unlock'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StaffRefCard extends StatelessWidget {
  const _StaffRefCard({required this.staff, required this.onTap});

  final StaffRef staff;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final name = _displayName(staff.name, staff.email);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AcaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Avatar(name, tone: Tone.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  Text(
                    staff.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textMuted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusPill(Fmt.label(staff.role), tone: StatusTone.role(staff.role), dense: true),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: p.textFaint),
          ],
        ),
      ),
    );
  }
}

class _FailedIpsCard extends StatelessWidget {
  const _FailedIpsCard({required this.ips});

  /// ip -> failed attempts.
  final Map<String, int> ips;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final entries = ips.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final most = entries.first.value <= 0 ? 1 : entries.first.value;

    return AcaCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Divider(color: p.border, height: 1),
            InkWell(
              onTap: () => copyToClipboard(context, entries[i].key, what: 'IP address copied'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entries[i].key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: entries[i].value / most,
                              minHeight: 6,
                              backgroundColor: p.surfaceHigh,
                              valueColor: AlwaysStoppedAnimation<Color>(p.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${entries[i].value} ${entries[i].value == 1 ? 'attempt' : 'attempts'}',
                      style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
