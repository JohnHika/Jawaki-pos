import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import '../billing/billing_screen.dart';
import '../tenants/tenant_changes.dart';
import '../tenants/tenant_detail_screen.dart';
import '../tenants/tenants_logic.dart';
import '../tenants/tenants_screen.dart';
import 'overview_chart.dart';
import 'overview_logic.dart';

/// Overview tab: the health of the whole book of business at a glance.
class OverviewScreen extends StatefulWidget {
  /// [staleAfter]: when the app comes back to the foreground and the data is older than this, it quietly reloads.
  const OverviewScreen({super.key, this.staleAfter = const Duration(seconds: 90)});

  final Duration staleAfter;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> with WidgetsBindingObserver {
  final _key = GlobalKey<LoadBuilderState<Overview>>();
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tenantChanges.addListener(_reloadQuietly);
  }

  @override
  void dispose() {
    tenantChanges.removeListener(_reloadQuietly);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A company changed somewhere in the app: refresh without a spinner, keeping what is on screen.
  void _reloadQuietly() => _key.currentState?.reload();

  /// Coming back to the app after a while: the numbers are stale, refresh them.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final at = _loadedAt;
    if (state == AppLifecycleState.resumed && at != null && DateTime.now().difference(at) >= widget.staleAfter) {
      _reloadQuietly();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final repo = context.read<AcaRepository>();
    final me = context.select<SessionController, String?>((s) => s.me?.name);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Overview'),
            Text(
              greetingLine(me, DateTime.now()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: p.textMuted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: LoadBuilder<Overview>(
        key: _key,
        skeleton: const _OverviewSkeleton(),
        load: () async {
          final o = await repo.overview();
          _loadedAt = DateTime.now();
          return o;
        },
        builder: (context, overview, reload) => _OverviewBody(overview: overview),
      ),
    );
  }
}

// ------------------------------------------------------------------- helpers

/// "Updated 2 min ago". A server clock slightly ahead of the phone reads as "just now", never "in 2 min".
String _updatedLabel(DateTime? generatedAt) {
  if (generatedAt == null) return 'Live data';
  return generatedAt.isAfter(DateTime.now()) ? 'Updated just now' : 'Updated ${Fmt.ago(generatedAt)}';
}

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({required this.overview});
  final Overview overview;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final o = overview;
    final session = context.watch<SessionController>();
    final canTenants = session.can(Perm.tenantsView);
    final canBilling = session.can(Perm.billingView);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _HeroCard(overview: o),
        SectionHeader(
          'Companies',
          action: canTenants ? 'View all' : null,
          onAction: canTenants ? () => _push(context, const TenantsScreen()) : null,
        ),
        _CompaniesSection(overview: o, canOpen: canTenants),
        SectionHeader('Revenue · last ${o.monthly.isEmpty ? 6 : o.monthly.length} months'),
        _RevenueCard(months: o.monthly),
        SectionHeader(
          'Billing at a glance',
          action: canBilling ? 'Open' : null,
          onAction: canBilling ? () => _push(context, const BillingScreen()) : null,
        ),
        _BillingGlance(overview: o, canOpen: canBilling),
        const SectionHeader('Needs attention'),
        _TenantListCard(
          tenants: o.needsAttention,
          canOpen: canTenants,
          emptyIcon: Icons.verified_rounded,
          emptyTitle: 'Every client is in good standing',
          emptyMessage: 'No company is past due or suspended.',
        ),
        const SectionHeader('Expiring in 14 days'),
        _TenantListCard(
          tenants: o.expiringSoon,
          canOpen: canTenants,
          emptyIcon: Icons.event_available_rounded,
          emptyTitle: 'Nothing expires soon',
          emptyMessage: 'No subscription ends in the next 14 days.',
        ),
        const SectionHeader('Fleet'),
        _FleetCard(overview: o),
        const SectionHeader('Recent payments'),
        _PaymentsCard(payments: o.recentPayments.take(10).toList(), canOpen: canTenants),
        const SizedBox(height: 20),
        Center(
          child: Text(
            _updatedLabel(o.generatedAt),
            style: TextStyle(fontSize: 12.5, color: p.textFaint),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------- hero

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.overview});
  final Overview overview;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final o = overview;
    final pct = o.collectedChangePct;

    return AcaCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly recurring revenue', style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Fmt.kes(o.mrrKes),
              style: TextStyle(
                fontSize: 36,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                color: p.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${Fmt.kes(o.arrKes)} a year (ARR)', style: TextStyle(color: p.textMuted)),
          const Divider(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Collected last 30 days', style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        Fmt.kes(o.collected30),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text, letterSpacing: -0.3),
                      ),
                    ),
                  ],
                ),
              ),
              if (pct != null) ...[const SizedBox(width: 12), _DeltaChip(pct: pct)],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            pct != null
                ? 'Previous 30 days: ${Fmt.kes(o.collectedPrev30)}'
                : (o.collected30 > 0
                    ? 'Nothing was collected in the 30 days before, so there is nothing to compare with.'
                    : 'Nothing collected in the last 60 days.'),
            style: TextStyle(color: p.textFaint, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.pct});
  final double pct;

  @override
  Widget build(BuildContext context) {
    final tone = deltaTone(pct);
    final icon = tone == Tone.success
        ? Icons.arrow_upward_rounded
        : tone == Tone.danger
            ? Icons.arrow_downward_rounded
            : Icons.remove_rounded;
    return Semantics(
      label: '${formatDelta(pct)} compared with the previous 30 days',
      child: StatusPill(formatDelta(pct), tone: tone, icon: icon),
    );
  }
}

