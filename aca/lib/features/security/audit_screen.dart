import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../billing/paged_list.dart';
import 'audit_entry_card.dart';
import 'audit_entry_sheet.dart';
import 'security_logic.dart';

export 'audit_entry_sheet.dart' show showAuditEntrySheet;

/// The platform audit log: every sign-in, team change, company action,
/// billing and licence event, newest first, with search and filters.
///
/// [tenantId] / [actorId] narrow the log to one company / one staff member;
/// the on-screen filters always combine with them.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, this.tenantId, this.actorId, this.title});

  final String? tenantId;
  final String? actorId;
  final String? title;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  static const int _pageSize = 30;
  static const Duration _debounce = Duration(milliseconds: 400);

  late final AcaRepository _repo = context.read<AcaRepository>();
  late final PagedController<AuditEntry> _entries;
  final TextEditingController _searchText = TextEditingController();
  Timer? _timer;

  String? _category;
  String? _severity;

  /// The search text the current results were requested with.
  String _query = '';

  bool get _filtered => _category != null || _severity != null || _query.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _entries = PagedController<AuditEntry>(
      fetch: (page) => _repo.audit(
        category: _category,
        severity: _severity,
        actorId: widget.actorId,
        tenantId: widget.tenantId,
        search: _query.isEmpty ? null : _query,
        page: page,
        pageSize: _pageSize,
      ),
      idOf: (e) => e.id,
    )..refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchText.dispose();
    _entries.dispose();
    super.dispose();
  }

  void _reload() => _entries.refresh(clear: true);

  void _onSearchChanged(String _) {
    setState(() {}); // shows / hides the clear button
    _timer?.cancel();
    _timer = Timer(_debounce, _applySearch);
  }

  void _applySearch() {
    _timer?.cancel();
    final q = _searchText.text.trim();
    if (q == _query) return;
    _query = q;
    _reload();
  }

  void _setCategory(String? v) {
    if (v == _category) return;
    setState(() => _category = v);
    _reload();
  }

  void _setSeverity(String? v) {
    if (v == _severity) return;
    setState(() => _severity = v);
    _reload();
  }

  void _clearFilters() {
    _timer?.cancel();
    _searchText.clear();
    setState(() {
      _category = null;
      _severity = null;
      _query = '';
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Audit log')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchText,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _applySearch(),
              textInputAction: TextInputAction.search,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Search activity, email or action',
                prefixIcon: const Icon(Icons.search_rounded),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                suffixIcon: _searchText.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchText.clear();
                          _applySearch();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          _ChipRow(
            filters: auditCategoryFilters,
            selected: _category,
            onSelected: _setCategory,
          ),
          _ChipRow(
            filters: auditSeverityFilters,
            selected: _severity,
            onSelected: _setSeverity,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListenableBuilder(
              listenable: _entries,
              builder: (context, _) {
                final rows = buildAuditRows(_entries.items);
                return PagedListBody(
                  controller: _entries,
                  skeleton: const ListSkeleton(rows: 7, rowHeight: 84),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row.isHeader) return _DayHeader(row.header!);
                    final entry = row.entry!;
                    return AuditEntryCard(
                      entry: entry,
                      onTap: () => showAuditEntrySheet(
                        context,
                        entry,
                        showActorLink: widget.actorId == null,
                        showCompanyLink: widget.tenantId == null,
                      ),
                    );
                  },
                  emptyState: EmptyState(
                    icon: _filtered ? Icons.search_off_rounded : Icons.history_rounded,
                    title: _filtered ? 'Nothing matches' : 'No activity recorded yet',
                    message: _filtered
                        ? 'No audit entries match your search and filters.'
                        : 'Sign-ins, team changes and company actions will be listed here.',
                    action: _filtered ? 'Clear filters' : null,
                    onAction: _filtered ? _clearFilters : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontally scrolling single-choice chips.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.filters, required this.selected, required this.onSelected});

  final List<(String?, String)> filters;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (value, label) = filters[i];
          return Center(
            child: ChoiceChip(
              label: Text(label),
              selected: selected == value,
              showCheckmark: false,
              onSelected: (_) => onSelected(value),
            ),
          );
        },
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: p.textMuted),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: p.border)),
        ],
      ),
    );
  }
}
