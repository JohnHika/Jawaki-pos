import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_theme.dart';
import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/desktop/auth_desktop_kit.dart';
import '../../domain/subscription_plans.dart';

/// Choose-your-plan on a computer, shown right after activation (outside the
/// shell, so it applies the desktop theme itself). The comparison table fills
/// the left; the choice, the terms and the Continue button sit in a column on
/// the right so nothing needs a long scroll.
///
/// Takes plain data: the owner of the state is the screen.
class DesktopPlanSelectionView extends StatelessWidget {
  const DesktopPlanSelectionView({
    super.key,
    required this.selectedPlanId,
    required this.onSelectPlan,
    required this.acceptedTerms,
    required this.onAcceptTerms,
    required this.termsLabel,
    required this.setupFeeLabel,
    required this.onContinue,
    this.termsLink,
    this.companyName,
    this.submitting = false,
    this.error,
  });

  final String? selectedPlanId;
  final ValueChanged<String> onSelectPlan;
  final bool acceptedTerms;
  final ValueChanged<bool> onAcceptTerms;

  /// "I agree to the subscription, billing and refund terms ..." with its link.
  final Widget termsLabel;

  /// A "Read the terms" link under the checkbox.
  final Widget? termsLink;

  /// "KSh 125,000".
  final String setupFeeLabel;
  final String? companyName;
  final bool submitting;
  final String? error;

  /// null while the button should be disabled.
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: DesktopTheme.of(Theme.of(context)),
      child: Builder(builder: (context) {
        final p = context.desktop;
        return CallbackShortcuts(
          bindings: {
            if (onContinue != null)
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  onContinue!,
          },
          child: FocusScope(
            autofocus: true,
            child: Scaffold(
              backgroundColor: p.panel,
              body: LayoutBuilder(builder: (context, outer) {
                final short = outer.maxHeight < 620;
                final name = companyName?.trim() ?? '';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(32, short ? 14 : 22, 32, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'COUNTERBASE  ·  FINAL STEP',
                            style: GoogleFonts.plusJakartaSans(
                              color: p.textFaint,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Semantics(
                            header: true,
                            child: Text(
                              'Choose your plan',
                              style: GoogleFonts.sora(
                                color: p.text,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          if (!short) ...[
                            const SizedBox(height: 4),
                            Text(
                              name.isEmpty
                                  ? 'Your 7-day trial is active. Choose the plan that should continue after the trial ends.'
                                  : '$name is activated. Choose the plan that should continue after your 7-day trial.',
                              style: GoogleFonts.plusJakartaSans(
                                color: p.textMuted,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                            32, short ? 10 : 16, 32, short ? 14 : 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _comparison(context)),
                            const SizedBox(width: 20),
                            SizedBox(width: 380, child: _choice(context, short)),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        );
      }),
    );
  }

  Widget _comparison(BuildContext context) {
    final p = context.desktop;
    Widget mark(bool included) => included
        ? const Icon(Icons.check_rounded, size: 19, color: DesignColors.success)
        : Icon(Icons.remove_rounded, size: 16, color: p.textFaint);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                Text(
                  'Compare plans',
                  style: GoogleFonts.sora(
                    color: p.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'What each plan includes',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.border),
          Expanded(
            child: DesktopDataTable<PlanFeature>(
              rows: kPlanFeatures,
              rowId: (row) => row.text,
              rowHeight: 48,
              minWidth: 0,
              columns: [
                DesktopColumn<PlanFeature>(
                  label: 'Feature',
                  flex: 1,
                  minWidth: 200,
                  cell: (context, row) => Text(
                    row.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.text,
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                DesktopColumn<PlanFeature>(
                  label: 'CORE',
                  width: 96,
                  numeric: true,
                  cell: (context, row) => mark(row.includedInCore),
                ),
                DesktopColumn<PlanFeature>(
                  label: 'BUSINESS',
                  width: 104,
                  numeric: true,
                  cell: (context, row) => mark(row.includedInBusiness),
                ),
                DesktopColumn<PlanFeature>(
                  label: 'ENTERPRISE',
                  width: 116,
                  numeric: true,
                  cell: (context, row) => mark(row.includedInEnterprise),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _choice(BuildContext context, bool short) {
    final p = context.desktop;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'Your plan after the trial',
                      style: GoogleFonts.sora(
                        color: p.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  for (final plan in kAvailablePlans)
                    _PlanOption(
                      plan: plan,
                      selected: plan.id == selectedPlanId,
                      onTap: () => onSelectPlan(plan.id),
                      autofocus: plan.id == selectedPlanId,
                      compact: short,
                    ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            size: 17, color: p.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your $setupFeeLabel one-time setup is paid. Nothing more is due until your free trial ends.',
                            style: GoogleFonts.plusJakartaSans(
                              color: p.textMuted,
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: p.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: submitting ? null : () => onAcceptTerms(!acceptedTerms),
                  borderRadius: BorderRadius.circular(6),
                  canRequestFocus: false,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: acceptedTerms,
                        onChanged: submitting
                            ? null
                            : (v) => onAcceptTerms(v ?? false),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        activeColor: DesignColors.accent,
                        checkColor: const Color(0xFF1A1610),
                        side: BorderSide(color: p.borderStrong, width: 1.5),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: DefaultTextStyle(
                            style: GoogleFonts.plusJakartaSans(
                              color: p.textMuted,
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                            child: termsLabel,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (termsLink != null) termsLink!,
                if (error != null) ...[
                  const SizedBox(height: 8),
                  AuthNotice(message: error!),
                ],
                const SizedBox(height: 10),
                AuthPrimaryButton(
                  label: submitting ? 'Saving your plan…' : 'Continue with this plan',
                  icon: Icons.arrow_forward_rounded,
                  loading: submitting,
                  onPressed: onContinue,
                ),
                if (!short) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Your first 7 days are free. Monthly billing begins when the trial ends.   Ctrl+Enter',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textFaint,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.plan,
    required this.selected,
    required this.onTap,
    required this.autofocus,
    required this.compact,
  });

  final SubscriptionPlan plan;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  /// A short window: one line per plan, no tagline.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        button: true,
        child: InkWell(
          onTap: onTap,
          autofocus: autofocus,
          borderRadius: BorderRadius.circular(10),
          hoverColor: p.hover,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: selected ? p.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? DesignColors.accent : p.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 10),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: selected ? p.accent : p.textFaint,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              plan.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                color: p.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${formatKes(plan.priceKes)}/mo',
                            style: DesignType.numeric(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: p.text,
                            ),
                          ),
                        ],
                      ),
                      if (!compact || plan.isPopular) ...[
                        const SizedBox(height: 3),
                        Text.rich(
                          TextSpan(
                            children: [
                              if (plan.isPopular)
                                TextSpan(
                                  text: compact ? 'Most popular' : 'Most popular. ',
                                  style: TextStyle(
                                    color: p.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              if (!compact) TextSpan(text: plan.tagline),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
