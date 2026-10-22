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
      final needsOtp = await session.signIn(
        _email.text,
        _password.text,
        otp: _needsOtp ? _otp.text : null,
      );
      if (!mounted) return;
      if (needsOtp) {
        setState(() {
          _needsOtp = true;
          _busy = false;
        });
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _otpFocus.requestFocus(),
        );
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
    final isDark = p.isDark;

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        children: [
          Positioned(
            top: -116,
            right: -96,
            child: IgnorePointer(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      p.brand.withValues(alpha: isDark ? 0.15 : 0.10),
                      p.bg.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BrandHero(isDark: isDark),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                          decoration: BoxDecoration(
                            color: p.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: p.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.22 : 0.07,
                                ),
                                blurRadius: 28,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Form(
                            key: _form,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: p.brand.withValues(alpha: 0.13),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        Icons.admin_panel_settings_rounded,
                                        color: p.brand,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _needsOtp
                                                ? 'Verify your sign-in'
                                                : 'Staff sign-in',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _needsOtp
                                                ? 'Two-step verification'
                                                : 'Authorized team members only',
                                            style: TextStyle(
                                              color: p.textMuted,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 22),
                                if (notice != null && _error == null)
                                  _Banner(text: notice, tone: Tone.info),
                                if (_error != null)
                                  _Banner(text: _error!, tone: Tone.danger),
                                if (!_needsOtp) ...[
                                  TextFormField(
                                    controller: _email,
                                    enabled: !_busy,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [
                                      AutofillHints.username,
                                      AutofillHints.email,
                                    ],
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    decoration: const InputDecoration(
                                      labelText: 'Work email',
                                      prefixIcon: Icon(
                                        Icons.alternate_email_rounded,
                                      ),
                                    ),
                                    onFieldSubmitted: (_) =>
                                        _passwordFocus.requestFocus(),
                                    validator: (v) =>
                                        (v == null || !v.contains('@'))
                                        ? 'Enter your staff email'
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _password,
                                    focusNode: _passwordFocus,
                                    enabled: !_busy,
                                    obscureText: _obscure,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: _obscure
                                            ? 'Show password'
                                            : 'Hide password',
                                        icon: Icon(
                                          _obscure
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                      ),
                                    ),
                                    onFieldSubmitted: (_) => _submit(),
                                    validator: (v) => (v == null || v.isEmpty)
                                        ? 'Enter your password'
                                        : null,
                                  ),
                                ] else ...[
                                  Text(
                                    'Enter the 6-digit code from your authenticator app, or use a backup code.',
                                    style: TextStyle(
                                      color: p.textMuted,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _otp,
                                    focusNode: _otpFocus,
                                    enabled: !_busy,
                                    keyboardType: TextInputType.visiblePassword,
                                    textAlign: TextAlign.center,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    inputFormatters: [
                                      LengthLimitingTextInputFormatter(12),
                                    ],
                                    style: const TextStyle(
                                      fontSize: 24,
                                      letterSpacing: 6,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '123456',
                                      labelText: 'Verification code',
                                    ),
                                    onFieldSubmitted: (_) => _submit(),
                                    validator: (v) =>
                                        (v == null || v.trim().length < 6)
                                        ? 'Enter your code'
                                        : null,
                                  ),
                                ],
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 56,
                                  child: FilledButton.icon(
                                    onPressed: _busy ? null : _submit,
                                    icon: _busy
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onPrimary,
                                            ),
                                          )
                                        : Icon(
                                            _needsOtp
                                                ? Icons.verified_user_rounded
                                                : Icons.arrow_forward_rounded,
                                            size: 19,
                                          ),
                                    label: Text(
                                      _needsOtp
                                          ? 'Verify and continue'
                                          : 'Sign in securely',
                                    ),
                                  ),
                                ),
                                if (_needsOtp)
                                  Center(
                                    child: TextButton(
                                      onPressed: _busy ? null : _backToPassword,
                                      child: const Text(
                                        'Use a different account',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _ServerFootnote(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFF1A1721),
                          Color(0xFF24171A),
                          Color(0xFF16131B),
                        ]
                      : const [
                          Color(0xFF27212B),
                          Color(0xFF39221E),
                          Color(0xFF1A1721),
                        ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -24,
            top: -34,
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFF8A4D).withValues(alpha: 0.16),
                  width: 1.2,
                ),
              ),
            ),
          ),
          Positioned(
            right: 7,
            top: -10,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFF8A4D).withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AcaMark(size: 44),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ACA',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'AXON COUNTERBASE ADMIN',
                            style: TextStyle(
                              color: Color(0xFFB9B1AC),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shield_rounded,
                            size: 13,
                            color: Color(0xFFFF9A62),
                          ),
                          SizedBox(width: 5),
                          Text(
                            'STAFF',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Run Counterbase.\nWith confidence.',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontSize: 25,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Clients, billing and platform security — in one control room.',
                  style: TextStyle(
                    color: Color(0xFFD0C8C2),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
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
          Icon(
            tone == Tone.danger
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            size: 20,
            color: p.toneColor(tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: p.text, height: 1.35)),
          ),
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
    final tone = prod ? p.success : p.warning;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: tone.withValues(alpha: 0.24)),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 7,
            runSpacing: 4,
            children: [
              Icon(
                prod ? Icons.cloud_done_rounded : Icons.science_rounded,
                size: 16,
                color: tone,
              ),
              Text(
                prod ? 'LIVE COUNTERBASE' : 'QA ENVIRONMENT',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w800,
                  color: tone,
                ),
              ),
              if (prod) ...[
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.textFaint,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  'Secure connection',
                  style: TextStyle(fontSize: 11, color: p.textMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Role-based access  ·  Admin actions are audited',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: p.textFaint),
        ),
        const SizedBox(height: 4),
        Text(
          'Need access? Contact your platform owner.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: p.textMuted),
        ),
      ],
    );
  }
}
