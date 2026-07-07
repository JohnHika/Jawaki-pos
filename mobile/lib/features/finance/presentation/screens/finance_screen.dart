import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/supplier_receipt_ocr_service.dart';
import '../../../../core/theme/design_system.dart';

final _supplierBalancesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    return await getIt<AppDatabase>().getSupplierDebts();
  } catch (e) {
    debugPrint('Finance: supplier tables not available ($e)');
    return [];
  }
});

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  static final currencyFmt =
      NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  final _picker = ImagePicker();
  final _ocr = SupplierReceiptOcrService();
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    final balancesAsync = ref.watch(_supplierBalancesProvider);

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Finance',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_supplierBalancesProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? null : _pickAndScanReceipt,
        icon: _isScanning
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.document_scanner_rounded),
        label: Text(_isScanning ? 'Scanning...' : 'Scan Receipt'),
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
      final scan = await _ocr.scan(File(image.path));
      if (!mounted) return;
      await _showInvoiceReviewDialog(scan: scan);
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Receipt scan failed: $e',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _showManualInvoiceDialog() async {
    await _showInvoiceReviewDialog(
      scan: const SupplierReceiptScan(
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

  Future<void> _showInvoiceReviewDialog(
      {required SupplierReceiptScan scan}) async {
    final supplierController = TextEditingController(
        text: scan.suggestedSupplierName == 'Unknown Supplier'
            ? ''
            : scan.suggestedSupplierName);
    final invoiceController =
        TextEditingController(text: scan.invoiceNumber ?? '');
    final paidController = TextEditingController(text: '0');
    final termsController = TextEditingController(text: 'Pay later');
    DateTime? dueDate = DateTime.now().add(const Duration(days: 30));
    final itemRows = scan.items.isEmpty
        ? [_InvoiceItemDraft()]
        : scan.items.map((item) => _InvoiceItemDraft.fromScan(item)).toList();

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final total =
              itemRows.fold<double>(0, (sum, item) => sum + item.lineTotal);
          final paid = double.tryParse(paidController.text) ?? 0;
          final due = (total - paid).clamp(0, double.infinity).toDouble();

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.fact_check_rounded, color: DesignColors.brand),
                const SizedBox(width: 8),
                const Expanded(child: Text('Review Supplier Invoice')),
                IconButton(
                    tooltip: 'Add item',
                    onPressed: () =>
                        setDialogState(() => itemRows.add(_InvoiceItemDraft())),
                    icon: const Icon(Icons.add_circle_outline_rounded)),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (scan.rawText.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                            color: DesignColors.brand.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(scan.summary,
                            style: const TextStyle(
                                fontSize: 12,
                                color: DesignColors.textSecondary)),
                      ),
                    TextField(
                        controller: supplierController,
                        decoration: const InputDecoration(
                            labelText: 'Supplier name',
                            prefixIcon: Icon(Icons.business_rounded))),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: TextField(
                                controller: invoiceController,
                                decoration: const InputDecoration(
                                    labelText: 'Invoice/receipt number'))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: TextField(
                                controller: termsController,
                                decoration:
                                    const InputDecoration(labelText: 'Terms'))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                            child: TextField(
                                controller: paidController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Paid now (KES)'),
                                onChanged: (_) => setDialogState(() {}))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: dueDate ?? DateTime.now(),
                                firstDate: DateTime.now()
                                    .subtract(const Duration(days: 365)),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 3650)),
                              );
                              if (picked != null) {
                                setDialogState(() => dueDate = picked);
                              }
                            },
                            icon: const Icon(Icons.event_rounded),
                            label: Text(dueDate == null
                                ? 'No due date'
                                : DateFormat('dd MMM yyyy').format(dueDate!)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Items',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ...itemRows
                        .asMap()
                        .entries
                        .map((entry) => _InvoiceItemEditor(
                              item: entry.value,
                              onChanged: () => setDialogState(() {}),
                              onRemove: itemRows.length == 1
                                  ? null
                                  : () => setDialogState(
                                      () => itemRows.removeAt(entry.key)),
                            )),
                    const SizedBox(height: 12),
                    _InvoiceTotals(total: total, paid: paid, due: due),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton.icon(
                onPressed: supplierController.text.trim().isEmpty ||
                        itemRows.every((item) => item.name.trim().isEmpty)
                    ? null
                    : () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save Invoice'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && mounted) {
      try {
        await getIt<AppDatabase>().recordSupplierInvoice(
          supplierName: supplierController.text.trim(),
          invoiceNumber: invoiceController.text.trim().isEmpty
              ? null
              : invoiceController.text.trim(),
          receiptImagePath: scan.imagePath.isEmpty ? null : scan.imagePath,
          ocrText: scan.rawText.isEmpty ? null : scan.rawText,
          summary: scan.summary,
          terms: termsController.text.trim().isEmpty
              ? 'Pay later'
              : termsController.text.trim(),
          paidAmount: double.tryParse(paidController.text) ?? 0,
          dueDate: dueDate,
          items: itemRows
              .where((item) => item.name.trim().isNotEmpty)
              .map((item) => item.toMap())
              .toList(),
        );
        ref.invalidate(_supplierBalancesProvider);
        if (mounted) {
          showGlassSnackBar(
              context, 'Supplier invoice saved and catalog updated',
              icon: Icons.check_circle_rounded, color: DesignColors.success);
        }
      } catch (e) {
        if (mounted) {
          showGlassSnackBar(context, 'Could not save invoice: $e',
              icon: Icons.error_outline_rounded, color: DesignColors.error);
        }
      }
    }
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
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Current balance: ${FinanceScreen.currencyFmt.format(currentDebt)}',
                style: const TextStyle(
                    color: DesignColors.textSecondary, fontSize: 13)),
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
      ),
    );

    if (confirmed == true && mounted) {
      final amount = double.tryParse(controller.text) ?? 0;
      if (amount > 0) {
        await getIt<AppDatabase>().recordSupplierPayment(supplierId, amount);
        ref.invalidate(_supplierBalancesProvider);
        if (mounted) {
          showGlassSnackBar(context,
              'Payment of ${FinanceScreen.currencyFmt.format(amount)} recorded',
              icon: Icons.check_circle_rounded, color: DesignColors.success);
        }
      }
    }
  }

  Future<void> _showSupplierInvoices(
      String supplierId, String supplierName) async {
    final invoices = await getIt<AppDatabase>().getSupplierInvoices(supplierId);
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
                    subtitle: invoice['summary'] as String? ?? '',
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                            FinanceScreen.currencyFmt.format(
                                (invoice['totalAmount'] as num).toDouble()),
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

  const _ReceiptCapturePanel(
      {required this.totalInvoices,
      required this.overdueCount,
      required this.isScanning,
      required this.onScan,
      required this.onManual});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
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
                    const Text('Supplier Receipt Intake',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(
                        '$totalInvoices invoice${totalInvoices == 1 ? '' : 's'} tracked, $overdueCount overdue',
                        style: const TextStyle(
                            fontSize: 12, color: DesignColors.textSecondary)),
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

  const _SupplierBalanceCard(
      {required this.supplier,
      required this.onRecordPayment,
      required this.onViewInvoices});

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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderRadius: 14,
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
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: DesignColors.textPrimary)),
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
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: DesignColors.textTertiary)),
                          Text('$invoices invoice${invoices == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: DesignColors.textTertiary)),
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
                    backgroundColor:
                        DesignColors.surfaceBorder.withValues(alpha: 0.4),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        DesignColors.success),
                    minHeight: 6),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${percentage.toStringAsFixed(0)}% paid',
                      style: const TextStyle(
                          fontSize: 10, color: DesignColors.textTertiary)),
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
                        style: const TextStyle(
                            fontSize: 10, color: DesignColors.textTertiary)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InvoiceItemDraft {
  final TextEditingController nameController;
  final TextEditingController quantityController;
  final TextEditingController unitCostController;
  final TextEditingController skuController;
  final String rawText;
  final double confidence;

  _InvoiceItemDraft(
      {String name = '',
      double quantity = 1,
      double unitCost = 0,
      String? sku,
      this.rawText = '',
      this.confidence = 0})
      : nameController = TextEditingController(text: name),
        quantityController = TextEditingController(
            text: quantity.toStringAsFixed(
                quantity.truncateToDouble() == quantity ? 0 : 2)),
        unitCostController = TextEditingController(
            text: unitCost == 0 ? '' : unitCost.toStringAsFixed(0)),
        skuController = TextEditingController(text: sku ?? '');

  factory _InvoiceItemDraft.fromScan(SupplierReceiptLineItem item) =>
      _InvoiceItemDraft(
          name: item.name,
          quantity: item.quantity,
          unitCost: item.unitCost,
          sku: item.sku,
          rawText: item.rawText,
          confidence: item.confidence);

  String get name => nameController.text.trim();
  double get quantity => double.tryParse(quantityController.text) ?? 1;
  double get unitCost => double.tryParse(unitCostController.text) ?? 0;
  double get lineTotal => quantity * unitCost;

  Map<String, dynamic> toMap() => {
        'name': name,
        'sku': skuController.text.trim().isEmpty
            ? null
            : skuController.text.trim(),
        'quantity': quantity,
        'unit': 'piece',
        'unitCost': unitCost,
        'lineTotal': lineTotal,
        'confidence': confidence,
        'rawText': rawText,
      };
}

