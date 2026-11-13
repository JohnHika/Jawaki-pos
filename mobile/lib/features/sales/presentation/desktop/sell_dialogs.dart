import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import 'checkout_support.dart';
import 'sell_style.dart';

/// Small dialogs the till opens from the keyboard. Each returns focus to the
/// page that opened it when it closes.
Widget _dialogFrame(
  BuildContext context, {
  required String title,
  required Widget child,
  List<Widget> actions = const [],
  double width = 440,
}) {
  final s = SellStyle.of(context);
  return Dialog(
    backgroundColor: s.p.panel,
    insetPadding: const EdgeInsets.all(24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: s.p.borderStrong),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: s.heading(size: 16)),
            const SizedBox(height: 12),
            Flexible(child: child),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

// ─── Void the ticket (F8) ───

/// Asks before throwing a ticket away. Enter keeps the ticket: the safe
/// answer is the default, so a stray Enter never loses a sale.
Future<bool> confirmVoidTicket(BuildContext context, int itemCount) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final s = SellStyle.of(ctx);
      return _dialogFrame(
        ctx,
        title: 'Void this ticket?',
        width: 420,
        child: Text(
          'All $itemCount ${itemCount == 1 ? 'item is' : 'items are'} taken off the ticket and nothing is saved. Hold the sale instead if the customer is coming back.',
          style: s.body(size: 13.5, color: s.p.textMuted, height: 1.45),
        ),
        actions: [
          OutlinedButton(
            key: const ValueKey('void-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: OutlinedButton.styleFrom(
              foregroundColor: s.danger,
              side: BorderSide(color: s.danger.withValues(alpha: 0.6)),
            ),
            child: const Text('Void ticket'),
          ),
          FilledButton(
            key: const ValueKey('void-keep'),
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            style: FilledButton.styleFrom(
              backgroundColor: s.accentFill,
              foregroundColor: s.ink,
            ),
            child: const Text('Keep ticket'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

// ─── Discount (F7) ───

/// Percent or amount off the whole ticket. The shop's discount limit is still
/// checked when the sale is paid.
Future<void> showSellDiscountDialog(BuildContext context, WidgetRef ref) {
  final cart = ref.read(cartProvider);
  return showDialog<void>(
    context: context,
    builder: (ctx) => _DiscountDialog(
      initialPercent: cart.discountAmount <= 0,
      initialText: cart.discountPercent > 0
          ? sellQty(cart.discountPercent)
          : cart.discountAmount > 0
              ? sellQty(cart.discountAmount)
              : '',
      hasDiscount: cart.manualDiscount > 0,
      notifier: ref.read(cartProvider.notifier),
    ),
  );
}

class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({
    required this.initialPercent,
    required this.initialText,
    required this.hasDiscount,
    required this.notifier,
  });

  final bool initialPercent;
  final String initialText;
  final bool hasDiscount;
  final CartNotifier notifier;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  late bool _percent = widget.initialPercent;
  late final _controller = TextEditingController(text: widget.initialText);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a number above 0.');
      return;
    }
    if (_percent && value > 100) {
      setState(() => _error = 'A percent cannot be over 100.');
      return;
    }
    if (_percent) {
      widget.notifier.setDiscountPercent(value);
    } else {
      widget.notifier.setDiscountAmount(value);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    Widget mode(String label, bool percent) => ChoiceChip(
          label: Text(label),
          selected: _percent == percent,
          onSelected: (_) => setState(() {
            _percent = percent;
            _error = null;
          }),
        );
    return _dialogFrame(
      context,
      title: 'Discount',
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your shop sets the biggest discount a cashier can give. It is checked when you take payment.',
            style: s.body(size: 13, color: s.p.textMuted, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              mode('Percent', true),
              const SizedBox(width: 8),
              mode('Amount', false),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('discount-field'),
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onSubmitted: (_) => _apply(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              prefixText: _percent ? null : 'KES ',
              suffixText: _percent ? '%' : null,
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.hasDiscount)
          TextButton(
            onPressed: () {
              widget.notifier
                ..setDiscountPercent(0)
                ..setDiscountAmount(0);
              Navigator.of(context).pop();
            },
            child: const Text('Remove discount'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _apply,
          style: FilledButton.styleFrom(
            backgroundColor: s.accentFill,
            foregroundColor: s.ink,
          ),
          child: const Text('Apply discount'),
        ),
      ],
    );
  }
}

// ─── Customer (F3) ───

/// Picks who the ticket is for. Walk-in clears the customer.
Future<void> showSellCustomerPicker(
  BuildContext context,
  WidgetRef ref, {
  required String customerSingular,
  required String customersLabel,
  required bool canViewCustomers,
}) async {
  final host = ref.read(sellCheckoutHostProvider);
  final notifier = ref.read(cartProvider.notifier);
  final pick = await showDialog<({String? id, String? name})>(
    context: context,
    builder: (ctx) => _CustomerDialog(
      host: host,
      current: ref.read(permissionsProvider).canSeeCustomers
          ? ref.read(cartProvider).customerName
          : null,
      customerSingular: customerSingular,
      customersLabel: customersLabel,
    ),
  );
  if (pick == null) return;
  final stillAllowed = ref.read(permissionsProvider).canSeeCustomers;
  if (pick.id != null && !stillAllowed) return;
  notifier.setCustomer(
    pick.id,
    customerName: stillAllowed ? pick.name : null,
  );
}

class _CustomerDialog extends ConsumerStatefulWidget {
  const _CustomerDialog({
    required this.host,
    required this.current,
    required this.customerSingular,
    required this.customersLabel,
  });

  final SellCheckoutHost host;
  final String? current;
  final String customerSingular;
  final String customersLabel;

  @override
  ConsumerState<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends ConsumerState<_CustomerDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _loading = true;
  bool _failed = false;
  int _request = 0;
  int _highlight = 0;

  @override
  void initState() {
    super.initState();
    if (ref.read(permissionsProvider).canSeeCustomers) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!ref.read(permissionsProvider).canSeeCustomers) {
      _request++;
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await widget.host.searchCustomers(_controller.text.trim());
      if (!mounted ||
          request != _request ||
          !ref.read(permissionsProvider).canSeeCustomers) {
        return;
      }
      setState(() {
        _results = rows;
        _loading = false;
        _highlight = 0;
      });
    } catch (_) {
      if (!mounted ||
          request != _request ||
          !ref.read(permissionsProvider).canSeeCustomers) {
        return;
      }
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _choose(Map<String, dynamic> row) {
    if (!ref.read(permissionsProvider).canSeeCustomers) return;
    Navigator.of(context).pop((
      id: row['id'] as String?,
      name: row['name'] as String? ?? widget.customerSingular,
    ));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_results.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(
          () => _highlight = (_highlight + 1).clamp(0, _results.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
          () => _highlight = (_highlight - 1).clamp(0, _results.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final canViewCustomers = ref.watch(permissionsProvider).canSeeCustomers;
    ref.listen(permissionsProvider, (previous, next) {
      if (previous?.canSeeCustomers == true && !next.canSeeCustomers) {
        _debounce?.cancel();
        _request++;
        _controller.clear();
        setState(() {
          _results = const [];
          _loading = false;
          _failed = false;
          _highlight = 0;
        });
      } else if (previous?.canSeeCustomers == false && next.canSeeCustomers) {
        _load();
      }
    });
    final s = SellStyle.of(context);
    final single = widget.customerSingular.toLowerCase();
    return _dialogFrame(
      context,
      title: widget.customerSingular,
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canViewCustomers)
            Focus(
              onKeyEvent: _onKey,
              child: TextField(
                key: const ValueKey('customer-search'),
                controller: _controller,
                autofocus: true,
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 220), _load);
                },
                onSubmitted: (_) {
                  if (_results.isNotEmpty) _choose(_results[_highlight]);
                },
                decoration: InputDecoration(
                  hintText: 'Search $single by name or phone',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                ),
              ),
            ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 264),
            child: !canViewCustomers
                ? _note(
                    s,
                    'Saved customer details are hidden. Choose Walk-in to continue.',
                  )
                : _loading
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : _failed
                        ? _note(s,
                            'Could not read the saved ${widget.customersLabel.toLowerCase()}. Try again.')
                        : _results.isEmpty
                            ? _note(
                                s,
                                'No $single found. Add new ${widget.customersLabel.toLowerCase()} in the Customers page, then come back.',
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemExtent: 44,
                                itemCount: _results.length,
                                itemBuilder: (context, i) {
                                  final row = _results[i];
                                  final phone = row['phone'] as String? ?? '';
                                  final balance =
                                      (row['balance'] as num?)?.toDouble() ?? 0;
                                  return InkWell(
                                    onTap: () => _choose(row),
                                    hoverColor: s.p.hover,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      color: i == _highlight
                                          ? s.p.selected
                                          : Colors.transparent,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              row['name'] as String? ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: s.body(
                                                weight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (phone.isNotEmpty)
                                            Text(
                                              phone,
                                              style: s.body(
                                                size: 12.5,
                                                color: s.p.textMuted,
                                              ),
                                            ),
                                          if (balance > 0) ...[
                                            const SizedBox(width: 10),
                                            Text(
                                              'Owes ${sellMoney(balance)}',
                                              style: s.body(
                                                size: 12,
                                                weight: FontWeight.w700,
                                                color: s.warning,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop((id: null, name: null)),
          child: Text('Walk-in $single'),
        ),
      ],
    );
  }

  Widget _note(SellStyle s, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: s.body(size: 13, color: s.p.textMuted, height: 1.4),
        ),
      );
}

// ─── Shortcut cheat-sheet (F1 or ?) ───

const List<(String, String)> sellShortcuts = [
  ('F2', 'Search or scan'),
  ('F3', 'Choose customer'),
  ('F4', 'Type quantity of selected line'),
  ('F7', 'Discount on the ticket'),
  ('F8', 'Void the ticket'),
  ('F9', 'Pay (also Ctrl Enter)'),
  ('Ctrl N', 'New sale'),
  ('Ctrl H', 'Hold the current sale'),
  ('Ctrl Shift H', 'Open held sales'),
  ('Ctrl 1', 'Focus search'),
  ('Ctrl 3', 'Focus ticket lines'),
  ('Up Down', 'Move through products or lines'),
  ('Enter', 'Add the highlighted product'),
  ('+  -', 'More or less of the selected line'),
  ('Delete', 'Remove the selected line'),
  ('1 2 3 4', 'Pick how they pay'),
  ('Esc', 'Back'),
  ('F1  ?', 'This list'),
];

Future<void> showSellShortcuts(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final s = SellStyle.of(ctx);
      return Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey != LogicalKeyboardKey.shiftLeft &&
              event.logicalKey != LogicalKeyboardKey.shiftRight) {
            Navigator.of(ctx).pop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: _dialogFrame(
          ctx,
          title: 'Keyboard shortcuts',
          width: 560,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 24,
              runSpacing: 4,
              children: [
                for (final (keys, label) in sellShortcuts)
                  SizedBox(
                    width: 240,
                    height: 30,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 74,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SellKey(keys),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: s.body(size: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    },
  );
}
