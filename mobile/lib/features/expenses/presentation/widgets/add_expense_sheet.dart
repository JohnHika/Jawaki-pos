import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../domain/expenses.dart';

typedef NewExpense = ({
  double amount,
  String category,
  String method,
  String? note,
});

/// Asks what was paid, what for and how. Returns null if closed.
Future<NewExpense?> showAddExpenseSheet(BuildContext context) {
  return showModalBottomSheet<NewExpense>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: SignInPalette.of(context).page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _AddExpenseSheet(),
  );
}

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet();

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _category;
  String _method = 'CASH';
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    final note = _note.text.trim();
    final String? problem;
    if (amount == null || amount <= 0) {
      problem = 'Enter how much was paid.';
    } else if (_category == null) {
      problem = 'Choose what the money was for.';
    } else if (_category == 'Other' && note.isEmpty) {
      problem = 'Say what it was for in the note.';
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop<NewExpense>((
      amount: amount!,
      category: _category!,
      method: _method,
      note: note.isEmpty ? null : note,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Add expense',
                    style: DesignType.display.copyWith(
                      color: palette.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: palette.soft),
                ),
              ],
            ),
            Text(
              'Rent, transport, wages and the like. Stock you buy goes under Receive stock.',
              style: TextStyle(color: palette.soft, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(12),
              ],
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              style: DesignType.numeric(fontSize: 18, color: palette.ink),
              decoration: kitFieldDecoration(context,
                  label: 'Amount paid', prefixText: 'KES ', hint: '0'),
            ),
            const SizedBox(height: 18),
            const FormLabel('What for'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in kExpenseCategories)
                  ChoicePill(
                    label: item.label,
                    icon: item.icon,
                    selected: _category == item.label,
                    onTap: () => setState(() {
                      _category = item.label;
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const FormLabel('Paid with'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in kExpenseMethods)
                  ChoicePill(
                    label: method.label,
                    selected: _method == method.code,
                    onTap: () => setState(() => _method = method.code),
                  ),
              ],
            ),
            if (_method == 'CASH') ...[
              const SizedBox(height: 8),
              Text(
                'End of day takes this off the cash that should be in the till.',
                style:
                    TextStyle(color: palette.faint, fontSize: 12, height: 1.4),
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: kitFieldDecoration(
                context,
                label: _category == 'Other' ? 'Note' : 'Note (optional)',
                hint: 'For example, boda to the wholesaler',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              SignInError(message: _error!),
            ],
            const SizedBox(height: 12),
            SignInButton(label: 'Save expense', onPressed: _save),
          ],
        ),
      ),
    );
  }
}
