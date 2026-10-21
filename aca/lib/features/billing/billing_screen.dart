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
import '../tenants/tenant_changes.dart';
import '../tenants/tenant_detail_screen.dart';
import 'billing_logic.dart';
import 'claim_views.dart';
import 'invoice_views.dart';
import 'mark_paid_sheet.dart';
import 'paged_list.dart';
import 'sheet_parts.dart';

/// Billing tab: every subscription invoice across all companies, and the
/// manual M-Pesa payment claims waiting to be reconciled.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  static const int _pageSize = 20;

  late final AcaRepository _repo = context.read<AcaRepository>();
  late final PagedController<Invoice> _invoices;

  /// null = all, otherwise PENDING / PAID (what the API understands).
  String? _status;

  List<Claim>? _claims;
  Object? _claimsError;
  bool _claimsLoading = true;

  @override
  void initState() {
    super.initState();
    _invoices = PagedController<Invoice>(
      fetch: (page) => _repo.invoices(status: _status, page: page, pageSize: _pageSize),
      idOf: (i) => i.id,
    )..refresh();
    _loadClaims();
  }

  @override
  void dispose() {
    _invoices.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------- data

  Future<void> _loadClaims() async {
    if (!mounted) return;
    setState(() {
      _claimsLoading = true;
      _claimsError = null;
    });
    try {
      final claims = await _repo.pendingClaims();
      if (!mounted) return;
      setState(() {
        _claims = sortClaims(claims);
        _claimsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _claimsError = e;
        _claimsLoading = false;
      });
      if (_claims != null) toast(context, e is ApiException ? e.message : 'Refresh failed. Try again.', error: true);
    }
  }

  Future<void> _reloadAll() async {
    await Future.wait([_invoices.refresh(), _loadClaims()]);
  }

  void _setStatus(String? status) {
    if (status == _status) return;
    setState(() => _status = status);
    _invoices.refresh(clear: true);
  }

  // ---------------------------------------------------------------- actions

  void _openCompany(String tenantId, String? name) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TenantDetailScreen(tenantId: tenantId, tenantName: name)),
    );
  }

  Future<void> _onInvoiceTap(Invoice invoice) async {
    final action = await showInvoiceSheet(context, invoice);
    if (!mounted || action == null) return;
    switch (action) {
      case InvoiceSheetAction.openCompany:
        _openCompany(invoice.tenantId, invoice.tenantName);
      case InvoiceSheetAction.markPaid:
        await _markInvoicePaid(invoice);
    }
  }

  Future<void> _markInvoicePaid(Invoice invoice) async {
    final choice = await showMarkPaidSheet(
      context,
      company: invoice.tenantName ?? 'This company',
      amount: invoice.amount,
    );
    if (!mounted || choice == null) return;
    final ok = await runAction(
      context,
      () => _repo.markInvoicePaid(invoice.id, mpesaCode: choice.mpesaCode),
      success: choice.mpesaCode == null ? 'Invoice marked as paid' : 'Invoice marked as paid with the M-Pesa code',
    );
    if (ok) tenantChanges.bump(); // Overview and Clients pick up the new status
    if (ok && mounted) await _reloadAll();
  }

  Future<void> _markClaimPaid(Claim claim) async {
    final company = claim.tenantName ?? 'this company';
    final confirmed = await confirmSheet(
      context,
      title: 'Mark invoice as paid?',
      message: 'Confirm that M-Pesa payment ${claim.mpesaCode} for ${Fmt.kes(claim.amount)} from $company has arrived. '
          'The invoice is marked paid with this code and the claim is settled. The company is reactivated if it was past due or suspended, and moved onto this invoice\'s period if that is newer.',
      confirmLabel: 'Yes, mark as paid',
    );
    if (!confirmed || !mounted) return;
    final ok = await runAction(
      context,
      () => _repo.markInvoicePaid(claim.invoiceId, mpesaCode: claim.mpesaCode),
      success: 'Invoice marked as paid',
    );
    if (ok) tenantChanges.bump(); // Overview and Clients pick up the new status
    if (ok && mounted) await _reloadAll();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final waiting = actionableClaimCount(_claims ?? const []);
    final canOpenCompany = context.select<SessionController, bool>((s) => s.can(Perm.tenantsView));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Billing'),
          bottom: TabBar(
            indicatorColor: p.brand,
            labelColor: p.text,
            unselectedLabelColor: p.textMuted,
            dividerColor: p.border,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
            tabs: [
              const Tab(text: 'Invoices'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Claims'),
                    if (waiting > 0) ...[
                      const SizedBox(width: 8),
                      Badge(
                        label: Text('$waiting'),
                        backgroundColor: p.brand,
                        textColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _KeepAlive(
              child: _InvoicesTab(
                controller: _invoices,
                status: _status,
                onStatus: _setStatus,
                onTap: _onInvoiceTap,
              ),
            ),
            _KeepAlive(
              child: _ClaimsTab(
                claims: _claims,
                loading: _claimsLoading,
                error: _claimsError,
                onReload: _loadClaims,
                onMarkPaid: _markClaimPaid,
                onOpenCompany: canOpenCompany ? (c) => _openCompany(c.tenantId, c.tenantName) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps a tab's scroll position and state when the user swipes away.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ------------------------------------------------------------------ invoices

class _InvoicesTab extends StatelessWidget {
  const _InvoicesTab({
    required this.controller,
    required this.status,
    required this.onStatus,
    required this.onTap,
  });

  final PagedController<Invoice> controller;
  final String? status;
  final ValueChanged<String?> onStatus;
  final ValueChanged<Invoice> onTap;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('PENDING', 'Pending'),
    ('PAID', 'Paid'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (value, label) in _filters)
                  ChoiceChip(
                    label: Text(label),
                    selected: status == value,
                    showCheckmark: false,
                    onSelected: (_) => onStatus(value),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => Text(
                controller.loadedOnce ? invoiceCountLabel(controller.total, status) : ' ',
                style: TextStyle(fontSize: 12.5, color: p.textMuted, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => PagedListBody(
              controller: controller,
              skeleton: const ListSkeleton(rows: 6, rowHeight: 128),
              itemCount: controller.items.length,
              itemBuilder: (context, i) {
                final invoice = controller.items[i];
                return InvoiceCard(invoice: invoice, onTap: () => onTap(invoice));
              },
              emptyState: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: switch (status) {
                  'PENDING' => 'No pending invoices',
                  'PAID' => 'No paid invoices yet',
                  _ => 'No invoices yet',
                },
                message: status == null
                    ? 'Subscription invoices appear here as companies are billed.'
                    : 'Nothing matches this filter. Try All to see every invoice.',
                action: status == null ? null : 'Show all invoices',
                onAction: status == null ? null : () => onStatus(null),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- claims

class _ClaimsTab extends StatelessWidget {
  const _ClaimsTab({
    required this.claims,
    required this.loading,
    required this.error,
    required this.onReload,
    required this.onMarkPaid,
    required this.onOpenCompany,
  });

  final List<Claim>? claims;
  final bool loading;
  final Object? error;
  final Future<void> Function() onReload;
  final ValueChanged<Claim> onMarkPaid;
  final ValueChanged<Claim>? onOpenCompany;

  @override
  Widget build(BuildContext context) {
    final list = claims;
    if (list == null) {
      if (loading) return const ListSkeleton(rows: 3, rowHeight: 200);
      return ErrorState(error: error ?? 'Couldn\'t load claims.', onRetry: onReload);
    }

    final canManage = context.select<SessionController, bool>((s) => s.can(Perm.billingManage));

    return RefreshIndicator(
      onRefresh: onReload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const HelpBanner(
            'A claim is an M-Pesa confirmation code a company submitted after paying its invoice by hand. '
            'Check the code against your M-Pesa statement, then mark the invoice paid.',
            icon: Icons.fact_check_outlined,
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(
                icon: Icons.task_alt_rounded,
                title: 'No claims waiting',
                message: 'When a company submits an M-Pesa code for a manual payment, it shows up here.',
              ),
            )
          else
            for (final claim in list)
              ClaimCard(
                claim: claim,
                onMarkPaid: canManage ? () => onMarkPaid(claim) : null,
                onOpenCompany: onOpenCompany == null ? null : () => onOpenCompany!(claim),
              ),
        ],
      ),
    );
  }
}
