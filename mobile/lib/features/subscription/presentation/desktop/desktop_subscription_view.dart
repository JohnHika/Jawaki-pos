import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// One row of the invoice table, already formatted for display.
class DesktopInvoice {
  const DesktopInvoice({
    required this.id,
    required this.description,
    required this.dateLabel,
    required this.dateSort,
    required this.amountLabel,
    required this.amountSort,
    required this.statusLabel,
    required this.statusColor,
  });

  final String id;
  final String description;
  final String dateLabel;

  /// Milliseconds since epoch; 0 when the date is unknown.
  final int dateSort;
  final String amountLabel;
  final num amountSort;
  final String statusLabel;
  final Color statusColor;
}

/// The shop's own subscription as a computer page: plan figures across the
/// top, the invoice table, and a side pane that shows what the plan includes
/// or, once an invoice is picked, that invoice. Takes plain data.
class DesktopSubscriptionView extends StatefulWidget {
  const DesktopSubscriptionView({
    super.key,
    required this.planName,
    required this.statusLabel,
    required this.statusColor,
    required this.priceLabel,
    required this.dateCaption,
    required this.dateLabel,
    required this.features,
    required this.invoices,
    this.pendingPlanLabel,
    this.loadingPlan = false,
    this.loadingInvoices = false,
    this.changingPlan = false,
    this.error,
    this.onChoosePlan,
    this.onRefresh,
    this.onRetry,
    this.paidPlanNote = false,
  });

  /// null while loading or when the plan could not be read.
  final String? planName;
  final String statusLabel;
  final Color statusColor;
  final String priceLabel;

  /// "Trial ends" or "Next billing".
  final String dateCaption;
  final String dateLabel;
  final String? pendingPlanLabel;
  final List<String> features;
  final List<DesktopInvoice> invoices;
  final bool loadingPlan;
  final bool loadingInvoices;
  final bool changingPlan;
  final String? error;

  /// null hides the button (only a trial can choose its next plan).
  final VoidCallback? onChoosePlan;
  final VoidCallback? onRefresh;
  final VoidCallback? onRetry;

  /// Explains why the plan cannot be changed while a paid plan is running.
  final bool paidPlanNote;

  @override
  State<DesktopSubscriptionView> createState() =>
      _DesktopSubscriptionViewState();
}

class _DesktopSubscriptionViewState extends State<DesktopSubscriptionView> {
  String? _selectedId;

