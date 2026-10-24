import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/auth/app_roles.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/receipt_vision_service.dart';
import '../../../../core/services/supplier_receipt_ocr_service.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/motion_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/bulk_allocation.dart';
import '../../domain/collections_ledger.dart';
import '../../domain/finance_models.dart';
import '../providers/finance_hub_controller.dart';
import 'invoice_review_screen.dart';
import 'shop_ledger_screen.dart';
import '../../../../core/utils/format.dart';

class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key, this.prefill});

  final RestockPrefill? prefill;
  static final currencyFmt =
      NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class RestockPrefill {
  const RestockPrefill({
    required this.productName,
    required this.quantity,
    required this.unitCost,
  });

  final String productName;
  final double quantity;
  final double unitCost;
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  final ImagePicker _picker = ImagePicker();
  final SupplierReceiptOcrService _ocr = SupplierReceiptOcrService();
  bool _isScanning = false;
  String? _scanningImagePath;
  bool _prefillHandled = false;
  int _tab = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prefillHandled && widget.prefill != null) {
      _prefillHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPrefill(widget.prefill!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = ref.watch(financeHubProvider);
    final controller = ref.read(financeHubProvider.notifier);
    final permissions = ref.watch(permissionsProvider);
    final snapshot = hub.snapshot;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Finance',
        showBackButton: false,
        actions: <Widget>[
          if (permissions.canViewCashFlow)
            _appBarAction(
              tooltip: 'Cash Flow',
              icon: const Icon(Icons.point_of_sale_rounded),
              onPressed: () => context.push('/cash-flow'),
            ),
          if (permissions.canRecordRestock)
            _appBarAction(
              tooltip: _isScanning ? 'Scanning receipt' : 'Scan Receipt',
              icon: _isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_rounded),
              onPressed: _isScanning ? null : _pickAndScanReceipt,
            ),
          _appBarAction(
            tooltip: 'Refresh Finance',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: hub.isRefreshing ? null : controller.refresh,
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          SafeArea(
            top: false,
            child: snapshot == null
                ? _NoSnapshotState(state: hub, onRetry: controller.refresh)
                : Column(
                    children: <Widget>[
                      _FinanceStatusBar(
                        state: hub,
                        onRetry: controller.refresh,
                      ),
                      _FinanceTabs(
                          index: _tab,
                          onChanged: (index) => setState(() => _tab = index)),
                      Expanded(
                          child: SlideSwitcher(
                              from: SlideFrom.right,
                              child: KeyedSubtree(
                                  key: ValueKey<int>(_tab),
                                  child: _tabBody(
                                      snapshot, controller, permissions)))),
                    ],
                  ),
          ),
          if (_isScanning)
            Positioned.fill(
              child: _AiScanOverlay(imagePath: _scanningImagePath),
            ),
        ],
      ),
    );
  }

  Widget _tabBody(FinanceSnapshot snapshot, FinanceHubController controller,
          RolePermissions permissions) =>
      switch (_tab) {
        0 => _OverviewTab(snapshot: snapshot),
        1 => _SupplierTab(
            payables: snapshot.payables,
            canCreateInvoices: permissions.canRecordRestock,
            onScan: permissions.canRecordRestock ? _pickAndScanReceipt : null,
            onManual:
                permissions.canRecordRestock ? _showManualInvoiceDialog : null,
            onOpenPayable: (item) => _showSupplierDetailsSheet(
              item,
              controller,
              canRecordPayment: permissions.canRecordSupplierPayment,
            ),
          ),
        2 => _RetailTab(
            receivables: snapshot.retailReceivables,
            canManageReceivables: permissions.canManageReceivables,
            onCollectForCustomer: () =>
                _showBulkCollectionSheet(snapshot, controller),
            onCollect: (item) => _showReceivableActions(
              title: 'Collect from ${item.customerName ?? 'customer'}',
              amount: item.outstandingAmount,
              receivableId: item.id,
              receivableType: 'retail',
              branchId: snapshot.branchId,
              controller: controller,
              onRecordReceived: () => _showCollectionSheet(
                title: 'Record payment from ${item.customerName ?? 'customer'}',
                amount: item.outstandingAmount,
                onSave: (amount, method, reference) =>
                    controller.recordRetailCollection(
                  ReceivableCollectionRequest(
                    receivableId: item.id,
                    branchId: snapshot.branchId,
                    amount: amount,
                    method: method,
                    reference: reference,
                  ),
                ),
              ),
            ),
          ),
        _ => _PeerTab(
            snapshot: snapshot,
            canManageReceivables: permissions.canManageReceivables,
            onOpenShop: (shop) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => ShopLedgerScreen(shopId: shop.id))),
            onAddShop: () => _showPeerShopSheet(controller),
            onAddReceivable: () =>
                _showPeerReceivableSheet(snapshot, controller),
            onCollect: (item) => _showReceivableActions(
              title: 'Collect from ${item.debtor.name}',
              amount: item.outstandingAmount,
              receivableId: item.id,
              receivableType: 'peer',
              branchId: snapshot.branchId,
              controller: controller,
              onRecordReceived: () => _showCollectionSheet(
                title: 'Record payment from ${item.debtor.name}',
                amount: item.outstandingAmount,
                onSave: (amount, method, reference) =>
                    controller.recordPeerCollection(
                  ReceivableCollectionRequest(
                    receivableId: item.id,
                    branchId: snapshot.branchId,
                    amount: amount,
                    method: method,
                    reference: reference,
                  ),
                ),
              ),
            ),
          ),
      };

  Widget _appBarAction(
          {required String tooltip,
          required Widget icon,
          VoidCallback? onPressed}) =>
      SizedBox(
        width: DesignSpacing.huge,
        height: DesignSpacing.huge,
        child: IconButton(tooltip: tooltip, icon: icon, onPressed: onPressed),
      );

  Future<void> _openPrefill(RestockPrefill prefill) => _openInvoiceReview(
        SupplierReceiptScan(
          imagePath: '',
          rawText: '',
          suggestedSupplierName: '',
          invoiceNumber: null,
          totalAmount: prefill.quantity * prefill.unitCost,
          items: <SupplierReceiptLineItem>[
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

  Future<void> _openInvoiceReview(SupplierReceiptScan scan) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => InvoiceReviewScreen(scan: scan)),
    );
    if (saved == true && mounted) {
      await ref.read(financeHubProvider.notifier).refresh();
    }
  }

  Future<void> _showManualInvoiceDialog() => _openInvoiceReview(
        const SupplierReceiptScan(
          imagePath: '',
          rawText: '',
          suggestedSupplierName: '',
          invoiceNumber: null,
          totalAmount: 0,
          items: <SupplierReceiptLineItem>[],
          summary: 'Manual supplier invoice.',
        ),
      );

  Future<void> _pickAndScanReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Take receipt photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose receipt image'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final image = await _picker.pickImage(
        source: source, imageQuality: 88, maxWidth: 1600);
    if (image == null || !mounted) return;
    setState(() {
      _isScanning = true;
      _scanningImagePath = image.path;
    });
    try {
      final file = File(image.path);
      SupplierReceiptScan scan;
      if (getIt<ConnectivityService>().isOnline) {
        try {
          // Axon AI looks at the photo itself: it decides whether this is a
          // receipt at all, what kind, and reads the supplier and line items.
          scan = await getIt<ReceiptVisionService>().scanFile(
            file,
            branchId: ref.read(financeHubProvider).snapshot?.branchId,
          );
        } on NotAReceiptException catch (e) {
          if (mounted) await _showNotAReceipt(e.reason);
          return;
        } catch (_) {
          // AI unreachable / no AI plan / unreadable — read it on-device.
          scan = await _ocr.scan(file);
          if (mounted) {
            showGlassSnackBar(
              context,
              'Axon AI is unavailable right now, so this was read on your phone. Please check the details.',
              icon: Icons.info_outline_rounded,
              color: DesignColors.warning,
            );
          }
        }
      } else {
        scan = await _ocr.scan(file);
      }
      if (mounted) await _openInvoiceReview(scan);
    } catch (_) {
      if (mounted) {
        showGlassSnackBar(
          context,
          'Could not read that photo. Try again in better light, or enter the invoice manually.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanningImagePath = null;
        });
      }
    }
  }

  Future<void> _showNotAReceipt(String reason) async {
    final retake = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.image_not_supported_rounded,
            color: DesignColors.warning, size: 32),
        title: const Text("That doesn't look like a receipt"),
        content: Text(reason),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Enter manually'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Scan again'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (retake == true) {
      await _pickAndScanReceipt();
    } else if (retake == false) {
      await _showManualInvoiceDialog();
    }
  }

  Future<void> _showPeerShopSheet(FinanceHubController controller) async {
    final name = TextEditingController();
    final contact = TextEditingController();
    String? error;
    await showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => _SheetFrame(
          title: 'Add other shop',
          children: <Widget>[
            TextField(
                controller: name,
                decoration:
                    InputDecoration(labelText: 'Shop name', errorText: error)),
            const SizedBox(height: DesignSpacing.md),
            TextField(
                controller: contact,
                decoration:
                    const InputDecoration(labelText: 'Contact (optional)')),
            const SizedBox(height: DesignSpacing.xl),
            _sheetButton('Add shop', () async {
              try {
                await controller.createPeerDebtor(
                    name: name.text, contact: contact.text);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } on FinanceFormException catch (e) {
                setSheetState(() => error = e.message);
              }
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _showPeerReceivableSheet(
      FinanceSnapshot snapshot, FinanceHubController controller) async {
    final description = TextEditingController();
    final amount = TextEditingController();
    PeerDebtor? selected =
        snapshot.peerDebtors.isEmpty ? null : snapshot.peerDebtors.first;
    String? descriptionError;
    String? amountError;
    String? shopError;
    await showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => _SheetFrame(
          title: 'Add debt',
          children: <Widget>[
            DropdownButtonFormField<PeerDebtor>(
              initialValue: selected,
              decoration: InputDecoration(
                  labelText: 'Other shop', errorText: shopError),
              items: snapshot.peerDebtors
                  .map((shop) =>
                      DropdownMenuItem(value: shop, child: Text(shop.name)))
                  .toList(),
              onChanged: (value) => setSheetState(() => selected = value),
            ),
            const SizedBox(height: DesignSpacing.md),
            TextField(
                key: const Key('peer-description'),
                controller: description,
                decoration: InputDecoration(
                    labelText: 'Description', errorText: descriptionError)),
            const SizedBox(height: DesignSpacing.md),
            TextField(
                key: const Key('peer-amount'),
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Amount (KES)', errorText: amountError)),
            const SizedBox(height: DesignSpacing.xl),
            _sheetButton('Create receivable', () async {
              final parsedAmount = double.tryParse(amount.text.trim()) ?? 0;
              setSheetState(() {
                shopError = selected == null ? 'Select a shop' : null;
                descriptionError = description.text.trim().isEmpty
                    ? 'Description is required'
                    : null;
                amountError = parsedAmount <= 0
                    ? 'Amount must be greater than zero'
                    : null;
              });
              if (shopError != null ||
                  descriptionError != null ||
                  amountError != null) {
                return;
              }
              try {
                await controller.createPeerReceivable(PeerReceivableRequest(
                  branchId: snapshot.branchId,
                  debtorId: selected!.id,
                  description: description.text.trim(),
                  amount: parsedAmount,
                ));
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } on FinanceFormException catch (e) {
                setSheetState(() => shopError = e.message);
              }
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _showCollectionSheet({
    required String title,
    required double amount,
    required Future<void> Function(
            double amount, String method, String? reference)
        onSave,
  }) async {
    final amountController =
        TextEditingController(text: amount.toStringAsFixed(0));
    final reference = TextEditingController();
    String? error;
    await showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => _SheetFrame(
          title: title,
          children: <Widget>[
            const Text(
              'Record cash already received. For M-Pesa, send a Paystack '
              'request from this debt; its balance updates after verification.',
            ),
            const SizedBox(height: DesignSpacing.md),
            TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Collected (KES)', errorText: error)),
            const SizedBox(height: DesignSpacing.md),
            TextField(
                controller: reference,
                decoration:
                    const InputDecoration(labelText: 'Reference (optional)')),
            const SizedBox(height: DesignSpacing.xl),
            _sheetButton('Record collection', () async {
              final parsed = double.tryParse(amountController.text) ?? 0;
              if (parsed <= 0) {
                setSheetState(() => error = 'Amount must be greater than zero');
                return;
              }
              await onSave(parsed, 'CASH',
                  reference.text.trim().isEmpty ? null : reference.text.trim());
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _showReceivableActions({
    required String title,
    required double amount,
    required String receivableId,
    required String receivableType,
    required String branchId,
    required FinanceHubController controller,
    required Future<void> Function() onRecordReceived,
  }) async {
    final choice = await showModalBottomSheet<int>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _SheetFrame(
        title: title,
        children: [
          Container(
            padding: const EdgeInsets.all(DesignSpacing.md),
            decoration: BoxDecoration(
              color: DesignColors.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            ),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: DesignColors.brand),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: Text('Outstanding balance',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              Text(formatMoney(amount),
                  style: DesignType.numeric(fontSize: 15)),
            ]),
          ),
          const SizedBox(height: DesignSpacing.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.receipt_long_rounded),
            title: const Text('Record cash received'),
            subtitle: const Text('Enter the cash collected from the customer'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.pop(sheetContext, 0),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.phone_android_rounded,
                color: DesignColors.brand),
            title: const Text('Request M-Pesa payment'),
            subtitle:
                const Text('Send a verified Paystack prompt to the payer'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.pop(sheetContext, 1),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 0) {
      await onRecordReceived();
    } else if (choice == 1) {
      await _showMerchantReceivablePaymentSheet(
        title: title,
        amount: amount,
        receivableId: receivableId,
        receivableType: receivableType,
        branchId: branchId,
        controller: controller,
      );
    }
  }

  Future<void> _showMerchantReceivablePaymentSheet({
    required String title,
    required double amount,
    required String receivableId,
    required String receivableType,
    required String branchId,
    required FinanceHubController controller,
  }) async {
    final formKey = GlobalKey<FormState>();
    final shopName = ref.read(tenantIdentityProvider).companyName;
    final amountController =
        TextEditingController(text: amount.toStringAsFixed(2));
    final phoneController = TextEditingController();
    String? error;
    bool saving = false;
    await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Form(
          key: formKey,
          child: _SheetFrame(
            title: 'Request M-Pesa payment',
            children: [
              Text(
                '$title · ${formatMoney(amount)} outstanding',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: DesignSpacing.sm),
              Text(
                'This request is for $shopName. The Paystack M-Pesa prompt may show “PAYSTACK Account no. Counterbase.” That is Paystack’s prompt label, not the shop bank account number. The debt changes only after Paystack verifies the payment.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(height: 1.4),
              ),
              const SizedBox(height: DesignSpacing.md),
              TextFormField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount to collect (KES)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final entered = double.tryParse(value?.trim() ?? '');
                  if (entered == null || entered < 3) {
                    return 'Enter at least KES 3';
                  }
                  if (entered > amount) {
                    return 'Amount exceeds the outstanding balance';
                  }
                  return null;
                },
              ),
              const SizedBox(height: DesignSpacing.md),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Payer phone number',
                  hintText: '712 345 678',
                  prefixText: '+254 ',
                  prefixIcon: Icon(Icons.phone_android_rounded),
                ),
                validator: (value) => _isKenyanPhone(value ?? '')
                    ? null
                    : 'Enter a valid Kenyan mobile number',
              ),
              if (error != null) ...[
                const SizedBox(height: DesignSpacing.md),
                Text(error!, style: const TextStyle(color: DesignColors.error)),
              ],
              const SizedBox(height: DesignSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: DesignSpacing.huge,
                child: FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setSheetState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            final result = await controller
                                .startMerchantReceivablePayment({
                              'requestId': const Uuid().v4(),
                              'receivableType': receivableType,
                              'receivableId': receivableId,
                              'branchId': branchId,
                              'amount':
                                  double.parse(amountController.text.trim()),
                              'phoneNumber':
                                  _normalizeKenyanPhone(phoneController.text),
                            });
                            if (!sheetContext.mounted) return;
                            Navigator.pop(sheetContext, true);
                            if (mounted) {
                              await _showMerchantPaymentStatus(
                                result,
                                controller,
                              );
                            }
                          } catch (e) {
                            final message = _financeRequestError(e);
                            if (message.toLowerCase().contains(
                                'set up your business payout account')) {
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                              if (mounted) {
                                context.push('/payments/setup');
                              }
                            } else if (sheetContext.mounted) {
                              setSheetState(() => error = message);
                            }
                          } finally {
                            if (sheetContext.mounted) {
                              setSheetState(() => saving = false);
                            }
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label:
                      Text(saving ? 'Sending request…' : 'Send M-Pesa request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    amountController.dispose();
    phoneController.dispose();
  }

  Future<void> _showMerchantPaymentStatus(
    Map<String, dynamic> initial,
    FinanceHubController controller,
  ) async {
    var status = initial['status']?.toString() ?? 'PENDING';
    var checking = false;
    String? error;
    final reference = initial['reference']?.toString() ?? '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final completed = status == 'COMPLETED';
          final failed = status == 'FAILED';
          return AlertDialog(
            icon: Icon(
              completed
                  ? Icons.check_circle_rounded
                  : failed
                      ? Icons.error_rounded
                      : Icons.phone_android_rounded,
              color: completed
                  ? DesignColors.success
                  : failed
                      ? DesignColors.error
                      : DesignColors.brand,
              size: 34,
            ),
            title: Text(completed
                ? 'Debt payment received'
                : failed
                    ? 'Payment not completed'
                    : 'Waiting for M-Pesa payment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(completed
                    ? 'Paystack confirmed the payment and the outstanding balance has been updated.'
                    : failed
                        ? 'The payer did not complete this payment. The debt remains open.'
                        : 'Ask the payer to approve the prompt on their phone. The debt will update after Paystack confirms it.'),
                const SizedBox(height: DesignSpacing.md),
                SelectableText('Reference: $reference'),
                if (error != null) ...[
                  const SizedBox(height: DesignSpacing.sm),
                  Text(error!,
                      style: const TextStyle(color: DesignColors.error)),
                ],
              ],
            ),
            actions: [
              if (completed || failed)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Done'),
                )
              else ...[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: checking
                      ? null
                      : () async {
                          setDialogState(() {
                            checking = true;
                            error = null;
                          });
                          try {
                            final result = await controller
                                .getMerchantPaymentStatus(reference);
                            status = result['status']?.toString() ?? 'PENDING';
                            if (status == 'COMPLETED') {
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                              await controller.refresh();
                              if (mounted) {
                                showGlassSnackBar(
                                  context,
                                  'M-Pesa payment verified. The debt balance is updated.',
                                  icon: Icons.check_circle_rounded,
                                  color: DesignColors.success,
                                );
                              }
                            } else if (dialogContext.mounted) {
                              setDialogState(() {});
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              setDialogState(
                                  () => error = _financeRequestError(e));
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => checking = false);
                            }
                          }
                        },
                  child: Text(checking ? 'Checking…' : 'Check payment'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _showSupplierDetailsSheet(
    FinancePayable payable,
    FinanceHubController controller, {
    required bool canRecordPayment,
  }) async {
    final formKey = GlobalKey<FormState>();
    final amount = TextEditingController(
        text: payable.outstandingAmount.toStringAsFixed(2));
    final notes = TextEditingController();
    String fundingSource = 'CASH_TILL';
    String? error;
    bool saving = false;
    await showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Form(
          key: formKey,
          child: _SheetFrame(
            title: tidySupplierName(payable.supplierName),
            children: [
              Text(payable.invoiceNumber ?? 'Supplier invoice',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: DesignSpacing.md),
              _InvoiceBalanceSummary(payable: payable),
              if (payable.payments.isNotEmpty) ...[
                const SizedBox(height: DesignSpacing.lg),
                Text('Payment history',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: DesignSpacing.xs),
                for (final payment in payable.payments.take(4))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.check_circle_outline_rounded,
                        color: DesignColors.success),
                    title: Text(formatMoney(payment.amount)),
                    subtitle: Text(
                      '${payment.fundingSource == 'CASH_TILL' ? 'Cash till' : 'Bank / M-Pesa'}'
                      '${payment.paidAt == null ? '' : ' · ${DateFormat('d MMM y').format(payment.paidAt!.toLocal())}'}'
                      '${payment.notes == null || payment.notes!.isEmpty ? '' : '\n${payment.notes}'}',
                    ),
                  ),
              ],
              if (canRecordPayment && payable.outstandingAmount > 0) ...[
                const Divider(height: DesignSpacing.xxl),
                Text('Record a supplier payment',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: DesignSpacing.xs),
                Text(
                  'This records a transfer you have already made. Counterbase does not send money to the supplier.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(height: 1.4),
                ),
                const SizedBox(height: DesignSpacing.md),
                SegmentedButton<String>(
                  expandedInsets: EdgeInsets.zero,
                  segments: const [
                    ButtonSegment(value: 'CASH_TILL', label: Text('Cash till')),
                    ButtonSegment(
                        value: 'BANK_OR_MPESA', label: Text('Bank / M-Pesa')),
                  ],
                  selected: {fundingSource},
                  onSelectionChanged: saving
                      ? null
                      : (value) =>
                          setSheetState(() => fundingSource = value.first),
                ),
                const SizedBox(height: DesignSpacing.md),
                TextFormField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount paid (KES)',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Enter an amount greater than zero';
                    }
                    if (parsed > payable.outstandingAmount) {
                      return 'Amount exceeds the outstanding balance';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: DesignSpacing.md),
                TextFormField(
                  controller: notes,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Transfer reference or note (optional)',
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: DesignSpacing.sm),
                  Text(error!,
                      style: const TextStyle(color: DesignColors.error)),
                ],
                const SizedBox(height: DesignSpacing.md),
                SizedBox(
                  width: double.infinity,
                  height: DesignSpacing.huge,
                  child: FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheetState(() {
                              saving = true;
                              error = null;
                            });
                            try {
                              await controller.recordSupplierPayment(
                                invoiceId: payable.id,
                                amount: double.parse(amount.text.trim()),
                                fundingSource: fundingSource,
                                requestId: const Uuid().v4(),
                                notes: notes.text.trim(),
                              );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                              if (mounted) {
                                showGlassSnackBar(
                                  context,
                                  'Supplier payment recorded. Balance updated.',
                                  icon: Icons.check_circle_rounded,
                                  color: DesignColors.success,
                                );
                              }
                            } catch (e) {
                              if (sheetContext.mounted) {
                                setSheetState(
                                    () => error = _financeRequestError(e));
                              }
                            } finally {
                              if (sheetContext.mounted) {
                                setSheetState(() => saving = false);
                              }
                            }
                          },
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(saving ? 'Saving…' : 'Record payment'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    amount.dispose();
    notes.dispose();
  }

  /// One payment from a customer, split across their open credits (oldest due first).
  Future<void> _showBulkCollectionSheet(
    FinanceSnapshot snapshot,
    FinanceHubController controller,
  ) async {
    final groups = <String, List<RetailReceivable>>{};
    for (final item in snapshot.retailReceivables) {
      if (item.outstandingAmount <= 0) continue;
      groups
          .putIfAbsent(item.customerId ?? item.customerName ?? '', () => [])
          .add(item);
    }
    if (groups.isEmpty) return;

    String selectedKey = groups.keys.first;
    double totalFor(String key) =>
        groups[key]!.fold(0, (sum, r) => sum + r.outstandingAmount);
    final amountController =
        TextEditingController(text: totalFor(selectedKey).toStringAsFixed(0));
    final reference = TextEditingController();
    // Fixed for this sheet so a retry after a dropped connection cannot pay twice.
    final offlineId = 'bulk-${DateTime.now().microsecondsSinceEpoch}';
    String? error;
    bool saving = false;

    await showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final items = groups[selectedKey]!;
          final amount = double.tryParse(amountController.text) ?? 0;
          final plan = allocateOldestFirst(items, amount);
          String nameOf(List<RetailReceivable> list) =>
              list.first.customerName ?? 'No customer';
          return _SheetFrame(
            title: 'Collect for a customer',
            children: <Widget>[
              DropdownButtonFormField<String>(
                key: const ValueKey('bulk-customer'),
                initialValue: selectedKey,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Customer'),
                items: groups.entries
                    .map((entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(
                            '${nameOf(entry.value)} · ${formatMoney(totalFor(entry.key))}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setSheetState(() {
                          selectedKey = value ?? selectedKey;
                          amountController.text =
                              totalFor(selectedKey).toStringAsFixed(0);
                          error = null;
                        }),
              ),
              const SizedBox(height: DesignSpacing.md),
              const Text(
                'Record cash already received. For M-Pesa, request payment '
                'on each debt so Paystack can verify and settle it.',
              ),
              const SizedBox(height: DesignSpacing.md),
              TextField(
                key: const ValueKey('bulk-amount'),
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setSheetState(() => error = null),
                decoration: InputDecoration(
                    labelText: 'Collected (KES)', errorText: error),
              ),
              const SizedBox(height: DesignSpacing.sm),
              Text(
                amount <= 0
                    ? 'Enter the amount the customer paid.'
                    : 'Settles ${plan.allocations.length} of ${items.length} '
                        'credit${items.length == 1 ? '' : 's'}, oldest due first',
                key: const ValueKey('bulk-preview'),
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: DesignSpacing.md),
              TextField(
                  controller: reference,
                  decoration:
                      const InputDecoration(labelText: 'Reference (optional)')),
              const SizedBox(height: DesignSpacing.xl),
              _sheetButton(saving ? 'Recording…' : 'Record collection',
                  () async {
                if (saving) return;
                if (amount <= 0) {
                  setSheetState(
                      () => error = 'Amount must be greater than zero');
                  return;
                }
                if (plan.unallocated > 0) {
                  setSheetState(() => error =
                      'More than the customer owes (${formatMoney(totalFor(selectedKey))})');
                  return;
                }
                setSheetState(() => saving = true);
                try {
                  await controller.recordRetailBulkCollection(
                    BulkCollectionRequest(
                      branchId: snapshot.branchId,
                      allocations: plan.allocations,
                      method: 'CASH',
                      reference: reference.text.trim().isEmpty
                          ? null
                          : reference.text.trim(),
                      offlineId: offlineId,
                    ),
                  );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                } catch (e) {
                  if (!sheetContext.mounted) return;
                  setSheetState(() {
                    saving = false;
                    error = e is FinanceFormException
                        ? e.message
                        : 'Couldn’t record the collection. Check your connection and try again.';
                  });
                }
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _sheetButton(String label, Future<void> Function() action) => SizedBox(
        width: double.infinity,
        height: DesignSpacing.huge,
        child: FilledButton(onPressed: action, child: Text(label)),
      );
}

class _NoSnapshotState extends StatelessWidget {
  const _NoSnapshotState({required this.state, required this.onRetry});
  final FinanceHubState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isRefreshing) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
        child: Padding(
      padding: DesignSpacing.paddingScreen,
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const Icon(Icons.cloud_off_rounded,
            color: DesignColors.error, size: 40),
        const SizedBox(height: DesignSpacing.md),
        Text(state.errorMessage ?? 'Couldn’t load Finance.',
            textAlign: TextAlign.center),
        const SizedBox(height: DesignSpacing.md),
        SizedBox(
            height: DesignSpacing.huge,
            child:
                FilledButton(onPressed: onRetry, child: const Text('Retry'))),
      ]),
    ));
  }
}

class _FinanceStatusBar extends StatelessWidget {
  const _FinanceStatusBar({required this.state, required this.onRetry});
  final FinanceHubState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final savedAt = state.snapshot?.savedAt;
    return Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
            DesignSpacing.lg, DesignSpacing.sm, DesignSpacing.lg, 0),
        child: Row(children: <Widget>[
          Icon(state.isRefreshing ? Icons.sync_rounded : Icons.history_rounded,
              size: 16, color: DesignColors.textSecondary),
          const SizedBox(width: DesignSpacing.xs),
          Text(
              state.isRefreshing
                  ? 'Refreshing'
                  : savedAt == null
                      ? 'Saved figures'
                      : 'Saved ${DateFormat('d MMM, HH:mm').format(savedAt.toLocal())}',
              style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
      if (state.errorMessage != null)
        Container(
          margin: const EdgeInsets.fromLTRB(
              DesignSpacing.lg, DesignSpacing.sm, DesignSpacing.lg, 0),
          padding: const EdgeInsets.symmetric(
              horizontal: DesignSpacing.md, vertical: DesignSpacing.sm),
          decoration: BoxDecoration(
              color: DesignColors.warning.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd)),
          child: Row(children: <Widget>[
            const Icon(Icons.wifi_off_rounded,
                size: 18, color: DesignColors.warning),
            const SizedBox(width: DesignSpacing.sm),
            Expanded(
                child: Text(state.errorMessage!,
                    style: Theme.of(context).textTheme.labelSmall)),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
    ]);
  }
}

class _FinanceTabs extends StatelessWidget {
  const _FinanceTabs({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;
  static const List<String> labels = <String>[
    'Overview',
    'Suppliers',
    'Customers',
    'Shops'
  ];

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.md,
            DesignSpacing.lg, DesignSpacing.sm),
        // Wrap (not a sideways scroller) so every tab is visible at once, even
        // on a narrow phone or with large text.
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: DesignSpacing.sm,
            children: List<Widget>.generate(
              labels.length,
              (i) => ChoiceChip(
                label: Text(labels[i]),
                selected: index == i,
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                onSelected: (_) => onChanged(i),
              ),
            ),
          ),
        ),
      );
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.snapshot});
  final FinanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Only balances still outstanding can be overdue; a settled debt keeps its
    // old due date but is nothing to chase.
    final overdue = <DateTime?>[
      ...snapshot.payables
          .where((item) => item.outstandingAmount > 0)
          .map((item) => item.dueDate),
      ...snapshot.retailReceivables
          .where((item) => item.outstandingAmount > 0)
          .map((item) => item.dueDate),
      ...snapshot.peerReceivables
          .where((item) => item.outstandingAmount > 0)
          .map((item) => item.dueDate),
    ]
        .where((date) =>
            date?.isBefore(DateTime(now.year, now.month, now.day)) ?? false)
        .length;
    final net = snapshot.retailReceivablesOutstanding +
        snapshot.peerReceivablesOutstanding;
    // A proper 2-column dashboard grid (Row of paired Expanded cards inside
    // a Column) instead of one full-width card stacked under the next —
    // the four related totals read as a single grouped panel, not a list.
    return ListView(
      padding: DesignSpacing.paddingScreen,
      children: <Widget>[
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _MetricCard(
                  label: 'We owe suppliers',
                  value: snapshot.supplierPayablesOutstanding,
                  color: DesignColors.error,
                ),
              ),
              const SizedBox(width: DesignSpacing.sm),
              Expanded(
                child: _MetricCard(
                  label: 'Customers owe us',
                  value: snapshot.retailReceivablesOutstanding,
                  color: DesignColors.info,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DesignSpacing.sm),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _MetricCard(
                  label: 'Other shops owe us',
                  value: snapshot.peerReceivablesOutstanding,
                  color: DesignColors.brand,
                ),
              ),
              const SizedBox(width: DesignSpacing.sm),
              Expanded(
                child: _MetricCard(
                  label: 'Total owed to us',
                  value: net,
                  color: DesignColors.success,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DesignSpacing.sm),
        _CountCard(overdue: overdue),
        const SizedBox(height: DesignSpacing.lg),
        _CollectionsFeed(snapshot: snapshot),
      ],
    );
  }
}

/// "Collected today" plus the latest money received from customers and shops,
/// so the owner can see what came in and when without opening each ledger.
class _CollectionsFeed extends StatelessWidget {
  const _CollectionsFeed({required this.snapshot});
  final FinanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = mergeInstalments(allCollections(snapshot));
    final today = startOfDay(DateTime.now());
    final todayTotal = collectedBetween(all, today);
    final weekTotal =
        collectedBetween(all, today.subtract(const Duration(days: 6)));
    final recent = all.take(6).toList();
    final success = context.readable(DesignColors.success);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GlassCard(
          padding: const EdgeInsets.all(DesignSpacing.lg),
          borderRadius: DesignSpacing.radiusLg,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Collected today', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 2),
                    CountUpText(formatMoney(todayTotal),
                        style: DesignType.numeric(fontSize: 26)
                            .copyWith(color: success)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text('Last 7 days', style: theme.textTheme.labelSmall),
                  Text(formatMoney(weekTotal),
                      style: DesignType.numeric(fontSize: 16)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: DesignSpacing.lg),
        Text('Recent collections', style: theme.textTheme.titleSmall),
        const SizedBox(height: DesignSpacing.sm),
        if (recent.isEmpty)
          const _EmptyLedger(
              message: 'Nothing collected yet. Payments from customers and '
                  'shops will show up here.')
        else
          for (var i = 0; i < recent.length; i++)
            FadeSlideIn(
              delay: Duration(milliseconds: 50 * i),
              child: Padding(
                padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: DesignSpacing.lg, vertical: DesignSpacing.md),
                  borderRadius: DesignSpacing.radiusMd,
                  child: Row(children: <Widget>[
                    Icon(
                        recent[i].isShop
                            ? Icons.storefront_rounded
                            : Icons.person_rounded,
                        color: DesignColors.brand),
                    const SizedBox(width: DesignSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(recent[i].who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall),
                          Text(
                              '${_whenLabel(recent[i].paidAt)} · ${paymentMethodLabel(recent[i].method)}',
                              style: theme.textTheme.labelSmall),
                        ],
                      ),
                    ),
                    Text('+${formatMoney(recent[i].amount)}',
                        style: DesignType.numeric(fontSize: 14)
                            .copyWith(color: success)),
                  ]),
                ),
              ),
            ),
      ],
    );
  }
}

String _whenLabel(DateTime d) {
  final today = startOfDay(DateTime.now());
  final diff = today.difference(startOfDay(d)).inDays;
  final time = DateFormat('h:mm a').format(d);
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Yesterday, $time';
  return '${DateFormat('d MMM').format(d)}, $time';
}

String _normalizeKenyanPhone(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (digits.startsWith('254')) {
    digits = digits.substring(3);
  }
  return '254$digits';
}

bool _isKenyanPhone(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 9) {
    return digits.startsWith('7') || digits.startsWith('1');
  }
  if (digits.length == 10) {
    return digits.startsWith('07') || digits.startsWith('01');
  }
  return digits.length == 12 &&
      digits.startsWith('254') &&
      (digits[3] == '7' || digits[3] == '1');
}

String _financeRequestError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    final message = data is Map ? data['message'] : null;
    if (message is List && message.isNotEmpty) return message.join(', ');
    if (message != null) return message.toString();
  }
  return 'Could not complete this finance action. Check your connection and try again.';
}

class _SupplierTab extends StatelessWidget {
  const _SupplierTab(
      {required this.payables,
      required this.canCreateInvoices,
      required this.onScan,
      required this.onManual,
      required this.onOpenPayable});
  final List<FinancePayable> payables;
  final bool canCreateInvoices;
  final VoidCallback? onScan;
  final VoidCallback? onManual;
  final ValueChanged<FinancePayable> onOpenPayable;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: DesignSpacing.paddingScreen, children: <Widget>[
        if (canCreateInvoices) ...[
          Row(children: <Widget>[
            Expanded(
                child: SizedBox(
                    height: DesignSpacing.huge,
                    child: FilledButton.icon(
                        onPressed: onScan,
                        icon: const Icon(Icons.document_scanner_rounded),
                        label: const Text('Scan Receipt')))),
            const SizedBox(width: DesignSpacing.sm),
            SizedBox(
                height: DesignSpacing.huge,
                child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(96, DesignSpacing.huge)),
                    onPressed: onManual,
                    child: const Text('Manual'))),
          ]),
          const SizedBox(height: DesignSpacing.lg),
        ],
        if (payables.isEmpty)
          const _EmptyLedger(message: 'No supplier payables yet.')
        else
          ...payables.map((item) => _LedgerCard(
                title: tidySupplierName(item.supplierName),
                subtitle: item.invoiceNumber ?? 'Supplier invoice',
                value: item.outstandingAmount,
                dueDate: item.dueDate,
                icon: Icons.business_rounded,
                action: 'Details',
                onAction: () => onOpenPayable(item),
              )),
      ]);
}

class _RetailTab extends StatelessWidget {
  const _RetailTab({
    required this.receivables,
    required this.canManageReceivables,
    required this.onCollect,
    required this.onCollectForCustomer,
  });
  final List<RetailReceivable> receivables;
  final bool canManageReceivables;
  final ValueChanged<RetailReceivable> onCollect;
  final VoidCallback onCollectForCustomer;

  @override
  Widget build(BuildContext context) {
    // Settled credits (balance 0) stay on the server for history but offering
    // "Collect" on a KES 0 balance is just noise.
    final open = receivables.where((r) => r.outstandingAmount > 0).toList();
    return ListView(padding: DesignSpacing.paddingScreen, children: <Widget>[
      if (open.isEmpty)
        const _EmptyLedger(message: 'No customer credit is outstanding.')
      else ...<Widget>[
        if (canManageReceivables)
          SizedBox(
            height: DesignSpacing.huge,
            child: FilledButton.icon(
              onPressed: onCollectForCustomer,
              icon: const Icon(Icons.payments_rounded),
              label: const Text('Collect for a customer'),
            ),
          ),
        if (canManageReceivables) const SizedBox(height: DesignSpacing.md),
        ...open.map((item) => _LedgerCard(
              title: item.receiptNumber ?? 'Receipt',
              subtitle: item.customerName ?? 'Customer',
              value: item.outstandingAmount,
              dueDate: item.dueDate,
              icon: Icons.person_rounded,
              action: canManageReceivables ? 'Collect' : null,
              onAction: canManageReceivables ? () => onCollect(item) : null,
            )),
      ],
    ]);
  }
}

class _PeerTab extends StatelessWidget {
  const _PeerTab(
      {required this.snapshot,
      required this.canManageReceivables,
      required this.onAddShop,
      required this.onAddReceivable,
      required this.onCollect,
      required this.onOpenShop});
  final FinanceSnapshot snapshot;
  final bool canManageReceivables;
  final VoidCallback onAddShop;
  final VoidCallback onAddReceivable;
  final ValueChanged<PeerReceivable> onCollect;
  final ValueChanged<PeerDebtor> onOpenShop;

  @override
  Widget build(BuildContext context) {
    final today = startOfDay(DateTime.now());
    final shopEntries = allCollections(snapshot).where((e) => e.isShop);
    final collectedToday = collectedBetween(shopEntries, today);
    final collectedMonth =
        collectedBetween(shopEntries, DateTime(today.year, today.month));
    // Shops that still owe something come first, biggest balance on top.
    final shops = [...snapshot.peerDebtors]..sort((a, b) =>
        shopOutstanding(snapshot, b).compareTo(shopOutstanding(snapshot, a)));
    return ListView(padding: DesignSpacing.paddingScreen, children: <Widget>[
      FadeSlideIn(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                  child: _MetricCard(
                      label: 'Shops owe us',
                      value: snapshot.peerReceivablesOutstanding,
                      color: DesignColors.brand)),
              const SizedBox(width: DesignSpacing.sm),
              Expanded(
                  child: _MetricCard(
                      label: 'Collected today',
                      value: collectedToday,
                      color: DesignColors.success)),
            ],
          ),
        ),
      ),
      if (collectedMonth > 0) ...<Widget>[
        const SizedBox(height: DesignSpacing.xs),
        Text('${formatMoney(collectedMonth)} collected this month',
            style: Theme.of(context).textTheme.labelSmall),
      ],
      const SizedBox(height: DesignSpacing.lg),
      if (canManageReceivables) ...[
        Row(children: <Widget>[
          Expanded(
              child: SizedBox(
                  height: DesignSpacing.huge,
                  child: OutlinedButton(
                      onPressed: onAddShop, child: const Text('Add shop')))),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
              child: SizedBox(
                  height: DesignSpacing.huge,
                  child: FilledButton(
                      onPressed: onAddReceivable,
                      child: const Text('Add debt')))),
        ]),
        const SizedBox(height: DesignSpacing.lg),
      ],
      Text('Other shops', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: DesignSpacing.sm),
      if (shops.isEmpty)
        const _EmptyLedger(message: 'No other shops added yet.')
      else
        for (var i = 0; i < shops.length; i++)
          FadeSlideIn(
            delay: Duration(milliseconds: 60 * i.clamp(0, 8)),
            child: _ShopCard(
              shop: shops[i],
              statement: shopStatement(snapshot, shops[i]),
              onTap: () => onOpenShop(shops[i]),
            ),
          ),
      const SizedBox(height: DesignSpacing.lg),
      Text('Open debts', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: DesignSpacing.sm),
      if (snapshot.peerReceivables.every((r) => r.outstandingAmount <= 0))
        const _EmptyLedger(message: 'No other-shop debts yet.')
      else
        ...snapshot.peerReceivables
            .where((r) => r.outstandingAmount > 0)
            .map((item) => _LedgerCard(
                  title: item.debtor.name,
                  subtitle: item.description,
                  value: item.outstandingAmount,
                  dueDate: item.dueDate,
                  icon: Icons.storefront_rounded,
                  action: canManageReceivables ? 'Collect' : null,
                  onAction: canManageReceivables ? () => onCollect(item) : null,
                )),
    ]);
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: DesignSpacing.paddingCard,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: DesignSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    FinanceScreen.currencyFmt.format(value),
                    style: DesignType.numeric(
                        fontSize: 20, color: context.readable(color)),
                  ),
                ),
              ])));
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.overdue});
  final int overdue;
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          minTileHeight: DesignSpacing.huge,
          leading: Wiggle(
              child: Icon(Icons.event_busy_rounded,
                  color: context.readable(DesignColors.warning))),
          title: const Text('Overdue'),
          trailing: Text('$overdue',
              style: DesignType.numeric(
                  fontSize: 22,
                  color: context.readable(DesignColors.warning)))));
}

