import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../billing/billing_screen.dart';
import 'tenant_widgets.dart';
import 'tenants_logic.dart';

/// Billing tab: recent invoices and manual M-Pesa claims waiting for a decision,
/// plus an in-place "all invoices" list.
class TenantBillingTab extends StatefulWidget {
  const TenantBillingTab({super.key, required this.tenantId, required this.load, required this.onReload, required this.refresh});

  final String tenantId;
  final DetailLoad load;
  final Future<void> Function() onReload;
  final Listenable refresh;

  @override
  State<TenantBillingTab> createState() => _TenantBillingTabState();
}

class _TenantBillingTabState extends State<TenantBillingTab> with TenantRefreshMixin {
  static const _pageSize = 50;

  List<Invoice>? _all;
  int _allTotal = 0;
  int _allPage = 0;
  bool _allHasMore = false;
  bool _loadingAll = false;
  Object? _allError;

  @override
  Listenable get refreshSignal => widget.refresh;

  @override
  void onRefreshSignal() {
    if (_all != null) _loadAll(reset: true);
  }

  Future<void> _loadAll({bool reset = false}) async {
    if (_loadingAll) return;
    final repo = context.read<AcaRepository>();
    setState(() {
      _loadingAll = true;
      _allError = null;
    });
    try {
      final page = reset ? 1 : _allPage + 1;
      final r = await repo.invoices(tenantId: widget.tenantId, page: page, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _all = reset ? r.items : mergePage(_all ?? const <Invoice>[], r.items, (i) => i.id);
        _allTotal = r.total;
        _allPage = r.page;
        _allHasMore = r.hasMore;
        _loadingAll = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _allError = e;
        _loadingAll = false;
      });
    }
  }

  Future<void> _refresh() async {
    await widget.onReload();
    if (_all != null && mounted) await _loadAll(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final load = widget.load;
    final d = load.detail;
    if (d == null) {
      if (load.error != null) {
        return RefreshableFill(onRefresh: widget.onReload, child: ErrorState(error: load.error!, onRetry: widget.onReload));
      }
      return const TabSkeleton();
    }

    final p = context.aca;
    final pending = d.claims.where((c) => c.status.toUpperCase() == 'PENDING').toList();
    final invoices = _all ?? d.recentInvoices;
    final showingAll = _all != null;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kTabPadding,
        children: [
          if (pending.isNotEmpty) ...[
            SectionHeader('M-Pesa claims waiting (${pending.length})', padding: const EdgeInsets.fromLTRB(4, 0, 4, 10)),
            AcaCard(
              tone: Tone.warning,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Column(
                children: [
                  for (var i = 0; i < pending.length; i++) ...[
                    if (i > 0) const Divider(),
                    _ClaimRow(claim: pending[i]),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BillingScreen())),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Review claims in Billing'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SectionHeader(
            showingAll ? 'All invoices ($_allTotal)' : 'Recent invoices',
            padding: EdgeInsets.fromLTRB(4, pending.isNotEmpty ? 20 : 0, 4, 10),
          ),
          if (invoices.isEmpty)
            AcaCard(
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, color: p.textMuted, size: 32),
                  const SizedBox(height: 8),
                  Text('No invoices yet', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Invoices appear here once the company is billed.',
                      textAlign: TextAlign.center, style: TextStyle(color: p.textMuted)),
                ],
              ),
            )
          else
            for (final inv in invoices)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: _InvoiceCard(invoice: inv)),
          if (_allError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                _allError is ApiException ? (_allError as ApiException).message : 'Couldn\'t load the invoices.',
                style: TextStyle(color: p.danger),
              ),
            ),
          if (!showingAll && d.invoiceCount > d.recentInvoices.length)
            OutlinedButton.icon(
              onPressed: _loadingAll ? null : () => _loadAll(reset: true),
              icon: _loadingAll
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.list_alt_rounded),
              label: Text('See all ${d.invoiceCount} invoices'),
            ),
          if (showingAll && _allHasMore)
            OutlinedButton.icon(
              onPressed: _loadingAll ? null : () => _loadAll(),
              icon: _loadingAll
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.expand_more_rounded),
              label: const Text('Load more'),
            ),
        ],
      ),
    );
  }
}

class _ClaimRow extends StatelessWidget {
  const _ClaimRow({required this.claim});
  final Claim claim;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.phone_iphone_rounded, color: p.warning, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(claim.mpesaCode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6, fontFamily: 'monospace')),
                Text('Claimed ${Fmt.ago(claim.createdAt)}', style: TextStyle(color: p.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(Fmt.kes(claim.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final i = invoice;
    final credit = i.isCredit;
    final reason = creditReason(i);
    final title = credit ? 'Goodwill credit' : '${Fmt.label(i.plan)} plan';
    final when = i.isPaid ? 'Paid ${Fmt.date(i.paidAt ?? i.createdAt)}' : 'Created ${Fmt.date(i.createdAt)}';
    final period = (i.periodStart != null && i.periodEnd != null && !credit)
        ? '${Fmt.dateShort(i.periodStart)} – ${Fmt.date(i.periodEnd)}'
        : null;
    final amountColor = credit ? p.info : p.text;

    return AcaCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: credit ? p.toneFill(Tone.info) : p.surfaceHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(credit ? Icons.card_giftcard_rounded : Icons.receipt_long_rounded,
                    size: 20, color: credit ? p.info : p.textMuted),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall)),
              const SizedBox(width: 8),
              Text(Fmt.kes(i.amount), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: amountColor)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              StatusPill(Fmt.label(i.status), tone: invoiceTone(i.status), dense: true),
              if (credit) const StatusPill('Credit', tone: Tone.info, dense: true) else StatusPill(providerLabel(i.provider), tone: Tone.neutral, dense: true),
            ],
          ),
          const SizedBox(height: 8),
          if (reason != null) Text(reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
          Text(when, style: TextStyle(color: p.textMuted, fontSize: 12.5)),
          if (period != null) Text('Covers $period', style: TextStyle(color: p.textFaint, fontSize: 12)),
        ],
      ),
    );
  }
}
