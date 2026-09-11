import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/receipt_vision_service.dart';
import '../../../../core/services/supplier_receipt_ocr_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../domain/finance_models.dart';
import '../providers/finance_hub_controller.dart';
import 'invoice_review_screen.dart';

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
    final snapshot = hub.snapshot;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Finance',
        showBackButton: false,
        actions: <Widget>[
          _appBarAction(
            tooltip: 'Cash Flow',
            icon: const Icon(Icons.point_of_sale_rounded),
            onPressed: () => context.push('/cash-flow'),
          ),
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
      body: SafeArea(
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
                  Expanded(child: _tabBody(snapshot, controller)),
                ],
              ),
      ),
    );
  }

  Widget _tabBody(FinanceSnapshot snapshot, FinanceHubController controller) =>
      switch (_tab) {
        0 => _OverviewTab(snapshot: snapshot),
        1 => _SupplierTab(
            payables: snapshot.payables,
            onScan: _pickAndScanReceipt,
            onManual: _showManualInvoiceDialog,
          ),
        2 => _RetailTab(
            receivables: snapshot.retailReceivables,
            onCollect: (item) => _showCollectionSheet(
              title: 'Collect from ${item.customerName ?? 'customer'}',
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
        _ => _PeerTab(
            snapshot: snapshot,
            onAddShop: () => _showPeerShopSheet(controller),
            onAddReceivable: () =>
                _showPeerReceivableSheet(snapshot, controller),
            onCollect: (item) => _showCollectionSheet(
              title: 'Collect from ${item.debtor.name}',
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
    setState(() => _isScanning = true);
    try {
      final scan = getIt<ConnectivityService>().isOnline
          ? await getIt<ReceiptVisionService>().scan(
              imageUrl: (await getIt<ApiClient>().uploadImage(
                filePath: image.path,
                fileName: image.name,
                type: 'supplier-invoice',
              ))['url'] as String,
              branchId: ref.read(financeHubProvider).snapshot?.branchId ?? '',
            )
          : await _ocr.scan(File(image.path));
      if (mounted) await _openInvoiceReview(scan);
    } catch (_) {
      final scan = await _ocr.scan(File(image.path));
      if (mounted) await _openInvoiceReview(scan);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _showPeerShopSheet(FinanceHubController controller) async {
    final name = TextEditingController();
    final contact = TextEditingController();
    String? error;
    await showModalBottomSheet<void>(
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
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => _SheetFrame(
          title: 'Add receivable',
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
    String method = 'CASH';
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => _SheetFrame(
          title: title,
          children: <Widget>[
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment(value: 'CASH', label: Text('Cash')),
                ButtonSegment(value: 'MPESA', label: Text('M-Pesa')),
                ButtonSegment(value: 'CARD', label: Text('Card')),
              ],
              selected: <String>{method},
              onSelectionChanged: (value) =>
                  setSheetState(() => method = value.first),
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
              await onSave(parsed, method,
                  reference.text.trim().isEmpty ? null : reference.text.trim());
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            }),
          ],
        ),
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
              color: DesignColors.warningSubtle,
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
    'Customer Credit',
    'Other Shops'
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.md,
            DesignSpacing.lg, DesignSpacing.sm),
        child: Row(
            children: List<Widget>.generate(
                labels.length,
                (i) => Padding(
                      padding: EdgeInsets.only(
                          right: i == labels.length - 1 ? 0 : DesignSpacing.sm),
                      child: SizedBox(
                          height: DesignSpacing.huge,
                          child: ChoiceChip(
                            label: Text(labels[i]),
                            selected: index == i,
                            onSelected: (_) => onChanged(i),
                          )),
                    ))),
      );
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.snapshot});
  final FinanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final overdue = <DateTime?>[
      ...snapshot.payables.map((item) => item.dueDate),
      ...snapshot.retailReceivables.map((item) => item.dueDate),
      ...snapshot.peerReceivables.map((item) => item.dueDate),
    ]
        .where((date) =>
            date?.isBefore(DateTime(now.year, now.month, now.day)) ?? false)
        .length;
    final net = snapshot.retailReceivablesOutstanding +
        snapshot.peerReceivablesOutstanding;
    return ListView(padding: DesignSpacing.paddingScreen, children: <Widget>[
      _MetricCard(
          label: 'We owe suppliers',
          value: snapshot.supplierPayablesOutstanding,
          color: DesignColors.error),
      _MetricCard(
          label: 'Customers owe us',
          value: snapshot.retailReceivablesOutstanding,
          color: DesignColors.info),
      _MetricCard(
          label: 'Other shops owe us',
          value: snapshot.peerReceivablesOutstanding,
          color: DesignColors.brand),
      _MetricCard(
          label: 'Net receivable', value: net, color: DesignColors.success),
      _CountCard(overdue: overdue),
    ]);
  }
}

