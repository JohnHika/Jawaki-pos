import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/providers/business_layout_provider.dart';
import 'package:axon_pos/core/providers/local_workspace_capabilities.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/core/widgets/motion.dart';

/// Creates the first workspace locally on this device. The owner's PIN is
/// protected by platform secure storage and no identity or business data is
/// sent to an online POS service.
class CompanySetupScreen extends ConsumerStatefulWidget {
  const CompanySetupScreen({super.key});

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
      },
    );
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
      searchController.dispose();
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
      _showError('Acknowledge the local data notice to create the workspace.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
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
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // The workspace is durable now. A failure in the success dialog or a
    // first-run preference must never send the owner back to setup with a
    // false "creation failed" message; continue into the shop instead.
    try {
      await _finishCreation();
    } catch (_) {
      _openCreatedWorkspace();
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  Future<void> _finishCreation() async {
    if (!mounted) return;
    final auth = getIt<AuthService>();
    final user = auth.currentUser;
    final tenant = user?['tenant'];
    final name = tenant is Map ? tenant['name']?.toString() : null;
    final companyName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : _companyNameController.text.trim();
    await _showCompanyCreatedDialog(
      companyName: companyName,
    );
    if (!mounted) return;
    await getIt<StorageService>().setHasSeenStaffTour(true);
    if (!mounted) return;
    _openCreatedWorkspace();
  }

  void _openCreatedWorkspace() {
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
    if (_currentStep < 1) {
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

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Your business',
      'Device security',
    ];
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
                  step: _currentStep,
                  label: labels[_currentStep],
                  totalSteps: labels.length,
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
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
    switch (_currentStep) {
      case 0:
        return _StepContent(
          title: 'Build your workspace',
          subtitle: 'Set up your shop for the way you sell.',
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.themed(DesignColors.darkSurface),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: context.themed(DesignColors.darkBorder),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.devices_rounded,
                    size: 21,
                    color: context.themed(DesignColors.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Local-first · Sales and stock stay on this device. Use an encrypted backup to move phones.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.themed(DesignColors.darkTextTertiary),
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
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
                label: 'Your first name',
                hint: 'Ada',
                icon: Icons.person_outline_rounded,
                validator: _requiredName,
              );
              final last = _field(
                _lastNameController,
                label: 'Last name',
                hint: 'Lovelace',
                icon: Icons.person_outline_rounded,
                validator: _requiredName,
              );
              if (constraints.maxWidth < 390) {
                return Column(children: [
                  first,
                  const SizedBox(height: 16),
                  last,
                ]);
              }
              return Row(children: [
                Expanded(child: first),
                const SizedBox(width: 12),
                Expanded(child: last),
              ]);
            }),
            const SizedBox(height: 16),
            _field(
              _emailController,
              label: 'Owner email · optional',
              hint: 'name@business.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: _emailValidator,
            ),
          ],
        );
      default:
        return _buildVerificationStep();
    }
  }

  Widget _buildVerificationStep() {
    return _StepContent(
      title: 'Secure this device',
      subtitle: 'Choose the PIN that opens your local workspace.',
      children: [
        const _SetupEditorialCard(
          index: '04 / DEVICE SECURITY',
          icon: Icons.phonelink_lock_rounded,
          title: 'Your shop stays on this device.',
          detail:
              'The workspace is created locally. No account, online POS server, or internet connection is needed.',
        ),
        const SizedBox(height: 28),
        _field(
          _ownerPinController,
          label: 'Owner PIN · 6 digits',
          hint: '••••••',
          icon: Icons.password_rounded,
          keyboardType: TextInputType.number,
          obscureText: true,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
              ? null
              : 'Choose exactly 6 digits',
        ),
        const SizedBox(height: 16),
        _field(
          _confirmOwnerPinController,
          label: 'Confirm owner PIN',
          hint: 'Enter the same 6 digits again',
          icon: Icons.verified_user_outlined,
          keyboardType: TextInputType.number,
          obscureText: true,
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
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
          decoration: BoxDecoration(
            color: context.themed(DesignColors.darkSurface),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
            border: Border.all(color: context.themed(DesignColors.darkBorder)),
          ),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(
                  value: _acceptedLocalDataNotice,
                  onChanged: _isLoading
                      ? null
                      : (value) => setState(
                          () => _acceptedLocalDataNotice = value ?? false)),
              Expanded(
                child: InkWell(
                  onTap: _isLoading
                      ? null
                      : () => setState(() =>
                          _acceptedLocalDataNotice = !_acceptedLocalDataNotice),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      'I understand the workspace and its records stay on this device. They will not sync to another device unless I create and move a backup.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(height: 1.4),
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
        GradientButton(
          label: 'Create local workspace',
          icon: Icons.store_mall_directory_outlined,
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _createLocalWorkspace,
          height: 54,
          borderRadius: 14,
        ),
        const SizedBox(height: 16),
        Text(
          'Moving an existing shop? After setup, restore its .cbmobile backup or import the encrypted .cbarchive in Settings → Local data before recording sales. A different shop can only be imported into an empty workspace.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.themed(DesignColors.darkTextTertiary),
              height: 1.4),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    if (_currentStep == 1) {
      return TextButton(
        onPressed: _isLoading ? null : _goBack,
        child: const Text('Back to business details'),
      );
    }
    return Row(children: [
      if (_currentStep > 0)
        TextButton(onPressed: _goBack, child: const Text('Back')),
      if (_currentStep > 0) const SizedBox(width: 12),
      Expanded(
        child: GradientButton(
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          onPressed: _nextStep,
          height: 54,
          borderRadius: 16,
        ),
      ),
    ]);
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
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: context.themed(DesignColors.darkTextSecondary))),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            onChanged: onChanged,
            validator: validator,
            keyboardType: keyboardType,
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

  Future<void> _showCompanyCreatedDialog({
    required String companyName,
  }) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: DesignColors.success),
            SizedBox(width: 12),
            Text('Workspace ready'),
          ]),
          content: Text(
              '$companyName is ready on this device. If you are moving an existing shop, restore its .cbmobile backup or import the encrypted .cbarchive in Settings → Local data before recording sales. Keep your owner PIN safe and create an encrypted backup before changing devices.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.step,
      required this.label,
      required this.totalSteps,
      required this.onBack});
  final int step;
  final String label;
  final int totalSteps;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 20, 0),
        child: Column(children: [
          Row(children: [
            AppBackButton(
              color: context.themed(DesignColors.darkTextPrimary),
              isDark: Theme.of(context).brightness == Brightness.dark,
              onPressed: onBack,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('COUNTERBASE / SETUP',
                  style: TextStyle(
                      color: context.themed(DesignColors.darkTextSecondary),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
            ),
            Text('${step + 1} / $totalSteps',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: DesignColors.accent)),
          ]),
          const SizedBox(height: 12),
          Row(
              children: List.generate(
                  totalSteps,
                  (index) => Expanded(
                        child: AnimatedContainer(
                          duration: DesignAnimation.normal,
                          curve: DesignAnimation.defaultCurve,
                          height: DesignSpacing.xs - 1,
                          margin: EdgeInsets.only(
                              right: index == totalSteps - 1
                                  ? 0
                                  : DesignSpacing.sm - 2),
                          decoration: BoxDecoration(
                            color: index <= step
                                ? DesignColors.accent
                                : context.themed(DesignColors.darkBorder),
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusFull),
                          ),
                        ),
                      ))),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Step ${step + 1} of $totalSteps · $label',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.themed(DesignColors.darkTextTertiary))),
          ),
        ]),
      );
}

