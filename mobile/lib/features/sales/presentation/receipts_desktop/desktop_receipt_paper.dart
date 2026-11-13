import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import 'receipt_thermal_text.dart';

/// The receipt as a strip of thermal paper: monospace, on the same column grid
/// the printer uses (32 columns for a 58mm roll, 48 for 80mm). The paper stays
/// light in the dark theme because that is what it looks like in the shop.
class DesktopReceiptPaper extends StatelessWidget {
  const DesktopReceiptPaper({
    super.key,
    required this.text,
    this.columns = thermalColumns58mm,
  });

  final String text;
  final int columns;

  /// Glyph size that keeps [columns] characters inside the roll width.
  static double fontSizeFor(int columns) => columns > 40 ? 10 : 12;

  static const Color paper = Color(0xFFFCFBF7);
  static const Color ink = Color(0xFF1F1D1A);

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final size = fontSizeFor(columns);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: p.dark ? const Color(0xFF3A352D) : p.border),
      ),
      // Scales down instead of overflowing if the panel is narrower than the roll.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: Text(
          text,
          softWrap: false,
          style: GoogleFonts.jetBrainsMono(
            fontSize: size,
            fontWeight: FontWeight.w700,
            height: 1.35,
            color: ink,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// Two small text toggles for the roll width: 58 mm | 80 mm.
class ReceiptPaperWidthToggle extends StatelessWidget {
  const ReceiptPaperWidthToggle({
    super.key,
    required this.columns,
    required this.onChanged,
  });

  final int columns;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    Widget option(String label, int value) {
      final selected = columns == value;
      return Material(
        color: selected ? p.selected : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? Colors.transparent : p.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => onChanged(value),
          hoverColor: p.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: selected ? p.text : p.textMuted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        option('58 mm', thermalColumns58mm),
        const SizedBox(width: 6),
        option('80 mm', thermalColumns80mm),
      ],
    );
  }
}
