import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';

/// Quiet buttons for the desktop pages. The orange fill is kept for the one
/// primary action on a page, so every other button is neutral: ink text and a
/// hairline outline. Text is set explicitly in the bundled font so the label
/// never falls back to a system face.
ButtonStyle desktopSecondaryButton(BuildContext context) {
  final p = DesktopPalette.of(context);
  return OutlinedButton.styleFrom(
    foregroundColor: p.text,
    side: BorderSide(color: p.borderStrong),
    textStyle: GoogleFonts.plusJakartaSans(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
    ),
    minimumSize: const Size(0, DesktopTokens.controlHeight),
    padding: const EdgeInsets.symmetric(horizontal: 14),
  );
}

/// A link-style button: deep orange text on light, orange on dark.
ButtonStyle desktopLinkButton(BuildContext context) {
  final p = DesktopPalette.of(context);
  return TextButton.styleFrom(
    foregroundColor: p.accent,
    textStyle: GoogleFonts.plusJakartaSans(
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
    minimumSize: const Size(0, 30),
    padding: const EdgeInsets.symmetric(horizontal: 10),
  );
}

/// The filled primary button with its label in the bundled font.
ButtonStyle desktopPrimaryButton(BuildContext context) {
  return FilledButton.styleFrom(
    textStyle: GoogleFonts.plusJakartaSans(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
    ),
    minimumSize: const Size(0, DesktopTokens.controlHeight),
    padding: const EdgeInsets.symmetric(horizontal: 16),
  );
}