// ----------------------------------------------------------------- companies

class _CompaniesSection extends StatelessWidget {
  const _CompaniesSection({required this.overview, required this.canOpen});
  final Overview overview;
  final bool canOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final o = overview;
    final cancelled = o.byStatus['CANCELLED'] ?? 0;

    Widget tile(OverviewStatusTile t) {
      final count = o.byStatus[t.status] ?? 0;
      return StatTile(
        label: t.label,
        value: Fmt.number(count),
        tone: count == 0 ? Tone.neutral : t.tone,
        onTap: canOpen ? () => _push(context, TenantsScreen(initialStatus: t.status)) : null,
      );
    }

    Widget pair(OverviewStatusTile a, OverviewStatusTile b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tile(a)),
              const SizedBox(width: 12),
              Expanded(child: tile(b)),
            ],
          ),
        );

    final tiles = kOverviewStatusTiles;
    return Column(
      children: [
        AcaCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Fmt.number(o.tenantTotal),
                      style: TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: p.text),
                    ),
                    const SizedBox(height: 2),
                    Text(o.tenantTotal == 1 ? 'company in total' : 'companies in total', style: TextStyle(color: p.textMuted)),
                    if (cancelled > 0) Text('$cancelled cancelled', style: TextStyle(color: p.textFaint, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusPill(
                    '${o.newTenants30 > 0 ? '+' : ''}${o.newTenants30} new',
                    tone: o.newTenants30 > 0 ? Tone.success : Tone.neutral,
                    icon: Icons.person_add_alt_1_rounded,
                  ),
                  const SizedBox(height: 4),
                  Text('in last 30 days', style: TextStyle(color: p.textMuted, fontSize: 12.5)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        pair(tiles[0], tiles[1]),
        const SizedBox(height: 12),
        pair(tiles[2], tiles[3]),
      ],
    );
  }
}

