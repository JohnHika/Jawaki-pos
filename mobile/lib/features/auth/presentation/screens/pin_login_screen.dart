import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/core/widgets/motion.dart';
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
  static const int _minPinLength = 4;
  static const int _maxPinLength = 6;

  late AnimationController _pulseController;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  bool _showError = false;
  String _errorMessage = '';
  late final _WorkspaceIdentity _workspaceIdentity;
  bool _biometricAvailable = false;
  String _appVersion = '';

  void _onNumberPressed(String number) {
    if (_pin.length >= _maxPinLength) return;

    setState(() {
      _pin += number;
      _showError = false;
    });
  }

  void _submitPin() {
    if (_pin.length < _minPinLength) {
      setState(() {
        _showError = true;
        _errorMessage = 'Enter at least 4 digits to continue.';
      });
      _shakeController.forward(from: 0);
      return;
    }
    _handlePinLogin();
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
    final controller = ref.read(authControllerProvider.notifier);

    // A device with a local PIN configured can unlock entirely offline,
    // matching biometric unlock. Only fall back to the server-authenticated
    // PIN login for a device that has never set one up locally.
    final hasLocalPin = await controller.hasLocalPinSet();
    final result = hasLocalPin
        ? await controller.unlockWithPin(_pin)
        : await controller.loginWithPin(_pin);

    if (result && mounted) {
      // Only the network-authenticated path is a genuine fresh login —
      // unlockWithPin just re-enters an already-authenticated session
      // entirely offline, so it must not trigger a network-dependent
      // mandatory update check.
      if (!hasLocalPin) {
        unawaited(getIt<UpdateCheckService>().checkAfterLogin());
      }
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

  /// Leaves quick-unlock for the full email login form. When this screen
  /// was pushed on top of /login (the user chose PIN from there), simply
  /// popping returns them. But a locked session lands here directly as the
  /// router's root screen with nothing to pop to — in that case, "use
  /// email instead" means the user doesn't want to unlock this session at
  /// all, so it must log out first (clearing the lock) or the router's
  /// locked-session guard would just bounce them straight back here.
  Future<void> _useEmailInstead() async {
    if (context.canPop()) {
      context.pop();
      return;
    }
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  void initState() {
    super.initState();
    _workspaceIdentity = _loadWorkspaceIdentity();
    _checkBiometric();
    _loadAppVersion();

    _pulseController = AnimationController(
      vsync: this,
      duration: DesignAnimation.slower,
    );

    _shakeController = AnimationController(
      vsync: this,
      duration: DesignAnimation.slow,
    );

    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    _pulseController.repeat(reverse: true);
  }

  // The logo pulse is an infinite loop: only run it when the OS
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
    final ready =
        await ref.read(authControllerProvider.notifier).isBiometricAvailable();
    final enabled = getIt<StorageService>().isBiometricEnabled();
    if (mounted) {
      setState(() => _biometricAvailable = ready && enabled);
    }
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _appVersion = 'POS Workspace v${info.version}');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 800;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: DesignColors.darkBg,
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
                    Semantics(
                      label: 'Use email instead',
                      button: true,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _useEmailInstead,
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(Icons.arrow_back_rounded,
                                color: Colors.white.withValues(alpha: 0.7),
                                size: DesignSpacing.lg + 2),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),

                SizedBox(height: isSmallScreen ? DesignSpacing.sm : DesignSpacing.xl),

                // Logo — first-mount stagger (see StaggeredItem)
                StaggeredItem(
                  itemKey: 'pin-logo',
                  child: _buildLogoSection(isSmallScreen),
                ),

                SizedBox(
                    height: isSmallScreen
                        ? DesignSpacing.md
                        : DesignSpacing.xxl + 4),

                // PIN dots
                StaggeredItem(
                  itemKey: 'pin-dots',
                  index: 1,
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
                StaggeredItem(
                  itemKey: 'pin-numpad',
                  index: 2,
                  child: _buildNumberPad(isSmallScreen),
                ),

                SizedBox(
                    height: isSmallScreen ? DesignSpacing.sm : DesignSpacing.lg),

                // Bottom links
                StaggeredItem(
                  itemKey: 'pin-options',
                  index: 3,
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
              color: DesignColors.darkSurfaceElevated,
              border: Border.all(
                color: DesignColors.accent.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: _buildWorkspaceMark(isSmallScreen ? 56 : 68),
            ),
          ),
        ),
        const SizedBox(height: DesignSpacing.md),
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
          'Enter your 4–6 digit PIN for this workspace',
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
    final slotGap = isSmallScreen ? 5.0 : 8.0;
    final availableWidth =
        screenWidth - 40 - (outerMargin * 2) - (horizontalPadding * 2);
    final slotWidth =
        ((availableWidth - (slotGap * (_maxPinLength - 1))) / _maxPinLength)
            .clamp(38.0, isSmallScreen ? 48.0 : 54.0)
            .toDouble();
    final isReady = _pin.length >= _minPinLength;

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          _shakeAnimation.value * 14 *
              (_shakeAnimation.value < 0.5 ? 1 : -1),
          0,
        ),
        child: child,
      ),
      child: GlassCard(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: isSmallScreen ? DesignSpacing.md : DesignSpacing.lg,
        ),
        margin: EdgeInsets.symmetric(horizontal: outerMargin),
        blur: 24,
        tint: Colors.white.withValues(alpha: 0.055),
        borderColor: _showError
            ? DesignColors.error.withValues(alpha: 0.48)
            : isReady
                ? DesignColors.accent.withValues(alpha: 0.46)
                : Colors.white.withValues(alpha: 0.12),
        borderRadius: DesignSpacing.radiusXl,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_maxPinLength, (index) {
                final isFilled = index < _pin.length;
                final isActive = index == _pin.length && _pin.length < _maxPinLength;
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == _maxPinLength - 1 ? 0 : slotGap,
                  ),
                  child: AnimatedScale(
                    duration: DesignAnimation.fast,
                    curve: Curves.easeOutBack,
                    scale: isFilled ? 1 : (isActive ? 1.03 : 0.96),
                    child: AnimatedContainer(
                      duration: DesignAnimation.fast,
                      curve: Curves.easeOutCubic,
                      width: slotWidth,
                      height: isSmallScreen ? 46 : 52,
                      decoration: BoxDecoration(
                        gradient: isFilled
                            ? const LinearGradient(
                                colors: [DesignColors.brand, DesignColors.accent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isFilled
                            ? null
                            : isActive
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.white.withValues(alpha: 0.045),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isFilled
                              ? DesignColors.accent.withValues(alpha: 0.9)
                              : isActive
                                  ? DesignColors.accent.withValues(alpha: 0.7)
                                  : Colors.white.withValues(alpha: 0.1),
                          width: isActive ? 1.6 : 1,
                        ),
                        boxShadow: isFilled
                            ? [
                                BoxShadow(
                                  color: DesignColors.accent.withValues(alpha: 0.24),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: AnimatedSwitcher(
                        duration: DesignAnimation.fast,
                        switchInCurve: Curves.easeOutBack,
                        child: isFilled
                            ? const Icon(
                                Icons.circle_rounded,
                                key: ValueKey('filled'),
                                color: Colors.white,
                                size: 13,
                              )
                            : Text(
                                '${index + 1}',
                                key: ValueKey('empty-$index'),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.28),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: DesignSpacing.md),
            AnimatedSwitcher(
              duration: DesignAnimation.fast,
              child: Text(
                isReady
                    ? 'Ready to unlock'
                    : '${_pin.length} of 4–6 digits',
                key: ValueKey(isReady),
                style: TextStyle(
                  color: isReady
                      ? DesignColors.accent
                      : Colors.white.withValues(alpha: 0.56),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(
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
          const SizedBox(width: DesignSpacing.sm),
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

  Widget _buildNumberPad(bool isSmallScreen) {
    final isReady = _pin.length >= _minPinLength;
    final isLoading = ref.watch(authControllerProvider).isLoading;
    final keyWidth = isSmallScreen ? 76.0 : 86.0;
    final keyHeight = isSmallScreen ? 52.0 : 60.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildNumberPadRow(keyWidth, keyHeight, ['1', '2', '3']),
        const SizedBox(height: DesignSpacing.sm),
        _buildNumberPadRow(keyWidth, keyHeight, ['4', '5', '6']),
        const SizedBox(height: DesignSpacing.sm),
        _buildNumberPadRow(keyWidth, keyHeight, ['7', '8', '9']),
        const SizedBox(height: DesignSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildActionButton(
              icon: Icons.clear_all_rounded,
              tooltip: 'Clear PIN',
              onTap: _onClearPressed,
              width: keyWidth,
              height: keyHeight,
            ),
            const SizedBox(width: DesignSpacing.sm),
            _buildNumberButton('0', keyWidth, keyHeight),
            const SizedBox(width: DesignSpacing.sm),
            _buildActionButton(
              icon: Icons.backspace_outlined,
              tooltip: 'Delete digit',
              onTap: _onBackspacePressed,
              width: keyWidth,
              height: keyHeight,
            ),
          ],
        ),
        const SizedBox(height: DesignSpacing.lg),
        Semantics(
          label: 'Unlock workspace',
          button: true,
          child: AnimatedContainer(
            duration: DesignAnimation.fast,
            curve: Curves.easeOutCubic,
            width: (keyWidth * 3) + (DesignSpacing.sm * 2),
            height: 52,
            decoration: BoxDecoration(
              gradient: isReady
                  ? const LinearGradient(
                      colors: [DesignColors.brand, DesignColors.accent],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: isReady ? null : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isReady
                    ? DesignColors.accent.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.12),
              ),
              boxShadow: isReady
                  ? [
                      BoxShadow(
                        color: DesignColors.accent.withValues(alpha: 0.26),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isReady && !isLoading ? _submitPin : null,
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_open_rounded,
                              color: isReady
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.35),
                              size: 20,
                            ),
                            const SizedBox(width: DesignSpacing.sm),
                            Text(
                              'Unlock workspace',
                              style: TextStyle(
                                color: isReady
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.35),
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNumberPadRow(
    double keyWidth,
    double keyHeight,
    List<String> digits,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: digits
          .map((digit) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: DesignSpacing.xs),
                child: _buildNumberButton(digit, keyWidth, keyHeight),
              ))
          .toList(),
    );
  }

  Widget _buildNumberButton(String digit, double width, double height) {
    final isLoading = ref.watch(authControllerProvider).isLoading;
    return Semantics(
      label: 'PIN digit $digit',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : () => _onNumberPressed(digit),
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.075),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Center(
              child: Text(
                digit,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required double width,
    required double height,
  }) {
    final isLoading = ref.watch(authControllerProvider).isLoading;
    return Semantics(
      label: tooltip,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Center(
              child: Icon(
                icon,
                color: Colors.white.withValues(alpha: 0.68),
                size: 21,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOptions(AuthState authState) {
    return Column(
      children: [
        if (_biometricAvailable) ...[
          Semantics(
            button: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: authState.isLoading ? null : _handleBiometricLogin,
                borderRadius:
                    BorderRadius.circular(DesignSpacing.radiusFull),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignSpacing.lg - 2,
                    vertical: DesignSpacing.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(DesignSpacing.radiusFull),
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
                        size: DesignSpacing.xl,
                      ),
                      const SizedBox(width: DesignSpacing.sm),
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
            ),
          ),
          const SizedBox(height: DesignSpacing.md),
        ],
        // Back to email login — TextButton so the target is 48px and
        // the tap gets standard Material feedback (was a bare text tap).
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 48),
          ),
          onPressed: _useEmailInstead,
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
        const SizedBox(height: DesignSpacing.sm),

        // Version
        if (_appVersion.isNotEmpty)
          Text(
            _appVersion,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.25),
            ),
          ),
      ],
    );
  }
}
