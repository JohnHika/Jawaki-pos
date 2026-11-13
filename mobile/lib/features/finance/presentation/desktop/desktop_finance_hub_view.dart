import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/desktop/desktop_facts.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/collections_ledger.dart';
import '../../domain/finance_models.dart';
import 'desktop_figures_row.dart';

/// The four panes of the Finance hub.
enum FinanceHubTab { overview, suppliers, customers, shops }

/// The Finance hub on a computer: key figures in one strip, a tab per ledger
/// (suppliers, customers, other shops), a table for each with the selected
/// record in a side panel, and an overview that puts what is overdue first.
///
/// Plain data in; the routed screen owns the providers and the sheets that
/// record money (they open as dialogs on a computer).
class DesktopFinanceHubView extends StatefulWidget {
  const DesktopFinanceHubView({
    super.key,
    required this.title,
    required this.snapshot,
    this.subtitle,
    this.headerBottom,
    this.localWorkspace = false,
    this.canRecordRestock = false,
    this.canRecordSupplierPayment = false,
    this.canManageReceivables = false,
    this.canViewCustomerDetails = false,
    this.refreshing = false,
    this.scanning = false,
    this.errorMessage,
    this.initialTab = FinanceHubTab.overview,
    this.onRefresh,
    this.onRetry,
    this.onScan,
    this.onManualInvoice,
    this.onOpenPayable,
    this.onPaySeveral,
    this.onCollectRetail,
    this.onCollectForCustomer,
    this.onOpenShop,
    this.onAddShop,
    this.onAddDebt,
    this.onCollectPeer,
    this.now,
  });

  final String title;
  final FinanceSnapshot snapshot;
  final String? subtitle;
  final Widget? headerBottom;
  final bool localWorkspace;
  final bool canRecordRestock;
  final bool canRecordSupplierPayment;
  final bool canManageReceivables;
  final bool canViewCustomerDetails;
  final bool refreshing;
  final bool scanning;

  /// Shown above the tables when the last refresh failed (saved figures stay).
  final String? errorMessage;
  final FinanceHubTab initialTab;

  final VoidCallback? onRefresh;
  final VoidCallback? onRetry;
  final VoidCallback? onScan;
  final VoidCallback? onManualInvoice;
  final ValueChanged<FinancePayable>? onOpenPayable;
  final VoidCallback? onPaySeveral;
  final ValueChanged<RetailReceivable>? onCollectRetail;
  final VoidCallback? onCollectForCustomer;
  final ValueChanged<PeerDebtor>? onOpenShop;
  final VoidCallback? onAddShop;
  final VoidCallback? onAddDebt;
  final ValueChanged<PeerReceivable>? onCollectPeer;

  /// Today, for tests. null reads the clock.
  final DateTime? now;

  @override
  State<DesktopFinanceHubView> createState() => _DesktopFinanceHubViewState();
}

class _DesktopFinanceHubViewState extends State<DesktopFinanceHubView> {
  late FinanceHubTab _tab = widget.initialTab;
  Object? _selected;

  DateTime get _today => startOfDay(widget.now ?? DateTime.now());

  FinanceSnapshot get _s => widget.snapshot;

  List<FinancePayable> get _payables => _s.payables;
  List<RetailReceivable> get _openRetail =>
      _s.retailReceivables.where((r) => r.outstandingAmount > 0).toList();
  List<PeerDebtor> get _shops => [..._s.peerDebtors]..sort((a, b) =>
      shopOutstanding(_s, b).compareTo(shopOutstanding(_s, a)));

  bool _isOverdue(DateTime? due, double outstanding) =>
      outstanding > 0 && due != null && due.toLocal().isBefore(_today);

  int get _overdueCount {
    var n = 0;
    for (final p in _payables) {
      if (_isOverdue(p.dueDate, p.outstandingAmount)) n++;
    }
    for (final r in _s.retailReceivables) {
      if (_isOverdue(r.dueDate, r.outstandingAmount)) n++;
    }
    for (final r in _s.peerReceivables) {
      if (_isOverdue(r.dueDate, r.outstandingAmount)) n++;
    }
    return n;
  }

  void _go(FinanceHubTab tab, [Object? selected]) {
    setState(() {
      _tab = tab;
      _selected = selected;
    });
  }

  @override
  void didUpdateWidget(DesktopFinanceHubView old) {
    super.didUpdateWidget(old);
    // A record that no longer exists (removed, paid off a list that hides it)
    // closes its panel.
    if (_selected != null && !_selectionExists()) _selected = null;
  }

