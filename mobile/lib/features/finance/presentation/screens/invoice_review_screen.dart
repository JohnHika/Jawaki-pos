import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/supplier_receipt_ocr_service.dart';
import '../../../../core/theme/design_system.dart';

/// Cash till vs credit — mirrors CashFundingSource on the backend.
enum InvoiceFundingSource { cashTill, creditSupplier }

extension InvoiceFundingSourceWireFormat on InvoiceFundingSource {
  String get wireName => switch (this) {
        InvoiceFundingSource.cashTill => 'CASH_TILL',
        InvoiceFundingSource.creditSupplier => 'CREDIT_SUPPLIER',
      };

  String get label => switch (this) {
        InvoiceFundingSource.cashTill => 'Cash till',
        InvoiceFundingSource.creditSupplier => 'Credit (pay later)',
      };
}

/// Full-screen supplier invoice review/edit, replacing the old generic
/// AlertDialog — styled to match the rest of the app (see
/// batch_receive_screen.dart for the same visual patterns: BrandedAppBar,
/// bordered header card, themed field decoration, bottom sticky action
/// bar). Reached from three places in finance_screen.dart: an AI/OCR scan,
/// a restock-suggestion prefill, or manual entry with no scan at all.
class InvoiceReviewScreen extends ConsumerStatefulWidget {
  final SupplierReceiptScan scan;

  const InvoiceReviewScreen({super.key, required this.scan});

  static final _currencyFmt =
      NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);

  @override
  ConsumerState<InvoiceReviewScreen> createState() => _InvoiceReviewScreenState();
}

