import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/config/google_auth_config.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/core/utils/device_features.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/auth/presentation/widgets/password_reset_sheet.dart';
import 'package:axon_pos/features/auth/presentation/widgets/sign_in_kit.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tenantSlugController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // Explicit order: the Google button sits between the company code and the
  // email, so the keyboard's Next key would otherwise land on the button.
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _biometricAvailable = false;
  bool _editingCode = false;

  // Dynamic company branding
  String? _companyName;
  String? _companyLogoUrl;
  String? _companyLookupError;
  bool _isFetchingCompany = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadRememberedLogin();
    _checkBiometric();
  }

  void _loadRememberedLogin() {
    final storage = getIt<StorageService>();
    final rememberLogin = storage.isRememberLoginEnabled();
    final rememberedTenant = storage.getRememberedTenantSlug();
    final rememberedEmail = storage.getRememberedEmail();
    final savedTenant = storage.getTenantSlug();

    _rememberMe = rememberLogin;
    if ((rememberedTenant ?? savedTenant)?.isNotEmpty == true) {
      _tenantSlugController.text = rememberedTenant ?? savedTenant!;
      _onSlugChanged(_tenantSlugController.text);
    }
    if (rememberedEmail?.isNotEmpty == true) {
      _emailController.text = rememberedEmail!;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tenantSlugController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _onSlugChanged(String slug) {
    _debounceTimer?.cancel();
    final normalizedSlug = _normalizeCompanyCode(slug);
    if (normalizedSlug.isEmpty) {
      setState(() {
        _companyName = null;
        _companyLogoUrl = null;
        _companyLookupError = null;
        _isFetchingCompany = false;
      });
      return;
    }
    setState(() {
      _companyName = null;
      _companyLogoUrl = null;
      _companyLookupError = null;
      _isFetchingCompany = true;
    });
    final lookupSlug = normalizedSlug;
    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final result = await getIt<ApiClient>()
            .getCompanyInfo(lookupSlug)
            .timeout(const Duration(seconds: 10));
        if (mounted &&
            _normalizeCompanyCode(_tenantSlugController.text) == lookupSlug) {
          setState(() {
            _isFetchingCompany = false;
            _companyName = result?['name'] as String?;
            _companyLogoUrl = result?['logoUrl'] as String?;
            _companyLookupError = result == null
                ? 'We couldn\u2019t find that business. Check the code with your administrator.'
                : result['isActive'] == false
                    ? 'This business is currently unavailable. Contact your administrator.'
                    : null;
          });
        }
      } catch (_) {
        if (mounted &&
            _normalizeCompanyCode(_tenantSlugController.text) == lookupSlug) {
          setState(() {
            _isFetchingCompany = false;
            _companyLookupError = null;
          });
        }
      }
    });
  }

  String _normalizeCompanyCode(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

  bool _isValidCompanyCode(String value) =>
      RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(value);

  Future<void> _checkBiometric() async {
    debugPrint('[LoginScreen] Checking biometric availability...');
    final storage = getIt<StorageService>();
    final deviceAvailable = await ref
        .read(authControllerProvider.notifier)
        .isDeviceAuthenticationAvailable();
    final ready =
        await ref.read(authControllerProvider.notifier).isBiometricAvailable();
    final enabled = storage.isBiometricEnabled();
    debugPrint(
      '[LoginScreen] Device auth available: $deviceAvailable, biometric ready: $ready',
    );
    if (mounted) {
      setState(() {
        _biometricAvailable = ready && enabled;
      });
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final tenantSlug = _normalizeCompanyCode(_tenantSlugController.text);
    final updates = getIt<UpdateCheckService>()..beginPostLoginCheck();
    final result = await ref.read(authControllerProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          tenantSlug: tenantSlug.isNotEmpty ? tenantSlug : null,
        );
    if (!result) updates.cancelPostLoginCheck();

    if (result && mounted) {
      final settle = updates.checkAfterLogin();
      // The router moves to the dashboard as soon as sign-in succeeds, which
      // can dispose this screen before the awaits below finish. Hold the
      // root navigator's context instead so the welcome dialog still shows.
      final host = Navigator.of(context, rootNavigator: true).context;
      await getIt<StorageService>().saveRememberedLogin(
        enabled: _rememberMe,
        email: _emailController.text.trim(),
        tenantSlug: tenantSlug,
      );

      final user = ref.read(authControllerProvider).user;
      final tenant = user?['tenant'];
      final companyName = tenant is Map<String, dynamic>
          ? tenant['name'] as String?
          : _companyName;
      final companyCode =
          (user?['tenantSlug'] as String?)?.trim().isNotEmpty == true
              ? (user?['tenantSlug'] as String).trim()
              : tenantSlug;

      await _showLoginSuccessDialog(
        // ignore: use_build_context_synchronously -- root navigator context
        host,
        companyName: companyName ?? 'Your company',
        companyCode: companyCode,
      );

      if (!mounted) return;
      await settle;
      if (!mounted) return;
      context.go('/');
    }
  }

  Future<void> _openPasswordReset() async {
    final completed = await showPasswordResetSheet(
      context,
      email: _emailController.text,
      companyCode: _normalizeCompanyCode(_tenantSlugController.text),
    );
    if (!mounted || completed != true) return;
    _passwordController.clear();
    showGlassSnackBar(
      context,
      'Password updated. Sign in with your new password.',
      icon: Icons.check_circle_rounded,
      color: DesignColors.success,
    );
  }

  Future<void> _handleGoogleLogin() async {
    final tenantSlug = _normalizeCompanyCode(_tenantSlugController.text);
    if (tenantSlug.isEmpty || !_isValidCompanyCode(tenantSlug)) {
      showGlassSnackBar(
        context,
        'Enter your company code before continuing with Google.',
        icon: Icons.business_outlined,
        color: DesignColors.warning,
      );
      return;
    }

    try {
      // Always show the chooser even when Google cached the last account.
      // This clears only the plugin session, not the device's Google accounts.
      await googleSignIn.signOut();
      final account = await googleSignIn.signIn();
      if (account == null) return;

      final authentication = await account.authentication;
      final idToken = authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        if (!mounted) return;
        showGlassSnackBar(
          context,
          'Google did not return a secure sign-in token. Try again.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
        return;
      }

      final updates = getIt<UpdateCheckService>()..beginPostLoginCheck();
      final result = await ref
          .read(authControllerProvider.notifier)
          .loginWithGoogle(idToken: idToken, tenantSlug: tenantSlug);
      if (!result || !mounted) {
        updates.cancelPostLoginCheck();
        return;
      }
      final settle = updates.checkAfterLogin();
      final host = Navigator.of(context, rootNavigator: true).context;

      await getIt<StorageService>().saveRememberedLogin(
        enabled: _rememberMe,
        email: account.email,
        tenantSlug: tenantSlug,
      );
      final user = ref.read(authControllerProvider).user;
      final tenant = user?['tenant'];
      final companyName = tenant is Map<String, dynamic>
          ? tenant['name'] as String?
          : _companyName;
      final companyCode =
          (user?['tenantSlug'] as String?)?.trim().isNotEmpty == true
              ? (user?['tenantSlug'] as String).trim()
              : tenantSlug;
      await _showLoginSuccessDialog(
        // ignore: use_build_context_synchronously -- root navigator context
        host,
        companyName: companyName ?? 'Your company',
        companyCode: companyCode,
      );
      if (!mounted) return;
      await settle;
      if (!mounted) return;
      context.go('/');
    } catch (_) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Google sign-in could not be completed. Try again or use email and password.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
  }

  Future<void> _showLoginSuccessDialog(
    BuildContext host, {
    required String companyName,
    required String companyCode,
  }) async {
    await showDialog<void>(
      context: host,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
          ),
          titlePadding: const EdgeInsets.fromLTRB(DesignSpacing.xxl,
              DesignSpacing.xxl, DesignSpacing.xxl, DesignSpacing.sm),
          contentPadding: const EdgeInsets.fromLTRB(
              DesignSpacing.xxl, 0, DesignSpacing.xxl, DesignSpacing.sm),
          actionsPadding: const EdgeInsets.fromLTRB(DesignSpacing.xxl,
              DesignSpacing.sm, DesignSpacing.xxl, DesignSpacing.xl),
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DesignColors.success.withValues(alpha: 0.14),
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: DesignColors.success,
                  size: DesignSpacing.xxl,
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              const Expanded(
                child: Text(
                  'Login Successful',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                companyName,
                style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: DesignSpacing.sm),
              const Text(
                'Save this company code. You and your staff will use it with the verified Google account or email credentials registered for this business.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: DesignSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: DesignColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  border: Border.all(
                    color: DesignColors.accent.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        companyCode,
                        style: DesignType.numeric(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy company code',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: companyCode),
                        );
                        if (mounted) {
                          showGlassSnackBar(
                            context,
                            'Company code copied',
                            icon: Icons.copy_rounded,
                            color: DesignColors.success,
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                label: 'I Saved It',
                icon: Icons.check_rounded,
                onPressed: () => Navigator.of(dialogContext).pop(),
                height: 48,
                borderRadius: DesignSpacing.radiusMd,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleBiometricLogin() async {
    debugPrint('[LoginScreen] Attempting biometric login...');
    if (!_biometricAvailable) {
      showGlassSnackBar(
        context,
        getIt<StorageService>().isBiometricEnabled()
            ? 'Biometrics unlock a remembered session. Sign in with your account to start a new session.'
            : 'Sign in once, then enable biometrics in Settings > Security for this company.',
        icon: Icons.info_outline_rounded,
        color: DesignColors.info,
      );
      return;
    }

    final result =
        await ref.read(authControllerProvider.notifier).loginWithBiometrics();
    debugPrint('[LoginScreen] Biometric login result: $result');

    if (result && mounted) {
      debugPrint(
          '[LoginScreen] Biometric login successful, navigating to home');
      context.go('/');
    } else {
      debugPrint('[LoginScreen] Biometric login failed');
      if (mounted) {
        showGlassSnackBar(
          context,
          'Biometric authentication failed. Please try again or use email login.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final palette = SignInPalette.of(context);
    final slug = _normalizeCompanyCode(_tenantSlugController.text);
    final businessName = businessNameFrom(name: _companyName, code: slug);
    final hasBusiness = _companyName != null && _companyLookupError == null;
    final showCodeField = _editingCode || !hasBusiness;
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final sheetColor = palette.isDark ? palette.card : palette.page;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: sheetColor,
        systemNavigationBarIconBrightness:
            palette.isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: DesignColors.darkBg,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Business header: who this phone signs in to.
            Padding(
              padding: EdgeInsets.fromLTRB(8, topInset + 4, 20, 26),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    color: DesignColors.darkTextPrimary,
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/company-choice'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  BusinessMark(
                    name: businessName,
                    logoUrl: _companyLogoUrl,
                    size: 48,
                    loading: _isFetchingCompany && _companyLogoUrl == null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          businessName.isEmpty ? 'Counterbase' : businessName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DesignType.display.copyWith(
                            color: DesignColors.darkTextPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          slug.isEmpty
                              ? 'Staff sign in'
                              : hasBusiness && !_editingCode
                                  ? slug
                                  : 'Check the company code',
                          style: const TextStyle(
                            color: DesignColors.darkTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasBusiness && !_editingCode)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: DesignColors.accentLight,
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => setState(() => _editingCode = true),
                      child: const Text('Change'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: sheetColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(22, 26, 22, bottomInset + 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Form(
                        key: _formKey,
                        child: _buildFormBody(palette, authState, showCodeField),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormBody(
    SignInPalette palette,
    AuthState authState,
    bool showCodeField,
  ) {
    final isDark = palette.isDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in to your shop',
          style: DesignType.display.copyWith(
            color: palette.ink,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Use the email and password for your staff account.',
          style: TextStyle(color: palette.soft, fontSize: 14, height: 1.4),
        ),
        if (_biometricAvailable) ...[
          const SizedBox(height: 14),
          SignInOutlineButton(
            label: 'Unlock with biometrics',
            leading: Icon(Icons.fingerprint_rounded, color: palette.ink),
            onPressed: authState.isLoading ? null : _handleBiometricLogin,
          ),
        ],
        const SizedBox(height: 22),
        if (showCodeField) ...[
          _buildPremiumTextField(
            controller: _tenantSlugController,
            label: 'Company code',
            hint: 'your-company-code',
            helperText: 'Ask your business owner or manager for this code.',
            prefixIcon: Icons.business_outlined,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _emailFocus.requestFocus(),
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            isDark: isDark,
            onChanged: _onSlugChanged,
            suffixIcon: _isFetchingCompany
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            validator: (value) {
              final code = _normalizeCompanyCode(value ?? '');
              if (code.isEmpty) {
                return 'Please enter your company code';
              }
              if (code.length < 2 || !_isValidCompanyCode(code)) {
                return 'Use the lowercase code format, for example acme-stores';
              }
              return null;
            },
          ),
          if (_companyLookupError != null) ...[
            const SizedBox(height: DesignSpacing.sm),
            Semantics(
              liveRegion: true,
              label: _companyLookupError!,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: DesignColors.warning, size: 17),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _companyLookupError!,
                      style: const TextStyle(
                        color: DesignColors.warning,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: DesignSpacing.lg),
        ],
        _buildPremiumTextField(
          controller: _emailController,
          focusNode: _emailFocus,
          label: 'Email',
          hint: 'your-email@company.com',
          prefixIcon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
          autocorrect: false,
          isDark: isDark,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your email';
            }
            if (!value.contains('@')) {
              return 'Please enter a valid email';
            }
            return null;
          },
        ),
        const SizedBox(height: DesignSpacing.lg),
        _buildPremiumTextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          label: 'Password',
          hint: 'Enter your password',
          prefixIcon: Icons.lock_outlined,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _handleLogin(),
          suffixIcon: IconButton(
            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: palette.faint,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          isDark: isDark,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your password';
            }
            if (value.length < 8) {
              return 'Password must be at least 8 characters';
            }
            return null;
          },
        ),
        const SizedBox(height: DesignSpacing.sm),
        Row(
          children: [
            Semantics(
              toggled: _rememberMe,
              label: 'Stay signed in',
              child: InkWell(
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignSpacing.xs,
                    vertical: DesignSpacing.md,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _rememberMe ? DesignColors.accent : palette.card,
                          border: Border.all(
                            color:
                                _rememberMe ? DesignColors.accent : palette.line,
                            width: 1.5,
                          ),
                        ),
                        child: _rememberMe
                            ? const Icon(Icons.check_rounded,
                                size: 16, color: SignInPalette.onAccent)
                            : null,
                      ),
                      const SizedBox(width: DesignSpacing.sm),
                      Text(
                        'Stay signed in',
                        style: TextStyle(color: palette.soft, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: authState.isLoading ? null : _openPasswordReset,
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 48),
                padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.sm),
              ),
              child: Text(
                'Forgot password?',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: palette.faint,
                ),
              ),
            ),
          ],
        ),
        if (authState.error != null) ...[
          const SizedBox(height: DesignSpacing.sm),
          SignInError(message: authState.error!),
        ],
        const SizedBox(height: DesignSpacing.lg),
        SignInButton(
          label: 'Sign in',
          loading: authState.isLoading,
          onPressed: authState.isLoading ? null : _handleLogin,
        ),
        const SizedBox(height: DesignSpacing.xs),
        LegalConsent(palette: palette, action: 'signing in'),
        if (DeviceFeatures.googleSignIn) ...[
        const SizedBox(height: DesignSpacing.sm),
        Row(
          children: [
            Expanded(child: Divider(color: palette.line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or',
                  style: TextStyle(color: palette.faint, fontSize: 12)),
            ),
            Expanded(child: Divider(color: palette.line)),
          ],
        ),
        const SizedBox(height: DesignSpacing.lg),
        SignInOutlineButton(
          label: 'Continue with Google',
          leading: Text(
            'G',
            style: DesignType.display.copyWith(
              color: palette.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: authState.isLoading ? null : _handleGoogleLogin,
        ),
        ],
        const SizedBox(height: DesignSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            SignInTextLink(
              label: 'Have an invitation code?',
              onPressed: () => context.push('/accept-invite'),
            ),
            SignInTextLink(
              label: 'Create a new business account',
              onPressed: () => context.push('/company-setup'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    FocusNode? focusNode,
    bool obscureText = false,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onFieldSubmitted,
    String? Function(String?)? validator,
    bool isDark = false,
    String? helperText,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool autocorrect = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark
                    ? DesignColors.darkTextSecondary
                    : DesignColors.textSecondary,
              ),
        ),
        const SizedBox(height: DesignSpacing.sm - 2),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          // Keep the whole field, not just the caret, clear of the keyboard.
          scrollPadding: const EdgeInsets.only(bottom: 160),
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          autocorrect: autocorrect,
          onChanged: onChanged,
          onFieldSubmitted: onFieldSubmitted,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: isDark
                    ? DesignColors.darkTextPrimary
                    : DesignColors.textPrimary,
              ),
          cursorColor: DesignColors.accent,
          decoration: InputDecoration(
            prefixIcon: Icon(
              prefixIcon,
              color: isDark
                  ? DesignColors.darkTextTertiary
                  : DesignColors.textTertiary,
              size: 20,
            ),
            suffixIcon: suffixIcon,
            hintText: hint,
            hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isDark
                      ? DesignColors.darkTextTertiary
                      : DesignColors.textTertiary,
                ),
            helperText: helperText,
            helperMaxLines: 2,
            errorMaxLines: 3,
            helperStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDark
                      ? DesignColors.darkTextTertiary
                      : DesignColors.textTertiary,
                  height: 1.3,
                ),
            filled: true,
            fillColor: isDark
                ? DesignColors.darkSurfaceElevated
                : DesignColors.surfaceSubtle,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              borderSide: BorderSide(
                color: isDark
                    ? DesignColors.darkBorder
                    : DesignColors.surfaceBorder,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              borderSide: BorderSide(
                color: isDark
                    ? DesignColors.darkBorder
                    : DesignColors.surfaceBorder,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              borderSide: BorderSide(
                color: DesignColors.accent.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              borderSide: BorderSide(
                color: DesignColors.error.withValues(alpha: 0.5),
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              borderSide: BorderSide(
                color: DesignColors.error.withValues(alpha: 0.7),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: DesignSpacing.lg,
              vertical: DesignSpacing.md,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}
