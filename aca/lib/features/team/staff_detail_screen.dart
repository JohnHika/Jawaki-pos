import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import '../account/account_logic.dart' show plural;
import '../account/account_screen.dart';
import '../account/session_tile.dart';
import '../account/sheet_kit.dart';
import '../security/audit_screen.dart';
import 'credential_sheet.dart';
import 'edit_staff_sheet.dart';
import 'role_widgets.dart';
import 'team_logic.dart';

class _StaffPage {
  const _StaffPage({required this.staff, required this.roles, this.sessions, this.sessionsError});
  final StaffMember staff;
  final List<RoleInfo> roles;

  /// Null when the signed-in person may not see sessions, or loading them failed.
  final List<SessionInfo>? sessions;
  final Object? sessionsError;
}

/// One staff member: identity, security state, devices, recent activity, and the
/// actions the signed-in person is allowed to take (the server enforces them too).
class StaffDetailScreen extends StatefulWidget {
  const StaffDetailScreen({super.key, required this.staffId, this.name});

  final String staffId;
  final String? name;

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  final _loader = GlobalKey<LoadBuilderState<_StaffPage>>();

  /// Name from the server once loaded (the caller's [StaffDetailScreen.name] is only a placeholder).
  String? _loadedName;

  Future<_StaffPage> _load() async {
    final repo = context.read<AcaRepository>();
    final wantSessions = context.read<SessionController>().can(Perm.securityView);
    List<SessionInfo>? sessions;
    Object? sessionsError;
    final sessionsLoad = wantSessions
        ? repo.staffSessions(widget.staffId).then<void>(
            (v) {
              sessions = v;
            },
            onError: (Object e) {
              sessionsError = e;
            },
          )
        : Future<void>.value();
    final r = await Future.wait<Object?>([repo.staff(widget.staffId), repo.roles(), sessionsLoad]);
    if (mounted) setState(() => _loadedName = (r[0] as StaffMember).name);
    return _StaffPage(
      staff: r[0] as StaffMember,
      roles: r[1] as List<RoleInfo>,
      sessions: sessions,
      sessionsError: sessionsError,
    );
  }

  Future<void> _reload() async => _loader.currentState?.reload();

  // ---------------------------------------------------------------- actions

  Future<void> _edit(StaffMember m) async {
    final saved = await showEditStaffSheet(context, staff: m);
    if (saved != true || !mounted) return;
    toast(context, 'Details saved');
    await _reload();
  }

  Future<void> _changeRole(_StaffPage page) async {
    final m = page.staff;
    final repo = context.read<AcaRepository>();
    final role = await showRolePicker(context, name: m.name, currentRole: m.role, roles: page.roles);
    if (role == null || role == m.role || !mounted) return;
    final label = Fmt.label(role);
    final ok = await confirmSheet(
      context,
      title: 'Change role to $label?',
      message: '${m.name} is signed out of every device straight away. '
          'They get $label access the next time they sign in.',
      confirmLabel: 'Change role',
    );
    if (!ok || !mounted) return;
    final done = await runAction(context, () => repo.updateStaff(m.id, role: role), success: 'Role changed to $label');
    if (done) await _reload();
  }

  Future<void> _setStatus(StaffMember m, {required bool enable}) async {
    final repo = context.read<AcaRepository>();
    final ok = await confirmSheet(
      context,
      title: enable ? 'Enable ${m.name}?' : 'Disable ${m.name}?',
      message: enable
          ? 'They can sign in again with their current password.'
          : 'They can no longer sign in, and they are signed out of every device straight away. '
              'You can enable the account again later.',
      confirmLabel: enable ? 'Enable account' : 'Disable account',
      destructive: !enable,
    );
    if (!ok || !mounted) return;
    final done = await runAction(
      context,
      () => repo.updateStaff(m.id, status: enable ? 'ACTIVE' : 'DISABLED'),
      success: enable ? 'Account enabled' : 'Account disabled',
    );
    if (done) await _reload();
  }

  Future<void> _resetPassword(StaffMember m) async {
    final repo = context.read<AcaRepository>();
    final ok = await confirmSheet(
      context,
      title: 'Reset ${m.name}\'s password?',
      message: 'Their current password stops working and a new temporary one is created. '
          'The account is unlocked and signed out on every device, and they must choose their own '
          'password at their next sign-in.',
      confirmLabel: 'Reset password',
      destructive: true,
    );
    if (!ok || !mounted) return;
    TempCredential? credential;
    final done = await runAction(context, () async {
      credential = await repo.resetStaffPassword(m.id, email: m.email);
    });
    final issued = credential;
    if (!done || issued == null) return;
    _reload();
    if (!mounted) return;
    await showCredentialSheet(context, credential: issued, kind: CredentialKind.reset, name: m.name);
    if (mounted) toast(context, 'Password reset for ${m.name}');
  }

