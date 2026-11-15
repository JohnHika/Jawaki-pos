import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// Checks a received quantity. Same wording as the phone form.
String? validateBatchQuantity(String? value) {
  if (value == null || value.isEmpty) return 'Enter how many';
  final qty = double.tryParse(value);
  if (qty == null) return 'Numbers only';
  if (!qty.isFinite) return 'Enter a valid quantity';
  if (qty <= 0) return 'Must be more than 0';
  return null;
}

/// Checks the optional buying price.
String? validateBatchCost(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final cost = double.tryParse(text);
  if (cost == null || !cost.isFinite) return 'Enter a valid cost';
  if (cost < 0) return 'Cost cannot be negative';
  return null;
}

/// One batch of a delivery as the grid draws it.
class DesktopBatchRow {
  const DesktopBatchRow({
    required this.quantity,
    required this.cost,
    required this.supplierRef,
    required this.notes,
    required this.unit,
    this.expiry,
    this.manufactured,
    this.conversion,
  });

  final TextEditingController quantity;
  final TextEditingController cost;
  final TextEditingController supplierRef;
  final TextEditingController notes;
  final String unit;
  final DateTime? expiry;
  final DateTime? manufactured;

  /// "= 240 piece" when the unit counted is a pack.
  final String? conversion;
}

/// Receiving batches of one product on a computer: a grid of batches (quantity,
/// unit, buying price, expiry, supplier reference) with a side panel for the
/// product, the running total and the extra details of the selected batch.
///
/// Enter moves quantity -> price -> next batch. Ctrl+Enter receives, Ctrl+N adds
/// a batch, Esc goes back. Plain data in, callbacks out; the routed screen does
/// the saving.
class DesktopBatchReceiveView extends StatefulWidget {
  const DesktopBatchReceiveView({
    super.key,
    required this.formKey,
    required this.productName,
    required this.baseUnit,
    required this.units,
    required this.rows,
    required this.onAdd,
    required this.onRemove,
    required this.onUnit,
    required this.onPickDate,
    required this.onChanged,
    required this.onSave,
    required this.onCancel,
    this.onHandLabel,
    this.packSizes = const [],
    this.totalLabel,
    this.afterLabel,
    this.busy = false,
  });

  final GlobalKey<FormState> formKey;
  final String productName;
  final String baseUnit;

  /// Every unit a batch can be counted in.
  final List<String> units;
  final List<DesktopBatchRow> rows;

  /// "On hand now: 12 pieces".
  final String? onHandLabel;

  /// "1 carton = 24 piece".
  final List<String> packSizes;

  /// "Adding 48 pieces".
  final String? totalLabel;

  /// "60 on hand after".
  final String? afterLabel;
  final bool busy;

  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int index, String unit) onUnit;
  final void Function(int index, {required bool expiry}) onPickDate;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  State<DesktopBatchReceiveView> createState() =>
      _DesktopBatchReceiveViewState();
}

