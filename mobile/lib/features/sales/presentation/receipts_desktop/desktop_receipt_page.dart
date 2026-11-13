import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import 'desktop_receipt_inspector.dart' show ReceiptNotice;
import 'desktop_receipt_paper.dart';
import 'receipt_format.dart';
import 'receipt_thermal_text.dart';

/// One receipt as a document on a computer: a centred page no wider than 720px
/// with the thermal paper on the left and the sale's facts beside it. Used by
/// the `/receipt/:id` route inside the desktop shell.
class DesktopReceiptPage extends StatefulWidget {
  const DesktopReceiptPage({
    super.key,
    required this.receipt,
    required this.fallbackNumber,
    required this.showTax,
    required this.onClose,
    this.loading = false,
    this.errorTitle,
    this.errorMessage,
    this.onRetry,
    this.waitingToSync = false,
    this.canVoid = false,
    this.onPrint,
    this.onPrintOnComputer,
    this.onShare,
    this.onVoid,
    this.onNewSale,
  });

  final Map<String, dynamic>? receipt;
  final String fallbackNumber;
  final bool showTax;

  /// Back to the receipts list (or the till).
  final VoidCallback onClose;
  final bool loading;
  final String? errorTitle;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final bool waitingToSync;
  final bool canVoid;
  final VoidCallback? onPrint;
  final VoidCallback? onPrintOnComputer;
  final VoidCallback? onShare;
  final VoidCallback? onVoid;

  /// null hides the button (a role that cannot sell).
  final VoidCallback? onNewSale;

  @override
  State<DesktopReceiptPage> createState() => _DesktopReceiptPageState();
}

class _DesktopReceiptPageState extends State<DesktopReceiptPage> {
  int _columns = thermalColumns58mm;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final r = w.receipt;
    final voided = r != null && isVoidedStatus(r['status']?.toString());
    final number = (r?['receiptNumber'] ?? w.fallbackNumber).toString();

