import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:axon_pos/core/config/google_auth_config.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/legal/policy_catalog.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/core/widgets/motion.dart';

String companySetupErrorMessage(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final message =
        (data is Map ? data['message'] : null)?.toString().toLowerCase() ?? '';
    if (message.contains('already exists')) {
      return 'A workspace with this name already exists. Choose a different name.';
    }
    if (message.contains('expired') || message.contains('invalid')) {
      return 'That verification code is invalid or expired. Request a new code and try again.';
    }
    if (status == 409) return 'A workspace with these details already exists.';
    if (status == 400 || status == 422) {
      return 'Check the details and verification code, then try again.';
    }
    if (status == 401) return 'Verification was not accepted. Try again.';
    if (status != null && status >= 500) {
      return 'Counterbase could not create your workspace right now. Try again shortly.';
    }
    if (error.type == DioExceptionType.connectionError) {
      return 'We could not reach Counterbase. Check your connection and try again.';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return 'The connection timed out. Check your network and try again.';
    }
  }
  return 'We could not complete verification. Please try again.';
}

enum _VerificationMode { google, emailOtp }

/// Creates a first workspace only after Google or email ownership verification.
/// Passwords are intentionally neither collected nor sent by this screen.
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
  final _otpController = TextEditingController();

  int _currentStep = 0;
  bool _isLoading = false;
  bool _acceptedSignupPolicies = false;
  String? _errorMessage;
  String? _challengeId;
  String? _challengeEmail;
  String? _verifiedGoogleEmail;
  _VerificationMode _verificationMode = _VerificationMode.google;

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
      _otpController,
    ]) {
      controller.dispose();
    }
    _setupScrollController.dispose();
    super.dispose();
  }

  WorkspaceCreationRequest _workspaceRequest() => WorkspaceCreationRequest(
        companyName: _companyNameController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        deviceId: getIt<AuthService>().deviceId,
        branch: WorkspaceBranchDetails(
          name: _branchNameController.text.trim(),
          code: _branchCodeController.text.trim().toUpperCase(),
          address: _optional(_branchAddressController),
          phone: _optional(_branchPhoneController),
          email: _verificationMode == _VerificationMode.google &&
                  _verifiedGoogleEmail != null
              ? _verifiedGoogleEmail!
              : _emailController.text.trim(),
        ),
        acceptedPolicyTypes: kSignupPolicyTypes,
      );

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _createWithGoogle() async {
    if (_isLoading) return;
    if (!_acceptedSignupPolicies) {
      _showError(
          'Accept the Terms of Service and Data Processing Addendum, and review the Privacy Notice, to create a workspace.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final account =
          await GoogleSignIn(serverClientId: googleWebClientId).signIn();
      if (account == null) return;
      final verifiedEmail = account.email.trim();
      if (verifiedEmail.isEmpty) {
        throw StateError('Google did not return an email address');
      }
      if (mounted) {
        setState(() {
          _verifiedGoogleEmail = verifiedEmail;
          _emailController.text = verifiedEmail;
        });
      }
      final idToken = (await account.authentication).idToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Google did not return an identity token');
      }
      await getIt<AuthService>().createWorkspaceWithGoogle(
        idToken: idToken,
        workspace: _workspaceRequest(),
      );
      await _finishCreation();
    } catch (error) {
      _showError(companySetupErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestEmailOtp() async {
    if (_isLoading) return;
    if (_emailValidator(_emailController.text) != null) {
      _showError('Enter the owner email you can access to receive a code.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await getIt<AuthService>()
          .requestWorkspaceEmailOtp(_emailController.text.trim());
      final challengeId = response['challengeId'] as String?;
      if (challengeId == null || challengeId.isEmpty) {
        throw StateError('Missing verification challenge');
      }
      if (!mounted) return;
      setState(() {
        _challengeId = challengeId;
        _challengeEmail = _emailController.text.trim();
        _verificationMode = _VerificationMode.emailOtp;
        _otpController.clear();
      });
    } catch (error) {
      _showError(companySetupErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createWithEmailOtp() async {
    if (_isLoading || _challengeId == null) return;
    if (!_acceptedSignupPolicies) {
      _showError(
          'Accept the Terms of Service and Data Processing Addendum, and review the Privacy Notice, to create a workspace.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await getIt<AuthService>().createWorkspaceWithEmailOtp(
        email: _emailController.text.trim(),
        challengeId: _challengeId!,
        code: _otpController.text.trim(),
        workspace: _workspaceRequest(),
      );
      await _finishCreation();
    } catch (error) {
      _showError(companySetupErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
    showGlassSnackBar(
      context,
      message,
      icon: Icons.error_outline_rounded,
      color: DesignColors.error,
    );
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
    final companyCode =
        user?['tenantSlug']?.toString().trim().isNotEmpty == true
            ? user!['tenantSlug'].toString().trim()
            : _slugify(companyName);

    await _showCompanyCreatedDialog(
      companyName: companyName,
      companyCode: companyCode,
    );
    if (!mounted) return;
    await getIt<UpdateCheckService>().checkAfterLogin();
    if (!mounted) return;
    await getIt<StorageService>().setHasSeenStaffTour(true);
    if (!mounted) return;
    context.go(
      auth.requiresTenantActivation ? '/activation' : '/owner-welcome',
      extra: companyName,
    );
  }

  void _nextStep() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_currentStep < 3) {
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
      'Workspace identity',
      'Owner profile',
      'First counter',
      'Verify ownership',
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
    switch (_currentStep) {
      case 0:
        return _StepContent(
          title: 'Build your workspace',
          subtitle:
              'Give your business a home. You can refine its details as you grow.',
          children: [
            const _SetupEditorialCard(
              index: '01 / BUSINESS',
              icon: Icons.storefront_outlined,
              title: 'One place for every sale.',
              detail:
                  'Your workspace connects counters, people, stock and payments under your business name.',
            ),
            const SizedBox(height: 28),
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
              'This name appears on receipts and your team workspace.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.themed(DesignColors.darkTextTertiary),
                  ),
            ),
          ],
        );
      case 1:
        return _StepContent(
          title: 'Meet the owner',
          subtitle:
              'This person will control access, billing and payout settings.',
          children: [
            const _SetupEditorialCard(
              index: '02 / OWNER',
              icon: Icons.admin_panel_settings_outlined,
              title: 'Your account stays yours.',
              detail:
                  'Only the verified owner can create this workspace. You can invite your team after setup.',
            ),
            const SizedBox(height: 28),
            LayoutBuilder(builder: (context, constraints) {
              final first = _field(
                _firstNameController,
                label: 'First name',
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
            const SizedBox(height: 20),
            _field(
              _emailController,
              label: 'Owner email',
              hint: 'name@business.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              onChanged: (value) {
                if (_challengeId != null && value.trim() != _challengeEmail) {
                  setState(() {
                    _challengeId = null;
                    _otpController.clear();
                  });
                }
              },
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty &&
                    _verificationMode == _VerificationMode.google) {
                  return null;
                }
                return _emailValidator(value);
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Use this address for an email code, or continue with Google in the final step.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.themed(DesignColors.darkTextTertiary),
                    height: 1.45,
                  ),
            ),
          ],
        );
      case 2:
        return _StepContent(
          title: 'Open your first counter',
          subtitle: 'Name the place where your first sale will happen.',
          children: [
            const _SetupEditorialCard(
              index: '03 / FIRST LOCATION',
              icon: Icons.point_of_sale_outlined,
              title: 'Ready for the first customer.',
              detail:
                  'A branch keeps sales and inventory together. Add more locations later from Settings.',
            ),
            const SizedBox(height: 28),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 580;
              final name = _field(
                _branchNameController,
                label: 'Branch name',
                hint: 'Main Store',
                icon: Icons.store_rounded,
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Enter at least 2 characters'
                    : null,
              );
              final code = _field(
                _branchCodeController,
                label: 'Branch code',
                hint: 'MAIN',
                icon: Icons.tag_rounded,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Enter at least 2 characters'
                    : null,
              );
              if (!wide) {
                return Column(children: [
                  name,
                  const SizedBox(height: DesignSpacing.md),
                  code,
                ]);
              }
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: DesignSpacing.md),
                    Expanded(child: code),
                  ]);
            }),
            const SizedBox(height: 10),
            Text(
              'The code helps your team identify this branch in reports.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.themed(DesignColors.darkTextTertiary),
                  ),
            ),
            const SizedBox(height: 20),
            _OptionalLocationDetails(
              address: _field(
                _branchAddressController,
                label: 'Address',
                hint: 'Street, town or area',
                icon: Icons.location_on_outlined,
              ),
              phone: _field(
                _branchPhoneController,
                label: 'Phone',
                hint: '+254 700 000 000',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
            ),
          ],
        );
      default:
        return _buildVerificationStep();
    }
  }

  Widget _buildVerificationStep() {
    final byGoogle = _verificationMode == _VerificationMode.google;
    return _StepContent(
      title: 'Verify your ownership',
      subtitle: 'One final check before your business goes live.',
      children: [
        const _SetupEditorialCard(
          index: '04 / OWNERSHIP',
          icon: Icons.verified_user_outlined,
          title: 'Secure ownership check',
          detail:
              'Confirm your identity to protect your team, payments and business data.',
        ),
        const SizedBox(height: 28),
        Text('CHOOSE A METHOD',
            style: DesignType.numeric(
                fontSize: 11,
                color: context.themed(DesignColors.darkTextTertiary),
                letterSpacing: 1.2)),
        const SizedBox(height: 12),
        _VerificationMethodOption(
          icon: Icons.g_mobiledata_rounded,
          title: 'Continue with Google',
          detail: 'Secure sign-in with your Google account',
          selected: byGoogle,
          onTap: _isLoading
              ? null
              : () =>
                  setState(() => _verificationMode = _VerificationMode.google),
        ),
        const SizedBox(height: 10),
        _VerificationMethodOption(
          icon: Icons.mail_outline_rounded,
          title: 'Use an email code instead',
          detail: 'Send a one-time code to your inbox',
          selected: !byGoogle,
          onTap: _isLoading
              ? null
              : () => setState(
                  () => _verificationMode = _VerificationMode.emailOtp),
        ),
        if (!byGoogle) ...[
          const SizedBox(height: 24),
          _field(
            _emailController,
            label: 'Email for verification',
            hint: 'name@business.com',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
            onChanged: (value) {
              if (_challengeId != null && value.trim() != _challengeEmail) {
                setState(() {
                  _challengeId = null;
                  _otpController.clear();
                });
              }
            },
          ),
          if (_challengeId != null) ...[
            const SizedBox(height: 18),
            Text('Code sent to $_challengeEmail',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: DesignColors.success)),
            const SizedBox(height: 12),
            _field(
              _otpController,
              label: 'Verification code',
              hint: '6–8 digits',
              icon: Icons.password_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              validator: (value) =>
                  RegExp(r'^\d{6,8}$').hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Enter the 6–8 digit code from your email',
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _requestEmailOtp,
                child: const Text('Resend code'),
              ),
            ),
          ],
        ],
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
                  value: _acceptedSignupPolicies,
                  onChanged: _isLoading
                      ? null
                      : (value) => setState(
                          () => _acceptedSignupPolicies = value ?? false)),
              Expanded(
                child: InkWell(
                  onTap: _isLoading
                      ? null
                      : () => setState(() =>
                          _acceptedSignupPolicies = !_acceptedSignupPolicies),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      'I agree to the Terms of Service and Data Processing Addendum, and acknowledge the Privacy Notice.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(height: 1.4),
                    ),
                  ),
                ),
              ),
            ]),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 4, children: [
                _legalLink('Terms', '/legal/terms'),
                _legalLink('Privacy', '/legal/privacy'),
                _legalLink('Data Processing', '/legal/data-processing'),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        GradientButton(
          label: byGoogle
              ? 'Verify and create workspace'
              : _challengeId == null
                  ? 'Send verification code'
                  : 'Verify email & create workspace',
          icon: byGoogle
              ? Icons.arrow_forward_rounded
              : _challengeId == null
                  ? Icons.mark_email_unread_outlined
                  : Icons.verified_rounded,
          isLoading: _isLoading,
          onPressed: _isLoading ||
                  (byGoogle && !_acceptedSignupPolicies) ||
                  (!byGoogle &&
                      _challengeId != null &&
                      !_acceptedSignupPolicies)
              ? null
              : byGoogle
                  ? _createWithGoogle
                  : _challengeId == null
                      ? _requestEmailOtp
                      : _createWithEmailOtp,
          height: 54,
          borderRadius: 14,
        ),
        const SizedBox(height: 16),
        Text(
          'Counterbase does not collect or store an owner password during workspace setup.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.themed(DesignColors.darkTextTertiary),
              height: 1.4),
        ),
      ],
    );
  }

  Widget _legalLink(String label, String route) => TextButton.icon(
        onPressed: _isLoading ? null : () => context.push(route),
        icon: const Icon(Icons.open_in_new_rounded, size: 14),
        label: Text(label),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _buildFooter() {
    if (_currentStep == 3) {
      return TextButton(
        onPressed: _isLoading ? null : _goBack,
        child: const Text('Back to branch details'),
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

  String? _emailValidator(String? value) =>
      RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(value?.trim() ?? '')
          ? null
          : 'Enter a valid email address';

  String _slugify(String value) => value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  Future<void> _showCompanyCreatedDialog({
    required String companyName,
    required String companyCode,
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
          content:
              Text('$companyName is ready. Your company code is $companyCode.'),
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
      {required this.step, required this.label, required this.onBack});
  final int step;
  final String label;
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
            Text('${step + 1} / 4',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: DesignColors.accent)),
          ]),
          const SizedBox(height: 12),
          Row(
              children: List.generate(
                  4,
                  (index) => Expanded(
                        child: AnimatedContainer(
                          duration: DesignAnimation.normal,
                          curve: DesignAnimation.defaultCurve,
                          height: DesignSpacing.xs - 1,
                          margin: EdgeInsets.only(
                              right: index == 3 ? 0 : DesignSpacing.sm - 2),
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
            child: Text('Step ${step + 1} of 4 · $label',
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

class _OptionalLocationDetails extends StatelessWidget {
  const _OptionalLocationDetails({required this.address, required this.phone});
  final Widget address;
  final Widget phone;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: context.themed(DesignColors.darkSurface),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(color: context.themed(DesignColors.darkBorder)),
        ),
        child: ExpansionTile(
          title: const Text('Add location details'),
          subtitle: const Text('Optional · useful on receipts'),
          leading: const Icon(Icons.add_location_alt_outlined,
              color: DesignColors.accent),
          shape: const Border(),
          collapsedShape: const Border(),
          childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          children: [
            address,
            const SizedBox(height: 16),
            phone,
          ],
        ),
      );
}

class _VerificationMethodOption extends StatelessWidget {
  const _VerificationMethodOption({
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          child: AnimatedContainer(
            duration: DesignAnimation.fast,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selected
                  ? DesignColors.accent.withValues(alpha: 0.09)
                  : context.themed(DesignColors.darkSurface),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
              border: Border.all(
                  color: selected
                      ? DesignColors.accent
                      : context.themed(DesignColors.darkBorder)),
            ),
            child: Row(children: [
              Icon(icon,
                  color: selected
                      ? DesignColors.accent
                      : context.themed(DesignColors.darkTextSecondary),
                  size: 29),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: context.themed(DesignColors.darkTextPrimary))),
                  const SizedBox(height: 3),
                  Text(detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              context.themed(DesignColors.darkTextSecondary))),
                ],
              )),
              Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected
                      ? DesignColors.accent
                      : context.themed(DesignColors.darkTextTertiary),
                  size: 20),
            ]),
          )));
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
