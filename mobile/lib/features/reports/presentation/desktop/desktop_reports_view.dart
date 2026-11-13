import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/load_error.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../dashboard/presentation/desktop/desktop_bar_chart.dart';
import '../../../dashboard/presentation/desktop/desktop_home_models.dart';
import '../../../dashboard/presentation/desktop/desktop_segmented_control.dart';
import '../providers/reports_provider.dart';
import 'desktop_report_pane.dart';
import 'desktop_report_tabs.dart';

/// The customers report reads the device's customer table directly on the
/// phone; the computer page wraps the same call in a provider.
final desktopCustomerReportProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    if (!ref.watch(permissionsProvider).canSeeCustomers) {
      return const [];
    }
    return getIt<AppDatabase>().getAllCustomers();
  },
);

enum _RangeChoice { today, week, month, custom }

/// Reports on the computer: a report picker, the period switch, then one
/// chart above a summary table with a totals row. Reads the same providers as
/// the phone's report sheets.
class DesktopReportsView extends ConsumerStatefulWidget {
  const DesktopReportsView({
    super.key,
    required this.onNavigate,
    this.gate,
    this.initialKind,
  });

  /// Go to another page: `/reports/analytics`, `/receipt/<id>`, `/`.
  final ValueChanged<String> onNavigate;

  /// Asks the licence whether this report may open. Null allows everything.
  final Future<bool> Function(DesktopReportKind kind)? gate;
  final DesktopReportKind? initialKind;

  @override
  ConsumerState<DesktopReportsView> createState() => _DesktopReportsViewState();
}

class _DesktopReportsViewState extends ConsumerState<DesktopReportsView> {
  late DesktopReportKind _kind =
      widget.initialKind ?? DesktopReportsHandoff.take();

  Future<void> _select(DesktopReportKind kind) async {
    if (kind == _kind) return;
    if (kind == DesktopReportKind.customers &&
        !ref.read(permissionsProvider).canSeeCustomers) {
      return;
    }
    final gate = widget.gate;
    if (kind.needsAnalyticsLicence && gate != null && !await gate(kind)) {
      return;
    }
    if (!mounted) return;
    final route = kind.route;
    if (route != null) {
      widget.onNavigate(route);
      return;
    }
    setState(() => _kind = kind);
  }

  void _refresh() {
    ref.invalidate(salesListProvider);
    ref.invalidate(paymentMethodProvider);
    ref.invalidate(cashierPerformanceProvider);
    ref.invalidate(categorySalesProvider);
    ref.invalidate(topProductsProvider);
    ref.invalidate(inventoryReportProvider);
    ref.invalidate(desktopCustomerReportProvider);
  }

  _RangeChoice _choiceOf(DateRangeState range) {
    if (range.label == 'Today') return _RangeChoice.today;
    if (range.label == 'This Week') return _RangeChoice.week;
    if (range.label == 'This Month') return _RangeChoice.month;
    return _RangeChoice.custom;
  }