class _DesktopBatchReceiveViewState extends State<DesktopBatchReceiveView> {
  final List<FocusNode> _qtyFocus = [];
  final List<FocusNode> _costFocus = [];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _syncFocus();
  }

  @override
  void didUpdateWidget(DesktopBatchReceiveView old) {
    super.didUpdateWidget(old);
    final grew = widget.rows.length > _qtyFocus.length && _qtyFocus.isNotEmpty;
    _syncFocus();
    if (_selected >= widget.rows.length) _selected = widget.rows.length - 1;
    if (grew) {
      _selected = widget.rows.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _qtyFocus.isNotEmpty) _qtyFocus.last.requestFocus();
      });
    }
  }

  void _syncFocus() {
    while (_qtyFocus.length < widget.rows.length) {
      _qtyFocus.add(FocusNode());
      _costFocus.add(FocusNode());
    }
    while (_qtyFocus.length > widget.rows.length) {
      _qtyFocus.removeLast().dispose();
      _costFocus.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    for (final n in [..._qtyFocus, ..._costFocus]) {
      n.dispose();
    }
    super.dispose();
  }

  String _date(DateTime? d) {
    if (d == null) return 'Set date';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final count = widget.rows.length;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            widget.onAdd,
        if (!widget.busy) ...{
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              widget.onSave,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              widget.onSave,
        },
      },
      child: Focus(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: 'Receive stock',
              subtitle: widget.productName,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              leading: IconButton(
                tooltip: 'Back (Esc)',
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: widget.onCancel,
              ),
              actions: [
                Tooltip(
                  message: 'Add another batch (Ctrl+N)',
                  child: OutlinedButton.icon(
                    key: const ValueKey('add-batch'),
                    style: desktopSecondaryButton(context),
                    onPressed: widget.busy ? null : widget.onAdd,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add batch'),
                  ),
                ),
                Tooltip(
                  message: 'Receive (Ctrl+Enter)',
                  child: FilledButton(
                    key: const ValueKey('receive-batches'),
                    style: desktopPrimaryButton(context),
                    onPressed: widget.busy ? null : widget.onSave,
                    child: Text(
                      widget.busy
                          ? 'Saving…'
                          : count > 1
                              ? 'Receive $count batches'
                              : 'Receive stock',
                    ),
                  ),
                ),
              ],
            ),
            Divider(height: 1, color: p.border),
            Expanded(
              child: Form(
                key: widget.formKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _grid(context)),
                    VerticalDivider(width: 1, color: p.border),
                    SizedBox(width: 300, child: _side(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _head(DesktopPalette p) => GoogleFonts.plusJakartaSans(
        color: p.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      );

  Widget _grid(BuildContext context) {
    final p = context.desktop;
    Widget h(String t, {double? width, bool right = false}) => width == null
        ? Expanded(child: Text(t, style: _head(p)))
        : SizedBox(
            width: width,
            child: Text(
              t,
              style: _head(p),
              textAlign: right ? TextAlign.right : TextAlign.left,
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sticky header: the rows scroll underneath it.
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: p.panelAlt,
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: Row(
            children: [
              h('#', width: 28),
              h('Quantity', width: 96, right: true),
              const SizedBox(width: 10),
              h('Counted in', width: 104),
              const SizedBox(width: 10),
              h('Price each', width: 112, right: true),
              const SizedBox(width: 10),
              h('Expires', width: 116),
              const SizedBox(width: 10),
              h('Invoice or reference'),
              const SizedBox(width: 36),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: widget.rows.length,
            itemBuilder: (context, i) => _row(context, i),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, int i) {
    final p = context.desktop;
    final row = widget.rows[i];
    final selected = i == _selected;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused && _selected != i) setState(() => _selected = i);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = i),
        child: Container(
          key: ValueKey('batch-row-$i'),
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          decoration: BoxDecoration(
            color: selected ? p.selected : null,
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                height: 36,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${i + 1}',
                    style: DesignType.numeric(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.textMuted,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 96,
                child: _field(
                  context,
                  key: ValueKey('batch-qty-$i'),
                  controller: row.quantity,
                  focusNode: _qtyFocus[i],
                  numeric: true,
                  validator: validateBatchQuantity,
                  onDone: () => _costFocus[i].requestFocus(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 104,
                height: 36,
                child: widget.units.length > 1
                    ? DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: ValueKey('batch-unit-$i'),
                          value: row.unit,
                          isDense: true,
                          isExpanded: true,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          items: [
                            for (final u in widget.units)
                              DropdownMenuItem(value: u, child: Text(u)),
                          ],
                          onChanged: (v) => widget.onUnit(i, v ?? row.unit),
                        ),
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          row.unit,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 112,
                child: _field(
                  context,
                  key: ValueKey('batch-cost-$i'),
                  controller: row.cost,
                  focusNode: _costFocus[i],
                  numeric: true,
                  prefix: 'KES ',
                  validator: validateBatchCost,
                  onDone: () {
                    if (i + 1 < widget.rows.length) {
                      _qtyFocus[i + 1].requestFocus();
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 116,
                height: 36,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: ValueKey('batch-expiry-$i'),
                    style: desktopLinkButton(context).copyWith(
                      foregroundColor: WidgetStatePropertyAll(
                        row.expiry == null ? p.textFaint : p.text,
                      ),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ),
                    onPressed: () => widget.onPickDate(i, expiry: true),
                    child: Text(_date(row.expiry)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  context,
                  controller: row.supplierRef,
                  hint: 'e.g. INV-001',
                  onDone: () {
                    if (i + 1 < widget.rows.length) {
                      _qtyFocus[i + 1].requestFocus();
                    }
                  },
                ),
              ),
              SizedBox(
                width: 36,
                height: 36,
                child: widget.rows.length > 1
                    ? IconButton(
                        tooltip: 'Remove this batch',
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: p.textMuted,
                        ),
                        onPressed: () => widget.onRemove(i),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    Key? key,
    required TextEditingController controller,
    FocusNode? focusNode,
    bool numeric = false,
    String? prefix,
    String? hint,
    String? Function(String?)? validator,
    VoidCallback? onDone,
  }) {
    final p = context.desktop;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextFormField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      textAlign: numeric ? TextAlign.right : TextAlign.left,
      keyboardType:
          numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      style: numeric
          ? DesignType.numeric(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: p.text,
            )
          : GoogleFonts.plusJakartaSans(color: p.text, fontSize: 13.5),
      validator: validator,
      onChanged: (_) => widget.onChanged(),
      onEditingComplete: onDone,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        prefixText: prefix,
        prefixStyle: GoogleFonts.plusJakartaSans(
          color: p.textMuted,
          fontSize: 12.5,
        ),
        errorStyle: GoogleFonts.plusJakartaSans(
          color: DesignColors.error,
          fontSize: 11.5,
          height: 1.1,
        ),
        filled: true,
        fillColor: p.dark ? p.panel : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        enabledBorder: border(p.border),
        border: border(p.border),
        focusedBorder: border(p.accent, 1.4),
        errorBorder: border(DesignColors.error),
        focusedErrorBorder: border(DesignColors.error, 1.4),
      ),
    );
  }

  Widget _side(BuildContext context) {
    final p = context.desktop;
    final sel = widget.rows.isEmpty ? null : widget.rows[_selected];
    TextStyle label() => GoogleFonts.plusJakartaSans(
          color: p.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        );
    return ColoredBox(
      color: p.panel,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.productName,
            style: GoogleFonts.sora(
              color: p.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          if (widget.onHandLabel != null) ...[
            const SizedBox(height: 2),
            Text(
              widget.onHandLabel!,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
              ),
            ),
          ],
          for (final pack in widget.packSizes) ...[
            const SizedBox(height: 4),
            Text(
              pack,
              style: GoogleFonts.plusJakartaSans(
                color: p.textFaint,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Divider(height: 1, color: p.border),
          const SizedBox(height: 14),
          Text('This delivery', style: label()),
          const SizedBox(height: 6),
          Text(
            widget.totalLabel ?? 'Nothing entered yet',
            key: const ValueKey('receive-summary'),
            style: GoogleFonts.plusJakartaSans(
              color: widget.totalLabel == null ? p.textFaint : p.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (widget.afterLabel != null)
            Text(
              widget.afterLabel!,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
              ),
            ),
          if (sel != null) ...[
            const SizedBox(height: 18),
            Divider(height: 1, color: p.border),
            const SizedBox(height: 14),
            Text('Batch ${_selected + 1} details', style: label()),
            if (sel.conversion != null) ...[
              const SizedBox(height: 6),
              Text(
                sel.conversion!,
                style: GoogleFonts.plusJakartaSans(
                  color: p.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text('Made on', style: label()),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('batch-made-date'),
                style: desktopSecondaryButton(context),
                onPressed: () =>
                    widget.onPickDate(_selected, expiry: false),
                icon: const Icon(Icons.calendar_month_outlined, size: 17),
                label: Text(_date(sel.manufactured)),
              ),
            ),
            const SizedBox(height: 12),
            Text('Notes', style: label()),
            const SizedBox(height: 4),
            TextFormField(
              key: ValueKey('batch-notes-$_selected'),
              controller: sel.notes,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => widget.onChanged(),
              decoration: const InputDecoration(
                hintText: 'Anything to remember about this batch',
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              DesktopKeyHint('Enter', 'next field'),
              DesktopKeyHint('Ctrl+N', 'add batch'),
              DesktopKeyHint('Ctrl+Enter', 'receive'),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Ctrl+N add batch": a small reminder of one shortcut.
class DesktopKeyHint extends StatelessWidget {
  const DesktopKeyHint(this.keys, this.action, {super.key});

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: keys,
            style: GoogleFonts.plusJakartaSans(
              color: p.text,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: ' $action',
            style: GoogleFonts.plusJakartaSans(
              color: p.textFaint,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
