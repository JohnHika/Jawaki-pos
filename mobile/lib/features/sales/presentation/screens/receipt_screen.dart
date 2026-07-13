import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/receipt_printer_service.dart';
import '../../../../core/services/print_queue_service.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/share_format_sheet.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../providers/sales_provider.dart';

class ReceiptScreen extends ConsumerWidget {
  final String saleId;

  const ReceiptScreen({super.key, required this.saleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptAsync = ref.watch(receiptProvider(saleId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Auto-print fires once, the moment the receipt data first loads —
    // ref.listen (not a postFrameCallback in initState) because this is a
    // stateless ConsumerWidget and the receipt arrives asynchronously via
    // the provider, not at build time.
    ref.listen(receiptProvider(saleId), (previous, next) {
      if (previous?.value == null && next.value != null) {
        _autoPrintIfEnabled(next.value!);
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: Container(
          margin: const EdgeInsets.only(left: 4),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.close_rounded, size: 20),
            ),
            onPressed: () => context.go('/'),
          ),
        ),
        title: Text(
          'Receipt',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: -0.5,
            color: isDark
                ? DesignColors.darkTextPrimary
                : DesignColors.textPrimary,
          ),
        ),
        centerTitle: false,
        backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DesignColors.accent.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.share_outlined, size: 20, color: DesignColors.accent),
            ),
            tooltip: 'Share receipt',
            onPressed: () async {
              final receipt = receiptAsync.valueOrNull;
              if (receipt == null) {
                showGlassSnackBar(
                  context,
                  'Receipt is still loading — try again in a moment.',
                  icon: Icons.hourglass_empty_rounded,
                  color: DesignColors.warning,
                );
                return;
              }
              final format = await showShareFormatSheet(
                context,
                title: 'Share Receipt',
                formats: const [
                  ShareFormatOption.pdf,
                  ShareFormatOption.plainText,
                ],
              );
              if (format == null || !context.mounted) return;

              if (format == ShareFormat.plainText) {
                await ExportDocumentService.sharePlainText(
                    _buildShareText(receipt));
                return;
              }
              await _shareReceiptPdf(ref, receipt);
            },
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DesignColors.accent.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.print_outlined,
                  size: 20, color: DesignColors.accent),
            ),
            tooltip: 'Print receipt',
            onPressed: () => _printReceipt(context, receiptAsync.valueOrNull),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DesignColors.error.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.block_rounded,
                  size: 20, color: DesignColors.error),
            ),
            onPressed: () => _voidSale(context, ref),
          ),
          const SizedBox(width: 4),
        ],
      ),
      backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
      body: receiptAsync.when(
        data: (receipt) =>
            _buildReceipt(context, receipt, ref.watch(tenantIdentityProvider).logoUrl),
        loading: () => const Center(
          child: CircularProgressIndicator(color: DesignColors.accent),
        ),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Failed to load receipt',
          subtitle: 'Check your connection and try again.',
          actionLabel: 'Retry',
          iconColor: DesignColors.error,
          onAction: () => ref.refresh(receiptProvider(saleId)),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: GradientButton(
            label: 'New Sale',
            icon: Icons.add_shopping_cart_rounded,
            onPressed: () => context.go('/'),
            height: 56,
            borderRadius: 16,
          ),
        ),
      ),
    );
  }

  // Character width of the physical 58mm thermal roll (esc_pos_utils
  // PaperSize.mm58). The on-screen preview lays everything out to the exact
  // same width and monospace grid the printer uses, so what you see is what
  // prints — name on the left, amount right-aligned, ASCII rules, etc.
  static const int _receiptCols = 32;

  Widget _buildReceipt(
      BuildContext context, Map<String, dynamic> receipt, String? logoUrl) {
    final items = receipt['items'] as List? ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final lines = _renderReceiptLines(receipt, items);
    final isVoided = (receipt['status'] ?? '').toString().toUpperCase() == 'VOIDED';

    // Paper background is always light (like real thermal paper) with dark
    // ink, regardless of app theme, so the preview reads as a printout.
    const paperColor = Color(0xFFFAFAF7);
    const inkColor = Color(0xFF1A1A1A);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Center(
        child: Column(
          children: [
            // A little "Preview of printed receipt (58mm)" caption so it's
            // clear this mirrors the physical printout.
            Text(
              'PREVIEW · 58mm THERMAL',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? DesignColors.darkTextTertiary
                    : DesignColors.textTertiary,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              // ~58mm of paper: a fixed narrow column. The monospace font at
              // this size fits 32 chars, matching the printer's line width.
              width: 280,
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 22),
              decoration: BoxDecoration(
                color: paperColor,
                border: isVoided
                    ? Border.all(color: DesignColors.error, width: 2)
                    : null,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Company logo at the top of the paper, like a real
                  // branded receipt. Grayscale-friendly; hidden if none set.
                  if (logoUrl != null && logoUrl.isNotEmpty) ...[
                    Center(
                      child: Image.network(
                        logoUrl,
                        height: 48,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    lines,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.35,
                      color: inkColor,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the exact monospace text block the receipt would print as, so
  /// the on-screen preview matches the 58mm thermal output line for line.
  /// Detailed by design: per-tier item lines (e.g. "1 box @ 1,200 —
  /// 12 pcs @ 100"), a payment breakdown (split tenders + balance owed on
  /// credit), a VOIDED banner when applicable, and a warm footer.
  String _renderReceiptLines(Map<String, dynamic> receipt, List items) {
    final b = StringBuffer();
    const w = _receiptCols;

    String center(String s) {
      if (s.length >= w) return s.substring(0, w);
      final pad = (w - s.length) ~/ 2;
      return '${' ' * pad}$s';
    }

    // A left label and a right value on the same line, right-justified.
    String lr(String left, String right) {
      final maxLeft = w - right.length - 1;
      var l = left;
      if (l.length > maxLeft) l = l.substring(0, maxLeft);
      final gap = w - l.length - right.length;
      return '$l${' ' * (gap < 1 ? 1 : gap)}$right';
    }

    // Wrap a long product name across lines at the column width, indenting
    // continuation lines so it reads as one item.
    List<String> wrapName(String name, {int indent = 0}) {
      final avail = w - indent;
      if (name.length <= avail) return [' ' * indent + name];
      final out = <String>[];
      var rest = name;
      var first = true;
      while (rest.isNotEmpty) {
        final take = (first ? avail : w - 2);
        final pad = first ? indent : 2;
        if (rest.length <= take) {
          out.add(' ' * pad + rest);
          break;
        }
        // Break on the last space within the window if there is one.
        var cut = rest.substring(0, take);
        final sp = cut.lastIndexOf(' ');
        if (sp > take ~/ 2) cut = cut.substring(0, sp);
        out.add(' ' * pad + cut.trimRight());
        rest = rest.substring(cut.length).trimLeft();
        first = false;
      }
      return out;
    }

    String money(num v) => v.toStringAsFixed(2);
    final rule = '-' * w;
    final dblRule = '=' * w;

    // Header — store name + address, centered. (Logo is drawn as an image on
    // the thermal print + PDF; the text preview keeps the name prominent.)
    b.writeln(center((receipt['branchName'] ?? 'POS Store').toString().toUpperCase()));
    final addr = (receipt['branchAddress'] ?? '').toString();
    if (addr.isNotEmpty) {
      for (final l in wrapName(addr)) {
        b.writeln(center(l.trim()));
      }
    }
    final phone = (receipt['branchPhone'] ?? '').toString();
    if (phone.isNotEmpty) b.writeln(center('Tel: $phone'));
    b.writeln(rule);

    // VOIDED banner — impossible to miss.
    final isVoided = (receipt['status'] ?? '').toString().toUpperCase() == 'VOIDED';
    if (isVoided) {
      b.writeln(center('*** VOIDED SALE ***'));
      final vr = (receipt['voidReason'] ?? '').toString();
      if (vr.isNotEmpty) {
        for (final l in wrapName('Reason: $vr')) {
          b.writeln(l);
        }
      }
      b.writeln(rule);
    }

    // Receipt meta.
    final rcp = receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase();
    b.writeln('Receipt #$rcp');
    b.writeln(_formatDateTime(receipt['createdAt']));
    if (receipt['cashierName'] != null) {
      b.writeln('Served by: ${receipt['cashierName']}');
    }
    if (receipt['customerName'] != null) {
      b.writeln('Customer: ${receipt['customerName']}');
    }
    if (receipt['customerPhone'] != null) {
      b.writeln('Phone: ${receipt['customerPhone']}');
    }
    b.writeln(rule);

    // Items. Each line: the product name (wrapped), then an indented detail
    // line showing how it was sold. When sold as a multi-unit tier (box/pack
    // with quantityPerUnit > 1), also show the per-base-unit price.
    for (final item in items) {
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      final name = (item['productName'] ?? item['name'] ?? '').toString();
      final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      final total = (item['total'] as num?)?.toDouble() ?? 0;
      final unit = (item['unit'] ?? '').toString().trim();
      final perUnit = (item['quantityPerUnit'] as num?)?.toDouble() ?? 0;

      for (final l in wrapName(name)) {
        b.writeln(l);
      }

      // "  2 box @ 1,200.00" (unit label if known, else plain qty).
      final unitLabel = unit.isNotEmpty ? ' $unit' : '';
      b.writeln(lr('  $qty$unitLabel @ ${money(unitPrice)}', money(total)));

      // When a tier bundles base units, show the effective per-piece price:
      // "    (12 pcs @ 100.00 each)".
      if (unit.isNotEmpty && perUnit > 1) {
        final perPiece = unitPrice / perUnit;
        final pieces = (perUnit * qty).round();
        b.writeln('    ($pieces pcs @ ${money(perPiece)} each)');
      }
    }
    b.writeln(rule);

    // Totals.
    final subtotal = (receipt['subtotal'] as num?)?.toDouble() ?? 0;
    b.writeln(lr('Subtotal', money(subtotal)));
    final discount = (receipt['discount'] as num?)?.toDouble() ?? 0;
    if (discount > 0) {
      b.writeln(lr('Discount', '-${money(discount)}'));
    }
    final tax = (receipt['tax'] as num?)?.toDouble() ?? 0;
    if (getIt<AuthService>().showTaxOnReceipt && tax > 0) {
      b.writeln(lr('Tax', money(tax)));
    }
    final grand = (receipt['total'] as num?)?.toDouble() ?? 0;
    b.writeln(dblRule);
    b.writeln(lr('TOTAL  KES', money(grand)));
    b.writeln(dblRule);

    // Payment detail — how it was paid, in full.
    final method = (receipt['paymentMethod'] ?? 'CASH').toString().toUpperCase();
    final tenders = receipt['paymentTenders'] as List?;
    if (method == 'SPLIT' && tenders != null && tenders.isNotEmpty) {
      b.writeln('Paid by (split):');
      for (final t in tenders) {
        final m = (t['method'] ?? '').toString();
        final amt = (t['amount'] as num?)?.toDouble() ?? 0;
        b.writeln(lr('  $m', money(amt)));
      }
    } else {
      b.writeln(lr('Paid by', method));
    }
    final ref = (receipt['paymentReference'] ?? '').toString();
    if (ref.isNotEmpty && method != 'SPLIT') {
      b.writeln(lr('  Ref', ref.length > 20 ? ref.substring(0, 20) : ref));
    }

    // Balance owed (credit / split-with-credit).
    final owed = (receipt['outstandingBalance'] as num?)?.toDouble() ?? 0;
    if (owed > 0.01) {
      b.writeln(rule);
      b.writeln(lr('BALANCE OWED', money(owed)));
      if (receipt['customerName'] != null) {
        b.writeln('  on ${receipt['customerName']}\'s account');
      }
    }

    b.writeln(rule);
    // Warm footer.
    b.writeln(center('Thank you for your purchase!'));
    b.writeln(center('We look forward to'));
    b.writeln(center('serving you again.'));
    b.writeln(center('All the best!'));

    return b.toString().trimRight();
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    final dt =
        dateTime is DateTime ? dateTime : DateTime.parse(dateTime.toString());
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _buildShareText(Map<String, dynamic> receipt) {
    final items = receipt['items'] as List? ?? [];
    final buffer = StringBuffer();

    buffer.writeln(receipt['branchName'] ?? 'POS Store');
    if ((receipt['branchAddress'] as String?)?.isNotEmpty == true) {
      buffer.writeln(receipt['branchAddress']);
    }
    buffer.writeln('Receipt #${receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase()}');
    buffer.writeln(_formatDateTime(receipt['createdAt']));
    if ((receipt['status'] ?? '').toString().toUpperCase() == 'VOIDED') {
      buffer.writeln('*** VOIDED SALE ***');
      final vr = (receipt['voidReason'] ?? '').toString();
      if (vr.isNotEmpty) buffer.writeln('Reason: $vr');
    }
    buffer.writeln('---');

    for (final item in items) {
      final name = item['productName'] ?? '';
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      final unit = (item['unit'] ?? '').toString().trim();
      final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      final perUnit = (item['quantityPerUnit'] as num?)?.toDouble() ?? 0;
      final total = (item['total'] as num?)?.toStringAsFixed(2) ?? '0.00';
      final label = unit.isNotEmpty ? '$qty $unit' : '$qty';
      buffer.writeln('$name');
      buffer.writeln('  $label @ ${unitPrice.toStringAsFixed(2)} — KES $total');
      if (unit.isNotEmpty && perUnit > 1) {
        final perPiece = unitPrice / perUnit;
        buffer.writeln('  (${(perUnit * qty).round()} pcs @ ${perPiece.toStringAsFixed(2)} each)');
      }
    }

    buffer.writeln('---');
    buffer.writeln('Subtotal: KES ${((receipt['subtotal'] as num?) ?? 0).toStringAsFixed(2)}');
    final discount = (receipt['discount'] as num?) ?? 0;
    if (discount > 0) {
      buffer.writeln('Discount: -KES ${discount.toStringAsFixed(2)}');
    }
    final tax = (receipt['tax'] as num?) ?? 0;
    if (getIt<AuthService>().showTaxOnReceipt && tax > 0) {
      buffer.writeln('Tax: KES ${tax.toStringAsFixed(2)}');
    }
    buffer.writeln('Total: KES ${((receipt['total'] as num?) ?? 0).toStringAsFixed(2)}');

    final method = (receipt['paymentMethod'] ?? 'CASH').toString().toUpperCase();
    final tenders = receipt['paymentTenders'] as List?;
    if (method == 'SPLIT' && tenders != null && tenders.isNotEmpty) {
      buffer.writeln('Paid by (split):');
      for (final t in tenders) {
        buffer.writeln('  ${t['method']}: KES ${((t['amount'] as num?) ?? 0).toStringAsFixed(2)}');
      }
    } else {
      buffer.writeln('Paid by: $method');
    }
    final owed = (receipt['outstandingBalance'] as num?)?.toDouble() ?? 0;
    if (owed > 0.01) {
      buffer.writeln('Balance owed: KES ${owed.toStringAsFixed(2)}');
    }
    buffer.writeln();
    buffer.writeln('Thank you for your purchase!');
    buffer.writeln('We look forward to serving you again. All the best!');

    return buffer.toString();
  }

  Future<void> _shareReceiptPdf(
      WidgetRef ref, Map<String, dynamic> receipt) async {
    final items = receipt['items'] as List? ?? [];
    final identity = ref.read(tenantIdentityProvider);
    final logoBytes = await ExportDocumentService.fetchLogoBytes(identity.logoUrl);

    final subtotal = ((receipt['subtotal'] as num?) ?? 0).toStringAsFixed(2);
    final discount = (receipt['discount'] as num?) ?? 0;
    final tax = (receipt['tax'] as num?) ?? 0;
    final total = ((receipt['total'] as num?) ?? 0).toStringAsFixed(2);
    final showTax = getIt<AuthService>().showTaxOnReceipt && tax > 0;

    final summaryRows = <List<String>>[
      ['Subtotal', 'KES $subtotal'],
      if (discount > 0) ['Discount', '-KES ${discount.toStringAsFixed(2)}'],
      if (showTax) ['Tax', 'KES ${tax.toStringAsFixed(2)}'],
      ['Total', 'KES $total'],
    ];

    // Payment breakdown into the summary: split tenders line-by-line, else
    // the single method; plus any balance owed.
    final method = (receipt['paymentMethod'] ?? 'CASH').toString().toUpperCase();
    final tenders = receipt['paymentTenders'] as List?;
    if (method == 'SPLIT' && tenders != null && tenders.isNotEmpty) {
      for (final t in tenders) {
        summaryRows.add([
          'Paid (${t['method']})',
          'KES ${((t['amount'] as num?) ?? 0).toStringAsFixed(2)}',
        ]);
      }
    } else {
      summaryRows.add(['Payment', method]);
    }
    final owed = (receipt['outstandingBalance'] as num?)?.toDouble() ?? 0;
    if (owed > 0.01) {
      summaryRows.add(['Balance owed', 'KES ${owed.toStringAsFixed(2)}']);
    }

    // Per-item row: qty with unit label + per-unit-within-tier breakdown.
    String itemQtyLabel(Map item) {
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      final unit = (item['unit'] ?? '').toString().trim();
      final perUnit = (item['quantityPerUnit'] as num?)?.toDouble() ?? 0;
      final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      var label = unit.isNotEmpty ? '$qty $unit @ ${unitPrice.toStringAsFixed(2)}' : '$qty';
      if (unit.isNotEmpty && perUnit > 1) {
        label += ' (${(perUnit * qty).round()} pcs @ ${(unitPrice / perUnit).toStringAsFixed(2)})';
      }
      return label;
    }

    final voided = (receipt['status'] ?? '').toString().toUpperCase() == 'VOIDED';
    final bytes = await ExportDocumentService.buildPdfReport(
      title: 'Receipt #${receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase()}'
          '${voided ? '  —  VOIDED' : ''}',
      companyName: (receipt['branchName'] as String?)?.isNotEmpty == true
          ? receipt['branchName']
          : identity.companyName,
      subtitle: _formatDateTime(receipt['createdAt']) +
          (voided && (receipt['voidReason'] ?? '').toString().isNotEmpty
              ? '  ·  VOIDED: ${receipt['voidReason']}'
              : ''),
      logoBytes: logoBytes,
      sections: [
        PdfReportSection(
          heading: 'Items',
          headers: const ['Item', 'Qty / Unit', 'Total'],
          rows: [
            for (final item in items)
              [
                '${item['productName'] ?? ''}',
                itemQtyLabel(item as Map),
                'KES ${((item['total'] as num?) ?? 0).toStringAsFixed(2)}',
              ],
          ],
        ),
        PdfReportSection(
          heading: 'Summary',
          headers: const ['', ''],
          rows: summaryRows,
        ),
      ],
    );
    await ExportDocumentService.sharePdf(bytes, 'receipt_${receipt['receiptNumber'] ?? saleId}');
  }

  /// Silent counterpart to [_printReceipt] for the "auto-print after each
  /// sale" setting — no snackbars on success (a printed receipt is
  /// self-evident), and failures don't interrupt the flow since the user
  /// never explicitly asked for a print in this moment. Manual retry via
  /// the print button in the app bar is still available if this fails.
  Future<void> _autoPrintIfEnabled(Map<String, dynamic> receipt) async {
    final prefs = await SharedPreferences.getInstance();
    final autoPrint = prefs.getBool(PrinterSettingsKeys.autoPrint) ?? false;
    if (!autoPrint) return;

    final queue = getIt<PrintQueueService>();
    final isDesignated = await queue.isDesignatedPrinter();

    // A non-designated device has no Bluetooth connection of its own to
    // fall back on — if the printer isn't configured here at all, silently
    // do nothing (matches the old silent-failure behavior for auto-print).
    final printerMac =
        prefs.getString(PrinterSettingsKeys.printerMacAddress) ?? '';
    if (!isDesignated && printerMac.isEmpty) return;

    final paperWidth =
        prefs.getString(PrinterSettingsKeys.paperWidth) ?? '58mm';
    try {
      await queue.requestPrint(
        receipt: receipt,
        saleId: saleId,
        paperWidth: paperWidth,
        showTax: getIt<AuthService>().showTaxOnReceipt,
      );
    } catch (_) {
      // Silent by design — see doc comment above.
    }
  }

  Future<void> _printReceipt(
      BuildContext context, Map<String, dynamic>? receipt) async {
    if (receipt == null) {
      showGlassSnackBar(
        context,
        'Receipt is still loading — try again in a moment.',
        icon: Icons.hourglass_empty_rounded,
        color: DesignColors.warning,
      );
      return;
    }

    final queue = getIt<PrintQueueService>();
    final isDesignated = await queue.isDesignatedPrinter();

    final prefs = await SharedPreferences.getInstance();
    final printerMac =
        prefs.getString(PrinterSettingsKeys.printerMacAddress) ?? '';

    // A device that neither holds the shared printer connection nor has a
    // printer of its own configured has nothing to queue toward — send it
    // to Settings rather than silently queuing a job nobody will ever drain.
    if (!isDesignated && printerMac.isEmpty) {
      if (!context.mounted) return;
      showGlassSnackBar(
        context,
        'Set up a receipt printer in Settings to print receipts.',
        icon: Icons.print_outlined,
        color: DesignColors.info,
        actionLabel: 'Open Settings',
        onAction: () => context.push('/settings'),
      );
      return;
    }

    final paperWidth =
        prefs.getString(PrinterSettingsKeys.paperWidth) ?? '58mm';

    try {
      final printedHere = await queue.requestPrint(
        receipt: receipt,
        saleId: saleId,
        paperWidth: paperWidth,
        showTax: getIt<AuthService>().showTaxOnReceipt,
      );
      if (!context.mounted) return;
      if (printedHere) {
        showGlassSnackBar(context, 'Receipt sent to printer',
            icon: Icons.check_circle_rounded, color: DesignColors.success);
      } else {
        showGlassSnackBar(context, 'Queued for printing',
            icon: Icons.schedule_send_rounded, color: DesignColors.info);
      }
    } on PrinterUnavailableException catch (e) {
      if (context.mounted) {
        showGlassSnackBar(context, e.message,
            icon: Icons.print_disabled_rounded, color: DesignColors.error);
      }
    } catch (e) {
      if (context.mounted) {
        showGlassSnackBar(context, 'Could not print receipt: $e',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    }
  }

  /// Voids a sale — now a soft-void with a mandatory reason (kept + audited,
  /// not deleted). Prompts for the reason, voids on the backend (restores
  /// stock server-side) when online, and marks the local sale VOIDED so the
  /// receipt immediately shows the VOIDED banner + reason.
  Future<void> _voidSale(BuildContext context, WidgetRef ref) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.block_rounded, color: DesignColors.error),
        title: const Text('Void this sale?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The sale is kept and marked VOIDED (not deleted), and stock is '
              'returned. Please give a reason.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason for voiding',
                hintText: 'e.g. wrong item, customer changed mind',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep sale'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DesignColors.error),
            onPressed: () {
              final r = reasonController.text.trim();
              if (r.isEmpty) return; // reason is mandatory
              Navigator.pop(ctx, r);
            },
            child: const Text('Void sale'),
          ),
        ],
      ),
    );

    if (reason == null || !context.mounted) return;

    final db = getIt<AppDatabase>();
    final userName = getIt<AuthService>().currentUser?['name'] as String?;

    // Void on the backend first (authoritative stock restore + audit) when
    // reachable; a failure there shouldn't block the local void, since the
    // sync layer will reconcile. Best-effort.
    try {
      await getIt<ApiClient>().voidSale(saleId, reason: reason);
    } catch (_) {
      // offline / not-yet-synced sale — local void still applies below
    }

    try {
      await db.voidPendingSale(saleId, reason: reason, voidedBy: userName);
      ref.invalidate(receiptProvider(saleId));
      if (context.mounted) {
        showGlassSnackBar(
          context,
          'Sale voided',
          icon: Icons.check_circle_outline_rounded,
          color: DesignColors.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showGlassSnackBar(
          context,
          'Could not void the sale. Please try again.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    }
  }
}
