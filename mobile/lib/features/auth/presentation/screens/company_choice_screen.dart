import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/auth/presentation/widgets/sign_in_kit.dart';

/// First-launch screen. Three doors: start a new shop, add this phone to a
/// shop that already exists, or sign in to a business account.
class CompanyChoiceScreen extends StatelessWidget {
  const CompanyChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Scaffold(
      backgroundColor: palette.page,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 32),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: AxonLogoTitle(logoSize: 64, showText: true),
                      ),
                      const SizedBox(height: 48),
                      Text(
                        'Run your counter, stock and daily sales.',
                        style: DesignType.display.copyWith(
                          color: palette.ink,
                          fontSize: 30,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Works without internet. Your records stay on your phone.',
                        style: TextStyle(
                          color: palette.soft,
                          fontSize: 16,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 40),
                      SignInButton(
                        label: 'Start a new shop',
                        onPressed: () => context.go('/company-setup'),
                      ),
                      const SizedBox(height: 12),
                      SignInOutlineButton(
                        label: 'Add this phone to my shop',
                        onPressed: () => context.go('/company-setup?join=1'),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: SignInTextLink(
                          label: 'Sign in to my account',
                          onPressed: () => context.go('/login'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      LegalConsent(palette: palette),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
