import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/receipt_printer_service.dart';
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
            onPressed: () async {
              final confirmed = await showConfirmDialog(
                context,
                title: 'Void Sale',
                message: 'Are you sure you want to void this sale? This cannot be undone.',
                confirmLabel: 'Void Sale',
                cancelLabel: 'Keep Sale',
                confirmColor: DesignColors.error,
              );
              if (!confirmed) return;

              try {
                final db = getIt<AppDatabase>();
                await db.customStatement(
                  'DELETE FROM pending_sales WHERE id = ?',
                  [saleId],
                );
                await db.customStatement(
                  'DELETE FROM pending_sale_items WHERE sale_id = ?',
                  [saleId],
                );

                if (context.mounted) {
                  showGlassSnackBar(
                    context,
                    'Sale voided successfully',
                    icon: Icons.check_circle_outline_rounded,
                    color: DesignColors.success,
                  );
                  context.go('/');
                }
              } catch (e) {
                if (context.mounted) {
                  showGlassSnackBar(
                    context,
                    'Failed to void sale: $e',
                    icon: Icons.error_outline_rounded,
                    color: DesignColors.error,
                  );
                }
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
      body: receiptAsync.when(
        data: (receipt) => _buildReceipt(context, receipt),
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

  Widget _buildReceipt(BuildContext context, Map<String, dynamic> receipt) {
    final items = receipt['items'] as List? ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final lines = _renderReceiptLines(receipt, items);

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
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                lines,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.35,
                  color: inkColor,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the exact monospace text block the receipt would print as, so
  /// the on-screen preview matches the 58mm thermal output line for line.
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

    final rule = '-' * w;

    // Header — store name + address, centered.
    b.writeln(center((receipt['branchName'] ?? 'POS Store').toString().toUpperCase()));
    final addr = (receipt['branchAddress'] ?? '').toString();
    if (addr.isNotEmpty) b.writeln(center(addr));
    b.writeln(rule);

    // Receipt meta.
    final rcp = receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase();
    b.writeln('Receipt #$rcp');
    b.writeln(_formatDateTime(receipt['createdAt']));
    if (receipt['cashierName'] != null) {
      b.writeln('Cashier: ${receipt['cashierName']}');
    }
    if (receipt['customerName'] != null) {
      b.writeln('Customer: ${receipt['customerName']}');
    }
    if (receipt['customerPhone'] != null) {
      b.writeln('Phone: ${receipt['customerPhone']}');
    }
    b.writeln(rule);

    // Items — "qty x name" on its own line, then the line total right-aligned
    // beneath it, matching how narrow thermal receipts wrap long names.
    for (final item in items) {
      final qty = item['quantity'];
      final name = (item['productName'] ?? item['name'] ?? '').toString();
      final unit = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      final total = (item['total'] as num?)?.toDouble() ?? 0;
      b.writeln('$qty x $name');
      b.writeln(lr('  @ ${unit.toStringAsFixed(2)}', total.toStringAsFixed(2)));
    }
    b.writeln(rule);

    // Totals.
    final subtotal = (receipt['subtotal'] as num?)?.toDouble() ?? 0;
    b.writeln(lr('Subtotal', subtotal.toStringAsFixed(2)));
    final discount = (receipt['discount'] as num?)?.toDouble() ?? 0;
    if (discount > 0) {
      b.writeln(lr('Discount', '-${discount.toStringAsFixed(2)}'));
    }
    final tax = (receipt['tax'] as num?)?.toDouble() ?? 0;
    if (getIt<AuthService>().showTaxOnReceipt && tax > 0) {
      b.writeln(lr('Tax', tax.toStringAsFixed(2)));
    }
    final grand = (receipt['total'] as num?)?.toDouble() ?? 0;
    b.writeln(rule);
    b.writeln(lr('TOTAL  KES', grand.toStringAsFixed(2)));
    b.writeln(lr('Payment', (receipt['paymentMethod'] ?? 'CASH').toString()));
    b.writeln(rule);
    b.writeln(center('Thank you for your purchase!'));

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
    buffer.writeln('---');

    for (final item in items) {
      final name = item['productName'] ?? '';
      final qty = item['quantity'];
      final total = (item['total'] as num?)?.toStringAsFixed(2) ?? '0.00';
      buffer.writeln('$qty x $name — KES $total');
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
    buffer.writeln('Payment: ${receipt['paymentMethod'] ?? 'CASH'}');
    buffer.writeln();
    buffer.writeln('Thank you for your purchase!');

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
      ['Payment', '${receipt['paymentMethod'] ?? 'CASH'}'],
    ];

    final bytes = await ExportDocumentService.buildPdfReport(
      title: 'Receipt #${receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase()}',
      companyName: (receipt['branchName'] as String?)?.isNotEmpty == true
          ? receipt['branchName']
          : identity.companyName,
      subtitle: _formatDateTime(receipt['createdAt']),
      logoBytes: logoBytes,
      sections: [
        PdfReportSection(
          heading: 'Items',
          headers: const ['Item', 'Qty', 'Total'],
          rows: [
            for (final item in items)
              [
                '${item['productName'] ?? ''}',
                '${item['quantity']}',
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

    final printerMac =
        prefs.getString(PrinterSettingsKeys.printerMacAddress) ?? '';
    if (printerMac.isEmpty) return;

    final printer = getIt<ReceiptPrinterService>();
    try {
      final connected = await printer.isConnected;
      if (!connected && !(await printer.connect(printerMac))) return;

      final paperWidth =
          prefs.getString(PrinterSettingsKeys.paperWidth) ?? '58mm';
      await printer.printReceipt(
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

    final prefs = await SharedPreferences.getInstance();
    final printerMac =
        prefs.getString(PrinterSettingsKeys.printerMacAddress) ?? '';
    if (printerMac.isEmpty) {
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

    final printer = getIt<ReceiptPrinterService>();
    final connected = await printer.isConnected;
    if (!connected) {
      final reconnected = await printer.connect(printerMac);
      if (!reconnected) {
        if (!context.mounted) return;
        showGlassSnackBar(
          context,
          'Could not reach the printer — check it\'s on and in range.',
          icon: Icons.print_disabled_rounded,
          color: DesignColors.error,
        );
        return;
      }
    }

    final paperWidth =
        prefs.getString(PrinterSettingsKeys.paperWidth) ?? '58mm';

    try {
      await printer.printReceipt(
        receipt: receipt,
        saleId: saleId,
        paperWidth: paperWidth,
        showTax: getIt<AuthService>().showTaxOnReceipt,
      );
      if (context.mounted) {
        showGlassSnackBar(context, 'Receipt sent to printer',
            icon: Icons.check_circle_rounded, color: DesignColors.success);
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
}
