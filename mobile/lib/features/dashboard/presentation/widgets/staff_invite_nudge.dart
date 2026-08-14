import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/di/injection.dart';

/// A persistent nudge banner shown on the dashboard when the current tenant
/// has no staff beyond the admin (i.e. the `invite_staff` onboarding step is
/// not yet COMPLETED).
///
/// The nudge reappears on every app launch/session until at least one
/// invitation is accepted.  "Remind Later" dismisses it for the current
/// session only — the flag lives in widget state and is lost on rebuild.
class StaffInviteNudge extends StatefulWidget {
  /// Override the API call for testing.
  final Future<Map<String, dynamic>> Function()? onboardingLoader;

  const StaffInviteNudge({super.key, this.onboardingLoader});

  @override
  State<StaffInviteNudge> createState() => _StaffInviteNudgeState();
}

class _StaffInviteNudgeState extends State<StaffInviteNudge> {
  bool _dismissedThisSession = false;
  bool _isLoading = true;
  bool _showNudge = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _checkStaffStatus();
  }

  @override
  void didUpdateWidget(covariant StaffInviteNudge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check on every dashboard rebuild so the nudge stays in sync
    // with the onboarding state (e.g. after returning from /invite-staff).
    _checkStaffStatus();
  }

  Future<void> _checkStaffStatus() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final result = await (widget.onboardingLoader?.call() ??
          getIt<ApiClient>().getTenantOnboarding());
      final steps = result['steps'];
      if (steps is List) {
        final inviteStep = steps.cast<Map>().firstWhere(
              (s) => s['key'] == 'invite_staff',
              orElse: () => <String, dynamic>{},
            );
        final status = inviteStep['status']?.toString() ?? '';
        // Show nudge when the step is anything other than COMPLETED
        // (PENDING, DEFERRED, or absent).
        if (mounted) {
          setState(() => _showNudge = status != 'COMPLETED');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading ||
        _loadError != null ||
        _dismissedThisSession ||
        !_showNudge) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final subtitleColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final borderColor =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final btnFgColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: InkRipple.splashFactory,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                DesignColors.brand.withValues(alpha: 0.10),
                DesignColors.accent.withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: DesignColors.accent.withValues(alpha: 0.25),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DesignColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.group_add_rounded,
                      color: DesignColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invite your team',
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Add staff members to help manage sales, inventory, and reports.',
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: GradientButton(
                        label: 'Invite Staff Now',
                        icon: Icons.send_rounded,
                        onPressed: () => context.push('/users'),
                        height: 42,
                        borderRadius: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => _dismissedThisSession = true);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: btnFgColor,
                        side: BorderSide(
                          color: borderColor,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Remind Later',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: btnFgColor),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
