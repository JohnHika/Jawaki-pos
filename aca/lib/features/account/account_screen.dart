import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import 'account_logic.dart';
import 'change_password_sheet.dart';
import 'disable_two_factor_sheet.dart';
import 'session_tile.dart';
import 'sheet_kit.dart';
import 'two_factor_setup_screen.dart';

/// "Account & security": profile, password, two-step verification, app lock,
/// privacy, the devices signed in as this person, and sign out.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _devices = GlobalKey<_DevicesSectionState>();
  late final Future<PackageInfo> _package = PackageInfo.fromPlatform();

  Future<void> _refresh() async {
    final session = context.read<SessionController>();
    await Future.wait<void>([session.reloadProfile(), _devices.currentState?.reload() ?? Future<void>.value()]);
  }

  Future<void> _changePassword() async {
    final changed = await showChangePasswordSheet(context);
    if (changed != true || !mounted) return;
    toast(context, 'Password changed. Your other devices were signed out.');
    _devices.currentState?.reload();
    context.read<SessionController>().reloadProfile();
  }

  Future<void> _turnOnTwoFactor() async {
    final on = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const TwoFactorSetupScreen()),
    );
    if (on == true && mounted) toast(context, 'Two-step verification is on');
  }

  Future<void> _turnOffTwoFactor() async {
    final session = context.read<SessionController>();
    final off = await showDisableTwoFactorSheet(context);
    if (off != true) return;
    await session.reloadProfile();
    if (mounted) toast(context, 'Two-step verification is off');
  }

  Future<void> _signOut() async {
    final session = context.read<SessionController>();
    final nav = Navigator.of(context);
    final needsCode = session.me?.twoFactorEnabled == true;
    final ok = await confirmSheet(
      context,
      title: 'Sign out of ACA?',
      message: 'You will need your password${needsCode ? ' and a verification code' : ''} to sign back in.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final done = await runAction(context, () => session.signOut());
    if (done) nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final session = context.watch<SessionController>();
    final me = session.me;
    // Briefly true while signing out, before the route is popped.
    if (me == null) return const Scaffold(body: SizedBox.shrink());

    final lockAvailable = session.deviceCanLock;
    return Scaffold(
      appBar: AppBar(title: const Text('Account & security')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _ProfileCard(me: me),
            const SectionHeader('Sign-in security'),
            AcaCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _SettingRow(
                    icon: Icons.password_rounded,
                    title: 'Change password',
                    subtitle: 'Signs you out of your other devices',
                    onTap: _changePassword,
                  ),
                  Divider(indent: 72, color: p.border),
                  _SettingRow(
                    icon: Icons.verified_user_outlined,
                    title: 'Two-step verification',
                    subtitle: me.twoFactorEnabled
                        ? 'On. A code from your authenticator app is needed to sign in. Tap to turn off.'
                        : 'Off. Add a code from an authenticator app for much stronger protection. Tap to turn on.',
                    trailing: StatusPill(
                      me.twoFactorEnabled ? 'On' : 'Off',
                      tone: me.twoFactorEnabled ? Tone.success : Tone.warning,
                      dense: true,
                    ),
                    onTap: me.twoFactorEnabled ? _turnOffTwoFactor : _turnOnTwoFactor,
                  ),
                  Divider(indent: 72, color: p.border),
                  _SwitchRow(
                    icon: Icons.fingerprint_rounded,
                    title: 'App lock',
                    subtitle: lockAvailable
                        ? 'Ask for your fingerprint, face or screen lock when you come back to ACA'
                        : 'Set up a screen lock or fingerprint on this phone first',
                    value: lockAvailable && session.lockEnabled,
                    onChanged: lockAvailable ? (v) => session.setLockEnabled(v) : null,
                  ),
                  Divider(indent: 72, color: p.border),
                  _SwitchRow(
                    icon: Icons.visibility_off_outlined,
                    title: 'Hide ACA in screenshots and recent apps',
                    subtitle: 'Blocks screenshots and blanks the preview in the app switcher',
                    value: session.hideContent,
                    onChanged: (v) => session.setHideContent(v),
                  ),
                ],
              ),
            ),
            _DevicesSection(key: _devices),
            const SectionHeader('Connection'),
            AcaCard(
              child: Column(
                children: [
                  KeyValueRow('Connected to', AcaConfig.serverLabel),
                  FutureBuilder<PackageInfo>(
                    future: _package,
                    builder: (_, snap) => KeyValueRow(
                      'App version',
                      snap.hasData ? '${snap.data!.version} (${snap.data!.buildNumber})' : (snap.hasError ? '—' : '…'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _signOut,
              style: OutlinedButton.styleFrom(
                foregroundColor: p.danger,
                side: BorderSide(color: p.danger.withValues(alpha: 0.6)),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- profile

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.me});
  final StaffProfile me;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final since = memberSince(me.createdAt);
    final phone = me.phone?.trim();
    return AcaCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(me.name, size: 60, tone: Tone.brand),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(me.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(me.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textMuted, fontSize: 13.5)),
                if (phone != null && phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textMuted, fontSize: 13.5)),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(Fmt.label(me.role), tone: StatusTone.role(me.role), dense: true),
                    if (since != null) Text('Member since $since', style: TextStyle(color: p.textFaint, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- rows

class _RowIcon extends StatelessWidget {
  const _RowIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: p.brand, size: 22),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _RowIcon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(subtitle, style: TextStyle(color: p.textMuted, fontSize: 12.5, height: 1.35)),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
          Icon(Icons.chevron_right_rounded, color: p.textFaint),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      secondary: _RowIcon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(subtitle, style: TextStyle(color: p.textMuted, fontSize: 12.5, height: 1.35)),
      ),
    );
  }
}

// ------------------------------------------------------------------- devices

class _DevicesSection extends StatefulWidget {
  const _DevicesSection({super.key});

  @override
  State<_DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends State<_DevicesSection> {
  List<SessionInfo>? _items;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final repo = context.read<AcaRepository>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await repo.mySessions();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      if (_items != null) toast(context, errorMessage(e), error: true);
    }
  }

  Future<void> _signOutDevice(SessionInfo s) async {
    final repo = context.read<AcaRepository>();
    final ok = await confirmSheet(
      context,
      title: 'Sign out ${deviceTitle(s)}?',
      message: 'That device is signed out straight away and will need your password to get back in.',
      confirmLabel: 'Sign out device',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final done = await runAction(context, () => repo.revokeMySession(s.id), success: 'Device signed out');
    if (done) await reload();
  }

  Future<void> _signOutOthers(int count) async {
    final repo = context.read<AcaRepository>();
    final ok = await confirmSheet(
      context,
      title: 'Sign out all other devices?',
      message: '${plural(count, 'other device')} will be signed out straight away. This phone stays signed in.',
      confirmLabel: 'Sign out other devices',
      destructive: true,
    );
    if (!ok || !mounted) return;
    var revoked = 0;
    final done = await runAction(context, () async {
      revoked = await repo.revokeMyOtherSessions();
    });
    if (!done || !mounted) return;
    toast(context, signedOutOthersMessage(revoked));
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final items = _items;
    final others = items == null ? const <SessionInfo>[] : otherSessions(items);

    Widget body;
    if (items == null && _loading) {
      body = const Column(
        children: [Skeleton(height: 66, radius: 16), SizedBox(height: 10), Skeleton(height: 66, radius: 16)],
      );
    } else if (items == null) {
      body = AcaCard(child: ErrorState(error: _error ?? 'Could not load devices', onRetry: reload));
    } else if (items.isEmpty) {
      body = AcaCard(child: Text('No devices are signed in.', style: TextStyle(color: p.textMuted)));
    } else {
      body = Column(
        children: [
          for (final s in items) ...[
            SessionTile(
              session: s,
              trailing: s.current
                  ? null
                  : PopupMenuButton<String>(
                      tooltip: 'Device options',
                      icon: Icon(Icons.more_vert_rounded, color: p.textMuted),
                      onSelected: (_) => _signOutDevice(s),
                      itemBuilder: (_) => const [
                        PopupMenuItem<String>(value: 'signout', child: Text('Sign out this device')),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
          ],
          if (others.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _signOutOthers(others.length),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.danger,
                side: BorderSide(color: p.danger.withValues(alpha: 0.6)),
              ),
              icon: const Icon(Icons.devices_other_rounded),
              label: const Text('Sign out all other devices'),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const SectionHeader('Devices signed in'), body],
    );
  }
}
