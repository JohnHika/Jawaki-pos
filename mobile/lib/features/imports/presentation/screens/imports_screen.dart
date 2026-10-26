import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/import_models.dart';
import '../providers/imports_provider.dart';

Color importStatusColor(String status) => switch (status) {
      'PLANNED' => DesignColors.info,
      'IN_TRANSIT' => DesignColors.warning,
      'ARRIVED' => DesignColors.accent,
      'RECEIVED' => DesignColors.success,
      _ => DesignColors.error,
    };

/// Containers and consignments: what was ordered, what it really cost to land,
/// and who in a shared container still owes their share.
class ImportsScreen extends ConsumerWidget {
  const ImportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imports = ref.watch(importsProvider);
    final perms = ref.watch(permissionsProvider);

    return Scaffold(
      appBar: BrandedAppBar(
        title: ref
            .watch(businessLayoutProvider)
            .actionLabel('/containers', 'Containers'),
        showBackButton: GoRouter.of(context).canPop(),
      ),
      floatingActionButton: perms.has('imports.manage')
          ? FloatingActionButton.extended(
              onPressed: () => _newContainer(context, ref),
              backgroundColor: DesignColors.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New container'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(importsProvider),
        child: imports.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(DesignSpacing.lg),
            children: [
              InlineRetryNotice(
                message: apiErrorMessage(e),
                onRetry: () => ref.invalidate(importsProvider),
              ),
            ],
          ),
          data: (rows) => rows.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 80),
                    EmptyState(
                      icon: Icons.local_shipping_outlined,
                      title: 'No containers yet',
                      subtitle:
                          'Record what you ordered and every cost on top - freight, duty, clearing - and see what each item really costs you.',
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(DesignSpacing.lg,
                      DesignSpacing.md, DesignSpacing.lg, 120),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final color = importStatusColor(r.status);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
                      child: ListCard(
                        leading:
                            Icon(Icons.local_shipping_outlined, color: color),
                        title: r.title,
                        subtitle: [
                          'Landed ${kesWhole(r.landedKes)}',
                          if (r.participantCount > 1)
                            '${r.participantCount} traders',
                          if (r.outstandingKes > 0)
                            'Owed ${kesWhole(r.outstandingKes)}',
                        ].join(' · '),
                        trailing: StatusBadge(
                            label: importStatusLabel(r.status), color: color),
                        onTap: () => context.push('/containers/${r.id}'),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _newContainer(BuildContext context, WidgetRef ref) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NewContainerSheet(),
    );
    ref.invalidate(importsProvider);
    if (id != null && context.mounted) context.push('/containers/$id');
  }
}

class _NewContainerSheet extends StatefulWidget {
  const _NewContainerSheet();

  @override
  State<_NewContainerSheet> createState() => _NewContainerSheetState();
}

class _NewContainerSheetState extends State<_NewContainerSheet> {
  final _title = TextEditingController();
  final _reference = TextEditingController();
  final _origin = TextEditingController();
  final _rate = TextEditingController();
  String _currency = 'USD';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _reference.dispose();
    _origin.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final branchId = getIt<StorageService>().getBranchId();
    if (_title.text.trim().length < 2) {
      setState(() => _error = 'Give the container a name.');
      return;
    }
    if (branchId == null) {
      setState(() => _error = 'Pick a branch first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rate = double.tryParse(_rate.text.trim());
      final json = await getIt<ApiClient>().createImport({
        'branchId': branchId,
        'title': _title.text.trim(),
        if (_reference.text.trim().isNotEmpty)
          'reference': _reference.text.trim(),
        if (_origin.text.trim().isNotEmpty) 'origin': _origin.text.trim(),
        'currency': _currency,
        if (rate != null && rate > 0) 'fxRate': rate,
      });
      if (!mounted) return;
      Navigator.of(context).pop('${json['id']}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(DesignSpacing.lg, 0, DesignSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + DesignSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New container',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: DesignSpacing.md),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: kitFieldDecoration(context,
                  label: 'Name', hint: 'e.g. 40ft kitchenware, October'),
            ),
            const SizedBox(height: DesignSpacing.md),
            TextField(
              controller: _reference,
              textCapitalization: TextCapitalization.characters,
              decoration: kitFieldDecoration(context,
                  label: 'Container / bill of lading no. (optional)'),
            ),
            const SizedBox(height: DesignSpacing.md),
            TextField(
              controller: _origin,
              textCapitalization: TextCapitalization.words,
              decoration: kitFieldDecoration(context,
                  label: 'Coming from (optional)', hint: 'e.g. Guangzhou'),
            ),
            const SizedBox(height: DesignSpacing.md),
            const FormLabel('Supplier prices are in'),
            Wrap(
              spacing: DesignSpacing.sm,
              runSpacing: DesignSpacing.sm,
              children: [
                for (final c in const [
                  'USD',
                  'CNY',
                  'AED',
                  'EUR',
                  'GBP',
                  'KES'
                ])
                  ChoicePill(
                    label: c,
                    selected: _currency == c,
                    onTap: () => setState(() => _currency = c),
                  ),
              ],
            ),
            const SizedBox(height: DesignSpacing.md),
            TextField(
              controller: _rate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: kitFieldDecoration(context,
                  label: 'Exchange rate (optional)',
                  prefixText: 'KES ',
                  helper:
                      "Leave empty to use today's rate. Use your own if you've already bought the money."),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: DesignSpacing.sm),
                child: Text(_error!,
                    style: const TextStyle(color: DesignColors.error)),
              ),
            const SizedBox(height: DesignSpacing.lg),
            GradientButton(
              label: 'Create container',
              icon: Icons.check_rounded,
              isLoading: _busy,
              onPressed: _busy ? null : _create,
            ),
          ],
        ),
      ),
    );
  }
}
