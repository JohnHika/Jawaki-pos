import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../inventory/presentation/widgets/product_picker_dialog.dart';
import '../../domain/import_models.dart';
import '../providers/imports_provider.dart';
import 'imports_screen.dart' show importStatusColor;

/// One container: the goods, every cost on top, what each item really costs
/// to land, and who in a shared container owes what.
class ImportDetailScreen extends ConsumerStatefulWidget {
  const ImportDetailScreen({super.key, required this.importId});

  final String importId;

  @override
  ConsumerState<ImportDetailScreen> createState() => _ImportDetailScreenState();
}

class _ImportDetailScreenState extends ConsumerState<ImportDetailScreen> {
  bool _busy = false;

  ApiClient get _api => getIt<ApiClient>();

  void _refresh() {
    ref.invalidate(importDetailProvider(widget.importId));
    ref.invalidate(importsProvider);
  }

  /// Runs an API call, refreshes, and shows a friendly error if it fails.
  Future<bool> _run(Future<dynamic> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
      if (done != null && mounted) {
        showGlassSnackBar(context, done,
            icon: Icons.check_circle_rounded, color: DesignColors.success);
      }
      return true;
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, apiErrorMessage(e),
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<T?> _sheet<T>(Widget child) => showModalBottomSheet<T>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => child,
      );

  Future<void> _confirmDelete(String what, Future<dynamic> Function() action) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $what?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (go == true) await _run(action);
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(importDetailProvider(widget.importId));
    final perms = ref.watch(permissionsProvider);

