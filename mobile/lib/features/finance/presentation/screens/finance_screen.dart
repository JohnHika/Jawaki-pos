import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/supplier_receipt_ocr_service.dart';
import '../../../../core/services/receipt_vision_service.dart';
import '../../../../core/theme/design_system.dart';
import 'invoice_review_screen.dart';

/// Cash till vs credit — mirrors CashFundingSource on the backend.
enum FundingSource { cashTill, creditSupplier }

extension FundingSourceWireFormat on FundingSource {
  String get wireName => switch (this) {
        FundingSource.cashTill => 'CASH_TILL',
        FundingSource.creditSupplier => 'CREDIT_SUPPLIER',
      };

  String get label => switch (this) {
        FundingSource.cashTill => 'Cash till',
        FundingSource.creditSupplier => 'Credit (pay later)',
      };
}

final _supplierBalancesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final debts = await getIt<ApiClient>().getSupplierDebts();
    return debts.cast<Map<String, dynamic>>();
  } catch (e) {
    debugPrint('Finance: could not load supplier debts ($e)');
    return [];
  }
});

class FinanceScreen extends ConsumerStatefulWidget {
  /// Optional single-item prefill, e.g. from tapping "Buy" on a restock
  /// suggestion — opens the manual invoice dialog pre-populated instead of
  /// making the user re-type what the suggestion already computed.
  final RestockPrefill? prefill;

  const FinanceScreen({super.key, this.prefill});

  static final currencyFmt =
      NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

/// Data carried from the Restock Suggestions screen into the Finance
/// screen's manual invoice dialog.
class RestockPrefill {
  final String productName;
  final double quantity;
  final double unitCost;