  Future<void> _unlock(StaffMember m) async {
    final repo = context.read<AcaRepository>();
    final ok = await confirmSheet(
      context,
      title: 'Unlock ${m.name}?',
      message: 'They can try to sign in again straight away.',
      confirmLabel: 'Unlock account',
    );
    if (!ok || !mounted) return;
    final done = await runAction(context, () => repo.unlockStaff(m.id), success: 'Account unlocked');
    if (done) await _reload();
  }

  Future<void> _signOutEverywhere(StaffMember m, {required bool isSelf}) async {
    final repo = context.read<AcaRepository>();
    final ok = await confirmSheet(
      context,
      title: isSelf ? 'Sign out your other devices?' : 'Sign ${m.name} out everywhere?',
      message: isSelf
          ? 'Every device except this phone is signed out straight away.'
          : 'Every device ${m.name} is signed in on is signed out straight away. '
              'They can sign in again with their password.',
      confirmLabel: isSelf ? 'Sign out other devices' : 'Sign out everywhere',
      destructive: true,
    );
    if (!ok || !mounted) return;
    var count = 0;
    final done = await runAction(context, () async {
      count = await repo.revokeStaffSessions(m.id);
    });
    if (!done || !mounted) return;
    toast(context, count <= 0 ? 'No sessions were signed in' : 'Signed out ${plural(count, 'session')}');
    await _reload();
  }

  Future<void> _open(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) toast(context, 'No app on this phone can open that', error: true);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionController>().me;
    return Scaffold(
      appBar: AppBar(title: Text(_loadedName ?? widget.name ?? 'Staff member', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: me == null
          ? const SizedBox.shrink()
          : LoadBuilder<_StaffPage>(
              key: _loader,
              load: _load,
              skeleton: const ListSkeleton(rows: 4, rowHeight: 120),
              builder: (context, page, reload) => _content(context, me, page),
            ),
    );
  }

  Widget _content(BuildContext context, StaffProfile me, _StaffPage page) {
    final session = context.read<SessionController>();
    final m = page.staff;
    final isSelf = m.id == me.id;
    final rights = staffRights(can: session.can, myId: me.id, myRole: me.role, target: m, roles: page.roles);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _HeaderCard(staff: m, isSelf: isSelf, onOpen: _open),
        if (isSelf) ...[
          const SizedBox(height: 12),
          AcaCard(
            tone: Tone.brand,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
            child: Row(
              children: [
                const Icon(Icons.manage_accounts_rounded),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('This is your account. Change your password, two-step verification and devices in Account & security.'),
                ),
                Icon(Icons.chevron_right_rounded, color: context.aca.textFaint),
              ],
            ),
          ),
        ],
        const SectionHeader('Security'),
        _SecurityCard(staff: m),
        if (rights.any) ...[
          const SectionHeader('Actions'),
          AcaCard(
            padding: EdgeInsets.zero,
            child: _ActionList(
              actions: [
                if (rights.editProfile)
                  _Action(Icons.edit_outlined, 'Edit details', 'Change name or phone number', () => _edit(m)),
                if (rights.changeRole)
                  _Action(Icons.swap_horiz_rounded, 'Change role', 'Now ${Fmt.label(m.role)}. They are signed out when it changes.',
                      () => _changeRole(page)),
                if (rights.resetPassword)
                  _Action(Icons.lock_reset_rounded, 'Reset password',
                      'Issue a new temporary password, unlock and sign out', () => _resetPassword(m)),
                if (rights.unlock)
                  _Action(Icons.lock_open_rounded, 'Unlock account', lockedUntilText(m.lockedUntil), () => _unlock(m)),
                if (rights.signOutEverywhere)
                  _Action(
                    Icons.devices_other_rounded,
                    isSelf ? 'Sign out other devices' : 'Sign out of all devices',
                    '${sessionsText(m.activeSessions)} right now',
                    () => _signOutEverywhere(m, isSelf: isSelf),
                    destructive: true,
                  ),
                if (rights.setStatus)
                  m.isActive
                      ? _Action(Icons.block_rounded, 'Disable account', 'Blocks sign-in and signs them out now',
                          () => _setStatus(m, enable: false),
                          destructive: true)
                      : _Action(Icons.check_circle_outline_rounded, 'Enable account', 'Lets them sign in again',
                          () => _setStatus(m, enable: true)),
              ],
            ),
          ),
        ],
        if (session.can(Perm.securityView)) ...[
          const SectionHeader('Devices signed in'),
          _SessionsBlock(page: page, onRetry: _reload),
        ],
        const SectionHeader('Recent activity'),
        _ActivityCard(staff: m),
        if (session.can(Perm.auditView)) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AuditScreen(actorId: m.id, title: m.name),
            )),
            icon: const Icon(Icons.history_rounded),
            label: const Text('See everything this person did'),
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------- header

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.staff, required this.isSelf, required this.onOpen});

  final StaffMember staff;
  final bool isSelf;
  final Future<void> Function(Uri uri) onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final m = staff;
    final phone = m.phone?.trim();
    final disabled = !m.isActive;
    return AcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(m.name, size: 64, tone: disabled ? Tone.neutral : StatusTone.role(m.role)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusPill(Fmt.label(m.role), tone: StatusTone.role(m.role), dense: true),
                        StatusPill(disabled ? 'Disabled' : 'Active',
                            tone: disabled ? Tone.neutral : Tone.success, dense: true),
                        if (isSelf) const StatusPill('You', tone: Tone.brand, dense: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ContactLine(
            icon: Icons.mail_outline_rounded,
            text: m.email,
            onTap: () => onOpen(Uri(scheme: 'mailto', path: m.email)),
          ),
          if (phone != null && phone.isNotEmpty)
            _ContactLine(
              icon: Icons.call_outlined,
              text: phone,
              onTap: () => onOpen(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s+'), ''))),
            ),
          if (m.createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Added ${Fmt.date(m.createdAt)}', style: TextStyle(color: p.textFaint, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

/// Tap opens the mail/phone app; long-press copies.
class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.icon, required this.text, required this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: text));
        toast(context, 'Copied');
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Icon(icon, size: 20, color: p.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text))),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- security

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.staff});
  final StaffMember staff;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final m = staff;
    final ip = m.lastLoginIp?.trim();
    return AcaCard(
      child: Column(
        children: [
          KeyValueRow(
            'Two-step sign-in',
            null,
            valueWidget: StatusPill(
              m.twoFactorEnabled ? 'On' : 'Off',
              tone: m.twoFactorEnabled ? Tone.success : Tone.warning,
              dense: true,
            ),
          ),
          KeyValueRow(
            'Account',
            null,
            valueWidget: m.locked
                ? Text(
                    lockedUntilText(m.lockedUntil),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.w700, color: p.danger),
                  )
                : const StatusPill('Not locked', tone: Tone.success, dense: true),
          ),
          KeyValueRow('Failed attempts', '${m.failedLoginAttempts}'),
          KeyValueRow(
            'Last sign-in',
            null,
            valueWidget: m.lastLoginAt == null
                ? Text('Never', style: TextStyle(fontWeight: FontWeight.w600, color: p.text))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(Fmt.dateTime(m.lastLoginAt),
                          textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: p.text)),
                      Text(
                        [Fmt.ago(m.lastLoginAt), if (ip != null && ip.isNotEmpty) ip].join(' · '),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: p.textMuted, fontSize: 12.5),
                      ),
                    ],
                  ),
          ),
          KeyValueRow('Password changed', passwordChangedText(m)),
          KeyValueRow('Active sessions', '${m.activeSessions}'),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ actions

