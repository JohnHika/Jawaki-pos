import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// One line of a delivery as the grid draws it.
class DesktopReceiveRow {
  const DesktopReceiveRow({
    required this.name,
    required this.code,
    required this.units,
    required this.unit,
    required this.quantity,
    required this.cost,
    required this.qtyFocus,
    required this.costFocus,
    this.note,
    this.lineTotal,
  });

  final String name;
  final String code;

  /// The units this product can be counted in (its own, then pack sizes).
  final List<String> units;
  final String unit;
  final TextEditingController quantity;
  final TextEditingController cost;
  final FocusNode qtyFocus;
  final FocusNode costFocus;

  /// "= 24 piece" when the unit counted is a pack.
  final String? note;

  /// Price paid for the whole line, when a buying price was entered.
  final double? lineTotal;
}

/// Receiving a delivery on a computer: a document, not a wizard. Supplier and
/// note at the top, a scan box that adds or counts up a line, and a grid where
/// Enter moves quantity -> price -> the next line. Ctrl+Enter or Ctrl+S saves.
///
/// Plain data in, callbacks out; the routed screen does the saving.
class DesktopReceiveDocument extends StatelessWidget {
  const DesktopReceiveDocument({
    super.key,
    required this.supplier,
    required this.note,
    required this.scanController,
    required this.scanFocus,
    required this.rows,
    required this.summary,
    required this.onScanSubmitted,
    required this.onBrowse,
    required this.onRemove,
    required this.onUnit,
    required this.onChanged,
    required this.onSave,
    required this.onCancel,
    this.tabs,
    this.paidLabel,
    this.busy = false,
    this.error,
    this.canSave = false,
  });

  final TextEditingController supplier;
  final TextEditingController note;
  final TextEditingController scanController;
  final FocusNode scanFocus;
  final List<DesktopReceiveRow> rows;

  /// "24 items in 3 products".
  final String summary;
  final String? paidLabel;
  final ValueChanged<String> onScanSubmitted;
  final VoidCallback onBrowse;
  final ValueChanged<int> onRemove;
  final void Function(int index, String unit) onUnit;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  /// The Inventory tab strip, shown under the title.
  final Widget? tabs;
  final bool busy;
  final String? error;
  final bool canSave;

