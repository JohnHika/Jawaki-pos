import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/utils/api_message.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/import_models.dart';

/// The server-backed containers list for the desktop shell.
class DesktopImportsView extends StatefulWidget {
  const DesktopImportsView({
    super.key,
    required this.title,
    required this.rows,
    required this.loading,
    required this.canCreate,
    required this.statusColor,
    required this.onOpen,
    required this.onRefresh,
    this.errorMessage,
    this.onCreate,
  });

  final String title;
  final List<ImportSummary> rows;
  final bool loading;
  final String? errorMessage;
  final bool canCreate;
  final Color Function(String status) statusColor;
  final VoidCallback? onCreate;
  final ValueChanged<ImportSummary> onOpen;
  final VoidCallback onRefresh;

  @override
  State<DesktopImportsView> createState() => _DesktopImportsViewState();
}

class _DesktopImportsViewState extends State<DesktopImportsView> {
  String _query = '';
  String? _selectedId;

  List<ImportSummary> get _filteredRows {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.rows;
    return widget.rows.where((row) {
      return row.title.toLowerCase().contains(query) ||
          (row.reference?.toLowerCase().contains(query) ?? false) ||
          (row.origin?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  ImportSummary? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final row in widget.rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final rows = _filteredRows;
    final selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: widget.title,
          subtitle: 'Containers, landed costs and shared balances.',
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actions: [
            IconButton(
              key: const ValueKey('imports-refresh'),
              tooltip: 'Refresh containers',
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
            if (widget.canCreate && widget.onCreate != null)
              FilledButton.icon(
                key: const ValueKey('imports-create'),
                style: desktopPrimaryButton(context),
                onPressed: widget.onCreate,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('New container'),
              ),
          ],
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: DesktopInspectorLayout(
            inspectorWidth: 360,
            overlayBelow: 1100,
            onClose: () => setState(() => _selectedId = null),
            inspector: selected == null ? null : _inspector(context, selected),
            main: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                14,
                selected == null ? 24 : 16,
                16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _query.trim().isEmpty
                              ? '${widget.rows.length} ${widget.rows.length == 1 ? 'container' : 'containers'}'
                              : '${rows.length} of ${widget.rows.length} containers',
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DesktopSearchField(
                        key: const ValueKey('imports-search'),
                        width: 250,
                        hint: 'Search containers',
                        onChanged: (value) => setState(() {
                          _query = value;
                          _selectedId = null;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: p.dark ? p.panelAlt : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.border),
                      ),
                      child: DesktopDataTable<ImportSummary>(
                        rows: rows,
                        rowId: (row) => row.id,
                        selectedId: _selectedId,
                        onRowSelected: (row) =>
                            setState(() => _selectedId = row.id),
                        onRowActivated: widget.onOpen,
                        loading: widget.loading,
                        minWidth: 690,
                        columns: [
                          DesktopColumn<ImportSummary>(
                            label: 'Container',
                            flex: 3,
                            minWidth: 170,
                            sortBy: (row) => row.title.toLowerCase(),
                            cell: (context, row) => DesktopCellText(
                              row.title,
                              strong: true,
                            ),
                          ),
                          DesktopColumn<ImportSummary>(
                            label: 'Status',
                            width: 112,
                            sortBy: (row) => row.status,
                            cell: (context, row) => Align(
                              alignment: Alignment.centerLeft,
                              child: DesktopStatusChip(
                                label: importStatusLabel(row.status),
                                color: widget.statusColor(row.status),
                              ),
                            ),
                          ),
                          DesktopColumn<ImportSummary>(
                            label: 'Landed (KES)',
                            width: 132,
                            numeric: true,
                            sortBy: (row) => row.landedKes,
                            cell: (context, row) => DesktopCellText(
                              kesWhole(row.landedKes),
                              numeric: true,
                            ),
                          ),
                          DesktopColumn<ImportSummary>(
                            label: 'Outstanding',
                            width: 132,
                            numeric: true,
                            sortBy: (row) => row.outstandingKes,
                            cell: (context, row) => DesktopCellText(
                              kesWhole(row.outstandingKes),
                              numeric: true,
                              muted: row.outstandingKes <= 0,
                            ),
                          ),
                          DesktopColumn<ImportSummary>(
                            label: 'Traders',
                            width: 78,
                            numeric: true,
                            sortBy: (row) => row.participantCount,
                            cell: (context, row) => DesktopCellText(
                              '${row.participantCount}',
                              numeric: true,
                            ),
                          ),
                        ],
                        empty: _empty(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    if (widget.errorMessage != null && !widget.loading) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load containers",
        message: widget.errorMessage,
        action: OutlinedButton(
          style: desktopSecondaryButton(context),
          onPressed: widget.onRefresh,
          child: const Text('Try again'),
        ),
      );
    }
    if (_query.trim().isNotEmpty) {
      return DesktopEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No containers match "${_query.trim()}"',
        message: 'Check the name, origin or reference and try again.',
      );
    }
    return DesktopEmptyState(
      icon: Icons.local_shipping_outlined,
      title: 'No containers yet',
      message:
          'Record what you ordered and its added costs to see the server-calculated landed cost.',
      action: widget.canCreate && widget.onCreate != null
          ? FilledButton.icon(
              style: desktopPrimaryButton(context),
              onPressed: widget.onCreate,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('New container'),
            )
          : null,
    );
  }

  Widget _inspector(BuildContext context, ImportSummary row) {
    final label = importStatusLabel(row.status);
    final color = widget.statusColor(row.status);
    return DesktopInspector(
      title: row.title,
      subtitle: [
        label,
        if (row.reference != null && row.reference!.isNotEmpty) row.reference!,
        if (row.origin != null && row.origin!.isNotEmpty) row.origin!,
      ].join(' · '),
      onClose: () => setState(() => _selectedId = null),
      footer: FilledButton.icon(
        key: const ValueKey('imports-open-selected'),
        style: desktopPrimaryButton(context),
        onPressed: () => widget.onOpen(row),
        icon: const Icon(Icons.open_in_new_rounded, size: 17),
        label: const Text('Open container'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopStatusChip(label: label, color: color),
          const SizedBox(height: 20),
          _ImportSummaryLine(label: 'Goods', value: kesWhole(row.goodsKes)),
          _ImportSummaryLine(
              label: 'Costs on top', value: kesWhole(row.costsKes)),
          _ImportSummaryLine(
              label: 'Landed cost', value: kesWhole(row.landedKes)),
          _ImportSummaryLine(
            label: 'Outstanding',
            value: kesWhole(row.outstandingKes),
          ),
          _ImportSummaryLine(
            label: 'Traders sharing',
            value: '${row.participantCount}',
          ),
          _ImportSummaryLine(label: 'Original currency', value: row.currency),
          if (row.expectedArrival != null)
            _ImportSummaryLine(
              label: 'Expected arrival',
              value: MaterialLocalizations.of(context)
                  .formatMediumDate(row.expectedArrival!.toLocal()),
            ),
        ],
      ),
    );
  }
}

class _ImportSummaryLine extends StatelessWidget {
  const _ImportSummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              color: p.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