class _LedgerCard extends StatelessWidget {
  const _LedgerCard(
      {required this.title,
      required this.subtitle,
      required this.value,
      required this.dueDate,
      required this.icon,
      this.action,
      this.onAction});
  final String title;
  final String subtitle;
  final double value;
  final DateTime? dueDate;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: Padding(
          padding: DesignSpacing.paddingCard,
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: DesignColors.brand),
                const SizedBox(width: DesignSpacing.md),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (dueDate != null)
                        // Past-due balances are what the owner needs to chase,
                        // so make them stand out instead of reading like any
                        // other date.
                        Builder(builder: (context) {
                          final today = DateTime.now();
                          final isOverdue = value > 0 &&
                              dueDate!.toLocal().isBefore(
                                  DateTime(today.year, today.month, today.day));
                          final label =
                              'Due ${DateFormat('d MMM y').format(dueDate!.toLocal())}';
                          return Text(
                            isOverdue ? 'Overdue · $label' : label,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: isOverdue ? DesignColors.error : null,
                                  fontWeight:
                                      isOverdue ? FontWeight.w700 : null,
                                ),
                          );
                        }),
                    ])),
                const SizedBox(width: DesignSpacing.sm),
                SizedBox(
                  width: 96,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(FinanceScreen.currencyFmt.format(value),
                              style: DesignType.numeric(fontSize: 14)),
                        ),
                        if (action != null)
                          SizedBox(
                              height: DesignSpacing.huge,
                              child: TextButton(
                                  onPressed: onAction,
                                  child: Text(action!,
                                      overflow: TextOverflow.ellipsis))),
                      ]),
                ),
              ])));
}

