import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/theme/design_system.dart';
import '../../../subscription/domain/subscription_plans.dart';
import 'auth_desktop_kit.dart';

/// The activation payment step on a computer: a brand panel that lists what
/// the workspace includes, and a calm form column with the price, the monthly
/// plans that follow, the pay button and the way out. The page sits outside
/// the desktop shell, so it uses the auth split layout.
///
/// Takes plain data; the screen owns the checkout state.
class CompanyActivationDesktopView extends StatelessWidget {
  const CompanyActivationDesktopView({
    super.key,
    required this.priceLabel,
    required this.hasCheckout,
    required this.onPay,
    required this.onVerify,
    required this.onSwitchAccount,
    this.companyName,
    this.loading = false,
    this.startingCheckout = false,
    this.verifying = false,
    this.error,
    this.codeCard,
  });

  /// "KSh 125,000".
  final String priceLabel;
  final String? companyName;
  final bool loading;
  final bool startingCheckout;
  final bool verifying;

  /// A checkout link already exists, so the shop can re-open it or check it.
  final bool hasCheckout;
  final String? error;

  /// The optional "have a code?" box.
  final Widget? codeCard;
  final VoidCallback onPay;
  final VoidCallback onVerify;
  final VoidCallback onSwitchAccount;

  @override
  Widget build(BuildContext context) {
    final name = companyName?.trim() ?? '';
    return AuthDesktopShell(
      brand: const AuthBrandPanel(
        statement: 'One payment unlocks your workspace.',
        facts: [
          'Dashboard: business overview and daily decisions',
          'POS workspace: sales, customers, products and payments',
          'Owner controls: staff, permissions, branches and settings',
        ],
      ),
      actions: loading
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AuthPrimaryButton(
                  label: startingCheckout
                      ? 'Opening secure checkout…'
                      : hasCheckout
                          ? 'Open payment checkout again'
                          : 'Pay $priceLabel to activate',
                  icon: Icons.lock_rounded,
                  loading: startingCheckout,
                  autofocus: true,
                  onPressed: startingCheckout ? null : onPay,
                ),
                if (hasCheckout) ...[
                  const SizedBox(height: 8),
                  AuthSecondaryButton(
                    label: verifying
                        ? 'Checking payment…'
                        : 'I completed payment, check status',
                    icon: Icons.verified_rounded,
                    onPressed: verifying ? null : onVerify,
                  ),
                ],
                const SizedBox(height: 4),
                Center(
                  child: AuthTextLink(
                    label: 'Use a different account',
                    onPressed: onSwitchAccount,
                  ),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthHeading(
            title: 'Activate your workspace',
            subtitle: name.isEmpty
                ? 'Your company is created. One payment unlocks the Counterbase workspace.'
                : '$name is created. Complete activation before using Counterbase.',
          ),
          const SizedBox(height: 20),
          _PriceRow(priceLabel: priceLabel),
          const SizedBox(height: 20),
          const _MonthlyPlans(),
          if (codeCard != null) ...[const SizedBox(height: 14), codeCard!],
          if (error != null) ...[
            const SizedBox(height: 14),
            AuthNotice(message: error!),
          ],
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 16),
          Text(
            'Secure checkout runs through our payment partner. Counterbase unlocks the workspace only after the server has verified the payment.',
            style: TextStyle(
              color: context.desktop.textFaint,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.priceLabel});

  final String priceLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Workspace activation',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'One-time setup payment',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          Text(
            priceLabel,
            style: DesignType.numeric(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: p.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyPlans extends StatelessWidget {
  const _MonthlyPlans();

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monthly plan after activation',
          style: GoogleFonts.plusJakartaSans(
            color: p.text,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'The payment above is one-time. You choose a monthly plan next. It starts with a 7-day trial, and monthly billing begins when the trial ends.',
          style: TextStyle(color: p.textMuted, fontSize: 12.5, height: 1.45),
        ),
        const SizedBox(height: 8),
        for (final plan in kAvailablePlans)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${formatKes(plan.priceKes).replaceFirst('KES ', 'KSh ')} / month',
                  style: DesignType.numeric(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