  void _selectAll(TextEditingController c) {
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return CallbackShortcuts(
      bindings: {
        if (canSave && !busy) ...{
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              onSave,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
        },
      },
      child: Focus(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: 'Receive stock',
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                tabs == null ? 12 : 0,
              ),
              bottom: tabs,
              actions: [
                OutlinedButton(
                  style: desktopSecondaryButton(context),
                  onPressed: busy ? null : onCancel,
                  child: const Text('Cancel'),
                ),
                Tooltip(
                  message: 'Save delivery (Ctrl+Enter)',
                  child: FilledButton(
                    style: desktopPrimaryButton(context),
                    onPressed: busy || !canSave ? null : onSave,
                    child: Text(busy ? 'Saving…' : 'Save delivery'),
                  ),
                ),
              ],
            ),
            Divider(height: 1, color: p.border),
            Expanded(
              child: SingleChildScrollView(
                child: DesktopContent(
                  maxWidth: 1100,
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _field(
                              context,
                              supplier,
                              label: 'From (optional)',
                              hint: 'For example, Mama Njeri Wholesalers',
                              capitalize: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: _field(
                              context,
                              note,
                              label: 'Note (optional)',
                              hint:
                                  'Invoice number, driver, anything to remember',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          DesktopSearchField(
                            controller: scanController,
                            focusNode: scanFocus,
                            autofocus: true,
                            width: 420,
                            hint: 'Scan a barcode or type a code, then Enter',
                            onSubmitted: onScanSubmitted,
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: desktopSecondaryButton(context),
                            onPressed: onBrowse,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Browse items'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _grid(context),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: DesignColors.error
                                .withValues(alpha: p.dark ? 0.18 : 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            error!,
                            style: GoogleFonts.plusJakartaSans(
                              color: p.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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

  Widget _field(
    BuildContext context,
    TextEditingController controller, {
    required String label,
    required String hint,
    bool capitalize = false,
  }) {
    return TextField(
      controller: controller,
      textCapitalization:
          capitalize ? TextCapitalization.words : TextCapitalization.none,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }

  Widget _grid(BuildContext context) {
    final p = context.desktop;
    TextStyle head() => GoogleFonts.plusJakartaSans(
          color: p.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        );

    Widget headerCell(String text,
            {double? width, bool right = false, int flex = 0}) =>
        flex > 0
            ? Expanded(
                flex: flex,
                child: Text(text, style: head()),
              )
            : SizedBox(
                width: width,
                child: Text(
                  text,
                  style: head(),
                  textAlign: right ? TextAlign.right : TextAlign.left,
                ),
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
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                headerCell('Item', flex: 1),
                headerCell('Counted in', width: 120),
                const SizedBox(width: 8),
                headerCell('Quantity', width: 96, right: true),
                const SizedBox(width: 8),
                headerCell('Price paid each', width: 140, right: true),
                const SizedBox(width: 8),
                headerCell('Line total', width: 110, right: true),
                const SizedBox(width: 40),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
              child: Text(
                'Scan each item that arrived, or browse the list. Scanning the same item again adds one to its count. Buying prices are optional; add them and each product shows its profit.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) _row(context, i),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Text(
                  rows.isEmpty ? 'Nothing added yet' : summary,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (paidLabel != null)
                  Text(
                    paidLabel!,
                    style: DesignType.numeric(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: p.text,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final p = context.desktop;
    final row = rows[i];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
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
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    if (row.code.isNotEmpty) row.code,
                    if (row.note != null) row.note!,
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: row.units.length > 1
                ? DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: row.unit,
                      isDense: true,
                      isExpanded: true,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      items: [
                        for (final u in row.units)
                          DropdownMenuItem(value: u, child: Text(u)),
                      ],
                      onChanged: (v) => onUnit(i, v ?? row.unit),
                    ),
                  )
                : Text(
                    row.unit,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: _cell(
              context,
              controller: row.quantity,
              focusNode: row.qtyFocus,
              onDone: () => row.costFocus.requestFocus(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: _cell(
              context,
              controller: row.cost,
              focusNode: row.costFocus,
              prefix: 'KES ',
              onDone: () {
                if (i + 1 < rows.length) {
                  rows[i + 1].qtyFocus.requestFocus();
                } else {
                  scanFocus.requestFocus();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(
              row.lineTotal == null ? '—' : _money(row.lineTotal!),
              textAlign: TextAlign.right,
              style: row.lineTotal == null
                  ? GoogleFonts.plusJakartaSans(
                      color: p.textFaint,
                      fontSize: 13,
                    )
                  : DesignType.numeric(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              tooltip: 'Remove from this delivery',
              icon: Icon(Icons.close_rounded, size: 18, color: p.textMuted),
              onPressed: () => onRemove(i),
            ),
          ),
        ],
      ),
    );
  }

  String _money(double v) {
    final whole = v.round();
    final text = whole.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (m) => ',',
        );
    return 'KES $text';
  }

  Widget _cell(
    BuildContext context, {
    required TextEditingController controller,
    required FocusNode focusNode,
    required VoidCallback onDone,
    String? prefix,
  }) {
    final p = context.desktop;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
          borderSide: BorderSide(color: color, width: width),
        );
    return Focus(
      onFocusChange: (focused) {
        if (focused) _selectAll(controller);
      },
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: DesignType.numeric(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: p.text,
        ),
        onChanged: (_) => onChanged(),
        onEditingComplete: onDone,
        decoration: InputDecoration(
          isDense: true,
          prefixText: prefix,
          prefixStyle: GoogleFonts.plusJakartaSans(
            color: p.textMuted,
            fontSize: 12.5,
          ),
          filled: true,
          fillColor: p.dark ? p.panel : p.panelAlt,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          enabledBorder: border(p.border),
          border: border(p.border),
          focusedBorder: border(p.accent, 1.4),
        ),
      ),
    );
  }
}
