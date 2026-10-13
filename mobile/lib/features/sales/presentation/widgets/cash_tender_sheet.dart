import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/design_system.dart';
import '../../domain/cash_tender.dart';

/// Asks the cashier how much cash the customer handed over and shows the change
/// to give back. Resolves to the amount received, or null if cancelled.
Future<double?> showCashTenderSheet(BuildContext context, {required double total}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CashTenderSheet(total: total),
  );
}

class _CashTenderSheet extends StatefulWidget {
  const _CashTenderSheet({required this.total});

  final double total;

  @override
  State<_CashTenderSheet> createState() => _CashTenderSheetState();
}

class _CashTenderSheetState extends State<_CashTenderSheet> {
  static final _money = NumberFormat('#,##0.##');
  final TextEditingController _controller = TextEditingController();

  double get _tendered => double.tryParse(_controller.text.trim()) ?? 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setAmount(double amount) {
    setState(() {
      _controller.text = _money.format(amount).replaceAll(',', '');
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    final total = widget.total;
    final enough = coversTotal(total: total, tendered: _tendered);
    final change = cashChange(total: total, tendered: _tendered);
    final short = cashShortfall(total: total, tendered: _tendered);
    final typed = _controller.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        DesignSpacing.lg,
        0,
        DesignSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + DesignSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cash received',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: DesignSpacing.xs),
            Text('Total due  KES ${_money.format(total)}',
                key: const ValueKey('cash-total'),
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: secondary)),
            const SizedBox(height: DesignSpacing.sm),
            Wrap(
              spacing: DesignSpacing.sm,
              runSpacing: DesignSpacing.sm,
              children: [
                for (final amount in suggestedTenders(total))
                  ActionChip(
                    key: ValueKey('cash-chip-${amount.toStringAsFixed(0)}'),
                    label: Text(amount == total
                        ? 'Exact  ${_money.format(amount)}'
                        : _money.format(amount)),
                    onPressed: () => _setAmount(amount),
                  ),
              ],
            ),
            const SizedBox(height: DesignSpacing.sm),
            TextField(
              key: const ValueKey('cash-input'),
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              // The keyboard's check key finishes the sale once enough is given,
              // so a cashier can type the amount and confirm without the keyboard
              // ever covering the button.
              onSubmitted: (_) {
                if (enough) Navigator.of(context).pop(_tendered);
              },
              decoration: const InputDecoration(
                labelText: 'Amount received (KES)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: DesignSpacing.sm),
            AnimatedContainer(
              duration: DesignAnimation.fast,
              padding: const EdgeInsets.symmetric(
                  horizontal: DesignSpacing.lg, vertical: DesignSpacing.md),
              decoration: BoxDecoration(
                color: (enough
                        ? DesignColors.success
                        : typed
                            ? DesignColors.error
                            : DesignColors.accent)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    !typed
                        ? 'Change to give'
                        : enough
                            ? 'Change to give'
                            : 'Still to pay',
                    style: TextStyle(
                        color: secondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    !typed
                        ? 'KES —'
                        : 'KES ${_money.format(enough ? change : short)}',
                    key: const ValueKey('cash-result'),
                    style: DesignType.numeric(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: enough
                          ? DesignColors.success
                          : typed
                              ? DesignColors.error
                              : primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignSpacing.md),
            SizedBox(
              height: DesignSpacing.huge,
              child: FilledButton(
                key: const ValueKey('cash-confirm'),
                onPressed:
                    enough ? () => Navigator.of(context).pop(_tendered) : null,
                child: const Text('Complete sale'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
