import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/update_check_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';

String companySetupErrorMessage(Object error) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    final serverMessage = _serverErrorMessage(error.response?.data);
    final normalized = serverMessage?.toLowerCase() ?? '';

    if (normalized.contains('already exists') ||
        normalized.contains('company with this slug')) {
      return 'A workspace with this name already exists. Choose a different name.';
    }
    if (normalized.contains('email')) {
      return 'This email is already registered. Use another email or sign in.';
    }

    switch (statusCode) {
      case 400:
      case 422:
        return 'Check the workspace details and try again.';
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 409:
        return 'A workspace with these details already exists.';
    }

    if (statusCode != null && statusCode >= 500) {
      return 'Axon could not create your workspace right now. Try again in a moment.';
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The connection timed out. Check your network and try again.';
      case DioExceptionType.connectionError:
        return 'We could not reach Axon. Check your connection and try again.';
      default:
        break;
    }
  }

  final normalized = error.toString().toLowerCase();
  if (normalized.contains('already exists')) {
    return 'A workspace with this name already exists. Choose a different name.';
  }
  if (normalized.contains('email')) {
    return 'This email is already registered. Use another email or sign in.';
  }
  return 'We could not create your workspace. Please try again.';
}

String? _serverErrorMessage(Object? data) {
  if (data is! Map) return null;
  final message = data['message'];
  if (message is String && message.trim().isNotEmpty) return message.trim();
  if (message is List && message.isNotEmpty) {
    return message.map((item) => item.toString()).join(' ');
  }
  return null;
}

/// Collects company, admin account, and first-branch details to
/// register a new tenant. Part of the first-time setup flow.
class CompanySetupScreen extends ConsumerStatefulWidget {
  const CompanySetupScreen({super.key});