    return Scaffold(
      appBar: BrandedAppBar(
        title: detail.valueOrNull?.title ?? 'Container',
        showBackButton: true,
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(DesignSpacing.lg),
          child: InlineRetryNotice(
            message: apiErrorMessage(e),
            onRetry: () => ref.invalidate(importDetailProvider(widget.importId)),
          ),
        ),
        data: (d) => _body(context, d, perms.has('imports.manage'),
            perms.has('imports.receive'), perms.has('imports.payments')),
      ),
    );
  }

  Widget _body(BuildContext context, ImportDetail d, bool canManage,
      bool canReceive, bool canPay) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final color = importStatusColor(d.status);
    final editable = d.isOpen && canManage;

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, 120),
        children: [
          Row(
            children: [
              StatusBadge(label: importStatusLabel(d.status), color: color),
              const SizedBox(width: DesignSpacing.sm),
              Expanded(
                child: Text(
                  [
                    if (d.reference != null) d.reference!,
                    if (d.origin != null) d.origin!,
                    '${d.currency} @ ${d.fxRate.toStringAsFixed(2)}',
                  ].join(' · '),
                  style: TextStyle(color: secondary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignSpacing.md),
          _TotalsCard(detail: d),
          for (final w in d.warnings)
            Padding(
              padding: const EdgeInsets.only(top: DesignSpacing.sm),
              child: Text(w,
                  style: const TextStyle(color: DesignColors.warning, fontSize: 12)),
            ),
          if (canManage && d.isOpen) ...[
            const SizedBox(height: DesignSpacing.md),
            _statusActions(d, canReceive),
          ],
          const SizedBox(height: DesignSpacing.xl),
          SectionHeader(
            title: 'Goods',
            subtitle: '${d.items.length} line${d.items.length == 1 ? '' : 's'}',
            trailing: editable
                ? TextButton.icon(
                    onPressed: _busy ? null : () => _addItem(d),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'))
                : null,
          ),
          const SizedBox(height: DesignSpacing.sm),
          if (d.items.isEmpty)
            Text('Add the goods in this container to see what each costs you.',
                style: TextStyle(color: secondary))
          else
            for (final i in d.items) _itemTile(d, i, editable, secondary),
          const SizedBox(height: DesignSpacing.xl),
          SectionHeader(
            title: 'Costs on top',
            subtitle: 'Freight, duty, clearing...',
            trailing: editable
                ? TextButton.icon(
                    onPressed: _busy ? null : () => _addCost(d),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'))
                : null,
          ),
          const SizedBox(height: DesignSpacing.sm),
          if (d.costs.isEmpty)
            Text('No costs yet. Duty and clearing are what surprise people.',
                style: TextStyle(color: secondary))
          else
            for (final c in d.costs)
              Padding(
                padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
                child: ListCard(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: c.title,
                  subtitle: [
                    if (c.currency != 'KES')
                      '${c.currency} ${kitNumber(c.amount)}',
                    if (c.reference != null) c.reference!,
                  ].join(' · '),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(kesWhole(c.amountKes),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (editable)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: _busy
                              ? null
                              : () => _confirmDelete('this cost',
                                  () => _api.removeImportCost(d.id, c.id)),
                        ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: DesignSpacing.xl),
          SectionHeader(
            title: 'Traders sharing this container',
            subtitle: 'Who owes what',
            trailing: (canManage && !d.isCancelled)
                ? TextButton.icon(
                    onPressed: _busy ? null : _addTrader,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Add'))
                : null,
          ),
          const SizedBox(height: DesignSpacing.sm),
          for (final p in d.participants) _traderTile(d, p, canPay, secondary),
        ],
      ),
    );
  }

  Widget _statusActions(ImportDetail d, bool canReceive) {
    final next = switch (d.status) {
      'PLANNED' => ('IN_TRANSIT', 'Mark as on the way', Icons.directions_boat_outlined),
      'IN_TRANSIT' => ('ARRIVED', 'Mark as arrived', Icons.inventory_outlined),
      _ => null,
    };
    return Column(
      children: [
        if (next != null)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => _api.updateImport(d.id, {'status': next.$1}),
                      done: 'Updated'),
              icon: Icon(next.$3),
              label: Text(next.$2),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
            ),
          ),
        if (canReceive && (d.status == 'IN_TRANSIT' || d.status == 'ARRIVED')) ...[
          const SizedBox(height: DesignSpacing.sm),
          GradientButton(
            label: 'Receive into stock',
            icon: Icons.move_to_inbox_rounded,
            isLoading: _busy,
            onPressed: _busy ? null : () => _receive(d),
          ),
        ],
      ],
    );
  }

  Widget _itemTile(ImportDetail d, ImportItemRow i, bool editable, Color secondary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: ListCard(
        leading: Icon(
          i.productId == null ? Icons.link_off_rounded : Icons.inventory_2_outlined,
          color: i.productId == null ? DesignColors.warning : null,
        ),
        title: i.description,
        subtitle:
            '${kitNumber(i.quantity)} ${i.unit} × ${d.currency} ${kitNumber(i.unitCost)}'
            '${d.participants.length > 1 ? ' · ${d.participantName(i.participantId)}' : ''}'
            '${i.productId == null && d.participantName(i.participantId) == 'You' ? '\nNot linked to a product' : ''}',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(kesWhole(i.landedUnitCostKes),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: DesignColors.accent)),
                Text('each, landed',
                    style: TextStyle(color: secondary, fontSize: 11)),
              ],
            ),
            if (editable)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: _busy
                    ? null
                    : () => _confirmDelete(
                        i.description, () => _api.removeImportItem(d.id, i.id)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _traderTile(
      ImportDetail d, ImportParticipantRow p, bool canPay, Color secondary) {
    final (label, color) = switch (p.status) {
      'SETTLED' => ('Paid up', DesignColors.success),
      'PART_PAID' => ('Part paid', DesignColors.warning),
      'OVERPAID' => ('Overpaid', DesignColors.info),
      _ => ('Owes', DesignColors.error),
    };
    final payments = d.payments.where((x) => x.participantId == p.id).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(DesignSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.isSelf ? '${p.name} (you)' : p.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                StatusBadge(label: label, color: color),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Goods ${kesWhole(p.owesKes - _costShare(d, p))} + costs ${kesWhole(_costShare(d, p))} = ${kesWhole(p.owesKes)}',
              style: TextStyle(color: secondary, fontSize: 12),
            ),
            Text(
              p.balanceKes > 0.5
                  ? 'Paid ${kesWhole(p.paidKes)} · Still owes ${kesWhole(p.balanceKes)}'
                  : 'Paid ${kesWhole(p.paidKes)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final pay in payments)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${timeAgo(pay.paidAt)} · ${kesWhole(pay.amountKes)}${pay.method != null ? ' · ${pay.method}' : ''}${pay.reference != null ? ' · ${pay.reference}' : ''}',
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ),
                    if (canPay)
                      InkWell(
                        onTap: _busy
                            ? null
                            : () => _confirmDelete('this payment',
                                () => _api.removeImportPayment(d.id, pay.id)),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            if (canPay && !d.isCancelled && p.balanceKes > 0.5) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _recordPayment(d, p),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Record payment'),
                ),
              ),
            ],
            if (!p.isSelf && d.isOpen && (payments.isEmpty))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _confirmDelete(p.name,
                          () => _api.removeImportParticipant(d.id, p.id)),
                  child: const Text('Remove'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// This trader's share of the container's costs, from the server's split.
  double _costShare(ImportDetail d, ImportParticipantRow p) => d.items
      .where((i) => i.participantId == p.id)
      .fold<double>(0, (sum, i) => sum + i.allocatedCostKes);

  // ---------------------------------------------------------------- actions

  Future<void> _addItem(ImportDetail d) async {
    final body = await _sheet<Map<String, dynamic>>(_AddItemSheet(detail: d));
    if (body == null) return;
    await _run(() => _api.addImportItem(d.id, body), done: 'Added');
  }

  Future<void> _addCost(ImportDetail d) async {
    final body = await _sheet<Map<String, dynamic>>(const _AddCostSheet());
    if (body == null) return;
    await _run(() => _api.addImportCost(d.id, body), done: 'Cost added');
  }

  Future<void> _addTrader() async {
    final body = await _sheet<Map<String, dynamic>>(const _AddTraderSheet());
    if (body == null) return;
    await _run(() => _api.addImportParticipant(widget.importId, body),
        done: 'Trader added');
  }

  Future<void> _recordPayment(ImportDetail d, ImportParticipantRow p) async {
    final body = await _sheet<Map<String, dynamic>>(_PaymentSheet(
      name: p.isSelf ? 'your share' : p.name,
      suggested: p.balanceKes,
    ));
    if (body == null) return;
    await _run(
        () => _api.recordImportPayment(d.id, {...body, 'participantId': p.id}),
        done: 'Payment recorded');
  }

  Future<void> _receive(ImportDetail d) async {
    final mine = d.items.where((i) => d.participantName(i.participantId) == 'You').toList();
    final result = await _sheet<List<Map<String, dynamic>>>(_ReceiveSheet(items: mine));
    if (result == null) return;
    final ok = await _run(() => _api.receiveImport(d.id, items: result));
    if (ok && mounted) {
      showGlassSnackBar(
          context, 'Booked into stock at landed cost. Check Shop Alerts for any price to review.',
          icon: Icons.check_circle_rounded, color: DesignColors.success);
    }
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.detail});

  final ImportDetail detail;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return GlassCard(
      padding: const EdgeInsets.all(DesignSpacing.lg),
      borderRadius: DesignSpacing.radiusXl,
      blur: 8,
      tint: DesignColors.accent.withValues(alpha: 0.08),
      borderColor: DesignColors.accent.withValues(alpha: 0.15),
      child: Column(
        children: [
          Text('It really costs you',
              style: TextStyle(color: secondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(kesWhole(detail.landedKes),
              style: DesignType.numeric(
                color: isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: DesignSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Goods ${kesWhole(detail.goodsKes)}',
                  style: TextStyle(color: secondary, fontSize: 12)),
              Text('Costs ${kesWhole(detail.costsKes)}',
                  style: TextStyle(color: secondary, fontSize: 12)),
            ],
          ),
          if (detail.costsKes > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Costs add ${detail.upliftPercent.toStringAsFixed(0)}% to the price you paid the supplier',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: DesignColors.accent, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- sheets

Widget _sheetFrame(BuildContext context, String title, List<Widget> children) {
  return Padding(
    padding: EdgeInsets.fromLTRB(DesignSpacing.lg, 0, DesignSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + DesignSpacing.lg),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: DesignSpacing.md),
          ...children,
        ],
      ),
    ),
  );
}

final _decimal = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

class _AddItemSheet extends StatefulWidget {
  const _AddItemSheet({required this.detail});

  final ImportDetail detail;

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final _description = TextEditingController();
  final _qty = TextEditingController();
  final _unitCost = TextEditingController();
  final _unit = TextEditingController(text: 'piece');
  final _cbm = TextEditingController();
  String? _productId;
  String? _participantId;
  String? _error;

  @override
  void dispose() {
    for (final c in [_description, _qty, _unitCost, _unit, _cbm]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total =>
      (double.tryParse(_qty.text) ?? 0) * (double.tryParse(_unitCost.text) ?? 0);

  Future<void> _pickProduct() async {
    final picked = await showProductPicker(context);
    if (picked == null) return;
    setState(() {
      _productId = '${picked['id']}';
      if (_description.text.trim().isEmpty) {
        _description.text = '${picked['name'] ?? ''}';
      }
    });
  }

  void _save() {
    final qty = double.tryParse(_qty.text);
    final cost = double.tryParse(_unitCost.text);
    if (_description.text.trim().isEmpty) {
      setState(() => _error = 'What are these goods?');
      return;
    }
    if (qty == null || qty <= 0) {
      setState(() => _error = 'How many?');
      return;
    }
    if (cost == null || cost < 0) {
      setState(() => _error = 'What does the supplier charge for one?');
      return;
    }
    Navigator.of(context).pop({
      'description': _description.text.trim(),
      'quantity': qty,
      'unitCost': cost,
      'unit': _unit.text.trim().isEmpty ? 'piece' : _unit.text.trim(),
      if (_productId != null) 'productId': _productId,
      if (_participantId != null) 'participantId': _participantId,
      if (double.tryParse(_cbm.text) != null) 'cbm': double.parse(_cbm.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    return _sheetFrame(context, 'Add goods', [
      TextField(
        controller: _description,
        textCapitalization: TextCapitalization.sentences,
        decoration: kitFieldDecoration(context,
            label: 'What is it?', hint: 'e.g. Steel sufuria set (3pc)'),
      ),
      const SizedBox(height: DesignSpacing.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _pickProduct,
          icon: Icon(_productId == null ? Icons.link_rounded : Icons.check_circle_rounded),
          label: Text(_productId == null
              ? 'Link to a product in my shop'
              : 'Linked to a product'),
        ),
      ),
      const SizedBox(height: DesignSpacing.sm),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_decimal],
              onChanged: (_) => setState(() {}),
              decoration: kitFieldDecoration(context, label: 'How many'),
            ),
          ),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: TextField(
              controller: _unit,
              decoration: kitFieldDecoration(context, label: 'Unit'),
            ),
          ),
        ],
      ),
      const SizedBox(height: DesignSpacing.md),
      TextField(
        controller: _unitCost,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_decimal],
        onChanged: (_) => setState(() {}),
        decoration: kitFieldDecoration(context,
            label: 'Supplier price for one',
            prefixText: '${d.currency} ',
            helper: _total > 0
                ? 'Line total ${d.currency} ${kitNumber(_total)} = ${kesWhole(_total * d.fxRate)}'
                : null),
      ),
      const SizedBox(height: DesignSpacing.md),
      TextField(
        controller: _cbm,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_decimal],
        decoration: kitFieldDecoration(context,
            label: 'Space it takes (optional)',
            suffixText: 'CBM',
            helper: 'Only needed if you split costs by space.'),
      ),
      if (d.participants.length > 1) ...[
        const SizedBox(height: DesignSpacing.md),
        const FormLabel('Whose goods are these?'),
        Wrap(
          spacing: DesignSpacing.sm,
          runSpacing: DesignSpacing.sm,
          children: [
            for (final p in d.participants)
              ChoicePill(
                label: p.isSelf ? 'Mine' : p.name,
                selected: (_participantId ?? d.self?.id) == p.id,
                onTap: () => setState(() => _participantId = p.id),
              ),
          ],
        ),
      ],
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: DesignSpacing.sm),
          child: Text(_error!, style: const TextStyle(color: DesignColors.error)),
        ),
      const SizedBox(height: DesignSpacing.lg),
      GradientButton(label: 'Add goods', icon: Icons.add_rounded, onPressed: _save),
    ]);
  }
}

