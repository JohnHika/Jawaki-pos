import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../domain/finance_models.dart';

/// What the owner chose to pay in one go.
typedef SupplierBatch = ({
  List<SupplierBillPayment> payments,
  String fundingSource,
  String? notes,
});

/// Lists every unpaid supplier bill, grouped by supplier, so several
/// suppliers can be paid in one go. [onPay] saves the payments; if it throws,
/// the sheet stays open with the reason. True when the payments were saved.
Future<bool> showPaySuppliersSheet(
  BuildContext context, {
  required List<FinancePayable> payables,
  required Future<void> Function(SupplierBatch batch) onPay,
}) async {
  final paid = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: SignInPalette.of(context).page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    // Lifts above the keyboard so the amount being typed and the Pay
    // button stay in sight.
    builder: (sheetContext) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: PaySuppliersSheet(payables: payables, onPay: onPay),
      ),
    ),
  );
  return paid == true;
}

class PaySuppliersSheet extends StatefulWidget {
  const PaySuppliersSheet({
    super.key,
    required this.payables,
    required this.onPay,
  });

  final List<FinancePayable> payables;
  final Future<void> Function(SupplierBatch batch) onPay;

  @override
  State<PaySuppliersSheet> createState() => _PaySuppliersSheetState();
}

class _PaySuppliersSheetState extends State<PaySuppliersSheet> {
  late final List<_SupplierGroup> _groups = _groupBills(widget.payables);
  final Set<String> _ticked = {};
  final Map<String, TextEditingController> _amounts = {};
  final _note = TextEditingController();
  String _source = 'CASH_TILL';
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final group in _groups) {
      for (final bill in group.bills) {
        _amounts[bill.id] = TextEditingController(
          text: _plainAmount(bill.outstandingAmount),
        )..addListener(_refresh);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _error = null);

  static List<_SupplierGroup> _groupBills(List<FinancePayable> payables) {
    final bySupplier = <String, List<FinancePayable>>{};
    for (final bill in payables) {
      if (bill.outstandingAmount <= 0.005) continue;
      bySupplier.putIfAbsent(bill.supplierId, () => []).add(bill);
    }
    final groups = [
      for (final bills in bySupplier.values)
        _SupplierGroup(
          name: tidySupplierName(bills.first.supplierName),
          bills: bills
            ..sort((a, b) => (a.dueDate ?? a.createdAt ?? DateTime(9999))
                .compareTo(b.dueDate ?? b.createdAt ?? DateTime(9999))),
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return groups;
  }

  static String _plainAmount(double value) {
    final cents = (value * 100).round();
    return cents % 100 == 0
        ? (cents ~/ 100).toString()
        : (cents / 100).toStringAsFixed(2);
  }

  double? _amountOf(String billId) => double.tryParse(
      (_amounts[billId]?.text ?? '').replaceAll(',', '').trim());

  int get _totalCents {
    var cents = 0;
    for (final id in _ticked) {
      final amount = _amountOf(id);
      if (amount != null && amount.isFinite && amount > 0) {
        cents += (amount * 100).round();
      }
    }
    return cents;
  }

  void _toggle(String billId) => setState(() {
        _error = null;
        if (!_ticked.remove(billId)) _ticked.add(billId);
      });

  void _toggleGroup(_SupplierGroup group) => setState(() {
        _error = null;
        final ids = group.bills.map((bill) => bill.id);
        if (ids.every(_ticked.contains)) {
          _ticked.removeAll(ids);
        } else {
          _ticked.addAll(ids);
        }
      });

  Future<void> _pay() async {
    if (_saving) return;
    if (_ticked.isEmpty) {
      setState(() => _error = 'Tick the bills you are paying.');
      return;
    }
    final payments = <SupplierBillPayment>[];
    for (final group in _groups) {
      for (final bill in group.bills) {
        if (!_ticked.contains(bill.id)) continue;
        final amount = _amountOf(bill.id);
        if (amount == null ||
            !amount.isFinite ||
            amount <= 0 ||
            amount > bill.outstandingAmount + 0.005) {
          setState(() => _error = 'Check the amount for ${group.name}: it '
              'must be above zero and no more than '
              '${formatMoney(bill.outstandingAmount, decimals: true)}.');
          return;
        }
        payments.add((invoiceId: bill.id, amount: amount));
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onPay((
        payments: payments,
        fundingSource: _source,
        notes: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Nothing was paid. ${apiErrorMessage(error)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final count = _ticked.length;
    final total = _totalCents / 100;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Pay suppliers',
                        style: DesignType.display.copyWith(
                            color: palette.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded, color: palette.soft),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Tick each bill you are paying today. Change an amount to pay '
                'part of a bill. Record money you have already sent; the app '
                'does not send it.',
                style: TextStyle(
                    color: palette.soft, fontSize: 14.5, height: 1.45),
              ),
              const SizedBox(height: 18),
              Text('PAID FROM',
                  style: TextStyle(
                      color: palette.faint,
                      fontSize: 11.5,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoicePill(
                    label: 'Cash from the till',
                    selected: _source == 'CASH_TILL',
                    onTap: () => setState(() => _source = 'CASH_TILL'),
                  ),
                  ChoicePill(
                    label: 'Bank or M-Pesa',
                    selected: _source == 'BANK_OR_MPESA',
                    onTap: () => setState(() => _source = 'BANK_OR_MPESA'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _source == 'CASH_TILL'
                    ? 'Comes off the cash expected in the till at End of day.'
                    : 'Add the M-Pesa code or bank reference below.',
                style: TextStyle(color: palette.soft, fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (_groups.isEmpty)
                Text('No supplier bills are waiting to be paid.',
                    style: TextStyle(color: palette.soft))
              else
                for (final group in _groups) ...[
                  _GroupCard(
                    group: group,
                    ticked: _ticked,
                    amounts: _amounts,
                    enabled: !_saving,
                    onToggle: _toggle,
                    onToggleGroup: () => _toggleGroup(group),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 4),
              TextField(
                key: const ValueKey('pay-suppliers-note'),
                controller: _note,
                enabled: !_saving,
                maxLength: 200,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: _source == 'CASH_TILL'
                      ? 'Note (optional)'
                      : 'M-Pesa code or bank reference',
                ),
              ),
            ],
          ),
        ),
        PinnedActionBar(
          // Problems show here, beside the button, so they are never
          // below the fold.
          summary: _error != null
              ? Text(_error!,
                  style:
                      const TextStyle(color: DesignColors.error, fontSize: 14))
              : count == 0
                  ? null
                  : Text(
                      '$count ${count == 1 ? 'bill' : 'bills'} from '
                      '${_supplierCount()} '
                      '${_supplierCount() == 1 ? 'supplier' : 'suppliers'}',
                      style: TextStyle(color: palette.soft, fontSize: 13.5),
                    ),
          child: SafeArea(
            top: false,
            child: SignInButton(
              label: count == 0
                  ? 'Tick the bills to pay'
                  : 'Pay ${formatMoney(total, decimals: _totalCents % 100 != 0)}',
              loading: _saving,
              onPressed: count == 0 ? null : _pay,
            ),
          ),
        ),
      ],
    );
  }

  int _supplierCount() => _groups
      .where((group) => group.bills.any((bill) => _ticked.contains(bill.id)))
      .length;
}

class _SupplierGroup {
  const _SupplierGroup({required this.name, required this.bills});

  final String name;
  final List<FinancePayable> bills;

  double get owed =>
      bills.fold<double>(0, (sum, bill) => sum + bill.outstandingAmount);
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.ticked,
    required this.amounts,
    required this.enabled,
    required this.onToggle,
    required this.onToggleGroup,
  });

  final _SupplierGroup group;
  final Set<String> ticked;
  final Map<String, TextEditingController> amounts;
  final bool enabled;
  final ValueChanged<String> onToggle;
  final VoidCallback onToggleGroup;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final allTicked = group.bills.every((bill) => ticked.contains(bill.id));
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.name,
                          style: TextStyle(
                              color: palette.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      Text('Owed ${formatMoney(group.owed)}',
                          style: TextStyle(color: palette.soft, fontSize: 13)),
                    ],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
                  onPressed: enabled ? onToggleGroup : null,
                  child: Text(allTicked ? 'Untick all' : 'Tick all'),
                ),
              ],
            ),
          ),
          for (final bill in group.bills) ...[
            Divider(height: 1, color: palette.line),
            _BillRow(
              bill: bill,
              ticked: ticked.contains(bill.id),
              amount: amounts[bill.id]!,
              enabled: enabled,
              onToggle: () => onToggle(bill.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.bill,
    required this.ticked,
    required this.amount,
    required this.enabled,
    required this.onToggle,
  });

  final FinancePayable bill;
  final bool ticked;
  final TextEditingController amount;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final due = bill.dueDate;
    final details = [
      'Balance ${formatMoney(bill.outstandingAmount)}',
      if (due != null) 'due ${DateFormat('d MMM').format(due.toLocal())}',
    ].join(' · ');
    return InkWell(
      onTap: enabled ? onToggle : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(
          children: [
            Checkbox(
              value: ticked,
              activeColor: DesignColors.accent,
              onChanged: enabled ? (_) => onToggle() : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bill.invoiceNumber ?? 'Supplier bill',
                      style: TextStyle(
                          color: palette.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                  Text(details,
                      style: TextStyle(color: palette.soft, fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 140,
              child: TextField(
                key: ValueKey('pay-amount-${bill.id}'),
                controller: amount,
                enabled: enabled && ticked,
                textAlign: TextAlign.right,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                style: const TextStyle(
                  fontSize: 15,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixText: 'KES ',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
