import 'dart:typed_data';

import '../../domain/recorded_payment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:dio/dio.dart';
import '../../../../core/services/haptic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/receipt_printer_service.dart';
import '../../../../core/services/print_queue_service.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/share_format_sheet.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/receipt_printer.dart';
import '../../../../core/widgets/workspace_image.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/utils/load_error.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../providers/sales_provider.dart';
import '../receipts_desktop/desktop_receipt_page.dart';
import '../receipts_desktop/receipt_thermal_text.dart';

typedef ReceiptPdfBuilder = Future<Uint8List> Function(
  WidgetRef ref,
  String saleId,
  Map<String, dynamic> receipt,
);
typedef ReceiptPdfShareDispatcher = Future<void> Function(
  Uint8List bytes,
  String fileName,
);

final receiptPdfBuilderProvider = Provider<ReceiptPdfBuilder>((ref) =>
    (widgetRef, saleId, receipt) =>
        ReceiptScreen(saleId: saleId)._buildReceiptPdf(widgetRef, receipt));
final receiptPdfShareDispatcherProvider = Provider<ReceiptPdfShareDispatcher>(
  (ref) => ExportDocumentService.sharePdf,
);

class ReceiptScreen extends ConsumerWidget {
  final String saleId;

  /// Play the success celebration (tick, ripples, confetti). Only true right
  /// after a sale is completed — never when re-opening an old receipt.
  final bool celebrate;

