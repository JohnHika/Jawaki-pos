import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/theme/design_system.dart';
import '../../data/models/permission_catalog.dart';

/// The five columns of the permission matrix. Every other action a feature
/// has (void, refund, export...) is listed under "More".
enum MatrixColumn {
  view('View'),
  create('Create'),
  edit('Edit'),
  delete('Delete'),
  approve('Approve');

  const MatrixColumn(this.label);
  final String label;

  /// The column a permission belongs to, or null for "More".
  static MatrixColumn? of(PermissionDef def) {
    switch (def.action.toLowerCase()) {
      case 'view':
      case 'read':
      case 'list':
        return MatrixColumn.view;
      case 'create':
        return MatrixColumn.create;
      case 'update':
      case 'edit':
        return MatrixColumn.edit;
      case 'delete':
        return MatrixColumn.delete;
      case 'approve':
        return MatrixColumn.approve;
    }
    return null;
  }
}

/// Rows are the areas of the shop (Sales, Products, Expenses...), columns are
/// what a role may do there. The header stays in place while the rows scroll;
/// a checkbox in the header turns a whole column on or off, one in the first
/// cell turns a whole row on or off. Permissions that are not View / Create /
/// Edit / Delete / Approve open under the row.
///
/// It edits the same set of permission keys the phone's role editor does.
class DesktopPermissionMatrix extends StatefulWidget {
  const DesktopPermissionMatrix({
    super.key,
    required this.groups,
    required this.selectedKeys,
    required this.onChanged,
    this.readOnly = false,
  });

  final List<PermissionFeatureGroup> groups;
  final Set<String> selectedKeys;

  /// Turns every key in [keys] on or off.
  final void Function(Iterable<String> keys, bool value) onChanged;
  final bool readOnly;

  static const double rowHeight = 44;
  static const double cellWidth = 76;
  static const double moreWidth = 104;

  @override
  State<DesktopPermissionMatrix> createState() =>
      _DesktopPermissionMatrixState();
}

class _DesktopPermissionMatrixState extends State<DesktopPermissionMatrix> {
  final Set<String> _open = {};

  List<PermissionDef> _inColumn(
    PermissionFeatureGroup group,
    MatrixColumn column,
  ) =>
      [
        for (final def in group.permissions)
          if (MatrixColumn.of(def) == column) def,
      ];

  List<PermissionDef> _more(PermissionFeatureGroup group) => [
        for (final def in group.permissions)
          if (MatrixColumn.of(def) == null) def,
      ];

  /// true when all are on, false when none, null when mixed.
  bool? _state(Iterable<PermissionDef> defs) {
    if (defs.isEmpty) return false;
    final on = defs.where((d) => widget.selectedKeys.contains(d.key)).length;
    if (on == 0) return false;
    return on == defs.length ? true : null;
  }

