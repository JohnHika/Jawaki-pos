import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/auth/presentation/desktop/pin_login_desktop_view.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/auth/presentation/widgets/sign_in_kit.dart';

class _WorkspaceIdentity {
  const _WorkspaceIdentity({
    required this.companyName,
    required this.branchName,
    this.logoUrl,
  });

  final String companyName;
  final String branchName;
  final String? logoUrl;
}

/// A person who can sign in on this phone.
class _Person {
  const _Person({required this.id, required this.name, required this.role});

  final String id;
  final String name;
  final String role;
}

/// PIN sign-in. On a phone shared by several people it first asks who is at
/// the till; otherwise it goes straight to the keypad.
class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen> {
  String _pin = '';
  static const int _minPinLength = 4;
  static const int _maxPinLength = 6;
  int? _configuredPinLength;
  bool? _hasLocalPin;
  bool _pinProfileLoading = true;
  late bool _isLockedSession;

  /// Who chose their name on a shared phone. The PIN is still what proves
  /// identity: if the PIN belongs to someone else the sign-in is undone.
  _Person? _selected;
  late final List<_Person> _people;

  int get _visiblePinLength {
    final configuredLength = _configuredPinLength;
    if (_hasLocalPin == true && configuredLength != null) {
      return configuredLength;
    }
    // Online PINs can be changed from another device, so a remembered server
    // length can be stale. Start with the four-digit minimum and grow the
    // indicators only as digits five and six are entered.
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
      final expectedId = _selected?.id;
      if (expectedId != null) {
        final signedInId =
            getIt<AuthService>().currentUser?['id']?.toString() ?? '';
        if (signedInId != expectedId) {
          await controller.logout();
          if (!mounted) return;
          setState(() {
            _showError = true;
            _errorMessage =
                'That PIN belongs to someone else. Check your name and try again.';
            _pin = '';
          });
          return;
        }
      }
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
    _people = _loadPeople();
    _checkBiometric();
    _loadAppVersion();
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

  _WorkspaceIdentity _loadWorkspaceIdentity() {
    final storage = getIt<StorageService>();
    final user = storage.getUser();
    final localWorkspace = storage.getLocalWorkspace();
    final localTenant = localWorkspace?['tenant'];
    final tenant = user?['tenant'] ?? localTenant;
    final tenantMap =
        tenant is Map<String, dynamic> ? tenant : <String, dynamic>{};
    final rememberedSlug = storage.getRememberedTenantSlug();
    final companyName = businessNameFrom(
      name: _firstNonEmptyOrNull([tenantMap['name'], user?['tenantName']]),
      code: _firstNonEmptyOrNull([
        storage.getTenantSlug(),
        rememberedSlug,
        user?['tenantSlug'],
        tenantMap['slug'],
      ]),
    );
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
      companyName: companyName.isEmpty ? 'Your workspace' : companyName,
      branchName: branchName,
      logoUrl: logoUrl,
    );
  }

  /// The owner plus every active staff account stored on this phone.
  List<_Person> _loadPeople() {
    final storage = getIt<StorageService>();
    if (!storage.hasLocalWorkspace()) return const [];
    final people = <_Person>[];
    final owner = storage.getLocalWorkspace()?['user'];
    if (owner is Map) {
      final id = owner['id']?.toString() ?? '';
      final name = _firstNonEmpty([
        owner['name'],
        '${owner['firstName'] ?? ''} ${owner['lastName'] ?? ''}',
        owner['email'],
        'Owner',
      ]);
      if (id.isNotEmpty) {
        people.add(_Person(id: id, name: name, role: 'Owner'));
      }
    }
    for (final account in storage.getLocalStaffAccounts()) {
      if (account['isActive'] == false) continue;
      final id = account['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      people.add(_Person(
        id: id,
        name: _firstNonEmpty([account['name'], 'Staff']),
        role: roleLabel(account['role']?.toString()),
      ));
    }
    return people;
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

  void _choosePerson(_Person? person) {
    setState(() {
      _selected = person;
      _pin = '';
      _showError = false;
    });
  }

