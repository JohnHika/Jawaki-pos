import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';

class _WorkspaceIdentity {
  const _WorkspaceIdentity({
    required this.companyName,
    required this.companyCode,
    required this.branchName,
    this.logoUrl,
  });

  final String companyName;
  final String companyCode;
  final String branchName;
  final String? logoUrl;

  String get initials {
    final source = companyName.trim().isNotEmpty ? companyName : companyCode;
    final parts = source
        .split(RegExp(r'\s+|-|_'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'POS';
    return parts
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
  }
}

class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen>
    with TickerProviderStateMixin {
  String _pin = '';
  static const int _pinLength = 4;

  late AnimationController _fadeAnimation;
  late Animation<double> _fadeAnimationValue;
  late AnimationController _pulseController;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  bool _showError = false;
  String _errorMessage = '';
  late final _WorkspaceIdentity _workspaceIdentity;
  bool _biometricAvailable = false;

  void _onNumberPressed(String number) {
    if (_pin.length >= _pinLength) return;

    setState(() {
      _pin += number;
      _showError = false;
    });

    if (_pin.length == _pinLength) {
      _handlePinLogin();
    }
  }

  void _onBackspacePressed() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _showError = false;
      });
    }
  }

  void _onClearPressed() {
    setState(() {
      _pin = '';
      _showError = false;
    });
  }

  Future<void> _handlePinLogin() async {
    final result =
        await ref.read(authControllerProvider.notifier).loginWithPin(_pin);

    if (result && mounted) {
      context.go('/');
    } else {
      if (mounted) {
        setState(() {
          _showError = true;
          _errorMessage = ref.read(authControllerProvider).error ??
              'Invalid PIN. Try again.';
          _pin = '';
        });
        _shakeController.forward(from: 0);
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    final result =
        await ref.read(authControllerProvider.notifier).loginWithBiometrics();

    if (result && mounted) {
      context.go('/');
      return;
    }

    if (!mounted) return;
    setState(() {
      _showError = true;
      _errorMessage = ref.read(authControllerProvider).error ??
          'Biometric unlock is unavailable. Use PIN or email login.';
      _pin = '';
    });
    _shakeController.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _workspaceIdentity = _loadWorkspaceIdentity();
    _checkBiometric();

    _fadeAnimation = AnimationController(
      duration: DesignAnimation.normal,
      vsync: this,
    );

    _fadeAnimationValue = CurvedAnimation(
      parent: _fadeAnimation,
      curve: DesignAnimation.defaultCurve,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );

    _fadeAnimation.forward();
  }

  _WorkspaceIdentity _loadWorkspaceIdentity() {
    final storage = getIt<StorageService>();
    final user = storage.getUser();
    final tenant = user?['tenant'];
    final tenantMap =
        tenant is Map<String, dynamic> ? tenant : <String, dynamic>{};
    final companyName = _firstNonEmpty([
      tenantMap['name'],
      user?['tenantName'],
      storage.getTenantSlug(),
      'POS Workspace',
    ]);
    final companyCode = _firstNonEmpty([
      user?['tenantSlug'],
      tenantMap['slug'],
      storage.getTenantSlug(),
      'workspace',
    ]).toUpperCase();
    final branchName = _firstNonEmpty([
      user?['branchName'],
      _primaryBranchName(user?['branches']),
      'Default Branch',
    ]);
    final logoUrl = _firstNonEmptyOrNull([
      tenantMap['logoUrl'],
      tenantMap['logo'],
      user?['tenantLogoUrl'],
      user?['companyLogoUrl'],
    ]);

    return _WorkspaceIdentity(
      companyName: companyName,
      companyCode: companyCode,
      branchName: branchName,
      logoUrl: logoUrl,
    );
  }

  String _firstNonEmpty(List<Object?> values) {
    return _firstNonEmptyOrNull(values) ?? '';
  }

  String? _firstNonEmptyOrNull(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  String? _primaryBranchName(Object? branches) {
    if (branches is! List || branches.isEmpty) return null;
    final branchMaps = branches.whereType<Map>().toList();
    if (branchMaps.isEmpty) return null;
    final primary = branchMaps.firstWhere(
          (branch) => branch['isPrimary'] == true,
          orElse: () => branchMaps.first,
        );
    return primary['name']?.toString();
  }

  Future<void> _checkBiometric() async {
    final available =
        await ref.read(authControllerProvider.notifier).isBiometricAvailable();
    if (mounted) {
      setState(() => _biometricAvailable = available);
    }
  }

  @override
  void dispose() {
    _fadeAnimation.dispose();
    _pulseController.dispose();
    _shakeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 800;
    final buttonSize = isSmallScreen ? 54.0 : 64.0;
    final bottomPad = MediaQuery.of(context).padding.bottom;

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
              Colors.teal,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: isSmallScreen ? 4 : 12,
              bottom: bottomPad + 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header bar (compact)
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        child: Icon(Icons.arrow_back_rounded,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 18),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),

                SizedBox(height: isSmallScreen ? 8 : 24),

                // Logo
                FadeTransition(
                  opacity: _fadeAnimationValue,
                  child: _buildLogoSection(isSmallScreen),
                ),

                SizedBox(height: isSmallScreen ? 12 : 28),

                // PIN dots
                FadeTransition(
                  opacity: _fadeAnimationValue,
                  child: _buildPinDotsSection(isSmallScreen),
                ),

                SizedBox(height: isSmallScreen ? 8 : 16),

                // Error
                if (_showError)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildErrorBanner(),
                  ),

                // Loading
                if (authState.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),

                SizedBox(height: isSmallScreen ? 8 : 20),

                // Number pad
                FadeTransition(
                  opacity: _fadeAnimationValue,
                  child: _buildNumberPad(isSmallScreen, buttonSize),
                ),

                SizedBox(height: isSmallScreen ? 8 : 16),

                // Bottom links
                FadeTransition(
                  opacity: _fadeAnimationValue,
                  child: _buildBottomOptions(authState),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection(bool isSmallScreen) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = 1.0 + (_pulseController.value * 0.05);
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: isSmallScreen ? 56 : 68,
            height: isSmallScreen ? 56 : 68,
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
                color: Colors.white.withValues(alpha: 0.25),
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
              child: _buildWorkspaceMark(isSmallScreen ? 56 : 68),
            ),
          ),
        ),
        SizedBox(height: DesignSpacing.md),
        Text(
          _workspaceIdentity.companyName,
          style: TextStyle(
            fontSize: isSmallScreen ? 20 : 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildIdentityChip(
              Icons.badge_outlined,
              _workspaceIdentity.companyCode,
            ),
            _buildIdentityChip(
              Icons.storefront_outlined,
              _workspaceIdentity.branchName,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Enter your 4-digit PIN for this workspace',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.68),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildWorkspaceMark(double size) {
    final logoUrl = _workspaceIdentity.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return Image.network(
        logoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: '${_workspaceIdentity.companyName} logo',
        errorBuilder: (_, __, ___) => _buildInitialsMark(),
      );
    }
    return _buildInitialsMark();
  }

  Widget _buildInitialsMark() {
    return Container(
      color: Colors.white.withValues(alpha: 0.92),
      alignment: Alignment.center,
      child: Text(
        _workspaceIdentity.initials,
        style: const TextStyle(
          color: DesignColors.brand,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildIdentityChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.72), size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinDotsSection(bool isSmallScreen) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final outerMargin = isSmallScreen ? DesignSpacing.sm : DesignSpacing.lg;
    final horizontalPadding =
        isSmallScreen ? DesignSpacing.md : DesignSpacing.lg;
    final dotGap = isSmallScreen ? 4.0 : 6.0;
    final availableWidth =
        screenWidth - 40 - (outerMargin * 2) - (horizontalPadding * 2);
    final dotSize =
        ((availableWidth - (dotGap * (_pinLength - 1))) / _pinLength)
            .clamp(38.0, isSmallScreen ? 48.0 : 56.0)
            .toDouble();

    return GlassCard(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: isSmallScreen ? DesignSpacing.md : DesignSpacing.lg,
      ),
      margin: EdgeInsets.symmetric(horizontal: outerMargin),
      blur: 20,
      tint: Colors.white.withValues(alpha: 0.06),
      borderColor: _showError
          ? DesignColors.error.withValues(alpha: 0.4)
          : Colors.white.withValues(alpha: 0.1),
      borderRadius: DesignSpacing.radiusXl,
      child: AnimatedBuilder(
        animation: _shakeAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(
              _shakeAnimation.value *
                  16 *
                  (_shakeAnimation.value < 0.5 ? 1 : -1),
              0,
            ),
            child: child,
          );
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_pinLength, (index) {
            final isFilled = index < _pin.length;
            final isCurrentlyEntering = index == _pin.length;

            return Container(
              margin: EdgeInsets.only(
                right: index == _pinLength - 1 ? 0 : dotGap,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled
                      ? DesignColors.accent
                      : isCurrentlyEntering
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: isFilled
                        ? DesignColors.accent
                        : isCurrentlyEntering
                            ? DesignColors.accent.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.15),
                    width: isCurrentlyEntering ? 2.0 : 1.5,
                  ),
                  boxShadow: isFilled
                      ? [
                          BoxShadow(
                            color: DesignColors.accent.withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: isFilled
                    ? Icon(
                        Icons.circle_rounded,
                        size: 14,
                        color: Colors.white,
                      )
                    : isCurrentlyEntering
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: DesignColors.accent.withValues(alpha: 0.6),
                            ),
                          )
                        : null,
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: DesignSpacing.md,
        vertical: DesignSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: DesignColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(
          color: DesignColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: DesignColors.error.withValues(alpha: 0.9),
            size: 18,
          ),
          SizedBox(width: DesignSpacing.sm),
          Flexible(
            child: Text(
              _errorMessage.isNotEmpty
                  ? _errorMessage
                  : 'Invalid PIN. Try again.',
              style: TextStyle(
                color: DesignColors.error.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberPad(bool isSmallScreen, double buttonSize) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: 1 2 3
          _buildNumberPadRow(isSmallScreen, buttonSize, ['1', '2', '3']),
          SizedBox(height: DesignSpacing.md),

          // Row 2: 4 5 6
          _buildNumberPadRow(isSmallScreen, buttonSize, ['4', '5', '6']),
          SizedBox(height: DesignSpacing.md),

          // Row 3: 7 8 9
          _buildNumberPadRow(isSmallScreen, buttonSize, ['7', '8', '9']),
          SizedBox(height: DesignSpacing.md),

          // Row 4: clear 0 backspace
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildActionButton(
                icon: Icons.clear_all_rounded,
                onTap: _onClearPressed,
                size: buttonSize,
              ),
              SizedBox(width: DesignSpacing.md),
              _buildNumberButton('0', isSmallScreen, buttonSize),
              SizedBox(width: DesignSpacing.md),
              _buildActionButton(
                icon: Icons.backspace_outlined,
                onTap: _onBackspacePressed,
                size: buttonSize,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumberPadRow(
    bool isSmallScreen,
    double buttonSize,
    List<String> digits,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: digits
          .map((digit) => Padding(
                padding: EdgeInsets.symmetric(horizontal: DesignSpacing.sm),
                child: _buildNumberButton(digit, isSmallScreen, buttonSize),
              ))
          .toList(),
    );
  }

  Widget _buildNumberButton(
    String digit,
    bool isSmallScreen,
    double size,
  ) {
    final isLoading = ref.watch(authControllerProvider).isLoading;
    final fontSize = isSmallScreen ? 22.0 : 26.0;

    return GestureDetector(
      onTap: isLoading ? null : () => _onNumberPressed(digit),
      onTapDown: isLoading ? null : (_) => _scaleController.forward(),
      onTapUp: isLoading ? null : (_) => _scaleController.reverse(),
      onTapCancel: () => _scaleController.reverse(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            digit,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required double size,
  }) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.6),
            size: size * 0.35,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOptions(AuthState authState) {
    return Column(
      children: [
        if (_biometricAvailable) ...[
          GestureDetector(
            onTap: authState.isLoading ? null : _handleBiometricLogin,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fingerprint_rounded,
                    color: Colors.white.withValues(alpha: 0.82),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Use biometric unlock',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.86),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: DesignSpacing.md),
        ],
        // Back to email login
        GestureDetector(
          onTap: () => context.pop(),
          child: Text(
            'Use email instead',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: DesignColors.accent.withValues(alpha: 0.8),
              decoration: TextDecoration.underline,
              decorationColor: DesignColors.accent.withValues(alpha: 0.3),
            ),
          ),
        ),
        SizedBox(height: DesignSpacing.sm),

        // Version
        Text(
          'POS Workspace v2.0',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }
}