  const RestockPrefill({
    required this.productName,
    required this.quantity,
    required this.unitCost,
  });
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  final _picker = ImagePicker();
  final _ocr = SupplierReceiptOcrService();
  bool _isScanning = false;
  bool _prefillHandled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prefillHandled && widget.prefill != null) {
      _prefillHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPrefilledInvoiceDialog(widget.prefill!);
      });
    }
  }

  Future<void> _openInvoiceReview(SupplierReceiptScan scan) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => InvoiceReviewScreen(scan: scan)),
    );
    if (saved == true) {
      ref.invalidate(_supplierBalancesProvider);
    }
  }

  Future<void> _showPrefilledInvoiceDialog(RestockPrefill prefill) async {
    await _openInvoiceReview(
      SupplierReceiptScan(
        imagePath: '',
        rawText: '',
        suggestedSupplierName: '',
        invoiceNumber: null,
        totalAmount: prefill.quantity * prefill.unitCost,
        items: [
          SupplierReceiptLineItem(
            name: prefill.productName,
            quantity: prefill.quantity,
            unit: 'piece',
            unitCost: prefill.unitCost,
            lineTotal: prefill.quantity * prefill.unitCost,
            confidence: 1,
            rawText: '',
          ),
        ],
        summary: 'Prefilled from a restock suggestion.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final balancesAsync = ref.watch(_supplierBalancesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Finance',
        showBackButton: false,
        actions: [
          IconButton(
            tooltip: _isScanning ? 'Scanning...' : 'Scan Receipt',
            icon: _isScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.document_scanner_rounded),
            onPressed: _isScanning ? null : _pickAndScanReceipt,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_supplierBalancesProvider),
          ),
        ],
      ),
      body: balancesAsync.when(
        data: (suppliers) {
          final totalOwed = suppliers.fold<double>(
              0, (sum, s) => sum + ((s['totalOwed'] as num?)?.toDouble() ?? 0));
          final totalPaid = suppliers.fold<double>(
              0, (sum, s) => sum + ((s['totalPaid'] as num?)?.toDouble() ?? 0));
          final totalInvoices = suppliers.fold<int>(
              0, (sum, s) => sum + ((s['invoiceCount'] as int?) ?? 0));
          final overdue = suppliers.fold<int>(
              0, (sum, s) => sum + ((s['overdueCount'] as int?) ?? 0));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            children: [
              Row(
                children: [
                  Expanded(
                      child: MetricCard(
                          title: 'Total Owed',
                          value: FinanceScreen.currencyFmt.format(totalOwed),
                          icon: Icons.trending_up_rounded,
                          color: DesignColors.error)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: MetricCard(
                          title: 'Total Paid',
                          value: FinanceScreen.currencyFmt.format(totalPaid),
                          icon: Icons.check_circle_rounded,
                          color: DesignColors.success)),
                ],
              ),
              const SizedBox(height: 12),
              _ReceiptCapturePanel(
                totalInvoices: totalInvoices,
                overdueCount: overdue,
                isScanning: _isScanning,
                onScan: _pickAndScanReceipt,
                onManual: _showManualInvoiceDialog,
                isDark: isDark,
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: 'Supplier Balances',
                subtitle:
                    '${suppliers.length} supplier${suppliers.length == 1 ? '' : 's'}',
                icon: Icons.business_rounded,
                trailing: StatusBadge(
                  label:
                      '${suppliers.where((s) => ((s['totalOwed'] as num?)?.toDouble() ?? 0) > 0).length} with debt',
                  color: DesignColors.warning,
                  isActive: true,
                ),
              ),
              const SizedBox(height: 8),
              if (suppliers.isEmpty)
                EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No Supplier Data',
                  subtitle:
                      'Scan a supplier receipt or enter an invoice to start tracking supplier debt.',
                  actionLabel: 'Scan Receipt',
                  onAction: _pickAndScanReceipt,
                )
              else
                ...suppliers.map((s) => _SupplierBalanceCard(
                      supplier: s,
                      onRecordPayment: (amount) => _recordPayment(
                          s['id'] as String, s['name'] as String, amount),
                      onViewInvoices: () => _showSupplierInvoices(
                          s['id'] as String, s['name'] as String),
                      isDark: isDark,
                    )),
            ],
          );
        },
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: List.generate(
              4,
              (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: ShimmerWidget(
                        width: double.infinity, height: 100, borderRadius: 14),
                  )),
        ),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Error loading supplier data',
          subtitle: 'Check your connection and try again.',
          iconColor: DesignColors.error,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(_supplierBalancesProvider),
        ),
      ),
    );
  }

  Future<void> _pickAndScanReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Take receipt photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose receipt image'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final image = await _picker.pickImage(
        source: source, imageQuality: 88, maxWidth: 1600);
    if (image == null || !mounted) return;

    setState(() => _isScanning = true);
    try {
      final isOnline = getIt<ConnectivityService>().isOnline;
      if (!isOnline) {
        // No network — vision scanning isn't possible at all, go straight
        // to on-device OCR as before. The eventual offline save keeps
        // imagePath as the local file path (the sync queue can't upload
        // it either without connectivity).
        final scan = await _ocr.scan(File(image.path));
        if (!mounted) return;
        await _openInvoiceReview(scan);
        return;
      }

      final branchId = getIt<AuthService>().branchId;
      String? uploadedUrl;
      try {
        final uploadResult = await getIt<ApiClient>().uploadImage(
          filePath: image.path,
          fileName: image.name,
          type: 'supplier-invoice',
        );
        uploadedUrl = uploadResult['url'] as String?;
      } catch (e) {
        debugPrint('Finance: receipt upload failed, falling back to OCR ($e)');
      }

      if (uploadedUrl == null) {
        // Upload itself failed (not a vision/gateway problem) — fall back
        // to on-device OCR on the local file; imagePath stays local since
        // there's no uploaded URL to use.
        final scan = await _ocr.scan(File(image.path));
        if (!mounted) return;
        await _openInvoiceReview(scan);
        return;
      }

      try {
        final scan = await getIt<ReceiptVisionService>().scan(
          imageUrl: uploadedUrl,
          branchId: branchId,
        );
        if (!mounted) return;
        await _openInvoiceReview(scan);
      } on NotAReceiptException catch (e) {
        if (!mounted) return;
        await _showNotAReceiptSheet(e.reason);
      } catch (e) {
        // Vision scan unavailable (gateway down, no AI subscription, etc.)
        // — fall back to on-device OCR, but keep the already-uploaded URL
        // so the saved invoice's receiptImageUrl is still a real, viewable
        // link instead of a local device path.
        debugPrint('Finance: vision scan failed, falling back to OCR ($e)');
        final ocrScan = await _ocr.scan(File(image.path));
        if (!mounted) return;
        await _openInvoiceReview(
          SupplierReceiptScan(
            imagePath: uploadedUrl,
            rawText: ocrScan.rawText,
            suggestedSupplierName: ocrScan.suggestedSupplierName,
            invoiceNumber: ocrScan.invoiceNumber,
            totalAmount: ocrScan.totalAmount,
            items: ocrScan.items,
            summary: 'AI scan unavailable — used basic text recognition instead. ${ocrScan.summary}',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Receipt scan failed: $e',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _showNotAReceiptSheet(String reason) async {
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.image_not_supported_rounded, color: DesignColors.warning),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('This doesn\'t look like a receipt',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(reason, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              ListTile(
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: const Text('Try another photo'),
                  onTap: () => Navigator.pop(ctx, 'retry')),
              ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('Enter manually'),
                  onTap: () => Navigator.pop(ctx, 'manual')),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'retry') {
      await _pickAndScanReceipt();
    } else if (action == 'manual') {
      await _showManualInvoiceDialog();
    }
  }

  Future<void> _showManualInvoiceDialog() async {
    await _openInvoiceReview(
      const SupplierReceiptScan(
        imagePath: '',
        rawText: '',
        suggestedSupplierName: '',
        invoiceNumber: null,
        totalAmount: 0,
        items: [],
        summary: 'Manual supplier invoice.',
      ),
    );
  }

  Future<void> _recordPayment(
      String supplierId, String supplierName, double currentDebt) async {
    final controller = TextEditingController(
        text: currentDebt > 0 ? currentDebt.toStringAsFixed(0) : '');
    final confirmed = await GlassBottomSheet.show<bool>(
      context,
      title: 'Pay $supplierName',
      initialSize: 0.42,
      maxSize: 0.6,
      scrollable: true,
      child: Builder(builder: (sheetContext) {
        final sheetIsDark =
            Theme.of(sheetContext).brightness == Brightness.dark;
        final sheetSecondary = sheetIsDark
            ? DesignColors.darkTextSecondary
            : DesignColors.textSecondary;
        return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Current balance: ${FinanceScreen.currencyFmt.format(currentDebt)}',
                style: TextStyle(color: sheetSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: 'Payment Amount (KES)',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: DesignColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Record Payment'),
                  ),
                ),
              ],
            ),
          ],
        ),
        );
      }),
    );

    if (confirmed == true && mounted) {
      final amount = double.tryParse(controller.text) ?? 0;
      if (amount > 0) {
        try {
          await _applyPaymentAcrossInvoices(supplierId, amount);
          ref.invalidate(_supplierBalancesProvider);
          if (mounted) {
            showGlassSnackBar(context,
                'Payment of ${FinanceScreen.currencyFmt.format(amount)} recorded',
                icon: Icons.check_circle_rounded, color: DesignColors.success);
          }
        } catch (e) {
          if (mounted) {
            showGlassSnackBar(context, 'Could not record payment: $e',
                icon: Icons.error_outline_rounded, color: DesignColors.error);
          }
        }
      }
    }
  }

  /// A supplier balance is the sum of several invoices, but a payment must
  /// be recorded against one specific invoice server-side. Applies [amount]
  /// oldest-invoice-first until it's exhausted, matching how the old
  /// device-local screen always showed one aggregate balance per supplier
  /// rather than per invoice.
  Future<void> _applyPaymentAcrossInvoices(
      String supplierId, double amount) async {
    final invoices = await getIt<ApiClient>().getSupplierInvoices(supplierId);
    final openInvoices = invoices
        .cast<Map<String, dynamic>>()
        .where((inv) => ((inv['dueAmount'] as num?)?.toDouble() ?? 0) > 0)
        .toList()
      ..sort((a, b) =>
          (a['createdAt'] as String).compareTo(b['createdAt'] as String));

    var remaining = amount;
    for (final invoice in openInvoices) {
      if (remaining <= 0) break;
      final due = (invoice['dueAmount'] as num).toDouble();
      final toApply = remaining < due ? remaining : due;
      await getIt<ApiClient>().recordSupplierPayment(
        invoice['id'] as String,
        {'amount': toApply},
      );
      remaining -= toApply;
    }
  }

  Future<void> _showSupplierInvoices(
      String supplierId, String supplierName) async {
    final invoices = (await getIt<ApiClient>().getSupplierInvoices(supplierId))
        .cast<Map<String, dynamic>>();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(supplierName,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (invoices.isEmpty)
              const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No invoices yet',
                  subtitle: 'Scanned supplier receipts will appear here.')
            else
              ...invoices.map((invoice) => ListCard(
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: DesignColors.brand.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.receipt_long_rounded,
                          color: DesignColors.brand, size: 20),
                    ),
                    title:
                        (invoice['invoiceNumber'] as String?)?.isNotEmpty ==
                                true
                            ? invoice['invoiceNumber'] as String
                            : 'Supplier invoice',
                    subtitle:
                        '${(invoice['items'] as List?)?.length ?? 0} item(s)',
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                            FinanceScreen.currencyFmt
                                .format((invoice['totalAmount'] as num).toDouble()),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text(invoice['status'] as String,
                            style: const TextStyle(
                                fontSize: 11,
                                color: DesignColors.textTertiary)),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _ReceiptCapturePanel extends StatelessWidget {
  final int totalInvoices;
  final int overdueCount;
  final bool isScanning;
  final VoidCallback onScan;
  final VoidCallback onManual;
  final bool isDark;

  const _ReceiptCapturePanel(
      {required this.totalInvoices,
      required this.overdueCount,
      required this.isScanning,
      required this.onScan,
      required this.onManual,
      required this.isDark});

  @override
  Widget build(BuildContext context) {
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: DesignColors.brand.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.document_scanner_rounded,
                      color: DesignColors.brand)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Supplier Receipt Intake',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: titleColor)),
                    Text(
                        '$totalInvoices invoice${totalInvoices == 1 ? '' : 's'} tracked, $overdueCount overdue',
                        style: TextStyle(fontSize: 12, color: secondaryColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: GradientButton(
                      label: isScanning ? 'Scanning...' : 'Scan',
                      icon: Icons.document_scanner_rounded,
                      onPressed: isScanning ? null : onScan,
                      height: 42)),
              const SizedBox(width: 10),
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: onManual,
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('Manual'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplierBalanceCard extends StatelessWidget {
  final Map<String, dynamic> supplier;
  final void Function(double amount) onRecordPayment;
  final VoidCallback onViewInvoices;
  final bool isDark;

  const _SupplierBalanceCard(
      {required this.supplier,
      required this.onRecordPayment,
      required this.onViewInvoices,
      required this.isDark});

  @override
  Widget build(BuildContext context) {
    final totalOwed = ((supplier['totalOwed'] as num?)?.toDouble() ?? 0);
    final totalPaid = ((supplier['totalPaid'] as num?)?.toDouble() ?? 0);
    final totalInvoiced =
        ((supplier['totalInvoiced'] as num?)?.toDouble() ?? 0);
    final invoices = (supplier['invoiceCount'] as int?) ?? 0;
    final overdue = (supplier['overdueCount'] as int?) ?? 0;
    final lastPayment = supplier['lastPaymentDate'] as String?;
    final percentage = totalInvoiced > 0
        ? (totalPaid / totalInvoiced * 100).clamp(0, 100).toDouble()
        : 0.0;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: DesignColors.brand.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: DesignColors.brand.withValues(alpha: 0.15))),
                    child: const Icon(Icons.business_rounded,
                        color: DesignColors.brand, size: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(supplier['name'] as String,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: titleColor)),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          Text(
                              'Owed: ${FinanceScreen.currencyFmt.format(totalOwed)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: totalOwed > 0
                                      ? DesignColors.error
                                      : DesignColors.success,
                                  fontWeight: FontWeight.w600)),
                          Text(
                              'Paid: ${FinanceScreen.currencyFmt.format(totalPaid)}',
                              style: TextStyle(
                                  fontSize: 12, color: tertiaryColor)),
                          Text('$invoices invoice${invoices == 1 ? '' : 's'}',
                              style: TextStyle(
                                  fontSize: 12, color: tertiaryColor)),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'invoices') onViewInvoices();
                    if (value == 'pay') onRecordPayment(totalOwed);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: 'invoices', child: Text('View invoices')),
                    if (totalOwed > 0)
                      const PopupMenuItem(
                          value: 'pay', child: Text('Record payment')),
                  ],
                ),
              ],
            ),
            if (totalInvoiced > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: percentage / 100,
                    backgroundColor: border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        DesignColors.success),
                    minHeight: 6),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${percentage.toStringAsFixed(0)}% paid',
                      style: TextStyle(fontSize: 10, color: tertiaryColor)),
                  if (overdue > 0) ...[
                    const SizedBox(width: 8),
                    Text('$overdue overdue',
                        style: const TextStyle(
                            fontSize: 10,
                            color: DesignColors.error,
                            fontWeight: FontWeight.w700)),
                  ],
                  const Spacer(),
                  if (lastPayment != null)
                    Text('Last: $lastPayment',
                        style: TextStyle(fontSize: 10, color: tertiaryColor)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

