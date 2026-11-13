import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart' show kitNumber;
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/import_models.dart';

/// Desktop presentation of one API-backed container. All actions are supplied
/// by the routed screen, which remains the owner of permissions and mutations.
class DesktopImportDetailView extends StatelessWidget {
  const DesktopImportDetailView({
    super.key,
    required this.detail,
    required this.onBack,
    required this.onRefresh,
    required this.busy,
    required this.editable,
    required this.canAddTrader,
    required this.canPay,
    required this.showStatusActions,
    required this.statusActions,
    required this.costShare,
    this.onAddItem,
    this.onAddCost,
    this.onAddTrader,
    this.onRemoveItem,
    this.onRemoveCost,
    this.onRecordPayment,
    this.onRemovePayment,
    this.onRemoveParticipant,
  });

  final ImportDetail detail;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final bool busy;
  final bool editable;
  final bool canAddTrader;
  final bool canPay;
  final bool showStatusActions;
  final Widget statusActions;
  final double Function(ImportParticipantRow participant) costShare;
  final VoidCallback? onAddItem;
  final VoidCallback? onAddCost;
  final VoidCallback? onAddTrader;
  final ValueChanged<ImportItemRow>? onRemoveItem;
  final ValueChanged<ImportCostRow>? onRemoveCost;
  final ValueChanged<ImportParticipantRow>? onRecordPayment;
  final ValueChanged<ImportPaymentRow>? onRemovePayment;
  final ValueChanged<ImportParticipantRow>? onRemoveParticipant;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      importStatusLabel(detail.status),
      if (detail.reference != null && detail.reference!.isNotEmpty)
        detail.reference!,
      if (detail.origin != null && detail.origin!.isNotEmpty) detail.origin!,
      '${detail.currency} @ ${detail.fxRate.toStringAsFixed(2)}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: detail.title,
          subtitle: subtitle,
          leading: IconButton(
            tooltip: 'Back to containers (Esc)',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actions: [
            IconButton(
              tooltip: 'Refresh container',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
            if (editable && onAddItem != null)
              FilledButton.icon(
                style: desktopPrimaryButton(context),
                onPressed: busy ? null : onAddItem,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('Add goods'),
              ),
          ],
        ),
        Divider(height: 1, color: context.desktop.border),
        Expanded(
          child: DesktopContent(
            maxWidth: 1280,
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
            child: ListView(
              key: const ValueKey('desktop-import-detail-scroll'),
              children: [
                DesktopMetricStrip(
                  metrics: [
                    DesktopMetric(
                      label: 'Landed cost',
                      value: kesWhole(detail.landedKes),
                      hint: 'Goods plus costs on top',
                    ),
                    DesktopMetric(
                      label: 'Goods',
                      value: kesWhole(detail.goodsKes),
                    ),
                    DesktopMetric(
                      label: 'Costs on top',
                      value: kesWhole(detail.costsKes),
                      hint: detail.costsKes > 0
                          ? 'Adds ${detail.upliftPercent.toStringAsFixed(0)}%'
                          : 'No added costs',
                    ),
                  ],
                ),
                if (detail.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _WarningsPanel(warnings: detail.warnings),
                ],
                if (showStatusActions) ...[
                  const SizedBox(height: 12),
                  DesktopPanel(
                    title: 'Container progress',
                    padding: const EdgeInsets.all(12),
                    child: statusActions,
                  ),
                ],
                const SizedBox(height: 12),
                _goodsPanel(context),
                const SizedBox(height: 12),
                _costsPanel(context),
                const SizedBox(height: 12),
                _participantsPanel(context),
                if (detail.payments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _paymentsPanel(context),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _goodsPanel(BuildContext context) {
    final rows = detail.items;
    return DesktopPanel(
      title: 'Goods',
      subtitle: '${rows.length} line${rows.length == 1 ? '' : 's'}',
      padding: EdgeInsets.zero,
      clip: true,
      child: SizedBox(
        height: _tableHeight(rows.length),
        child: DesktopDataTable<ImportItemRow>(
          rows: rows,
          rowId: (row) => row.id,
          minWidth: 850,
          columns: [
            DesktopColumn<ImportItemRow>(
              label: 'Item',
              flex: 3,
              minWidth: 150,
              sortBy: (row) => row.description.toLowerCase(),
              cell: (context, row) => DesktopCellText(
                row.description,
                strong: true,
                color: row.productId == null ? DesignColors.warning : null,
              ),
            ),
            DesktopColumn<ImportItemRow>(
              label: 'Quantity',
              width: 86,
              numeric: true,
              sortBy: (row) => row.quantity,
              cell: (context, row) =>
                  DesktopCellText(kitNumber(row.quantity), numeric: true),
            ),
            DesktopColumn<ImportItemRow>(
              label: 'Unit',
              width: 88,
              cell: (context, row) => DesktopCellText(row.unit, muted: true),
            ),
            DesktopColumn<ImportItemRow>(
              label: 'Supplier cost',
              width: 132,
              numeric: true,
              sortBy: (row) => row.unitCost,
              cell: (context, row) => DesktopCellText(
                '${detail.currency} ${kitNumber(row.unitCost)}',
                numeric: true,
              ),
            ),
            DesktopColumn<ImportItemRow>(
              label: 'Landed / unit',
              width: 132,
              numeric: true,
              sortBy: (row) => row.landedUnitCostKes,
              cell: (context, row) => DesktopCellText(
                kesWhole(row.landedUnitCostKes),
                numeric: true,
              ),
            ),
            DesktopColumn<ImportItemRow>(
              label: 'Landed total',
              width: 132,
              numeric: true,
              sortBy: (row) => row.landedTotalKes,
              cell: (context, row) => DesktopCellText(
                kesWhole(row.landedTotalKes),
                numeric: true,
              ),
            ),
            if (detail.participants.length > 1)
              DesktopColumn<ImportItemRow>(
                label: 'Trader',
                width: 120,
                sortBy: (row) => detail.participantName(row.participantId),
                cell: (context, row) => DesktopCellText(
                  detail.participantName(row.participantId),
                  muted: true,
                ),
              ),
            if (editable && onRemoveItem != null)
              DesktopColumn<ImportItemRow>(
                label: '',
                width: 48,
                cell: (context, row) => IconButton(
                  tooltip: 'Remove ${row.description}',
                  visualDensity: VisualDensity.compact,
                  onPressed: busy ? null : () => onRemoveItem!(row),
                  icon: const Icon(Icons.close_rounded, size: 17),
                ),
              ),
          ],
          empty: const DesktopEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No goods recorded',
            message:
                'Add the goods in this container to see their landed cost.',
          ),
        ),
      ),
    );
  }

  Widget _costsPanel(BuildContext context) {
    final rows = detail.costs;
    return DesktopPanel(
      title: 'Costs on top',
      subtitle: 'Freight, duty, clearing and other landed costs',
      trailing: editable && onAddCost != null
          ? TextButton.icon(
              key: const ValueKey('desktop-import-add-cost'),
              onPressed: busy ? null : onAddCost,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Add cost'),
            )
          : null,
      padding: EdgeInsets.zero,
      clip: true,
      child: SizedBox(
        height: _tableHeight(rows.length),
        child: DesktopDataTable<ImportCostRow>(
          rows: rows,
          rowId: (row) => row.id,
          minWidth: 650,
          columns: [
            DesktopColumn<ImportCostRow>(
              label: 'Cost',
              flex: 3,
              minWidth: 160,
              sortBy: (row) => row.title.toLowerCase(),
              cell: (context, row) => DesktopCellText(row.title, strong: true),
            ),
            DesktopColumn<ImportCostRow>(
              label: 'Original amount',
              width: 150,
              numeric: true,
              sortBy: (row) => row.amount,
              cell: (context, row) => DesktopCellText(
                '${row.currency} ${kitNumber(row.amount)}',
                numeric: true,
              ),
            ),
            DesktopColumn<ImportCostRow>(
              label: 'Landed (KES)',
              width: 132,
              numeric: true,
              sortBy: (row) => row.amountKes,
              cell: (context, row) =>
                  DesktopCellText(kesWhole(row.amountKes), numeric: true),
            ),
            DesktopColumn<ImportCostRow>(
              label: 'Reference',
              flex: 2,
              minWidth: 100,
              cell: (context, row) =>
                  DesktopCellText(row.reference ?? '—', muted: true),
            ),
            if (editable && onRemoveCost != null)
              DesktopColumn<ImportCostRow>(
                label: '',
                width: 48,
                cell: (context, row) => IconButton(
                  tooltip: 'Remove ${row.title}',
                  visualDensity: VisualDensity.compact,
                  onPressed: busy ? null : () => onRemoveCost!(row),
                  icon: const Icon(Icons.close_rounded, size: 17),
                ),
              ),
          ],
          empty: const DesktopEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No costs recorded',
            message: 'Freight, duty and clearing appear here when recorded.',
          ),
        ),
      ),
    );
  }

  Widget _participantsPanel(BuildContext context) {
    final rows = detail.participants;
    return DesktopPanel(
      title: 'Traders sharing this container',
      subtitle: 'Server-recorded shares and payment balances',
      trailing: canAddTrader && onAddTrader != null
          ? TextButton.icon(
              key: const ValueKey('desktop-import-add-trader'),
              onPressed: busy ? null : onAddTrader,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
              label: const Text('Add trader'),
            )
          : null,
      padding: EdgeInsets.zero,
      clip: true,
      child: SizedBox(
        height: _tableHeight(rows.length),
        child: DesktopDataTable<ImportParticipantRow>(
          rows: rows,
          rowId: (row) => row.id,
          minWidth: 940,
          columns: [
            DesktopColumn<ImportParticipantRow>(
              label: 'Trader',
              flex: 2,
              minWidth: 130,
              sortBy: (row) => row.name.toLowerCase(),
              cell: (context, row) => DesktopCellText(
                row.isSelf ? '${row.name} (you)' : row.name,
                strong: true,
              ),
            ),
            DesktopColumn<ImportParticipantRow>(
              label: 'Goods + costs',
              flex: 3,
              minWidth: 230,
              sortBy: (row) => row.owesKes,
              cell: (context, row) {
                final costs = costShare(row);
                final goods = row.owesKes - costs;
                return Tooltip(
                  message:
                      'Goods ${kesWhole(goods)} + costs ${kesWhole(costs)} = ${kesWhole(row.owesKes)}',
                  child: DesktopCellText(
                    '${kesWhole(goods)} goods · ${kesWhole(costs)} costs',
                    muted: true,
                  ),
                );
              },
            ),
            DesktopColumn<ImportParticipantRow>(
              label: 'Owes',
              width: 112,
              numeric: true,
              sortBy: (row) => row.owesKes,
              cell: (context, row) =>
                  DesktopCellText(kesWhole(row.owesKes), numeric: true),
            ),
            DesktopColumn<ImportParticipantRow>(
              label: 'Paid',
              width: 112,
              numeric: true,
              sortBy: (row) => row.paidKes,
              cell: (context, row) =>
                  DesktopCellText(kesWhole(row.paidKes), numeric: true),
            ),
            DesktopColumn<ImportParticipantRow>(
              label: 'Balance',
              width: 112,
              numeric: true,
              sortBy: (row) => row.balanceKes,
              cell: (context, row) =>
                  DesktopCellText(kesWhole(row.balanceKes), numeric: true),
            ),
            DesktopColumn<ImportParticipantRow>(
              label: 'Status',
              width: 108,
              sortBy: (row) => row.status,
              cell: (context, row) {
                final (label, color) = _participantStatus(row.status);
                return Align(
                  alignment: Alignment.centerLeft,
                  child: DesktopStatusChip(label: label, color: color),
                );
              },
            ),
            if (canPay && onRecordPayment != null ||
                onRemoveParticipant != null)
              DesktopColumn<ImportParticipantRow>(
                label: 'Actions',
                width: 132,
                cell: (context, row) {
                  final actions = <Widget>[];
                  if (canPay &&
                      !detail.isCancelled &&
                      row.balanceKes > 0.5 &&
                      onRecordPayment != null) {
                    actions.add(IconButton(
                      tooltip: 'Record payment for ${row.name}',
                      visualDensity: VisualDensity.compact,
                      onPressed: busy ? null : () => onRecordPayment!(row),
                      icon: const Icon(Icons.payments_outlined, size: 17),
                    ));
                  }
                  if (!row.isSelf &&
                      detail.isOpen &&
                      onRemoveParticipant != null &&
                      !detail.payments
                          .any((payment) => payment.participantId == row.id)) {
                    actions.add(IconButton(
                      tooltip: 'Remove ${row.name}',
                      visualDensity: VisualDensity.compact,
                      onPressed: busy ? null : () => onRemoveParticipant!(row),
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ));
                  }
                  return Row(mainAxisSize: MainAxisSize.min, children: actions);
                },
              ),
          ],
          empty: const DesktopEmptyState(
            icon: Icons.people_outline_rounded,
            title: 'No traders recorded',
            message: 'Add a trader when costs are shared.',
          ),
        ),
      ),
    );
  }

  Widget _paymentsPanel(BuildContext context) {
    final rows = detail.payments;
    return DesktopPanel(
      title: 'Recorded payments',
      subtitle: '${rows.length} payment${rows.length == 1 ? '' : 's'}',
      padding: EdgeInsets.zero,
      clip: true,
      child: SizedBox(
        height: _tableHeight(rows.length),
        child: DesktopDataTable<ImportPaymentRow>(
          rows: rows,
          rowId: (row) => row.id,
          minWidth: 720,
          columns: [
            DesktopColumn<ImportPaymentRow>(
              label: 'Trader',
              flex: 2,
              minWidth: 130,
              sortBy: (row) => detail.participantName(row.participantId),
              cell: (context, row) => DesktopCellText(
                detail.participantName(row.participantId),
                strong: true,
              ),
            ),
            DesktopColumn<ImportPaymentRow>(
              label: 'Amount',
              width: 132,
              numeric: true,
              sortBy: (row) => row.amountKes,
              cell: (context, row) =>
                  DesktopCellText(kesWhole(row.amountKes), numeric: true),
            ),
            DesktopColumn<ImportPaymentRow>(
              label: 'Method',
              width: 112,
              cell: (context, row) =>
                  DesktopCellText(row.method ?? '—', muted: true),
            ),
            DesktopColumn<ImportPaymentRow>(
              label: 'Reference',
              flex: 2,
              minWidth: 130,
              cell: (context, row) =>
                  DesktopCellText(row.reference ?? '—', muted: true),
            ),
            DesktopColumn<ImportPaymentRow>(
              label: 'Paid',
              width: 132,
              sortBy: (row) => row.paidAt.millisecondsSinceEpoch,
              cell: (context, row) => DesktopCellText(
                MaterialLocalizations.of(context)
                    .formatMediumDate(row.paidAt.toLocal()),
                muted: true,
              ),
            ),
            if (canPay && onRemovePayment != null)
              DesktopColumn<ImportPaymentRow>(
                label: '',
                width: 48,
                cell: (context, row) => IconButton(
                  tooltip: 'Remove payment',
                  visualDensity: VisualDensity.compact,
                  onPressed: busy ? null : () => onRemovePayment!(row),
                  icon: const Icon(Icons.close_rounded, size: 17),
                ),
              ),
          ],
          empty: const DesktopEmptyState(
            icon: Icons.payments_outlined,
            title: 'No payments recorded',
            message: 'Recorded payments appear here.',
          ),
        ),
      ),
    );
  }

  double _tableHeight(int count) =>
      count == 0 ? 240 : (72 + (count.clamp(1, 4) * 44)).toDouble();

  (String, Color) _participantStatus(String status) => switch (status) {
        'SETTLED' => ('Paid up', DesignColors.success),
        'PART_PAID' => ('Part paid', DesignColors.warning),
        'OVERPAID' => ('Overpaid', DesignColors.info),
        _ => ('Owes', DesignColors.error),
      };
}

class _WarningsPanel extends StatelessWidget {
  const _WarningsPanel({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: p.dark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DesignColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: DesignColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      warning,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
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