class _StepContent extends StatelessWidget {
  const _StepContent(
      {required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Each step's header rises/fades in on first mount (onboarding stagger)
      StaggeredItem(
        itemKey: 'setup-step-title-$title',
        child: Text(title,
            style: theme.textTheme.headlineMedium?.copyWith(
                color: context.themed(DesignColors.darkTextPrimary),
                fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: DesignSpacing.md),
      Text(subtitle,
          style: theme.textTheme.titleMedium?.copyWith(
              color: context.themed(DesignColors.darkTextSecondary),
              height: 1.4)),
      const SizedBox(height: DesignSpacing.xxxl - 4),
      ...children,
    ]);
  }
}

class _SetupEditorialCard extends StatelessWidget {
  const _SetupEditorialCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final String index;
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: context.themed(DesignColors.darkSurface),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
          border: Border.all(color: context.themed(DesignColors.darkBorder)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: DesignColors.accent, size: 26),
            const Spacer(),
            Text(index,
                style: DesignType.numeric(
                    fontSize: 11,
                    color: context.themed(DesignColors.darkTextTertiary),
                    letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 26),
          Text(title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: context.themed(DesignColors.darkTextPrimary),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(detail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.themed(DesignColors.darkTextSecondary),
                  height: 1.5)),
        ]),
      );
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
