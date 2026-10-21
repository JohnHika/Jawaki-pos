import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import '../security/audit_screen.dart';
import 'license_editor_screen.dart';
import 'license_logic.dart';
import 'tenant_changes.dart';
import 'tenant_widgets.dart';
import 'tenants_logic.dart';

/// Overview tab of a company: who they are, the subscription, and the licence.
class TenantOverviewTab extends StatefulWidget {
  const TenantOverviewTab({
    super.key,
    required this.tenantId,
    required this.tenantName,
    required this.load,
    required this.onReload,
    required this.refresh,
  });

  final String tenantId;
  final String tenantName;
  final DetailLoad load;
  final Future<void> Function() onReload;
  final Listenable refresh;

  @override
  State<TenantOverviewTab> createState() => _TenantOverviewTabState();
}

class _TenantOverviewTabState extends State<TenantOverviewTab> with TenantRefreshMixin {
  LicenseView? _license;
  Object? _licenseError;
  bool _licenseLoading = true;

  @override
  Listenable get refreshSignal => widget.refresh;

  @override
  void onRefreshSignal() => _loadLicense();

  @override
  void initState() {
    super.initState();
    _loadLicense(first: true);
  }

  Future<void> _loadLicense({bool first = false}) async {
    final repo = context.read<AcaRepository>();
    if (!first) {
      setState(() {
        _licenseLoading = _license == null;
        _licenseError = null;
      });
    }
    try {
      final j = await repo.license(widget.tenantId);
      if (!mounted) return;
      setState(() {
        _license = LicenseView.fromJson(j);
        _licenseLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _licenseError = e;
        _licenseLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([widget.onReload(), _loadLicense()]);
  }

  Future<void> _editLicense(String name) async {
    final current = _license;
    if (current == null) return;
    final saved = await Navigator.of(context).push<LicenseEditResult?>(
      MaterialPageRoute(
        builder: (_) => LicenseEditorScreen(tenantId: widget.tenantId, tenantName: name, license: current),
      ),
    );
    if (!mounted || saved == null) return; // cancelled: nothing changed
    tenantChanges.bump();
    final updated = saved.license;
    if (updated != null) {
      setState(() => _license = updated);
    } else {
      // Saved, but the server sent nothing usable back: re-read it.
      await _loadLicense();
    }
  }

  @override
  Widget build(BuildContext context) {
    final load = widget.load;
    final d = load.detail;
    if (d == null) {
      if (load.error != null) {
        return RefreshableFill(onRefresh: widget.onReload, child: ErrorState(error: load.error!, onRetry: widget.onReload));
      }
      return const TabSkeleton(rows: 3, rowHeight: 150);
    }
    final session = context.watch<SessionController>();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kTabPadding,
        children: [
          _HeaderCard(detail: d),
          const SectionHeader('Subscription'),
          _SubscriptionCard(detail: d, license: _license, licenseLoading: _licenseLoading),
          const SectionHeader('Licence'),
          _LicenseCard(
            license: _license,
            loading: _licenseLoading,
            error: _licenseError,
            onRetry: _loadLicense,
            onEdit: session.can(Perm.tenantsLicense) ? () => _editLicense(d.name) : null,
          ),
          if (session.can(Perm.auditView)) ...[
            const SizedBox(height: 16),
            AcaCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => AuditScreen(tenantId: d.id, title: d.name)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, color: context.aca.textMuted),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Audit trail for this company', style: TextStyle(fontWeight: FontWeight.w700))),
                    Icon(Icons.chevron_right_rounded, color: context.aca.textFaint),
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

// ------------------------------------------------------------------- header

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.detail});
  final TenantDetail detail;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final d = detail;
    final owner = d.owner;
    final statusTone = StatusTone.subscription(d.subscriptionStatus);
    return AcaCard(
      tone: d.isActive ? null : Tone.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(d.name, size: 52, tone: d.isActive ? (statusTone == Tone.neutral ? Tone.brand : statusTone) : Tone.danger),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
                    if (d.slug.isNotEmpty)
                      Text(d.slug, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (!d.isActive) const StatusPill('Locked out', tone: Tone.danger, icon: Icons.lock_rounded),
              if (!planRepeatsStatus(d.plan, d.subscriptionStatus)) StatusPill(Fmt.label(d.plan), tone: Tone.brand),
              StatusPill(Fmt.label(d.subscriptionStatus), tone: statusTone),
              if (d.activationStatus != null)
                StatusPill('Activation ${Fmt.label(d.activationStatus).toLowerCase()}', tone: activationTone(d.activationStatus)),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(),
          ContactRow(
            icon: Icons.person_outline_rounded,
            label: owner == null || owner.fullName.isEmpty ? 'Owner' : 'Owner · ${owner.fullName}',
            value: owner?.email,
            onTap: owner == null ? null : () => openLink(context, Uri(scheme: 'mailto', path: owner.email)),
            onLongPressCopy: owner?.email,
          ),
          ContactRow(
            icon: Icons.phone_outlined,
            label: 'Billing phone',
            value: d.billingPhone,
            onTap: d.billingPhone == null ? null : () => openLink(context, Uri(scheme: 'tel', path: d.billingPhone!.replaceAll(RegExp(r'\s'), ''))),
            onLongPressCopy: d.billingPhone,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- subscription

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.detail, required this.license, required this.licenseLoading});

  final TenantDetail detail;
  final LicenseView? license;
  final bool licenseLoading;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final d = detail;
    final end = endTone(d.currentPeriodEnd);
    final endColor = end == Tone.neutral ? p.textMuted : p.toneColor(end);

    // Effective limits come from the licence (plan allowance vs company columns); fall back to the company record.
    final maxUsers = license?.maxUsers ?? d.maxUsers;
    final maxBranches = license?.maxBranches ?? d.maxBranches;

    return AcaCard(
      child: Column(
        children: [
          KeyValueRow('Plan', null, valueWidget: StatusPill(Fmt.label(d.plan), tone: Tone.brand, dense: true)),
          KeyValueRow('Status', null,
              valueWidget: StatusPill(Fmt.label(d.subscriptionStatus), tone: StatusTone.subscription(d.subscriptionStatus), dense: true)),
          KeyValueRow('Period started', Fmt.date(d.currentPeriodStart)),
          KeyValueRow(
            'Period ends',
            null,
            valueWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.date(d.currentPeriodEnd), style: TextStyle(fontWeight: FontWeight.w600, color: p.text)),
                Text(Fmt.daysUntil(d.currentPeriodEnd), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: endColor)),
              ],
            ),
          ),
          KeyValueRow('Auto-renew', d.autoRenewEnabled ? 'On' : 'Off'),
          KeyValueRow('Payment provider', d.subscriptionProvider == null ? null : providerLabel(d.subscriptionProvider)),
          KeyValueRow(
            'Activation',
            null,
            valueWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusPill(Fmt.label(d.activationStatus), tone: activationTone(d.activationStatus), dense: true),
                if (d.activationPaidAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('Paid ${Fmt.date(d.activationPaidAt)}', style: TextStyle(fontSize: 12.5, color: p.textMuted)),
                  ),
              ],
            ),
          ),
          KeyValueRow('Setup fee', d.setupFeePaidAt == null ? 'Not recorded as paid' : 'Paid ${Fmt.date(d.setupFeePaidAt)}'),
          const Divider(height: 20),
          if (licenseLoading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Skeleton(height: 14))
          else ...[
            _Seat(label: 'Users', used: d.userCount, max: maxUsers),
            _Seat(label: 'Branches', used: d.branchCount, max: maxBranches),
          ],
        ],
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({required this.label, required this.used, required this.max});
  final String label;
  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final unlimited = max >= kUnlimitedSeats || max <= 0;
    final full = seatsFull(used, max);
    final fraction = unlimited ? 0.0 : (used / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(color: p.textMuted))),
              Text(
                max <= 0 ? '$used' : seatsLabel(used, max),
                style: TextStyle(fontWeight: FontWeight.w700, color: full ? p.warning : p.text),
              ),
            ],
          ),
          if (!unlimited) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: p.surfaceHigh,
                color: full ? p.warning : p.brand,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- licence