  /// Computer window: split layout with a keypad that also answers the
  /// physical keyboard. Same state and sign-in calls as the phone layout.
  Widget _buildDesktop(bool pickingPerson) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading || _pinProfileLoading;
    final selected = _selected;
    final hasLocalWorkspace = getIt<StorageService>().hasLocalWorkspace();
    final hint = _pinProfileLoading
        ? 'Getting the keypad ready'
        : _hasActiveLocalTeam
            ? 'Enter your own 4 to 6 digit PIN'
            : _hasLocalPin == true && _configuredPinLength != null
                ? 'Enter your $_configuredPinLength digit PIN'
                : 'Enter your 4 to 6 digit PIN';
    PinDesktopPerson? asDesktop(_Person? person) => person == null
        ? null
        : PinDesktopPerson(id: person.id, name: person.name, role: person.role);
    return PinLoginDesktopView(
      companyName: _workspaceIdentity.companyName,
      branchName: _workspaceIdentity.branchName,
      logoUrl: _workspaceIdentity.logoUrl,
      people: [for (final person in _people) asDesktop(person)!],
      picking: pickingPerson,
      selected: asDesktop(selected),
      pinLength: _visiblePinLength,
      filled: _pin.length,
      showError: _showError,
      errorMessage: _errorMessage,
      loading: authState.isLoading,
      keypadEnabled: !isLoading,
      hint: hint,
      actionLabel: _isLockedSession ? 'Unlock' : 'Sign in',
      canSubmit: _isPinReady && !_pinProfileLoading,
      localWorkspace: hasLocalWorkspace,
      appVersion: _appVersion.isEmpty ? null : _appVersion,
      onDigit: _onNumberPressed,
      onBackspace: _onBackspacePressed,
      onClear: _onClearPressed,
      onSubmit: _submitPin,
      onChoosePerson: (person) => _choosePerson(
        person == null
            ? null
            : _people.firstWhere((candidate) => candidate.id == person.id),
      ),
      onBiometric: _biometricAvailable ? _handleBiometricLogin : null,
      onUsePassword: hasLocalWorkspace ? null : _useEmailInstead,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final pickingPerson =
        _hasActiveLocalTeam && _people.length > 1 && _selected == null;
    if (DesktopLayout.wantsShell(context)) return _buildDesktop(pickingPerson);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (palette.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: palette.page,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(22, 4, 22, bottomPad + 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - bottomPad - 12,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: pickingPerson
                        ? _buildPersonPicker(palette)
                        : _buildKeypadStep(palette),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Direction B: who is at the till?
  Widget _buildPersonPicker(SignInPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            BusinessMark(
              name: _workspaceIdentity.companyName,
              logoUrl: _workspaceIdentity.logoUrl,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _workspaceIdentity.companyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignType.display.copyWith(
                      color: palette.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _workspaceIdentity.branchName.isNotEmpty
                        ? '${_workspaceIdentity.branchName} · ${_people.length} people on this phone'
                        : '${_people.length} people on this phone',
                    style: TextStyle(color: palette.soft, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          'Who is at the till?',
          style: DesignType.display.copyWith(
            color: palette.ink,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Choose your name, then enter your PIN.',
          style: TextStyle(color: palette.soft, fontSize: 14),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final person in _people)
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 44 - 12 > 420
                        ? 420
                        : MediaQuery.sizeOf(context).width - 44 - 12) /
                    2,
                child: _PersonTile(
                  person: person,
                  palette: palette,
                  onTap: () => _choosePerson(person),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        if (!getIt<StorageService>().hasLocalWorkspace())
          SignInTextLink(
            label: 'Sign in with email instead',
            onPressed: _useEmailInstead,
          ),
        LegalConsent(palette: palette, action: 'signing in'),
        if (_appVersion.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _appVersion,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.faint, fontSize: 11),
            ),
          ),
      ],
    );
  }

  /// Direction A: the keypad.
  Widget _buildKeypadStep(SignInPalette palette) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading || _pinProfileLoading;
    final person = _selected;
    final actionLabel = _isLockedSession ? 'Unlock' : 'Sign in';
    final hint = _pinProfileLoading
        ? 'Getting the keypad ready'
        : _hasActiveLocalTeam
            ? 'Enter your own 4 to 6 digit PIN'
            : _hasLocalPin == true && _configuredPinLength != null
                ? 'Enter your $_configuredPinLength digit PIN'
                : 'Enter your 4 to 6 digit PIN';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: Align(
            alignment: Alignment.centerLeft,
            child: person != null
                ? TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: palette.ink,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => _choosePerson(null),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    label: const Text('Not you?'),
                  )
                : !getIt<StorageService>().hasLocalWorkspace()
                    ? IconButton(
                        tooltip: 'Use email instead',
                        color: palette.ink,
                        onPressed: _useEmailInstead,
                        icon: const Icon(Icons.arrow_back_rounded),
                      )
                    : null,
          ),
        ),
        const SizedBox(height: 4),
        Column(
          children: [
            if (person != null)
              _Avatar(name: person.name, size: 60, selected: true)
            else
              BusinessMark(
                name: _workspaceIdentity.companyName,
                logoUrl: _workspaceIdentity.logoUrl,
                size: 60,
              ),
            const SizedBox(height: 12),
            Text(
              person?.name ?? _workspaceIdentity.companyName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: DesignType.display.copyWith(
                color: palette.ink,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              person != null && person.role.isNotEmpty
                  ? '${person.role} · enter your PIN'
                  : hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.soft, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 22),
        PinDots(
          length: _visiblePinLength,
          filled: _pin.length,
          error: _showError,
        ),
        SizedBox(
          height: 44,
          child: Center(
            child: _showError
                ? Text(
                    _errorMessage.isNotEmpty
                        ? _errorMessage
                        : 'Invalid PIN. Try again.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: DesignColors.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : authState.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
          ),
        ),
        PinKeypad(
          enabled: !isLoading,
          onDigit: _onNumberPressed,
          onClear: _onClearPressed,
          onBackspace: _onBackspacePressed,
        ),
        const SizedBox(height: 16),
        SignInButton(
          label: actionLabel,
          loading: authState.isLoading,
          onPressed: _isPinReady && !_pinProfileLoading ? _submitPin : null,
        ),
        const SizedBox(height: 4),
        if (_biometricAvailable)
          SignInTextLink(
            label: 'Use biometric unlock',
            onPressed: authState.isLoading ? null : _handleBiometricLogin,
          ),
        if (!getIt<StorageService>().hasLocalWorkspace())
          SignInTextLink(
            label: 'Sign in with email instead',
            onPressed: _useEmailInstead,
          ),
        LegalConsent(palette: palette, action: 'signing in'),
        if (_appVersion.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _appVersion,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.faint, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 40, this.selected = false});

  final String name;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? DesignColors.accent : palette.field,
      ),
      child: Text(
        initialsFor(name),
        style: DesignType.display.copyWith(
          color: selected ? SignInPalette.onAccent : palette.ink,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.palette,
    required this.onTap,
  });

  final _Person person;
  final SignInPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${person.name}, ${person.role}',
      excludeSemantics: true,
      child: Material(
        color: palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          side: BorderSide(color: palette.line),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          ),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 112),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(name: person.name),
                const SizedBox(height: 12),
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (person.role.isNotEmpty)
                  Text(
                    person.role,
                    style: TextStyle(color: palette.soft, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