class _InvoiceReviewScreenState extends ConsumerState<InvoiceReviewScreen> {
  late final TextEditingController _supplierController;
  late final TextEditingController _invoiceController;
  late final TextEditingController _paidController;
  late final TextEditingController _termsController;
  DateTime? _dueDate;
  InvoiceFundingSource _fundingSource = InvoiceFundingSource.cashTill;
  late List<_InvoiceItemDraft> _itemRows;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final scan = widget.scan;
    _supplierController = TextEditingController(
        text: scan.suggestedSupplierName == 'Unknown Supplier'
            ? ''
            : scan.suggestedSupplierName);
    _invoiceController = TextEditingController(text: scan.invoiceNumber ?? '');
    _paidController = TextEditingController(text: '0');
    _termsController = TextEditingController(text: 'Pay later');
    _dueDate = DateTime.now().add(const Duration(days: 30));
    _itemRows = scan.items.isEmpty
        ? [_InvoiceItemDraft()]
        : scan.items.map((item) => _InvoiceItemDraft.fromScan(item)).toList();
  }

  @override
  void dispose() {
    _supplierController.dispose();
    _invoiceController.dispose();
    _paidController.dispose();
    _termsController.dispose();
    for (final item in _itemRows) {
      item.dispose();
    }
    super.dispose();
  }

  double get _total =>
      _itemRows.fold<double>(0, (sum, item) => sum + item.lineTotal);
  double get _paid => double.tryParse(_paidController.text) ?? 0;
  double get _due => (_total - _paid).clamp(0, double.infinity).toDouble();

  bool get _canSave =>
      _supplierController.text.trim().isNotEmpty &&
      _itemRows.any((item) => item.name.trim().isNotEmpty);

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String labelText,
    String? hintText,
    String? prefixText,
    IconData? prefixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final tertiaryColor =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    final fill = isDark
        ? DesignColors.darkSurfaceElevated
        : DesignColors.surfaceBorder.withValues(alpha: 0.15);

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      hintStyle: TextStyle(color: tertiaryColor),
      labelStyle: TextStyle(color: secondaryColor, fontWeight: FontWeight.w500),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      prefixText: prefixText,
      prefixStyle: prefixText != null
          ? TextStyle(color: secondaryColor, fontWeight: FontWeight.w600)
          : null,
      prefixIcon:
          prefixIcon != null ? Icon(prefixIcon, color: tertiaryColor, size: 20) : null,
      filled: true,
      fillColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DesignColors.brand, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Review Supplier Invoice',
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DesignColors.brand.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.add_circle_outline_rounded,
                color: DesignColors.brand,
                size: 20,
              ),
            ),
            tooltip: 'Add item',
            onPressed: () => setState(() => _itemRows.add(_InvoiceItemDraft())),
          ),
        ],
      ),
      body: PageContainer(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  if (widget.scan.imagePath.isNotEmpty ||
                      widget.scan.summary.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: surface,
                        border: Border.all(
                            color: DesignColors.brand.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.scan.imagePath.startsWith('http'))
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                widget.scan.imagePath,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                          if (widget.scan.imagePath.startsWith('http'))
                            const SizedBox(height: 12),
                          if (widget.scan.summary.isNotEmpty)
                            Text(widget.scan.summary,
                                style: TextStyle(fontSize: 12, color: secondaryColor)),
                        ],
                      ),
                    ),

                  TextFormField(
                    controller: _supplierController,
                    style: TextStyle(color: titleColor),
                    decoration: _fieldDecoration(context,
                        labelText: 'Supplier name', prefixIcon: Icons.business_rounded),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _invoiceController,
                          style: TextStyle(color: titleColor),
                          decoration: _fieldDecoration(context,
                              labelText: 'Invoice/receipt number'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _termsController,
                          style: TextStyle(color: titleColor),
                          decoration: _fieldDecoration(context, labelText: 'Terms'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _paidController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: titleColor),
                          decoration: _fieldDecoration(context,
                              labelText: 'Paid now', prefixText: 'KES '),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickDueDate(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? DesignColors.darkSurfaceElevated
                                  : DesignColors.surfaceBorder.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.event_rounded,
                                    color: secondaryColor, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _dueDate == null
                                        ? 'No due date'
                                        : DateFormat('dd MMM yyyy').format(_dueDate!),
                                    style: TextStyle(color: titleColor, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Text('Funding source',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: secondaryColor)),
                  const SizedBox(height: 8),
                  SegmentedButton<InvoiceFundingSource>(
                    segments: const [
                      ButtonSegment(
                        value: InvoiceFundingSource.cashTill,
                        label: Text('Cash till'),
                        icon: Icon(Icons.payments_outlined),
                      ),
                      ButtonSegment(
                        value: InvoiceFundingSource.creditSupplier,
                        label: Text('Credit'),
                        icon: Icon(Icons.schedule_outlined),
                      ),
                    ],
                    selected: {_fundingSource},
                    onSelectionChanged: (selection) =>
                        setState(() => _fundingSource = selection.first),
                  ),
                  const SizedBox(height: 20),

                  Text('Items',
                      style: TextStyle(fontWeight: FontWeight.w700, color: titleColor)),
                  const SizedBox(height: 10),
                  ..._itemRows.asMap().entries.map(
                        (entry) => _InvoiceItemCard(
                          item: entry.value,
                          onChanged: () => setState(() {}),
                          onRemove: _itemRows.length == 1
                              ? null
                              : () => setState(() {
                                    _itemRows[entry.key].dispose();
                                    _itemRows.removeAt(entry.key);
                                  }),
                        ),
                      ),
                  const SizedBox(height: 16),

                  _InvoiceTotalsCard(total: _total, paid: _paid, due: _due),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: GradientButton(
                  label: 'Save Invoice',
                  icon: Icons.save_rounded,
                  onPressed: _canSave && !_isSaving ? _save : null,
                  isLoading: _isSaving,
                  height: 52,
                  borderRadius: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDueDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    final branchId = getIt<AuthService>().branchId;
    if (branchId == null) {
      showGlassSnackBar(context, 'No branch selected — cannot save invoice',
          icon: Icons.error_outline_rounded, color: DesignColors.error);
      return;
    }

    setState(() => _isSaving = true);

    final items = _itemRows
        .where((item) => item.name.trim().isNotEmpty)
        .map((item) => {
              'productName': item.name,
              'quantity': item.quantity,
              'unit': 'piece',
              'unitCost': item.unitCost,
            })
        .toList();

    final payload = {
      'branchId': branchId,
      'supplierName': _supplierController.text.trim(),
      'invoiceNumber':
          _invoiceController.text.trim().isEmpty ? null : _invoiceController.text.trim(),
      'receiptImageUrl': widget.scan.imagePath.isEmpty ? null : widget.scan.imagePath,
      'items': items,
      'paidAmount': double.tryParse(_paidController.text) ?? 0,
      'fundingSource': _fundingSource.wireName,
      'dueDate': _dueDate?.toIso8601String(),
    };

    try {
      if (getIt<ConnectivityService>().isOnline) {
        await getIt<ApiClient>().createSupplierInvoice(payload);
        if (mounted) {
          showGlassSnackBar(context, 'Supplier invoice saved and stock updated',
              icon: Icons.check_circle_rounded, color: DesignColors.success);
        }
      } else {
        final authService = getIt<AuthService>();
        await getIt<SyncService>().queueSyncItem(
          tableName: 'suppliers',
          recordId: 'offline-invoice-${DateTime.now().microsecondsSinceEpoch}',
          action: SyncAction.create,
          eventType: SyncEventType.supplierInvoiceCreated,
          data: {
            ...payload,
            'offlineId': 'offline-invoice-${DateTime.now().microsecondsSinceEpoch}',
          },
          deviceId: authService.deviceId ?? '',
          userId: authService.userId ?? '',
        );
        if (mounted) {
          showGlassSnackBar(
              context, 'Offline — invoice will sync once you\'re back online',
              icon: Icons.cloud_off_rounded, color: DesignColors.warning);
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Could not save invoice: $e',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _InvoiceItemDraft {
  final TextEditingController nameController;
  final TextEditingController quantityController;
  final TextEditingController unitCostController;
  final TextEditingController skuController;

  _InvoiceItemDraft({String name = '', double quantity = 1, double unitCost = 0, String? sku})
      : nameController = TextEditingController(text: name),
        quantityController = TextEditingController(
            text: quantity.toStringAsFixed(quantity.truncateToDouble() == quantity ? 0 : 2)),
        unitCostController =
            TextEditingController(text: unitCost == 0 ? '' : unitCost.toStringAsFixed(0)),
        skuController = TextEditingController(text: sku ?? '');

  factory _InvoiceItemDraft.fromScan(SupplierReceiptLineItem item) => _InvoiceItemDraft(
        name: item.name,
        quantity: item.quantity,
        unitCost: item.unitCost,
        sku: item.sku,
      );

  String get name => nameController.text.trim();
  double get quantity => double.tryParse(quantityController.text) ?? 1;
  double get unitCost => double.tryParse(unitCostController.text) ?? 0;
  double get lineTotal => quantity * unitCost;

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    unitCostController.dispose();
    skuController.dispose();
  }
}

class _InvoiceItemCard extends StatelessWidget {
  final _InvoiceItemDraft item;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _InvoiceItemCard({required this.item, required this.onChanged, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final fill = isDark
        ? DesignColors.darkSurfaceElevated
        : DesignColors.surfaceBorder.withValues(alpha: 0.15);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: surface, border: Border.all(color: border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: item.nameController,
                    style: TextStyle(color: titleColor),
                    decoration: InputDecoration(
                      labelText: 'Product',
                      labelStyle: TextStyle(color: secondaryColor, fontSize: 12),
                      filled: true,
                      fillColor: fill,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: DesignColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: DesignColors.error, size: 18),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: item.quantityController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: titleColor),
                    decoration: InputDecoration(
                      labelText: 'Qty',
                      labelStyle: TextStyle(color: secondaryColor, fontSize: 12),
                      filled: true,
                      fillColor: fill,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: item.unitCostController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: titleColor),
                    decoration: InputDecoration(
                      labelText: 'Cost',
                      labelStyle: TextStyle(color: secondaryColor, fontSize: 12),
                      filled: true,
                      fillColor: fill,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: item.skuController,
                    style: TextStyle(color: titleColor),
                    decoration: InputDecoration(
                      labelText: 'SKU',
                      labelStyle: TextStyle(color: secondaryColor, fontSize: 12),
                      filled: true,
                      fillColor: fill,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                InvoiceReviewScreen._currencyFmt.format(item.lineTotal),
                style: TextStyle(fontWeight: FontWeight.w700, color: titleColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceTotalsCard extends StatelessWidget {
  final double total;
  final double paid;
  final double due;

  const _InvoiceTotalsCard({required this.total, required this.paid, required this.due});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final fill = isDark
        ? DesignColors.darkSurfaceElevated
        : DesignColors.surfaceBorder.withValues(alpha: 0.2);
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: fill, border: Border.all(color: border)),
      child: Column(
        children: [
          _row('Total', total, secondaryColor, titleColor),
          const SizedBox(height: 8),
          _row('Paid', paid, secondaryColor, titleColor),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: border),
          ),
          _row('Balance due', due, secondaryColor, titleColor, isStrong: true),
        ],
      ),
    );
  }

  Widget _row(String label, double value, Color secondaryColor, Color titleColor,
      {bool isStrong = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isStrong ? FontWeight.w800 : FontWeight.w500,
            color: isStrong ? titleColor : secondaryColor,
          ),
        ),
        const Spacer(),
        Text(
          InvoiceReviewScreen._currencyFmt.format(value),
          style: TextStyle(
            fontWeight: isStrong ? FontWeight.w800 : FontWeight.w600,
            color: titleColor,
          ),
        ),
      ],
    );
  }
}
