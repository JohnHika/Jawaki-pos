import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/widgets/brand.dart';
import '../../data/api_client.dart';
import '../../state/session.dart';

/// Email + password, then the authenticator (or backup) code when the account has 2FA.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  final _passwordFocus = FocusNode();
  final _otpFocus = FocusNode();

  bool _obscure = true;
  bool _needsOtp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    _passwordFocus.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final session = context.read<SessionController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final needsOtp = await session.signIn(_email.text, _password.text, otp: _needsOtp ? _otp.text : null);
      if (!mounted) return;
      if (needsOtp) {
        setState(() {
          _needsOtp = true;
          _busy = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _otpFocus.requestFocus());
      }
      // On success the root gate swaps this screen out.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        if (_needsOtp && e.isUnauthorized) _otp.clear();
      });
    }
  }

  void _backToPassword() => setState(() {
        _needsOtp = false;
        _otp.clear();
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final notice = context.select<SessionController, String?>((s) => s.notice);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AcaLockup()),
                    const SizedBox(height: 36),
                    if (notice != null && _error == null) _Banner(text: notice, tone: Tone.info),
                    if (_error != null) _Banner(text: _error!, tone: Tone.danger),
                    if (!_needsOtp) ...[
                      TextFormField(
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(labelText: 'Staff email', prefixIcon: Icon(Icons.mail_outline_rounded)),
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                        validator: (v) => (v == null || !v.contains('@')) ? 'Enter your staff email' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        enabled: !_busy,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                      ),
                    ] else ...[
                      Text('Two-step verification',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Enter the 6-digit code from your authenticator app, or one of your backup codes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.textMuted, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _otp,
                        focusNode: _otpFocus,
                        enabled: !_busy,
                        keyboardType: TextInputType.visiblePassword,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        enableSuggestions: false,
                        inputFormatters: [LengthLimitingTextInputFormatter(12)],
                        style: const TextStyle(fontSize: 26, letterSpacing: 6, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(hintText: '123456'),
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => (v == null || v.trim().length < 6) ? 'Enter your code' : null,
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Theme.of(context).colorScheme.onPrimary))
                          : Text(_needsOtp ? 'Verify and sign in' : 'Sign in'),
                    ),
                    if (_needsOtp)
                      TextButton(onPressed: _busy ? null : _backToPassword, child: const Text('Use a different account')),
                    const SizedBox(height: 28),
                    _ServerFootnote(),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.tone});
  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.toneFill(tone),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.toneColor(tone).withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(tone == Tone.danger ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              size: 20, color: p.toneColor(tone)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: p.text, height: 1.35))),
        ],
      ),
    );
  }
}

/// Always tells the operator which server they are signing in to.
class _ServerFootnote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final prod = AcaConfig.isProduction;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(prod ? Icons.verified_user_outlined : Icons.science_outlined,
                size: 15, color: prod ? p.textFaint : p.warning),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                prod ? 'Live Counterbase · ${AcaConfig.serverLabel}' : 'QA BUILD · ${AcaConfig.apiBaseUrl}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: prod ? p.textFaint : p.warning, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Staff accounts only. Activity is recorded.',
            style: TextStyle(fontSize: 12, color: p.textFaint)),
      ],
    );
  }
}
