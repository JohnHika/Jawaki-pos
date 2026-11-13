import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/cart_provider.dart';
import '../widgets/product_quick_add.dart';
import 'sell_style.dart';

/// The right half of the till: the ticket. Always on screen, never a sheet or
/// a separate page. The lines scroll; the totals and the Pay button do not.
class SellTicketPanel extends ConsumerStatefulWidget {
  const SellTicketPanel({
    super.key,
    required this.width,
    required this.focusNode,
    required this.selectedLineId,
    required this.onSelectLine,
    required this.onLeaveTicket,
    required this.onPay,
    required this.onPickCustomer,
    required this.onDiscount,
    required this.onVoid,
    required this.onMessage,
    this.onHoldSale,
    this.onOpenHeldSales,
    this.heldSalesCount = 0,
    this.heldSalesRestoring = false,
    this.heldSalesRestoreWarning,
    this.locked = false,
    this.showCustomer = true,
    this.customerLabel = 'Customer',
    this.canApplyDiscount = true,
    this.canViewCustomers = true,
    this.payPending = false,
  });

  final double width;

  /// Focus for the line list: arrows, + / -, Delete and Enter act on lines
  /// while it has focus.
  final FocusNode focusNode;
  final String? selectedLineId;
  final ValueChanged<String?> onSelectLine;

  /// Esc in the line list: hand the keyboard back to the search field.
  final VoidCallback onLeaveTicket;
  final VoidCallback onPay;
  final VoidCallback onPickCustomer;
  final VoidCallback onDiscount;
  final VoidCallback onVoid;
  final ValueChanged<SellNotice> onMessage;
  final VoidCallback? onHoldSale;
  final VoidCallback? onOpenHeldSales;
  final int heldSalesCount;
  final bool heldSalesRestoring;
  final String? heldSalesRestoreWarning;

  /// A payment request is open: the lines cannot change any more.
  final bool locked;
  final bool showCustomer;
  final String customerLabel;
  final bool canApplyDiscount;
  final bool canViewCustomers;

  /// A payment is waiting for a decision (M-Pesa); Pay says "Resume".
  final bool payPending;

  @override
  ConsumerState<SellTicketPanel> createState() => SellTicketPanelState();
}

class SellTicketPanelState extends ConsumerState<SellTicketPanel> {
  static const double _rowHeight = 52;

  final _scroll = ScrollController();
  String? _editingId;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  CartItem? _selected(CartState cart) {
    if (cart.items.isEmpty) return null;
    return cart.items.where((i) => i.id == widget.selectedLineId).firstOrNull ??
        cart.items.last;
  }

  /// F4: type the quantity of the selected line.
  void editSelectedQuantity() {
    final cart = ref.read(cartProvider);
    final item = _selected(cart);
    if (item == null || widget.locked) return;
    widget.onSelectLine(item.id);
    widget.focusNode.requestFocus();
    setState(() => _editingId = item.id);
  }

  double _step(CartItem item) {
    final conversion = item.unitConversionFactor;
    final factor = conversion != null && conversion.isFinite && conversion > 0
        ? conversion
        : 1.0;
    return (item.allowFractions ? 0.1 : 1) *
        (item.saleUnit == null ? 1 : factor);
  }

  Future<void> _bump(CartItem item, int direction) async {
    if (widget.locked) return;
    final result = await ref
        .read(cartProvider.notifier)
        .changeQuantityBy(item.productId, direction * _step(item));
    _report(item, result);
  }

  Future<void> _setQuantity(CartItem item, double quantity) async {
    final notifier = ref.read(cartProvider.notifier);
    if (quantity <= 0) {
      notifier.removeItem(item.productId);
      return;
    }
    final conversion = item.unitConversionFactor ?? 1;
    final base = item.saleUnit != null ? quantity * conversion : quantity;
    final result = await notifier.updateQuantity(item.productId, base);
    _report(item, result);
  }

  void _report(CartItem item, CartMutationResult result) {
    if (result.success) return;
    widget.onMessage(
      SellNotice(
        result.isStockBlocked
            ? stockBlockedMessage(item.productName, result.currentStock)
            : result.message,
        kind: SellNoticeKind.error,
      ),
    );
  }

  void _remove(CartState cart, CartItem item) {
    if (widget.locked) return;
    final index = cart.items.indexOf(item);
    ref.read(cartProvider.notifier).removeItem(item.productId);
    final rest = [...cart.items]..removeAt(index);
    widget.onSelectLine(
      rest.isEmpty ? null : rest[index.clamp(0, rest.length - 1)].id,
    );
  }