class _LicenseCard extends StatelessWidget {
  const _LicenseCard({
    required this.license,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onEdit,
  });

  final LicenseView? license;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final l = license;

    if (l == null) {
      if (loading) return const AcaCard(child: Column(children: [Skeleton(height: 16), SizedBox(height: 12), Skeleton(height: 16), SizedBox(height: 12), Skeleton(height: 60)]));
      final msg = error is ApiException ? (error as ApiException).message : 'Couldn\'t load the licence.';
      final forbidden = error is ApiException && (error as ApiException).isForbidden;
      return AcaCard(
        child: Column(
          children: [
            Icon(forbidden ? Icons.lock_outline_rounded : Icons.error_outline_rounded, color: p.textMuted, size: 30),
            const SizedBox(height: 8),
            Text(forbidden ? 'Not allowed for your role' : 'Couldn\'t load the licence', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(msg, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
            if (!forbidden) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(160, 44)),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      );
    }

    final enforcementTone = switch (l.enforcement) {
      'enforce' => Tone.danger,
      'warn' => Tone.warning,
      _ => Tone.neutral,
    };
    final enforcementText = switch (l.enforcement) {
      'enforce' => 'Enforced',
      'warn' => 'Warn only',
      _ => 'Not enforced',
    };

    return AcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusPill(enforcementText, tone: enforcementTone, icon: Icons.shield_outlined),
              StatusPill('${Fmt.label(l.plan)} plan', tone: Tone.brand),
              if (l.expired) const StatusPill('Expired', tone: Tone.danger, icon: Icons.event_busy_rounded),
            ],
          ),
          const SizedBox(height: 4),
          Text(enforcementExplain(l.enforcement), style: TextStyle(color: p.textMuted, fontSize: 12.5, height: 1.4)),
          if (l.unknownPlan) ...[
            const SizedBox(height: 8),
            Text(
              'This plan is not on the price list, so every module stays open until the company moves to a real plan or you set modules by hand.',
              style: TextStyle(color: p.info, fontSize: 12.5, height: 1.4),
            ),
          ],
          const Divider(height: 24),
          KeyValueRow('Licence key', l.licenseKey ?? 'Not issued yet', onCopy: l.licenseKey),
          KeyValueRow('Valid until', l.validUntil == null ? 'No expiry' : Fmt.date(l.validUntil)),
          KeyValueRow(
            'Limits',
            '${l.maxBranches >= kUnlimitedSeats ? 'Unlimited' : plural(l.maxBranches, 'branch', 'branches')} · '
                '${l.maxUsers >= kUnlimitedSeats ? 'unlimited' : plural(l.maxUsers, 'user')}',
          ),
          if (l.note != null && l.note!.trim().isNotEmpty) KeyValueRow('Note', l.note!.trim()),
          const SizedBox(height: 8),
          Text('MODULES', style: TextStyle(fontSize: 11.5, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: p.textMuted)),
          const SizedBox(height: 8),
          if (l.features.isEmpty)
            Text('No modules listed.', style: TextStyle(color: p.textMuted))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in l.features.entries) _ModuleChip(label: featureLabel(e.key), allowed: e.value.allowed, status: l.featureStatus(e.key)),
              ],
            ),
          if (onEdit != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit licence'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModuleChip extends StatelessWidget {
  const _ModuleChip({required this.label, required this.allowed, required this.status});
  final String label;
  final bool allowed;
  final String status;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final tone = allowed ? Tone.success : Tone.neutral;
    final c = p.toneColor(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: p.toneFill(tone), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(allowed ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded, size: 15, color: c),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: label, style: TextStyle(fontWeight: FontWeight.w700, color: allowed ? p.text : p.textMuted)),
                TextSpan(text: ' · $status', style: TextStyle(color: p.textMuted)),
              ]),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
