import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../state/session.dart';
import 'billing_logic.dart';
import 'sheet_parts.dart';

/// What the user chose in the invoice detail sheet.
enum InvoiceSheetAction { markPaid, openCompany }

/// One invoice in the Invoices list.
class InvoiceCard extends StatelessWidget {
  const InvoiceCard({super.key, required this.invoice, required this.onTap});

  final Invoice invoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final credit = invoice.isCredit;
    final reference = invoiceReferenceText(invoice);
    final period = credit ? null : periodLabel(invoice.periodStart, invoice.periodEnd);
    final amountColor = credit ? p.success : p.text;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AcaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    invoice.tenantName ?? 'Company',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.25),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  Fmt.kes(invoice.amount),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: amountColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(invoiceStatusLabel(invoice.status), tone: invoiceStatusTone(invoice.status), dense: true),
                if (credit)
                  const StatusPill('Credit', tone: Tone.success, icon: Icons.card_giftcard_rounded, dense: true)
                else if (invoice.plan.isNotEmpty)
                  StatusPill(Fmt.label(invoice.plan), dense: true),
              ],
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                if (period != null) MetaLine(Icons.date_range_rounded, period),
                if (credit)
                  MetaLine(
                    Icons.notes_rounded,
                    reference == null ? providerLabel(invoice.provider) : 'Reason: $reference',
                    maxLines: 2,
                  )
                else
                  MetaLine(
                    Icons.account_balance_wallet_outlined,
                    reference == null
                        ? providerLabel(invoice.provider)
                        : '${providerLabel(invoice.provider)} · $reference',
                  ),
                MetaLine(Icons.schedule_rounded, invoiceTimelineLabel(invoice)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Full detail for one invoice. Returns what the user asked for, if anything;
/// the caller performs it (so the confirm flow runs on a live context).
Future<InvoiceSheetAction?> showInvoiceSheet(BuildContext context, Invoice invoice) {
  return showDetailSheet<InvoiceSheetAction>(
    context,
    builder: (ctx) => _InvoiceSheet(invoice: invoice),
  );
}

class _InvoiceSheet extends StatelessWidget {
  const _InvoiceSheet({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final session = context.watch<SessionController>();
    final canManage = session.can(Perm.billingManage);
    final canOpenCompany = session.can(Perm.tenantsView) && invoice.tenantId.isNotEmpty;
    final credit = invoice.isCredit;
    final reference = invoiceReferenceText(invoice);
    final markable = invoiceCanBeMarkedPaid(invoice);

    return DetailSheetBody(
      children: [
        Text(invoice.tenantName ?? 'Company', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          Fmt.kes(invoice.amount),
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: credit ? p.success : p.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            StatusPill(invoiceStatusLabel(invoice.status), tone: invoiceStatusTone(invoice.status)),
            if (credit) const StatusPill('Credit', tone: Tone.success, icon: Icons.card_giftcard_rounded),
          ],
        ),
        if (invoice.status == 'PENDING_CONFIRMATION') ...[
          const SizedBox(height: 14),
          const HelpBanner(
            'The company submitted an M-Pesa code for this invoice. Check it on the Claims tab and mark it paid once the money has arrived.',
          ),
        ],
        const SizedBox(height: 8),
        const SheetSectionTitle('Invoice'),
        DetailRow('Plan', credit ? 'Goodwill credit' : Fmt.label(invoice.plan)),
        const DetailDivider(),
        if (!credit) ...[
          DetailRow('Billing period', periodLabel(invoice.periodStart, invoice.periodEnd, withYear: true)),
          const DetailDivider(),
        ],
        DetailRow('Payment method', providerLabel(invoice.provider)),
        const DetailDivider(),
        DetailRow(
          credit ? 'Reason' : 'Reference',
          reference,
          copyText: reference,
          copyLabel: credit ? 'Reason copied' : 'Reference copied',
          mono: !credit,
        ),
        const SheetSectionTitle('Timeline'),
        DetailRow('Created', invoice.createdAt == null ? null : '${Fmt.dateTime(invoice.createdAt)}\n${Fmt.ago(invoice.createdAt)}'),
        const DetailDivider(),
        DetailRow(
          'Paid',
          invoice.paidAt == null ? 'Not paid yet' : '${Fmt.dateTime(invoice.paidAt)}\n${Fmt.ago(invoice.paidAt)}',
        ),
        const DetailDivider(),
        DetailRow(
          'Invoice ID',
          invoice.id,
          copyText: invoice.id,
          copyLabel: 'Invoice ID copied',
          mono: true,
          muted: true,
        ),
        const SizedBox(height: 20),
        if (markable && canManage) ...[
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, InvoiceSheetAction.markPaid),
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: const Text('Mark as paid'),
          ),
          const SizedBox(height: 10),
        ],
        if (canOpenCompany)
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, InvoiceSheetAction.openCompany),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Open company'),
          ),
      ],
    );
  }
}
