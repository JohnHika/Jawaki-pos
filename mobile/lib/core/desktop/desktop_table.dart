import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_system.dart';
import 'desktop_layout.dart';

/// One column of a [DesktopDataTable].
class DesktopColumn<T> {
  const DesktopColumn({
    required this.label,
    required this.cell,
    this.width,
    this.flex = 1,
    this.minWidth = 72,
    this.numeric = false,
    this.sortBy,
  });

  final String label;
  final Widget Function(BuildContext context, T row) cell;

  /// A fixed width. When null the column shares the leftover space by [flex].
  final double? width;
  final int flex;
  final double minWidth;

  /// Right-aligned, for money and counts.
  final bool numeric;

  /// Makes the header clickable and sorts rows by this key.
  final Comparable<Object?> Function(T row)? sortBy;
}

/// A dense, sortable table with a sticky header, hover and selection, arrow-key
/// navigation and an optional totals footer. The desktop answer to a list of
/// full-width cards.
///
/// Rows are virtualised, so it stays fast with thousands of products.
class DesktopDataTable<T> extends StatefulWidget {
  const DesktopDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.rowId,
    this.selectedId,
    this.onRowSelected,
    this.onRowActivated,
    this.onRowSecondaryTap,
    this.footer,
    this.empty,
    this.loading = false,
    this.rowHeight = DesktopTokens.rowHeight,
    this.minWidth = 640,
    this.initialSortColumn,
    this.initialSortAscending = true,
    this.padding = EdgeInsets.zero,
  });

  final List<DesktopColumn<T>> columns;
  final List<T> rows;
  final Object Function(T row) rowId;

  /// The highlighted row (the one an inspector is showing).
  final Object? selectedId;

  /// A row was clicked or reached with the arrow keys.
  final ValueChanged<T>? onRowSelected;

  /// A row was double-clicked or Enter was pressed on it.
  final ValueChanged<T>? onRowActivated;

  /// Right-click on a row, with the pointer position for a context menu.
  final void Function(T row, Offset globalPosition)? onRowSecondaryTap;

  /// Pinned under the rows: totals, "Showing 40 of 812".
  final Widget? footer;

  /// Shown instead of rows when [rows] is empty and not [loading].
  final Widget? empty;
  final bool loading;
  final double rowHeight;

  /// Narrower than this and the table scrolls sideways instead of squashing.
  final double minWidth;
  final int? initialSortColumn;
  final bool initialSortAscending;
  final EdgeInsetsGeometry padding;

  @override
  State<DesktopDataTable<T>> createState() => _DesktopDataTableState<T>();
}