// ------------------------------------------------------------------- revenue

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({required this.months});
  final List<MonthRevenue> months;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final n = months.isEmpty ? 6 : months.length;

    if (!hasRevenue(months)) {
      return AcaCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: p.surfaceHigh, shape: BoxShape.circle),
              child: Icon(Icons.bar_chart_rounded, color: p.textMuted, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              'No payments recorded in the last $n months',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'The chart fills in as soon as a company pays an invoice.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.textMuted, height: 1.4),
            ),
          ],
        ),
      );
    }

    return AcaCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: Fmt.kes(revenueTotal(months)), style: TextStyle(fontWeight: FontWeight.w800, color: p.text, fontSize: 16)),
                TextSpan(text: '  collected in $n months', style: TextStyle(color: p.textMuted, fontSize: 13)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          RevenueChart(months: months),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- billing

class _BillingGlance extends StatelessWidget {
  const _BillingGlance({required this.overview, required this.canOpen});
  final Overview overview;
  final bool canOpen;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    void open() => _push(context, const BillingScreen());
    return AcaCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _GlanceRow(
            icon: Icons.receipt_long_rounded,
            title: 'Pending invoices',
            caption: 'Waiting to be paid',
            count: o.pendingInvoices,
            tone: Tone.info,
            onTap: canOpen ? open : null,
          ),
          const Divider(),
          _GlanceRow(
            icon: Icons.warning_amber_rounded,
            title: 'Overdue',
            caption: 'Unpaid for more than 7 days',
            count: o.overdueInvoices,
            tone: Tone.danger,
            onTap: canOpen ? open : null,
          ),
          const Divider(),
          _GlanceRow(
            icon: Icons.phone_iphone_rounded,
            title: 'M-Pesa claims waiting',
            caption: 'Manual payments to reconcile',
            count: o.pendingClaims,
            tone: Tone.warning,
            onTap: canOpen ? open : null,
          ),
        ],
      ),
    );
  }
}

class _GlanceRow extends StatelessWidget {
  const _GlanceRow({required this.icon, required this.title, required this.caption, required this.count, required this.tone, required this.onTap});

