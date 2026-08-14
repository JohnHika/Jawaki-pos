import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';

/// Full-screen form that accepts a staff invitation by asking the invitee
/// for the OTP code they received via email. On success it navigates to
/// [SetPasswordAfterInviteScreen] so the new user can set their password
/// and PIN.
///
/// The [invitationId] and [challengeId] come from the invitation email
/// link (or are passed as route parameters from the join flow).
class AcceptInviteScreen extends StatefulWidget {
  final String invitationId;
  final String challengeId;

  const AcceptInviteScreen({
    super.key,
    required this.invitationId,
    required this.challengeId,
  });

  @override
  State<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends State<AcceptInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isSubmitting = false;

  AuthService get _auth => getIt<AuthService>();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      await _auth.acceptStaffInvitation(
        invitationId: widget.invitationId,
        challengeId: widget.challengeId,
        code: _codeController.text.trim(),
      );
      if (!mounted) return;

      // Navigate to set-password/PIN screen on success
      context.pushReplacement('/set-password-after-invite');
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'The invitation code could not be verified. Please check and try again.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      child: Scaffold(
        backgroundColor: DesignColors.darkBg,
        appBar: AppBar(
          backgroundColor: DesignColors.darkSurface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: DesignColors.darkTextPrimary),
            onPressed: () => context.pop(),
          ),
          title: const Text(
            'Accept Invitation',
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
                const Icon(Icons.mail_lock_rounded,
                    color: DesignColors.brand, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Enter your invitation code',
                  style: TextStyle(
                    color: DesignColors.darkTextPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'A verification code was sent to your email. '
                  'Enter it below to accept the invitation and join your team.',
                  style: TextStyle(
                    color: DesignColors.darkTextSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // OTP / Code field
                TextFormField(
                  controller: _codeController,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter the code from your email';
                    }
                    if (value.trim().length < 4) {
                      return 'The code must be at least 4 characters';
                    }
                    return null;
                  },
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  style: const TextStyle(
                    color: DesignColors.darkTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: 'Verification code',
                    labelStyle:
                        const TextStyle(color: DesignColors.darkTextSecondary),
                    hintText: '000000',
                    hintStyle: TextStyle(
                      color:
                          DesignColors.darkTextTertiary.withValues(alpha: 0.5),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                    prefixIcon: const Icon(Icons.pin_outlined,
                        color: DesignColors.darkTextSecondary),
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
                      borderSide: const BorderSide(
                          color: DesignColors.accent, width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: DesignColors.error),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Submit button
                GradientButton(
                  label: 'Accept invitation',
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
      ),
    );
  }
}