class _DesktopDataTableState<T> extends State<DesktopDataTable<T>> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'DesktopDataTable');
  int? _sortColumn;
  bool _ascending = true;
  Object? _hoverId;
  Object? _lastTapId;
  DateTime? _lastTapAt;

  @override
  void initState() {
    super.initState();
    _sortColumn = widget.initialSortColumn;
    _ascending = widget.initialSortAscending;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<T> get _sorted {
    final column = _sortColumn;
    if (column == null || column >= widget.columns.length) return widget.rows;
    final key = widget.columns[column].sortBy;
    if (key == null) return widget.rows;
    final copy = [...widget.rows];
    copy.sort((a, b) {
      final result = Comparable.compare(key(a), key(b));
      return _ascending ? result : -result;
    });
    return copy;
  }

  void _toggleSort(int index) {
    setState(() {
      if (_sortColumn == index) {
        _ascending = !_ascending;
      } else {
        _sortColumn = index;
        _ascending = true;
      }
    });
  }

  KeyEventResult _onKey(List<T> rows, KeyEvent event) {
    if (event is KeyUpEvent || rows.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final selected = rows.indexWhere((r) => widget.rowId(r) == widget.selectedId);
    int? next;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = selected < 0 ? 0 : (selected + 1).clamp(0, rows.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = selected < 0 ? 0 : (selected - 1).clamp(0, rows.length - 1);
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = rows.length - 1;
    } else if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        selected >= 0) {
      widget.onRowActivated?.call(rows[selected]);
      return KeyEventResult.handled;
    }
    if (next == null) return KeyEventResult.ignored;
    widget.onRowSelected?.call(rows[next]);
    _reveal(next);
    return KeyEventResult.handled;
  }

  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final top = index * widget.rowHeight;
    final bottom = top + widget.rowHeight;
    final viewport = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (bottom > _scroll.offset + viewport) {
      _scroll.jumpTo(bottom - viewport);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final rows = _sorted;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        // Never narrower than the columns' own minimums, or cells overflow.
        final needed = widget.columns
            .fold<double>(0, (sum, c) => sum + (c.width ?? c.minWidth));
        final floor = widget.minWidth > needed ? widget.minWidth : needed;
        final tableWidth = available < floor ? floor : available;
        final widths = _resolveWidths(tableWidth);

        Widget table = SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              _HeaderRow<T>(
                palette: p,
                columns: widget.columns,
                widths: widths,
                sortColumn: _sortColumn,
                ascending: _ascending,
                onSort: _toggleSort,
              ),
              Divider(height: 1, color: p.border),
              Expanded(child: _body(context, p, rows, widths)),
              if (widget.footer != null) ...[
                Divider(height: 1, color: p.border),
                widget.footer!,
              ],
            ],
          ),
        );

        if (available < floor) {
          table = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          );
        }
        return Padding(padding: widget.padding, child: table);
      },
    );
  }

  Widget _body(
    BuildContext context,
    DesktopPalette p,
    List<T> rows,
    List<double> widths,
  ) {
    if (widget.loading && rows.isEmpty) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 8; i++)
            SizedBox(
              height: widget.rowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.2 + (i % 4) * 0.15,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: p.hover,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    if (rows.isEmpty) return widget.empty ?? const SizedBox.shrink();

    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) => _onKey(rows, event),
      child: ListView.builder(
        controller: _scroll,
        itemExtent: widget.rowHeight,
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final row = rows[i];
          final id = widget.rowId(row);
          final selected = id == widget.selectedId;
          final hovered = id == _hoverId;
          return MouseRegion(
            cursor: widget.onRowSelected == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hoverId = id),
            onExit: (_) {
              if (_hoverId == id) setState(() => _hoverId = null);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // A double click is read from two quick taps on the same row, not
              // a double-tap recogniser: that one holds back every single click
              // for ~300 ms until it knows no second tap is coming.
              onTap: () {
                _focus.requestFocus();
                final now = DateTime.now();
                final again = _lastTapId == id &&
                    _lastTapAt != null &&
                    now.difference(_lastTapAt!) <
                        const Duration(milliseconds: 350);
                _lastTapId = id;
                _lastTapAt = again ? null : now;
                if (!again) widget.onRowSelected?.call(row);
                if (again) widget.onRowActivated?.call(row);
              },
              onSecondaryTapDown: widget.onRowSecondaryTap == null
                  ? null
                  : (d) => widget.onRowSecondaryTap!(row, d.globalPosition),
              child: Container(
                decoration: BoxDecoration(
                  color: selected
                      ? p.selected
                      : hovered
                          ? p.hover
                          : Colors.transparent,
                  border: Border(bottom: BorderSide(color: p.border)),
                ),
                child: Row(
                  children: [
                    for (var c = 0; c < widget.columns.length; c++)
                      SizedBox(
                        width: widths[c],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Align(
                            alignment: widget.columns[c].numeric
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: widget.columns[c].cell(context, row),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Fixed columns keep their width; flex columns split what is left, never
  /// narrower than their [DesktopColumn.minWidth].
  List<double> _resolveWidths(double total) {
    final cols = widget.columns;
    final widths = <double>[
      for (final c in cols) c.width ?? 0,
    ];
    var left = total - cols.fold<double>(0, (sum, c) => sum + (c.width ?? 0));
    final flexing = <int>[
      for (var i = 0; i < cols.length; i++)
        if (cols[i].width == null) i,
    ];
    // A column that would come out narrower than its minimum keeps the minimum
    // and the others share what is left, so the row never outgrows the table.
    while (flexing.isNotEmpty) {
      final flexTotal = flexing.fold<int>(0, (sum, i) => sum + cols[i].flex);
      final pinned = flexing
          .where((i) => left * cols[i].flex / flexTotal < cols[i].minWidth)
          .toList();
      if (pinned.isEmpty) {
        for (final i in flexing) {
          widths[i] = (left * cols[i].flex / flexTotal).floorToDouble();
        }
        break;
      }
      for (final i in pinned) {
        widths[i] = cols[i].minWidth;
        left -= cols[i].minWidth;
        flexing.remove(i);
      }
    }
    return widths;
  }
}

class _HeaderRow<T> extends StatelessWidget {
  const _HeaderRow({
    required this.palette,
    required this.columns,
    required this.widths,
    required this.sortColumn,
    required this.ascending,
    required this.onSort,
  });

  final DesktopPalette palette;
  final List<DesktopColumn<T>> columns;
  final List<double> widths;
  final int? sortColumn;
  final bool ascending;
  final ValueChanged<int> onSort;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            SizedBox(
              width: widths[i],
              child: InkWell(
                onTap: columns[i].sortBy == null ? null : () => onSort(i),
                hoverColor: p.hover,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: columns[i].numeric
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          columns[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: sortColumn == i ? p.text : p.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (sortColumn == i) ...[
                        const SizedBox(width: 4),
                        Icon(
                          ascending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 13,
                          color: p.text,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cell text in the table's standard styles.
class DesktopCellText extends StatelessWidget {
  const DesktopCellText(
    this.text, {
    super.key,
    this.muted = false,
    this.strong = false,
    this.numeric = false,
    this.color,
  });

  final String text;
  final bool muted;
  final bool strong;

  /// Tabular figures, for money and quantities.
  final bool numeric;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final base = numeric
        ? DesignType.numeric(
            fontSize: 13,
            // JetBrains Mono ships bold and extra-bold only.
            fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
            letterSpacing: 0,
          )
        : GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          );
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(color: color ?? (muted ? p.textMuted : p.text)),
    );
  }
}

/// A small coloured status label (Paid, Low stock, Pending).
class DesktopStatusChip extends StatelessWidget {
  const DesktopStatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: p.dark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: GoogleFonts.plusJakartaSans(
          color: p.text,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
