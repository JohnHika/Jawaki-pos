import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/repository.dart';
import 'account_logic.dart';
import 'sheet_kit.dart';

/// Opens the "turn off two-step verification" sheet. Resolves to true when it was turned off.
Future<bool?> showDisableTwoFactorSheet(BuildContext context) =>
    showFormSheet<bool>(context, builder: (_) => const _DisableTwoFactorSheet());

class _DisableTwoFactorSheet extends StatefulWidget {
  const _DisableTwoFactorSheet();

  @override
  State<_DisableTwoFactorSheet> createState() => _DisableTwoFactorSheetState();
}

class _DisableTwoFactorSheetState extends State<_DisableTwoFactorSheet> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _ready => _password.text.isNotEmpty && looksLikeSecondFactor(_code.text);

  Future<void> _submit() async {
    if (!_ready || _busy) return;
    final repo = context.read<AcaRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.disableTwoFactor(password: _password.text, code: _code.text.trim());
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

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return PopScope(
      canPop: !_busy,
      child: SheetBody(
        title: 'Turn off two-step verification?',
        children: [
          const NoticeBox(
            'Without the second step, anyone who learns your password can sign in as you. '
            'Your backup codes stop working too.',
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[InlineError(_error!), const SizedBox(height: 14)],
          TextField(
            controller: _password,
            obscureText: _obscure,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Your password',
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 20,
            textCapitalization: TextCapitalization.characters,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]'))],
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Authenticator or backup code',
              counterText: '',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use the 6-digit code from your authenticator app, or one of your backup codes.',
            style: TextStyle(color: p.textMuted, fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 18),
          SubmitButton(
            label: 'Turn off',
            destructive: true,
            busy: _busy,
            onPressed: _ready ? _submit : null,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Keep it on'),
          ),
        ],
      ),
    );
  }
}