  const ReceiptScreen(
      {super.key, required this.saleId, this.celebrate = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptAsync = ref.watch(receiptProvider(saleId));
    final permissions = ref.watch(permissionsProvider);
    final canViewCustomerDetails = permissions.canSeeCustomers;
    final visibleReceiptAsync = receiptAsync.whenData(
      (receipt) => receiptForCustomerVisibility(
        receipt,
        canViewCustomerDetails: canViewCustomerDetails,
      ),
    );
    final canMakeSales = permissions.canMakeSales;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Auto-print fires once, the moment the receipt data first loads —
    // ref.listen (not a postFrameCallback in initState) because this is a
    // stateless ConsumerWidget and the receipt arrives asynchronously via
    // the provider, not at build time.
    ref.listen(receiptProvider(saleId), (previous, next) {
      final receipt = next.valueOrNull;
      if (previous?.valueOrNull == null && receipt != null) {
        if (celebrate) HapticService().medium();
        _autoPrintIfEnabled(receiptForCustomerVisibility(
          receipt,
          canViewCustomerDetails: canViewCustomerDetails,
        ));
      }
    });

    // On a computer the receipt is a centred document, not a phone page.
    if (context.inDesktopShell) {
      final receipt = visibleReceiptAsync.valueOrNull;
      final error = receipt == null ? visibleReceiptAsync.error : null;
      final missingHere = error is StateError &&
          getIt<AuthService>().isLocalWorkspace &&
          error.message == 'This receipt is not saved on this device.';
      return DesktopReceiptPage(
        receipt: receipt,
        fallbackNumber: saleId.substring(0, 8).toUpperCase(),
        showTax: getIt<AuthService>().showTaxOnReceipt,
        onClose: () =>
            context.go(celebrate && canMakeSales ? '/' : '/receipts'),
        errorTitle: missingHere ? 'Receipt not found on this computer' : null,
        errorMessage: error == null
            ? null
            : error is StateError
                ? error.message.toString()
                : loadErrorSubtitle(error),
        onRetry:
            error == null || isPermissionDenied(error) || error is StateError
                ? null
                : () => ref.refresh(receiptProvider(saleId)),
        waitingToSync: receipt != null &&
            !getIt<AuthService>().isLocalWorkspace &&
            receipt['isSynced'] == false,
        canVoid: permissions.canVoidSales,
        onPrint: () => printReceipt(context, ref, receipt),
        onPrintOnComputer: () => _printReceiptOnComputer(context, ref, receipt),
        onShare: () => shareReceipt(context, ref, receipt),
        onVoid: receipt == null ? null : () => voidSale(context, ref, receipt),
        onNewSale: canMakeSales ? () => context.go('/') : null,
      );
    }

    Future<void> onShare() =>
        shareReceipt(context, ref, visibleReceiptAsync.valueOrNull);

    return Scaffold(
      appBar: AppBar(
        leading: Container(
          margin: const EdgeInsets.only(left: DesignSpacing.xs),
          child: IconButton(
            tooltip: 'Close receipt',
            icon: Container(
              padding: const EdgeInsets.all(DesignSpacing.sm),
              decoration: BoxDecoration(
                color: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(DesignSpacing.md - 2),
              ),
              child: const Icon(Icons.close_rounded, size: 20),
            ),
            onPressed: () => context.go(canMakeSales ? '/' : '/receipts'),
          ),
        ),
        title: Text(
          'Receipt',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: DesignSpacing.xl,
            letterSpacing: -0.5,
            color: isDark
                ? DesignColors.darkTextPrimary
                : DesignColors.textPrimary,
          ),
        ),
        centerTitle: false,
        backgroundColor:
            isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (permissions.canVoidSales &&
              visibleReceiptAsync.hasValue &&
              (visibleReceiptAsync.valueOrNull?['status'] ?? '')
                      .toString()
                      .toUpperCase() !=
                  'VOIDED')
            IconButton(
              tooltip: 'Void sale',
              icon: Container(
                padding: const EdgeInsets.all(DesignSpacing.sm),
                decoration: BoxDecoration(
                  color: DesignColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(DesignSpacing.md - 2),
                ),
                child: const Icon(Icons.block_rounded,
                    size: 20, color: DesignColors.error),
              ),
              onPressed: () => voidSale(
                context,
                ref,
                visibleReceiptAsync.valueOrNull!,
              ),
            ),
          const SizedBox(width: DesignSpacing.xs),
        ],
      ),
      backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
      body: visibleReceiptAsync.when(
        data: (receipt) => Column(
          children: [
            if (!getIt<AuthService>().isLocalWorkspace &&
                receipt['isSynced'] == false)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(
                  DesignSpacing.lg,
                  DesignSpacing.sm,
                  DesignSpacing.lg,
                  0,
                ),
                padding: const EdgeInsets.all(DesignSpacing.md),
                decoration: BoxDecoration(
                  color: DesignColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  border: Border.all(
                    color: DesignColors.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cloud_upload_outlined,
                        color: DesignColors.warning),
                    SizedBox(width: DesignSpacing.sm),
                    Expanded(
                      child: Text(
                        'Sale saved on this device and waiting to sync. Keep this device online.',
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _buildReceipt(
                  context, receipt, ref.watch(tenantIdentityProvider).logoUrl),
            ),
          ],
        ),
        // The machine sits on "Processing" while the receipt loads, then
        // starts printing the moment the data lands.
        loading: () => ReceiptPrinterView(
          key: const ValueKey('receipt-printer'),
          ready: false,
          celebrate: celebrate,
          summaryTitle: 'Receipt',
          summarySubtitle: 'Loading…',
          summaryTotal: '',
          paper: null,
        ),
        error: (e, _) {
          final isMissingLocalReceipt = getIt<AuthService>().isLocalWorkspace &&
              e is StateError &&
              e.message == 'This receipt is not saved on this device.';
          return EmptyState(
            icon: Icons.error_outline_rounded,
            title: isMissingLocalReceipt
                ? 'Receipt not found on this device'
                : 'Failed to load receipt',
            subtitle:
                e is StateError ? e.message.toString() : loadErrorSubtitle(e),
            actionLabel:
                isPermissionDenied(e) || e is StateError ? null : 'Retry',
            iconColor: DesignColors.error,
            onAction: isPermissionDenied(e) || e is StateError
                ? null
                : () => ref.refresh(receiptProvider(saleId)),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.sm,
              DesignSpacing.lg, DesignSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ReceiptActionButton(
                      icon: Icons.print_outlined,
                      label: 'Print',
                      onPressed: () => printReceipt(
                        context,
                        ref,
                        visibleReceiptAsync.valueOrNull,
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignSpacing.md),
                  Expanded(
                    child: _ReceiptActionButton(
                      icon: Icons.ios_share_rounded,
                      label: 'Share',
                      onPressed: onShare,
                    ),
                  ),
                ],
              ),
              if (canMakeSales) ...[
                const SizedBox(height: DesignSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: () => context.go('/'),
                    style: FilledButton.styleFrom(
                      backgroundColor: DesignColors.accent,
                      foregroundColor: DesignColors.textPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusLg),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    child: const Text('New sale'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Asks PDF or plain text, then shares the receipt. Used by the phone
  /// receipt page and the desktop receipts page.
  Future<void> shareReceipt(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? receipt,
  ) async {
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
    final visibleReceipt = receiptForCustomerVisibility(
      receipt,
      canViewCustomerDetails: ref.read(permissionsProvider).canSeeCustomers,
    );

    if (format == ShareFormat.plainText) {
      await ExportDocumentService.sharePlainText(
          _buildShareText(visibleReceipt));
      return;
    }
    await _shareReceiptPdf(ref, visibleReceipt);
  }

  // Character width of the physical 58mm thermal roll (esc_pos_utils
  // PaperSize.mm58). The on-screen preview lays everything out to the exact
  // same width and monospace grid the printer uses, so what you see is what
  // prints — name on the left, amount right-aligned, ASCII rules, etc.
  static const int _receiptCols = 32;

  Widget _buildReceipt(
      BuildContext context, Map<String, dynamic> receipt, String? logoUrl) {
    final items = receipt['items'] as List? ?? [];
    final lines = _renderReceiptLines(receipt, items);
    final isVoided =
        (receipt['status'] ?? '').toString().toUpperCase() == 'VOIDED';
    final rcp =
        receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase();
    final total = (receipt['total'] as num?)?.toDouble() ?? 0;
    final itemCount = items.length;

    return ReceiptPrinterView(
      key: const ValueKey('receipt-printer'),
      ready: true,
      celebrate: celebrate && !isVoided,
      voided: isVoided,
      completeLabel: isVoided ? 'Sale voided' : 'Sale complete',
      logo: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: DesignColors.accent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.receipt_long_rounded,
            size: 16, color: Colors.white),
      ),
      summaryTitle: itemCount == 1 ? '1 item' : '$itemCount items',
      summarySubtitle: 'Receipt #$rcp',
      summaryTotal: 'KES ${total.toStringAsFixed(2)}',
      // ~58mm of paper: the monospace font at this size fits the printer's
      // 32 columns, so what you see is what prints.
      paper: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Company logo at the top of the paper, like a real branded
          // receipt. Hidden if none is set.
          if (logoUrl != null && logoUrl.isNotEmpty) ...[
            Center(
              child: WorkspaceImage(
                source: logoUrl,
                height: DesignSpacing.xxl + 24,
                fit: BoxFit.contain,
                placeholder: const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: DesignSpacing.md - 2),
          ],
          Text(
            lines,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              height: 1.35,
              color: Color(0xFF1A1A1A),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  /// The exact monospace text block the receipt prints as (see
  /// [renderThermalReceiptText]).
  String _renderReceiptLines(Map<String, dynamic> receipt, List items) =>
      renderThermalReceiptText(
        receipt,
        fallbackNumber: saleId.substring(0, 8).toUpperCase(),
        showTax: getIt<AuthService>().showTaxOnReceipt,
        columns: _receiptCols,
      );

  /// "Cash given" and "Change" for a cash sale, when the amount handed over
  /// was saved with it (sales from this version on).
  ({double given, double change})? _cashTender(
      Map<String, dynamic> receipt, String method) {
    final given = (receipt['cashGiven'] as num?)?.toDouble();
    if (method != 'CASH' || given == null) return null;
    return (
      given: given,
      change: (receipt['changeGiven'] as num?)?.toDouble() ?? 0,
    );
  }

  String _methodLabel(String method) => switch (method) {
        'CASH' => 'Cash',
        'MPESA' => 'M-Pesa',
        'CARD' => 'Card',
        'CREDIT' => 'Customer credit',
        _ => method,
      };

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    final dt = dateTime is DateTime
        ? dateTime
        : DateTime.parse(dateTime.toString()).toLocal();
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatQuantity(double quantity) =>
      quantity == quantity.roundToDouble()
          ? quantity.toStringAsFixed(0)
          : quantity
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');

  String _buildShareText(Map<String, dynamic> receipt) {
    final items = receipt['items'] as List? ?? [];
    final buffer = StringBuffer();

    buffer.writeln(receipt['branchName'] ?? 'POS Store');
    if ((receipt['branchAddress'] as String?)?.isNotEmpty == true) {
      buffer.writeln(receipt['branchAddress']);
    }
    if ((receipt['branchPhone'] as String?)?.isNotEmpty == true) {
      buffer.writeln('Tel: ${receipt['branchPhone']}');
    }
    buffer.writeln(
        'Receipt #${receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase()}');
    buffer.writeln(_formatDateTime(receipt['createdAt']));
    if (receipt['customerName'] != null) {
      buffer.writeln('Customer: ${receipt['customerName']}');
    }
    if (receipt['customerPhone'] != null) {
      buffer.writeln('Phone: ${receipt['customerPhone']}');
    }
    if ((receipt['status'] ?? '').toString().toUpperCase() == 'VOIDED') {
      buffer.writeln('*** VOIDED SALE ***');
      final vr = (receipt['voidReason'] ?? '').toString();
      if (vr.isNotEmpty) buffer.writeln('Reason: $vr');
    }
    buffer.writeln('---');

    for (final item in items) {
      final name = item['productName'] ?? '';
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
      final unit = (item['unit'] ?? '').toString().trim();
      final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      final perUnit = (item['quantityPerUnit'] as num?)?.toDouble() ?? 0;
      final total = (item['total'] as num?)?.toStringAsFixed(2) ?? '0.00';
      final label = unit.isNotEmpty
          ? '${_formatQuantity(qty)} $unit'
          : _formatQuantity(qty);
      buffer.writeln('$name');
      buffer.writeln('  $label @ ${unitPrice.toStringAsFixed(2)} — KES $total');
      if (unit.isNotEmpty && perUnit > 1) {
        final perPiece = unitPrice / perUnit;
        buffer.writeln(
            '  (${_formatQuantity(perUnit * qty)} pcs @ ${perPiece.toStringAsFixed(2)} each)');
      }
    }

    buffer.writeln('---');
    buffer.writeln(
        'Subtotal: KES ${((receipt['subtotal'] as num?) ?? 0).toStringAsFixed(2)}');
    final discount = (receipt['discount'] as num?) ?? 0;
    if (discount > 0) {
      buffer.writeln('Discount: -KES ${discount.toStringAsFixed(2)}');
    }
    final tax = (receipt['tax'] as num?) ?? 0;
    if (getIt<AuthService>().showTaxOnReceipt && tax > 0) {
      buffer.writeln('Tax: KES ${tax.toStringAsFixed(2)}');
    }
    buffer.writeln(
        'Total: KES ${((receipt['total'] as num?) ?? 0).toStringAsFixed(2)}');

    final method =
        (receipt['paymentMethod'] ?? 'CASH').toString().toUpperCase();
    final tenders = receipt['paymentTenders'] as List?;
    if (method == 'SPLIT' && tenders != null && tenders.isNotEmpty) {
      buffer.writeln('Paid by (split):');
      for (final t in tenders) {
        buffer.writeln(
            '  ${t['method']}: KES ${((t['amount'] as num?) ?? 0).toStringAsFixed(2)}');
      }
    } else {
      buffer.writeln('Paid by: ${_methodLabel(method)}');
      final cash = _cashTender(receipt, method);
      if (cash != null) {
        buffer.writeln('Cash given: KES ${cash.given.toStringAsFixed(2)}');
        buffer.writeln('Change: KES ${cash.change.toStringAsFixed(2)}');
      }
    }
    final creditAdded =
        (receipt['creditAmountAtSale'] as num?)?.toDouble() ?? 0;
    if (creditAdded > 0.01) {
      buffer.writeln('Credit added: KES ${creditAdded.toStringAsFixed(2)}');
    }
    buffer.writeln();
    buffer.writeln('Thank you for your purchase!');
    buffer.writeln('We look forward to serving you again. All the best!');

    return buffer.toString();
  }

  Future<void> _shareReceiptPdf(
      WidgetRef ref, Map<String, dynamic> receipt) async {
    final canViewCustomerDetails =
        ref.read(permissionsProvider).canSeeCustomers;
    final safeReceipt = receiptForCustomerVisibility(
      receipt,
      canViewCustomerDetails: canViewCustomerDetails,
    );
    final bytes =
        await ref.read(receiptPdfBuilderProvider)(ref, saleId, safeReceipt);
    if (canViewCustomerDetails &&
        !ref.read(permissionsProvider).canSeeCustomers) {
      return;
    }
    await ref.read(receiptPdfShareDispatcherProvider)(
      bytes,
      'receipt_${safeReceipt['receiptNumber'] ?? saleId}',
    );
  }

  Future<Uint8List> _buildReceiptPdf(
      WidgetRef ref, Map<String, dynamic> receipt) async {
    final items = receipt['items'] as List? ?? [];
    final identity = ref.read(tenantIdentityProvider);
    final logoBytes = await ExportDocumentService.fetchLogoBytes(
      identity.logoUrl,
      allowNetwork: !getIt<AuthService>().isLocalWorkspace,
    );

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
    final method =
        (receipt['paymentMethod'] ?? 'CASH').toString().toUpperCase();
    final tenders = receipt['paymentTenders'] as List?;
    if (method == 'SPLIT' && tenders != null && tenders.isNotEmpty) {
      for (final t in tenders) {
        summaryRows.add([
          'Paid (${t['method']})',
          'KES ${((t['amount'] as num?) ?? 0).toStringAsFixed(2)}',
        ]);
      }
    } else if (RecordedPaymentMethod.isRecorded(method)) {
      final recorded = RecordedPaymentDetails.tryParse(
          receipt['paymentReference']?.toString());
      summaryRows.add(['Payment', RecordedPaymentMethod.label(method)]);
      if (recorded != null) {
        summaryRows.add(['Reference', recorded.code]);
        if (recorded.recordedByName.isNotEmpty) {
          summaryRows.add(['Recorded by', recorded.recordedByName]);
        }
        if (recorded.approvedByName != null) {
          summaryRows.add(['Approved by', recorded.approvedByName!]);
        }
      }
      summaryRows
          .add(['Note', 'Recorded by the shop. Not verified by Counterbase.']);
    } else {
      summaryRows.add(['Payment', _methodLabel(method)]);
      final cash = _cashTender(receipt, method);
      if (cash != null) {
        summaryRows.add(['Cash given', 'KES ${cash.given.toStringAsFixed(2)}']);
        summaryRows.add(['Change', 'KES ${cash.change.toStringAsFixed(2)}']);
      }
    }
    final creditAdded =
        (receipt['creditAmountAtSale'] as num?)?.toDouble() ?? 0;
    if (creditAdded > 0.01) {
      summaryRows
          .add(['Credit added', 'KES ${creditAdded.toStringAsFixed(2)}']);
    }

    // Per-item row: qty with unit label + per-unit-within-tier breakdown.
    String itemQtyLabel(Map item) {
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
      final unit = (item['unit'] ?? '').toString().trim();
      final perUnit = (item['quantityPerUnit'] as num?)?.toDouble() ?? 0;
      final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      var label = unit.isNotEmpty
          ? '${_formatQuantity(qty)} $unit @ ${unitPrice.toStringAsFixed(2)}'
          : _formatQuantity(qty);
      if (unit.isNotEmpty && perUnit > 1) {
        label +=
            ' (${_formatQuantity(perUnit * qty)} pcs @ ${(unitPrice / perUnit).toStringAsFixed(2)})';
      }
      return label;
    }

    final voided =
        (receipt['status'] ?? '').toString().toUpperCase() == 'VOIDED';
    return ExportDocumentService.buildPdfReport(
      title:
          'Receipt #${receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase()}'
          '${voided ? '  —  VOIDED' : ''}',
      companyName: (receipt['branchName'] as String?)?.isNotEmpty == true
          ? receipt['branchName']
          : identity.companyName,
      subtitle: [
        if ((receipt['branchAddress'] ?? '').toString().isNotEmpty)
          receipt['branchAddress'].toString(),
        if ((receipt['branchPhone'] ?? '').toString().isNotEmpty)
          'Tel: ${receipt['branchPhone']}',
        _formatDateTime(receipt['createdAt']),
        if (receipt['customerName'] != null)
          'Customer: ${receipt['customerName']}',
        if (receipt['customerPhone'] != null) '${receipt['customerPhone']}',
        if (voided && (receipt['voidReason'] ?? '').toString().isNotEmpty)
          'VOIDED: ${receipt['voidReason']}',
      ].join('  ·  '),
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
  }

  /// Opens the operating system's print dialog with the same A4 PDF used by
  /// Share. This is deliberately separate from the thermal Bluetooth queue.
  Future<void> _printReceiptOnComputer(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? receipt,
  ) async {
    if (receipt == null) {
      showGlassSnackBar(
        context,
        'Receipt is still loading — try again in a moment.',
        icon: Icons.hourglass_empty_rounded,
        color: DesignColors.warning,
      );
      return;
    }

    try {
      final canViewCustomerDetails =
          ref.read(permissionsProvider).canSeeCustomers;
      final bytes = await ref.read(receiptPdfBuilderProvider)(
        ref,
        saleId,
        receiptForCustomerVisibility(
          receipt,
          canViewCustomerDetails: canViewCustomerDetails,
        ),
      );
      if (!context.mounted) return;
      if (canViewCustomerDetails &&
          !ref.read(permissionsProvider).canSeeCustomers) {
        return;
      }
      final number =
          (receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase())
              .toString();
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Receipt $number',
        format: PdfPageFormat.a4,
        dynamicLayout: false,
      );
    } catch (e) {
      if (!context.mounted) return;
      showGlassSnackBar(
        context,
        'Could not print receipt. ${apiErrorMessage(e)}',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
  }

  /// Silent counterpart to [printReceipt] for the "auto-print after each
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

  Future<void> printReceipt(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? receipt,
  ) async {
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
    final visibleReceipt = receiptForCustomerVisibility(
      receipt,
      canViewCustomerDetails: ref.read(permissionsProvider).canSeeCustomers,
    );

    try {
      final printedHere = await queue.requestPrint(
        receipt: visibleReceipt,
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
        showGlassSnackBar(
            context, 'Could not print receipt. ${apiErrorMessage(e)}',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    }
  }

  /// Voids a sale — now a soft-void with a mandatory reason (kept + audited,
  /// not deleted). Prompts for the reason, voids on the backend (restores
  /// stock server-side) when online, and marks the local sale VOIDED so the
  /// receipt immediately shows the VOIDED banner + reason.
  Future<void> voidSale(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> receipt,
  ) async {
    final auth = getIt<AuthService>();
    final reasonController = TextEditingController();
    final paymentMethod =
        (receipt['paymentMethod'] ?? 'CASH').toString().trim().toUpperCase();
    final receiptTotal = (receipt['total'] as num?)?.toDouble() ?? 0;
    final tenders = receipt['paymentTenders'] as List?;
    final cashTenderAmount = paymentMethod == 'CASH'
        ? receiptTotal
        : paymentMethod == 'SPLIT'
            ? (tenders ?? const [])
                .whereType<Map>()
                .where((tender) =>
                    (tender['method'] ?? '').toString().toUpperCase() == 'CASH')
                .fold<double>(
                  0,
                  (amount, tender) =>
                      amount + ((tender['amount'] as num?)?.toDouble() ?? 0),
                )
            : 0;
    var recordCashRefund = false;
    String? reasonError;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          icon: const Icon(Icons.block_rounded, color: DesignColors.error),
          title: const Text('Void this sale?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The receipt stays in the audit history and its stock is returned.',
                ),
                if (auth.isLocalWorkspace && cashTenderAmount > 0) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: recordCashRefund,
                    onChanged: (value) => setDialogState(
                      () => recordCashRefund = value ?? false,
                    ),
                    title: const Text('Cash was returned from the till'),
                    subtitle: Text(
                      'Record KES ${cashTenderAmount.toStringAsFixed(2)} as a till refund. Select this only if you physically returned the cash. A split sale records only its cash portion.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (!recordCashRefund)
                    const Text(
                      'If no cash was handed back, the original cash stays in the till and will remain in the cash reconciliation.',
                      style: TextStyle(color: DesignColors.textSecondary),
                    ),
                ] else if (auth.isLocalWorkspace) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'No till cash refund is available for this payment. Refund any M-Pesa or card payment through its original payment method.',
                    style: TextStyle(color: DesignColors.textSecondary),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Voiding does not issue a refund through the payment provider.',
                    style: TextStyle(color: DesignColors.textSecondary),
                  ),
                ],
                if (auth.isLocalWorkspace) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'For credit sales, voiding is blocked if a later customer collection exists or if active due dates would exceed the remaining customer balance. Customer collections and schedules are account-level, so review them before reversing a receipt.',
                    style: TextStyle(color: DesignColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  onChanged: (value) {
                    if (reasonError != null && value.trim().isNotEmpty) {
                      setDialogState(() => reasonError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Reason for voiding',
                    hintText: 'e.g. wrong item, customer changed mind',
                    errorText: reasonError,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep sale'),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: DesignColors.error),
              onPressed: () {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  setDialogState(
                    () => reasonError = 'Enter a reason to void this sale.',
                  );
                  return;
                }
                Navigator.pop(ctx, {
                  'reason': reason,
                  'recordCashRefund': recordCashRefund,
                });
              },
              child: const Text('Void sale'),
            ),
          ],
        ),
      ),
    );

    final reason = result?['reason']?.toString();
    recordCashRefund = result?['recordCashRefund'] == true;
    if (reason == null || !context.mounted) return;

    final db = getIt<AppDatabase>();
    final userName = auth.currentUser?['name'] as String?;

    if (auth.isLocalWorkspace) {
      try {
        await db.voidPendingSale(
          saleId,
          reason: reason,
          voidedBy: userName,
          guardUnallocatedCollections: true,
          recordCashRefund: recordCashRefund,
        );
        ref.invalidate(receiptProvider(saleId));
        if (context.mounted) {
          showGlassSnackBar(
            context,
            recordCashRefund
                ? 'Sale voided. The cash refund was recorded and stock returned.'
                : cashTenderAmount > 0
                    ? 'Sale voided. No cash refund was recorded; cash remains in the till.'
                    : 'Sale voided. Any non-cash refund must be returned through its payment provider.',
            icon: Icons.check_circle_outline_rounded,
            color: DesignColors.success,
          );
        }
      } catch (error) {
        if (context.mounted) {
          if (error is LocalSaleVoidConflict) {
            await showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                icon: const Icon(
                  Icons.info_outline_rounded,
                  color: DesignColors.warning,
                ),
                title: const Text('Sale not voided'),
                content: Text(error.message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Understood'),
                  ),
                ],
              ),
            );
            return;
          }
          showGlassSnackBar(
            context,
            'Could not void the sale. The saved sale and stock were left unchanged.',
            icon: Icons.error_outline_rounded,
            color: DesignColors.error,
          );
        }
      }
      return;
    }

    var queueVoidSync = false;
    // Void on the backend first when reachable. Authorization and validation
    // failures must not be turned into a local-only void; network and
    // not-yet-synced receipt failures can be queued for ordered recovery.
    try {
      await getIt<ApiClient>().voidSale(saleId, reason: reason);
    } catch (error) {
      if (error is DioException &&
          const {400, 401, 403, 409, 422}
              .contains(error.response?.statusCode)) {
        if (context.mounted) {
          showGlassSnackBar(
            context,
            'Sale was not voided: ${loadErrorSubtitle(error)}',
            icon: Icons.error_outline_rounded,
            color: DesignColors.error,
          );
        }
        return;
      }
      queueVoidSync = true;
    }

    try {
      await db.voidPendingSale(saleId, reason: reason, voidedBy: userName);
      var syncQueued = !queueVoidSync;
      if (queueVoidSync) {
        final auth = getIt<AuthService>();
        final userId = auth.userId;
        if (userId != null && userId.isNotEmpty) {
          try {
            await getIt<SyncService>().queueSaleVoidForSync(
              saleId: saleId,
              reason: reason,
              voidedById: userId,
            );
            syncQueued = true;
          } catch (_) {
            syncQueued = false;
          }
        }
      }
      ref.invalidate(receiptProvider(saleId));
      if (context.mounted) {
        showGlassSnackBar(
          context,
          syncQueued
              ? queueVoidSync
                  ? 'Sale voided on this device. Sync is queued.'
                  : 'Sale voided'
              : 'Sale voided locally, but its cloud sync could not be queued. Reconnect and retry sync.',
          icon: syncQueued
              ? Icons.check_circle_outline_rounded
              : Icons.sync_problem_rounded,
          color: syncQueued ? DesignColors.success : DesignColors.warning,
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

class _ReceiptActionButton extends StatelessWidget {
  const _ReceiptActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor:
              isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
          side: BorderSide(
            color:
                isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