  void _select(CartState cart, int delta) {
    if (cart.items.isEmpty) return;
    final current = _selected(cart);
    final index = current == null ? 0 : cart.items.indexOf(current);
    final next = (index + delta).clamp(0, cart.items.length - 1);
    widget.onSelectLine(cart.items[next].id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(next));
  }

  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final top = index * _rowHeight;
    final bottom = top + _rowHeight;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top.clamp(0.0, position.maxScrollExtent));
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (bottom - position.viewportDimension)
            .clamp(0.0, position.maxScrollExtent),
      );
    }
  }

  KeyEventResult _onLineKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_editingId != null) return KeyEventResult.ignored;
    final cart = ref.read(cartProvider);
    final item = _selected(cart);
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _select(cart, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _select(cart, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && event is KeyDownEvent) {
      widget.onLeaveTicket();
      return KeyEventResult.handled;
    }
    if (item == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd ||
        key == LogicalKeyboardKey.equal) {
      _bump(item, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      if (item.quantity > _step(item)) _bump(item, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _remove(cart, item);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      editSelectedQuantity();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    final cart = ref.watch(cartProvider);
    final selected = _selected(cart);
    final empty = cart.items.isEmpty;

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: s.ticket,
        border: Border(left: BorderSide(color: s.p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s, cart),
          if (widget.heldSalesRestoreWarning != null)
            _heldSalesWarning(s, widget.heldSalesRestoreWarning!),
          if (widget.showCustomer) _customerRow(s, cart),
          Divider(height: 1, color: s.p.border),
          Expanded(
            child: empty
                ? _emptyTicket(s)
                : Focus(
                    focusNode: widget.focusNode,
                    onKeyEvent: _onLineKey,
                    child: AnimatedBuilder(
                      animation: widget.focusNode,
                      builder: (context, _) => ListView.builder(
                        controller: _scroll,
                        itemExtent: _rowHeight,
                        itemCount: cart.items.length,
                        itemBuilder: (context, i) {
                          final item = cart.items[i];
                          return _LineRow(
                            key: ValueKey(item.id),
                            item: item,
                            selected: selected?.id == item.id,
                            zoneFocused: widget.focusNode.hasFocus,
                            locked: widget.locked,
                            editing: _editingId == item.id,
                            canDecrease: item.quantity > _step(item),
                            onTap: () {
                              widget.onSelectLine(item.id);
                              widget.focusNode.requestFocus();
                            },
                            onMinus: () => _bump(item, -1),
                            onPlus: () => _bump(item, 1),
                            onRemove: () => _remove(cart, item),
                            onStartEdit: () {
                              widget.onSelectLine(item.id);
                              setState(() => _editingId = item.id);
                            },
                            onEditDone: (value) {
                              setState(() => _editingId = null);
                              widget.focusNode.requestFocus();
                              if (value != null) _setQuantity(item, value);
                            },
                          );
                        },
                      ),
                    ),
                  ),
          ),
          _totals(s, cart),
        ],
      ),
    );
  }

  Widget _header(SellStyle s, CartState cart) {
    final count = cart.itemCount;
    final heldTooltip = widget.heldSalesRestoreWarning != null
        ? 'Held sales need attention (Ctrl+Shift+H)'
        : widget.heldSalesRestoring
            ? 'Held sales loading (Ctrl+Shift+H)'
            : 'Held sales (${widget.heldSalesCount}) (Ctrl+Shift+H)';
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
      child: Row(
        children: [
          Text('Ticket', style: s.heading(size: 15)),
          const SizedBox(width: 8),
          if (count > 0)
            Text(
              '$count ${count == 1 ? 'item' : 'items'}',
              style: s.body(size: 12.5, color: s.p.textMuted),
            ),
          const Spacer(),
          if (widget.onOpenHeldSales != null)
            IconButton(
              tooltip: heldTooltip,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              onPressed: widget.onOpenHeldSales,
              icon: widget.heldSalesRestoring
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Badge(
                      isLabelVisible: widget.heldSalesCount > 0,
                      label: Text('${widget.heldSalesCount}'),
                      child: const Icon(Icons.inventory_2_outlined, size: 17),
                    ),
            ),
          if (widget.onHoldSale != null)
            IconButton(
              tooltip: 'Hold sale (Ctrl+H)',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              onPressed: count == 0 || widget.locked ? null : widget.onHoldSale,
              icon: const Icon(Icons.pause_circle_outline_rounded, size: 19),
            ),
          if (count > 0 && !widget.locked)
            SellQuietButton(
              label: 'Void',
              keyHint: 'F8',
              icon: Icons.delete_outline_rounded,
              tooltip: 'Void this ticket (F8)',
              onPressed: widget.onVoid,
            ),
        ],
      ),
    );
  }

  Widget _heldSalesWarning(SellStyle s, String warning) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: s.warning.withValues(alpha: s.p.dark ? 0.14 : 0.1),
          border: Border(bottom: BorderSide(color: s.p.border)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: s.warning, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                warning,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: s.body(size: 11.5, color: s.p.textMuted, height: 1.3),
              ),
            ),
            if (widget.onOpenHeldSales != null)
              TextButton(
                onPressed: widget.onOpenHeldSales,
                child: const Text('Review'),
              ),
          ],
        ),
      );

  Widget _customerRow(SellStyle s, CartState cart) {
    final name = widget.canViewCustomers ? cart.customerName : null;
    final label = !widget.canViewCustomers && cart.customerId != null
        ? 'Selected ${widget.customerLabel.toLowerCase()}'
        : name ?? 'Walk-in ${widget.customerLabel.toLowerCase()}';
    return Tooltip(
      message: 'Choose a ${widget.customerLabel.toLowerCase()} (F3)',
      child: HoverBuilder(
        builder: (context, hovered) => Material(
          color: hovered ? s.p.hover : Colors.transparent,
          child: InkWell(
            onTap: widget.locked ? null : widget.onPickCustomer,
            hoverColor: Colors.transparent,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: s.p.border)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 18,
                    color: name == null ? s.p.textFaint : s.p.text,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: s.body(
                        size: 13,
                        weight:
                            name == null ? FontWeight.w500 : FontWeight.w600,
                        color: name == null ? s.p.textMuted : s.p.text,
                      ),
                    ),
                  ),
                  const SellKey('F3'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyTicket(SellStyle s) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_scanner_rounded,
                  size: 30, color: s.p.textFaint),
              const SizedBox(height: 10),
              Text(
                'Nothing on this ticket yet',
                textAlign: TextAlign.center,
                style: s.heading(size: 14),
              ),
              const SizedBox(height: 6),
              Text(
                'Scan a barcode or search for an item and press Enter.',
                textAlign: TextAlign.center,
                style: s.body(size: 12.5, color: s.p.textMuted, height: 1.4),
              ),
            ],
          ),
        ),
      );

  Widget _totals(SellStyle s, CartState cart) {
    final empty = cart.items.isEmpty;
    final discount = cart.manualDiscount;
    final coupon = cart.couponDiscount;
    final tax = cart.tax;
    Widget row(String label, Widget value, {Widget? trailing}) => SizedBox(
          height: 22,
          child: Row(
            children: [
              Text(label, style: s.body(size: 12.5, color: s.p.textMuted)),
              if (trailing != null) ...[const SizedBox(width: 6), trailing],
              const Spacer(),
              value,
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: s.p.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('Subtotal', Text(sellMoney(cart.subtotal), style: s.number())),
          if (discount > 0)
            row(
              cart.discountPercent > 0
                  ? 'Discount ${sellQty(cart.discountPercent)}%'
                  : 'Discount',
              Text(
                '−${sellMoney(discount)}',
                style: s.number(color: s.success),
              ),
              trailing: const SellKey('F7'),
            )
          else if (widget.canApplyDiscount)
            SizedBox(
              height: 22,
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: empty || widget.locked ? null : widget.onDiscount,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Add discount',
                        style: s.body(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: empty ? s.p.textFaint : s.p.accent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const SellKey('F7'),
                    ],
                  ),
                ),
              ),
            ),
          if (coupon > 0)
            row(
              'Coupon ${cart.coupon?.code ?? ''}',
              Text('−${sellMoney(coupon)}', style: s.number(color: s.success)),
            ),
          if (tax > 0) row('Tax', Text(sellMoney(tax), style: s.number())),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Total',
                style: s.body(size: 14, weight: FontWeight.w600),
              ),
              const Spacer(),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    sellMoney(cart.total),
                    key: const ValueKey('ticket-total'),
                    style: s.heading(size: 26, weight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SellPrimaryButton(
            key: const ValueKey('pay-button'),
            label: empty
                ? 'Pay'
                : widget.payPending
                    ? 'Resume payment'
                    : 'Pay ${sellMoney(cart.total)}',
            keyHint: 'F9',
            onPressed: empty ? null : widget.onPay,
          ),
        ],
      ),
    );
  }
}

