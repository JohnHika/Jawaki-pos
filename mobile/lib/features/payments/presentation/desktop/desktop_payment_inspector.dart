import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../../sales/presentation/receipts_desktop/receipt_format.dart';
import 'desktop_payments_view.dart';

/// The right-hand panel of the Payments page for one payment: the amount, how
/// it was paid and its reference. A payment the shop typed in (an M-Pesa or bank
/// code) that is not yet checked gets a Match button that opens the statement
/// check.
class DesktopPaymentInspector extends StatelessWidget {
  const DesktopPaymentInspector({
    super.key,
    required this.payment,
    required this.onClose,
    this.onOpenReceipt,
    this.onMatch,
  });

  final DesktopPaymentRow payment;
  final VoidCallback onClose;
  final VoidCallback? onOpenReceipt;

  /// Open the statement check (M-Pesa / bank match). null hides the button.
  final VoidCallback? onMatch;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final r = payment;
    final ref = r.reference ?? '';

    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 104,
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: value),
              ),
            ],
          ),
        );
    Widget line() => Divider(height: 1, color: p.border);

    return DesktopInspector(
      title: 'Receipt #${r.receiptNumber}',
      subtitle: formatReceiptTime(r.at),
      onClose: onClose,
      footer: Row(
        children: [
          if (r.unmatched && onMatch != null) ...[
            Expanded(
              child: Tooltip(
                message: 'Check this code against your statement',
                child: FilledButton.icon(
                  style: desktopPrimaryButton(context),
                  onPressed: onMatch,
                  icon: const Icon(Icons.fact_check_outlined, size: 17),
                  label: const Text('Match'),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: OutlinedButton.icon(
              style: desktopSecondaryButton(context),
              onPressed: onOpenReceipt,
              icon: const Icon(Icons.receipt_long_outlined, size: 17),
              label: const Text('Open receipt'),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  formatMoney(r.amount, decimals: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignType.numeric(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
              ),
              if (r.unmatched)
                const DesktopStatusChip(
                  label: 'Unmatched',
                  color: DesignColors.warning,
                )
              else if (r.recorded)
                const DesktopStatusChip(
                  label: 'Checked',
                  color: DesignColors.success,
                )
              else
                const DesktopStatusChip(
                  label: 'Confirmed',
                  color: DesignColors.success,
                ),
            ],
          ),
          const SizedBox(height: 14),
          line(),
          row(
            'Paid by',
            DesktopStatusChip(
              label: paymentMethodLabel(r.method),
              color: receiptMethodColor(r.method),
            ),
          ),
          for (final t in r.tenders)
            row(
              '   ${paymentMethodLabel(t.method)}',
              DesktopCellText(formatMoney(t.amount, decimals: true),
                  numeric: true),
            ),
          if (ref.isNotEmpty)
            row(
              'Reference',
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: DesktopCellText(ref, strong: true)),
                  IconButton(
                    tooltip: 'Copy reference',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: ref));
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(content: Text('Reference copied')),
                      );
                    },
                  ),
                ],
              ),
            ),
          if ((r.recordedBy ?? '').isNotEmpty)
            row('Recorded by', DesktopCellText(r.recordedBy!)),
          line(),
          if (r.unmatched) ...[
            const SizedBox(height: 14),
            Text(
              'You typed this ${r.methodKey.contains('BANK') ? 'bank' : 'M-Pesa'} '
              'code in at the till. Counterbase cannot see your M-Pesa or '
              'bank account, so it is not confirmed until you match it to '
              'your statement.',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ] else if (r.recorded) ...[
            const SizedBox(height: 6),
            row(
              'Checked by',
              DesktopCellText(
                [
                  if ((r.checkedBy ?? '').isNotEmpty) r.checkedBy!,
                  if (r.checkedAt != null) formatReceiptTime(r.checkedAt!),
                ].join(', '),
              ),
            ),
            if ((r.checkNote ?? '').isNotEmpty)
              row('Note', DesktopCellText(r.checkNote!)),
          ],
        ],
      ),
    );
  }
}