  Future<void> _chooseRange(_RangeChoice choice) async {
    final notifier = ref.read(dateRangeProvider.notifier);
    switch (choice) {
      case _RangeChoice.today:
        notifier.setToday();
      case _RangeChoice.week:
        notifier.setThisWeek();
      case _RangeChoice.month:
        notifier.setThisMonth();
      case _RangeChoice.custom:
        final current = ref.read(dateRangeProvider);
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2024),
          lastDate: DateTime.now(),
          initialDateRange: DateTimeRange(start: current.from, end: current.to),
          helpText: 'Choose the days to report on',
        );
        if (picked != null) notifier.setCustom(picked.start, picked.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(dateRangeProvider);
    final choice = _choiceOf(range);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: 'Reports',
          padding: const EdgeInsets.fromLTRB(
            DesktopTokens.gutter,
            16,
            DesktopTokens.gutter,
            0,
          ),
          actions: [
            if (_kind.usesDateRange)
              SegmentedRangeControl<_RangeChoice>(
                semanticLabel: 'Period',
                selected: choice,
                onChanged: _chooseRange,
                options: [
                  const SegmentedOption(_RangeChoice.today, 'Today'),
                  const SegmentedOption(_RangeChoice.week, 'This week'),
                  const SegmentedOption(_RangeChoice.month, 'This month'),
                  SegmentedOption(
                    _RangeChoice.custom,
                    choice == _RangeChoice.custom ? range.label : 'Custom',
                    tooltip: 'Pick any start and end day',
                  ),
                ],
              ),
            Tooltip(
              message: 'Refresh',
              child: IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ),
          ],
          bottom: DesktopReportTabs(selected: _kind, onSelect: _select),
        ),
        Expanded(child: _pane(context, range)),
      ],
    );
  }

  Widget _pane(BuildContext context, DateRangeState range) {
    return switch (_kind) {
      DesktopReportKind.sales => _salesPane(range),
      DesktopReportKind.payments => _paymentsPane(range),
      DesktopReportKind.cashiers => _cashiersPane(range),
      DesktopReportKind.categories => _categoriesPane(range),
      DesktopReportKind.products => _productsPane(range),
      DesktopReportKind.stock => _stockPane(),
      DesktopReportKind.customers => _customersPane(),
      // These two have their own routes; the tab strip navigates there.
      _ => const SizedBox.shrink(),
    };
  }

  // ── Helpers ───────────────────────────────────────────────────────

  static double _n(Object? v) => (v as num?)?.toDouble() ?? 0;

  static String _short(String text, [int max = 13]) =>
      text.length <= max ? text : '${text.substring(0, max - 1)}…';

  static String _pct(double part, double whole) =>
      whole > 0 ? '${(part / whole * 100).toStringAsFixed(1)}%' : '—';

  static String _qty(double qty) => qty == qty.roundToDouble()
      ? qty.round().toString()
      : qty.toStringAsFixed(1);

  String _rangeText(DateRangeState range) {
    final fmt = DateFormat('d MMM');
    final sameDay = range.from.year == range.to.year &&
        range.from.month == range.to.month &&
        range.from.day == range.to.day;
    return sameDay
        ? '${range.label} · ${fmt.format(range.from)}'
        : '${range.label} · ${fmt.format(range.from)} to ${fmt.format(range.to)}';
  }

  /// Rows, the loading flag and the error text for a provider's state.
  ({List<T>? rows, bool loading, String? error}) _read<T>(
    AsyncValue<List<T>> async,
  ) =>
      (
        rows: async.valueOrNull,
        loading: !async.hasValue && !async.hasError,
        error: !async.hasValue && async.hasError
            ? loadErrorSubtitle(async.error)
            : null,
      );

  Widget _empty({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) =>
      DesktopEmptyState(
        icon: icon,
        title: title,
        message: message,
        action: action,
      );

  Widget get _startSale => FilledButton.icon(
        onPressed: () => widget.onNavigate('/'),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Start a sale'),
      );

  Color _methodColor(String method) {
    final m = method.toUpperCase();
    if (m == 'CASH') return MoneyColors.cash;
    if (m.contains('MPESA') || m.contains('M-PESA') || m.contains('RECORDED')) {
      return MoneyColors.recorded;
    }
    if (m == 'CREDIT') return MoneyColors.credit;
    return MoneyColors.verified;
  }

  List<DesktopChartBar> _rankBars<T>(
    List<T> rows,
    String Function(T) name,
    double Function(T) value,
    String Function(T) detail,
  ) {
    final top = [...rows]..sort((a, b) => value(b).compareTo(value(a)));
    return [
      for (final row in top.take(10))
        DesktopChartBar(
          label: _short(name(row)),
          value: value(row),
          tooltipTitle: name(row),
          tooltipValue: '${formatMoney(value(row))} · ${detail(row)}',
        ),
    ];
  }

  // ── Sales ─────────────────────────────────────────────────────────

  Widget _salesPane(DateRangeState range) {
    final r = _read(ref.watch(salesListProvider));
    final rows = r.rows;

    DateTime when(Map<String, dynamic> m) =>
        DateTime.tryParse(m['createdAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now();

    List<DesktopChartBar>? bars;
    var singleDay = true;
    if (rows != null) {
      final days = DateTime(range.to.year, range.to.month, range.to.day)
              .difference(
                  DateTime(range.from.year, range.from.month, range.from.day))
              .inDays +
          1;
      singleDay = days <= 1;
      if (singleDay) {
        bars = hourlyBarsFromSales([
          for (final m in rows)
            HomeSaleRow(
              id: '${m['id']}',
              receiptNumber: '${m['receiptNumber']}',
              createdAt: when(m),
              paymentMethod: '${m['paymentMethod']}',
              total: _n(m['totalAmount']),
            ),
        ]);
      } else {
        final key = DateFormat('yyyy-MM-dd');
        final byDate = <String, ({double amount, int count})>{};
        for (final m in rows) {
          final k = key.format(when(m));
          final prev = byDate[k];
          byDate[k] = (
            amount: (prev?.amount ?? 0) + _n(m['totalAmount']),
            count: (prev?.count ?? 0) + 1,
          );
        }
        bars = dailyBars(
          end: range.to,
          days: days.clamp(1, 62),
          byDate: byDate,
        );
      }
    }

    final fmt = DateFormat('d MMM yyyy, h:mm a');
    final columns = <DesktopColumn<Map<String, dynamic>>>[
      DesktopColumn(
        label: 'Receipt',
        flex: 3,
        minWidth: 120,
        sortBy: (m) => '${m['receiptNumber']}',
        cell: (c, m) =>
            DesktopCellText('${m['receiptNumber'] ?? ''}', strong: true),
      ),
      DesktopColumn(
        label: 'Date and time',
        width: 178,
        sortBy: (m) => when(m),
        cell: (c, m) => DesktopCellText(fmt.format(when(m)), muted: true),
      ),
      DesktopColumn(
        label: 'Paid with',
        flex: 2,
        minWidth: 120,
        sortBy: (m) => '${m['paymentMethod']}',
        cell: (c, m) => _MethodCell(
          label: paymentMethodLabel('${m['paymentMethod']}'),
          color: _methodColor('${m['paymentMethod']}'),
        ),
      ),
      DesktopColumn(
        label: 'Total',
        width: 140,
        numeric: true,
        sortBy: (m) => _n(m['totalAmount']),
        cell: (c, m) => DesktopCellText(
          formatMoney(_n(m['totalAmount'])),
          numeric: true,
          strong: true,
        ),
      ),
    ];

    return ReportPane<Map<String, dynamic>>(
      key: const ValueKey('sales'),
      rows: rows,
      loading: r.loading,
      error: r.error,
      onRetry: () => ref.invalidate(salesListProvider),
      columns: columns,
      rowId: (m) => '${m['id']}',
      initialSortColumn: 1,
      initialSortAscending: false,
      chartTitle: singleDay ? 'Sales by hour' : 'Sales by day',
      chartSubtitle: _rangeText(range),
      bars: bars ?? const [],
      onRowActivated: (m) => widget.onNavigate('/receipt/${m['id']}'),
      totals: (list) => [
        countLabel(list.length, 'sale'),
        null,
        null,
        formatMoney(list.fold<double>(0, (a, m) => a + _n(m['totalAmount']))),
      ],
      empty: _empty(
        icon: Icons.receipt_long_outlined,
        title: 'No sales in this period',
        message:
            'Pick a wider period above, or ring up a sale and it will show here.',
        action: _startSale,
      ),
    );
  }

  // ── Payments ──────────────────────────────────────────────────────

  Widget _paymentsPane(DateRangeState range) {
    final r = _read(ref.watch(paymentMethodProvider));
    final rows = r.rows;
    final total =
        rows?.fold<double>(0, (a, m) => a + _n(m['totalAmount'])) ?? 0;

    final columns = <DesktopColumn<Map<String, dynamic>>>[
      DesktopColumn(
        label: 'Method',
        flex: 3,
        minWidth: 140,
        sortBy: (m) => '${m['paymentMethod']}',
        cell: (c, m) => _MethodCell(
          label: paymentMethodLabel('${m['paymentMethod']}'),
          color: _methodColor('${m['paymentMethod']}'),
        ),
      ),
      DesktopColumn(
        label: 'Transactions',
        width: 130,
        numeric: true,
        sortBy: (m) => _n(m['count']),
        cell: (c, m) => DesktopCellText(_qty(_n(m['count'])), numeric: true),
      ),
      DesktopColumn(
        label: 'Share',
        width: 100,
        numeric: true,
        cell: (c, m) =>
            DesktopCellText(_pct(_n(m['totalAmount']), total), muted: true),
      ),
      DesktopColumn(
        label: 'Amount',
        width: 150,
        numeric: true,
        sortBy: (m) => _n(m['totalAmount']),
        cell: (c, m) => DesktopCellText(
          formatMoney(_n(m['totalAmount'])),
          numeric: true,
          strong: true,
        ),
      ),
    ];

    return ReportPane<Map<String, dynamic>>(
      key: const ValueKey('payments'),
      rows: rows,
      loading: r.loading,
      error: r.error,
      onRetry: () => ref.invalidate(paymentMethodProvider),
      columns: columns,
      rowId: (m) => '${m['paymentMethod']}',
      initialSortColumn: 3,
      initialSortAscending: false,
      chartTitle: 'Takings by payment method',
      chartSubtitle: _rangeText(range),
      bars: rows == null
          ? const []
          : _rankBars(
              rows,
              (m) => paymentMethodLabel('${m['paymentMethod']}'),
              (m) => _n(m['totalAmount']),
              (m) =>
                  '${countLabel(_n(m['count']), 'transaction')} · ${_pct(_n(m['totalAmount']), total)}',
            ),
      totals: (list) => [
        'Total',
        _qty(list.fold<double>(0, (a, m) => a + _n(m['count']))),
        list.isEmpty ? null : '100%',
        formatMoney(total),
      ],
      empty: _empty(
        icon: Icons.payments_outlined,
        title: 'No payments in this period',
        message: 'Payments show here by method once you have made sales.',
        action: _startSale,
      ),
    );
  }

  // ── Cashiers ──────────────────────────────────────────────────────

  Widget _cashiersPane(DateRangeState range) {
    final r = _read(ref.watch(cashierPerformanceProvider));
    final rows = r.rows;
    final total =
        rows?.fold<double>(0, (a, m) => a + _n(m['totalAmount'])) ?? 0;

    String name(Map<String, dynamic> m) => '${m['cashierId'] ?? 'Staff'}';
    final columns = <DesktopColumn<Map<String, dynamic>>>[
      DesktopColumn(
        label: 'Cashier',
        flex: 3,
        minWidth: 140,
        sortBy: name,
        cell: (c, m) => DesktopCellText(name(m), strong: true),
      ),
      DesktopColumn(
        label: 'Sales',
        width: 100,
        numeric: true,
        sortBy: (m) => _n(m['count']),
        cell: (c, m) => DesktopCellText(_qty(_n(m['count'])), numeric: true),
      ),
      DesktopColumn(
        label: 'Average sale',
        width: 140,
        numeric: true,
        cell: (c, m) => DesktopCellText(
          formatMoney(
              _n(m['count']) > 0 ? _n(m['totalAmount']) / _n(m['count']) : 0),
          numeric: true,
          muted: true,
        ),
      ),
      DesktopColumn(
        label: 'Share',
        width: 90,
        numeric: true,
        cell: (c, m) =>
            DesktopCellText(_pct(_n(m['totalAmount']), total), muted: true),
      ),
      DesktopColumn(
        label: 'Takings',
        width: 150,
        numeric: true,
        sortBy: (m) => _n(m['totalAmount']),
        cell: (c, m) => DesktopCellText(
          formatMoney(_n(m['totalAmount'])),
          numeric: true,
          strong: true,
        ),
      ),
    ];

    return ReportPane<Map<String, dynamic>>(
      key: const ValueKey('cashiers'),
      rows: rows,
      loading: r.loading,
      error: r.error,
      onRetry: () => ref.invalidate(cashierPerformanceProvider),
      columns: columns,
      rowId: name,
      initialSortColumn: 4,
      initialSortAscending: false,
      chartTitle: 'Takings by cashier',
      chartSubtitle: _rangeText(range),
      bars: rows == null
          ? const []
          : _rankBars(
              rows,
              name,
              (m) => _n(m['totalAmount']),
              (m) => countLabel(_n(m['count']), 'sale'),
            ),
      totals: (list) => [
        'Total',
        _qty(list.fold<double>(0, (a, m) => a + _n(m['count']))),
        null,
        list.isEmpty ? null : '100%',
        formatMoney(total),
      ],
      empty: _empty(
        icon: Icons.badge_outlined,
        title: 'No cashier sales in this period',
        message: 'Sales per cashier show here once someone has made a sale.',
        action: _startSale,
      ),
    );
  }

  // ── Categories ────────────────────────────────────────────────────

  Widget _categoriesPane(DateRangeState range) {
    final r = _read(ref.watch(categorySalesProvider));
    final rows = r.rows;
    final total =
        rows?.fold<double>(0, (a, m) => a + _n(m['totalRevenue'])) ?? 0;

    String name(Map<String, dynamic> m) =>
        '${m['categoryName'] ?? 'Uncategorised'}';
    final columns = <DesktopColumn<Map<String, dynamic>>>[
      DesktopColumn(
        label: 'Category',
        flex: 3,
        minWidth: 140,
        sortBy: name,
        cell: (c, m) => DesktopCellText(name(m), strong: true),
      ),
      DesktopColumn(
        label: 'Items sold',
        width: 120,
        numeric: true,
        sortBy: (m) => _n(m['totalQty']),
        cell: (c, m) => DesktopCellText(_qty(_n(m['totalQty'])), numeric: true),
      ),
      DesktopColumn(
        label: 'Share',
        width: 100,
        numeric: true,
        cell: (c, m) =>
            DesktopCellText(_pct(_n(m['totalRevenue']), total), muted: true),
      ),
      DesktopColumn(
        label: 'Sales',
        width: 150,
        numeric: true,
        sortBy: (m) => _n(m['totalRevenue']),
        cell: (c, m) => DesktopCellText(
          formatMoney(_n(m['totalRevenue'])),
          numeric: true,
          strong: true,
        ),
      ),
    ];

    return ReportPane<Map<String, dynamic>>(
      key: const ValueKey('categories'),
      rows: rows,
      loading: r.loading,
      error: r.error,
      onRetry: () => ref.invalidate(categorySalesProvider),
      columns: columns,
      rowId: name,
      initialSortColumn: 3,
      initialSortAscending: false,
      chartTitle: 'Sales by category',
      chartSubtitle: _rangeText(range),
      bars: rows == null
          ? const []
          : _rankBars(
              rows,
              name,
              (m) => _n(m['totalRevenue']),
              (m) =>
                  '${countLabel(_n(m['totalQty']), 'item')} · ${_pct(_n(m['totalRevenue']), total)}',
            ),
      totals: (list) => [
        'Total',
        _qty(list.fold<double>(0, (a, m) => a + _n(m['totalQty']))),
        list.isEmpty ? null : '100%',
        formatMoney(total),
      ],
      empty: _empty(
        icon: Icons.category_outlined,
        title: 'No category sales in this period',
        message:
            'Sales by category show here. Give your products a category to see them grouped.',
        action: _startSale,
      ),
    );
  }

  // ── Top products ──────────────────────────────────────────────────

  Widget _productsPane(DateRangeState range) {
    final r = _read(ref.watch(topProductsProvider));
    final rows = r.rows;

    String name(Map<String, dynamic> m) => '${m['productName'] ?? 'Unknown'}';
    final columns = <DesktopColumn<Map<String, dynamic>>>[
      DesktopColumn(
        label: 'Product',
        flex: 3,
        minWidth: 160,
        sortBy: name,
        cell: (c, m) => Tooltip(
          message: name(m),
          child: DesktopCellText(name(m), strong: true),
        ),
      ),
      DesktopColumn(
        label: 'Units sold',
        width: 120,
        numeric: true,
        sortBy: (m) => _n(m['totalQty']),
        cell: (c, m) => DesktopCellText(_qty(_n(m['totalQty'])), numeric: true),
      ),
      DesktopColumn(
        label: 'Sales',
        width: 150,
        numeric: true,
        sortBy: (m) => _n(m['totalRevenue']),
        cell: (c, m) => DesktopCellText(
          formatMoney(_n(m['totalRevenue'])),
          numeric: true,
          strong: true,
        ),
      ),
    ];

    return ReportPane<Map<String, dynamic>>(
      key: const ValueKey('products'),
      rows: rows,
      loading: r.loading,
      error: r.error,
      onRetry: () => ref.invalidate(topProductsProvider),
      columns: columns,
      rowId: name,
      initialSortColumn: 1,
      initialSortAscending: false,
      chartTitle: 'Best sellers by sales',
      chartSubtitle: _rangeText(range),
      bars: rows == null
          ? const []
          : _rankBars(
              rows,
              name,
              (m) => _n(m['totalRevenue']),
              (m) => countLabel(_n(m['totalQty']), 'unit'),
            ),
      totals: (list) => [
        'Top ${list.length}',
        _qty(list.fold<double>(0, (a, m) => a + _n(m['totalQty']))),
        formatMoney(list.fold<double>(0, (a, m) => a + _n(m['totalRevenue']))),
      ],
      empty: _empty(
        icon: Icons.star_outline_rounded,
        title: 'No products sold in this period',
        message: 'Your best sellers rank here after the first sales.',
        action: _startSale,
      ),
    );
  }

  // ── Stock ─────────────────────────────────────────────────────────

  Widget _stockPane() {
    final r = _read(ref.watch(inventoryReportProvider));
    final rows = r.rows;

    double stock(Map<String, dynamic> m) => _n(m['stock']);
    double minStock(Map<String, dynamic> m) => _n(m['minStock']);
    bool isOut(Map<String, dynamic> m) => stock(m) <= 0;
    bool isLow(Map<String, dynamic> m) =>
        !isOut(m) && minStock(m) > 0 && stock(m) <= minStock(m);

    final out = rows?.where(isOut).length ?? 0;
    final low = rows?.where(isLow).length ?? 0;

    final columns = <DesktopColumn<Map<String, dynamic>>>[
      DesktopColumn(
        label: 'Product',
        flex: 4,
        minWidth: 180,
        sortBy: (m) => '${m['name']}',
        cell: (c, m) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DesktopCellText('${m['name'] ?? ''}', strong: true),
            DesktopCellText('${m['sku'] ?? ''}', muted: true),
          ],
        ),
      ),
      DesktopColumn(
        label: 'Category',
        flex: 2,
        minWidth: 110,
        sortBy: (m) => '${m['categoryName']}',
        cell: (c, m) =>
            DesktopCellText('${m['categoryName'] ?? ''}', muted: true),
      ),
      DesktopColumn(
        label: 'In stock',
        width: 110,
        numeric: true,
        sortBy: stock,
        cell: (c, m) =>
            DesktopCellText(_qty(stock(m)), numeric: true, strong: true),
      ),
      DesktopColumn(
        label: 'Minimum',
        width: 110,
        numeric: true,
        sortBy: minStock,
        cell: (c, m) =>
            DesktopCellText(_qty(minStock(m)), numeric: true, muted: true),
      ),
      DesktopColumn(
        label: 'Status',
        width: 130,
        cell: (c, m) => isOut(m)
            ? const DesktopStatusChip(
                label: 'Out of stock',
                color: DesignColors.error,
              )
            : isLow(m)
                ? const DesktopStatusChip(
                    label: 'Low stock',
                    color: DesignColors.warning,
                  )
                : const DesktopStatusChip(
                    label: 'In stock',
                    color: DesignColors.success,
                  ),
      ),
    ];

    return ReportPane<Map<String, dynamic>>(
      key: const ValueKey('stock'),
      rows: rows,
      loading: r.loading,
      error: r.error,
      onRetry: () => ref.invalidate(inventoryReportProvider),
      columns: columns,
      rowId: (m) => '${m['id'] ?? m['name']}',
      initialSortColumn: 2,
      leading: DesktopMetricStrip(
        metrics: [
          DesktopMetric(
            label: 'Products',
            value: rows == null ? '—' : '${rows.length}',
            hint: 'Stock on hand right now',
          ),
          DesktopMetric(
            label: 'Low stock',
            value: rows == null ? '—' : '$low',
            hint: 'At or below the minimum',
          ),
          DesktopMetric(
            label: 'Out of stock',
            value: rows == null ? '—' : '$out',
            hint: 'Cannot be sold',
          ),
        ],
      ),
      totals: (list) => [
        '${list.length} products',
        null,
        _qty(list.fold<double>(0, (a, m) => a + stock(m))),
        null,
        '$low low · $out out',
      ],
      empty: _empty(
        icon: Icons.warehouse_outlined,
        title: 'No products to report on',
        message:
            'Add your products and their stock levels, then come back to see what is running low.',
        action: FilledButton(
          onPressed: () => widget.onNavigate('/products'),
          child: const Text('Add products'),
        ),
      ),
    );
  }

  // ── Customers ─────────────────────────────────────────────────────

  Widget _customersPane() {
    if (!ref.watch(permissionsProvider).canSeeCustomers) {
      return _empty(
        icon: Icons.lock_outline_rounded,
        title: 'Customer access required',
        message: 'You do not have permission to view customer details.',
      );
    }
    final r = _read(ref.watch(desktopCustomerReportProvider));
    final rows = r.rows;

    DateTime? last(Map<String, dynamic> m) =>
        DateTime.tryParse('${m['lastPurchaseAt'] ?? ''}');
    double spent(Map<String, dynamic> m) => _n(m['totalSpent']);
    double buys(Map<String, dynamic> m) => _n(m['totalPurchases']);

    final columns = <DesktopColumn<Map<String, dynamic>>>[
      DesktopColumn(
        label: 'Customer',
        flex: 3,
        minWidth: 160,
        sortBy: (m) => '${m['name']}',
        cell: (c, m) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DesktopCellText('${m['name'] ?? ''}', strong: true),
            if ('${m['phone'] ?? ''}'.isNotEmpty)
              DesktopCellText('${m['phone']}', muted: true),
          ],
        ),
      ),
      DesktopColumn(
        label: 'Purchases',
        width: 110,
        numeric: true,
        sortBy: buys,
        cell: (c, m) => DesktopCellText(_qty(buys(m)), numeric: true),
      ),
      DesktopColumn(
        label: 'Average',
        width: 120,
        numeric: true,
        cell: (c, m) => DesktopCellText(
          formatMoney(buys(m) > 0 ? spent(m) / buys(m) : 0),
          numeric: true,
          muted: true,
        ),
      ),
      DesktopColumn(
        label: 'Last purchase',
        width: 130,
        sortBy: (m) => last(m) ?? DateTime(2000),
        cell: (c, m) => DesktopCellText(
          last(m) == null ? 'Never' : DateFormat('d MMM yyyy').format(last(m)!),
          muted: true,
        ),
      ),
      DesktopColumn(
        label: 'Total spent',
        width: 150,
        numeric: true,
        sortBy: spent,
        cell: (c, m) =>
            DesktopCellText(formatMoney(spent(m)), numeric: true, strong: true),
      ),
    ];

    return ReportPane<Map<String, dynamic>>(
      key: const ValueKey('customers'),
      rows: rows,
      loading: r.loading,
      error: r.error,
      onRetry: () => ref.invalidate(desktopCustomerReportProvider),
      columns: columns,
      rowId: (m) => '${m['id'] ?? m['name']}',
      initialSortColumn: 4,
      initialSortAscending: false,
      chartTitle: 'Biggest customers',
      chartSubtitle: 'By total spent, all time',
      bars: rows == null
          ? const []
          : _rankBars(
              rows,
              (m) => '${m['name']}',
              spent,
              (m) => countLabel(buys(m), 'purchase'),
            ),
      totals: (list) => [
        countLabel(list.length, 'customer'),
        _qty(list.fold<double>(0, (a, m) => a + buys(m))),
        null,
        null,
        formatMoney(list.fold<double>(0, (a, m) => a + spent(m))),
      ],
      empty: _empty(
        icon: Icons.people_outline_rounded,
        title: 'No customers yet',
        message:
            'Customers you add or attach to a sale show here with what they have spent.',
        action: FilledButton(
          onPressed: () => widget.onNavigate('/customers'),
          child: const Text('Open customers'),
        ),
      ),
    );
  }
}

class _MethodCell extends StatelessWidget {
  const _MethodCell({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: p.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
