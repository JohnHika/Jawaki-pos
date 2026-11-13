import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/desktop/desktop_facts.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// One stock request, read once from the server's map so the view does not
/// pass loosely typed maps around.
class DesktopStockRequest {
  const DesktopStockRequest({
    required this.id,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.unit,
    required this.priority,
    required this.status,
    required this.requester,
    required this.branch,
    required this.createdAt,
    required this.currentStock,
    this.reason,
  });

  final String id;
  final String productName;
  final String sku;
  final num quantity;
  final String unit;
  final String priority;
  final String status;
  final String requester;
  final String branch;
  final DateTime createdAt;
  final num currentStock;
  final String? reason;

  factory DesktopStockRequest.fromMap(Map<String, dynamic> m) {
    DateTime asDate(Object? v) {
      if (v is DateTime) return v;
      return DateTime.tryParse(v?.toString() ?? '')?.toLocal() ??
          DateTime.now();
    }

    return DesktopStockRequest(
      id: m['id'] as String? ?? '',
      productName: m['productName'] as String? ?? 'Unknown product',
      sku: m['productSku'] as String? ?? '',
      quantity: m['quantity'] as num? ?? 0,
      unit: m['unit'] as String? ?? 'piece',
      priority: (m['priority'] as String? ?? 'normal').toLowerCase(),
      status: m['status'] as String? ?? 'PENDING',
      requester: m['requestedByName'] as String? ?? 'Unknown',
      branch: m['branchName'] as String? ?? 'Unknown branch',
      createdAt: asDate(m['createdAt']),
      currentStock: m['currentStock'] as num? ?? 0,
      reason: m['reason'] as String?,
    );
  }
}

String _qty(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);

/// Stock requests on a computer: a status filter, a table of requests and the
/// selected request in a side panel with Approve / Reject / Mark fulfilled.
class DesktopStockRequestsView extends StatefulWidget {
  const DesktopStockRequestsView({
    super.key,
    required this.rows,
    required this.status,
    required this.onStatus,
    this.headerBottom,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    this.onApprove,
    this.onReject,
    this.onFulfill,
    this.onNewRequest,
  });

  final List<DesktopStockRequest> rows;

  /// PENDING, APPROVED, FULFILLED or ALL: the list the rows belong to.
  final String status;
  final ValueChanged<String> onStatus;
  final Widget? headerBottom;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onRefresh;
  final ValueChanged<String>? onApprove;
  final ValueChanged<String>? onReject;
  final ValueChanged<String>? onFulfill;
  final VoidCallback? onNewRequest;

  @override
  State<DesktopStockRequestsView> createState() =>
      _DesktopStockRequestsViewState();
}

