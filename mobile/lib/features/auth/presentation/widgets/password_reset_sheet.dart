import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';

Future<bool?> showPasswordResetSheet(
  BuildContext context, {
  required String email,
  required String companyCode,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PasswordResetSheet(
      email: email,
      companyCode: companyCode,
    ),
  );
}

class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet({
    required this.email,
    required this.companyCode,
  });

  final String email;
  final String companyCode;

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  final _email = TextEditingController();
  final _companyCode = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _codeRequested = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.text = widget.email.trim();
    _companyCode.text = widget.companyCode.trim().toLowerCase();
  }

  @override
  void dispose() {
    _email.dispose();
    _companyCode.dispose();
    _code.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String get _normalizedCode =>
      _companyCode.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

  Future<void> _requestCode() async {
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await getIt<ApiClient>().requestPasswordReset(
        email: _email.text.trim(),
        tenantSlug: _normalizedCode,
      );
      if (!mounted) return;
      setState(() => _codeRequested = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await getIt<ApiClient>().completePasswordReset(
        email: _email.text.trim(),
        tenantSlug: _normalizedCode,
        code: _code.text.trim(),
        newPassword: _password.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = context.themed(DesignColors.darkTextPrimary);
    final secondary = context.themed(DesignColors.darkTextSecondary);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            DesignSpacing.lg,
            DesignSpacing.sm,
            DesignSpacing.lg,
            DesignSpacing.xl,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: DesignColors.accent.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        color: DesignColors.accent,
                      ),
                    ),
                    const SizedBox(width: DesignSpacing.md),
                    Expanded(
                      child: Text(
                        'Reset your password',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignSpacing.sm),
                Text(
                  _codeRequested
                      ? 'If an active account matches, a code will arrive at this email. It expires in 10 minutes.'
                      : 'Enter your company code and sign-in email. We’ll send a one-time code if they match an active account.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: secondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: DesignSpacing.lg),
                TextFormField(
                  controller: _companyCode,
                  enabled: !_codeRequested && !_busy,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Company code',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                  validator: (value) {
                    final code = (value ?? '')
                        .trim()
                        .toLowerCase()
                        .replaceAll(RegExp(r'\s+'), '-');
                    if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(code)) {
                      return 'Enter the company code used on the sign-in screen.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: DesignSpacing.md),
                TextFormField(
                  controller: _email,
                  enabled: !_codeRequested && !_busy,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Sign-in email',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(email)) {
                      return 'Enter a valid email address.';
                    }
                    return null;
                  },
                ),
                if (_codeRequested) ...[
                  const SizedBox(height: DesignSpacing.md),
                  TextFormField(
                    controller: _code,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: const InputDecoration(
                      labelText: '8-digit email code',
                      prefixIcon: Icon(Icons.verified_user_outlined),
                    ),
                    validator: (value) => value?.trim().length == 8
                        ? null
                        : 'Enter the 8-digit code from your email.',
                  ),
                  const SizedBox(height: DesignSpacing.md),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      helperText:
                          'Use 8+ characters with upper, lower and a number.',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip:
                            _showPassword ? 'Hide password' : 'Show password',
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(_showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                      ),
                    ),
                    validator: (value) {
                      final password = value ?? '';
                      if (password.length < 8 ||
                          !RegExp(r'[a-z]').hasMatch(password) ||
                          !RegExp(r'[A-Z]').hasMatch(password) ||
                          !RegExp(r'\d').hasMatch(password)) {
                        return 'Use 8+ characters with an uppercase, lowercase and number.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: DesignSpacing.md),
                  TextFormField(
                    controller: _confirmPassword,
                    enabled: !_busy,
                    obscureText: !_showPassword,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                    validator: (value) => value == _password.text
                        ? null
                        : 'Passwords do not match.',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: DesignSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(DesignSpacing.md),
                    decoration: BoxDecoration(
                      color: DesignColors.error.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      border: Border.all(
                        color: DesignColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.readable(DesignColors.error),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: DesignSpacing.lg),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : _codeRequested
                            ? _resetPassword
                            : _requestCode,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_codeRequested
                            ? Icons.check_rounded
                            : Icons.send_rounded),
                    label: Text(
                      _busy
                          ? _codeRequested
                              ? 'Updating password…'
                              : 'Sending code…'
                          : _codeRequested
                              ? 'Save new password'
                              : 'Send reset code',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: DesignColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                      ),
                    ),
                  ),
                ),
                if (_codeRequested) ...[
                  const SizedBox(height: DesignSpacing.sm),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _codeRequested = false;
                              _code.clear();
                              _error = null;
                            }),
                    child: const Text('Change email or company code'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