  void _toggle(Iterable<PermissionDef> defs, bool? current) {
    if (widget.readOnly || defs.isEmpty) return;
    widget.onChanged(defs.map((d) => d.key), current != true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = 220.0 +
            MatrixColumn.values.length * DesktopPermissionMatrix.cellWidth +
            DesktopPermissionMatrix.moreWidth;
        final width =
            constraints.maxWidth < minWidth ? minWidth : constraints.maxWidth;
        Widget table = SizedBox(
          width: width,
          child: Column(
            children: [
              _header(context, p),
              Divider(height: 1, color: p.border),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.groups.length,
                  itemBuilder: (context, i) =>
                      _row(context, p, widget.groups[i]),
                ),
              ),
            ],
          ),
        );
        if (constraints.maxWidth < minWidth) {
          table = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          );
        }
        return table;
      },
    );
  }

  Widget _header(BuildContext context, DesktopPalette p) {
    return Container(
      height: 44,
      color: p.dark ? p.panelAlt : p.panelAlt,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Area',
              style: _headStyle(p),
            ),
          ),
          for (final column in MatrixColumn.values)
            SizedBox(
              width: DesktopPermissionMatrix.cellWidth,
              child: _HeaderCell(
                label: column.label,
                state: _columnState(column),
                readOnly: widget.readOnly,
                onTap: () {
                  final all = [
                    for (final g in widget.groups) ..._inColumn(g, column),
                  ];
                  _toggle(all, _state(all));
                },
              ),
            ),
          SizedBox(
            width: DesktopPermissionMatrix.moreWidth,
            child: Align(
              alignment: Alignment.center,
              child: Text('More', style: _headStyle(p)),
            ),
          ),
        ],
      ),
    );
  }

  bool? _columnState(MatrixColumn column) {
    final all = [
      for (final g in widget.groups) ..._inColumn(g, column),
    ];
    if (all.isEmpty) return false;
    return _state(all);
  }

  TextStyle _headStyle(DesktopPalette p) => GoogleFonts.plusJakartaSans(
        color: p.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      );

  Widget _row(
    BuildContext context,
    DesktopPalette p,
    PermissionFeatureGroup group,
  ) {
    final all = group.permissions;
    final more = _more(group);
    final open = _open.contains(group.feature);
    final onCount =
        all.where((d) => widget.selectedKeys.contains(d.key)).length;

    return Column(
      key: ValueKey('matrix-row-${group.feature}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: DesktopPermissionMatrix.rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _Tick(
                      key: ValueKey('matrix-all-${group.feature}'),
                      state: _state(all),
                      readOnly: widget.readOnly,
                      semanticLabel: 'Everything in ${group.displayName}',
                      onTap: () => _toggle(all, _state(all)),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        group.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$onCount/${all.length}',
                      style: DesignType.numeric(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: p.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              for (final column in MatrixColumn.values)
                SizedBox(
                  width: DesktopPermissionMatrix.cellWidth,
                  child: Center(
                    child: _cell(group, column, p),
                  ),
                ),
              SizedBox(
                width: DesktopPermissionMatrix.moreWidth,
                child: Center(
                  child: more.isEmpty
                      ? Text('–', style: TextStyle(color: p.textFaint))
                      : TextButton(
                          key: ValueKey('matrix-more-${group.feature}'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            textStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                            foregroundColor: p.accent,
                          ),
                          onPressed: () => setState(() {
                            if (!_open.add(group.feature)) {
                              _open.remove(group.feature);
                            }
                          }),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${more.where((d) => widget.selectedKeys.contains(d.key)).length}/${more.length}',
                              ),
                              Icon(
                                open
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        if (open && more.isNotEmpty)
          Container(
            width: double.infinity,
            color: p.dark ? p.hover : p.panelAlt,
            padding: const EdgeInsets.fromLTRB(44, 6, 12, 8),
            decoration: null,
            child: Wrap(
              spacing: 20,
              runSpacing: 2,
              children: [
                for (final def in more)
                  SizedBox(
                    width: 250,
                    child: _MoreItem(
                      def: def,
                      selected: widget.selectedKeys.contains(def.key),
                      readOnly: widget.readOnly,
                      onChanged: (v) => widget.onChanged([def.key], v),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(
    PermissionFeatureGroup group,
    MatrixColumn column,
    DesktopPalette p,
  ) {
    final defs = _inColumn(group, column);
    if (defs.isEmpty) return Text('–', style: TextStyle(color: p.textFaint));
    final state = _state(defs);
    return _Tick(
      key: ValueKey('matrix-${group.feature}-${column.name}'),
      state: state,
      readOnly: widget.readOnly,
      semanticLabel: '${column.label} ${group.displayName}',
      tooltip: defs.length == 1 ? defs.first.label : null,
      onTap: () => _toggle(defs, state),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.state,
    required this.readOnly,
    required this.onTap,
  });

  final String label;
  final bool? state;
  final bool readOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return InkWell(
      onTap: readOnly ? null : onTap,
      hoverColor: p.hover,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: state,
              tristate: true,
              onChanged: readOnly ? null : (_) => onTap(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({
    super.key,
    required this.state,
    required this.readOnly,
    required this.onTap,
    required this.semanticLabel,
    this.tooltip,
  });

  final bool? state;
  final bool readOnly;
  final VoidCallback onTap;
  final String semanticLabel;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      width: 32,
      height: 32,
      child: Semantics(
        label: semanticLabel,
        child: Checkbox(
          value: state,
          tristate: true,
          onChanged: readOnly ? null : (_) => onTap(),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
    return tooltip == null ? box : Tooltip(message: tooltip!, child: box);
  }
}

class _MoreItem extends StatelessWidget {
  const _MoreItem({
    required this.def,
    required this.selected,
    required this.readOnly,
    required this.onChanged,
  });

  final PermissionDef def;
  final bool selected;
  final bool readOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return InkWell(
      onTap: readOnly ? null : () => onChanged(!selected),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: selected,
              onChanged: readOnly ? null : (v) => onChanged(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Tooltip(
              message: def.key,
              child: Text(
                def.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: p.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
