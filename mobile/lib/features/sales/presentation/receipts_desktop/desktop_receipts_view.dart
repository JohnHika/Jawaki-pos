import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/database/app_database.dart' show PendingSale;
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/receipt_search.dart';
import 'receipt_format.dart';

/// Which receipts the table is narrowed to.
enum DesktopReceiptStatus { all, sales, voided, unsynced }

/// The date ranges offered in the toolbar. null days is all time and 0 is
/// since midnight.
const List<({String label, int? days})> desktopReceiptRanges = [
  (label: 'Today', days: 0),
  (label: 'Last 7 days', days: 7),
  (label: 'Last 30 days', days: 30),
  (label: 'Last 90 days', days: 90),
  (label: 'All time', days: null),
];

String desktopReceiptRangeLabel(int? days) => desktopReceiptRanges
    .firstWhere((r) => r.days == days,
        orElse: () => (label: 'Last $days days', days: days))
    .label;

/// The Receipts page on a computer: a toolbar, a sortable table and, when a row
/// is picked, the receipt as thermal paper on the right.
///
/// It takes plain rows, so a test can feed sample sales. The routed screen owns
/// loading and every action; this widget draws them and keeps only the page's
/// own state: the search text, the filters and the selected row.
class DesktopReceiptsView extends StatefulWidget {
  const DesktopReceiptsView({
    super.key,
    required this.title,
    required this.sales,
    required this.rangeDays,
    required this.onRangeChanged,
    required this.inspectorBuilder,
    required this.canViewCustomerDetails,
    this.customerNames = const {},
    this.customerPhones = const {},
    this.cashierNames = const {},
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    this.onOpen,
    this.onPrint,
    this.initialSelectedId,
  });

  final String title;
  final List<PendingSale> sales;

  /// Days back from now (0 is today, null is all time).
  final int? rangeDays;
  final ValueChanged<int?> onRangeChanged;

  /// The panel for the picked sale. Call [close] to dismiss it.
  final Widget Function(
    BuildContext context,
    PendingSale sale,
    VoidCallback close,
  ) inspectorBuilder;

  final bool canViewCustomerDetails;

  /// By customer id.
  final Map<String, String> customerNames;
  final Map<String, String> customerPhones;

  /// By cashier id. A cashier that is not listed shows as "Staff".
  final Map<String, String> cashierNames;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onRefresh;

  /// Open the full receipt (the context menu; the inspector has its own).
  final ValueChanged<PendingSale>? onOpen;

  /// Ctrl+P on the picked row.
  final ValueChanged<PendingSale>? onPrint;
  final String? initialSelectedId;

  @override
  State<DesktopReceiptsView> createState() => _DesktopReceiptsViewState();
}