class _AddCostSheet extends StatefulWidget {
  const _AddCostSheet();

  @override
  State<_AddCostSheet> createState() => _AddCostSheetState();
}

class _AddCostSheetState extends State<_AddCostSheet> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String _type = 'FREIGHT';
  String _currency = 'KES';
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _save() {
    final amount = double.tryParse(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'How much was it?');
      return;
    }
    Navigator.of(context).pop({
      'type': _type,
      'amount': amount,
      'currency': _currency,
      if (_reference.text.trim().isNotEmpty) 'reference': _reference.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return _sheetFrame(context, 'Add a cost', [
      const FormLabel('What was it for?'),
      Wrap(
        spacing: DesignSpacing.sm,
        runSpacing: DesignSpacing.sm,
        children: [
          for (final e in importCostTypes.entries)
            ChoicePill(
              label: e.value,
              selected: _type == e.key,
              onTap: () => setState(() => _type = e.key),
            ),
        ],
      ),
      const SizedBox(height: DesignSpacing.md),
      TextField(
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_decimal],
        decoration: kitFieldDecoration(context, label: 'Amount', prefixText: '$_currency '),
      ),
      const SizedBox(height: DesignSpacing.sm),
      Wrap(
        spacing: DesignSpacing.sm,
        children: [
          for (final c in const ['KES', 'USD', 'CNY'])
            ChoicePill(
              label: c,
              selected: _currency == c,
              onTap: () => setState(() => _currency = c),
            ),
        ],
      ),
      const SizedBox(height: DesignSpacing.md),
      TextField(
        controller: _reference,
        decoration: kitFieldDecoration(context,
            label: 'Receipt / M-Pesa code (optional)'),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: DesignSpacing.sm),
          child: Text(_error!, style: const TextStyle(color: DesignColors.error)),
        ),
      const SizedBox(height: DesignSpacing.lg),
      GradientButton(label: 'Add cost', icon: Icons.add_rounded, onPressed: _save),
    ]);
  }
}

