import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';

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
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _biometricAvailable = false;
  bool _deviceAuthenticationAvailable = false;

  // Dynamic company branding
  String? _companyName;
  String? _companyLogoUrl;
  bool _isFetchingCompany = false;
  Timer? _debounceTimer;

  late AnimationController _fadeAnimation;
  late Animation<double> _fadeAnimationValue;
  late Animation<Offset> _slideAnimation;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadRememberedLogin();
    _checkBiometric();

    _fadeAnimation = AnimationController(
      duration: DesignAnimation.normal,
      vsync: this,
    );

    _fadeAnimationValue = CurvedAnimation(
      parent: _fadeAnimation,
      curve: DesignAnimation.defaultCurve,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fadeAnimation,
      curve: DesignAnimation.smooth,
    ));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _fadeAnimation.forward();
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
    _fadeAnimation.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onSlugChanged(String slug) {
    _debounceTimer?.cancel();
    if (slug.trim().isEmpty) {
      setState(() {
        _companyName = null;
        _companyLogoUrl = null;
        _isFetchingCompany = false;
      });
      return;
    }
    setState(() => _isFetchingCompany = true);
    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      final result = await getIt<ApiClient>().getCompanyInfo(slug.trim());
      if (mounted) {
        setState(() {
          _isFetchingCompany = false;
          _companyName = result?['name'] as String?;
          _companyLogoUrl = result?['logoUrl'] as String?;
        });
      }
    });
  }

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
      });
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final tenantSlug = _tenantSlugController.text.trim();
    final result = await ref.read(authControllerProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          tenantSlug: tenantSlug.isNotEmpty ? tenantSlug : null,
        );

    if (result && mounted) {
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
        companyName: companyName ?? 'Your company',
        companyCode: companyCode,
      );

      if (!mounted) return;
      context.go('/');
    }
  }

  Future<void> _showLoginSuccessDialog({
    required String companyName,
    required String companyCode,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
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
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Save this company code. You and your staff will use it with email and password when logging in on any device.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: DesignColors.brand.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: DesignColors.brand.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        companyCode,
                        style: const TextStyle(
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
                borderRadius: 12,
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
        'Sign in once, then enable biometrics in Settings > Security for this company.',
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

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: isDark ? DesignColors.darkBg : const Color(0xFF1A1A2E),
        child: SafeArea(
          minimum: EdgeInsets.only(top: 8, bottom: 16),
          child: Stack(
            children: [
              Positioned(
                top: 4,
                left: 4,
                child: IconButton(
                  icon:
                      const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  tooltip: 'Back',
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go('/company-choice'),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: isSmallScreen ? 12 : 32,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo section
                      FadeTransition(
                        opacity: _fadeAnimationValue,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final scale = 1.0 + (_pulseController.value * 0.04);
                            return Transform.scale(
                              scale: scale,
                              child: child,
                            );
                          },
                          child: Container(
                            width: isSmallScreen ? 72 : 88,
                            height: isSmallScreen ? 72 : 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _buildLogo(isSmallScreen ? 72 : 88),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: isSmallScreen ? 16 : 24),

                      // Title — dynamic based on fetched company
                      Text(
                        _companyName ?? 'POS System',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 26 : 32,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Point of Sale System',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.7),
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: isSmallScreen ? 24 : 32),

                      // Login card
                      FadeTransition(
                        opacity: _fadeAnimationValue,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child:
                              _buildLoginCard(isSmallScreen, authState, isDark),
                        ),
                      ),

                      // Bottom branding
                      SizedBox(height: isSmallScreen ? 16 : 24),
                      _buildBottomLinks(),
                    ],
                  ),
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
      constraints: BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Padding(
          padding: EdgeInsets.all(
            isSmallScreen ? 20 : 24,
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
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sign In',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 20 : 22,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? DesignColors.darkTextPrimary
                          : DesignColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Secure staff access for POS, products, and analytics',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? DesignColors.darkTextSecondary
                      : DesignColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),

              // Company identifier field
              _buildPremiumTextField(
                controller: _tenantSlugController,
                label: 'Company Code',
                hint: 'your-company-code',
                prefixIcon: Icons.business_outlined,
                keyboardType: TextInputType.text,
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
                  if (value == null || value.isEmpty) {
                    return 'Please enter your company code';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Email field
              _buildPremiumTextField(
                controller: _emailController,
                label: 'Email',
                hint: 'your-email@company.com',
                prefixIcon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
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
              const SizedBox(height: 16),

              // Password field
              _buildPremiumTextField(
                controller: _passwordController,
                label: 'Password',
                hint: 'Enter your password',
                prefixIcon: Icons.lock_outlined,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleLogin(),
                suffixIcon: IconButton(
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
                  if (value.length < 3) {
                    return 'Password must be at least 3 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Remember me + Forgot password
              Row(
                children: [
                  // Custom remember me toggle
                  GestureDetector(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _rememberMe
                                ? DesignColors.brand
                                : isDark
                                    ? DesignColors.darkSurfaceElevated
                                    : Colors.white,
                            border: Border.all(
                              color: _rememberMe
                                  ? DesignColors.brand
                                  : isDark
                                      ? DesignColors.darkBorder
                                      : DesignColors.surfaceBorder,
                              width: 1.5,
                            ),
                          ),
                          child: _rememberMe
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(
                                height: 2), // Adjust vertical alignment
                            Text(
                              'Remember me',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? DesignColors.darkTextSecondary
                                    : DesignColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Forgot password link
                  GestureDetector(
                    onTap: () {
                      showGlassSnackBar(
                        context,
                        'Contact administrator to reset password',
                        icon: Icons.lock_reset_rounded,
                        color: DesignColors.info,
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 2), // Adjust vertical alignment
                        Text(
                          'Forgot Password?',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DesignColors.brand,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Sign In button
              GradientButton(
                label: 'Sign In',
                icon: Icons.arrow_forward_rounded,
                onPressed: authState.isLoading ? null : _handleLogin,
                isLoading: authState.isLoading,
                height: 48,
                borderRadius: 12,
                gradient: isDark
                    ? [DesignColors.brand, DesignColors.brandDark]
                    : [DesignColors.brand, DesignColors.brandDark],
              ),

              const SizedBox(height: 16),

              // Error message
              if (authState.error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DesignColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          authState.error!,
                          style: TextStyle(
                            color: DesignColors.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Divider
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      color: isDark
                          ? DesignColors.darkBorder
                          : DesignColors.surfaceBorder,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'or',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DesignColors.textPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: isDark
                          ? DesignColors.darkBorder
                          : DesignColors.surfaceBorder,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Alternative login options
              Row(
                children: [
                  // PIN login button
                  Expanded(
                    child: _buildAltLoginButton(
                      icon: Icons.pin_outlined,
                      label: 'Login with PIN',
                      onTap: () => context.push('/pin-login'),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Device biometric / face unlock button
                  if (_deviceAuthenticationAvailable)
                    Expanded(
                      child: _buildAltLoginButton(
                        icon: Icons.fingerprint_rounded,
                        label: _biometricAvailable
                            ? 'Biometric / Face'
                            : 'Set up biometric',
                        onTap: authState.isLoading
                            ? () {}
                            : () => _handleBiometricLogin(),
                        isDark: isDark,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24), // Added bottom padding for balance
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
        color: DesignColors.brand,
      );

  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    bool obscureText = false,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onFieldSubmitted,
    String? Function(String?)? validator,
    bool isDark = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark
                ? DesignColors.darkTextSecondary
                : DesignColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onFieldSubmitted: onFieldSubmitted,
          style: TextStyle(
            color: isDark
                ? DesignColors.darkTextPrimary
                : DesignColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: DesignColors.brand,
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
            hintStyle: TextStyle(
              color: isDark
                  ? DesignColors.darkTextTertiary
                  : DesignColors.textTertiary,
              fontSize: 15,
            ),
            filled: true,
            fillColor: isDark
                ? DesignColors.darkSurfaceElevated
                : DesignColors.surfaceSubtle,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark
                    ? DesignColors.darkBorder
                    : DesignColors.surfaceBorder,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark
                    ? DesignColors.darkBorder
                    : DesignColors.surfaceBorder,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: DesignColors.brand.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: DesignColors.error.withValues(alpha: 0.5),
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: DesignColors.error.withValues(alpha: 0.7),
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 12,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark
              ? DesignColors.darkSurfaceElevated
              : DesignColors.surfaceSubtle,
          border: Border.all(
            color:
                isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isDark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary,
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? DesignColors.darkTextSecondary
                    : DesignColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomLinks() {
    return Column(
      children: [
        const Icon(
          Icons.cloud_done_rounded,
          size: 20,
          color: DesignColors.success,
        ),
        const SizedBox(height: 8),
        Text(
          'Connected to cloud POS',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DesignColors.darkTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Point of Sale System',
          style: TextStyle(
            fontSize: 12,
            color: DesignColors.darkTextTertiary,
          ),
        ),
      ],
    );
  }
}
