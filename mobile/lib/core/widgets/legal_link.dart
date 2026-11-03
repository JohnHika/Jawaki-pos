import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/design_system.dart';

/// Blue used for tappable legal links. Brighter on dark surfaces for
/// contrast, standard Material link blue on light surfaces.
Color legalLinkColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? DesignColors.info
        : const Color(0xFF1976D2);

/// Text style for inline legal links (blue + underline).
TextStyle legalLinkTextStyle(BuildContext context) => TextStyle(
      color: legalLinkColor(context),
      decoration: TextDecoration.underline,
      decorationColor: legalLinkColor(context),
      fontWeight: FontWeight.w600,
    );

/// A single tappable legal link (blue, underlined) that navigates to a
/// [route] under /legal. Styled via [style] when placed inside rich text.
class LegalLinkText extends StatelessWidget {
  const LegalLinkText({
    super.key,
    required this.text,
    required this.route,
    this.alignLeft = true,
  });

  final String text;
  final String route;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: TextButton(
        onPressed: () => context.push(route),
        style: TextButton.styleFrom(
          foregroundColor: legalLinkColor(context),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: legalLinkColor(context),
            decoration: TextDecoration.underline,
            decorationColor: legalLinkColor(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Consent checkbox label with an embedded tappable link (blue,
/// underlined) for the word "terms". Lets the user open the exact policy
/// they are agreeing to without leaving the flow.
class TermsConsentText extends StatelessWidget {
  const TermsConsentText({
    super.key,
    required this.before,
    required this.linkText,
    required this.after,
    required this.route,
  });

  final String before;
  final String linkText;
  final String after;
  final String route;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        text: before,
        style: base,
        children: [
          TextSpan(
            text: linkText,
            style: legalLinkTextStyle(context),
            recognizer: TapGestureRecognizer()
              ..onTap = () => context.push(route),
          ),
          TextSpan(text: after, style: base),
        ],
      ),
    );
  }
}
