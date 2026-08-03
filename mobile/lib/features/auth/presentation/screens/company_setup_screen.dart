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
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';

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
      return 'Axon could not create your workspace right now. Try again shortly.';
    }
    if (error.type == DioExceptionType.connectionError) {
      return 'We could not reach Axon. Check your connection and try again.';
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
  String? _errorMessage;
  String? _challengeId;
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
          email: _emailController.text.trim(),
        ),
      );

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _createWithGoogle() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final account =
          await GoogleSignIn(serverClientId: googleWebClientId).signIn();
      if (account == null) return;
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
    unawaited(getIt<UpdateCheckService>().checkAfterLogin());
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
      setState(() {
        _currentStep += 1;
        _errorMessage = null;
      });
    }
  }

  void _goBack() {
    if (_isLoading) return;
    if (_currentStep == 0) {
      context.go('/company-choice');
      return;
    }
    setState(() {
      _currentStep -= 1;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Workspace identity',
      'Owner profile',
      'First counter',
      'Verify ownership',
    ];
    return Scaffold(
      backgroundColor: DesignColors.darkBg,
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
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
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
                      const SizedBox(height: 24),
                      _buildFooter(),
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

  Widget _buildStep() {
    switch (_currentStep) {
      case 0:
        return _StepContent(
          title: 'Build your workspace',
          subtitle:
              'Start with the business identity your team and customers will see.',
          children: [
            _field(
              _companyNameController,
              label: 'Company name',
              hint: 'Your business name',
              icon: Icons.business_rounded,
              validator: _companyValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
          ],
        );
      case 1:
        return _StepContent(
          title: 'Meet the owner',
          subtitle:
              'Tell us who will control this workspace. We will verify this identity next.',
          children: [
            Row(children: [
              Expanded(
                child: _field(
                  _firstNameController,
                  label: 'First name',
                  hint: 'Ada',
                  icon: Icons.person_outline_rounded,
                  validator: _requiredName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  _lastNameController,
                  label: 'Last name',
                  hint: 'Lovelace',
                  icon: Icons.person_outline_rounded,
                  validator: _requiredName,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            _field(
              _emailController,
              label: 'Owner email',
              hint: 'owner@business.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: _emailValidator,
            ),
          ],
        );
      case 2:
        return _StepContent(
          title: 'Open your first counter',
          subtitle: 'Add the location where your first sale will happen.',
          children: [
            _field(
              _branchNameController,
              label: 'Branch name',
              hint: 'Main Store',
              icon: Icons.store_rounded,
              validator: (value) => value == null || value.trim().length < 2
                  ? 'Enter at least 2 characters'
                  : null,
            ),
            const SizedBox(height: 16),
            _field(
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
            ),
            const SizedBox(height: 16),
            _field(
              _branchAddressController,
              label: 'Address (optional)',
              hint: '123 Main Street, City',
              icon: Icons.location_on_outlined,
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            _field(
              _branchPhoneController,
              label: 'Phone (optional)',
              hint: '+254 700 000 000',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
          ],
        );
      default:
        return _buildVerificationStep();
    }
  }

  Widget _buildVerificationStep() {
    final email = _emailController.text.trim();
    return _StepContent(
      title: 'Verify your ownership',
      subtitle: _verificationMode == _VerificationMode.google
          ? 'Use your Google account to securely verify the first workspace owner.'
          : 'We sent a code to $email. Enter it below to verify your email ownership.',
      children: [
        if (_verificationMode == _VerificationMode.google) ...[
          _VerificationCard(
            icon: Icons.verified_user_outlined,
            title: 'Google verification',
            subtitle:
                'Recommended — Google verifies your identity before workspace creation.',
            child: GradientButton(
              label: 'Verify with Google & create workspace',
              icon: Icons.g_mobiledata_rounded,
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _createWithGoogle,
              height: 54,
              borderRadius: 14,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _isLoading ? null : _requestEmailOtp,
            icon: const Icon(Icons.email_outlined),
            label: const Text('Use an email code instead'),
          ),
        ] else ...[
          _VerificationCard(
            icon: Icons.mark_email_read_outlined,
            title: 'Email verification code',
            subtitle:
                'Only the owner who can access this inbox can create the workspace.',
            child: _field(
              _otpController,
              label: '6–8 digit code',
              hint: 'Enter the code',
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
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Verify email & create workspace',
            icon: Icons.verified_rounded,
            isLoading: _isLoading,
            onPressed: _isLoading ? null : _createWithEmailOtp,
            height: 54,
            borderRadius: 14,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isLoading ? null : _requestEmailOtp,
            child: const Text('Resend code'),
          ),
          TextButton(
            onPressed: _isLoading
                ? null
                : () => setState(() {
                      _verificationMode = _VerificationMode.google;
                      _challengeId = null;
                      _otpController.clear();
                    }),
            child: const Text('Use Google instead'),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Axon does not collect or store an owner password during workspace setup.',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: DesignColors.darkTextTertiary, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

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
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: DesignColors.darkTextSecondary)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            validator: validator,
            keyboardType: keyboardType,
            maxLines: maxLines,
            inputFormatters: inputFormatters,
            autovalidateMode: autovalidateMode,
            style: const TextStyle(color: DesignColors.darkTextPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: DesignColors.darkTextTertiary),
              prefixIcon: Icon(icon, color: DesignColors.darkTextSecondary),
              filled: true,
              fillColor: DesignColors.darkSurfaceElevated,
              errorMaxLines: 2,
              border: _inputBorder(DesignColors.darkBorder),
              enabledBorder: _inputBorder(DesignColors.darkBorder),
              focusedBorder: _inputBorder(DesignColors.brand, width: 1.5),
              errorBorder: _inputBorder(DesignColors.error),
              focusedErrorBorder: _inputBorder(DesignColors.error, width: 1.5),
            ),
          ),
        ],
      );

  OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded,
                  color: DesignColors.darkTextPrimary),
            ),
            const Expanded(
              child: Text('AXON / SETUP',
                  style: TextStyle(
                      color: DesignColors.darkTextSecondary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
            ),
            Text('${step + 1} / 4',
                style: const TextStyle(
                    color: DesignColors.accent, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          Row(
              children: List.generate(
                  4,
                  (index) => Expanded(
                        child: Container(
                          height: 4,
                          margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
                          decoration: BoxDecoration(
                            color: index <= step
                                ? DesignColors.accent
                                : DesignColors.darkBorder,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ))),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Step ${step + 1} of 4 · $label',
                style: const TextStyle(
                    color: DesignColors.darkTextTertiary, fontSize: 12)),
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
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: DesignColors.darkTextPrimary,
                fontSize: 30,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text(subtitle,
            style: const TextStyle(
                color: DesignColors.darkTextSecondary,
                fontSize: 16,
                height: 1.4)),
        const SizedBox(height: 28),
        ...children,
      ]);
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.child});
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: DesignColors.darkSurfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DesignColors.darkBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: DesignColors.accent),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  color: DesignColors.darkTextPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                  color: DesignColors.darkTextSecondary, height: 1.4)),
          const SizedBox(height: 18),
          child,
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
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: DesignColors.error.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            const Icon(Icons.error_outline_rounded, color: DesignColors.error),
            const SizedBox(width: 12),
            Expanded(
                child: Text(message,
                    style: const TextStyle(
                        color: DesignColors.darkTextSecondary))),
            IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded,
                    color: DesignColors.darkTextTertiary)),
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
