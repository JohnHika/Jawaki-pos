import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/widgets/brand.dart';
import '../../data/api_client.dart';
import '../../data/repository.dart';
import '../../state/session.dart';

/// Blocks the whole app until a staff member replaces their temporary password.
/// The server enforces this too (every other route answers PASSWORD_CHANGE_REQUIRED).
class ForcePasswordChangeScreen extends StatefulWidget {
  const ForcePasswordChangeScreen({super.key});

  @override
  State<ForcePasswordChangeScreen> createState() => _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<ForcePasswordChangeScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  static String? policyError(String v) {
    if (v.length < 12) return 'Use at least 12 characters';
    if (!RegExp(r'[a-z]').hasMatch(v)) return 'Add a lower-case letter';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Add an upper-case letter';
    if (!RegExp(r'\d').hasMatch(v)) return 'Add a number';
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(v)) return 'Add a symbol (e.g. ! @ # %)';
    return null;
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final repo = context.read<AcaRepository>();
    final session = context.read<SessionController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.changePassword(currentPassword: _current.text, newPassword: _next.text);
      await session.reloadProfile();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final me = context.watch<SessionController>().me;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AcaMark(size: 56)),
                    const SizedBox(height: 22),
                    Text('Set your own password',
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      '${me?.name ?? 'Welcome'}, you signed in with a temporary password. Choose a new one before you continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: p.toneFill(Tone.danger), borderRadius: BorderRadius.circular(12)),
                        child: Text(_error!, style: TextStyle(color: p.danger, fontWeight: FontWeight.w600)),
                      ),
                    TextFormField(
                      controller: _current,
                      obscureText: _obscure,
                      enabled: !_busy,
                      decoration: const InputDecoration(labelText: 'Temporary password'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Enter the temporary password' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _next,
                      obscureText: _obscure,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        helperText: '12+ characters with upper, lower, number and symbol',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => policyError(v ?? ''),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _obscure,
                      enabled: !_busy,
                      decoration: const InputDecoration(labelText: 'Confirm new password'),
                      onFieldSubmitted: (_) => _save(),
                      validator: (v) => v != _next.text ? 'Passwords don\'t match' : null,
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Theme.of(context).colorScheme.onPrimary))
                          : const Text('Save and continue'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => context.read<SessionController>().signOut(),
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