class _ShopCard extends StatelessWidget {
  const _ShopCard(
      {required this.shop, required this.statement, required this.onTap});
  final PeerDebtor shop;
  final ShopStatement statement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDebt = statement.originalTotal > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: TapScale(
        child: GlassCard(
          onTap: onTap,
          padding: const EdgeInsets.all(DesignSpacing.lg),
          borderRadius: DesignSpacing.radiusMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                const Icon(Icons.store_rounded, color: DesignColors.brand),
                const SizedBox(width: DesignSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(shop.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall),
                      Text(
                          hasDebt
                              ? (statement.isSettled
                                  ? 'Fully paid'
                                  : 'Owes ${formatMoney(statement.outstanding)}')
                              : 'No debts yet',
                          style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ]),
              if (hasDebt) ...<Widget>[
                const SizedBox(height: DesignSpacing.md),
                AnimatedProgressBar(
                  value: statement.progress,
                  height: 6,
                  color: statement.isSettled
                      ? DesignColors.success
                      : DesignColors.accent,
                ),
                const SizedBox(height: DesignSpacing.xs),
                Text(
                    '${formatMoney(statement.paid)} of ${formatMoney(statement.originalTotal)} paid back',
                    style: theme.textTheme.labelSmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(DesignSpacing.xl),
      child: Text(message, textAlign: TextAlign.center));
}

class _InvoiceBalanceSummary extends StatelessWidget {
  const _InvoiceBalanceSummary({required this.payable});
  final FinancePayable payable;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(DesignSpacing.md),
        decoration: BoxDecoration(
          color: DesignColors.brand.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          border: Border.all(color: DesignColors.brand.withValues(alpha: 0.12)),
        ),
        child: Row(children: [
          Expanded(
              child:
                  _InvoiceAmount(label: 'Invoice', value: payable.totalAmount)),
          Expanded(
              child: _InvoiceAmount(label: 'Paid', value: payable.paidAmount)),
          Expanded(
            child: _InvoiceAmount(
              label: 'Due',
              value: payable.outstandingAmount,
              emphasize: true,
            ),
          ),
        ]),
      );
}

class _InvoiceAmount extends StatelessWidget {
  const _InvoiceAmount({
    required this.label,
    required this.value,
    this.emphasize = false,
  });
  final String label;
  final double value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              FinanceScreen.currencyFmt.format(value),
              style: DesignType.numeric(
                fontSize: 13,
                color: emphasize ? DesignColors.warning : null,
              ),
            ),
          ),
        ],
      );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
          child: Padding(
        padding: EdgeInsets.fromLTRB(
            DesignSpacing.xl,
            DesignSpacing.sm,
            DesignSpacing.xl,
            MediaQuery.viewInsetsOf(context).bottom + DesignSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: DesignSpacing.lg),
                  // Fields rise in one after another instead of the sheet
                  // appearing as a single block.
                  for (var i = 0; i < children.length; i++)
                    FadeSlideIn(
                      distance: 10,
                      delay: Duration(milliseconds: 45 * i.clamp(0, 8)),
                      child: children[i],
                    ),
                ]),
          ),
        ),
      ));
}

