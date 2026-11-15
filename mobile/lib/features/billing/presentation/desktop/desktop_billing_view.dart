import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../../finance/presentation/desktop/desktop_figures_row.dart';

/// How loud a [DesktopBillingNotice] is.
enum DesktopBillingTone { info, warning, error }

/// A one-line message above the figures: saved details, grace period, errors.
class DesktopBillingNotice {
  const DesktopBillingNotice(this.message, {this.tone = DesktopBillingTone.warning});

  final String message;
  final DesktopBillingTone tone;
}

/// A button the page offers (pay, refresh, check status).
class DesktopBillingAction {
  const DesktopBillingAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final IconData icon;

  /// null disables the button.
  final VoidCallback? onPressed;
  final bool busy;
}

/// What the Renewal panel says and offers right now.
class DesktopBillingRenewal {
  const DesktopBillingRenewal({
    required this.message,
    this.primary,
    this.secondary,
    this.note,
  });

  final String message;

  /// The filled action (pay now). At most one per page.
  final DesktopBillingAction? primary;
  final DesktopBillingAction? secondary;

  /// Small print under the buttons (the payer email).
  final String? note;
}

/// Auto-renew line of the Renewal panel.
class DesktopBillingAutoRenew {
  const DesktopBillingAutoRenew({
    required this.enabled,
    required this.summary,
    required this.onConfigure,
  });

  final bool enabled;
  final String summary;
  final VoidCallback onConfigure;
}

/// What the licence covers.
class DesktopBillingLicence {
  const DesktopBillingLicence({
    required this.modules,
    required this.limits,
    this.licenceKey,
    this.expired = false,
  });

  /// Module name and whether this licence allows it.
  final List<({String label, bool allowed})> modules;
  final String limits;
  final String? licenceKey;
  final bool expired;
}

/// One invoice as the table and inspector show it.
class DesktopBillingInvoice {
  const DesktopBillingInvoice({
    required this.id,
    required this.description,
    required this.dateLabel,
    required this.amount,
    required this.amountLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.method,
    this.date,
    this.reference,
    this.check,
  });

  final String id;
  final String description;
  final String dateLabel;
  final DateTime? date;
  final double amount;
  final String amountLabel;
  final String statusLabel;
  final Color statusColor;

  /// Card, M-Pesa or empty.
  final String method;
  final String? reference;

  /// "Check payment" for an invoice still being confirmed.
  final DesktopBillingAction? check;
}

/// The Plan & Billing page on a computer: key figures, the renewal and plan
/// panels side by side, and the invoice history as a table with a side panel
/// for the selected invoice. Plain data in; the routed screen owns the
/// entitlement, the invoices and every payment call.
class DesktopBillingView extends StatefulWidget {
  const DesktopBillingView({
    super.key,
    required this.figures,
    required this.renewal,
    required this.invoices,
    this.title = 'Plan & billing',
    this.subtitle,
    this.notices = const [],
    this.loading = false,
    this.unavailable = false,
    this.onRefresh,
    this.planSummary,
    this.choosePlan,
    this.licence,
    this.autoRenew,
    this.onFreeDays,
    this.invoicesLoading = false,
    this.invoiceError,
    this.onRetryInvoices,
  });

  final String title;
  final String? subtitle;
  final List<DesktopFigure> figures;
  final List<DesktopBillingNotice> notices;

  /// First load of the plan: a spinner instead of figures.
  final bool loading;

  /// The plan could not be loaded at all.
  final bool unavailable;
  final VoidCallback? onRefresh;
  final DesktopBillingRenewal renewal;

  /// Admin only: the "Manage plan" sentence, and the action when a trial can
  /// pick its plan.
  final String? planSummary;
  final DesktopBillingAction? choosePlan;
  final DesktopBillingLicence? licence;

  /// Admin only.
  final DesktopBillingAutoRenew? autoRenew;
  final VoidCallback? onFreeDays;

  final List<DesktopBillingInvoice> invoices;
  final bool invoicesLoading;
  final String? invoiceError;
  final VoidCallback? onRetryInvoices;

  @override
  State<DesktopBillingView> createState() => _DesktopBillingViewState();
}

class _DesktopBillingViewState extends State<DesktopBillingView> {
  String? _selectedId;

