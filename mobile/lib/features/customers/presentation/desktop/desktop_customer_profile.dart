import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

enum _ProfileTab { overview, sales, schedule }

/// The right-hand side of the Customers page: who this is, what they owe, what
/// they bought and when payments are due.
///
/// Plain data in, callbacks out. The routed profile screen loads the data and
/// does every write; this widget only draws it.
class DesktopCustomerProfile extends StatefulWidget {
  const DesktopCustomerProfile({
    super.key,
    required this.customer,
    required this.customerLabel,
    required this.purchases,
    required this.topProducts,
    required this.installments,
    required this.canManageReceivables,
    required this.unscheduledBalance,
    required this.onStartSale,
    required this.onAddDueDate,
    required this.onRecordInstallment,
    required this.onCancelInstallment,
    required this.onOpenReceipt,
    this.purchasesFailed = false,
    this.installmentsFailed = false,
    this.loadError,
    this.onRetry,
    this.savingInstallmentIds = const {},
    this.creditCard,
    this.statementButton,
  });

  final Map<String, dynamic> customer;

  /// "Customer", for fallbacks and button text.
  final String customerLabel;
  final List<Map<String, dynamic>> purchases;
  final List<Map<String, dynamic>> topProducts;
  final List<Map<String, dynamic>> installments;
  final bool canManageReceivables;

  /// How much of the balance has no due date yet.
  final double unscheduledBalance;
  final VoidCallback onStartSale;
  final VoidCallback onAddDueDate;
  final ValueChanged<Map<String, dynamic>> onRecordInstallment;
  final ValueChanged<Map<String, dynamic>> onCancelInstallment;
  final ValueChanged<String> onOpenReceipt;
  final bool purchasesFailed;
  final bool installmentsFailed;
  final String? loadError;
  final VoidCallback? onRetry;
  final Set<String> savingInstallmentIds;

  /// The existing credit-limit card (it reads its own providers).
  final Widget? creditCard;

  /// The existing "Send statement" button.
  final Widget? statementButton;

  @override
  State<DesktopCustomerProfile> createState() => _DesktopCustomerProfileState();
}

class _DesktopCustomerProfileState extends State<DesktopCustomerProfile> {
  _ProfileTab _tab = _ProfileTab.overview;

  static final DateFormat _date = DateFormat('d MMM y');

  Map<String, dynamic> get _c => widget.customer;
  double get _balance => (_c['balance'] as num?)?.toDouble() ?? 0;
  String get _name {
    final n = _c['name']?.toString().trim() ?? '';
    return n.isEmpty ? widget.customerLabel : n;
  }