    return CallbackShortcuts(
      bindings: {
        if (r != null && w.onPrint != null)
          const SingleActivator(LogicalKeyboardKey.keyP, control: true):
              w.onPrint!,
        const SingleActivator(LogicalKeyboardKey.escape): w.onClose,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopContent(
              maxWidth: 720 + 2 * DesktopTokens.gutter,
              child: DesktopPageHeader(
                title: 'Receipt #$number',
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
                leading: IconButton(
                  tooltip: 'Back (Esc)',
                  onPressed: w.onClose,
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                ),
                actions: [
                  if (r != null && w.canVoid && !voided && w.onVoid != null)
                    OutlinedButton.icon(
                      style: desktopSecondaryButton(context).copyWith(
                        foregroundColor: WidgetStatePropertyAll(
                          receiptDangerColor(context.desktop.dark),
                        ),
                      ),
                      onPressed: w.onVoid,
                      icon: const Icon(Icons.block_rounded, size: 17),
                      label: const Text('Void sale'),
                    ),
                  OutlinedButton.icon(
                    style: desktopSecondaryButton(context),
                    onPressed: r == null ? null : w.onShare,
                    icon: const Icon(Icons.ios_share_rounded, size: 17),
                    label: const Text('Share'),
                  ),
                  Tooltip(
                    message: 'Print (Ctrl+P)',
                    child: OutlinedButton.icon(
                      style: desktopSecondaryButton(context),
                      onPressed: r == null ? null : w.onPrint,
                      icon: const Icon(Icons.print_outlined, size: 17),
                      label: const Text('Print'),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: desktopSecondaryButton(context),
                    onPressed: r == null ? null : w.onPrintOnComputer,
                    icon: const Icon(Icons.desktop_windows_outlined, size: 17),
                    label: const Text('Print on this computer'),
                  ),
                  if (w.onNewSale != null)
                    FilledButton.icon(
                      style: desktopPrimaryButton(context),
                      onPressed: w.onNewSale,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New sale'),
                    ),
                ],
              ),
            ),
            Expanded(child: _body(context, r, voided)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic>? r, bool voided) {
    final w = widget;
    if (r == null) {
      if (w.errorMessage != null) {
        return DesktopEmptyState(
          icon: Icons.error_outline_rounded,
          title: w.errorTitle ?? "Couldn't load this receipt",
          message: w.errorMessage,
          action: w.onRetry == null
              ? null
              : OutlinedButton(
                  style: desktopSecondaryButton(context),
                  onPressed: w.onRetry,
                  child: const Text('Try again'),
                ),
        );
      }
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    final text = renderThermalReceiptText(
      r,
      fallbackNumber: w.fallbackNumber,
      showTax: w.showTax,
      columns: _columns,
    );
    return SingleChildScrollView(
      child: DesktopContent(
        maxWidth: 720 + 2 * DesktopTokens.gutter,
        padding: const EdgeInsets.fromLTRB(
          DesktopTokens.gutter,
          4,
          DesktopTokens.gutter,
          DesktopTokens.gutter,
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final stacked = box.maxWidth < 560;
            final paper = Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: ReceiptPaperWidthToggle(
                    columns: _columns,
                    onChanged: (v) => setState(() => _columns = v),
                  ),
                ),
                const SizedBox(height: 10),
                DesktopReceiptPaper(text: text, columns: _columns),
              ],
            );
            final facts = _Facts(receipt: r, voided: voided);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (w.waitingToSync) ...[
                  const ReceiptNotice(
                    message: 'Saved on this computer and waiting to sync. '
                        'Keep it online.',
                  ),
                  const SizedBox(height: 12),
                ],
                if (stacked) ...[
                  facts,
                  const SizedBox(height: 16),
                  paper,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: facts),
                      const SizedBox(width: 24),
                      paper,
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The sale's facts, as rows of a document: who, when, how it was paid.
class _Facts extends StatelessWidget {
  const _Facts({required this.receipt, required this.voided});

  final Map<String, dynamic> receipt;
  final bool voided;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final r = receipt;
    final total = (r['total'] as num?)?.toDouble() ?? 0;
    final method = (r['paymentMethod'] ?? 'CASH').toString();
    final items = r['items'] as List? ?? const [];
    final created = r['createdAt'] == null
        ? null
        : (r['createdAt'] is DateTime
            ? r['createdAt'] as DateTime
            : DateTime.tryParse(r['createdAt'].toString())?.toLocal());
    final tenders = r['paymentTenders'] as List?;
    final credit = (r['creditAmountAtSale'] as num?)?.toDouble() ?? 0;

    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 112,
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
                  child: Align(alignment: Alignment.centerLeft, child: value)),
            ],
          ),
        );
    Widget line() => Divider(height: 1, color: p.border);

    return DesktopPanel(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    formatMoney(total, decimals: true),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignType.numeric(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: voided ? p.textFaint : p.text,
                    ).copyWith(
                      decoration: voided ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (voided)
                  const DesktopStatusChip(
                    label: 'Voided',
                    color: DesignColors.error,
                  )
                else
                  const DesktopStatusChip(
                    label: 'Complete',
                    color: DesignColors.success,
                  ),
              ],
            ),
          ),
          line(),
          row(
            'Paid by',
            DesktopStatusChip(
              label: paymentMethodLabel(method),
              color: receiptMethodColor(method),
            ),
          ),
          if (tenders != null &&
              tenders.isNotEmpty &&
              method.toUpperCase() == 'SPLIT')
            for (final t in tenders)
              row(
                '  ${paymentMethodLabel((t['method'] ?? '').toString())}',
                DesktopCellText(
                  formatMoney((t['amount'] as num?) ?? 0, decimals: true),
                  numeric: true,
                ),
              ),
          if (credit > 0.01)
            row(
              'On account',
              DesktopCellText(formatMoney(credit, decimals: true),
                  numeric: true),
            ),
          line(),
          row(
              'Date',
              DesktopCellText(
                  created == null ? '—' : formatReceiptTime(created))),
          row(
            'Customer',
            DesktopCellText(
              (r['customerName']?.toString().trim().isNotEmpty ?? false)
                  ? r['customerName'].toString()
                  : r['linkedCustomerDetailsHidden'] == true
                      ? 'Customer details hidden'
                      : r['hasCustomer'] == true
                          ? 'Customer unavailable'
                          : 'Walk-in',
            ),
          ),
          if (r['customerPhone'] != null)
            row('Phone', DesktopCellText(r['customerPhone'].toString())),
          row('Served by',
              DesktopCellText((r['cashierName'] ?? '—').toString())),
          row('Items', DesktopCellText('${items.length}', numeric: true)),
          if (voided && (r['voidReason'] ?? '').toString().isNotEmpty) ...[
            line(),
            row('Void reason', DesktopCellText(r['voidReason'].toString())),
          ],
        ],
      ),
    );
  }
}
