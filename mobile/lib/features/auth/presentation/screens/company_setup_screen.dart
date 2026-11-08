import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/auth/local_staff_roles.dart';
import 'package:axon_pos/core/legal/policy_catalog.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/providers/local_workspace_capabilities.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/core/widgets/motion.dart';
import 'package:axon_pos/features/auth/presentation/widgets/sign_in_kit.dart';
import 'package:axon_pos/core/widgets/modal_disposal.dart';

/// Lets the setup screen keep the person on it for the moment between the
/// shop being created (which signs them in) and them opening it. Without it
/// the router would send every signed-in person straight to the dashboard and
/// the "Your shop is ready" screen would never show.
class SetupSession {
  const SetupSession._();
  static bool holdReady = false;
}

/// Creates the first workspace locally on this device. The owner's PIN is
/// protected by platform secure storage and no identity or business data is
/// sent to an online POS service.
class CompanySetupScreen extends ConsumerStatefulWidget {
  const CompanySetupScreen({super.key, this.join = false});

  /// True when this phone is being added to a shop that already exists.
  /// The shop is created empty and the owner is pointed at the backup
  /// restore, which is how records reach a second phone.
  final bool join;

  @override
  ConsumerState<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends ConsumerState<CompanySetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _setupScrollController = ScrollController();
  final _companyNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _branchCodeController = TextEditingController();
  final _branchAddressController = TextEditingController();
  final _branchPhoneController = TextEditingController();
  final _ownerPinController = TextEditingController();
  final _confirmOwnerPinController = TextEditingController();
  int _currentStep = 0;
  bool _isLoading = false;
  bool _acceptedLocalDataNotice = false;
  String _businessLayoutId = 'general_retail';
  final List<String> _additionalBusinessLayoutIds = [];
  List<String> _posQuickActions =
      businessLayoutDefaultPosQuickActions('general_retail', const []);
  String? _errorMessage;
  bool _showPin = false;
  String _sellingMode = 'solo';
  final List<_StaffDraft> _team = [];
  bool _created = false;
  String _createdName = '';
  final List<String> _teamIssues = [];

  List<_SetupStep> get _steps => [
        _SetupStep.business,
        _SetupStep.sell,
        if (_sellingMode != 'solo') _SetupStep.team,
        _SetupStep.pin,
      ];

  @override
  void initState() {
    super.initState();
    // A standalone install starts with one location. Give it a clear, usable
    // default so owners are not forced to invent an internal branch code.
    _branchNameController.text = 'Main location';
    _branchCodeController.text = 'MAIN';
  }

  @override
  void dispose() {
    for (final controller in [
      _companyNameController,
      _firstNameController,
      _lastNameController,
      _emailController,
      _branchNameController,
      _branchCodeController,
      _branchAddressController,
      _branchPhoneController,
      _ownerPinController,
      _confirmOwnerPinController,
    ]) {
      controller.dispose();
    }
    _setupScrollController.dispose();
    super.dispose();
  }

  WorkspaceCreationRequest _workspaceRequest() {
    final preset = businessLayoutPreset(_businessLayoutId);
    final priorityPaths = businessLayoutDefaultPriorityPaths(
      _businessLayoutId,
      _additionalBusinessLayoutIds,
    );
    return WorkspaceCreationRequest(
      companyName: _companyNameController.text.trim(),
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      deviceId: getIt<AuthService>().deviceId,
      branch: WorkspaceBranchDetails(
        name: _branchNameController.text.trim(),
        code: _optional(_branchCodeController)?.toUpperCase(),
        address: _optional(_branchAddressController),
        phone: _optional(_branchPhoneController),
        email: _emailController.text.trim(),
      ),
      // Local setup records the explicit local-data notice instead of
      // pretending that remote signup policies were accepted.
      acceptedPolicyTypes: const [],
      settings: {
        'businessLayout': BusinessLayoutConfig(
          preset: preset,
          additionalProfileIds: _additionalBusinessLayoutIds,
          priorityPaths: priorityPaths,
          hiddenPaths: _businessLayoutHiddenPaths(),
          startPath: priorityPaths.firstOrNull,
          posQuickActions: _posQuickActions,
          showPosFavorites: _posQuickActions.contains('favorites'),
          showPosCustomer: _posQuickActions.contains('customer'),
          dashboardMetrics: businessLayoutDefaultDashboardMetrics(
            _businessLayoutId,
            _additionalBusinessLayoutIds,
          ),
          dashboardSections: businessLayoutDefaultDashboardSections(
            _businessLayoutId,
            _additionalBusinessLayoutIds,
          ),
          productFieldKeys: businessLayoutDefaultProductFieldKeys(
            _businessLayoutId,
            _additionalBusinessLayoutIds,
          ),
        ).toJson(),
        // How this shop sells and which documents were accepted, so later
        // screens and support can tell what the owner agreed to.
        'sellingMode': _sellingMode,
        'policyAcceptance': _policyAcceptance(),
      },
    );
  }