class _AddTraderSheet extends StatefulWidget {
  const _AddTraderSheet();

  @override
  State<_AddTraderSheet> createState() => _AddTraderSheetState();
}

class _AddTraderSheetState extends State<_AddTraderSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter their name.');
      return;
    }
    Navigator.of(context).pop({
      'name': _name.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return _sheetFrame(context, 'Add a trader', [
      Text('Someone sharing this container. Their goods and their share of the costs are tracked separately.',
          style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary)),
      const SizedBox(height: DesignSpacing.md),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: kitFieldDecoration(context, label: 'Name', hint: 'e.g. Mama Wanjiru'),
      ),
      const SizedBox(height: DesignSpacing.md),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: kitFieldDecoration(context, label: 'Phone (optional)'),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: DesignSpacing.sm),
          child: Text(_error!, style: const TextStyle(color: DesignColors.error)),
        ),
      const SizedBox(height: DesignSpacing.lg),
      GradientButton(label: 'Add trader', icon: Icons.person_add_alt_1_rounded, onPressed: _save),
    ]);
  }
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.name, required this.suggested});

  final String name;
  final double suggested;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final TextEditingController _amount =
      TextEditingController(text: kitNumber(widget.suggested.roundToDouble()));
  final _reference = TextEditingController();
  String _method = 'MPESA';
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _save() {
    final amount = double.tryParse(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount received.');
      return;
    }
    Navigator.of(context).pop({
      'amountKes': amount,
      'method': _method,
      if (_reference.text.trim().isNotEmpty) 'reference': _reference.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return _sheetFrame(context, 'Payment from ${widget.name}', [
      TextField(
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_decimal],
        decoration: kitFieldDecoration(context, label: 'Amount received', prefixText: 'KES '),
      ),
      const SizedBox(height: DesignSpacing.md),
      Wrap(
        spacing: DesignSpacing.sm,
        children: [
          for (final m in const ['MPESA', 'CASH', 'BANK'])
            ChoicePill(
              label: m == 'MPESA' ? 'M-Pesa' : (m == 'CASH' ? 'Cash' : 'Bank'),
              selected: _method == m,
              onTap: () => setState(() => _method = m),
            ),
        ],
      ),
      const SizedBox(height: DesignSpacing.md),
      TextField(
        controller: _reference,
        textCapitalization: TextCapitalization.characters,
        decoration: kitFieldDecoration(context, label: 'M-Pesa code / reference (optional)'),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: DesignSpacing.sm),
          child: Text(_error!, style: const TextStyle(color: DesignColors.error)),
        ),
      const SizedBox(height: DesignSpacing.lg),
      GradientButton(label: 'Record payment', icon: Icons.check_rounded, onPressed: _save),
    ]);
  }
}

