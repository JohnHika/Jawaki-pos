import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import 'desktop_receipt_paper.dart';
import 'receipt_format.dart';
import 'receipt_thermal_text.dart';

/// The right-hand panel of the Receipts page: the picked receipt drawn as thermal
/// paper, with Print, Share and Open under it. It takes the same map the phone
/// receipt page uses, so nothing about the data changes.
class DesktopReceiptInspector extends StatefulWidget {
  const DesktopReceiptInspector({
    super.key,
    required this.receipt,
    required this.fallbackNumber,
    required this.showTax,
    required this.onClose,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.waitingToSync = false,
    this.canVoid = false,
    this.onOpen,
    this.onPrint,
    this.onShare,
    this.onVoid,
  });

  /// null while loading or when it could not be loaded.
  final Map<String, dynamic>? receipt;
  final String fallbackNumber;
  final bool showTax;
  final VoidCallback onClose;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// Saved on this computer but not yet sent to the cloud.
  final bool waitingToSync;
  final bool canVoid;
  final VoidCallback? onOpen;
  final VoidCallback? onPrint;
  final VoidCallback? onShare;
  final VoidCallback? onVoid;

  @override
  State<DesktopReceiptInspector> createState() =>
      _DesktopReceiptInspectorState();
}

class _DesktopReceiptInspectorState extends State<DesktopReceiptInspector> {
  int _columns = thermalColumns58mm;

  @override
  Widget build(BuildContext context) {
    final r = widget.receipt;
    final voided = r != null && isVoidedStatus(r['status']?.toString());
    final number = (r?['receiptNumber'] ?? widget.fallbackNumber).toString();
    final createdAt = r == null ? null : _asDate(r['createdAt']);

    return DesktopInspector(
      title: 'Receipt #$number',
      subtitle: createdAt == null ? null : formatReceiptTime(createdAt),
      onClose: widget.onClose,
      actions: [
        if (r != null && widget.canVoid && !voided && widget.onVoid != null)
          IconButton(
            tooltip: 'Void sale',
            icon: Icon(
              Icons.block_rounded,
              size: 19,
              color: receiptDangerColor(context.desktop.dark),
            ),
            onPressed: widget.onVoid,
          ),
      ],
      footer: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: 'Print (Ctrl+P)',
              child: FilledButton.icon(
                style: desktopPrimaryButton(context),
                onPressed: r == null ? null : widget.onPrint,
                icon: const Icon(Icons.print_outlined, size: 17),
                label: const Text('Print'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: desktopSecondaryButton(context),
              onPressed: r == null ? null : widget.onShare,
              icon: const Icon(Icons.ios_share_rounded, size: 17),
              label: const Text('Share'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: 'Open the full receipt',
              child: OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: widget.onOpen,
                child: const Text('Open'),
              ),
            ),
          ),
        ],
      ),
      child: r == null ? _placeholder(context) : _content(context, r, voided),
    );
  }

  Widget _placeholder(BuildContext context) {
    final p = context.desktop;
    if (widget.errorMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Couldn't load this receipt",
            style: GoogleFonts.plusJakartaSans(
              color: p.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.errorMessage!,
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (widget.onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              style: desktopSecondaryButton(context),
              onPressed: widget.onRetry,
              child: const Text('Try again'),
            ),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < 9; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.35 + (i % 4) * 0.18,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: p.hover,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _content(
    BuildContext context,
    Map<String, dynamic> r,
    bool voided,
  ) {
    final p = context.desktop;
    final total = (r['total'] as num?)?.toDouble() ?? 0;
    final method = (r['paymentMethod'] ?? 'CASH').toString();
    final text = renderThermalReceiptText(
      r,
      fallbackNumber: widget.fallbackNumber,
      showTax: widget.showTax,
      columns: _columns,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                formatMoney(total, decimals: true),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesignType.numeric(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: voided ? p.textFaint : p.text,
                ).copyWith(
                  decoration: voided ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            DesktopStatusChip(
              label: paymentMethodLabel(method),
              color: receiptMethodColor(method),
            ),
            if (voided) ...[
              const SizedBox(width: 6),
              const DesktopStatusChip(
                label: 'Voided',
                color: DesignColors.error,
              ),
            ],
          ],
        ),
        if (widget.waitingToSync) ...[
          const SizedBox(height: 12),
          const ReceiptNotice(
            message: 'Saved on this computer and waiting to sync. '
                'Keep it online.',
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Receipt preview',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ReceiptPaperWidthToggle(
              columns: _columns,
              onChanged: (value) => setState(() => _columns = value),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(child: DesktopReceiptPaper(text: text, columns: _columns)),
      ],
    );
  }
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString())?.toLocal();
}

/// A slim amber line for a state worth knowing about (waiting to sync).
class ReceiptNotice extends StatelessWidget {
  const ReceiptNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: p.dark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_upload_outlined, size: 17, color: p.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
