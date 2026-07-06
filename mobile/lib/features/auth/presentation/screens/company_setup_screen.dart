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
import 'package:axon_pos/core/theme/design_system.dart';

/// Collects company, admin account, and first-branch details to
/// register a new tenant. Part of the first-time setup flow.
class CompanySetupScreen extends ConsumerStatefulWidget {
  const CompanySetupScreen({super.key});

  @override
  ConsumerState<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends ConsumerState<CompanySetupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Company fields
  final _companyNameController = TextEditingController();
  File? _logoFile; // local preview

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

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: DesignAnimation.normal,
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: DesignAnimation.defaultCurve,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scrollController.dispose();
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
          final uploadResult = await apiClient.uploadImage(
            filePath: _logoFile!.path,
            fileName: _logoFile!.uri.pathSegments.isNotEmpty
                ? _logoFile!.uri.pathSegments.last
                : 'company-logo.jpg',
            type: 'logo',
          );

          final updatedTenant = await apiClient.updateCurrentTenant(
            logo: uploadResult['url'] as String?,
            logoPublicId: uploadResult['publicId'] as String?,
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
        context.go('/');
      }
    } catch (e) {
      String errorMsg;
      if (e is DioException) {
        final url = e.requestOptions.uri.toString();
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
          case DioExceptionType.receiveTimeout:
          case DioExceptionType.sendTimeout:
            errorMsg = 'Connection timed out.\nURL: $url';
            break;
          case DioExceptionType.connectionError:
            errorMsg = 'Cannot reach server.\nURL: $url\n${e.message ?? ''}';
            break;
          case DioExceptionType.badResponse:
            final code = e.response?.statusCode;
            final body = e.response?.data?.toString() ?? '';
            errorMsg = 'Server error $code.\n$body';
            break;
          default:
            errorMsg = 'Network error: ${e.message ?? e.type.name}';
            break;
        }
      } else if (e.toString().contains('already exists')) {
        errorMsg = 'A company with this name already exists';
      } else if (e.toString().contains('email')) {
        errorMsg = 'This email is already registered';
      } else {
        errorMsg = 'Failed to create company: ${e.toString()}';
      }

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
  Widget build(BuildContext context) {
    // This flow always renders on the dark Axon setup canvas, matching
    // the company-choice screen it's reached from — not tied to the
    // device theme, since it's a focused first-run task, not app chrome.
    const isDark = true;
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 700;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: DesignColors.darkBg,
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(isDark),

              // Form
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: isSmallScreen ? 16 : 24),

                          // Company section
                          _buildSectionTitle('Company Details', isDark),
                          const SizedBox(height: 16),
                          _buildLogoField(isDark),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _companyNameController,
                            label: 'Company Name',
                            hint: 'Your Business Name',
                            icon: Icons.business_rounded,
                            isDark: isDark,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Company name is required';
                              }
                              if (value.trim().length < 2) {
                                return 'Company name is too short';
                              }
                              return null;
                            },
                          ),

                          SizedBox(height: isSmallScreen ? 24 : 32),

                          // Admin section
                          _buildSectionTitle('Admin Account', isDark),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  controller: _firstNameController,
                                  label: 'First Name',
                                  hint: 'John',
                                  icon: Icons.person_outline_rounded,
                                  isDark: isDark,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: _lastNameController,
                                  label: 'Last Name',
                                  hint: 'Doe',
                                  icon: Icons.person_outline_rounded,
                                  isDark: isDark,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _emailController,
                            label: 'Email Address',
                            hint: 'admin@yourcompany.com',
                            icon: Icons.email_outlined,
                            isDark: isDark,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Email is required';
                              }
                              final emailRegex =
                                  RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$');
                              if (!emailRegex.hasMatch(value.trim())) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _passwordController,
                            label: 'Password',
                            hint: 'Create a strong password',
                            icon: Icons.lock_outline_rounded,
                            isDark: isDark,
                            obscureText: _obscurePassword,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: DesignColors.darkTextSecondary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Password is required';
                              }
                              if (value.length < 8) {
                                return 'Password must be at least 8 characters';
                              }
                              if (!RegExp(r'[A-Z]').hasMatch(value)) {
                                return 'Include at least one uppercase letter';
                              }
                              if (!RegExp(r'[0-9]').hasMatch(value)) {
                                return 'Include at least one number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _confirmPasswordController,
                            label: 'Confirm Password',
                            hint: 'Re-enter your password',
                            icon: Icons.lock_outline_rounded,
                            isDark: isDark,
                            obscureText: _obscureConfirmPassword,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: DesignColors.darkTextSecondary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
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

                          SizedBox(height: isSmallScreen ? 24 : 32),

                          // Branch section
                          _buildSectionTitle('First Branch', isDark),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: _buildTextField(
                                  controller: _branchNameController,
                                  label: 'Branch Name',
                                  hint: 'Main Store',
                                  icon: Icons.store_rounded,
                                  isDark: isDark,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTextField(
                                  controller: _branchCodeController,
                                  label: 'Code',
                                  hint: 'MAIN',
                                  icon: Icons.tag_rounded,
                                  isDark: isDark,
                                  inputFormatters: [
                                    UpperCaseTextFormatter(),
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[A-Za-z0-9]')),
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _branchAddressController,
                            label: 'Address (optional)',
                            hint: '123 Main Street, City',
                            icon: Icons.location_on_outlined,
                            isDark: isDark,
                            maxLines: 2,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _branchPhoneController,
                            label: 'Phone (optional)',
                            hint: '+1 (555) 123-4567',
                            icon: Icons.phone_outlined,
                            isDark: isDark,
                            keyboardType: TextInputType.phone,
                          ),

                          const SizedBox(height: 32),

                          // Error message
                          if (_errorMessage != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color:
                                    DesignColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      DesignColors.error.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: DesignColors.error,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        color: DesignColors.error,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Submit button
                          GradientButton(
                            onPressed: _isLoading ? null : _submit,
                            label: 'Create Company',
                            isLoading: _isLoading,
                          ),

                          const SizedBox(height: 16),

                          // Back to choice
                          Center(
                            child: TextButton(
                              onPressed: () => context.go('/company-choice'),
                              child: const Text(
                                'Back to options',
                                style: TextStyle(
                                  color: DesignColors.darkTextSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: DesignColors.darkTextPrimary,
            ),
            onPressed: () => context.go('/company-choice'),
          ),
          const SizedBox(width: 4),
          Text(
            'Register your company',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: DesignColors.darkTextPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: DesignColors.darkTextPrimary,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildLogoField(bool isDark) {
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
              decoration: BoxDecoration(
                color: DesignColors.darkBorder,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _logoFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
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