  final IconData icon;
  final String title;
  final String caption;
  final int count;
  final Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final hot = count > 0;
    final tint = hot ? tone : Tone.neutral;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: p.toneFill(tint), shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: p.toneColor(tint)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(caption, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                Fmt.number(count),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: hot ? p.toneColor(tone) : p.text),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: p.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ company lists

class _TenantListCard extends StatelessWidget {
  const _TenantListCard({
    required this.tenants,
    required this.canOpen,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final List<OverviewTenant> tenants;
  final bool canOpen;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    if (tenants.isEmpty) {
      return AcaCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.toneFill(Tone.success), shape: BoxShape.circle),
              child: Icon(emptyIcon, color: p.success),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emptyTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(emptyMessage, style: TextStyle(color: p.textMuted, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return AcaCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < tenants.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            _TenantRow(
              tenant: tenants[i],
              onTap: canOpen ? () => openTenant(context, id: tenants[i].id, name: tenants[i].name) : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _TenantRow extends StatelessWidget {
  const _TenantRow({required this.tenant, required this.onTap});
  final OverviewTenant tenant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final t = tenant;
    final statusTone = StatusTone.subscription(t.subscriptionStatus);
    final end = endTone(t.currentPeriodEnd);
    final endColor = end == Tone.neutral ? p.textMuted : p.toneColor(end);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Avatar(t.name, size: 40, tone: statusTone == Tone.neutral ? Tone.brand : statusTone),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (!planRepeatsStatus(t.plan, t.subscriptionStatus)) StatusPill(Fmt.label(t.plan), tone: Tone.brand, dense: true),
                        StatusPill(Fmt.label(t.subscriptionStatus), tone: statusTone, dense: true),
                        Text(
                          Fmt.daysUntil(t.currentPeriodEnd),
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: endColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: p.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- fleet

class _FleetCard extends StatelessWidget {
  const _FleetCard({required this.overview});
  final Overview overview;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final o = overview;
    final breakdown = versionBreakdown(o.appVersions);
    final pct = activePercent(o.devicesActive24h, o.devices);

    Widget metric(String label, String value, String? caption) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 26, height: 1.1, fontWeight: FontWeight.w800, color: p.text, letterSpacing: -0.4)),
              ),
              if (caption != null) Text(caption, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
            ],
          ),
        );

    return AcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              metric('Devices', Fmt.number(o.devices), 'registered'),
              const SizedBox(width: 12),
              metric('Active in 24 h', Fmt.number(o.devicesActive24h), pct == null ? null : '$pct% of devices'),
            ],
          ),
          const Divider(height: 28),
          Text('APP VERSIONS', style: TextStyle(fontSize: 11.5, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: p.textMuted)),
          const SizedBox(height: 10),
          if (breakdown.shown.isEmpty)
            Text(
              o.devices == 0 ? 'No device has registered yet.' : 'No app version has been reported yet.',
              style: TextStyle(color: p.textMuted),
            )
          else ...[
            for (final v in breakdown.shown) _VersionBar(share: v),
            if (breakdown.otherVersions > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+ ${plural(breakdown.otherVersions, 'other version')} on ${plural(breakdown.otherDevices, 'device')}',
                  style: TextStyle(color: p.textMuted, fontSize: 12.5),
                ),
              ),
            const SizedBox(height: 10),
            if (breakdown.latest != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    breakdown.behindLatest > 0 ? Icons.system_update_rounded : Icons.check_circle_rounded,
                    size: 16,
                    color: breakdown.behindLatest > 0 ? p.warning : p.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      breakdown.behindLatest > 0
                          ? '${plural(breakdown.behindLatest, 'device')} not on the newest version (${breakdown.latest})'
                          : 'Every device is on the newest version (${breakdown.latest})',
                      style: TextStyle(color: breakdown.behindLatest > 0 ? p.warning : p.success, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _VersionBar extends StatelessWidget {
  const _VersionBar({required this.share});
  final VersionShare share;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final s = share;
    final color = s.unknown ? p.textFaint : (s.latest ? p.success : p.warning);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              s.unknown ? 'Unknown' : 'v${s.version}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: s.latest ? FontWeight.w800 : FontWeight.w600, color: s.latest ? p.text : p.textMuted),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Stack(
                children: [
                  Container(height: 10, color: p.surfaceHigh),
                  FractionallySizedBox(
                    widthFactor: s.fraction.clamp(0.04, 1.0),
                    child: Container(height: 10, color: color),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(Fmt.number(s.devices), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ payments

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({required this.payments, required this.canOpen});
  final List<PaymentRow> payments;
  final bool canOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    if (payments.isEmpty) {
      return AcaCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.surfaceHigh, shape: BoxShape.circle),
              child: Icon(Icons.payments_outlined, color: p.textMuted),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No payments yet', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Payments appear here the moment a company pays.', style: TextStyle(color: p.textMuted, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return AcaCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < payments.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            _PaymentRow(
              payment: payments[i],
              onTap: canOpen ? () => openTenant(context, id: payments[i].tenantId, name: payments[i].tenantName) : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.onTap});
  final PaymentRow payment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final x = payment;
    final credit = x.amount < 0 || x.provider?.toUpperCase() == 'CREDIT';
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: credit ? p.toneFill(Tone.info) : p.toneFill(Tone.success), shape: BoxShape.circle),
                child: Icon(credit ? Icons.card_giftcard_rounded : Icons.south_west_rounded, size: 19, color: credit ? p.info : p.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(x.tenantName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${providerLabel(x.provider)} · ${Fmt.ago(x.paidAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                Fmt.kes(x.amount),
                style: TextStyle(fontWeight: FontWeight.w800, color: credit ? p.info : p.text, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: p.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ skeleton

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: const [
        Skeleton(height: 176, radius: 16),
        SizedBox(height: 32),
        Skeleton(height: 18, width: 120),
        SizedBox(height: 12),
        Skeleton(height: 84, radius: 16),
        SizedBox(height: 12),
        Row(children: [Expanded(child: Skeleton(height: 84, radius: 16)), SizedBox(width: 12), Expanded(child: Skeleton(height: 84, radius: 16))]),
        SizedBox(height: 12),
        Row(children: [Expanded(child: Skeleton(height: 84, radius: 16)), SizedBox(width: 12), Expanded(child: Skeleton(height: 84, radius: 16))]),
        SizedBox(height: 32),
        Skeleton(height: 220, radius: 16),
      ],
    );
  }
}