class _DesktopReceiptsViewState extends State<DesktopReceiptsView> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'ReceiptsSearch');
  String _query = '';
  DesktopReceiptStatus _status = DesktopReceiptStatus.all;

  /// A [receiptMethodKey], or null for every method.
  String? _method;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedId;
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _number(PendingSale s) => s.receiptNumber.trim().isNotEmpty
      ? s.receiptNumber
      : s.id.length >= 8
          ? s.id.substring(0, 8).toUpperCase()
          : s.id.toUpperCase();

  String? _customer(PendingSale s) =>
      widget.canViewCustomerDetails ? widget.customerNames[s.customerId] : null;

  String? _customerPhone(PendingSale s) => widget.canViewCustomerDetails
      ? widget.customerPhones[s.customerId]
      : null;

  String _customerLabel(PendingSale s) {
    if (s.customerId == null) return 'Walk-in';
    if (!widget.canViewCustomerDetails) return 'Customer details hidden';
    return _customer(s) ?? 'Customer unavailable';
  }

  String _cashier(PendingSale s) => widget.cashierNames[s.cashierId] ?? 'Staff';

  bool _matches(PendingSale s) {
    switch (_status) {
      case DesktopReceiptStatus.all:
        break;
      case DesktopReceiptStatus.sales:
        if (isVoidedStatus(s.status)) return false;
      case DesktopReceiptStatus.voided:
        if (!isVoidedStatus(s.status)) return false;
      case DesktopReceiptStatus.unsynced:
        if (s.isSynced) return false;
    }
    if (_method != null && receiptMethodKey(s.paymentMethod) != _method) {
      return false;
    }
    if (_query.trim().isEmpty) return true;
    return receiptMatchesQuery(
      saleId: s.id,
      receiptNumber: s.receiptNumber,
      paymentMethod: s.paymentMethod,
      customerName: _customer(s),
      customerPhone: _customerPhone(s),
      query: _query,
    );
  }

  void _select(PendingSale? sale) => setState(() => _selectedId = sale?.id);

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final w = widget;
    final rows = w.sales.where(_matches).toList();
    final selected = w.sales.where((s) => s.id == _selectedId).firstOrNull;
    final inspector = selected == null
        ? null
        : w.inspectorBuilder(context, selected, () {
            _select(null);
          });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _searchFocus.requestFocus(),
        if (w.onRefresh != null)
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              w.onRefresh!,
        if (selected != null && w.onPrint != null)
          const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
              w.onPrint!(selected),
        if (selected != null)
          const SingleActivator(LogicalKeyboardKey.escape): () => _select(null),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: w.title,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              actions: [
                if (w.onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh (Ctrl+R)',
                    onPressed: w.onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
              ],
            ),
            Expanded(
              child: DesktopInspectorLayout(
                inspectorWidth: 380,
                onClose: () => _select(null),
                inspector: inspector,
                main: Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    inspector == null ? 24 : 16,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _toolbar(context),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: p.dark ? p.panelAlt : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: p.border),
                          ),
                          child: _body(context, rows),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final w = widget;
    final all = w.sales;
    final voided = all.where((s) => isVoidedStatus(s.status)).length;
    final unsynced = all.where((s) => !s.isSynced).length;
    final methods = <String, String>{};
    for (final s in all) {
      methods.putIfAbsent(
          receiptMethodKey(s.paymentMethod), () => s.paymentMethod);
    }
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DesktopSearchField(
            controller: _search,
            focusNode: _searchFocus,
            width: box.maxWidth < 700 ? 240 : 300,
            hint: w.canViewCustomerDetails
                ? 'Receipt, customer or phone'
                : 'Receipt or payment',
            onChanged: (v) => setState(() => _query = v),
          ),
          DesktopFilterChip(
            label: 'All',
            count: all.length,
            selected: _status == DesktopReceiptStatus.all,
            onTap: () => setState(() => _status = DesktopReceiptStatus.all),
          ),
          DesktopFilterChip(
            label: 'Sales',
            count: all.length - voided,
            selected: _status == DesktopReceiptStatus.sales,
            onTap: () => setState(() => _status = DesktopReceiptStatus.sales),
          ),
          DesktopFilterChip(
            label: 'Voided',
            count: voided,
            selected: _status == DesktopReceiptStatus.voided,
            onTap: () => setState(() => _status = DesktopReceiptStatus.voided),
          ),
          if (unsynced > 0)
            DesktopFilterChip(
              label: 'Not synced',
              count: unsynced,
              selected: _status == DesktopReceiptStatus.unsynced,
              onTap: () =>
                  setState(() => _status = DesktopReceiptStatus.unsynced),
            ),
          _MenuChip<String?>(
            tooltip: 'Filter by payment method',
            label: _method == null
                ? null
                : paymentMethodLabel(methods[_method] ?? _method),
            emptyLabel: 'Payment',
            selected: _method,
            options: [
              (value: null, label: 'All payment methods'),
              for (final e in methods.entries)
                (value: e.key, label: paymentMethodLabel(e.value)),
            ],
            onSelected: (v) => setState(() => _method = v),
          ),
          _MenuChip<int?>(
            tooltip: 'Date range',
            label: desktopReceiptRangeLabel(w.rangeDays),
            emptyLabel: 'Date range',
            selected: w.rangeDays,
            options: [
              for (final r in desktopReceiptRanges)
                (value: r.days, label: r.label),
            ],
            onSelected: w.onRangeChanged,
            highlightWhenSet: false,
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, List<PendingSale> rows) {
    final w = widget;
    if (w.errorMessage != null && w.sales.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load receipts",
        message: w.errorMessage,
        action: w.onRetry == null
            ? null
            : OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: w.onRetry,
                child: const Text('Try again'),
              ),
      );
    }
    if (rows.isEmpty && !w.loading) return _empty(context);

    return LayoutBuilder(
      builder: (context, box) {
        // With the inspector open the table is narrow. The paper already shows
        // the cashier and status, so those columns step aside.
        final compact = box.maxWidth < 780;
        final p = context.desktop;
        final columns = <DesktopColumn<PendingSale>>[
          DesktopColumn<PendingSale>(
            label: 'Receipt',
            width: 112,
            sortBy: (s) => s.receiptNumber,
            cell: (context, s) {
              final number = DesktopCellText('#${_number(s)}', strong: true);
              // The Status column steps aside when the table is narrow, so a
              // voided or unsynced receipt says so under its number.
              final note = !compact
                  ? null
                  : isVoidedStatus(s.status)
                      ? ('Voided', _alert(p, DesignColors.error))
                      : !s.isSynced
                          ? ('Not synced', _alert(p, DesignColors.warning))
                          : null;
              if (note == null) return number;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  number,
                  Text(
                    note.$1,
                    style: GoogleFonts.plusJakartaSans(
                      color: note.$2,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              );
            },
          ),
          DesktopColumn<PendingSale>(
            label: 'Date and time',
            width: 128,
            sortBy: (s) => s.createdAt,
            cell: (context, s) =>
                DesktopCellText(formatReceiptTime(s.createdAt), muted: true),
          ),
          DesktopColumn<PendingSale>(
            label: 'Customer',
            flex: 3,
            minWidth: 130,
            sortBy: (s) => _customerLabel(s).toLowerCase(),
            cell: (context, s) => DesktopCellText(
              _customerLabel(s),
              muted: _customer(s) == null,
            ),
          ),
          if (!compact)
            DesktopColumn<PendingSale>(
              label: 'Cashier',
              flex: 2,
              minWidth: 100,
              sortBy: (s) => _cashier(s).toLowerCase(),
              cell: (context, s) => DesktopCellText(_cashier(s), muted: true),
            ),
          DesktopColumn<PendingSale>(
            label: 'Payment',
            width: 112,
            sortBy: (s) => paymentMethodLabel(s.paymentMethod),
            cell: (context, s) => DesktopStatusChip(
              label: paymentMethodLabel(s.paymentMethod),
              color: receiptMethodColor(s.paymentMethod),
            ),
          ),
          DesktopColumn<PendingSale>(
            label: 'Total',
            width: 116,
            numeric: true,
            sortBy: (s) => s.total,
            cell: (context, s) => DesktopCellText(
              formatMoney(s.total),
              numeric: true,
              color: isVoidedStatus(s.status) ? p.textFaint : null,
            ),
          ),
          if (!compact)
            DesktopColumn<PendingSale>(
              label: 'Status',
              width: 112,
              sortBy: (s) => isVoidedStatus(s.status) ? 1 : 0,
              cell: (context, s) {
                if (isVoidedStatus(s.status)) {
                  return const DesktopStatusChip(
                    label: 'Voided',
                    color: DesignColors.error,
                  );
                }
                if (!s.isSynced) {
                  return const DesktopStatusChip(
                    label: 'Not synced',
                    color: DesignColors.warning,
                  );
                }
                return const DesktopCellText('Complete', muted: true);
              },
            ),
        ];
        return DesktopDataTable<PendingSale>(
          columns: columns,
          rows: rows,
          rowId: (s) => s.id,
          rowHeight: 46,
          minWidth: compact ? 560 : 800,
          loading: w.loading,
          initialSortColumn: 1,
          initialSortAscending: false,
          selectedId: _selectedId,
          onRowSelected: _select,
          // No double-click handler on purpose: Flutter waits out the
          // double-tap timeout before it reports a single click, which makes
          // picking a row feel slow. Open is in the inspector and the menu.
          onRowSecondaryTap: _showRowMenu,
          footer: _footer(context, rows),
        );
      },
    );
  }

  /// Text colour for a warning that reads on white and on the dark panel.
  Color _alert(DesktopPalette p, Color base) {
    if (p.dark) return base;
    return base == DesignColors.error
        ? const Color(0xFFB3261E)
        : const Color(0xFF8A5A00);
  }

  Widget _footer(BuildContext context, List<PendingSale> rows) {
    final p = context.desktop;
    var total = 0.0;
    var voided = 0;
    for (final s in rows) {
      if (isVoidedStatus(s.status)) {
        voided++;
      } else {
        total += s.total;
      }
    }
    final style = GoogleFonts.plusJakartaSans(
      color: p.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final noun = rows.length == 1 ? 'receipt' : 'receipts';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Text('${formatMoney(rows.length, symbol: '')} $noun', style: style),
          const Spacer(),
          if (voided > 0) ...[
            Text('$voided voided, not counted', style: style),
            const SizedBox(width: 18),
          ],
          Text('Total', style: style),
          const SizedBox(width: 8),
          Text(
            formatMoney(total, decimals: true),
            style: DesignType.numeric(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: p.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final w = widget;
    final filtered = _query.trim().isNotEmpty ||
        _status != DesktopReceiptStatus.all ||
        _method != null;
    if (w.sales.isNotEmpty && filtered) {
      return DesktopEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No receipts match',
        message: 'Try another receipt number, customer or phone, '
            'or clear the filters.',
        action: OutlinedButton(
          style: desktopSecondaryButton(context),
          onPressed: () {
            _search.clear();
            setState(() {
              _query = '';
              _status = DesktopReceiptStatus.all;
              _method = null;
            });
          },
          child: const Text('Clear filters'),
        ),
      );
    }
    if (w.rangeDays != null) {
      return DesktopEmptyState(
        icon: Icons.receipt_long_outlined,
        title:
            'No receipts ${desktopReceiptRangeLabel(w.rangeDays).toLowerCase()}',
        message: 'Every completed sale shows up here with its receipt. '
            'Try a longer range to look further back.',
        action: OutlinedButton(
          style: desktopSecondaryButton(context),
          onPressed: () => w.onRangeChanged(null),
          child: const Text('Show all time'),
        ),
      );
    }
    return const DesktopEmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'No receipts yet',
      message: 'Every completed sale shows up here with its receipt, '
          'ready to print or share.',
    );
  }

  Future<void> _showRowMenu(PendingSale sale, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    _select(sale);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.onOpen != null)
          const PopupMenuItem(value: 'open', child: Text('Open receipt')),
        if (widget.onPrint != null)
          const PopupMenuItem(value: 'print', child: Text('Print')),
        const PopupMenuItem(value: 'copy', child: Text('Copy number')),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'open':
        widget.onOpen?.call(sale);
      case 'print':
        widget.onPrint?.call(sale);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _number(sale)));
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Receipt number copied')),
        );
    }
  }
}

/// A drop-down that looks like the filter chips beside it.
class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({
    required this.tooltip,
    required this.label,
    required this.emptyLabel,
    required this.selected,
    required this.options,
    required this.onSelected,
    this.highlightWhenSet = true,
  });

  final String tooltip;

  /// null shows [emptyLabel] in the quiet style.
  final String? label;
  final String emptyLabel;
  final T selected;
  final List<({T value, String label})> options;
  final ValueChanged<T> onSelected;

  /// A set value fills the chip with the accent tint. The date range always
  /// has a value, so it stays quiet.
  final bool highlightWhenSet;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final active = label != null && highlightWhenSet;
    return PopupMenuButton<int>(
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      onSelected: (i) => onSelected(options[i].value),
      itemBuilder: (context) => [
        for (var i = 0; i < options.length; i++)
          PopupMenuItem(
            value: i,
            child: Text(
              options[i].label,
              style: TextStyle(
                fontWeight: options[i].value == selected
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: ShapeDecoration(
          color: active ? p.selected : Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(color: active ? Colors.transparent : p.border),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label ?? emptyLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: active ? p.text : p.textMuted,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}
