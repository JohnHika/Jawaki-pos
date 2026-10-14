import 'package:flutter/material.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/motion_kit_extras.dart';
import '../../domain/bulk_allocation.dart';
import '../../domain/collections_ledger.dart';
import '../providers/finance_hub_controller.dart';

/// Records one instalment from another shop and spreads it across everything
/// that shop owes, oldest due first. Returns the amount collected, or null if
/// the sheet was dismissed.
Future<double?> showShopInstallmentSheet(
  BuildContext context, {
  required ShopStatement statement,
  required String branchId,
  required FinanceHubController controller,
}) {
  return showModalBottomSheet<double>(
    useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _InstallmentForm(
      statement: statement,
      branchId: branchId,
      controller: controller,
    ),
  );
}

class _InstallmentForm extends StatefulWidget {
  const _InstallmentForm({
    required this.statement,
    required this.branchId,
    required this.controller,
  });

  final ShopStatement statement;
  final String branchId;
  final FinanceHubController controller;

  @override
  State<_InstallmentForm> createState() => _InstallmentFormState();
}

class _InstallmentFormState extends State<_InstallmentForm> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  // Fixed for this sheet so a retry after a dropped connection cannot pay twice.
  final _offlineId = 'peer-bulk-${DateTime.now().microsecondsSinceEpoch}';
  String _method = 'CASH';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  double get _entered => double.tryParse(_amount.text.replaceAll(',', '')) ?? 0;

  Future<void> _save(BulkAllocationPlan plan) async {
    if (_saving) return;
    final owed = widget.statement.outstanding;
    if (_entered <= 0) {
      setState(() => _error = 'Enter the amount the shop paid');
      return;
    }
    if (plan.unallocated > 0) {
      setState(() => _error = 'More than the shop owes (${formatMoney(owed)})');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.recordPeerBulkCollection(BulkCollectionRequest(
        branchId: widget.branchId,
        allocations: plan.allocations,
        method: _method,
        reference:
            _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        offlineId: _offlineId,
      ));
      if (mounted) Navigator.pop(context, plan.total);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is FinanceFormException
            ? e.message
            : 'Couldn’t record the instalment. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statement = widget.statement;
    final open = statement.openDebts;
    final plan = allocatePeerOldestFirst(open, _entered);
    final after = ((statement.outstanding - plan.total) * 100).round() / 100;
    final byId = {for (final d in open) d.id: d};

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(DesignSpacing.xl, DesignSpacing.sm,
            DesignSpacing.xl, MediaQuery.viewInsetsOf(context).bottom + DesignSpacing.xl),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Instalment from ${statement.shop.name}',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: DesignSpacing.xs),
              Text(
                '${formatMoney(statement.outstanding)} still owed across '
                '${open.length} debt${open.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: DesignSpacing.lg),
              SegmentedButton<String>(
                expandedInsets: EdgeInsets.zero,
                segments: const <ButtonSegment<String>>[
                  ButtonSegment(value: 'CASH', label: Text('Cash')),
                  ButtonSegment(value: 'MPESA', label: Text('M-Pesa')),
                  ButtonSegment(value: 'CARD', label: Text('Card')),
                ],
                selected: <String>{_method},
                onSelectionChanged: (v) => setState(() => _method = v.first),
              ),
              const SizedBox(height: DesignSpacing.md),
              TextField(
                key: const ValueKey('installment-amount'),
                controller: _amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'Amount collected (KES)',
                  errorText: _error,
                  suffixIcon: TextButton(
                    onPressed: () => setState(() {
                      _amount.text = statement.outstanding.toStringAsFixed(0);
                      _error = null;
                    }),
                    child: const Text('Full balance'),
                  ),
                ),
              ),
              if (_entered > 0 && plan.allocations.isNotEmpty) ...<Widget>[
                const SizedBox(height: DesignSpacing.md),
                Container(
                  key: const ValueKey('installment-preview'),
                  padding: const EdgeInsets.all(DesignSpacing.md),
                  decoration: BoxDecoration(
                    color: DesignColors.peach.withValues(alpha: 0.5),
                    borderRadius:
                        BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('This payment settles, oldest first',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: DesignSpacing.xs),
                      for (final a in plan.allocations)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  byId[a.receivableId]?.description ?? 'Debt',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(formatMoney(a.amount),
                                  style: DesignType.numeric(fontSize: 13)),
                            ],
                          ),
                        ),
                      const Divider(height: DesignSpacing.lg),
                      Row(
                        children: <Widget>[
                          const Expanded(child: Text('Balance after')),
                          RollingNumber(formatMoney(after),
                              style: DesignType.numeric(fontSize: 14)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: DesignSpacing.md),
              TextField(
                controller: _reference,
                decoration: const InputDecoration(
                    labelText: 'Reference, e.g. M-Pesa code (optional)'),
              ),
              const SizedBox(height: DesignSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: DesignSpacing.huge,
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(plan),
                  child: Text(_saving ? 'Recording…' : 'Record instalment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