/// Full-body "Axon AI is reading your receipt" state shown while a photo is
/// being scanned: the photo itself with a sweeping scan line over it, so the
/// wait feels like the AI is actually looking at the receipt.
class _AiScanOverlay extends StatefulWidget {
  const _AiScanOverlay({this.imagePath});

  final String? imagePath;

  @override
  State<_AiScanOverlay> createState() => _AiScanOverlayState();
}

class _AiScanOverlayState extends State<_AiScanOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.imagePath;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(DesignSpacing.lg),
          decoration: BoxDecoration(
            color: context.themed(DesignColors.darkSurface),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
            boxShadow: DesignShadows.soft(
                Theme.of(context).brightness == Brightness.dark),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                child: SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (path != null)
                        Image.file(File(path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink()),
                      AnimatedBuilder(
                        animation: _sweep,
                        builder: (context, _) => Align(
                          alignment: Alignment(0, -1 + 2 * _sweep.value),
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: DesignColors.accent,
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: DesignColors.accent
                                      .withValues(alpha: 0.7),
                                  blurRadius: 14,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: DesignSpacing.lg),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.auto_awesome_rounded,
                      color: DesignColors.accent, size: 18),
                  const SizedBox(width: DesignSpacing.sm),
                  Flexible(
                    child: Text(
                      'Axon AI is reading your receipt',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: context.themed(DesignColors.darkTextPrimary),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignSpacing.xs),
              Text(
                'Checking it is a receipt, then picking out the supplier and items.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.themed(DesignColors.darkTextSecondary),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