class _SupplierTab extends StatelessWidget {
  const _SupplierTab(
      {required this.payables, required this.onScan, required this.onManual});
  final List<FinancePayable> payables;
  final VoidCallback onScan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: DesignSpacing.paddingScreen, children: <Widget>[
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
                  onPressed: onManual, child: const Text('Manual'))),
        ]),
        const SizedBox(height: DesignSpacing.lg),
        if (payables.isEmpty)
          const _EmptyLedger(
              message: 'No supplier payables yet. Scan a receipt to begin.')
        else
          ...payables.map((item) => _LedgerCard(
                title: item.supplierName,
                subtitle: item.invoiceNumber ?? 'Supplier invoice',
                value: item.outstandingAmount,
                dueDate: item.dueDate,
                icon: Icons.business_rounded,
              )),
      ]);
}

class _RetailTab extends StatelessWidget {
  const _RetailTab({required this.receivables, required this.onCollect});
  final List<RetailReceivable> receivables;
  final ValueChanged<RetailReceivable> onCollect;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: DesignSpacing.paddingScreen, children: <Widget>[
        if (receivables.isEmpty)
          const _EmptyLedger(message: 'No customer credit is outstanding.')
        else
          ...receivables.map((item) => _LedgerCard(
                title: item.receiptNumber ?? 'Receipt',
                subtitle: item.customerName ?? 'Customer',
                value: item.outstandingAmount,
                dueDate: item.dueDate,
                icon: Icons.person_rounded,
                action: 'Collect',
                onAction: () => onCollect(item),
              )),
      ]);
}

class _PeerTab extends StatelessWidget {
  const _PeerTab(
      {required this.snapshot,
      required this.onAddShop,
      required this.onAddReceivable,
      required this.onCollect});
  final FinanceSnapshot snapshot;
  final VoidCallback onAddShop;
  final VoidCallback onAddReceivable;
  final ValueChanged<PeerReceivable> onCollect;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: DesignSpacing.paddingScreen, children: <Widget>[
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
                      child: const Text('Add receivable')))),
        ]),
        const SizedBox(height: DesignSpacing.lg),
        Text('Other shops', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: DesignSpacing.sm),
        if (snapshot.peerDebtors.isEmpty)
          const _EmptyLedger(message: 'No other shops added yet.')
        else
          ...snapshot.peerDebtors.map((shop) => _ShopCard(shop: shop)),
        const SizedBox(height: DesignSpacing.lg),
        Text('Receivables', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: DesignSpacing.sm),
        if (snapshot.peerReceivables.isEmpty)
          const _EmptyLedger(message: 'No other-shop receivables yet.')
        else
          ...snapshot.peerReceivables.map((item) => _LedgerCard(
                title: item.debtor.name,
                subtitle: item.description,
                value: item.outstandingAmount,
                dueDate: item.dueDate,
                icon: Icons.storefront_rounded,
                action: 'Collect',
                onAction: () => onCollect(item),
              )),
      ]);
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
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: DesignSpacing.xs),
                Text(FinanceScreen.currencyFmt.format(value),
                    style: DesignType.numeric(fontSize: 22, color: color)),
              ])));
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.overdue});
  final int overdue;
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          minTileHeight: DesignSpacing.huge,
          leading:
              const Icon(Icons.event_busy_rounded, color: DesignColors.warning),
          title: const Text('Overdue'),
          trailing: Text('$overdue',
              style: DesignType.numeric(
                  fontSize: 22, color: DesignColors.warning))));
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
          child: Row(children: <Widget>[
            Icon(icon, color: DesignColors.brand),
            const SizedBox(width: DesignSpacing.md),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  Text(subtitle),
                  if (dueDate != null)
                    Text(
                        'Due ${DateFormat('d MMM y').format(dueDate!.toLocal())}',
                        style: Theme.of(context).textTheme.labelSmall),
                ])),
            Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(FinanceScreen.currencyFmt.format(value),
                      style: DesignType.numeric(fontSize: 14)),
                  if (action != null)
                    SizedBox(
                        height: DesignSpacing.huge,
                        child: TextButton(
                            onPressed: onAction, child: Text(action!))),
                ]),
          ])));
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.shop});
  final PeerDebtor shop;
  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: ListTile(
          minTileHeight: DesignSpacing.huge,
          leading: const Icon(Icons.store_rounded, color: DesignColors.brand),
          title: Text(shop.name),
          subtitle: shop.phone == null ? null : Text(shop.phone!)));
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(DesignSpacing.xl),
      child: Text(message, textAlign: TextAlign.center));
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
                  ...children
                ]),
          ),
        ),
      ));
}
