import 'package:flutter/material.dart';
import '../../theme/counterbase_theme.dart';

import '../../core/desktop_workspace.dart';

Future<void> showDesktopArchiveHistoryDialog(
  BuildContext context,
  DesktopWorkspaceStore workspace,
) => showDialog<void>(
  context: context,
  builder: (_) => _DesktopArchiveHistoryDialog(workspace: workspace),
);

class _DesktopArchiveHistoryDialog extends StatefulWidget {
  const _DesktopArchiveHistoryDialog({required this.workspace});

  final DesktopWorkspaceStore workspace;

  @override
  State<_DesktopArchiveHistoryDialog> createState() =>
      _DesktopArchiveHistoryDialogState();
}

class _DesktopArchiveHistoryDialogState
    extends State<_DesktopArchiveHistoryDialog> {
  late Future<List<Map<String, dynamic>>> _archives;
  Future<Map<String, dynamic>?>? _payload;
  String? _selectedArchiveId;

  static const _sectionLabels = <String, String>{
    'users': 'Staff profiles',
    'userBranches': 'Staff branch assignments',
    'saleItemBatches': 'Sale batch links',
    'stockBatches': 'Inventory batches',
    'stockMovements': 'Stock movement history',
    'stockCounts': 'Stock count sessions',
    'stockCountItems': 'Stock count lines',
    'cashLedgerEntries': 'Cash ledger history',
    'cashReconciliations': 'Cash reconciliation history',
    'dailyCloses': 'End-of-day close history',
  };

  @override
  void initState() {
    super.initState();
    _archives = widget.workspace.getImportedArchiveHistory();
  }

  void _selectArchive(Map<String, dynamic> archive) {
    final id = archive['archiveId']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() {
      _selectedArchiveId = id;
      _payload = widget.workspace.getImportedArchivePayload(id);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Imported archive history'),
    content: SizedBox(
      width: 820,
      height: 560,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _archives,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Could not read imported archive history.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final archives = snapshot.data!;
          if (archives.isEmpty) {
            return const Center(
              child: Text('No legacy shop archives have been imported.'),
            );
          }
          return Row(
            children: [
              SizedBox(
                width: 265,
                child: ListView.separated(
                  itemCount: archives.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final archive = archives[index];
                    final id = archive['archiveId']?.toString();
                    final date = DateTime.tryParse(
                      archive['importedAt']?.toString() ?? '',
                    );
                    return ListTile(
                      selected: id == _selectedArchiveId,
                      leading: const Icon(Icons.archive_outlined),
                      title: Text(
                        archive['tenantName']?.toString() ?? 'Shop',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        date == null
                            ? 'Imported archive'
                            : 'Imported ${MaterialLocalizations.of(context).formatMediumDate(date.toLocal())}',
                      ),
                      onTap: () => _selectArchive(archive),
                    );
                  },
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _buildArchiveDetail(context)),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );

  Widget _buildArchiveDetail(BuildContext context) {
    final future = _payload;
    if (future == null) {
      return const Center(
        child: Text('Choose an archive to browse its preserved records.'),
      );
    }
    return FutureBuilder<Map<String, dynamic>?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('This archive history could not be read.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final payload = snapshot.data;
        if (payload == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This archive was imported by an earlier desktop version. Select the same .cbarchive file again to add its remaining history here.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final sections = <MapEntry<String, List<Map<String, dynamic>>>>[];
        for (final entry in payload.entries) {
          if (entry.key == 'tenant') continue;
          final rawRows = entry.value;
          if (rawRows is! List || rawRows.isEmpty) continue;
          sections.add(
            MapEntry(
              entry.key.toString(),
              rawRows.whereType<Map>().map(Map<String, dynamic>.from).toList(),
            ),
          );
        }
        if (sections.isEmpty) {
          return const Center(
            child: Text('This archive has no additional preserved records.'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                'Read-only archive data. These records do not change live stock or financial totals.',
                style: TextStyle(color: CbInk.ink2),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: sections.length,
                itemBuilder: (context, index) {
                  final section = sections[index];
                  return ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(
                      _sectionLabels[section.key] ?? _fieldLabel(section.key),
                    ),
                    subtitle: Text(
                      '${section.value.length} records Â· Read only',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => _ArchiveSectionDialog(
                        title:
                            _sectionLabels[section.key] ??
                            _fieldLabel(section.key),
                        rows: section.value,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ArchiveSectionDialog extends StatelessWidget {
  const _ArchiveSectionDialog({required this.title, required this.rows});

  final String title;
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 680,
      height: 520,
      child: ListView.separated(
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = rows[index];
          final titleValue = _recordTitle(row, index);
          final entries = row.entries
              .where((entry) => entry.value != null)
              .toList(growable: false);
          return ExpansionTile(
            title: Text(titleValue),
            subtitle: Text('${entries.length} archived fields'),
            children: [
              for (final entry in entries)
                ListTile(
                  dense: true,
                  title: Text(_fieldLabel(entry.key)),
                  subtitle: SelectableText(_displayValue(entry.value)),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

String _recordTitle(Map<String, dynamic> row, int index) {
  for (final field in const [
    'receiptNumber',
    'batchNumber',
    'title',
    'name',
    'type',
  ]) {
    final value = row[field]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return 'Record ${index + 1}';
}

String _fieldLabel(String field) => field
    .replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    )
    .replaceAll('_', ' ')
    .split(' ')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

String _displayValue(dynamic value) {
  if (value is Map || value is List) return 'Structured archive value';
  final text = value.toString();
  if (text.length <= 500) return text;
  return '${text.substring(0, 500)}…';
}
