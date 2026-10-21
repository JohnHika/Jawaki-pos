import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api_client.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import 'tenant_actions.dart';
import 'tenant_billing_tab.dart';
import 'tenant_changes.dart';
import 'tenant_devices_tab.dart';
import 'tenant_notes_tab.dart';
import 'tenant_overview_tab.dart';
import 'tenant_people_tab.dart';
import 'tenant_widgets.dart';
import 'tenants_logic.dart';

/// Opens a company's detail screen. Used by the Clients list and the Overview.
Future<void> openTenant(BuildContext context, {required String id, String? name}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TenantDetailScreen(tenantId: id, tenantName: name)));

/// One company: Overview, People, Devices, Billing and Notes tabs, plus the
/// actions staff can take on it (extend, suspend, credit, lock out...).
class TenantDetailScreen extends StatefulWidget {
  const TenantDetailScreen({super.key, required this.tenantId, this.tenantName});

  final String tenantId;
  final String? tenantName;

  @override
  State<TenantDetailScreen> createState() => _TenantDetailScreenState();
}

class _Tab {
  const _Tab(this.label, this.builder);
  final String label;
  final Widget Function() builder;
}

class _TenantDetailScreenState extends State<TenantDetailScreen> {
  DetailLoad _load = const DetailLoad();

  /// Bumped after every change so open tabs reload themselves.
  final ValueNotifier<int> _refresh = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _loadDetail(first: true);
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _loadDetail({bool first = false}) async {
    final repo = context.read<AcaRepository>();
    final previous = _load.detail;
    if (!first) setState(() => _load = DetailLoad(detail: previous, loading: true));
    try {
      final d = await repo.tenant(widget.tenantId);
      if (!mounted) return;
      setState(() => _load = DetailLoad(detail: d, loading: false));
    } catch (e) {
      if (!mounted) return;
      if (previous != null) {
        setState(() => _load = DetailLoad(detail: previous, loading: false));
        toast(context, e is ApiException ? e.message : 'Could not refresh this company.', error: true);
      } else {
        setState(() => _load = DetailLoad(error: e, loading: false));
      }
    }
  }

  /// After a successful change: re-read the company, tell the tabs, tell the lists.
  Future<void> _afterChange() async {
    await _loadDetail();
    if (!mounted) return;
    _refresh.value++;
    tenantChanges.bump();
  }

  List<_Tab> _tabs(SessionController session, String name) => [
        _Tab(
          'Overview',
          () => TenantOverviewTab(
            tenantId: widget.tenantId,
            tenantName: name,
            load: _load,
            onReload: _loadDetail,
            refresh: _refresh,
          ),
        ),
        if (session.can(Perm.tenantsUsers))
          _Tab('People', () => TenantPeopleTab(tenantId: widget.tenantId, tenantName: name, refresh: _refresh)),
        if (session.can(Perm.tenantsUsers)) _Tab('Devices', () => TenantDevicesTab(tenantId: widget.tenantId, refresh: _refresh)),
        if (session.can(Perm.billingView))
          _Tab(
            'Billing',
            () => TenantBillingTab(tenantId: widget.tenantId, load: _load, onReload: _loadDetail, refresh: _refresh),
          ),
        if (session.can(Perm.tenantsView)) _Tab('Notes', () => TenantNotesTab(tenantId: widget.tenantId, refresh: _refresh)),
      ];

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final session = context.watch<SessionController>();
    final d = _load.detail;
    final name = d?.name ?? widget.tenantName ?? 'Company';
    final tabs = _tabs(session, name);
    final actions = d == null
        ? const <TenantAction>[]
        : availableActions(can: session.can, subscriptionStatus: d.subscriptionStatus, isActive: d.isActive);

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (d != null && d.slug.isNotEmpty)
                Text(d.slug, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.textMuted, fontWeight: FontWeight.w500)),
            ],
          ),
          actions: [
            if (actions.isNotEmpty && d != null)
              IconButton(
                tooltip: 'Actions',
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => showTenantActionsSheet(context, tenant: d, onChanged: _afterChange),
              ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: p.border,
            indicatorColor: p.brand,
            labelColor: p.text,
            unselectedLabelColor: p.textMuted,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: [for (final t in tabs) Tab(text: t.label, height: 48)],
          ),
        ),
        body: Column(
          children: [
            if (d != null && !d.isActive)
              _LockoutBanner(
                onLift: session.can(Perm.tenantsSecurity)
                    ? () => liftTenantLockout(context, tenant: d, onChanged: _afterChange)
                    : null,
              ),
            Expanded(
              child: TabBarView(
                children: [for (final t in tabs) KeepAliveTab(child: t.builder())],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockoutBanner extends StatelessWidget {
  const _LockoutBanner({required this.onLift});
  final VoidCallback? onLift;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Container(
      width: double.infinity,
      color: p.toneFill(Tone.danger),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, color: p.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This company is locked out — nobody can sign in',
              style: TextStyle(color: p.danger, fontWeight: FontWeight.w700, height: 1.3),
            ),
          ),
          if (onLift != null)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: p.danger),
              onPressed: onLift,
              child: const Text('Lift lockout'),
            ),
        ],
      ),
    );
  }
}
