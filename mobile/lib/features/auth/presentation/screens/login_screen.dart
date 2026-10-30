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
import 'package:axon_pos/core/widgets/motion.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/auth/presentation/widgets/password_reset_sheet.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
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
  bool _deviceAuthenticationAvailable = false;
  bool _showPasswordFallback = false;
  String _primaryLoginMethod = 'email';

  // Dynamic company branding
  String? _companyName;
  String? _companyLogoUrl;
  String? _companyLookupError;
  bool _isFetchingCompany = false;
  Timer? _debounceTimer;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadRememberedLogin();
    _checkBiometric();

    _pulseController = AnimationController(
      vsync: this,
      duration: DesignAnimation.slowest,
    );
  }

  // The brand pulse is an infinite loop: it must only run when the OS
  // "remove animations" setting is off (see core/widgets/motion.dart).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  void _loadRememberedLogin() {
    final storage = getIt<StorageService>();
    final rememberLogin = storage.isRememberLoginEnabled();
    final rememberedTenant = storage.getRememberedTenantSlug();
    final rememberedEmail = storage.getRememberedEmail();
    final savedTenant = storage.getTenantSlug();

    _rememberMe = rememberLogin;
    _primaryLoginMethod = storage.getPrimaryLoginMethod();
    _showPasswordFallback = _primaryLoginMethod == 'email';
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
    _pulseController.dispose();
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
        _deviceAuthenticationAvailable = deviceAvailable;
        _biometricAvailable = ready && enabled;
        if (_primaryLoginMethod == 'biometric' && !ready) {
          // Biometrics only reopen a remembered session; a full sign-in still
          // needs a credential, so make that route the visible fallback.
          _showPasswordFallback = true;
        }
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
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 700;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: context.themed(DesignColors.darkBg),
        child: SafeArea(
          minimum: const EdgeInsets.only(
              top: DesignSpacing.sm, bottom: DesignSpacing.lg),
          // The back button has its own row above the scrolling content, so
          // the form never slides underneath it.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 64,
                  height: 56,
                  child: AppBackButton(
                    background: context.themed(DesignColors.darkBg),
                    color: isDark ? Colors.white : DesignColors.textPrimary,
                    isDark: isDark,
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/company-choice'),
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    // Decorative 3D-ish brand image in the upper-right background.
                    // Kept small and above the headline: at 55% width it used to run
                    // straight through the title and subtitle (and its orange shop
                    // badge sat on top of the text).
                    Positioned(
                      top: size.height * 0.02,
                      right: size.width * 0.02,
                      width: size.width * 0.34,
                      height: size.width * 0.34,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: _pulseController.value * 0.06 - 0.03,
                            child: Transform.scale(
                              scale: 1.0 + (_pulseController.value * 0.03),
                              child: child,
                            ),
                          );
                        },
                        // Hidden while typing: the content scrolls up under it and
                        // the shop badge would sit on the company name.
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          // The icon artwork has an opaque dark plate, which reads as
                          // a grey box on the light canvas, so it is dark-theme only.
                          opacity: (!isDark ||
                                  MediaQuery.viewInsetsOf(context).bottom > 0)
                              ? 0.0
                              : 0.35,
                          child: Image.asset(
                            'assets/images/axon_app_icon_512.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal: DesignSpacing.xxl,
                          vertical: isSmallScreen
                              ? DesignSpacing.md
                              : DesignSpacing.xxxl,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Logo section — first-mount stagger (see StaggeredItem)
                            StaggeredItem(
                              itemKey: 'login-logo',
                              child: AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) {
                                  final scale =
                                      1.0 + (_pulseController.value * 0.04);
                                  return Transform.scale(
                                    scale: scale,
                                    child: child,
                                  );
                                },
                                child: AuthEntrance(
                                  child: Container(
                                    width: isSmallScreen ? 72 : 88,
                                    height: isSmallScreen ? 72 : 88,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.2),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: _buildLogo(
                                        isSmallScreen ? 72 : 88,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: isSmallScreen ? 16 : 24),

                            // Title — dynamic based on fetched company
                            StaggeredItem(
                              itemKey: 'login-title',
                              index: 1,
                              child: Text(
                                _companyName ?? 'Arxon Axon',
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  color: isDark
                                      ? Colors.white
                                      : DesignColors.textPrimary,
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                              ),
                            ),
                            const SizedBox(height: DesignSpacing.sm),
                            StaggeredItem(
                              itemKey: 'login-subtitle',
                              index: 2,
                              child: Text(
                                _companyName == null
                                    ? 'CONNECT YOUR STAFF ACCOUNT'
                                    : 'READY FOR STAFF SIGN IN',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.7)
                                      : DesignColors.textSecondary,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                            SizedBox(
                                height: isSmallScreen
                                    ? DesignSpacing.xxl
                                    : DesignSpacing.xxxl),

                            // Login card
                            StaggeredItem(
                              itemKey: 'login-card',
                              index: 3,
                              child: _buildLoginCard(
                                  isSmallScreen, authState, isDark),
                            ),

                            // Bottom branding
                            SizedBox(
                                height: isSmallScreen
                                    ? DesignSpacing.lg
                                    : DesignSpacing.xl),
                            StaggeredItem(
                              itemKey: 'login-footer',
                              index: 4,
                              child: _buildBottomLinks(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard(bool isSmallScreen, AuthState authState, bool isDark) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(
          color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
            blurRadius: DesignSpacing.xl,
            offset: const Offset(0, DesignSpacing.sm),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Padding(
          padding: EdgeInsets.all(
            isSmallScreen ? DesignSpacing.xl : DesignSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings_rounded,
                    color: isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary,
                    size: DesignSpacing.xxl,
                  ),
                  const SizedBox(width: DesignSpacing.md),
                  Expanded(
                    child: Text(
                      'Staff sign in',
                      style: (isSmallScreen
                              ? Theme.of(context).textTheme.titleLarge
                              : Theme.of(context).textTheme.headlineSmall)
                          ?.copyWith(
                        color: isDark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignSpacing.sm),
              Text(
                'Enter the company code from your administrator, then sign in with your staff account.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? DesignColors.darkTextSecondary
                          : DesignColors.textSecondary,
                    ),
              ),
              const SizedBox(height: DesignSpacing.lg),

              // Quick sign-in options — placed at the top of the card so users
              // can see PIN / biometric without scrolling past the email form.
              Text(
                'Already set up on this device?',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: isDark
                          ? DesignColors.darkTextSecondary
                          : DesignColors.textSecondary,
                    ),
              ),
              const SizedBox(height: DesignSpacing.sm + 2),
              Row(
                children: [
                  Expanded(
                    child: _buildAltLoginButton(
                      icon: Icons.pin_outlined,
                      label: 'PIN',
                      onTap: () => context.push('/pin-login'),
                      isDark: isDark,
                      selected: _primaryLoginMethod == 'pin',
                    ),
                  ),
                  if (_deviceAuthenticationAvailable) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: AuthEntrance(
                        child: _buildAltLoginButton(
                          icon: Icons.fingerprint_rounded,
                          label: _biometricAvailable
                              ? 'Biometric'
                              : getIt<StorageService>().isBiometricEnabled()
                                  ? 'Biometric unlock'
                                  : 'Set up biometric',
                          onTap: authState.isLoading
                              ? () {}
                              : () => _handleBiometricLogin(),
                          isDark: isDark,
                          selected: _primaryLoginMethod == 'biometric',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: DesignSpacing.xl),

              const SizedBox(height: DesignSpacing.md),

              // Company identifier comes first: Google sign-in is always
              // scoped to the business the staff member is joining.
              _buildPremiumTextField(
                controller: _tenantSlugController,
                label: 'Company Code',
                hint: 'your-company-code',
                helperText: 'Ask your business owner or manager for this code.',
                prefixIcon: Icons.business_outlined,
                keyboardType: TextInputType.text,
                textInputAction: _showPasswordFallback
                    ? TextInputAction.next
                    : TextInputAction.done,
                onFieldSubmitted: (_) => _showPasswordFallback
                    ? _emailFocus.requestFocus()
                    : FocusScope.of(context).unfocus(),
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
                      const Icon(
                        Icons.info_outline_rounded,
                        color: DesignColors.warning,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _companyLookupError!,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: DesignColors.warning,
                                    height: 1.35,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: DesignSpacing.lg + 2),

              OutlinedButton.icon(
                onPressed: authState.isLoading ? null : _handleGoogleLogin,
                icon: const Icon(Icons.account_circle_outlined),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                  side: BorderSide(
                    color: _primaryLoginMethod == 'google'
                        ? DesignColors.accent
                        : isDark
                            ? DesignColors.darkBorder
                            : DesignColors.surfaceBorder,
                    width: _primaryLoginMethod == 'google' ? 1.8 : 1,
                  ),
                ),
              ),
              const SizedBox(height: DesignSpacing.sm),
              Text(
                'Choose the Google account linked to this business.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: isDark
                          ? DesignColors.darkTextSecondary
                          : DesignColors.textSecondary,
                    ),
              ),
              if (!_showPasswordFallback)
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: authState.isLoading
                        ? null
                        : () => setState(() => _showPasswordFallback = true),
                    child: const Text('Use email and password instead'),
                  ),
                ),

              if (_showPasswordFallback) ...[
                const SizedBox(height: DesignSpacing.lg),

                // Email field
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

                // Password field
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
                    tooltip: 'Show or hide password',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: isDark
                          ? DesignColors.darkTextTertiary
                          : DesignColors.textTertiary,
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
                const SizedBox(height: DesignSpacing.md),

                // Remember me + Forgot password
                Row(
                  children: [
                    // Custom remember me toggle — Semantics(checked) so the
                    // state is announced, on a 48px InkWell so the target
                    // clears the 44px minimum and gets ripple feedback.
                    Semantics(
                      toggled: _rememberMe,
                      label: 'Stay signed in',
                      child: InkWell(
                        onTap: () => setState(() => _rememberMe = !_rememberMe),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.xs,
                            vertical: DesignSpacing.sm + 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _rememberMe
                                      ? DesignColors.accent
                                      : isDark
                                          ? DesignColors.darkSurfaceElevated
                                          : Colors.white,
                                  border: Border.all(
                                    color: _rememberMe
                                        ? DesignColors.accent
                                        : isDark
                                            ? DesignColors.darkBorder
                                            : DesignColors.surfaceBorder,
                                    width: 1.5,
                                  ),
                                ),
                                child: _rememberMe
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: Colors.black,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: DesignSpacing.sm),
                              Text(
                                'Stay signed in',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: isDark
                                          ? DesignColors.darkTextSecondary
                                          : DesignColors.textSecondary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Forgot password link
                    TextButton(
                      onPressed:
                          authState.isLoading ? null : _openPasswordReset,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignSpacing.sm,
                        ),
                      ),
                      child: Text(
                        'Forgot password?',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: DesignColors.accent,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignSpacing.xl),

                // Sign In button
                GradientButton(
                  label: 'Sign in to business',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: authState.isLoading ? null : _handleLogin,
                  isLoading: authState.isLoading,
                  height: 48,
                  borderRadius: DesignSpacing.radiusMd,
                  gradient: const [
                    DesignColors.accent,
                    DesignColors.accentDark
                  ],
                ),

                const SizedBox(height: DesignSpacing.lg),
              ],

              // Error message
              if (authState.error != null)
                Semantics(
                  liveRegion: true,
                  label: 'Sign-in error: ${authState.error}',
                  child: Container(
                    padding: const EdgeInsets.all(DesignSpacing.md),
                    decoration: BoxDecoration(
                      color: DesignColors.error.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusMd),
                      border: Border.all(
                        color: DesignColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: DesignColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: DesignSpacing.sm),
                        Expanded(
                          child: Text(
                            authState.error!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: DesignColors.error,
                                      fontWeight: FontWeight.w500,
                                      height: 1.35,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: DesignSpacing.md),

              // Invitation code entry point
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, 48),
                  ),
                  onPressed: () => context.push('/accept-invite'),
                  child: Text(
                    'Have an invitation code?',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DesignColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),

                            // Sign up for a new business. /company-setup is
                            // the local-first workspace-creation flow.
                            Align(
                              alignment: Alignment.center,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(64, 48),
                                ),
                                onPressed: () => context.push('/company-setup'),
                                child: Text(
                                  'Create a new business account',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: DesignColors.accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ),

              const SizedBox(height: DesignSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the logo area: company logo if available, spinner while fetching,
  /// otherwise a generic store icon.
  Widget _buildLogo(double size) {
    if (_companyLogoUrl != null && _companyLogoUrl!.isNotEmpty) {
      return Image.network(
        _companyLogoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _defaultLogoIcon(size),
      );
    }
    if (_isFetchingCompany) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return _defaultLogoIcon(size);
  }

  Widget _defaultLogoIcon(double size) => Icon(
        Icons.store_rounded,
        size: size * 0.55,
        color: DesignColors.accent,
      );

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

  Widget _buildAltLoginButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDark = false,
    bool selected = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
            vertical: DesignSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
            color: isDark
                ? (selected
                    ? DesignColors.accent.withValues(alpha: 0.16)
                    : DesignColors.darkSurfaceElevated)
                : (selected
                    ? DesignColors.accent.withValues(alpha: 0.1)
                    : DesignColors.surfaceSubtle),
            border: Border.all(
              color: selected
                  ? DesignColors.accent
                  : isDark
                      ? DesignColors.darkBorder
                      : DesignColors.surfaceBorder,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected
                    ? DesignColors.accent
                    : isDark
                        ? DesignColors.darkTextSecondary
                        : DesignColors.textSecondary,
                size: 22,
              ),
              const SizedBox(height: DesignSpacing.sm - 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? DesignColors.darkTextSecondary
                          : DesignColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomLinks() {
    return Column(
      children: [
        const Icon(
          Icons.shield_outlined,
          size: 20,
          color: DesignColors.info,
        ),
        const SizedBox(height: DesignSpacing.sm),
        Text(
          'Secure business access',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.themed(DesignColors.darkTextSecondary),
              ),
        ),
        const SizedBox(height: DesignSpacing.sm - 2),
        Text(
          'Point of Sale System',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.themed(DesignColors.darkTextTertiary),
              ),
        ),
      ],
    );
  }
}
