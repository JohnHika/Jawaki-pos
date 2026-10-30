import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/local_archive_import_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';

class LocalArchiveHistoryScreen extends StatefulWidget {
  const LocalArchiveHistoryScreen({super.key});

  @override
  State<LocalArchiveHistoryScreen> createState() =>
      _LocalArchiveHistoryScreenState();
}

class _LocalArchiveHistoryScreenState extends State<LocalArchiveHistoryScreen> {
  late Future<List<LocalArchiveHistorySummary>> _archives;

  LocalArchiveImportService get _service => LocalArchiveImportService(
        database: getIt<AppDatabase>(),
        storage: getIt<StorageService>(),
        auth: getIt<AuthService>(),
      );

  @override
  void initState() {
    super.initState();
    _archives = _service.listPreservedHistory();
  }

  Future<void> _refresh() async {
    final future = _service.listPreservedHistory();
    setState(() => _archives = future);
    await future;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Imported archive history')),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<LocalArchiveHistorySummary>>(
            future: _archives,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ListView(
                  padding: const EdgeInsets.all(DesignSpacing.lg),
                  children: [
                    InlineRetryNotice(
                      message: _safeArchiveError(snapshot.error),
                      onRetry: () => setState(
                          () => _archives = _service.listPreservedHistory()),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final archives = snapshot.data!;
              if (archives.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 72),
                    EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No imported archive history',
                      subtitle:
                          'Import a legacy .cbarchive from Settings → Local data. Any history not yet available in live screens will be kept here for the shop owner.',
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  DesignSpacing.lg,
                  DesignSpacing.md,
                  DesignSpacing.lg,
                  DesignSpacing.xxl,
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(DesignSpacing.md),
                    decoration: BoxDecoration(
                      color: DesignColors.info.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      border: Border.all(
                        color: DesignColors.info.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            color: DesignColors.info),
                        SizedBox(width: DesignSpacing.sm),
                        Expanded(
                          child: Text(
                            'Read-only history from the encrypted archive. These records are not added to current stock or financial totals.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.lg),
                  for (final archive in archives)
                    Card(
                      margin: const EdgeInsets.only(bottom: DesignSpacing.sm),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: DesignSpacing.md,
                          vertical: DesignSpacing.xs,
                        ),
                        leading: const CircleAvatar(
                          backgroundColor: DesignColors.accentSubtle,
                          child: Icon(Icons.archive_outlined,
                              color: DesignColors.accent),
                        ),
                        title: Text(archive.tenantName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          'Imported ${_formatDate(archive.importedAt)} · View preserved records',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push(
                            '/settings/archive-history/${archive.archiveId}'),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
}

class LocalArchiveHistoryDetailScreen extends StatefulWidget {
  const LocalArchiveHistoryDetailScreen({
    required this.archiveId,
    super.key,
  });

  final String archiveId;

  @override
  State<LocalArchiveHistoryDetailScreen> createState() =>
      _LocalArchiveHistoryDetailScreenState();
}

class _LocalArchiveHistoryDetailScreenState
    extends State<LocalArchiveHistoryDetailScreen> {
  late Future<LocalArchiveHistoryDetail> _detail;

  LocalArchiveImportService get _service => LocalArchiveImportService(
        database: getIt<AppDatabase>(),
        storage: getIt<StorageService>(),
        auth: getIt<AuthService>(),
      );

  @override
  void initState() {
    super.initState();
    _detail = _service.loadPreservedHistory(widget.archiveId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Preserved shop records')),
        body: FutureBuilder<LocalArchiveHistoryDetail>(
          future: _detail,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(DesignSpacing.lg),
                children: [
                  InlineRetryNotice(
                    message: _safeArchiveError(snapshot.error),
                    onRetry: () =>
                        setState(() => _detail = _service.loadPreservedHistory(
                              widget.archiveId,
                            )),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final detail = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                DesignSpacing.lg,
                DesignSpacing.md,
                DesignSpacing.lg,
                DesignSpacing.xxl,
              ),
              children: [
                Text(detail.summary.tenantName,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: DesignSpacing.xs),
                Text(
                  'Archive imported ${_formatDate(detail.summary.importedAt)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: DesignColors.textSecondary,
                      ),
                ),
                const SizedBox(height: DesignSpacing.lg),
                if (detail.sections.isEmpty)
                  const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'All imported history is available',
                    subtitle:
                        'This archive has no additional preserved-only records.',
                  )
                else ...[
                  const Text(
                    'Preserved history',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: DesignSpacing.sm),
                  for (final section in detail.sections)
                    Card(
                      margin: const EdgeInsets.only(bottom: DesignSpacing.sm),
                      child: ListTile(
                        leading: const Icon(Icons.history_rounded,
                            color: DesignColors.accent),
                        title: Text(section.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle:
                            Text('${section.rows.length} read-only records'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _showSection(context, section),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      );

  Future<void> _showSection(
    BuildContext context,
    LocalArchiveHistorySection section,
  ) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: 0.9,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignSpacing.lg,
                  DesignSpacing.xs,
                  DesignSpacing.lg,
                  DesignSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section.label,
                        style: Theme.of(sheetContext).textTheme.titleLarge),
                    const SizedBox(height: DesignSpacing.xs),
                    Text(
                      '${section.rows.length} archived records · Read only',
                      style: Theme.of(sheetContext).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    DesignSpacing.lg,
                    0,
                    DesignSpacing.lg,
                    DesignSpacing.xl,
                  ),
                  itemCount: section.rows.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: DesignSpacing.xs),
                  itemBuilder: (context, index) => _ArchivedRecordTile(
                    section: section,
                    row: section.rows[index],
                    index: index,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ArchivedRecordTile extends StatelessWidget {
  const _ArchivedRecordTile({
    required this.section,
    required this.row,
    required this.index,
  });

  final LocalArchiveHistorySection section;
  final Map<String, dynamic> row;
  final int index;

  static const _visibleFields = <String, List<String>>{
    'retailReceivables': [
      'customerName',
      'customerId',
      'branchName',
      'amount',
      'paidAmount',
      'outstandingAmount',
      'status',
      'dueDate',
      'createdAt',
      'saleId',
      'notes',
    ],
    'users': ['name', 'email', 'phone', 'role', 'isActive', 'createdAt'],
    'userBranches': ['userName', 'branchName', 'role', 'isPrimary'],
    'saleItemBatches': [
      'productName',
      'batchNumber',
      'quantity',
      'unitCost',
      'createdAt',
    ],
    'stockBatches': [
      'productName',
      'batchNumber',
      'quantity',
      'costPrice',
      'supplierRef',
      'expiryDate',
      'manufactureDate',
      'isBlocked',
      'notes',
      'createdAt',
    ],
    'stockMovements': [
      'productName',
      'type',
      'quantity',
      'previousQty',
      'newQty',
      'reason',
      'reference',
      'batchNumber',
      'notes',
      'createdAt',
    ],
    'stockCounts': [
      'title',
      'status',
      'blind',
      'totalVarianceValue',
      'notes',
      'createdAt',
      'submittedAt',
      'approvedAt',
    ],
    'stockCountItems': [
      'productName',
      'sku',
      'expectedQty',
      'countedQty',
      'unitCost',
      'reason',
      'countedAt',
    ],
    'cashLedgerEntries': [
      'type',
      'amount',
      'balanceAfter',
      'referenceType',
      'referenceId',
      'note',
      'createdAt',
    ],
    'cashReconciliations': [
      'cashMode',
      'periodStart',
      'periodEnd',
      'expectedCash',
      'countedCash',
      'discrepancy',
      'notes',
      'createdAt',
    ],
    'dailyCloses': [
      'date',
      'cashSales',
      'mpesaSales',
      'cardSales',
      'creditSales',
      'totalSales',
      'totalTransactions',
      'expectedCash',
      'countedCash',
      'cashDiscrepancy',
      'closedAt',
      'notes',
    ],
  };

  static const _moneyFields = <String>{
    'costPrice',
    'unitCost',
    'amount',
    'paidAmount',
    'outstandingAmount',
    'balanceAfter',
    'totalVarianceValue',
    'expectedCash',
    'countedCash',
    'discrepancy',
    'cashSales',
    'mpesaSales',
    'cardSales',
    'creditSales',
    'totalSales',
    'cashDiscrepancy',
  };

  @override
  Widget build(BuildContext context) {
    final fields = _visibleFields[section.key] ?? const <String>[];
    final values = <String>[];
    for (final field in fields) {
      final value = row[field];
      if (value == null || value.toString().trim().isEmpty) continue;
      values.add('${_fieldLabel(field)}: ${_displayValue(value, field)}');
    }
    final title = _recordTitle(row) ?? '${section.label} record ${index + 1}';
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.description_outlined),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: values.isEmpty
            ? const Text('Details are preserved in the encrypted archive.')
            : Text(values.join(' · '), maxLines: 4),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showArchivedRecordDetails(
          context,
          section: section,
          row: row,
          title: title,
        ),
      ),
    );
  }

  static List<String> visibleFieldsFor(String sectionKey) =>
      _visibleFields[sectionKey] ?? const <String>[];
}

Future<void> _showArchivedRecordDetails(
  BuildContext context, {
  required LocalArchiveHistorySection section,
  required Map<String, dynamic> row,
  required String title,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final fields =
            _ArchivedRecordTile.visibleFieldsFor(section.key).where((field) {
          final value = row[field];
          return value != null && value.toString().trim().isNotEmpty;
        }).toList(growable: false);

        return FractionallySizedBox(
          heightFactor: 0.86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignSpacing.lg,
                  DesignSpacing.xs,
                  DesignSpacing.lg,
                  DesignSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.label,
                      style:
                          Theme.of(sheetContext).textTheme.labelLarge?.copyWith(
                                color: DesignColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: DesignSpacing.xs),
                    Text(
                      title,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: DesignSpacing.xs),
                    const Text('Read-only record from the encrypted archive.'),
                  ],
                ),
              ),
              Expanded(
                child: fields.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(DesignSpacing.xl),
                          child: Text(
                            'No additional details were saved for this record.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          DesignSpacing.lg,
                          0,
                          DesignSpacing.lg,
                          DesignSpacing.xl,
                        ),
                        itemCount: fields.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: DesignSpacing.xs),
                        itemBuilder: (context, index) {
                          final field = fields[index];
                          final value = row[field]!;
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(DesignSpacing.md),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? DesignColors.darkSurfaceElevated
                                  : DesignColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(
                                DesignSpacing.radiusMd,
                              ),
                              border: Border.all(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? DesignColors.darkBorder
                                    : DesignColors.surfaceBorder,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _fieldLabel(field),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: DesignColors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: DesignSpacing.xs),
                                SelectableText(
                                  _displayValue(value, field),
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );

String? _recordTitle(Map<String, dynamic> row) {
  for (final key in const [
    'customerName',
    'productName',
    'batchNumber',
    'receiptNumber',
    'reference',
    'name',
    'title',
    'description',
  ]) {
    final value = row[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String _fieldLabel(String key) => switch (key) {
      'customerName' => 'Customer',
      'customerId' => 'Customer ID',
      'branchName' => 'Branch',
      'dueDate' => 'Due date',
      'saleId' => 'Related sale',
      'paidAmount' => 'Paid',
      'outstandingAmount' => 'Open balance',
      'isActive' => 'Active',
      'isPrimary' => 'Primary branch',
      'isBlocked' => 'Blocked batch',
      'previousQty' => 'Before',
      'newQty' => 'After',
      'expectedQty' => 'Expected qty',
      'countedQty' => 'Counted qty',
      'totalVarianceValue' => 'Variance value',
      'referenceType' => 'Reference type',
      'referenceId' => 'Reference',
      'periodStart' => 'Period start',
      'periodEnd' => 'Period end',
      'expectedCash' => 'Expected cash',
      'countedCash' => 'Counted cash',
      'cashDiscrepancy' => 'Cash difference',
      'createdAt' => 'Created',
      'closedAt' => 'Closed',
      'countedAt' => 'Counted',
      'submittedAt' => 'Submitted',
      'approvedAt' => 'Approved',
      'expiryDate' => 'Expires',
      'manufactureDate' => 'Made',
      'supplierRef' => 'Supplier ref',
      'unitCost' => 'Unit cost',
      'costPrice' => 'Unit cost',
      _ => key.replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'), (match) => '${match[1]} ${match[2]}'),
    };

String _displayValue(Object value, String field) {
  if (value is bool) return value ? 'Yes' : 'No';
  if (_ArchivedRecordTile._moneyFields.contains(field) && value is num) {
    return formatMoney(value);
  }
  if (field.toLowerCase().contains('date') ||
      field.toLowerCase().endsWith('at')) {
    final parsed = DateTime.tryParse(value.toString());
    if (parsed != null) return _formatDate(parsed);
  }
  return value.toString();
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _safeArchiveError(Object? error) => error is LocalArchiveImportException
    ? error.message
    : 'Could not read imported archive history. Keep the original archive and try again.';