// ─── One line of the ticket ───

class _LineRow extends StatefulWidget {
  const _LineRow({
    super.key,
    required this.item,
    required this.selected,
    required this.zoneFocused,
    required this.locked,
    required this.editing,
    required this.canDecrease,
    required this.onTap,
    required this.onMinus,
    required this.onPlus,
    required this.onRemove,
    required this.onStartEdit,
    required this.onEditDone,
  });

  final CartItem item;
  final bool selected;
  final bool zoneFocused;
  final bool locked;
  final bool editing;
  final bool canDecrease;
  final VoidCallback onTap;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onRemove;
  final VoidCallback onStartEdit;
  final ValueChanged<double?> onEditDone;

  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    final item = widget.item;
    final conversion = item.unitConversionFactor ?? 1;
    final sold = item.saleUnit != null && item.saleQuantity != null;
    final displayQty = sold ? item.saleQuantity! : item.quantity;
    final perUnit = item.unitPrice * (sold ? conversion : 1);
    final detail = [
      if (item.sku.isNotEmpty) item.sku,
      if (sold && conversion != 1) 'by ${item.saleUnit}',
    ].join(' · ');
    final tint = widget.selected
        ? (widget.zoneFocused ? s.p.selected : s.p.hover)
        : (_hovered ? s.p.hover : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
          decoration: BoxDecoration(
            color: tint,
            border: Border(bottom: BorderSide(color: s.p.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: item.productName,
                      child: Text(
                        item.productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: s.body(size: 13, weight: FontWeight.w600),
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: s.body(
                          size: 12,
                          color: s.p.textFaint,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _Stepper(
                quantity: displayQty,
                editing: widget.editing,
                enabled: !widget.locked,
                canDecrease: widget.canDecrease,
                onMinus: widget.onMinus,
                onPlus: widget.onPlus,
                onStartEdit: widget.onStartEdit,
                onEditDone: widget.onEditDone,
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 66,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      sellMoney(item.total, symbol: false),
                      maxLines: 1,
                      style: s.number(),
                    ),
                    Text(
                      item.discount > 0
                          ? '−${sellMoney(item.discount, symbol: false)}'
                          : '@ ${sellMoney(perUnit, symbol: false)}',
                      maxLines: 1,
                      style: s.body(
                        size: 11.5,
                        color: item.discount > 0 ? s.success : s.p.textFaint,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 28,
                child: widget.locked || !(_hovered || widget.selected)
                    ? null
                    : IconButton(
                        tooltip: 'Remove from ticket (Delete)',
                        onPressed: widget.onRemove,
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.close_rounded,
                          color: s.p.textMuted,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.editing,
    required this.enabled,
    required this.canDecrease,
    required this.onMinus,
    required this.onPlus,
    required this.onStartEdit,
    required this.onEditDone,
  });

  final double quantity;
  final bool editing;
  final bool enabled;
  final bool canDecrease;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onStartEdit;
  final ValueChanged<double?> onEditDone;

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    Widget button(IconData icon, VoidCallback? onTap, String tip) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            hoverColor: s.p.hover,
            child: SizedBox(
              width: 24,
              height: 28,
              child: Icon(
                icon,
                size: 15,
                color: onTap == null ? s.p.textFaint : s.p.text,
              ),
            ),
          ),
        );
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: s.p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            Icons.remove_rounded,
            enabled && canDecrease ? onMinus : null,
            'One less (-)',
          ),
          SizedBox(
            width: 34,
            child: editing
                ? _QtyField(initial: quantity, onDone: onEditDone)
                : Tooltip(
                    message: 'Type a quantity (F4)',
                    child: InkWell(
                      onTap: enabled ? onStartEdit : null,
                      child: Center(
                        child: Text(
                          sellQty(quantity),
                          key: const ValueKey('line-qty'),
                          maxLines: 1,
                          style: s.number(size: 13),
                        ),
                      ),
                    ),
                  ),
          ),
          button(Icons.add_rounded, enabled ? onPlus : null, 'One more (+)'),
        ],
      ),
    );
  }
}

class _QtyField extends StatefulWidget {
  const _QtyField({required this.initial, required this.onDone});

  final double initial;
  final ValueChanged<double?> onDone;

  @override
  State<_QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<_QtyField> {
  late final TextEditingController _controller =
      TextEditingController(text: sellQty(widget.initial));
  final _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish(commit: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _finish({required bool commit}) {
    if (_done) return;
    _done = true;
    final value = commit ? double.tryParse(_controller.text.trim()) : null;
    widget.onDone(value);
  }

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _finish(commit: false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        key: const ValueKey('line-qty-field'),
        controller: _controller,
        focusNode: _focus,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onSubmitted: (_) => _finish(commit: true),
        onTapOutside: (_) {},
        style: s.number(size: 13),
        cursorColor: s.p.accent,
        decoration: const InputDecoration(
          isCollapsed: true,
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 7),
        ),
      ),
    );
  }
}
