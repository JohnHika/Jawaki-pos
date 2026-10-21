import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/repository.dart';
import 'account_logic.dart';
import 'sheet_kit.dart';

/// Opens the change-password sheet. Resolves to true when the password was changed.
Future<bool?> showChangePasswordSheet(BuildContext context) =>
    showFormSheet<bool>(context, builder: (_) => const _ChangePasswordSheet());

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? get _problem => changePasswordProblem(current: _current.text, next: _next.text, confirm: _confirm.text);

  Future<void> _submit() async {
    if (_problem != null || _busy) return;
    final repo = context.read<AcaRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.changePassword(currentPassword: _current.text, newPassword: _next.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  InputDecoration _decoration(String label, {String? helper}) => InputDecoration(
        labelText: label,
        helperText: helper,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show passwords' : 'Hide passwords',
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final rules = PasswordPolicy.evaluate(_next.text);
    final mismatch = _confirm.text.isNotEmpty && _confirm.text != _next.text;
    final same = _next.text.isNotEmpty && _next.text == _current.text;
    return PopScope(
      canPop: !_busy,
      child: SheetBody(
        title: 'Change password',
        message: 'You will stay signed in here. Every other device is signed out.',
        children: [
          if (_error != null) ...[InlineError(_error!), const SizedBox(height: 14)],
          TextField(
            controller: _current,
            obscureText: _obscure,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: _decoration('Current password'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _next,
            obscureText: _obscure,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.newPassword],
            inputFormatters: [LengthLimitingTextInputFormatter(PasswordPolicy.maxLength)],
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: _decoration('New password'),
          ),
          const SizedBox(height: 10),
          PolicyChecklist(rules: rules),
          if (same) ...[
            const SizedBox(height: 6),
            Text('Choose a password different from the current one.', style: TextStyle(color: p.danger, fontSize: 12.5)),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _confirm,
            obscureText: _obscure,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: _decoration('Confirm new password').copyWith(errorText: mismatch ? 'The passwords do not match' : null),
          ),
          const SizedBox(height: 18),
          SubmitButton(label: 'Change password', busy: _busy, onPressed: _problem == null ? _submit : null),
        ],
      ),
    );
  }
}

/// Live list of password rules; each turns green once met.
class PolicyChecklist extends StatelessWidget {
  const PolicyChecklist({super.key, required this.rules});
  final List<PasswordRule> rules;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Column(
      children: [
        for (final r in rules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  r.met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: r.met ? p.success : p.textFaint,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: r.met ? p.success : p.textMuted,
                      fontWeight: r.met ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
