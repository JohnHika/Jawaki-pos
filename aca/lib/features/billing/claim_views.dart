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

/// A manual M-Pesa payment claim waiting for reconciliation.
class ClaimCard extends StatelessWidget {
  const ClaimCard({
    super.key,
    required this.claim,
    required this.onMarkPaid,
    this.onOpenCompany,
  });

  final Claim claim;

  /// Called after the user taps the action; null hides it (read-only roles).
  final VoidCallback? onMarkPaid;

  /// Null when the role cannot open companies.
  final VoidCallback? onOpenCompany;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final needsAction = claimNeedsAction(claim);
    final canManage = context.select<SessionController, bool>((s) => s.can(Perm.billingManage));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AcaCard(
        onTap: onOpenCompany,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    claim.tenantName ?? 'Company',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.25),
                  ),
                ),
                if (onOpenCompany != null) Icon(Icons.chevron_right_rounded, color: p.textFaint),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusPill(
                  'Invoice ${invoiceStatusLabel(claim.invoiceStatus).toLowerCase()}',
                  tone: invoiceStatusTone(claim.invoiceStatus),
                  dense: true,
                ),
                if (claim.plan != null && claim.plan!.isNotEmpty) StatusPill(Fmt.label(claim.plan), dense: true),
              ],
            ),
            const SizedBox(height: 12),
            _CodeBox(code: claim.mpesaCode),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    Fmt.kes(claim.amount),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    'Submitted ${Fmt.ago(claim.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textMuted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
            if (needsAction && canManage && onMarkPaid != null) ...[
              const SizedBox(height: 14),
              FilledButton(
                onPressed: onMarkPaid,
                child: const Text('Mark invoice paid with this code', textAlign: TextAlign.center),
              ),
            ] else if (!needsAction) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 18, color: p.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This invoice is already paid, so there is nothing left to do.',
                      style: TextStyle(color: p.textMuted, fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Big, copyable M-Pesa code so it can be matched against the statement.
class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Material(
      color: p.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => copyToClipboard(context, code, what: 'M-Pesa code copied'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('M-Pesa code', style: TextStyle(fontSize: 11.5, color: p.textMuted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          code.isEmpty ? '—' : code,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: Icon(Icons.copy_rounded, size: 20, color: p.textMuted),
                  onPressed: () => copyToClipboard(context, code, what: 'M-Pesa code copied'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