class _DesktopStockRequestsViewState extends State<DesktopStockRequestsView> {
  final _search = TextEditingController();
  String _query = '';
  String? _selectedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DesktopStockRequest> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.rows;
    return [
      for (final r in widget.rows)
        if (r.productName.toLowerCase().contains(q) ||
            r.sku.toLowerCase().contains(q) ||
            r.requester.toLowerCase().contains(q) ||
            r.branch.toLowerCase().contains(q))
          r,
    ];
  }

  DesktopStockRequest? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final r in widget.rows) {
      if (r.id == id) return r;
    }
    return null;
  }

  static const _statuses = [
    ('PENDING', 'Pending'),
    ('APPROVED', 'Approved'),
    ('FULFILLED', 'Fulfilled'),
    ('ALL', 'All'),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: 'Stock requests',
          subtitle: 'Review what the team has asked for and approve it',
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          bottom: widget.headerBottom,
          actions: [
            if (widget.onNewRequest != null)
              OutlinedButton.icon(
                style: desktopSecondaryButton(context),
                onPressed: widget.onNewRequest,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New request'),
              ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: widget.loading ? null : widget.onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
          child: Row(
            children: [
              DesktopSearchField(
                controller: _search,
                hint: 'Search product, person or branch',
                width: 300,
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(width: 14),
              for (final s in _statuses) ...[
                DesktopFilterChip(
                  label: s.$2,
                  selected: widget.status == s.$1,
                  onTap: () {
                    setState(() => _selectedId = null);
                    widget.onStatus(s.$1);
                  },
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Expanded(
          child: DesktopInspectorLayout(
            main: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: _table(context, rows),
            ),
            inspector: selected == null ? null : _inspector(context, selected),
            onClose: () => setState(() => _selectedId = null),
          ),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, List<DesktopStockRequest> rows) {
    final p = DesktopPalette.of(context);
    if (widget.errorMessage != null && widget.rows.isEmpty) {
      return _frame(
        context,
        DesktopEmptyState(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load stock requests",
          message: widget.errorMessage,
          action: widget.onRetry == null
              ? null
              : OutlinedButton(
                  style: desktopSecondaryButton(context),
                  onPressed: widget.onRetry,
                  child: const Text('Try again'),
                ),
        ),
      );
    }
    return _frame(
      context,
      LayoutBuilder(builder: (context, box) {
        // With the side panel open the table is narrow: drop the columns the
        // panel repeats instead of scrolling sideways.
        final compact = box.maxWidth < 820;
        final tight = box.maxWidth < 700;
        return DesktopDataTable<DesktopStockRequest>(
          rows: rows,
          loading: widget.loading,
          rowId: (r) => r.id,
          selectedId: _selectedId,
          onRowSelected: (r) => setState(() => _selectedId = r.id),
          rowHeight: 48,
          minWidth: 560,
          initialSortColumn: 5,
          initialSortAscending: false,
          columns: [
            DesktopColumn<DesktopStockRequest>(
              label: 'Product',
              flex: 3,
              minWidth: 170,
              sortBy: (r) => r.productName.toLowerCase(),
              cell: (_, r) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DesktopCellText(r.productName, strong: true),
                  if (r.sku.isNotEmpty) DesktopCellText(r.sku, muted: true),
                ],
              ),
            ),
            DesktopColumn<DesktopStockRequest>(
              label: 'Priority',
              width: 92,
              sortBy: (r) => _priorityRank(r.priority),
              cell: (_, r) => _priorityChip(r.priority),
            ),
            DesktopColumn<DesktopStockRequest>(
              label: 'Asked for',
              width: 104,
              numeric: true,
              sortBy: (r) => r.quantity,
              cell: (_, r) =>
                  DesktopCellText('${_qty(r.quantity)} ${r.unit}', numeric: true),
            ),
            DesktopColumn<DesktopStockRequest>(
              label: 'In stock',
              width: 96,
              numeric: true,
              sortBy: (r) => r.currentStock,
              cell: (_, r) => DesktopCellText(
                _qty(r.currentStock),
                numeric: true,
                color: _stockColor(p, r),
              ),
            ),
            if (!compact)
              DesktopColumn<DesktopStockRequest>(
                label: 'Requested by',
                flex: 2,
                minWidth: 130,
                sortBy: (r) => r.requester.toLowerCase(),
                cell: (_, r) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DesktopCellText(r.requester),
                    DesktopCellText(r.branch, muted: true),
                  ],
                ),
              ),
            if (!tight)
            DesktopColumn<DesktopStockRequest>(
              label: 'When',
              width: 118,
              sortBy: (r) => r.createdAt.millisecondsSinceEpoch,
              cell: (_, r) => DesktopCellText(
                DateFormat('d MMM, h:mm a').format(r.createdAt),
                muted: true,
              ),
            ),
            DesktopColumn<DesktopStockRequest>(
              label: 'Status',
              width: 108,
              cell: (_, r) => _statusChip(r.status),
            ),
          ],
          footer: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Text(
              '${rows.length} ${rows.length == 1 ? 'request' : 'requests'}',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          empty: DesktopEmptyState(
            icon: Icons.inbox_outlined,
            title: widget.status == 'ALL'
                ? 'No stock requests yet'
                : 'No ${widget.status.toLowerCase()} requests',
            message: widget.status == 'PENDING'
                ? 'All caught up. Nothing is waiting for you.'
                : 'Stock requests will appear here.',
          ),
        );
      }),
    );
  }

  Widget _frame(BuildContext context, Widget child) {
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

  Widget _inspector(BuildContext context, DesktopStockRequest r) {
    final p = DesktopPalette.of(context);
    final pending = r.status == 'PENDING';
    final approved = r.status == 'APPROVED';
    return DesktopInspector(
      title: r.productName,
      subtitle: r.sku.isEmpty ? null : 'SKU ${r.sku}',
      onClose: () => setState(() => _selectedId = null),
      footer: pending
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: desktopSecondaryButton(context).copyWith(
                      foregroundColor:
                          WidgetStatePropertyAll(negativeText(p)),
                    ),
                    onPressed: widget.onReject == null
                        ? null
                        : () => widget.onReject!(r.id),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: desktopPrimaryButton(context),
                    onPressed: widget.onApprove == null
                        ? null
                        : () => widget.onApprove!(r.id),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            )
          : approved
              ? FilledButton.icon(
                  style: desktopPrimaryButton(context),
                  onPressed: widget.onFulfill == null
                      ? null
                      : () => widget.onFulfill!(r.id),
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('Mark as fulfilled'),
                )
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusChip(r.status),
              const SizedBox(width: 8),
              _priorityChip(r.priority),
            ],
          ),
          const SizedBox(height: 14),
          DesktopFactList(facts: [
            DesktopFact('Asked for', '${_qty(r.quantity)} ${r.unit}',
                numeric: true),
            DesktopFact(
              'In stock now',
              '${_qty(r.currentStock)} ${r.unit}',
              numeric: true,
              color: _stockColor(p, r),
            ),
            DesktopFact('Branch', r.branch),
            DesktopFact('Requested by', r.requester),
            DesktopFact(
              'Requested on',
              DateFormat('d MMM y, h:mm a').format(r.createdAt),
            ),
          ]),
          if (r.reason != null && r.reason!.trim().isNotEmpty) ...[
            const SizedBox(height: 20),
            const DesktopSectionLabel('REASON'),
            Text(
              r.reason!,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color negativeText(DesktopPalette p) =>
      p.dark ? DesignColors.error : const Color(0xFFB3261E);

  Color? _stockColor(DesktopPalette p, DesktopStockRequest r) {
    if (r.currentStock <= 0) return negativeText(p);
    if (r.currentStock < r.quantity) {
      return p.dark ? DesignColors.warning : const Color(0xFF9A5B00);
    }
    return null;
  }

  int _priorityRank(String priority) => switch (priority) {
        'urgent' => 0,
        'high' => 1,
        'low' => 3,
        _ => 2,
      };

  Widget _priorityChip(String priority) {
    final color = switch (priority) {
      'urgent' => DesignColors.error,
      'high' => DesignColors.warning,
      'low' => DesignColors.info,
      _ => DesignColors.brand,
    };
    final label = priority.isEmpty
        ? 'Normal'
        : priority[0].toUpperCase() + priority.substring(1);
    return DesktopStatusChip(label: label, color: color);
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'PENDING' => DesignColors.warning,
      'APPROVED' => DesignColors.info,
      'FULFILLED' => DesignColors.success,
      'REJECTED' => DesignColors.error,
      _ => DesignColors.brand,
    };
    final label = status.isEmpty
        ? 'Unknown'
        : status[0] + status.substring(1).toLowerCase();
    return DesktopStatusChip(label: label, color: color);
  }
}
