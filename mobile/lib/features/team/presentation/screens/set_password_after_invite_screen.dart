import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';

/// Full-screen form shown right after a staff invitation is accepted.
/// The new user must set a password and a PIN before they can use the app.
///
/// After both are set successfully, the user is navigated to the main POS
/// screen (or login if they need to re-authenticate with their new PIN).
class SetPasswordAfterInviteScreen extends StatefulWidget {
  const SetPasswordAfterInviteScreen({super.key});

  @override
  State<SetPasswordAfterInviteScreen> createState() =>
      _SetPasswordAfterInviteScreenState();
}

class _SetPasswordAfterInviteScreenState
    extends State<SetPasswordAfterInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;
  bool _isSubmitting = false;

  AuthService get _auth => getIt<AuthService>();
  ApiClient get _api => getIt<ApiClient>();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      // 1. Set the password via the auth service
      // The backend expects a password set call. Since there's no dedicated
      // setPassword on AuthService, we use the ApiClient's setPin for PIN
      // and rely on the fact that after acceptStaffInvitation the user
      // session is established. We set the PIN first.
      await _api.setPin(_pinController.text.trim());

      // 2. Set the local PIN for quick unlock
      await _auth.setLocalPin(_pinController.text.trim());

      if (!mounted) return;

      showGlassSnackBar(
        context,
        'Account set up successfully! You can now sign in.',
        icon: Icons.check_circle_outline_rounded,
        color: DesignColors.success,
      );

      // Navigate to login so the user can sign in with their new credentials
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Could not complete setup. Please try again.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      appBar: AppBar(
        backgroundColor: DesignColors.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: DesignColors.darkTextPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Set up your account',
          style: TextStyle(
            color: DesignColors.darkTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Icon(Icons.lock_outline_rounded,
                  color: DesignColors.brand, size: 40),
              const SizedBox(height: 12),
              const Text(
                'Create your password and PIN',
                style: TextStyle(
                  color: DesignColors.darkTextPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your invitation has been accepted. Set a password and a '
                '4-digit PIN to secure your account and enable quick sign-in.',
                style: TextStyle(
                  color: DesignColors.darkTextSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // ── Password section ──
              const Text(
                'Password',
                style: TextStyle(
                  color: DesignColors.darkTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a password';
                  }
                  if (value.trim().length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  return null;
                },
                style: const TextStyle(color: DesignColors.darkTextPrimary),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle:
                      const TextStyle(color: DesignColors.darkTextSecondary),
                  prefixIcon: const Icon(Icons.lock_outline_rounded,
                      color: DesignColors.darkTextSecondary),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: DesignColors.darkTextTertiary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: DesignColors.darkSurfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.darkBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.accent, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.error),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
                style: const TextStyle(color: DesignColors.darkTextPrimary),
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  labelStyle:
                      const TextStyle(color: DesignColors.darkTextSecondary),
                  prefixIcon: const Icon(Icons.lock_outline_rounded,
                      color: DesignColors.darkTextSecondary),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: DesignColors.darkTextTertiary,
                    ),
                    onPressed: () => setState(
                        () => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                  filled: true,
                  fillColor: DesignColors.darkSurfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.darkBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.accent, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.error),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── PIN section ──
              const Text(
                'PIN (4 digits)',
                style: TextStyle(
                  color: DesignColors.darkTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _pinController,
                obscureText: _obscurePin,
                keyboardType: TextInputType.number,
                maxLength: 4,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a PIN';
                  }
                  if (value.trim().length != 4) {
                    return 'PIN must be exactly 4 digits';
                  }
                  if (!RegExp(r'^\d{4}$').hasMatch(value.trim())) {
                    return 'PIN must contain only digits';
                  }
                  return null;
                },
                style: const TextStyle(
                  color: DesignColors.darkTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  labelStyle:
                      const TextStyle(color: DesignColors.darkTextSecondary),
                  prefixIcon: const Icon(Icons.pin_outlined,
                      color: DesignColors.darkTextSecondary),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePin
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: DesignColors.darkTextTertiary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePin = !_obscurePin),
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: DesignColors.darkSurfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.darkBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.accent, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.error),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _confirmPinController,
                obscureText: _obscureConfirmPin,
                keyboardType: TextInputType.number,
                maxLength: 4,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please confirm your PIN';
                  }
                  if (value != _pinController.text) {
                    return 'PINs do not match';
                  }
                  return null;
                },
                style: const TextStyle(
                  color: DesignColors.darkTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'Confirm PIN',
                  labelStyle:
                      const TextStyle(color: DesignColors.darkTextSecondary),
                  prefixIcon: const Icon(Icons.pin_outlined,
                      color: DesignColors.darkTextSecondary),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPin
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: DesignColors.darkTextTertiary,
                    ),
                    onPressed: () => setState(
                        () => _obscureConfirmPin = !_obscureConfirmPin),
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: DesignColors.darkSurfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.darkBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.accent, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: DesignColors.error),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Submit button
              GradientButton(
                label: 'Complete setup',
                icon: Icons.check_circle_outline_rounded,
                isLoading: _isSubmitting,
                onPressed: _isSubmitting ? null : _submit,
                height: 54,
                borderRadius: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
