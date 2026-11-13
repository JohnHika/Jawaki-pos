import 'package:flutter/material.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/utils/company_code.dart';
import '../widgets/sign_in_kit.dart';
import 'auth_desktop_kit.dart';

/// Sign-in for a computer window: brand panel on the left, the form in a
/// centred column on the right.
///
/// It only draws. The screen that owns it keeps the controllers, validators
/// and the sign-in call, so the phone and computer layouts share one set of
/// rules.
class LoginDesktopView extends StatelessWidget {
  const LoginDesktopView({
    super.key,
    required this.formKey,
    required this.companyController,
    required this.emailController,
    required this.passwordController,
    required this.companyFocus,
    required this.emailFocus,
    required this.passwordFocus,
    required this.showCodeField,
    required this.businessName,
    required this.companyCode,
    required this.fetchingCompany,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.rememberMe,
    required this.onRememberChanged,
    required this.loading,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onInvite,
    required this.onCreateBusiness,
    required this.onBack,
    required this.onCompanyChanged,
    required this.onChangeCompany,
    required this.validateCompany,
    required this.validateEmail,
    required this.validatePassword,
    this.logoUrl,
    this.lookupError,
    this.errorMessage,
    this.onPhoneSignIn,
    this.onBiometric,
    this.appVersion,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController companyController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode companyFocus;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;

  /// True while the company code is being typed or checked. False once the
  /// business is known, when its name and a Change link take the field's place.
  final bool showCodeField;
  final String businessName;
  final String companyCode;
  final String? logoUrl;
  final bool fetchingCompany;
  final String? lookupError;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final bool rememberMe;
  final ValueChanged<bool> onRememberChanged;
  final bool loading;
  final String? errorMessage;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onInvite;
  final VoidCallback onCreateBusiness;
  final VoidCallback onBack;
  final ValueChanged<String> onCompanyChanged;
  final VoidCallback onChangeCompany;
  final String? Function(String?) validateCompany;
  final String? Function(String?) validateEmail;
  final String? Function(String?) validatePassword;

  /// Null when this computer cannot sign in with a phone.
  final VoidCallback? onPhoneSignIn;

  /// Null when no biometric unlock is set up.
  final VoidCallback? onBiometric;
  final String? appVersion;

  @override
  Widget build(BuildContext context) {
    return AuthDesktopShell(
      onEscape: onBack,
      brand: AuthBrandPanel(
        footer: appVersion,
      ),
      header: AuthBackLink(onPressed: onBack),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const AuthHeading(
              title: 'Sign in to your shop',
              subtitle: 'Use the email and password for your staff account.',
            ),
            const SizedBox(height: 20),
            if (showCodeField) ...[
              AuthField(
                fieldKey: const ValueKey('auth-company-code'),
                label: 'Company code',
                controller: companyController,
                focusNode: companyFocus,
                hint: 'your-company-code',
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => emailFocus.requestFocus(),
                onChanged: onCompanyChanged,
                inputFormatters: const [CompanyCodeFormatter()],
                validator: validateCompany,
                suffix: fetchingCompany
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              if (lookupError != null) ...[
                const SizedBox(height: 8),
                AuthNotice(message: lookupError!, warning: true),
              ],
            ] else
              _BusinessRow(
                name: businessName,
                code: companyCode,
                logoUrl: logoUrl,
                onChange: onChangeCompany,
              ),
            const SizedBox(height: 14),
            AuthField(
              fieldKey: const ValueKey('auth-email'),
              label: 'Email',
              controller: emailController,
              focusNode: emailFocus,
              hint: 'your-email@company.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => passwordFocus.requestFocus(),
              validator: validateEmail,
            ),
            const SizedBox(height: 14),
            AuthPasswordField(
              fieldKey: const ValueKey('auth-password'),
              controller: passwordController,
              focusNode: passwordFocus,
              hint: 'Enter your password',
              obscure: obscurePassword,
              onToggle: onToggleObscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
              validator: validatePassword,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                AuthCheckRow(
                  label: 'Stay signed in',
                  value: rememberMe,
                  onChanged: onRememberChanged,
                ),
                const Spacer(),
                AuthTextLink(
                  label: 'Forgot password?',
                  onPressed: loading ? null : onForgotPassword,
                ),
              ],
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              AuthNotice(message: errorMessage!),
            ],
            const SizedBox(height: 12),
            AuthPrimaryButton(
              label: 'Sign in',
              loading: loading,
              onPressed: onSubmit,
            ),
            if (onBiometric != null) ...[
              const SizedBox(height: 8),
              AuthSecondaryButton(
                label: 'Unlock with biometrics',
                icon: Icons.fingerprint_rounded,
                onPressed: loading ? null : onBiometric,
              ),
            ],
            if (onPhoneSignIn != null) ...[
              const SizedBox(height: 8),
              AuthSecondaryButton(
                label: 'Sign in with your phone',
                icon: Icons.qr_code_2_rounded,
                onPressed: loading ? null : onPhoneSignIn,
              ),
            ],
            const SizedBox(height: 6),
            const AuthLegalLine(action: 'signing in'),
            const SizedBox(height: 2),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                AuthTextLink(
                  label: 'Have an invitation code?',
                  onPressed: onInvite,
                ),
                AuthTextLink(
                  label: 'Create a new business account',
                  onPressed: onCreateBusiness,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Who this computer signs in to, once the company code has been recognised.
class _BusinessRow extends StatelessWidget {
  const _BusinessRow({
    required this.name,
    required this.code,
    required this.onChange,
    this.logoUrl,
  });

  final String name;
  final String code;
  final String? logoUrl;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: p.panelAlt,
        borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          BusinessMark(name: name, logoUrl: logoUrl, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? code : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          AuthTextLink(label: 'Change', onPressed: onChange, strong: true),
        ],
      ),
    );
  }
}
