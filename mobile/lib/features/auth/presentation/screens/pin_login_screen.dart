import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../../core/widgets/motion_kit_extras.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/core/widgets/workspace_image.dart';
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
  int? _configuredPinLength;
  bool? _hasLocalPin;
  bool _pinProfileLoading = true;
  late bool _isLockedSession;

  int get _visiblePinLength {
    final configuredLength = _configuredPinLength;
    if (_hasLocalPin == true && configuredLength != null) {
      return configuredLength;
    }
    // Online PINs can be changed from another device, so a remembered server
    // length can be stale. Start with the four-digit minimum and grow the
    // indicators only as digits five and six are entered. A four-digit PIN
    // therefore never sits in a six-slot row.
    return _pin.length > _minPinLength
        ? _pin.length.clamp(_minPinLength, _maxPinLength).toInt()
        : _minPinLength;
  }

  int get _inputLimit => _hasLocalPin == true && _configuredPinLength != null
      ? _configuredPinLength!
      : _maxPinLength;

  bool get _isPinReady => _hasLocalPin == true && _configuredPinLength != null
      ? _pin.length == _configuredPinLength
      : _pin.length >= _minPinLength;

  bool get _hasActiveLocalTeam {
    final storage = getIt<StorageService>();
    return storage.hasLocalWorkspace() &&
        storage
            .getLocalStaffAccounts()
            .any((account) => account['isActive'] != false);
  }

  late AnimationController _pulseController;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  bool _showError = false;
  String _errorMessage = '';
  late final _WorkspaceIdentity _workspaceIdentity;
  bool _biometricAvailable = false;
  bool _autoBiometricAttempted = false;
  String _appVersion = '';

  void _onNumberPressed(String number) {
    if (_pinProfileLoading || _pin.length >= _inputLimit) return;

    setState(() {
      _pin += number;
      _showError = false;
    });
  }

  void _submitPin() {
    if (_pinProfileLoading) return;
    if (_pin.length < _minPinLength ||
        (_hasLocalPin == true &&
            _configuredPinLength != null &&
            _pin.length != _configuredPinLength)) {
      setState(() {
        _showError = true;
        _errorMessage = _hasLocalPin != true || _configuredPinLength == null
            ? 'Enter at least 4 digits to continue.'
            : 'Enter all $_configuredPinLength digits to continue.';
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

    // A local quick-unlock PIN belongs to an existing locked session. It
    // must not intercept signed-out PIN login after logout, because logout
    // intentionally preserves this hash for future quick unlocks.
    final isLockedSession = ref.read(authControllerProvider).isLocked;
    final hasLocalPin = isLockedSession && await controller.hasLocalPinSet();
    final hasLocalWorkspace = getIt<StorageService>().hasLocalWorkspace();
    final localAuthentication = hasLocalPin || hasLocalWorkspace;
    final updates = getIt<UpdateCheckService>();
    if (!localAuthentication) updates.beginPostLoginCheck();
    final result = hasLocalPin
        ? await controller.unlockWithPin(_pin)
        : await controller.loginWithPin(_pin);
    if (!result && !localAuthentication) updates.cancelPostLoginCheck();

    if (result && mounted) {
      // Only the network-authenticated path is a genuine fresh login —
      // unlockWithPin just re-enters an already-authenticated session
      // entirely offline, so it must not trigger a network-dependent
      // mandatory update check.
      if (!localAuthentication) {
        await getIt<UpdateCheckService>().checkAfterLogin();
        if (!mounted) return;
      }
      _openConfiguredStartScreen();
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
      _openConfiguredStartScreen();
      return;
    }

    if (!mounted) return;
    setState(() {
      _showError = true;
      _errorMessage = ref.read(authControllerProvider).error ??
          (getIt<StorageService>().hasLocalWorkspace()
              ? 'Biometric unlock is unavailable. Enter your device PIN instead.'
              : 'Biometric sign-in is unavailable. Enter your PIN or choose another sign-in method.');
      _pin = '';
    });
    _shakeController.forward(from: 0);
  }

  void _openConfiguredStartScreen() {
    // Let the router apply the shop's saved start path, role permissions, and
    // first-login staff tour instead of sending every successful unlock to POS.
    context.go('/login');
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
    _isLockedSession = ref.read(authControllerProvider).isLocked;
    unawaited(_loadConfiguredPinLength());
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

  }

  Future<void> _loadConfiguredPinLength() async {
    try {
      final storage = getIt<StorageService>();
      final isLockedSession = ref.read(authControllerProvider).isLocked;
      final hasLocalPin = (isLockedSession || storage.hasLocalWorkspace()) &&
          await storage.hasLocalPinSet();
      final length = hasLocalPin && !_hasActiveLocalTeam
          ? await storage.getConfiguredPinLength()
          : null;
      if (mounted) {
        setState(() {
          _isLockedSession = isLockedSession;
          _configuredPinLength = length;
          _hasLocalPin = hasLocalPin;
          _pinProfileLoading = false;
          if (hasLocalPin && length != null && _pin.length > length) {
            _pin = '';
            _showError = true;
            _errorMessage =
                'Your PIN has $length digits. Please enter it again.';
          }
        });
      }
    } catch (_) {
      // Unknown-length entry remains usable and expands as the user types.
      // Storage must never prevent PIN login.
      if (mounted) setState(() => _pinProfileLoading = false);
    }
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

  /// Text/outline colour for this screen: white on the dark theme, the
  /// normal dark ink on the (default) light theme.
  Color get _fg => Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : DesignColors.textPrimary;

  _WorkspaceIdentity _loadWorkspaceIdentity() {
    final storage = getIt<StorageService>();
    final user = storage.getUser();
    final localWorkspace = storage.getLocalWorkspace();
    final localTenant = localWorkspace?['tenant'];
    final tenant = user?['tenant'] ?? localTenant;
    final tenantMap =
        tenant is Map<String, dynamic> ? tenant : <String, dynamic>{};
    final rememberedSlug = storage.getRememberedTenantSlug();
    final companyName = _firstNonEmpty([
      tenantMap['name'],
      user?['tenantName'],
      _titleFromSlug(storage.getTenantSlug()),
      _titleFromSlug(rememberedSlug),
      'Your workspace',
    ]);
    final companyCode = _firstNonEmpty([
      user?['tenantSlug'],
      tenantMap['slug'],
      storage.getTenantSlug(),
      rememberedSlug,
      'workspace',
    ]).toUpperCase();
    final branchName = _firstNonEmpty([
      user?['branchName'],
      _primaryBranchName(user?['branches']),
      (localWorkspace?['branch'] as Map?)?['name'],
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

  /// "mama-njeri" -> "Mama Njeri".
  String? _titleFromSlug(String? slug) {
    final text = slug?.trim() ?? '';
    if (text.isEmpty) return null;
    return text
        .split(RegExp(r'[-_\s]+'))
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
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
    final storage = getIt<StorageService>();
    final enabled = storage.isBiometricEnabled();
    if (mounted) {
      setState(() => _biometricAvailable = ready && enabled);
      if (ready &&
          enabled &&
          storage.getPrimaryLoginMethod() == 'biometric' &&
          !_autoBiometricAttempted) {
        _autoBiometricAttempted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_handleBiometricLogin());
        });
      }
    }
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _appVersion = 'Counterbase v${info.version}');
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

    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final pageColor = context.themed(DesignColors.darkBg);
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: (isDarkTheme
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false),
        child: Scaffold(
          backgroundColor: pageColor,
          body: Container(
            width: double.infinity,
            height: double.infinity,
            color: pageColor,
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
                        if (!getIt<StorageService>().hasLocalWorkspace()) ...[
                          Semantics(
                            label: 'Use email instead',
                            button: true,
                            child: AppBackButton(
                              background: context.themed(DesignColors.darkBg),
                              color: _fg,
                              isDark: Theme.of(context).brightness ==
                                  Brightness.dark,
                              onPressed: _useEmailInstead,
                            ),
                          ),
                        ],
                        const Spacer(),
                      ],
                    ),

                    SizedBox(
                        height: isSmallScreen
                            ? DesignSpacing.sm
                            : DesignSpacing.xl),

                    // Logo — first-mount stagger (see StaggeredItem)
                    StaggeredItem(
                      itemKey: 'pin-logo',
                      child: AuthEntrance(
                        child: _buildLogoSection(isSmallScreen),
                      ),
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
                        height: isSmallScreen
                            ? DesignSpacing.sm
                            : DesignSpacing.lg),

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
        ));
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
              color: context.themed(DesignColors.darkSurfaceElevated),
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
        BlurIn(
          delay: const Duration(milliseconds: 120),
          child: Text(
            _workspaceIdentity.companyName,
            style: TextStyle(
              fontSize: isSmallScreen ? 20 : 24,
              fontWeight: FontWeight.w700,
              color: _fg,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
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
            if (_workspaceIdentity.branchName.isNotEmpty)
              _buildIdentityChip(
                Icons.storefront_outlined,
                _workspaceIdentity.branchName,
              ),
          ],
        ),
        const SizedBox(height: 10),
        WipeIn(
          alignment: Alignment.center,
          delay: const Duration(milliseconds: 320),
          child: Text(
            _pinProfileLoading
                ? 'Preparing your secure keypad…'
                : _hasActiveLocalTeam
                    ? 'Enter your own 4–6 digit team PIN'
                    : _hasLocalPin == true && _configuredPinLength != null
                        ? 'Enter your $_configuredPinLength-digit device PIN'
                        : 'Enter your 4–6 digit PIN',
            style: TextStyle(
              fontSize: 13,
              color: _fg.withValues(alpha: 0.68),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceMark(double size) {
    final logoUrl = _workspaceIdentity.logoUrl;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return Semantics(
        image: true,
        label: '${_workspaceIdentity.companyName} logo',
        child: WorkspaceImage(
          source: logoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: _buildInitialsMark(),
        ),
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
        color: _fg.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _fg.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _fg.withValues(alpha: 0.72), size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: _fg.withValues(alpha: 0.82),
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
    final slotGap = isSmallScreen ? (screenWidth < 360 ? 3.0 : 5.0) : 8.0;
    final slotCount = _visiblePinLength;
    final availableWidth =
        // -2 for the card's 1dp border on each side (it used to overflow by 2px)
        screenWidth - 40 - (outerMargin * 2) - (horizontalPadding * 2) - 4;
    final slotWidth =
        ((availableWidth - (slotGap * (slotCount - 1))) / slotCount)
            .clamp(30.0, isSmallScreen ? 48.0 : 54.0)
            .toDouble();
    final isReady = !_pinProfileLoading && _isPinReady;
    final String statusText;
    if (_pinProfileLoading) {
      statusText = 'Preparing your secure keypad…';
    } else if (_hasLocalPin == true && _configuredPinLength != null) {
      statusText = isReady
          ? 'Ready to unlock'
          : '${_pin.length} of $_configuredPinLength digits';
    } else if (_pin.length < _minPinLength) {
      statusText = '${_pin.length} of $_minPinLength digits';
    } else if (_pin.length == _minPinLength) {
      statusText = _isLockedSession
          ? 'Ready to unlock · add digits if your PIN is longer'
          : 'Ready to continue · add digits if your PIN is longer';
    } else if (_pin.length < _maxPinLength) {
      statusText = '${_pin.length} digits entered · add one more if needed';
    } else {
      statusText = _isLockedSession ? 'Ready to unlock' : 'Ready to continue';
    }

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          _shakeAnimation.value * 14 * (_shakeAnimation.value < 0.5 ? 1 : -1),
          0,
        ),
        child: child,
      ),
      // This screen is always dark. A themed GlassCard turns solid white in
      // light mode, which made the white-tinted PIN slots and the digit counter
      // invisible, so the card is drawn explicitly here.
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: isSmallScreen ? DesignSpacing.md : DesignSpacing.lg,
        ),
        margin: EdgeInsets.symmetric(horizontal: outerMargin),
        decoration: BoxDecoration(
          color: _fg.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
          border: Border.all(
            color: _showError
                ? DesignColors.error.withValues(alpha: 0.48)
                : isReady
                    ? DesignColors.accent.withValues(alpha: 0.46)
                    : _fg.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          children: [
            AnimatedSize(
              duration: DesignAnimation.fast,
              curve: Curves.easeOutCubic,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(slotCount, (index) {
                  final isFilled = index < _pin.length;
                  final isActive =
                      index == _pin.length && _pin.length < slotCount;
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == slotCount - 1 ? 0 : slotGap,
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
                                  colors: [
                                    DesignColors.brand,
                                    DesignColors.accent,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isFilled
                              ? null
                              : isActive
                                  ? _fg.withValues(alpha: 0.12)
                                  : _fg.withValues(alpha: 0.045),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isFilled
                                ? DesignColors.accent.withValues(alpha: 0.9)
                                : isActive
                                    ? DesignColors.accent.withValues(alpha: 0.7)
                                    : _fg.withValues(alpha: 0.1),
                            width: isActive ? 1.6 : 1,
                          ),
                          boxShadow: isFilled
                              ? [
                                  BoxShadow(
                                    color: DesignColors.accent
                                        .withValues(alpha: 0.24),
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
                              ? Icon(
                                  Icons.circle_rounded,
                                  key: const ValueKey('filled'),
                                  color: _fg,
                                  size: 13,
                                )
                              : Text(
                                  '${index + 1}',
                                  key: ValueKey('empty-$index'),
                                  style: TextStyle(
                                    color: _fg.withValues(alpha: 0.28),
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
            ),
            const SizedBox(height: DesignSpacing.md),
            AnimatedSwitcher(
              duration: DesignAnimation.fast,
              child: Text(
                statusText,
                key: ValueKey(statusText),
                style: TextStyle(
                  color: isReady
                      ? DesignColors.accent
                      : _fg.withValues(alpha: 0.56),
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
    final isReady = !_pinProfileLoading && _isPinReady;
    final isLoading =
        ref.watch(authControllerProvider).isLoading || _pinProfileLoading;
    final actionLabel = _isLockedSession ? 'Unlock workspace' : 'Sign in';
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
          label: actionLabel,
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
              color: isReady ? null : _fg.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isReady
                    ? DesignColors.accent.withValues(alpha: 0.7)
                    : _fg.withValues(alpha: 0.12),
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
                                  : _fg.withValues(alpha: 0.35),
                              size: 20,
                            ),
                            const SizedBox(width: DesignSpacing.sm),
                            Text(
                              actionLabel,
                              style: TextStyle(
                                color: isReady
                                    ? Colors.white
                                    : _fg.withValues(alpha: 0.35),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: DesignSpacing.xs),
                child: _buildNumberButton(digit, keyWidth, keyHeight),
              ))
          .toList(),
    );
  }

  Widget _buildNumberButton(String digit, double width, double height) {
    final isLoading =
        ref.watch(authControllerProvider).isLoading || _pinProfileLoading;
    return Semantics(
      label: 'PIN digit $digit',
      button: true,
      enabled: !isLoading,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : () => _onNumberPressed(digit),
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: _fg.withValues(alpha: 0.075),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _fg.withValues(alpha: 0.12)),
            ),
            child: Center(
              child: Text(
                digit,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _fg,
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
    required VoidCallback? onTap,
    required double width,
    required double height,
  }) {
    final isLoading =
        ref.watch(authControllerProvider).isLoading || _pinProfileLoading;
    return Semantics(
      label: tooltip,
      button: true,
      enabled: !isLoading,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: _fg.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _fg.withValues(alpha: 0.09)),
            ),
            child: Center(
              child: Icon(
                icon,
                color: _fg.withValues(alpha: 0.68),
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
          AuthEntrance(
            child: Semantics(
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: authState.isLoading ? null : _handleBiometricLogin,
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusFull),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignSpacing.lg - 2,
                      vertical: DesignSpacing.sm + 2,
                    ),
                    decoration: BoxDecoration(
                      color: _fg.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusFull),
                      border: Border.all(
                        color: _fg.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fingerprint_rounded,
                          color: _fg.withValues(alpha: 0.82),
                          size: DesignSpacing.xl,
                        ),
                        const SizedBox(width: DesignSpacing.sm),
                        Text(
                          'Use biometric unlock',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _fg.withValues(alpha: 0.86),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: DesignSpacing.md),
        ],
        if (!getIt<StorageService>().hasLocalWorkspace())
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
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
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DesignSpacing.sm),
            child: Text(
              getIt<AuthService>().hasActiveLocalStaff
                  ? 'Shared register · each staff member signs in with their own PIN'
                  : _biometricAvailable
                      ? 'Local workspace · use your PIN or biometric unlock'
                      : 'Local workspace · PIN access',
              style: TextStyle(
                fontSize: 12,
                color: _fg.withValues(alpha: 0.55),
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
              color: _fg.withValues(alpha: 0.25),
            ),
          ),
      ],
    );
  }
}
