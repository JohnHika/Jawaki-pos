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
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF0B0A0F),
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
    child: Theme(
      data: AcaTheme.darkTheme.copyWith(
        textTheme: AcaTheme.darkTheme.textTheme.apply(
          fontFamily: 'PlusJakartaSans',
        ),
        primaryTextTheme: AcaTheme.darkTheme.primaryTextTheme.apply(
          fontFamily: 'PlusJakartaSans',
        ),
      ),
      child: Builder(
        builder: (context) {
          final p = context.aca;
          final notice = context.select<SessionController, String?>(
            (s) => s.notice,
          );
          return Scaffold(
            backgroundColor: p.bg,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _BrandHeader(),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                            decoration: BoxDecoration(
                              color: p.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: p.border),
                            ),
                            child: Form(
                              key: _form,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.admin_panel_settings_outlined,
                                        size: 17,
                                        color: p.brand,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'PLATFORM STAFF',
                                        style: TextStyle(
                                          color: p.brand,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.05,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _needsOtp ? 'Verify sign-in' : 'Sign in',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontFamily: 'Sora',
                                          color: p.text,
                                          fontSize: 22,
                                          letterSpacing: -0.3,
                                        ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _needsOtp
                                        ? 'Enter your authenticator code to continue.'
                                        : 'Use your assigned work email and password.',
                                    style: TextStyle(
                                      color: p.textMuted,
                                      height: 1.4,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
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
                                    const SizedBox(height: 13),
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
                                    TextFormField(
                                      controller: _otp,
                                      focusNode: _otpFocus,
                                      enabled: !_busy,
                                      keyboardType:
                                          TextInputType.visiblePassword,
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
                                        letterSpacing: 5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'Verification code',
                                        hintText: '123456',
                                      ),
                                      onFieldSubmitted: (_) => _submit(),
                                      validator: (v) =>
                                          (v == null || v.trim().length < 6)
                                          ? 'Enter your code'
                                          : null,
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  SizedBox(
                                    height: 54,
                                    child: FilledButton(
                                      onPressed: _busy ? null : _submit,
                                      child: _busy
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
                                          : Text(
                                              _needsOtp
                                                  ? 'Verify and sign in'
                                                  : 'Continue',
                                            ),
                                    ),
                                  ),
                                  if (_needsOtp)
                                    Center(
                                      child: TextButton(
                                        onPressed: _busy
                                            ? null
                                            : _backToPassword,
                                        child: const Text(
                                          'Use a different account',
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 17),
                          const _ServerFootnote(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Row(
      children: [
        const AcaMark(size: 54),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Counterbase',
                style: TextStyle(
                  fontFamily: 'Sora',
                  color: p.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PLATFORM ADMIN',
                style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  color: p.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
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
  const _ServerFootnote();

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final prod = AcaConfig.isProduction;
    final tone = prod ? p.success : p.warning;
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 7,
          runSpacing: 3,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
            Text(
              prod ? 'LIVE COUNTERBASE' : 'QA BUILD · LOCAL API',
              style: TextStyle(
                color: tone,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Authorized staff only · Activity is recorded',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.textFaint, fontSize: 11.5, height: 1.35),
        ),
      ],
    );
  }
}