  DesktopInvoice? get _selected {
    for (final invoice in widget.invoices) {
      if (invoice.id == _selectedId) return invoice;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final w = widget;
    return LayoutBuilder(builder: (context, outer) {
      final short = outer.maxHeight < 620;
      return CallbackShortcuts(
        bindings: {
          if (w.onRefresh != null)
            const SingleActivator(LogicalKeyboardKey.keyR, control: true):
                w.onRefresh!,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_selectedId != null) setState(() => _selectedId = null);
          },
        },
        child: Focus(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopPageHeader(
                title: 'Subscription',
                subtitle: short
                    ? null
                    : 'Your plan with Arche Axon and what you have paid',
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                actions: [
                  if (w.onRefresh != null)
                    IconButton(
                      tooltip: 'Refresh (Ctrl+R)',
                      onPressed: w.onRefresh,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  if (w.onChoosePlan != null)
                    FilledButton.icon(
                      onPressed: w.changingPlan ? null : w.onChoosePlan,
                      style: desktopPrimaryButton(context),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: Text(w.changingPlan ? 'Saving plan…' : 'Choose plan'),
                    ),
                ],
              ),
              Expanded(
                child: w.loadingPlan && w.planName == null
                    ? const Center(child: CircularProgressIndicator())
                    : w.planName == null
                        ? DesktopEmptyState(
                            icon: Icons.error_outline_rounded,
                            title: 'Could not load subscription details',
                            message: w.error,
                            action: w.onRetry == null
                                ? null
                                : OutlinedButton(
                                    onPressed: w.onRetry,
                                    child: const Text('Try again'),
                                  ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _main(context, short)),
                              Container(
                                width: 340,
                                decoration: BoxDecoration(
                                  color: p.panel,
                                  border: Border(
                                    left: BorderSide(color: p.border),
                                  ),
                                ),
                                child: _pane(context),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _main(BuildContext context, bool short) {
    final p = context.desktop;
    final w = widget;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, short ? 10 : 14, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (w.error != null) ...[
            _ErrorLine(message: w.error!, onRetry: w.onRetry),
            const SizedBox(height: 10),
          ],
          DesktopMetricStrip(metrics: [
            DesktopMetric(label: 'Plan', value: w.planName ?? ''),
            DesktopMetric(
              label: 'Status',
              value: w.statusLabel,
              hint: w.pendingPlanLabel == null
                  ? null
                  : 'Next: ${w.pendingPlanLabel}',
            ),
            DesktopMetric(label: 'Per month', value: w.priceLabel),
            DesktopMetric(label: w.dateCaption, value: w.dateLabel),
          ]),
          if (w.paidPlanNote) ...[
            const SizedBox(height: 10),
            Text(
              'Your paid plan is active for this billing period. Plan changes are not available while it is active.',
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: p.dark ? p.panelAlt : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: Text(
                      'Invoice history',
                      style: GoogleFonts.sora(
                        color: p.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Divider(height: 1, color: p.border),
                  Expanded(child: _table(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context) {
    final w = widget;
    return DesktopDataTable<DesktopInvoice>(
      rows: w.invoices,
      rowId: (row) => row.id,
      selectedId: _selectedId,
      loading: w.loadingInvoices,
      minWidth: 0,
      initialSortColumn: 0,
      initialSortAscending: false,
      onRowSelected: (row) => setState(() => _selectedId = row.id),
      // Plain text, not DesktopEmptyState: the table can be very short on a
      // laptop at 125% scaling.
      empty: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No invoices yet. They appear after your first billing cycle.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              color: context.desktop.textMuted,
              fontSize: 13,
            ),
          ),
        ),
      ),
      columns: [
        DesktopColumn<DesktopInvoice>(
          label: 'Date',
          width: 130,
          sortBy: (row) => row.dateSort,
          cell: (context, row) => DesktopCellText(row.dateLabel, muted: true),
        ),
        DesktopColumn<DesktopInvoice>(
          label: 'Description',
          flex: 3,
          minWidth: 140,
          sortBy: (row) => row.description.toLowerCase(),
          cell: (context, row) => DesktopCellText(row.description, strong: true),
        ),
        DesktopColumn<DesktopInvoice>(
          label: 'Amount',
          width: 140,
          numeric: true,
          sortBy: (row) => row.amountSort,
          cell: (context, row) =>
              DesktopCellText(row.amountLabel, numeric: true, strong: true),
        ),
        DesktopColumn<DesktopInvoice>(
          label: 'Status',
          width: 110,
          sortBy: (row) => row.statusLabel,
          cell: (context, row) => DesktopStatusChip(
            label: row.statusLabel,
            color: row.statusColor,
          ),
        ),
      ],
    );
  }

  Widget _pane(BuildContext context) {
    final p = context.desktop;
    final invoice = _selected;
    if (invoice != null) {
      return DesktopInspector(
        title: 'Invoice',
        subtitle: invoice.dateLabel,
        onClose: () => setState(() => _selectedId = null),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Fact('Description', invoice.description),
            _Fact('Date', invoice.dateLabel),
            _Fact('Amount', invoice.amountLabel, numeric: true),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      'Status',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DesktopStatusChip(
                    label: invoice.statusLabel,
                    color: invoice.statusColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return DesktopInspector(
      title: 'Included in ${widget.planName}',
      subtitle: 'Everything this plan gives you',
      child: widget.features.isEmpty
          ? Text(
              'Plan details are not available.',
              style: TextStyle(color: p.textMuted, fontSize: 13),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final feature in widget.features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: DesignColors.success,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            feature,
                            style: GoogleFonts.plusJakartaSans(
                              color: p.text,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.numeric = false});

  final String label;
  final String value;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: numeric
                  ? DesignType.numeric(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    )
                  : GoogleFonts.plusJakartaSans(
                      color: p.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: DesignColors.error.withValues(alpha: p.dark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
        border: Border.all(color: DesignColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 18, color: context.readable(DesignColors.error)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: p.text, fontSize: 13, height: 1.35),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