  bool _selectionExists() {
    final id = _selected;
    return switch (_tab) {
      FinanceHubTab.overview => false,
      FinanceHubTab.suppliers => _payables.any((e) => e.id == id),
      FinanceHubTab.customers => _s.retailReceivables.any((e) => e.id == id),
      FinanceHubTab.shops => _s.peerDebtors.any((e) => e.id == id),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final short = MediaQuery.sizeOf(context).height < 640;
    final net = _s.retailReceivablesOutstanding + _s.peerReceivablesOutstanding;
    final overdue = _overdueCount;
    final negative = negativeAmountColor(p);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: widget.title,
          subtitle: short ? null : widget.subtitle,
          padding: EdgeInsets.fromLTRB(24, short ? 12 : 16, 24, 0),
          bottom: widget.headerBottom,
          actions: [
            if (widget.canRecordRestock)
              OutlinedButton.icon(
                style: desktopSecondaryButton(context),
                onPressed: widget.scanning ? null : widget.onScan,
                icon: widget.scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner_rounded, size: 17),
                label: Text(widget.scanning ? 'Scanning…' : 'Scan receipt'),
              ),
            IconButton(
              tooltip: 'Refresh finance',
              onPressed: widget.refreshing ? null : widget.onRefresh,
              icon: widget.refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        if (widget.errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
            child: _Banner(
              message: widget.errorMessage!,
              onRetry: widget.onRetry,
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, short ? 10 : 14, 24, 0),
          child: DesktopFiguresRow(
            dense: short,
            figures: [
              DesktopFigure(
                label: 'We owe suppliers',
                value: formatMoney(_s.supplierPayablesOutstanding),
                hint: _countHint(
                  _payables.where((r) => r.outstandingAmount > 0).length,
                  'unpaid bill',
                ),
                valueColor:
                    _s.supplierPayablesOutstanding > 0 ? negative : null,
              ),
              DesktopFigure(
                label: 'Customers owe us',
                value: formatMoney(_s.retailReceivablesOutstanding),
                hint: _countHint(_openRetail.length, 'open credit'),
              ),
              if (!widget.localWorkspace)
                DesktopFigure(
                  label: 'Other shops owe us',
                  value: formatMoney(_s.peerReceivablesOutstanding),
                  hint: _countHint(
                    _s.peerReceivables
                        .where((r) => r.outstandingAmount > 0)
                        .length,
                    'open debt',
                  ),
                ),
              DesktopFigure(
                label: 'Total owed to us',
                value: formatMoney(net),
              ),
              DesktopFigure(
                label: 'Overdue',
                value: '$overdue',
                hint: overdue == 0 ? 'Nothing late' : 'Needs chasing',
                valueColor: overdue > 0 ? negative : null,
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, short ? 10 : 14, 24, 10),
          child: _tabRow(context),
        ),
        Expanded(
          child: DesktopInspectorLayout(
            main: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: _body(context),
            ),
            inspector: _inspectorFor(context),
            onClose: () => setState(() => _selected = null),
          ),
        ),
      ],
    );
  }

  String _countHint(int n, String noun) =>
      n == 0 ? ' ' : '$n $noun${n == 1 ? '' : 's'}';

  // ── tab row ────────────────────────────────────────────────────────────

  Widget _tabRow(BuildContext context) {
    final owingSuppliers =
        _payables.where((r) => r.outstandingAmount > 0).length;
    final tabs = <(FinanceHubTab, String, int?)>[
      (FinanceHubTab.overview, 'Overview', null),
      (FinanceHubTab.suppliers, 'Suppliers', owingSuppliers),
      (FinanceHubTab.customers, 'Customers', _openRetail.length),
      if (!widget.localWorkspace)
        (FinanceHubTab.shops, 'Other shops', _s.peerDebtors.length),
    ];
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in tabs)
                DesktopFilterChip(
                  label: t.$2,
                  count: t.$3,
                  selected: _tab == t.$1,
                  onTap: () => _go(t.$1),
                ),
            ],
          ),
        ),
        ..._tabActions(context),
      ],
    );
  }

  List<Widget> _tabActions(BuildContext context) {
    switch (_tab) {
      case FinanceHubTab.overview:
        return const [];
      case FinanceHubTab.suppliers:
        return [
          if (widget.canRecordRestock && widget.onManualInvoice != null) ...[
            OutlinedButton.icon(
              style: desktopSecondaryButton(context),
              onPressed: widget.onManualInvoice,
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Enter invoice'),
            ),
            const SizedBox(width: 8),
          ],
          if (widget.onPaySeveral != null &&
              _payables.any((r) => r.outstandingAmount > 0.005))
            FilledButton.icon(
              style: desktopPrimaryButton(context),
              onPressed: widget.onPaySeveral,
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: const Text('Pay suppliers'),
            ),
        ];
      case FinanceHubTab.customers:
        return [
          if (widget.canManageReceivables &&
              widget.onCollectForCustomer != null &&
              _openRetail.isNotEmpty)
            FilledButton.icon(
              style: desktopPrimaryButton(context),
              onPressed: widget.onCollectForCustomer,
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: const Text('Collect for a customer'),
            ),
        ];
      case FinanceHubTab.shops:
        return [
          if (widget.canManageReceivables) ...[
            OutlinedButton.icon(
              style: desktopSecondaryButton(context),
              onPressed: widget.onAddShop,
              icon: const Icon(Icons.add_business_rounded, size: 18),
              label: const Text('Add shop'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: desktopPrimaryButton(context),
              onPressed: widget.onAddDebt,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add debt'),
            ),
          ],
        ];
    }
  }

  // ── bodies ─────────────────────────────────────────────────────────────

  Widget _body(BuildContext context) {
    switch (_tab) {
      case FinanceHubTab.overview:
        return _overview(context);
      case FinanceHubTab.suppliers:
        return _suppliers(context);
      case FinanceHubTab.customers:
        return _customers(context);
      case FinanceHubTab.shops:
        return _shopsBody(context);
    }
  }

  Widget _surface(BuildContext context, {required Widget child}) {
    final p = DesktopPalette.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: child,
    );
  }

  Widget _tableFooter(BuildContext context, String left, String? right) {
    final p = DesktopPalette.of(context);
    final style = GoogleFonts.plusJakartaSans(
      color: p.textMuted,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: p.dark ? p.panelAlt : p.panel,
      child: Row(
        children: [
          Expanded(child: Text(left, style: style)),
          if (right != null)
            Text(
              right,
              style: DesignType.numeric(fontSize: 12.5, letterSpacing: 0)
                  .copyWith(color: p.text),
            ),
        ],
      ),
    );
  }

  // Overview: what is late or due first, and what has come in.
  Widget _overview(BuildContext context) {
    final p = DesktopPalette.of(context);
    final items = _attention();
    final collections = mergeInstalments(allCollections(_s));
    final today = _today;
    final todayTotal = collectedBetween(collections, today);
    final weekTotal =
        collectedBetween(collections, today.subtract(const Duration(days: 6)));
    final success = context.readable(DesignColors.success);

    final attention = _surface(
      context,
      child: DesktopDataTable<_Owing>(
        minWidth: 480,
        rowHeight: 48,
        columns: [
          DesktopColumn<_Owing>(
            label: 'Who',
            flex: 3,
            minWidth: 150,
            cell: (_, r) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DesktopCellText(r.who, strong: true),
                if (r.what.isNotEmpty) DesktopCellText(r.what, muted: true),
              ],
            ),
          ),
          DesktopColumn<_Owing>(
            label: 'Direction',
            width: 104,
            cell: (_, r) => DesktopStatusChip(
              label: r.weOwe ? 'We owe' : 'Owes us',
              color: r.weOwe ? DesignColors.error : DesignColors.success,
            ),
          ),
          DesktopColumn<_Owing>(
            label: 'Due',
            width: 132,
            cell: (context, r) => DesktopCellText(
              _dueLabel(r.due, r.amount),
              color: _isOverdue(r.due, r.amount)
                  ? negativeAmountColor(DesktopPalette.of(context))
                  : null,
              muted: !_isOverdue(r.due, r.amount),
              strong: _isOverdue(r.due, r.amount),
            ),
          ),
          DesktopColumn<_Owing>(
            label: 'Balance',
            width: 116,
            numeric: true,
            cell: (_, r) => DesktopCellText(
              formatMoney(r.amount),
              numeric: true,
            ),
          ),
        ],
        rows: items,
        rowId: (r) => r.key,
        selectedId: _selected,
        onRowSelected: (r) => _go(r.tab, r.id),
        footer: _tableFooter(
          context,
          items.isEmpty
              ? 'Nothing to chase'
              : 'Latest first by due date. Click a row to open it.',
          null,
        ),
        empty: const DesktopEmptyState(
          icon: Icons.verified_rounded,
          title: 'You are all square',
          message: 'Nobody owes you and you owe nobody right now.',
        ),
      ),
    );

    final collected = _surface(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Collected today',
                        style: GoogleFonts.plusJakartaSans(
                          color: p.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatMoney(todayTotal),
                          style: DesignType.numeric(
                            fontSize: 24,
                            color: success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Last 7 days',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      formatMoney(weekTotal),
                      style: DesignType.numeric(
                        fontSize: 15,
                        color: p.text,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.border),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: DesktopSectionLabel('RECENT COLLECTIONS'),
          ),
          Expanded(
            child: collections.isEmpty
                ? const DesktopEmptyState(
                    icon: Icons.savings_rounded,
                    title: 'Nothing collected yet',
                    message:
                        'Payments from customers and shops will show up here.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    children: [
                      for (final c in collections.take(8))
                        DesktopActivityLine(
                          icon: c.isShop
                              ? Icons.storefront_rounded
                              : Icons.person_rounded,
                          title: c.isShop || widget.canViewCustomerDetails
                              ? c.who
                              : 'Customer details hidden',
                          subtitle:
                              '${_whenLabel(c.paidAt)} · ${paymentMethodLabel(c.method)}',
                          amount: '+${formatMoney(c.amount)}',
                          amountColor: success,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return ListView(
            children: [
              SizedBox(height: 380, child: attention),
              const SizedBox(height: 14),
              SizedBox(height: 380, child: collected),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: attention),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: collected),
          ],
        );
      },
    );
  }

  Widget _suppliers(BuildContext context) {
    final p = DesktopPalette.of(context);
    final rows = _payables;
    final outstanding = rows.fold<double>(0, (a, r) => a + r.outstandingAmount);
    return _surface(
      context,
      child: LayoutBuilder(builder: (context, box) {
        // With the side panel open the table is narrow; "Paid" is in the panel.
        final compact = box.maxWidth < 700;
        return DesktopDataTable<FinancePayable>(
        minWidth: 560,
        rows: rows,
        rowId: (r) => r.id,
        selectedId: _selected,
        onRowSelected: (r) => setState(() => _selected = r.id),
        initialSortColumn: 1,
        columns: [
          DesktopColumn<FinancePayable>(
            label: 'Supplier',
            flex: 3,
            minWidth: 160,
            sortBy: (r) => tidySupplierName(r.supplierName).toLowerCase(),
            cell: (_, r) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DesktopCellText(tidySupplierName(r.supplierName), strong: true),
                DesktopCellText(
                  r.invoiceNumber ?? 'Supplier invoice',
                  muted: true,
                ),
              ],
            ),
          ),
          DesktopColumn<FinancePayable>(
            label: 'Due',
            width: 132,
            sortBy: (r) => r.dueDate?.millisecondsSinceEpoch ?? (1 << 52),
            cell: (context, r) {
              final late = _isOverdue(r.dueDate, r.outstandingAmount);
              return DesktopCellText(
                _dueLabel(r.dueDate, r.outstandingAmount),
                muted: !late,
                strong: late,
                color: late ? negativeAmountColor(p) : null,
              );
            },
          ),
          DesktopColumn<FinancePayable>(
            label: 'Invoice total',
            width: 120,
            numeric: true,
            sortBy: (r) => r.totalAmount,
            cell: (_, r) =>
                DesktopCellText(formatMoney(r.totalAmount), numeric: true),
          ),
          if (!compact)
          DesktopColumn<FinancePayable>(
            label: 'Paid',
            width: 110,
            numeric: true,
            sortBy: (r) => r.paidAmount,
            cell: (_, r) => DesktopCellText(
              formatMoney(r.paidAmount),
              numeric: true,
              muted: true,
            ),
          ),
          DesktopColumn<FinancePayable>(
            label: 'Balance',
            width: 120,
            numeric: true,
            sortBy: (r) => r.outstandingAmount,
            cell: (_, r) => DesktopCellText(
              formatMoney(r.outstandingAmount),
              numeric: true,
              strong: true,
            ),
          ),
          DesktopColumn<FinancePayable>(
            label: 'Status',
            width: 108,
            cell: (_, r) => _payableChip(r),
          ),
        ],
        footer: _tableFooter(
          context,
          '${rows.length} ${rows.length == 1 ? 'bill' : 'bills'}',
          'Outstanding ${formatMoney(outstanding)}',
        ),
        empty: DesktopEmptyState(
          icon: Icons.business_rounded,
          title: 'No supplier bills yet',
          message: 'Scan a supplier receipt or enter an invoice and it will '
              'be tracked here until it is paid.',
          action: widget.canRecordRestock && widget.onScan != null
              ? OutlinedButton.icon(
                  style: desktopSecondaryButton(context),
                  onPressed: widget.onScan,
                  icon: const Icon(Icons.document_scanner_rounded, size: 18),
                  label: const Text('Scan a receipt'),
                )
              : null,
        ),
      );
      }),
    );
  }

  String _retailCustomerLabel(RetailReceivable receivable) =>
      widget.canViewCustomerDetails
          ? receivable.customerName ?? 'Walk-in customer'
          : 'Customer details hidden';

  Widget _customers(BuildContext context) {
    final p = DesktopPalette.of(context);
    final rows = _openRetail;
    final outstanding = rows.fold<double>(0, (a, r) => a + r.outstandingAmount);
    return _surface(
      context,
      child: DesktopDataTable<RetailReceivable>(
        minWidth: 600,
        rows: rows,
        rowId: (r) => r.id,
        selectedId: _selected,
        onRowSelected: (r) => setState(() => _selected = r.id),
        initialSortColumn: 1,
        columns: [
          DesktopColumn<RetailReceivable>(
            label: 'Customer',
            flex: 3,
            minWidth: 160,
            sortBy: (r) => widget.canViewCustomerDetails
                ? (r.customerName ?? '').toLowerCase()
                : (r.receiptNumber ?? '').toLowerCase(),
            cell: (_, r) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DesktopCellText(_retailCustomerLabel(r), strong: true),
                DesktopCellText(
                  r.receiptNumber == null
                      ? 'Owed from credit sales'
                      : 'Receipt ${r.receiptNumber}',
                  muted: true,
                ),
              ],
            ),
          ),
          DesktopColumn<RetailReceivable>(
            label: 'Due',
            width: 132,
            sortBy: (r) => r.dueDate?.millisecondsSinceEpoch ?? (1 << 52),
            cell: (context, r) {
              final late = _isOverdue(r.dueDate, r.outstandingAmount);
              return DesktopCellText(
                _dueLabel(r.dueDate, r.outstandingAmount),
                muted: !late,
                strong: late,
                color: late ? negativeAmountColor(p) : null,
              );
            },
          ),
          DesktopColumn<RetailReceivable>(
            label: 'Original',
            width: 116,
            numeric: true,
            sortBy: (r) => r.originalAmount,
            cell: (_, r) =>
                DesktopCellText(formatMoney(r.originalAmount), numeric: true),
          ),
          DesktopColumn<RetailReceivable>(
            label: 'Balance',
            width: 120,
            numeric: true,
            sortBy: (r) => r.outstandingAmount,
            cell: (_, r) => DesktopCellText(
              formatMoney(r.outstandingAmount),
              numeric: true,
              strong: true,
            ),
          ),
          DesktopColumn<RetailReceivable>(
            label: 'Status',
            width: 108,
            cell: (_, r) => _receivableChip(r.dueDate, r.outstandingAmount,
                r.originalAmount),
          ),
        ],
        footer: _tableFooter(
          context,
          '${rows.length} open ${rows.length == 1 ? 'credit' : 'credits'}',
          'Owed ${formatMoney(outstanding)}',
        ),
        empty: const DesktopEmptyState(
          icon: Icons.groups_rounded,
          title: 'No customer credit is outstanding',
          message: 'Sales made on credit appear here until they are paid.',
        ),
      ),
    );
  }

  Widget _shopsBody(BuildContext context) {
    final rows = _shops;
    final owed = _s.peerReceivablesOutstanding;
    return _surface(
      context,
      child: DesktopDataTable<PeerDebtor>(
        minWidth: 600,
        rows: rows,
        rowId: (r) => r.id,
        selectedId: _selected,
        onRowSelected: (r) => setState(() => _selected = r.id),
        onRowActivated: widget.onOpenShop,
        columns: [
          DesktopColumn<PeerDebtor>(
            label: 'Shop',
            flex: 3,
            minWidth: 160,
            sortBy: (r) => r.name.toLowerCase(),
            cell: (_, r) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DesktopCellText(r.name, strong: true),
                if ((r.contactName ?? '').isNotEmpty)
                  DesktopCellText(r.contactName!, muted: true),
              ],
            ),
          ),
          DesktopColumn<PeerDebtor>(
            label: 'Paid back',
            flex: 2,
            minWidth: 140,
            cell: (context, r) {
              final st = shopStatement(_s, r);
              if (st.originalTotal <= 0) {
                return const DesktopCellText('No debts yet', muted: true);
              }
              return _ProgressCell(
                value: st.progress,
                label:
                    '${formatMoney(st.paid)} of ${formatMoney(st.originalTotal)}',
              );
            },
          ),
          DesktopColumn<PeerDebtor>(
            label: 'Owes us',
            width: 128,
            numeric: true,
            sortBy: (r) => shopOutstanding(_s, r),
            cell: (_, r) => DesktopCellText(
              formatMoney(shopOutstanding(_s, r)),
              numeric: true,
              strong: true,
            ),
          ),
        ],
        footer: _tableFooter(
          context,
          '${rows.length} ${rows.length == 1 ? 'shop' : 'shops'}',
          'Owed ${formatMoney(owed)}',
        ),
        empty: DesktopEmptyState(
          icon: Icons.storefront_rounded,
          title: 'No other shops added yet',
          message: 'Add a shop that owes you money, then record what it owes.',
          action: widget.canManageReceivables
              ? OutlinedButton.icon(
                  style: desktopSecondaryButton(context),
                  onPressed: widget.onAddShop,
                  icon: const Icon(Icons.add_business_rounded, size: 18),
                  label: const Text('Add shop'),
                )
              : null,
        ),
      ),
    );
  }

  // ── inspector ──────────────────────────────────────────────────────────

  Widget? _inspectorFor(BuildContext context) {
    final id = _selected;
    if (id == null) return null;
    switch (_tab) {
      case FinanceHubTab.overview:
        return null;
      case FinanceHubTab.suppliers:
        final r = _payables.where((e) => e.id == id).firstOrNull;
        return r == null ? null : _payableInspector(context, r);
      case FinanceHubTab.customers:
        final r = _s.retailReceivables.where((e) => e.id == id).firstOrNull;
        return r == null ? null : _retailInspector(context, r);
      case FinanceHubTab.shops:
        final r = _s.peerDebtors.where((e) => e.id == id).firstOrNull;
        return r == null ? null : _shopInspector(context, r);
    }
  }

  void _close() => setState(() => _selected = null);

  Widget _payableInspector(BuildContext context, FinancePayable r) {
    final p = DesktopPalette.of(context);
    final late = _isOverdue(r.dueDate, r.outstandingAmount);
    return DesktopInspector(
      title: tidySupplierName(r.supplierName),
      subtitle: r.invoiceNumber ?? 'Supplier invoice',
      onClose: _close,
      footer: widget.onOpenPayable == null
          ? null
          : FilledButton.icon(
              style: desktopPrimaryButton(context),
              onPressed: () => widget.onOpenPayable!(r),
              icon: Icon(
                widget.canRecordSupplierPayment && r.outstandingAmount > 0
                    ? Icons.payments_rounded
                    : Icons.receipt_long_rounded,
                size: 18,
              ),
              label: Text(
                widget.canRecordSupplierPayment && r.outstandingAmount > 0
                    ? 'Record a payment'
                    : 'Open the bill',
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _payableChip(r),
          const SizedBox(height: 14),
          DesktopFactList(facts: [
            DesktopFact('Invoice total', formatMoney(r.totalAmount, decimals: true),
                numeric: true),
            DesktopFact('Paid so far', formatMoney(r.paidAmount, decimals: true),
                numeric: true),
            DesktopFact(
              'Still to pay',
              formatMoney(r.outstandingAmount, decimals: true),
              numeric: true,
              color: r.outstandingAmount > 0 ? negativeAmountColor(p) : null,
            ),
            DesktopFact(
              'Due',
              r.dueDate == null
                  ? 'No due date'
                  : DateFormat('d MMM y').format(r.dueDate!.toLocal()),
              color: late ? negativeAmountColor(p) : null,
            ),
            if (r.supplierPhone != null && r.supplierPhone!.isNotEmpty)
              DesktopFact('Supplier phone', r.supplierPhone!),
          ]),
          const SizedBox(height: 20),
          const DesktopSectionLabel('PAYMENT HISTORY'),
          if (r.payments.isEmpty)
            Text(
              'No payments recorded yet.',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 13,
              ),
            )
          else
            for (final pay in r.payments)
              DesktopActivityLine(
                icon: Icons.check_circle_outline_rounded,
                title: formatMoney(pay.amount, decimals: true),
                subtitle: [
                  pay.fundingSource == 'CASH_TILL'
                      ? 'Cash till'
                      : 'Bank / M-Pesa',
                  if (pay.paidAt != null)
                    DateFormat('d MMM y').format(pay.paidAt!.toLocal()),
                ].join(' · '),
                amount: '',
              ),
        ],
      ),
    );
  }

  Widget _retailInspector(BuildContext context, RetailReceivable r) {
    final p = DesktopPalette.of(context);
    final late = _isOverdue(r.dueDate, r.outstandingAmount);
    return DesktopInspector(
      title: _retailCustomerLabel(r),
      subtitle:
          r.receiptNumber == null ? 'Credit sale' : 'Receipt ${r.receiptNumber}',
      onClose: _close,
      footer: widget.canManageReceivables &&
              r.outstandingAmount > 0 &&
              widget.onCollectRetail != null
          ? FilledButton.icon(
              style: desktopPrimaryButton(context),
              onPressed: () => widget.onCollectRetail!(r),
              icon: const Icon(Icons.payments_rounded, size: 18),
              label: const Text('Collect payment'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _receivableChip(r.dueDate, r.outstandingAmount, r.originalAmount),
          const SizedBox(height: 14),
          DesktopFactList(facts: [
            DesktopFact('Original credit',
                formatMoney(r.originalAmount, decimals: true),
                numeric: true),
            DesktopFact(
              'Still owed',
              formatMoney(r.outstandingAmount, decimals: true),
              numeric: true,
              color: r.outstandingAmount > 0 ? negativeAmountColor(p) : null,
            ),
            DesktopFact(
              'Due',
              r.dueDate == null
                  ? 'No due date'
                  : DateFormat('d MMM y').format(r.dueDate!.toLocal()),
              color: late ? negativeAmountColor(p) : null,
            ),
          ]),
          const SizedBox(height: 20),
          const DesktopSectionLabel('PAYMENTS RECEIVED'),
          if (r.payments.isEmpty)
            Text(
              'Nothing received yet.',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 13,
              ),
            )
          else
            for (final pay in r.payments)
              DesktopActivityLine(
                icon: Icons.south_west_rounded,
                title: paymentMethodLabel(pay.method),
                subtitle: _paidAtLabel(pay),
                amount: '+${formatMoney(pay.amount, decimals: true)}',
                amountColor: context.readable(DesignColors.success),
              ),
        ],
      ),
    );
  }

  Widget _shopInspector(BuildContext context, PeerDebtor shop) {
    final p = DesktopPalette.of(context);
    final st = shopStatement(_s, shop);
    final open = st.openDebts;
    return DesktopInspector(
      title: shop.name,
      subtitle: (shop.contactName ?? '').isNotEmpty
          ? shop.contactName
          : (shop.phone ?? ''),
      onClose: _close,
      footer: widget.onOpenShop == null
          ? null
          : OutlinedButton.icon(
              style: desktopSecondaryButton(context),
              onPressed: () => widget.onOpenShop!(shop),
              icon: const Icon(Icons.menu_book_rounded, size: 18),
              label: const Text('Open the full ledger'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopFactList(facts: [
            DesktopFact('Debts recorded',
                formatMoney(st.originalTotal, decimals: true),
                numeric: true),
            DesktopFact('Paid back', formatMoney(st.paid, decimals: true),
                numeric: true),
            DesktopFact(
              'Still owes',
              formatMoney(st.outstanding, decimals: true),
              numeric: true,
              color: st.outstanding > 0 ? negativeAmountColor(p) : null,
            ),
            if ((shop.phone ?? '').isNotEmpty)
              DesktopFact('Phone', shop.phone!),
          ]),
          const SizedBox(height: 20),
          DesktopSectionLabel('OPEN DEBTS (${open.length})'),
          if (open.isEmpty)
            Text(
              st.isSettled ? 'Fully paid.' : 'No open debts.',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 13,
              ),
            )
          else
            for (final d in open)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: DesktopActivityLine(
                        title: d.description,
                        subtitle: d.dueDate == null
                            ? 'No due date'
                            : _dueLabel(d.dueDate, d.outstandingAmount),
                        amount:
                            formatMoney(d.outstandingAmount, decimals: true),
                      ),
                    ),
                    if (widget.canManageReceivables &&
                        widget.onCollectPeer != null)
                      TextButton(
                        style: desktopLinkButton(context),
                        onPressed: () => widget.onCollectPeer!(d),
                        child: const Text('Collect'),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  // ── shared bits ────────────────────────────────────────────────────────

  Widget _payableChip(FinancePayable r) {
    if (r.outstandingAmount <= 0.005) {
      return const DesktopStatusChip(
        label: 'Paid',
        color: DesignColors.success,
      );
    }
    if (_isOverdue(r.dueDate, r.outstandingAmount)) {
      return const DesktopStatusChip(
        label: 'Overdue',
        color: DesignColors.error,
      );
    }
    return DesktopStatusChip(
      label: r.paidAmount > 0 ? 'Part paid' : 'Unpaid',
      color: DesignColors.warning,
    );
  }

  Widget _receivableChip(DateTime? due, double outstanding, double original) {
    if (outstanding <= 0.005) {
      return const DesktopStatusChip(
        label: 'Settled',
        color: DesignColors.success,
      );
    }
    if (_isOverdue(due, outstanding)) {
      return const DesktopStatusChip(
        label: 'Overdue',
        color: DesignColors.error,
      );
    }
    return DesktopStatusChip(
      label: outstanding < original ? 'Part paid' : 'Open',
      color: DesignColors.warning,
    );
  }

  String _dueLabel(DateTime? due, double outstanding) {
    if (due == null) return 'No due date';
    final day = startOfDay(due.toLocal());
    final diff = _today.difference(day).inDays;
    if (outstanding > 0 && diff > 0) {
      return 'Overdue ${diff}d';
    }
    if (diff == 0) return 'Due today';
    if (diff == -1) return 'Due tomorrow';
    return DateFormat('d MMM y').format(day);
  }

  String _whenLabel(DateTime d) {
    final diff = _today.difference(startOfDay(d)).inDays;
    final time = DateFormat('h:mm a').format(d);
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
    return '${DateFormat('d MMM').format(d)}, $time';
  }

  String _paidAtLabel(ReceivablePayment pay) {
    final d = (pay.paidAt ?? pay.createdAt)?.toLocal();
    return d == null ? '' : _whenLabel(d);
  }

  /// Every open balance, late ones first, then by due date, undated last.
  List<_Owing> _attention() {
    final out = <_Owing>[
      for (final r in _payables)
        if (r.outstandingAmount > 0)
          _Owing(
            key: 'p:${r.id}',
            id: r.id,
            tab: FinanceHubTab.suppliers,
            weOwe: true,
            who: tidySupplierName(r.supplierName),
            what: r.invoiceNumber ?? 'Supplier invoice',
            due: r.dueDate,
            amount: r.outstandingAmount,
          ),
      for (final r in _openRetail)
        _Owing(
          key: 'r:${r.id}',
          id: r.id,
          tab: FinanceHubTab.customers,
          weOwe: false,
          who: _retailCustomerLabel(r),
          what: r.receiptNumber == null
              ? 'Credit sales'
              : 'Receipt ${r.receiptNumber}',
          due: r.dueDate,
          amount: r.outstandingAmount,
        ),
      if (!widget.localWorkspace)
        for (final r in _s.peerReceivables)
          if (r.outstandingAmount > 0)
            _Owing(
              key: 's:${r.id}',
              id: r.debtor.id,
              tab: FinanceHubTab.shops,
              weOwe: false,
              who: r.debtor.name,
              what: r.description,
              due: r.dueDate,
              amount: r.outstandingAmount,
            ),
    ];
    int rank(_Owing o) {
      if (_isOverdue(o.due, o.amount)) return 0;
      return o.due == null ? 2 : 1;
    }

    out.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final ad = a.due, bd = b.due;
      if (ad != null && bd != null) return ad.compareTo(bd);
      return b.amount.compareTo(a.amount);
    });
    return out.take(40).toList();
  }
}

class _Owing {
  const _Owing({
    required this.key,
    required this.id,
    required this.tab,
    required this.weOwe,
    required this.who,
    required this.what,
    required this.due,
    required this.amount,
  });

  final String key;
  final String id;
  final FinanceHubTab tab;
  final bool weOwe;
  final String who;
  final String what;
  final DateTime? due;
  final double amount;
}

class _ProgressCell extends StatelessWidget {
  const _ProgressCell({required this.value, required this.label});

  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 5,
            backgroundColor: p.hover,
            color: value >= 1 ? DesignColors.success : DesignColors.accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            color: p.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: p.dark ? 0.16 : 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 17, color: DesignColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              style: desktopLinkButton(context),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
