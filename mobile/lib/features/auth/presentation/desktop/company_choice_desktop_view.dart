import 'package:flutter/material.dart';

import 'auth_desktop_kit.dart';

/// First screen on a new computer: start a shop here, bring this computer
/// into a shop that already exists, or sign in to an online account.
class CompanyChoiceDesktopView extends StatelessWidget {
  const CompanyChoiceDesktopView({
    super.key,
    required this.onStartNew,
    required this.onJoin,
    required this.onSignIn,
  });

  final VoidCallback onStartNew;
  final VoidCallback onJoin;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return AuthDesktopShell(
      brand: const AuthBrandPanel(
        facts: [
          'Works without internet',
          'Your sales and stock stay on this computer',
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AuthHeading(
            title: 'Welcome to Counterbase',
            subtitle:
                'Start a shop on this computer, or bring this computer into a shop you already run.',
          ),
          const SizedBox(height: 24),
          AuthPrimaryButton(
            label: 'Start a new shop',
            autofocus: true,
            onPressed: onStartNew,
          ),
          const SizedBox(height: 10),
          AuthSecondaryButton(
            label: 'Add this computer to my shop',
            onPressed: onJoin,
          ),
          const SizedBox(height: 6),
          Center(
            child: AuthTextLink(
              label: 'Sign in to my account',
              onPressed: onSignIn,
            ),
          ),
          const SizedBox(height: 14),
          const Center(child: AuthLegalLine()),
        ],
      ),
    );
  }
}