  Map<String, dynamic> _policyAcceptance() {
    String version(String slug) => kStandalonePolicyDocuments
        .firstWhere((document) => document.slug == slug)
        .version;
    return {
      'termsVersion': version('terms'),
      'privacyVersion': version('privacy'),
      'localDataNoticeVersion': version('data-processing'),
      'acceptedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  List<String> _businessLayoutHiddenPaths() {
    final hidden = businessLayoutDefaultHiddenPaths(
      _businessLayoutId,
      _additionalBusinessLayoutIds,
    ).toSet();
    // A screen selected as a POS shortcut should also be reachable elsewhere
    // in the app after the merchant finishes setup.
    for (final id in _posQuickActions) {
      final path = businessLayoutPosAction(id)?.path;
      if (path != null) hidden.remove(path);
    }
    return hidden.toList(growable: false);
  }

  // ignore: unused_element

  Future<void> _choosePrimaryBusinessProfile() async {
    final searchController = TextEditingController();
    String? selectedId;
    try {
      selectedId = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: context.themed(DesignColors.darkSurface),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final query = searchController.text.trim().toLowerCase();
            final profiles = businessLayoutPresets
                .where((profile) =>
                    businessLayoutProfileMatchesSearch(profile, query))
                .toList(growable: false);
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * .82,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.themed(DesignColors.darkBorder),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose your shop type',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'This sets helpful starting defaults. You can fine-tune the layout later.',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: context.themed(
                                      DesignColors.darkTextSecondary),
                                ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: searchController,
                            onChanged: (_) => setSheetState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Search shop types',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      onPressed: () {
                                        searchController.clear();
                                        setSheetState(() {});
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: profiles.isEmpty
                          ? const Center(child: Text('No shop types match.'))
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: profiles.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final profile = profiles[index];
                                final selected =
                                    profile.id == _businessLayoutId;
                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(
                                      color: selected
                                          ? DesignColors.brand
                                          : context.themed(
                                              DesignColors.darkBorder),
                                    ),
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: DesignColors.brand
                                        .withValues(alpha: .12),
                                    child: Icon(profile.icon,
                                        color: DesignColors.brand, size: 20),
                                  ),
                                  title: Text(profile.name),
                                  subtitle: Text(profile.description),
                                  trailing: selected
                                      ? const Icon(Icons.check_circle_rounded,
                                          color: DesignColors.brand)
                                      : const Icon(Icons.chevron_right_rounded),
                                  onTap: () => Navigator.of(sheetContext)
                                      .pop(profile.id),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } finally {
      disposeAfterModalCloses([searchController]);
    }
    if (selectedId == null || !mounted || selectedId == _businessLayoutId) {
      return;
    }

