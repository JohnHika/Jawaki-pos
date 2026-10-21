import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import 'billing_logic.dart';
import 'sheet_parts.dart';

/// Result of the "mark as paid" sheet. [mpesaCode] is null when the user left
/// the optional field blank.
class MarkPaidChoice {
  const MarkPaidChoice({this.mpesaCode});
  final String? mpesaCode;
}

/// Confirmation for reconciling an invoice by hand, with an OPTIONAL M-Pesa
/// code. Returns null when cancelled.
Future<MarkPaidChoice?> showMarkPaidSheet(
  BuildContext context, {
  required String company,
  required num amount,
}) {
  return showModalBottomSheet<MarkPaidChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MarkPaidSheet(company: company, amount: amount),
  );
}

class _MarkPaidSheet extends StatefulWidget {
  const _MarkPaidSheet({required this.company, required this.amount});

  final String company;
  final num amount;

  @override
  State<_MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends State<_MarkPaidSheet> {
  final TextEditingController _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final error = mpesaCodeError(_code.text);
    final hasCode = normalizeMpesaCode(_code.text) != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mark invoice as paid', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '${widget.company} · ${Fmt.kes(widget.amount)}',
              style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofocus: false,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 15,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'M-Pesa code (optional)',
                errorText: error,
                helperText: 'Copy it from the M-Pesa confirmation message',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            HelpBanner(
              hasCode
                  ? 'Recorded as M-Pesa (manual) with this code. The company is reactivated if it was past due or suspended, and moved onto this invoice\'s period if that is newer.'
                  : 'Without a code the invoice is only marked paid: the payment method stays as it was and the company\'s status does not change. '
                      'If this invoice covers a newer period than the company has, the company is moved onto it and reactivated. Add the M-Pesa code to also reactivate a past due or suspended company for an older invoice.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: error == null
                  ? () => Navigator.pop(context, MarkPaidChoice(mpesaCode: normalizeMpesaCode(_code.text)))
                  : null,
              child: const Text('Mark as paid'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}