  DesktopBillingInvoice? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final invoice in widget.invoices) {
      if (invoice.id == id) return invoice;
    }
    return null;
  }

  void _select(DesktopBillingInvoice? invoice) =>
      setState(() => _selectedId = invoice?.id);

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final selected = _selected;
    return CallbackShortcuts(
      bindings: {
        if (widget.onRefresh != null)
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              widget.onRefresh!,
        if (selected != null)
          const SingleActivator(LogicalKeyboardKey.escape): () => _select(null),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: widget.title,
              subtitle: widget.subtitle,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              actions: [
                if (widget.onRefresh != null)
                  IconButton(
                    key: const ValueKey('billing-refresh'),
                    tooltip: 'Refresh (Ctrl+R)',
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
              ],
            ),
            Divider(height: 1, color: p.border),
            Expanded(
              child: widget.loading
                  ? const Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : DesktopInspectorLayout(
                      inspectorWidth: 340,
                      onClose: () => _select(null),
                      inspector:
                          selected == null ? null : _inspector(context, selected),
                      main: _main(context, selected != null),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _main(BuildContext context, bool inspectorOpen) {
    return LayoutBuilder(
      builder: (context, box) {
        final dense = box.maxHeight < 560;
        final wide = box.maxWidth >= 860;
        final panels = [
          _renewalPanel(context),
          if (widget.planSummary != null || widget.licence != null)
            _planPanel(context),
        ];
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            14,
            inspectorOpen ? 16 : 24,
            DesktopTokens.gutter,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final notice in widget.notices) ...[
                    _NoticeBar(notice: notice),
                    const SizedBox(height: 8),
                  ],
                  if (widget.unavailable)
                    const _NoticeBar(
                      notice: DesktopBillingNotice(
                        'Could not load subscription details. Reconnect and refresh.',
                        tone: DesktopBillingTone.error,
                      ),
                    )
                  else
                    DesktopFiguresRow(figures: widget.figures, dense: dense),
                  const SizedBox(height: 14),
                  if (wide && panels.length == 2)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 5, child: panels[0]),
                          const SizedBox(width: 14),
                          Expanded(flex: 4, child: panels[1]),
                        ],
                      ),
                    )
                  else
                    for (final panel in panels) ...[
                      panel,
                      const SizedBox(height: 14),
                    ],
                  const SizedBox(height: 14),
                  _invoiceSection(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _renewalPanel(BuildContext context) {
    final p = context.desktop;
    final renewal = widget.renewal;
    final autoRenew = widget.autoRenew;
    return DesktopPanel(
      title: 'Renewal',
      subtitle: 'Pay the monthly subscription and set how it renews.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            renewal.message,
            style: GoogleFonts.plusJakartaSans(
              color: p.text,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          if (renewal.primary != null || renewal.secondary != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (renewal.primary != null)
                  _actionButton(context, renewal.primary!, filled: true),
                if (renewal.secondary != null)
                  _actionButton(context, renewal.secondary!),
              ],
            ),
          ],
          if (renewal.note != null) ...[
            const SizedBox(height: 8),
            Text(
              renewal.note!,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (autoRenew != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: p.border),
            _ToggleLine(
              key: const ValueKey('billing-auto-renew'),
              title: 'Auto-renew',
              summary: autoRenew.summary,
              value: autoRenew.enabled,
              onTap: autoRenew.onConfigure,
            ),
          ],
          if (widget.onFreeDays != null) ...[
            Divider(height: 1, color: p.border),
            _LinkLine(
              key: const ValueKey('billing-free-days'),
              title: 'Free days',
              summary:
                  'Invite other shops and get free days, or enter a promo code.',
              onTap: widget.onFreeDays!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _planPanel(BuildContext context) {
    final p = context.desktop;
    final licence = widget.licence;
    return DesktopPanel(
      title: 'Plan and licence',
      trailing: widget.choosePlan == null
          ? null
          : _actionButton(context, widget.choosePlan!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.planSummary != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.planSummary!,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          if (licence != null) ...[
            const SizedBox(height: 12),
            if (licence.expired) ...[
              Text(
                'Your licence has expired. Contact support to renew it.',
                style: GoogleFonts.plusJakartaSans(
                  color: p.dark ? const Color(0xFFFF8A80) : DesignColors.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final module in licence.modules)
                  SizedBox(
                    width: 176,
                    child: Row(
                      children: [
                        Icon(
                          module.allowed
                              ? Icons.check_rounded
                              : Icons.lock_outline_rounded,
                          size: 16,
                          color: module.allowed
                              ? DesignColors.success
                              : p.textFaint,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            module.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: module.allowed ? p.text : p.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              licence.limits,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
              ),
            ),
            if (licence.licenceKey != null) ...[
              const SizedBox(height: 4),
              SelectableText(
                'Licence key ${licence.licenceKey}',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context,
    DesktopBillingAction action, {
    bool filled = false,
  }) {
    final icon = action.busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(action.icon, size: 17);
    return filled
        ? FilledButton.icon(
            style: desktopPrimaryButton(context),
            onPressed: action.onPressed,
            icon: icon,
            label: Text(action.label),
          )
        : OutlinedButton.icon(
            style: desktopSecondaryButton(context),
            onPressed: action.onPressed,
            icon: icon,
            label: Text(action.label),
          );
  }

  Widget _invoiceSection(BuildContext context) {
    final p = context.desktop;
    final rows = widget.invoices;
    const headerHeight = 36.0;
    // Show up to eight rows, then let the table scroll inside its panel.
    final visible = rows.length.clamp(1, 8);
    final tableHeight = headerHeight + visible * DesktopTokens.rowHeight + 2;

    Widget body;
    if (widget.invoiceError != null && rows.isEmpty) {
      body = _InlineEmpty(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load invoices",
        message: widget.invoiceError!,
        action: widget.onRetryInvoices == null
            ? null
            : OutlinedButton(
                style: desktopSecondaryButton(context),
                onPressed: widget.onRetryInvoices,
                child: const Text('Try again'),
              ),
      );
    } else {
      body = SizedBox(
        height: rows.isEmpty && !widget.invoicesLoading ? headerHeight + 98 : tableHeight,
        child: DesktopDataTable<DesktopBillingInvoice>(
          rows: rows,
          rowId: (invoice) => invoice.id,
          selectedId: _selectedId,
          onRowSelected: _select,
          onRowActivated: _select,
          loading: widget.invoicesLoading && rows.isEmpty,
          minWidth: 600,
          initialSortColumn: 0,
          initialSortAscending: false,
          empty: const _InlineEmpty(
            icon: Icons.receipt_long_outlined,
            title: 'No invoices yet',
            message: 'Invoices appear at each monthly renewal.',
          ),
          columns: [
            DesktopColumn<DesktopBillingInvoice>(
              label: 'Date',
              width: 128,
              sortBy: (invoice) =>
                  invoice.date ?? DateTime.fromMillisecondsSinceEpoch(0),
              cell: (_, invoice) => DesktopCellText(invoice.dateLabel),
            ),
            DesktopColumn<DesktopBillingInvoice>(
              label: 'Invoice',
              flex: 3,
              minWidth: 160,
              sortBy: (invoice) => invoice.description.toLowerCase(),
              cell: (_, invoice) =>
                  DesktopCellText(invoice.description, strong: true),
            ),
            DesktopColumn<DesktopBillingInvoice>(
              label: 'Paid with',
              flex: 2,
              minWidth: 150,
              sortBy: (invoice) => invoice.method,
              cell: (_, invoice) => DesktopCellText(
                [
                  if (invoice.method.isNotEmpty) invoice.method,
                  if (invoice.reference != null) invoice.reference!,
                ].join(' · '),
                muted: true,
              ),
            ),
            DesktopColumn<DesktopBillingInvoice>(
              label: 'Status',
              width: 150,
              sortBy: (invoice) => invoice.statusLabel,
              cell: (_, invoice) => Align(
                alignment: Alignment.centerLeft,
                child: DesktopStatusChip(
                  label: invoice.statusLabel,
                  color: invoice.statusColor,
                ),
              ),
            ),
            DesktopColumn<DesktopBillingInvoice>(
              label: 'Amount',
              width: 132,
              numeric: true,
              sortBy: (invoice) => invoice.amount,
              cell: (_, invoice) => DesktopCellText(
                invoice.amountLabel,
                numeric: true,
                strong: true,
              ),
            ),
          ],
        ),
      );
    }

    return DesktopPanel(
      title: 'Invoice history',
      subtitle: rows.isEmpty
          ? null
          : '${rows.length} ${rows.length == 1 ? 'invoice' : 'invoices'}',
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          if (widget.invoiceError != null && rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _NoticeBar(
                notice: DesktopBillingNotice(
                  widget.invoiceError!,
                  tone: DesktopBillingTone.error,
                ),
              ),
            ),
          Divider(height: 1, color: p.border),
          body,
        ],
      ),
    );
  }

  Widget _inspector(BuildContext context, DesktopBillingInvoice invoice) {
    final p = context.desktop;
    Widget fact(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value.isEmpty ? '—' : value,
                style: GoogleFonts.plusJakartaSans(
                  color: p.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );

    return DesktopInspector(
      key: ValueKey('billing-invoice-${invoice.id}'),
      title: invoice.description,
      subtitle: invoice.dateLabel,
      onClose: () => _select(null),
      footer: invoice.check == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: _actionButton(context, invoice.check!),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            invoice.amountLabel,
            style: DesignType.numeric(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: p.text,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: DesktopStatusChip(
              label: invoice.statusLabel,
              color: invoice.statusColor,
            ),
          ),
          const SizedBox(height: 18),
          fact('Paid with', invoice.method),
          fact('Reference', invoice.reference ?? ''),
          fact('Invoice number', invoice.id),
        ],
      ),
    );
  }
}

/// A short empty or error line that fits the invoice panel at any window height.
class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return SizedBox(
      height: 96,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Icon(icon, size: 26, color: p.textFaint),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.notice});

  final DesktopBillingNotice notice;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final color = switch (notice.tone) {
      DesktopBillingTone.info => p.textMuted,
      DesktopBillingTone.warning => DesignColors.warning,
      DesktopBillingTone.error => DesignColors.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.dark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            notice.tone == DesktopBillingTone.error
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice.message,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleLine extends StatelessWidget {
  const _ToggleLine({
    super.key,
    required this.title,
    required this.summary,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String summary;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return InkWell(
      onTap: onTap,
      hoverColor: p.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    summary,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            IgnorePointer(
              child: Switch(
                value: value,
                activeThumbColor: DesignColors.accent,
                onChanged: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkLine extends StatelessWidget {
  const _LinkLine({
    super.key,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return InkWell(
      onTap: onTap,
      hoverColor: p.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    summary,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: p.textFaint),
          ],
        ),
      ),
    );
  }
}