  @override
  ConsumerState<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends ConsumerState<CompanySetupScreen> {
  final _formKey = GlobalKey<FormState>();

  // Company fields
  final _companyNameController = TextEditingController();
  File? _logoFile; // local preview
  // When set, the picked logo is traced into a crisp scalable SVG on upload
  // (deterministic vectorization) instead of stored as a raster image.
  final bool _vectorizeLogo = false;

  // Admin fields
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  // Branch fields
  final _branchNameController = TextEditingController();
  final _branchCodeController = TextEditingController();
  final _branchAddressController = TextEditingController();
  final _branchPhoneController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  int _currentStep = 0;

  @override
  void dispose() {
    _companyNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _branchNameController.dispose();
    _branchCodeController.dispose();
    _branchAddressController.dispose();
    _branchPhoneController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() {
      _logoFile = File(image.path);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiClient = getIt<ApiClient>();
      final authService = getIt<AuthService>();

      final response = await apiClient.registerCompany(
        companyName: _companyNameController.text.trim(),
        adminEmail: _emailController.text.trim(),
        adminPassword: _passwordController.text,
        adminFirstName: _firstNameController.text.trim(),
        adminLastName: _lastNameController.text.trim(),
        branchName: _branchNameController.text.trim(),
        branchCode: _branchCodeController.text.trim().toUpperCase(),
        branchAddress: _branchAddressController.text.trim().isNotEmpty
            ? _branchAddressController.text.trim()
            : null,
        branchPhone: _branchPhoneController.text.trim().isNotEmpty
            ? _branchPhoneController.text.trim()
            : null,
        deviceId: authService.deviceId,
      );

      await authService.applyAuthResponse(response);

      if (_logoFile != null) {
        try {
          final fileName = _logoFile!.uri.pathSegments.isNotEmpty
              ? _logoFile!.uri.pathSegments.last
              : 'company-logo.jpg';

          // Vectorize into an SVG when requested (crisp at any receipt/print
          // size); otherwise store the raster image as before.
          String? logoUrl;
          String? logoPublicId;
          if (_vectorizeLogo) {
            final v = await apiClient.vectorizeLogo(
              filePath: _logoFile!.path,
              fileName: fileName,
            );
            logoUrl = (v['svgUrl'] ?? v['rasterUrl']) as String?;
            logoPublicId = v['publicId'] as String?;
          } else {
            final uploadResult = await apiClient.uploadImage(
              filePath: _logoFile!.path,
              fileName: fileName,
              type: 'logo',
            );
            logoUrl = uploadResult['url'] as String?;
            logoPublicId = uploadResult['publicId'] as String?;
          }

          final updatedTenant = await apiClient.updateCurrentTenant(
            logo: logoUrl,
            logoPublicId: logoPublicId,
          );

          await authService.updateTenantSession({
            'id': updatedTenant['id'],
            'name': updatedTenant['name'],
            'slug': updatedTenant['slug'],
            'logo': updatedTenant['logo'],
            'logoPublicId': updatedTenant['logoPublicId'],
            'settings': updatedTenant['settings'],
            'isActive': updatedTenant['isActive'],
          });
        } catch (e, stackTrace) {
          debugPrint('[CompanySetup] Logo upload failed: $e');
          debugPrint('$stackTrace');
          if (mounted) {
            showGlassSnackBar(
              context,
              'Company created, but the logo upload did not finish. You can update it later in settings.',
              icon: Icons.warning_amber_rounded,
              color: DesignColors.warning,
            );
          }
        }
      }

      if (mounted) {
        final user = response['user'] as Map<String, dynamic>?;
        final companyCode = (user?['tenantSlug'] as String?) ??
            _slugify(_companyNameController.text.trim());
        final companyName =
            (user?['tenant'] as Map<String, dynamic>?)?['name'] as String? ??
                _companyNameController.text.trim();

        await _showCompanyCreatedDialog(
          companyName: companyName,
          companyCode: companyCode,
        );

        if (!mounted) return;
        unawaited(getIt<UpdateCheckService>().checkAfterLogin());
        // The owner already gets a dedicated welcome screen right after
        // signup — running the generic staff coach-mark tour immediately
        // afterward on the same device would be redundant.
        await getIt<StorageService>().setHasSeenStaffTour(true);
        if (!mounted) return;
        context.go(
          authService.requiresTenantActivation
              ? '/activation'
              : '/owner-welcome',
          extra: companyName,
        );
      }
    } catch (e) {
      final errorMsg = companySetupErrorMessage(e);

      setState(() {
        _errorMessage = errorMsg;
      });

      if (mounted) {
        showGlassSnackBar(
          context,
          errorMsg,
          icon: Icons.error_rounded,
          color: DesignColors.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _buildWizard();

  Widget _buildWizard() {
    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      body: SafeArea(
        child: Stack(
          children: [
            _buildSetupAmbientField(),
            Column(
              children: [
                _buildWizardHeader(),
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                      child: Column(
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 420),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final slide = Tween<Offset>(
                                begin: const Offset(0.08, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: slide,
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey(_currentStep),
                              child: _buildWizardStep(),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildWizardFooter(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupAmbientField() {
    final size = MediaQuery.sizeOf(context);
    return Positioned(
      left: -size.width * 0.28,
      right: -size.width * 0.28,
      bottom: -size.height * 0.22,
      height: size.width * 1.05,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0.86, end: 1.0),
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  DesignColors.brand.withValues(alpha: 0.10),
                  DesignColors.accent.withValues(alpha: 0.035),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.34, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWizardHeader() {
    const labels = [
      'Workspace identity',
      'Owner profile',
      'Secure access',
      'First counter',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _goBack,
                  child: Ink(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: DesignColors.darkTextPrimary,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'AXON / SETUP',
                  style: TextStyle(
                    color: DesignColors.darkTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                  ),
                ),
              ),
              Text(
                '${_currentStep + 1} / 4',
                style: const TextStyle(
                  color: DesignColors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: List.generate(4, (index) {
              final active = index <= _currentStep;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  height: 4,
                  margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
                  decoration: BoxDecoration(
                    color:
                        active ? DesignColors.accent : DesignColors.darkBorder,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color:
                                  DesignColors.accent.withValues(alpha: 0.28),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: Text(
                'Step ${_currentStep + 1} of 4 · ${labels[_currentStep]}',
                key: ValueKey(_currentStep),
                style: const TextStyle(
                  color: DesignColors.darkTextTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWizardStep() {
    late String title;
    late String subtitle;
    late List<Widget> fields;

    switch (_currentStep) {
      case 0:
        title = 'Build your workspace';
        subtitle = 'Start with the identity your team and customers will see.';
        fields = [
          _buildLogoPicker(true),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _companyNameController,
            label: 'Company name',
            hint: 'Your business name',
            icon: Icons.business_rounded,
            isDark: true,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Company name is required';
              }
              if (value.trim().length < 2) return 'Company name is too short';
              if (value.trim().length > 100) {
                return 'Company name must be 100 characters or fewer';
              }
              if (!RegExp(r"^[a-zA-Z0-9\s&'-]+$").hasMatch(value.trim())) {
                return "Only letters, numbers, spaces, &, ' and - are allowed";
              }
              return null;
            },
          ),
        ];
        break;
      case 1:
        title = 'Meet the owner';
        subtitle = 'Tell us who will be the first person in control.';
        fields = [
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _firstNameController,
                  label: 'First name',
                  hint: 'John',
                  icon: Icons.person_outline_rounded,
                  isDark: true,
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _lastNameController,
                  label: 'Last name',
                  hint: 'Doe',
                  icon: Icons.person_outline_rounded,
                  isDark: true,
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
              ),
            ],
          ),
        ];
        break;
      case 2:
        title = 'Secure your account';
        subtitle = 'Use an email and password you can access when you need us.';
        fields = [
          _buildTextField(
            controller: _emailController,
            label: 'Email address',
            hint: 'admin@yourcompany.com',
            icon: Icons.email_outlined,
            isDark: true,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Email is required';
              }
              if (!RegExp(r'^[\w.-]+@([\w-]+\.)+[\w-]{2,}$')
                  .hasMatch(value.trim())) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _passwordController,
            label: 'Password',
            hint: 'At least 8 characters',
            icon: Icons.lock_outline_rounded,
            isDark: true,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: DesignColors.darkTextSecondary,
              ),
              onPressed: () => setState(
                () => _obscurePassword = !_obscurePassword,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Password is required';
              if (value.length < 8) return 'Use at least 8 characters';
              if (!RegExp(r'[A-Z]').hasMatch(value)) {
                return 'Include one uppercase letter';
              }
              if (!RegExp(r'[0-9]').hasMatch(value)) {
                return 'Include one number';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _confirmPasswordController,
            label: 'Confirm password',
            hint: 'Re-enter your password',
            icon: Icons.lock_outline_rounded,
            isDark: true,
            obscureText: _obscureConfirmPassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: DesignColors.darkTextSecondary,
              ),
              onPressed: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
        ];
        break;
      default:
        title = 'Open your first counter';
        subtitle = 'Add the location where your first sale will happen.';
        fields = [
          _buildTextField(
            controller: _branchNameController,
            label: 'Branch name',
            hint: 'Main Store',
            icon: Icons.store_rounded,
            isDark: true,
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Required';
              if (value.trim().length < 2) return 'Too short';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _branchCodeController,
            label: 'Branch code',
            hint: 'MAIN',
            icon: Icons.tag_rounded,
            isDark: true,
            inputFormatters: [
              UpperCaseTextFormatter(),
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(10),
            ],
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Required';
              if (value.trim().length < 2) return 'Too short';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _branchAddressController,
            label: 'Address (optional)',
            hint: '123 Main Street, City',
            icon: Icons.location_on_outlined,
            isDark: true,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _branchPhoneController,
            label: 'Phone (optional)',
            hint: '+254 700 000 000',
            icon: Icons.phone_outlined,
            isDark: true,
            keyboardType: TextInputType.phone,
          ),
        ];
    }

    return Column(
      key: ValueKey('step-content-$_currentStep'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            color: DesignColors.darkTextPrimary,
            fontSize: 32,
            height: 1.05,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: const TextStyle(
            color: DesignColors.darkTextSecondary,
            fontSize: 16,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        ...fields,
        if (_errorMessage != null) ...[
          const SizedBox(height: 20),
          _buildWizardError(),
        ],
      ],
    );
  }

  Widget _buildWizardError() {
    return Semantics(
      liveRegion: true,
      label: 'Error: $_errorMessage',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DesignColors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: DesignColors.error.withValues(alpha: 0.34),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: DesignColors.error.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: DesignColors.error,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Couldn’t create workspace',
                    style: TextStyle(
                      color: DesignColors.darkTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: DesignColors.darkTextSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Dismiss error',
              onPressed: () => setState(() => _errorMessage = null),
              icon: const Icon(
                Icons.close_rounded,
                color: DesignColors.darkTextTertiary,
                size: 19,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWizardFooter() {
    final actionButton = GradientButton(
      label: _currentStep == 3 ? 'Create Company' : 'Continue',
      icon: _currentStep == 3
          ? Icons.rocket_launch_rounded
          : Icons.arrow_forward_rounded,
      isLoading: _isLoading,
      onPressed: _isLoading ? null : _nextStep,
      height: 54,
      borderRadius: 16,
    );

    return SafeArea(
      top: false,
      child: _currentStep == 0
          ? SizedBox(
              width: double.infinity,
              child: actionButton,
            )
          : Row(
              children: [
                TextButton(
                  onPressed: _goBack,
                  child: const Text(
                    'Back',
                    style: TextStyle(color: DesignColors.darkTextSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: actionButton),
              ],
            ),
    );
  }

  void _goBack() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep -= 1;
        _errorMessage = null;
      });
    } else {
      context.go('/company-choice');
    }
  }

  void _nextStep() {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_currentStep == 3) {
      unawaited(_submit());
      return;
    }
    setState(() {
      _currentStep += 1;
      _errorMessage = null;
    });
  }

  Future<void> _showCompanyCreatedDialog({
    required String companyName,
    required String companyCode,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: DesignColors.success.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: DesignColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Company Ready',
                  style: TextStyle(
                    color: isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary,
                  ),
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? DesignColors.darkTextPrimary
                      : DesignColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Use this company code when logging in on this phone or another staff device.',
                style: TextStyle(
                  color: isDark
                      ? DesignColors.darkTextSecondary
                      : DesignColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: DesignColors.brand.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: DesignColors.brand.withValues(alpha: 0.25),
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
                          letterSpacing: 0.4,
                          color: DesignColors.brand,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy company code',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: companyCode),
                        );
                        if (!mounted) return;
                        showGlassSnackBar(
                          context,
                          'Company code copied. Save it somewhere safe.',
                          icon: Icons.copy_rounded,
                          color: DesignColors.success,
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Please save this code. Staff will need it together with their email and password.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? DesignColors.darkTextSecondary
                      : DesignColors.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('I Saved It'),
            ),
          ],
        );
      },
    );
  }

  String _slugify(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Widget _buildLogoPicker(bool isDark) {
    return InkWell(
      onTap: _pickLogo,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: DesignColors.darkSurfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DesignColors.darkBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: DesignColors.darkBorder,
                shape: BoxShape.circle,
              ),
              child: _logoFile != null
                  ? ClipOval(
                      child: Image.file(
                        _logoFile!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 28,
                      color: DesignColors.darkTextSecondary,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _logoFile != null ? 'Logo selected' : 'Add Company Logo',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: DesignColors.darkTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _logoFile != null
                        ? 'The logo uploads after your company is created'
                        : 'Optional - PNG or JPG',
                    style: const TextStyle(
                      fontSize: 13,
                      color: DesignColors.darkTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: DesignColors.darkTextTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    AutovalidateMode? autovalidateMode,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: DesignColors.darkTextSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          autovalidateMode: autovalidateMode,
          style: const TextStyle(
            fontSize: 15,
            color: DesignColors.darkTextPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: DesignColors.darkTextTertiary),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(
                icon,
                size: 20,
                color: DesignColors.darkTextSecondary,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 44),
            suffixIcon: suffixIcon,
            errorMaxLines: 2,
            filled: true,
            fillColor: DesignColors.darkSurfaceElevated,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.darkBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: DesignColors.darkBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: DesignColors.brand,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: DesignColors.error,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: DesignColors.error,
                width: 1.5,
              ),
            ),
            errorStyle: const TextStyle(
              color: DesignColors.error,
              fontSize: 12,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}

/// Input formatter that converts text to uppercase.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
