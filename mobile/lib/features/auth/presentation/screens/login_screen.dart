import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:levisa_adventures_pos/core/theme/design_system.dart';
import 'package:levisa_adventures_pos/core/di/injection.dart';
import 'package:levisa_adventures_pos/core/services/local_server_service.dart';
import 'package:levisa_adventures_pos/core/services/storage_service.dart';
import 'package:levisa_adventures_pos/features/auth/presentation/providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _biometricAvailable = false;

  late AnimationController _fadeAnimation;
  late Animation<double> _fadeAnimationValue;
  late Animation<Offset> _slideAnimation;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fadeAnimation.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometric() async {
    debugPrint('[LoginScreen] Checking biometric availability...');
    final available =
        await ref.read(authControllerProvider.notifier).isBiometricAvailable();
    debugPrint('[LoginScreen] Biometric available: $available');
    if (mounted) setState(() => _biometricAvailable = available);
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final result = await ref.read(authControllerProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (result && mounted) {
      context.go('/');
    }
  }

  Future<void> _handleBiometricLogin() async {
    debugPrint('[LoginScreen] Attempting biometric login...');
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

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              DesignColors.brandDark,
              DesignColors.brand,
              DesignColors.teal,
            ],
          ),
        ),
        child: Stack(
          children: [
            // Subtle background grid pattern
            Positioned.fill(
              child: CustomPaint(
                painter: _BackgroundPatternPainter(
                  color: Colors.white.withValues(alpha: 0.03),
                ),
              ),
            ),

            // Decorative gradient circles
            Positioned(
              top: -size.width * 0.3,
              right: -size.width * 0.2,
              child: Container(
                width: size.width * 0.7,
                height: size.width * 0.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Positioned(
              bottom: -size.width * 0.25,
              left: -size.width * 0.15,
              child: Container(
                width: size.width * 0.6,
                height: size.width * 0.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DesignColors.brandLight.withValues(alpha: 0.08),
                ),
              ),
            ),

            // Main content
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: isSmallScreen ? 12 : 32,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated logo section
                      FadeTransition(
                        opacity: _fadeAnimationValue,
                        child: _buildLogoSection(isSmallScreen),
                      ),
                      SizedBox(
                        height:
                            isSmallScreen ? DesignSpacing.md : DesignSpacing.xl,
                      ),

                      // Premium form card with slide/fade
                      FadeTransition(
                        opacity: _fadeAnimationValue,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: _buildLoginCard(isSmallScreen, authState),
                        ),
                      ),

                      // Bottom branding + Server Mode
                      SizedBox(
                          height: isSmallScreen
                              ? DesignSpacing.md
                              : DesignSpacing.lg),
                      _buildBottomLinks(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSection(bool isSmallScreen) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated pulse logo with glass effect
        AnimatedBuilder(
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
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.2),
                  Colors.white.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/levisa_adventures_logo.png',
                fit: BoxFit.cover,
                semanticLabel: 'Levisa Adventures logo',
              ),
            ),
          ),
        ),
        SizedBox(
          height: isSmallScreen ? DesignSpacing.sm : DesignSpacing.md,
        ),
        Text(
          'Levisa Adventures',
          style: TextStyle(
            fontSize: isSmallScreen ? 22 : 28,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Point of Sale',
          style: TextStyle(
            fontSize: isSmallScreen ? 13 : 15,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.7),
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard(bool isSmallScreen, AuthState authState) {
    return GlassCard(
      margin: EdgeInsets.symmetric(horizontal: DesignSpacing.xs),
      padding: EdgeInsets.all(
        isSmallScreen ? DesignSpacing.md : DesignSpacing.xl,
      ),
      blur: 20,
      tint: Colors.white.withValues(alpha: 0.08),
      borderColor: Colors.white.withValues(alpha: 0.15),
      borderRadius: DesignSpacing.radiusXl,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card header
            Text(
              'Welcome back to Levisa Adventures',
              style: TextStyle(
                fontSize: isSmallScreen ? 20 : 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sign in to continue to Levisa Adventures POS',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            SizedBox(height: DesignSpacing.xl),

            // Email field
            _buildPremiumTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'Enter your email',
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
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
            SizedBox(
                height: isSmallScreen ? DesignSpacing.md : DesignSpacing.lg),

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
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            SizedBox(height: DesignSpacing.sm),

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
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _rememberMe
                              ? DesignColors.accent
                              : Colors.white.withValues(alpha: 0.1),
                          border: Border.all(
                            color: _rememberMe
                                ? DesignColors.accent
                                : Colors.white.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: _rememberMe
                            ? Icon(
                                Icons.check_rounded,
                                size: 13,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      SizedBox(width: DesignSpacing.sm),
                      Text(
                        'Remember me',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
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
                  child: Text(
                    'Forgot Password?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DesignColors.accent.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: DesignSpacing.xl),

            // Sign In button with gradient
            GradientButton(
              label: 'Sign In',
              icon: Icons.arrow_forward_rounded,
              onPressed: authState.isLoading ? null : _handleLogin,
              isLoading: authState.isLoading,
              height: 52,
              gradient: [
                DesignColors.accent,
                DesignColors.teal,
              ],
            ),

            // Error message
            if (authState.error != null) ...[
              SizedBox(height: DesignSpacing.md),
              Container(
                padding: EdgeInsets.all(DesignSpacing.md),
                decoration: BoxDecoration(
                  color: DesignColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  border: Border.all(
                    color: DesignColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: DesignColors.error.withValues(alpha: 0.9),
                      size: 20,
                    ),
                    SizedBox(width: DesignSpacing.sm),
                    Expanded(
                      child: Text(
                        authState.error!,
                        style: TextStyle(
                          color: DesignColors.error.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: DesignSpacing.lg),

            // Divider
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: DesignSpacing.md),
                  child: Text(
                    'or',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
            SizedBox(height: DesignSpacing.lg),

            // Alternative login options row
            Row(
              children: [
                // PIN login button
                Expanded(
                  child: _buildAltLoginButton(
                    icon: Icons.pin_outlined,
                    label: 'Login with PIN',
                    onTap: () => context.push('/pin-login'),
                  ),
                ),
                SizedBox(width: DesignSpacing.md),
                // Biometric login button
                if (_biometricAvailable)
                  Expanded(
                    child: _buildAltLoginButton(
                      icon: Icons.fingerprint_rounded,
                      label: 'Biometric',
                      onTap: authState.isLoading
                          ? () {}
                          : () => _handleBiometricLogin(),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    bool obscureText = false,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    ValueChanged<String>? onFieldSubmitted,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.6),
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: DesignSpacing.xs),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: DesignColors.accent,
          decoration: InputDecoration(
            prefixIcon: Icon(
              prefixIcon,
              color: Colors.white.withValues(alpha: 0.4),
              size: 20,
            ),
            suffixIcon: suffixIcon,
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 15,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
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
            contentPadding: EdgeInsets.symmetric(
              horizontal: DesignSpacing.md,
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: DesignSpacing.md,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.7),
              size: 22,
            ),
            SizedBox(height: DesignSpacing.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomLinks() {
    final server = getIt<LocalServerService>();
    final running = server.isRunning;

    return Column(
      children: [
        // Server Mode toggle — always visible on login screen
        GestureDetector(
          onTap: () async {
            if (running) {
              await server.stop();
              setState(() {});
            } else {
              final started = await server.start(port: 3000);
              if (started) {
                final storage = getIt<StorageService>();
                await storage.setServerModeEnabled(true);
              }
              setState(() {});
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: running
                  ? DesignColors.success.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                color: running
                    ? DesignColors.success.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.1),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  running ? Icons.dns : Icons.dns_outlined,
                  size: 18,
                  color: running
                      ? DesignColors.success
                      : Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Text(
                  running ? 'Server Mode: ON' : 'Start Phone Server',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: running
                        ? DesignColors.success
                        : Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Levisa Adventures POS v2.0',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }
}

// Subtle background grid pattern painter
class _BackgroundPatternPainter extends CustomPainter {
  final Color color;

  _BackgroundPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