class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet({required this.items});

  final List<ImportItemRow> items;

  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  late final Map<String, TextEditingController> _qty = {
    for (final i in widget.items) i.id: TextEditingController(text: kitNumber(i.quantity)),
  };

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unlinked = widget.items.where((i) => i.productId == null).length;
    return _sheetFrame(context, 'What actually arrived?', [
      Text(
          'Change any count that came short. The cost of the whole line is carried by the units that did arrive.',
          style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary)),
      const SizedBox(height: DesignSpacing.md),
      if (widget.items.isEmpty)
        const Text('None of the goods in this container are yours.')
      else
        for (final i in widget.items)
          Padding(
            padding: const EdgeInsets.only(bottom: DesignSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.description,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('Ordered ${kitNumber(i.quantity)} ${i.unit}'
                          '${i.productId == null ? ' · not linked, will be skipped' : ''}',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _qty[i.id],
                    textAlign: TextAlign.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_decimal],
                    decoration: kitFieldDecoration(context, label: 'Arrived'),
                  ),
                ),
              ],
            ),
          ),
      if (unlinked > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
          child: Text(
            '$unlinked line${unlinked == 1 ? ' is' : 's are'} not linked to a product, so ${unlinked == 1 ? 'it' : 'they'} will not be added to stock.',
            style: const TextStyle(color: DesignColors.warning, fontSize: 12),
          ),
        ),
      GradientButton(
        label: 'Add to stock',
        icon: Icons.move_to_inbox_rounded,
        onPressed: () {
          Navigator.of(context).pop([
            for (final i in widget.items)
              {
                'itemId': i.id,
                'receivedQty': double.tryParse(_qty[i.id]!.text) ?? i.quantity,
              },
          ]);
        },
      ),
    ]);
  }
}