class _InvoiceItemEditor extends StatelessWidget {
  final _InvoiceItemDraft item;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _InvoiceItemEditor(
      {required this.item, required this.onChanged, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          border: Border.all(
              color: DesignColors.surfaceBorder.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  flex: 3,
                  child: TextField(
                      controller: item.nameController,
                      decoration: const InputDecoration(labelText: 'Product'),
                      onChanged: (_) => onChanged())),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: item.quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Qty'),
                      onChanged: (_) => onChanged())),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: item.unitCostController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cost'),
                      onChanged: (_) => onChanged())),
              if (onRemove != null)
                IconButton(
                    tooltip: 'Remove',
                    onPressed: onRemove,
                    icon: const Icon(Icons.remove_circle_outline_rounded,
                        color: DesignColors.error)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: TextField(
                      controller: item.skuController,
                      decoration:
                          const InputDecoration(labelText: 'SKU optional'),
                      onChanged: (_) => onChanged())),
              const SizedBox(width: 8),
              Text(FinanceScreen.currencyFmt.format(item.lineTotal),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InvoiceTotals extends StatelessWidget {
  final double total;
  final double paid;
  final double due;

  const _InvoiceTotals(
      {required this.total, required this.paid, required this.due});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: DesignColors.surfaceBorder.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        _row('Total', total),
        _row('Paid', paid),
        const Divider(height: 16),
        _row('Balance due', due, isStrong: true)
      ]),
    );
  }

  Widget _row(String label, double value, {bool isStrong = false}) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(
                fontWeight: isStrong ? FontWeight.w800 : FontWeight.w500)),
        const Spacer(),
        Text(FinanceScreen.currencyFmt.format(value),
            style: TextStyle(
                fontWeight: isStrong ? FontWeight.w800 : FontWeight.w600)),
      ],
    );
  }
}
