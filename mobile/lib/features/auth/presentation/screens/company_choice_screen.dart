import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/theme/design_system.dart';

/// First-launch screen: sign in to the business account, or create a
/// device-local workspace. Kept deliberately plain — a standard mobile
/// onboarding with one primary action and one secondary.
class CompanyChoiceScreen extends StatelessWidget {
  const CompanyChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.themed(DesignColors.darkBg),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: DesignColors.accent,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/axon_app_icon_512.png',
                      fit: BoxFit.cover,
                      semanticLabel: 'Counterbase',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Welcome to Counterbase',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: context.themed(DesignColors.darkTextPrimary),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'Run your counter, stock and daily sales.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.themed(DesignColors.darkTextSecondary),
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 40),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: DesignColors.accent,
                  foregroundColor: DesignColors.textInverse,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.login_rounded),
                label: const Text(
                  'Sign in',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: () => context.go('/login'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.themed(DesignColors.darkTextPrimary),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  side: BorderSide(
                    color: context.themed(DesignColors.darkBorder),
                  ),
                ),
                icon: const Icon(Icons.storefront_rounded),
                label: const Text(
                  'Set up on this device only',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onPressed: () => context.go('/company-setup'),
              ),
              const SizedBox(height: 16),
              Text(
                'Device-only setup keeps records on this phone. '
                'Sign in to reach your business across devices.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.themed(DesignColors.darkTextTertiary),
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => context.go('/legal/terms'),
                  child: const Text(
                    'Terms & conditions',
                    style: TextStyle(
                      color: DesignColors.info,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
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
}
