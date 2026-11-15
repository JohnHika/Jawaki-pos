import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// The editable fields of one invoice line. The routed screen owns the
/// controllers (they hold the user's typing); this view only draws them.
class DesktopInvoiceLine {
  const DesktopInvoiceLine({
    required this.name,
    required this.sku,
    required this.quantity,
    required this.unitCost,
    required this.lineTotal,
  });

  final TextEditingController name;
  final TextEditingController sku;
  final TextEditingController quantity;
  final TextEditingController unitCost;
  final double lineTotal;
}

/// Review Invoice on a computer: the invoice details and an editable lines
/// table on the left, the totals and the scanned receipt on the right, Save in
/// the header. Ctrl+S saves and Ctrl+N adds a line.
class DesktopInvoiceReviewView extends StatelessWidget {
  const DesktopInvoiceReviewView({
    super.key,
    required this.supplier,
    required this.invoiceNumber,
    required this.terms,
    required this.paid,
    required this.dueLabel,
    required this.fundingCredit,
    required this.lines,
    required this.total,
    required this.paidAmount,
    required this.balanceDue,
    required this.canSave,
    required this.saving,
    required this.onSave,
    required this.onAddLine,
    required this.onPickDue,
    required this.onFundingChanged,
    required this.onChanged,
    this.onRemoveLine,
    this.onBack,
    this.aiLabel,
    this.summary = '',
    this.receipt,
    this.title = 'Review invoice',
  });

  final TextEditingController supplier;
  final TextEditingController invoiceNumber;
  final TextEditingController terms;
  final TextEditingController paid;
  final String dueLabel;

  /// true: pay later (credit), false: paid from the cash till.
  final bool fundingCredit;
  final List<DesktopInvoiceLine> lines;
  final double total;
  final double paidAmount;
  final double balanceDue;
  final bool canSave;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onAddLine;
  final VoidCallback onPickDue;
  final ValueChanged<bool> onFundingChanged;

  /// A field changed: totals and Save need redrawing.
  final VoidCallback onChanged;

  /// null when there is only one line (it cannot be removed).
  final ValueChanged<int>? onRemoveLine;
  final VoidCallback? onBack;

  /// "Axon AI · Supplier invoice" when the lines were read from a photo.
  final String? aiLabel;
  final String summary;

  /// The scanned receipt picture, built by the routed screen.
  final Widget? receipt;
  final String title;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (canSave && !saving)
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            onAddLine,
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: title,
              subtitle: aiLabel,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
              leading: onBack == null
                  ? null
                  : IconButton(
                      tooltip: 'Back',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    ),
              actions: [
                Tooltip(
                  message: 'Ctrl+N',
                  child: OutlinedButton.icon(
                    style: desktopSecondaryButton(context),
                    onPressed: onAddLine,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add item'),
                  ),
                ),
                Tooltip(
                  message: 'Ctrl+S',
                  child: FilledButton.icon(
                    style: desktopPrimaryButton(context),
                    onPressed: canSave && !saving ? onSave : null,
                    icon: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: const Text('Save invoice'),
                  ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                child: DesktopContent(
                  maxWidth: 1180 + 2 * DesktopTokens.gutter,
                  padding: const EdgeInsets.fromLTRB(
                    DesktopTokens.gutter,
                    4,
                    DesktopTokens.gutter,
                    DesktopTokens.gutter,
                  ),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final main = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _details(context),
                          const SizedBox(height: 14),
                          _linesPanel(context),
                        ],
                      );
                      final side = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _totals(context),
                          if (receipt != null || summary.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _scan(context),
                          ],
                        ],
                      );
                      if (box.maxWidth < 860) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [side, const SizedBox(height: 14), main],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: main),
                          const SizedBox(width: 16),
                          SizedBox(width: 300, child: side),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _details(BuildContext context) {
    return DesktopPanel(
      title: 'Invoice details',
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: supplier,
                    autofocus: supplier.text.trim().isEmpty,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(labelText: 'Supplier name'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: invoiceNumber,
                    decoration: const InputDecoration(labelText: 'Invoice no.'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: terms,
                    decoration: const InputDecoration(labelText: 'Terms'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: paid,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Paid now',
                      prefixText: 'KES ',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onPickDue,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Due date',
                        suffixIcon: Icon(Icons.event_rounded, size: 18),
                      ),
                      child: Text(dueLabel, maxLines: 1),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _Funding(
                    credit: fundingCredit,
                    onChanged: onFundingChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _linesPanel(BuildContext context) {
    final p = context.desktop;
    final head = GoogleFonts.plusJakartaSans(
      color: p.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text('Item', style: head)),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: Text('SKU', style: head)),
                const SizedBox(width: 8),
                SizedBox(width: 70, child: Text('Qty', style: head)),
                const SizedBox(width: 8),
                SizedBox(width: 92, child: Text('Unit cost', style: head)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: Text('Line total',
                      textAlign: TextAlign.right, style: head),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ),
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: lines[i].name,
                      onChanged: (_) => onChanged(),
                      decoration: const InputDecoration(hintText: 'Product'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: lines[i].sku,
                      onChanged: (_) => onChanged(),
                      decoration: const InputDecoration(hintText: 'SKU'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: lines[i].quantity,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => onChanged(),
                      decoration: const InputDecoration(hintText: 'Qty'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 92,
                    child: TextField(
                      controller: lines[i].unitCost,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => onChanged(),
                      decoration: const InputDecoration(hintText: 'Cost'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: Text(
                      formatMoney(lines[i].lineTotal),
                      textAlign: TextAlign.right,
                      style: DesignType.numeric(
                        fontSize: 13.5,
                        color: p.text,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: onRemoveLine == null
                        ? null
                        : IconButton(
                            tooltip: 'Remove item',
                            onPressed: () => onRemoveLine!(i),
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 18, color: p.textMuted),
                          ),
                  ),
                ],
              ),
            ),
          ],
          Divider(height: 1, color: p.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: desktopLinkButton(context),
                onPressed: onAddLine,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add item'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totals(BuildContext context) {
    final p = context.desktop;
    Widget row(String label, double value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    color: strong ? p.text : p.textMuted,
                    fontSize: strong ? 14 : 13,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              Text(
                formatMoney(value),
                style: DesignType.numeric(
                  fontSize: strong ? 17 : 13.5,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                  color: p.text,
                ),
              ),
            ],
          ),
        );
    return DesktopPanel(
      title: 'Totals',
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          children: [
            row('Total', total),
            row('Paid', paidAmount),
            Divider(height: 12, color: p.border),
            row('Balance due', balanceDue, strong: true),
          ],
        ),
      ),
    );
  }

  Widget _scan(BuildContext context) {
    final p = context.desktop;
    return DesktopPanel(
      title: 'Scanned receipt',
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (receipt != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(height: 150, child: receipt),
              ),
            if (receipt != null && summary.isNotEmpty)
              const SizedBox(height: 10),
            if (summary.isNotEmpty)
              Text(
                summary,
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Cash till / Credit, as one compact two-way switch under a small label.
class _Funding extends StatelessWidget {
  const _Funding({required this.credit, required this.onChanged});

  final bool credit;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Funding source',
          style: GoogleFonts.plusJakartaSans(
            color: p.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: DesktopTokens.controlHeight,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Cash till')),
              ButtonSegment(value: true, label: Text('Credit')),
            ],
            selected: {credit},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
      ],
    );
  }
}
