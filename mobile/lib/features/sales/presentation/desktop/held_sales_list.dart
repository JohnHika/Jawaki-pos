import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sell_style.dart';

/// One held sale as the list draws it.
class HeldSaleRowData {
  const HeldSaleRowData({
    required this.id,
    required this.label,
    required this.itemCount,
    required this.total,
    required this.parkedAt,
  });

  final String id;

  /// Customer or "Held sale".
  final String label;
  final int itemCount;
  final double total;
  final DateTime parkedAt;
}

/// "now", "12 min ago", "3 h ago", "2 days ago".
String heldSaleAge(DateTime parkedAt, DateTime now) {
  final d = now.difference(parkedAt);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  final days = d.inDays;
  return days == 1 ? '1 day ago' : '$days days ago';
}

/// The held-sales list on a computer: one compact row per sale with how many
/// items, the total and how long it has waited. Arrow keys move, Enter
/// resumes, Delete discards. Shown inside the dialog the Sell page opens.
///
/// Plain data in, callbacks out: the page owns the checks that run before a
/// sale is resumed or discarded.
class HeldSalesList extends StatefulWidget {
  const HeldSalesList({
    super.key,
    required this.rows,
    required this.onResume,
    required this.onDiscard,
    this.restoring = false,
    this.warning,
    this.busyId,
    this.now,
  });

  final List<HeldSaleRowData> rows;
  final ValueChanged<String> onResume;
  final ValueChanged<String> onDiscard;

  /// True while saved held sales are still being loaded.
  final bool restoring;

  /// Shown above the list when some held sales could not be restored.
  final String? warning;

  /// The sale being resumed right now, if any.
  final String? busyId;

  /// Overrides the clock (tests).
  final DateTime? now;

  @override
  State<HeldSalesList> createState() => _HeldSalesListState();
}

class _HeldSalesListState extends State<HeldSalesList> {
  int _selected = 0;

  bool get _locked => widget.restoring || widget.warning != null;
  bool get _discardLocked => _locked || widget.busyId != null;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || widget.rows.isEmpty) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final last = widget.rows.length - 1;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1).clamp(0, last));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (_selected - 1).clamp(0, last));
      return KeyEventResult.handled;
    }
    final row = widget.rows[_selected.clamp(0, last)];
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!_locked && widget.busyId == null) widget.onResume(row.id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      if (!_discardLocked) widget.onDiscard(row.id);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    final now = widget.now ?? DateTime.now();
    final selected = widget.rows.isEmpty
        ? 0
        : _selected.clamp(0, widget.rows.length - 1);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.warning != null)
            Container(
              margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: s.tint(s.warning),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.warning!,
                key: const ValueKey('held-warning'),
                style: s.body(size: 12.5, color: s.warning),
              ),
            ),
          if (widget.rows.isEmpty)
            _empty(s)
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  Expanded(
                    child: Text('Sale', style: _head(s)),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      'Total',
                      textAlign: TextAlign.right,
                      style: _head(s),
                    ),
                  ),
                  const SizedBox(width: 170),
                ],
              ),
            ),
            Divider(height: 1, color: s.p.border),
            for (var i = 0; i < widget.rows.length; i++)
              _row(s, widget.rows[i], i, i == selected, now),
            Divider(height: 1, color: s.p.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
              child: Wrap(
                spacing: 14,
                children: [
                  _hint(s, 'Up / Down', 'choose'),
                  _hint(s, 'Enter', 'resume'),
                  _hint(s, 'Delete', 'discard'),
                  _hint(s, 'Esc', 'close'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  TextStyle _head(SellStyle s) => s.body(
        size: 12,
        weight: FontWeight.w700,
        color: s.p.textMuted,
      );

  Widget _hint(SellStyle s, String keys, String action) => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: keys,
              style: s.body(size: 11.5, weight: FontWeight.w700),
            ),
            TextSpan(
              text: ' $action',
              style: s.body(size: 11.5, color: s.p.textFaint),
            ),
          ],
        ),
      );

  Widget _empty(SellStyle s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Center(
        child: widget.restoring
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: s.p.accent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Restoring held sales…',
                    style: s.body(color: s.p.textMuted),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pause_circle_outline_rounded,
                      size: 30, color: s.p.textFaint),
                  const SizedBox(height: 10),
                  Text(
                    widget.warning == null
                        ? 'No held sales'
                        : 'No held sales could be restored',
                    style: s.heading(size: 15),
                  ),
                  if (widget.warning == null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Press Ctrl+H on the till to set a sale aside.',
                      style: s.body(size: 12.5, color: s.p.textMuted),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _row(
    SellStyle s,
    HeldSaleRowData row,
    int index,
    bool selected,
    DateTime now,
  ) {
    final resuming = widget.busyId == row.id;
    return HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = index),
        child: Container(
          key: ValueKey('held-${row.id}'),
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: selected
                ? s.p.selected
                : hovered
                    ? s.p.hover
                    : null,
            border: Border(bottom: BorderSide(color: s.p.border)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  '${row.itemCount}',
                  style: s.number(size: 14, color: s.p.textMuted),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: s.body(size: 13.5, weight: FontWeight.w700),
                    ),
                    Text(
                      '${row.itemCount} ${row.itemCount == 1 ? 'item' : 'items'}'
                      '  ·  ${heldSaleAge(row.parkedAt, now)}',
                      style: s.body(size: 12, color: s.p.textFaint),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 96,
                child: Text(
                  sellMoney(row.total),
                  textAlign: TextAlign.right,
                  style: s.number(size: 13.5),
                ),
              ),
              SizedBox(
                width: 170,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: ValueKey('resume-${row.id}'),
                      onPressed: _locked || widget.busyId != null
                          ? null
                          : () => widget.onResume(row.id),
                      style: TextButton.styleFrom(
                        foregroundColor: s.p.accent,
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: s.body(size: 13, weight: FontWeight.w700),
                      ),
                      child: Text(resuming ? 'Resuming…' : 'Resume'),
                    ),
                    IconButton(
                      key: ValueKey('discard-${row.id}'),
                      tooltip: 'Discard held sale (Delete)',
                      iconSize: 18,
                      onPressed: _discardLocked
                          ? null
                          : () => widget.onDiscard(row.id),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: _discardLocked ? s.p.textFaint : s.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
