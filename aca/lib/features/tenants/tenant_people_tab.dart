import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import 'tenant_changes.dart';
import 'tenant_widgets.dart';
import 'tenants_logic.dart';

/// People tab: the company's own staff accounts (not Counterbase staff).
class TenantPeopleTab extends StatefulWidget {
  const TenantPeopleTab({super.key, required this.tenantId, required this.tenantName, required this.refresh});

  final String tenantId;
  final String tenantName;
  final Listenable refresh;

  @override
  State<TenantPeopleTab> createState() => _TenantPeopleTabState();
}

class _TenantPeopleTabState extends State<TenantPeopleTab> with TenantRefreshMixin {
  final _key = GlobalKey<LoadBuilderState<List<TenantUser>>>();

  @override
  Listenable get refreshSignal => widget.refresh;

  @override
  void onRefreshSignal() => _key.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AcaRepository>();
    return LoadBuilder<List<TenantUser>>(
      key: _key,
      load: () => repo.tenantUsers(widget.tenantId),
      emptyWhen: (u) => u.isEmpty,
      empty: const EmptyState(
        icon: Icons.people_outline_rounded,
        title: 'No people yet',
        message: 'This company has not added any staff accounts.',
      ),
      builder: (context, users, reload) {
        final p = context.aca;
        final active = users.where((u) => u.isActive).length;
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: kTabPadding,
          itemCount: users.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text(
                  '${plural(users.length, 'person', 'people')} · $active active',
                  style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              );
            }
            final u = users[i - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _UserCard(
                user: u,
                onTap: () => _openUser(context, u, reload),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openUser(BuildContext context, TenantUser user, Future<void> Function() reload) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _UserSheet(tenantId: widget.tenantId, user: user),
    );
    if (changed == true) {
      await reload();
      tenantChanges.bump();
    }
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onTap});
  final TenantUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final u = user;
    final title = u.fullName.isEmpty ? u.email : u.fullName;
    return AcaCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(title, size: 42, tone: u.isActive ? null : Tone.neutral),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                if (u.fullName.isNotEmpty)
                  Text(u.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    StatusPill(Fmt.label(u.role), tone: companyRoleTone(u.role), dense: true),
                    u.isActive
                        ? const StatusPill('Active', tone: Tone.success, dense: true)
                        : const StatusPill('Deactivated', tone: Tone.danger, icon: Icons.block_rounded, dense: true),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  u.lastLoginAt == null ? 'Never signed in' : 'Last sign-in ${Fmt.ago(u.lastLoginAt)}',
                  style: TextStyle(fontSize: 12.5, color: p.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  u.activeSessions == 0 ? 'No active sessions' : plural(u.activeSessions, 'active session'),
                  style: TextStyle(fontSize: 12.5, color: u.activeSessions == 0 ? p.textFaint : p.success),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(Icons.chevron_right_rounded, color: p.textFaint),
          ),
        ],
      ),
    );
  }
}

/// Details + security actions for one company user. Pops `true` when something changed.
class _UserSheet extends StatelessWidget {
  const _UserSheet({required this.tenantId, required this.user});

  final String tenantId;
  final TenantUser user;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final canSecure = context.select<SessionController, bool>((s) => s.can(Perm.tenantsSecurity));
    final u = user;
    final title = u.fullName.isEmpty ? u.email : u.fullName;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(title, size: 48, tone: u.isActive ? null : Tone.neutral),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          StatusPill(Fmt.label(u.role), tone: companyRoleTone(u.role), dense: true),
                          u.isActive
                              ? const StatusPill('Active', tone: Tone.success, dense: true)
                              : const StatusPill('Deactivated', tone: Tone.danger, dense: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            KeyValueRow('Email', u.email, onCopy: u.email),
            KeyValueRow('Phone', u.phone),
            KeyValueRow('Last sign-in', u.lastLoginAt == null ? 'Never' : Fmt.dateTime(u.lastLoginAt)),
            KeyValueRow('Active sessions', '${u.activeSessions}'),
            KeyValueRow('Added', Fmt.date(u.createdAt)),
            const SizedBox(height: 12),
            if (!canSecure)
              Text('Your role can look at this account but not change it.', style: TextStyle(color: p.textMuted, fontSize: 13))
            else ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: u.isActive ? p.danger : p.text,
                ),
                onPressed: () => _toggleActive(context),
                icon: Icon(u.isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded),
                label: Text(u.isActive ? 'Deactivate user' : 'Reactivate user'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: u.activeSessions == 0 ? null : () => _signOutEverywhere(context),
                icon: const Icon(Icons.logout_rounded),
                label: Text(u.activeSessions == 0 ? 'Not signed in anywhere' : 'Sign out of all devices'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActive(BuildContext context) async {
    final repo = context.read<AcaRepository>();
    final nav = Navigator.of(context);
    final name = user.fullName.isEmpty ? user.email : user.fullName;
    final deactivate = user.isActive;
    final yes = await confirmAction(
      context,
      title: deactivate ? 'Deactivate $name?' : 'Reactivate $name?',
      message: deactivate
          ? 'They can no longer sign in and their current sessions end. You can reactivate the account later.'
          : 'They will be able to sign in to Counterbase again.',
      confirmLabel: deactivate ? 'Deactivate user' : 'Reactivate user',
      destructive: deactivate,
    );
    if (!yes || !context.mounted) return;
    final ok = await runAction(
      context,
      () => repo.setTenantUserActive(tenantId, user.id, active: !deactivate),
      success: deactivate ? '$name deactivated' : '$name reactivated',
    );
    if (ok) nav.pop(true);
  }

  Future<void> _signOutEverywhere(BuildContext context) async {
    final repo = context.read<AcaRepository>();
    final nav = Navigator.of(context);
    final name = user.fullName.isEmpty ? user.email : user.fullName;
    final yes = await confirmAction(
      context,
      title: 'Sign $name out?',
      message: 'Ends every session on every device. They can sign in again straight away.',
      confirmLabel: 'Sign out of all devices',
      destructive: true,
    );
    if (!yes || !context.mounted) return;
    var ended = 0;
    final ok = await runAction(context, () async {
      ended = await repo.revokeTenantUserSessions(tenantId, user.id);
    });
    if (ok) {
      if (context.mounted) toast(context, ended == 0 ? 'Nobody was signed in' : 'Signed out ${plural(ended, 'session')}');
      nav.pop(true);
    }
  }
}