class _Action {
  const _Action(this.icon, this.title, this.subtitle, this.onTap, {this.destructive = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;
}

class _ActionList extends StatelessWidget {
  const _ActionList({required this.actions});
  final List<_Action> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Column(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          ListTile(
            onTap: actions[i].onTap,
            minVerticalPadding: 10,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(actions[i].icon, color: actions[i].destructive ? p.danger : p.brand),
            title: Text(
              actions[i].title,
              style: TextStyle(fontWeight: FontWeight.w600, color: actions[i].destructive ? p.danger : p.text),
            ),
            subtitle: Text(actions[i].subtitle, style: TextStyle(color: p.textMuted, fontSize: 12.5, height: 1.3)),
            trailing: Icon(Icons.chevron_right_rounded, color: p.textFaint),
          ),
          if (i < actions.length - 1) Divider(indent: 56, color: p.border),
        ],
      ],
    );
  }
}

// ----------------------------------------------------------------- sessions

class _SessionsBlock extends StatelessWidget {
  const _SessionsBlock({required this.page, required this.onRetry});

  final _StaffPage page;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final items = page.sessions;
    if (items == null) {
      return AcaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              page.sessionsError == null ? 'Devices are not available.' : errorMessage(page.sessionsError!),
              style: TextStyle(color: p.textMuted),
            ),
            if (page.sessionsError != null) TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return AcaCard(child: Text('Not signed in on any device.', style: TextStyle(color: p.textMuted)));
    }
    return Column(
      children: [
        for (final s in items) ...[
          SessionTile(session: s),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ----------------------------------------------------------------- activity

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.staff});
  final StaffMember staff;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final entries = staff.recentActivity.take(15).toList();
    if (entries.isEmpty) {
      return AcaCard(child: Text('No activity recorded for this person yet.', style: TextStyle(color: p.textMuted)));
    }
    return AcaCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _ActivityRow(entry: entries[i]),
            if (i < entries.length - 1) Divider(color: p.border),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});
  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final summary = (entry.summary == null || entry.summary!.trim().isEmpty) ? Fmt.label(entry.action) : entry.summary!;
    final tone = StatusTone.severity(entry.severity);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 12),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: tone == Tone.neutral ? p.textFaint : p.toneColor(tone), shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 2),
                Text(
                  '${Fmt.ago(entry.createdAt)} · ${Fmt.label(entry.category)}',
                  style: TextStyle(color: p.textFaint, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