    final previousProfileId = _businessLayoutId;
    final previousAdditionalIds = [..._additionalBusinessLayoutIds];
    setState(() {
      _businessLayoutId = selectedId!;
      _additionalBusinessLayoutIds.remove(selectedId);
      _posQuickActions = businessLayoutReconcileRecommendations(
        current: _posQuickActions,
        previousRecommendations: businessLayoutDefaultPosQuickActions(
          previousProfileId,
          previousAdditionalIds,
        ),
        nextRecommendations: businessLayoutDefaultPosQuickActions(
          _businessLayoutId,
          _additionalBusinessLayoutIds,
        ),
      );
    });
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _createLocalWorkspace() async {
    if (_isLoading || !(_formKey.currentState?.validate() ?? false)) return;
    if (_ownerPinController.text != _confirmOwnerPinController.text) {
      _showError('The two PIN entries do not match.');
      return;
    }
    if (!_acceptedLocalDataNotice) {
      _showError('Tick the box to confirm you understand where your records are kept.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    SetupSession.holdReady = true;
    try {
      await getIt<AuthService>().createLocalWorkspace(
        workspace: _workspaceRequest(),
        ownerEmail: _emailController.text.trim(),
        ownerPin: _ownerPinController.text.trim(),
        acceptedLocalDataNotice: _acceptedLocalDataNotice,
      );
    } catch (_) {
      // Database and platform errors are often implementation details. Keep
      // those out of the owner's setup flow and give them a useful next step.
      _showError(
        'Could not create the workspace. Check the details and available device storage, then try again.',
      );
      SetupSession.holdReady = false;
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // The workspace is durable now. A failure while adding staff or showing
    // the ready screen must never send the owner back to setup with a false
    // "creation failed" message.
    try {
      await _addTeamMembers();
      final auth = getIt<AuthService>();
      final tenant = auth.currentUser?['tenant'];
      final name = tenant is Map ? tenant['name']?.toString() : null;
      if (!mounted) return;
      setState(() {
        _createdName = name?.trim().isNotEmpty == true
            ? name!.trim()
            : _companyNameController.text.trim();
        _created = true;
        _errorMessage = null;
      });
    } catch (_) {
      _openCreatedWorkspace();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Staff are added after the workspace exists because only its owner can
  /// create them. One bad entry (for example a repeated PIN) must not undo the
  /// shop, so problems are listed on the ready screen instead.
  Future<void> _addTeamMembers() async {
    final auth = getIt<AuthService>();
    for (final person in _team) {
      try {
        await auth.createLocalStaffAccount(
          name: person.name,
          role: person.role,
          pin: person.pin,
        );
      } catch (_) {
        _teamIssues.add(person.name);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _errorMessage = message);
    // Keep one persistent error surface instead of stacking an identical
    // snackbar over the inline panel. Scroll the panel into view so errors
    // remain easy to find on short screens and while the keyboard is open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_setupScrollController.hasClients) return;
      _setupScrollController.animateTo(
        _setupScrollController.position.maxScrollExtent,
        duration: reducedMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _openShop() async {
    await getIt<StorageService>().setHasSeenStaffTour(true);
    if (!mounted) return;
    _openCreatedWorkspace();
  }

  Future<void> _openShopThen(String route) async {
    await _openShop();
    if (!mounted) return;
    context.push(route);
  }

  void _openCreatedWorkspace() {
    SetupSession.holdReady = false;
    if (!mounted) return;
    final user = getIt<AuthService>().currentUser;
    final permissions = RolePermissions(
      user?['permissions'] as List<dynamic>?,
    );
    final layout = businessLayoutFromUser(user);
    // The first screen after setup should match the profile's saved start
    // action (for example POS for a counter-first shop), just like cold start.
    context.go(LocalWorkspaceCapabilities.homePathFor(permissions, layout));
  }

  void _nextStep() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_currentStep < _steps.length - 1) {
      _changeStep(_currentStep + 1);
    }
  }

  void _changeStep(int step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _currentStep = step;
      _errorMessage = null;
    });
    // Each onboarding step starts at its heading. Keeping the prior scroll
    // offset can make a short next step appear blank or hide its title, and
    // leaving a text field focused can keep the keyboard over the new step.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_setupScrollController.hasClients) return;
      _setupScrollController.animateTo(
        0,
        duration: reducedMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _goBack() {
    if (_isLoading) return;
    if (_currentStep == 0) {
      context.go('/company-choice');
      return;
    }
    _changeStep(_currentStep - 1);
  }

  static const _stepLabels = {
    _SetupStep.business: 'Your business',
    _SetupStep.sell: 'How you sell',
    _SetupStep.team: 'Your team',
    _SetupStep.pin: 'Owner PIN',
  };

  @override
  Widget build(BuildContext context) {
    if (_created) return _buildReady();
    final steps = _steps;
    final step = steps[_currentStep.clamp(0, steps.length - 1)];
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      child: Scaffold(
        backgroundColor: context.themed(DesignColors.darkBg),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _Header(
                  title: widget.join ? 'Add this phone' : 'Set up your shop',
                  step: _currentStep,
                  label: _stepLabels[step]!,
                  totalSteps: steps.length,
                  onBack: _goBack,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _setupScrollController,
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedSwitcher(
                          duration: DesignAnimation.fast,
                          child: KeyedSubtree(
                            key: ValueKey(_currentStep),
                            child: _buildStep(),
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 20),
                          _ErrorPanel(
                              message: _errorMessage!,
                              onDismiss: () {
                                setState(() => _errorMessage = null);
                              }),
                        ],
                      ],
                    ),
                  ),
                ),
                // Pinned outside the scroll view so it stays reachable at a
                // fixed position when the keyboard opens/closes or the form
                // content scrolls — previously lived inside the scrollable
                // column and could drift out of the tappable viewport.
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: _buildFooter(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    final selectedProfile = businessLayoutPreset(_businessLayoutId);
    switch (_steps[_currentStep]) {
      case _SetupStep.business:
        return _StepContent(
          title: 'Tell us about your shop',
          subtitle: widget.join
              ? 'Use the same shop name as on your main phone.'
              : 'This sets up your shop on this phone.',
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.phone_android_rounded,
                    size: 18, color: SignInPalette.of(context).soft),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your sales and stock stay on this phone. You can move them to another phone with a backup.',
                    style: TextStyle(
                      color: SignInPalette.of(context).soft,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _field(
              _companyNameController,
              label: 'Business name',
              hint: 'e.g. Acme Retail',
              icon: Icons.business_rounded,
              validator: _companyValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
            const SizedBox(height: 10),
            Text(
              'Shown on receipts and throughout this workspace.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.themed(DesignColors.darkTextTertiary),
                  ),
            ),
            const SizedBox(height: 26),
            Text(
              'Choose your shop profile',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.themed(DesignColors.darkTextPrimary),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Checkout, product details and dashboard adapt to your trade.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.themed(DesignColors.darkTextTertiary),
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 12),
            Material(
              color: context.themed(DesignColors.darkSurfaceElevated),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _choosePrimaryBusinessProfile,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: context.themed(DesignColors.brand),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            DesignColors.brand.withValues(alpha: .14),
                        child: Icon(selectedProfile.icon,
                            color: DesignColors.brand, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedProfile.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              selectedProfile.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: context.themed(
                                        DesignColors.darkTextTertiary),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _choosePrimaryBusinessProfile,
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, constraints) {
              final first = _field(
                _firstNameController,
                label: 'First name',
                hint: 'Wanjiru',
                icon: Icons.person_outline_rounded,
                validator: _requiredName,
              );
              final last = _field(
                _lastNameController,
                label: 'Last name',
                hint: 'Kamau',
                icon: Icons.person_outline_rounded,
                validator: _requiredName,
              );
              if (constraints.maxWidth < 300) {
                return Column(children: [
                  first,
                  const SizedBox(height: 16),
                  last,
                ]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: first),
                const SizedBox(width: 12),
                Expanded(child: last),
              ]);
            }),
            const SizedBox(height: 16),
            _field(
              _emailController,
              action: TextInputAction.done,
              label: 'Owner email · optional',
              hint: 'name@business.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: _emailValidator,
            ),
          ],
        );
      case _SetupStep.sell:
        return _buildSellStep();
      case _SetupStep.team:
        return _buildTeamStep();
      case _SetupStep.pin:
        return _buildVerificationStep();
    }
  }

  Widget _buildSellStep() {
    final palette = SignInPalette.of(context);
    final shop = _companyNameController.text.trim();
    void choose(String mode) {
      setState(() {
        _sellingMode = mode;
        // A second till needs a name that tells the phones apart.
        final name = _branchNameController.text.trim();
        if (mode == 'multi' && name == 'Main location') {
          _branchNameController.text = 'Front counter';
        } else if (mode != 'multi' && name == 'Front counter') {
          _branchNameController.text = 'Main location';
        }
      });
    }

    return _StepContent(
      title: 'How will you sell?',
      subtitle: shop.isEmpty
          ? 'Pick what fits today. You can change it in Settings.'
          : 'Pick what fits $shop today. You can change it in Settings.',
      children: [
        _OptionCard(
          selected: _sellingMode == 'solo',
          title: 'Just me',
          detail: 'One phone, one person at the till.',
          onTap: () => choose('solo'),
        ),
        const SizedBox(height: 12),
        _OptionCard(
          selected: _sellingMode == 'team',
          title: 'A team on this phone',
          detail:
              'Each person signs in with their own PIN, so every sale shows who made it.',
          onTap: () => choose('team'),
        ),
        const SizedBox(height: 12),
        _OptionCard(
          selected: _sellingMode == 'multi',
          title: 'Several phones',
          detail:
              'Each phone is its own till, such as Front counter and Back shop.',
          onTap: () => choose('multi'),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.themed(DesignColors.accentSubtle),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          ),
          child: Text(
            'Each phone keeps its own records for now. Move or combine them with a backup.',
            style: TextStyle(color: palette.ink, fontSize: 13, height: 1.45),
          ),
        ),
        const SizedBox(height: 24),
        _field(
          _branchNameController,
          action: TextInputAction.done,
          label: _sellingMode == 'multi' ? 'Name this till' : 'Shop location',
          hint: _sellingMode == 'multi' ? 'Front counter' : 'Main location',
          icon: Icons.storefront_outlined,
          textCapitalization: TextCapitalization.words,
          validator: (value) => (value?.trim().length ?? 0) >= 2
              ? null
              : 'Enter a name of at least 2 letters',
        ),
        const SizedBox(height: 8),
        Text(
          'Shown on receipts and in your end of day till close.',
          style: TextStyle(color: palette.faint, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _buildTeamStep() {
    final palette = SignInPalette.of(context);
    final owner =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
            .trim();
    return _StepContent(
      title: 'Who works at the till?',
      subtitle:
          'Each person gets a PIN, so every sale shows who made it. You can skip this and add people later in Settings.',
      children: [
        _PersonRow(
          name: owner.isEmpty ? 'You' : owner,
          detail: 'You · Owner',
          me: true,
        ),
        for (var i = 0; i < _team.length; i++) ...[
          const SizedBox(height: 10),
          _PersonRow(
            name: _team[i].name,
            detail: 'PIN set',
            chip: _team[i].role,
            onRemove: () => setState(() => _team.removeAt(i)),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _addPerson,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add a person'),
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.ink,
            minimumSize: const Size.fromHeight(52),
            side: BorderSide(color: palette.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addPerson() async {
    final nameController = TextEditingController();
    final pinController = TextEditingController();
    var role = LocalStaffRoles.names.first;
    String? error;
    final draft = await showModalBottomSheet<_StaffDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SignInPalette.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) {
          final palette = SignInPalette.of(context);
          return Padding(
            padding: EdgeInsets.fromLTRB(
                24, 20, 24, 20 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add a person',
                    style: DesignType.display.copyWith(
                        color: palette.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final name in LocalStaffRoles.names)
                      ChoiceChip(
                        label: Text(name),
                        selected: role == name,
                        selectedColor: DesignColors.accent,
                        checkmarkColor: SignInPalette.onAccent,
                        labelStyle: TextStyle(
                          color: role == name
                              ? SignInPalette.onAccent
                              : palette.ink,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) => setSheet(() => role = name),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration:
                      const InputDecoration(labelText: 'PIN, 4 to 6 digits'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: DesignColors.error, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                SignInButton(
                  label: 'Add person',
                  onPressed: () {
                    final name = nameController.text
                        .trim()
                        .replaceAll(RegExp(r'\s+'), ' ');
                    final pin = pinController.text.trim();
                    String? problem;
                    if (name.length < 2) {
                      problem = 'Enter a name of at least 2 letters.';
                    } else if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
                      problem = 'The PIN must be 4 to 6 digits.';
                    } else if (_team.any((person) => person.pin == pin)) {
                      problem = 'Someone you added already uses that PIN.';
                    }
                    if (problem != null) {
                      setSheet(() => error = problem);
                      return;
                    }
                    Navigator.of(sheetContext)
                        .pop(_StaffDraft(name: name, role: role, pin: pin));
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
    disposeAfterModalCloses([nameController, pinController]);
    if (draft != null && mounted) setState(() => _team.add(draft));
  }

  Widget _buildVerificationStep() {
    final palette = SignInPalette.of(context);
    final pinToggle = IconButton(
      tooltip: _showPin ? 'Hide PIN' : 'Show PIN',
      onPressed: () => setState(() => _showPin = !_showPin),
      icon: Icon(
        _showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: palette.faint,
        size: 20,
      ),
    );
    return _StepContent(
      title: 'Set your owner PIN',
      subtitle:
          'You will use this 6 digit PIN to open Counterbase on this phone.',
      children: [
        _field(
          _ownerPinController,
          label: 'Owner PIN',
          hint: '6 digits',
          icon: Icons.password_rounded,
          keyboardType: TextInputType.number,
          obscureText: !_showPin,
          suffix: pinToggle,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
              ? null
              : 'Choose exactly 6 digits',
        ),
        const SizedBox(height: 16),
        _field(
          _confirmOwnerPinController,
          action: TextInputAction.done,
          label: 'Confirm PIN',
          hint: 'Enter the same 6 digits again',
          icon: Icons.verified_user_outlined,
          keyboardType: TextInputType.number,
          obscureText: !_showPin,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) {
            if ((value?.length ?? 0) != 6) {
              return 'Enter the same 6 digits again';
            }
            if (value != _ownerPinController.text) {
              return 'The PINs do not match';
            }
            return null;
          },
        ),
        const SizedBox(height: 24),
        Semantics(
          checked: _acceptedLocalDataNotice,
          child: InkWell(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            onTap: _isLoading
                ? null
                : () => setState(
                    () => _acceptedLocalDataNotice = !_acceptedLocalDataNotice),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                border: Border.all(
                  color: _acceptedLocalDataNotice
                      ? DesignColors.accent
                      : palette.line,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _acceptedLocalDataNotice,
                    activeColor: DesignColors.accent,
                    checkColor: SignInPalette.onAccent,
                    onChanged: _isLoading
                        ? null
                        : (value) => setState(
                            () => _acceptedLocalDataNotice = value ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'I understand my sales and stock stay on this phone. They only move to another phone if I make a backup.',
                        style: TextStyle(
                          color: palette.ink,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        LegalConsent(palette: palette, action: 'creating your shop'),
        const SizedBox(height: 8),
        Text(
          'Moving a shop from another phone? After setup, restore its backup in Settings under Local data, before you record any sales.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.faint, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    switch (_steps[_currentStep]) {
      case _SetupStep.pin:
        return SignInButton(
          label: 'Create my shop',
          loading: _isLoading,
          onPressed: _isLoading ? null : _createLocalWorkspace,
        );
      case _SetupStep.team:
        return SignInButton(
          label: _team.isEmpty ? 'Skip for now' : 'Continue',
          onPressed: _nextStep,
        );
      case _SetupStep.business:
      case _SetupStep.sell:
        return SignInButton(label: 'Continue', onPressed: _nextStep);
    }
  }

  void _showAddTillHelp() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add another till'),
        content: const Text(
          'On the other phone, install Counterbase and choose "Add this phone to my shop". Then restore the backup you make on this phone. Each phone keeps its own sales, so bring the backups together when you want one view of the shop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildReady() {
    final palette = SignInPalette.of(context);
    final tiles = <Widget>[
      if (widget.join)
        _NextStep(
          icon: Icons.restore_rounded,
          title: 'Restore your backup',
          detail: 'Bring products, prices and staff from your main phone.',
          onTap: () => _openShopThen('/settings'),
        ),
      _NextStep(
        icon: Icons.inventory_2_outlined,
        title: 'Add your products',
        detail: 'Type them in, scan, or import a list.',
        onTap: () => _openShopThen('/products'),
      ),
      _NextStep(
        icon: Icons.payments_outlined,
        title: 'Choose how customers pay',
        detail: 'Cash and M-Pesa at the counter.',
        onTap: () => _openShopThen('/payments'),
      ),
      _NextStep(
        icon: Icons.image_outlined,
        title: 'Add your logo',
        detail: 'Your own logo replaces the Counterbase mark.',
        onTap: () => _openShopThen('/settings'),
      ),
      if (_sellingMode == 'multi' && !widget.join)
        _NextStep(
          icon: Icons.phone_android_rounded,
          title: 'Add another till',
          detail: 'See how to bring a second phone in.',
          onTap: _showAddTillHelp,
        ),
    ];
    return Scaffold(
      backgroundColor: palette.page,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: BusinessMark(name: _createdName, size: 88)),
                    const SizedBox(height: 18),
                    Text(
                      'Your shop is ready',
                      textAlign: TextAlign.center,
                      style: DesignType.display.copyWith(
                          color: palette.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$_createdName is set up on this phone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.soft, fontSize: 15),
                    ),
                    if (_teamIssues.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'We could not add ${_teamIssues.join(', ')}. Add them again in Settings, under Users.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: DesignColors.warning, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Text(
                      'Do these next',
                      style: TextStyle(
                          color: palette.soft,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    for (final tile in tiles) ...[
                      tile,
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'Make a backup once you have sales. It protects you if the phone is lost.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: palette.faint, fontSize: 12.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SignInButton(label: 'Open my shop', onPressed: _openShop),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
    AutovalidateMode? autovalidateMode,
    ValueChanged<String>? onChanged,
    Widget? suffix,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction action = TextInputAction.next,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: context.themed(DesignColors.darkTextSecondary),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            onChanged: onChanged,
            validator: validator,
            keyboardType: keyboardType,
            textInputAction: action,
            textCapitalization: textCapitalization,
            obscureText: obscureText,
            maxLines: maxLines,
            inputFormatters: inputFormatters,
            autovalidateMode: autovalidateMode,
            style:
                TextStyle(color: context.themed(DesignColors.darkTextPrimary)),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                  color: context.themed(DesignColors.darkTextTertiary)),
              prefixIcon: Icon(icon,
                  color: context.themed(DesignColors.darkTextSecondary)),
              suffixIcon: suffix,
              filled: true,
              fillColor: context.themed(DesignColors.darkSurfaceElevated),
              errorMaxLines: 2,
              border: _inputBorder(context.themed(DesignColors.darkBorder)),
              enabledBorder:
                  _inputBorder(context.themed(DesignColors.darkBorder)),
              focusedBorder: _inputBorder(DesignColors.brand, width: 1.5),
              errorBorder: _inputBorder(DesignColors.error),
              focusedErrorBorder: _inputBorder(DesignColors.error, width: 1.5),
            ),
          ),
        ],
      );

  OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide: BorderSide(color: color, width: width));

  String? _companyValidator(String? value) {
    final name = value?.trim() ?? '';
    if (name.length < 2) return 'Company name must be at least 2 characters';
    if (name.length > 100) {
      return 'Company name must be 100 characters or fewer';
    }
    if (!RegExp(r"^[a-zA-Z0-9\s&'-]+$").hasMatch(name)) {
      return "Only letters, numbers, spaces, &, ' and - are allowed";
    }
    return null;
  }

  String? _requiredName(String? value) =>
      (value?.trim().isNotEmpty ?? false) ? null : 'Required';

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null;
    return RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(email)
        ? null
        : 'Enter a valid email address';
  }
}

enum _SetupStep { business, sell, team, pin }

/// A staff member entered during setup. They are created once the workspace
/// exists, because only the owner can add staff.
class _StaffDraft {
  const _StaffDraft(
      {required this.name, required this.role, required this.pin});
  final String name;
  final String role;
  final String pin;
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.title,
      required this.step,
      required this.label,
      required this.totalSteps,
      required this.onBack});
  final String title;
  final int step;
  final String label;
  final int totalSteps;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 24, 8),
      child: Column(children: [
        Row(children: [
          IconButton(
            tooltip: 'Back',
            color: palette.ink,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Text(title,
                style: DesignType.display.copyWith(
                    color: palette.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
          ),
          Text('Step ${step + 1} of $totalSteps',
              style: TextStyle(
                  color: palette.soft,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Semantics(
            label: 'Step ${step + 1} of $totalSteps, $label',
            child: Row(
                children: List.generate(
                    totalSteps,
                    (index) => Expanded(
                          child: AnimatedContainer(
                            duration: DesignAnimation.normal,
                            curve: DesignAnimation.defaultCurve,
                            height: 4,
                            margin: EdgeInsets.only(
                                right: index == totalSteps - 1 ? 0 : 6),
                            decoration: BoxDecoration(
                              color: index <= step
                                  ? DesignColors.accent
                                  : palette.line,
                              borderRadius: BorderRadius.circular(
                                  DesignSpacing.radiusFull),
                            ),
                          ),
                        ))),
          ),
        ),
      ]),
    );
  }
}

class _StepContent extends StatelessWidget {
  const _StepContent(
      {required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: DesignType.display.copyWith(
              color: palette.ink, fontSize: 26, fontWeight: FontWeight.w700)),
      const SizedBox(height: DesignSpacing.sm),
      Text(subtitle,
          style: TextStyle(color: palette.soft, fontSize: 15, height: 1.45)),
      const SizedBox(height: DesignSpacing.xxl),
      ...children,
    ]);
  }
}

/// A radio-style choice card.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.selected,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            border: Border.all(
              color: selected ? DesignColors.accent : palette.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? DesignColors.accent : palette.faint,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: DesignColors.accent,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: palette.ink,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(detail,
                        style: TextStyle(
                            color: palette.soft, fontSize: 13.5, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.detail,
    this.chip,
    this.me = false,
    this.onRemove,
  });

  final String name;
  final String detail;
  final String? chip;
  final bool me;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: me ? DesignColors.accent : palette.field,
            ),
            child: Text(
              initialsFor(name),
              style: DesignType.display.copyWith(
                color: me ? SignInPalette.onAccent : palette.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: palette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                Text(detail,
                    style: TextStyle(color: palette.soft, fontSize: 12.5)),
              ],
            ),
          ),
          if (chip != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: palette.field,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(chip!,
                  style: TextStyle(
                      color: palette.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove $name',
              onPressed: onRemove,
              icon: Icon(Icons.close_rounded, color: palette.faint, size: 20),
            ),
        ],
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: context.themed(DesignColors.accentSubtle),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: DesignColors.accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: palette.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(detail,
                        style: TextStyle(color: palette.soft, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: 'Error: $message',
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DesignColors.error.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusMd + 2),
            border:
                Border.all(color: DesignColors.error.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            const Icon(Icons.error_outline_rounded, color: DesignColors.error),
            const SizedBox(width: 12),
            Expanded(
                child: Text(message,
                    style: TextStyle(
                        color:
                            context.themed(DesignColors.darkTextSecondary)))),
            IconButton(
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                icon: Icon(Icons.close_rounded,
                    color: context.themed(DesignColors.darkTextTertiary))),
          ]),
        ),
      );
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      TextEditingValue(
          text: newValue.text.toUpperCase(), selection: newValue.selection);
}