  String _dateLabel(Object? value) {
    final raw = value?.toString() ?? '';
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d != null) return _date.format(d);
    return raw.length > 10 ? raw.substring(0, 10) : raw;
  }

  String _receipt(Map<String, dynamic> sale) {
    final printed = sale['receiptNumber']?.toString().trim() ?? '';
    if (printed.isNotEmpty) return printed;
    final id = sale['id']?.toString() ?? '';
    return (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final phone = _c['phone']?.toString().trim() ?? '';
    final location = _c['location']?.toString().trim() ?? '';
    final subtitle = [
      if (phone.isNotEmpty) phone,
      if (location.isNotEmpty) location,
    ].join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.selected,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  String.fromCharCode(_name.runes.first).toUpperCase(),
                  style: GoogleFonts.sora(
                    color: p.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.sora(
                        color: p.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.textMuted,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.statementButton != null)
                    SizedBox(
                        width: 190, height: 36, child: widget.statementButton),
                  FilledButton.icon(
                    style: desktopPrimaryButton(context),
                    onPressed: widget.onStartSale,
                    icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                    label: const Text('Start sale'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _tabs(context),
        Divider(height: 1, color: p.border),
        if (widget.loadError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: _Notice(message: widget.loadError!, onRetry: widget.onRetry),
          ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _tabs(BuildContext context) {
    final p = context.desktop;
    Widget tab(_ProfileTab value, String label, {int? count}) {
      final selected = _tab == value;
      return InkWell(
        onTap: () => setState(() => _tab = value),
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
          margin: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? p.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  color: selected ? p.text : p.textMuted,
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          tab(_ProfileTab.overview, 'Overview'),
          tab(_ProfileTab.sales, 'Sales', count: widget.purchases.length),
          tab(
            _ProfileTab.schedule,
            'Payment schedule',
            count: widget.installments.length,
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_tab) {
      case _ProfileTab.overview:
        return _overview(context);
      case _ProfileTab.sales:
        return _salesTab(context);
      case _ProfileTab.schedule:
        return _scheduleTab(context);
    }
  }

  // ─── Overview ─────────────────────────────────────────────────────────

  Widget _overview(BuildContext context) {
    final p = context.desktop;
    final spent = (_c['totalSpent'] as num?)?.toDouble() ?? 0;

    final primary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopMetricStrip(
          metrics: [
            DesktopMetric(
              label: 'Balance owed',
              value: formatMoney(_balance),
              hint: _balance > 0 ? 'Not paid yet' : 'Paid up',
              hintColor: _balance > 0
                  ? (p.dark ? DesignColors.error : const Color(0xFFB3261E))
                  : p.textMuted,
            ),
            DesktopMetric(label: 'Total spent', value: formatMoney(spent)),
            DesktopMetric(
              label: 'Purchases',
              value: '${_c['totalPurchases'] ?? 0}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        DesktopPanel(
          title: 'Recent sales',
          trailing: widget.purchases.length > 5
              ? TextButton(
                  style: desktopLinkButton(context),
                  onPressed: () => setState(() => _tab = _ProfileTab.sales),
                  child: Text('See all ${widget.purchases.length}'),
                )
              : null,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: _recentSales(context),
        ),
        if (widget.topProducts.isNotEmpty) ...[
          const SizedBox(height: 16),
          DesktopPanel(
            title: 'Often bought',
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Column(
              children: [
                for (final item in widget.topProducts.take(5))
                  _line(
                    context,
                    item['productName']?.toString() ?? '',
                    '${item['timesBought'] ?? 0} times',
                  ),
              ],
            ),
          ),
        ],
      ],
    );

    final notes = _c['notes']?.toString().trim() ?? '';
    final secondary = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPanel(
          title: 'Details',
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Column(
            children: [
              _line(context, 'Phone', _orDash(_c['phone'])),
              _line(context, 'Location', _orDash(_c['location'])),
              _line(context, 'Loyalty points', '${_c['loyaltyPoints'] ?? 0}'),
              if (notes.isNotEmpty) _line(context, 'Notes', notes),
            ],
          ),
        ),
        if (widget.creditCard != null) ...[
          const SizedBox(height: 16),
          widget.creditCard!,
        ],
        const SizedBox(height: 16),
        _nextDue(context),
      ],
    );

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 760;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: primary),
                    const SizedBox(width: 20),
                    Expanded(child: secondary),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [primary, const SizedBox(height: 16), secondary],
                ),
        );
      },
    );
  }

  String _orDash(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? '—' : s;
  }

  Widget _line(BuildContext context, String label, String value) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentSales(BuildContext context) {
    final p = context.desktop;
    if (widget.purchasesFailed && widget.purchases.isEmpty) {
      return _quiet(context, 'Could not load purchase history. Try again.');
    }
    if (widget.purchases.isEmpty) {
      return _quiet(context, 'No purchases yet.');
    }
    return Column(
      children: [
        for (final sale in widget.purchases.take(5))
          InkWell(
            onTap: () => widget.onOpenReceipt(sale['id'].toString()),
            hoverColor: p.hover,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Receipt ${_receipt(sale)}',
                          style: GoogleFonts.plusJakartaSans(
                            color: p.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${_dateLabel(sale['createdAt'])} · ${paymentMethodLabel(sale['paymentMethod']?.toString())}',
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatMoney(sale['total'] as num?),
                    style: DesignType.numeric(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _quiet(BuildContext context, String text) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(color: p.textMuted, fontSize: 13),
      ),
    );
  }

  Widget _nextDue(BuildContext context) {
    final open = widget.installments.where((i) {
      final s = i['status']?.toString().toLowerCase();
      return s != 'paid' && s != 'cancelled';
    }).toList()
      ..sort((a, b) => (a['dueDate']?.toString() ?? '')
          .compareTo(b['dueDate']?.toString() ?? ''));
    return DesktopPanel(
      title: 'Next due',
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      trailing: widget.canManageReceivables && widget.unscheduledBalance > 0.005
          ? TextButton(
              style: desktopLinkButton(context),
              onPressed: widget.onAddDueDate,
              child: const Text('Add due date'),
            )
          : null,
      child: open.isEmpty
          ? _quiet(
              context,
              _balance > 0
                  ? 'No due dates yet. Add one when you agree a repayment date.'
                  : 'Nothing is owed.',
            )
          : Column(
              children: [
                _line(
                  context,
                  _dateLabel(open.first['dueDate']),
                  formatMoney(open.first['amount'] as num?),
                ),
              ],
            ),
    );
  }

  // ─── Sales tab ────────────────────────────────────────────────────────

  Widget _salesTab(BuildContext context) {
    final p = context.desktop;
    if (widget.purchasesFailed && widget.purchases.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load purchases",
        message: 'Your saved records are safe. Try again.',
        action: widget.onRetry == null
            ? null
            : OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: widget.onRetry,
                child: const Text('Try again'),
              ),
      );
    }
    if (widget.purchases.isEmpty) {
      return const DesktopEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No purchases yet',
        message:
            'Sales made to this customer show here. Start a sale to add the first.',
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.dark ? p.panelAlt : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: DesktopDataTable<Map<String, dynamic>>(
          minWidth: 480,
          rows: widget.purchases,
          rowId: (r) => r['id'].toString(),
          rowHeight: 44,
          onRowSelected: (r) => widget.onOpenReceipt(r['id'].toString()),
          columns: [
            DesktopColumn<Map<String, dynamic>>(
              label: 'Receipt',
              flex: 2,
              sortBy: (r) => _receipt(r),
              cell: (context, r) => DesktopCellText(_receipt(r), strong: true),
            ),
            DesktopColumn<Map<String, dynamic>>(
              label: 'Date',
              flex: 2,
              sortBy: (r) => r['createdAt']?.toString() ?? '',
              cell: (context, r) =>
                  DesktopCellText(_dateLabel(r['createdAt']), muted: true),
            ),
            DesktopColumn<Map<String, dynamic>>(
              label: 'Paid with',
              flex: 2,
              cell: (context, r) => DesktopCellText(
                paymentMethodLabel(r['paymentMethod']?.toString()),
                muted: true,
              ),
            ),
            DesktopColumn<Map<String, dynamic>>(
              label: 'Total',
              width: 120,
              numeric: true,
              sortBy: (r) => (r['total'] as num?) ?? 0,
              cell: (context, r) => DesktopCellText(
                formatMoney(r['total'] as num?),
                numeric: true,
              ),
            ),
          ],
          footer: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.purchases.length} ${widget.purchases.length == 1 ? 'sale' : 'sales'}',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Payment schedule tab ─────────────────────────────────────────────

  Widget _scheduleTab(BuildContext context) {
    final p = context.desktop;
    if (widget.installmentsFailed) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load due dates",
        message: 'Try again in a moment.',
        action: widget.onRetry == null
            ? null
            : OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: widget.onRetry,
                child: const Text('Try again'),
              ),
      );
    }
    final canAdd =
        widget.canManageReceivables && widget.unscheduledBalance > 0.005;
    if (widget.installments.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.event_note_outlined,
        title: 'No due dates yet',
        message: _balance > 0
            ? 'Schedule part of what they owe when you agree a repayment date. This does not add new debt.'
            : 'There is no balance to schedule.',
        action: canAdd
            ? FilledButton.icon(
                style: desktopPrimaryButton(context),
                onPressed: widget.onAddDueDate,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add due date'),
              )
            : null,
      );
    }
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);

    ({String label, Color color, bool open}) status(Map<String, dynamic> i) {
      final s = i['status']?.toString().toLowerCase();
      final due = DateTime.tryParse(i['dueDate']?.toString() ?? '');
      if (s == 'paid') {
        return (label: 'Paid', color: DesignColors.success, open: false);
      }
      if (s == 'cancelled') {
        return (
          label: 'Cancelled',
          color: DesignColors.textTertiary,
          open: false
        );
      }
      if (due != null && due.isBefore(startOfToday)) {
        return (label: 'Overdue', color: DesignColors.error, open: true);
      }
      return (label: 'Due', color: DesignColors.warning, open: true);
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canAdd)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  style: desktopSecondaryButton(context),
                  onPressed: widget.onAddDueDate,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add due date'),
                ),
              ),
            ),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: p.dark ? p.panelAlt : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border),
              ),
              child: DesktopDataTable<Map<String, dynamic>>(
                minWidth: 560,
                rows: widget.installments,
                rowId: (r) => r['id']?.toString() ?? '',
                rowHeight: 48,
                columns: [
                  DesktopColumn<Map<String, dynamic>>(
                    label: 'Due date',
                    flex: 2,
                    sortBy: (r) => r['dueDate']?.toString() ?? '',
                    cell: (context, r) => DesktopCellText(
                      _dateLabel(r['dueDate']),
                      strong: true,
                    ),
                  ),
                  DesktopColumn<Map<String, dynamic>>(
                    label: 'Amount',
                    width: 120,
                    numeric: true,
                    sortBy: (r) => (r['amount'] as num?) ?? 0,
                    cell: (context, r) => DesktopCellText(
                      formatMoney(r['amount'] as num?),
                      numeric: true,
                    ),
                  ),
                  DesktopColumn<Map<String, dynamic>>(
                    label: 'Status',
                    width: 120,
                    cell: (context, r) {
                      final s = status(r);
                      return DesktopStatusChip(label: s.label, color: s.color);
                    },
                  ),
                  DesktopColumn<Map<String, dynamic>>(
                    label: 'Note',
                    flex: 2,
                    cell: (context, r) => DesktopCellText(
                      r['note']?.toString() ?? '',
                      muted: true,
                    ),
                  ),
                  if (widget.canManageReceivables)
                    DesktopColumn<Map<String, dynamic>>(
                      label: '',
                      width: 170,
                      cell: (context, r) {
                        final s = status(r);
                        final saving = widget.savingInstallmentIds
                            .contains(r['id']?.toString() ?? '');
                        if (!s.open) return const SizedBox.shrink();
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              style: desktopLinkButton(context),
                              onPressed: saving
                                  ? null
                                  : () => widget.onRecordInstallment(r),
                              child: saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Record'),
                            ),
                            TextButton(
                              style: desktopLinkButton(context),
                              onPressed: saving
                                  ? null
                                  : () => widget.onCancelInstallment(r),
                              child: const Text('Cancel'),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: p.dark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: p.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: desktopLinkButton(context),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
