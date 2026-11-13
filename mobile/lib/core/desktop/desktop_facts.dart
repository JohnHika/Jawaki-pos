import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_system.dart';
import 'desktop_layout.dart';

/// One label and value line in a [DesktopFactList].
class DesktopFact {
  const DesktopFact(this.label, this.value, {this.color, this.numeric = false});

  final String label;
  final String value;

  /// Overrides the ink colour of the value (red for overdue).
  final Color? color;

  /// Money and counts use tabular figures.
  final bool numeric;
}

/// Label on the left, value on the right, hairlines between: the facts of one
/// record in an inspector (invoice total, paid, due date).
class DesktopFactList extends StatelessWidget {
  const DesktopFactList({super.key, required this.facts});

  final List<DesktopFact> facts;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Column(
      children: [
        for (var i = 0; i < facts.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: Border(
                top: i == 0 ? BorderSide(color: p.border) : BorderSide.none,
                bottom: BorderSide(color: p.border),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  facts[i].label,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    facts[i].value,
                    textAlign: TextAlign.right,
                    style: (facts[i].numeric
                            ? DesignType.numeric(fontSize: 13, letterSpacing: 0)
                            : GoogleFonts.plusJakartaSans(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ))
                        .copyWith(color: facts[i].color ?? p.text),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A small heading above a group inside a panel or inspector ("Payments").
class DesktopSectionLabel extends StatelessWidget {
  const DesktopSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A "Label  ·  value" line list with a trailing amount, used for payment
/// history and recent activity inside inspectors and panels.
class DesktopActivityLine extends StatelessWidget {
  const DesktopActivityLine({
    super.key,
    required this.title,
    required this.amount,
    this.subtitle,
    this.icon,
    this.amountColor,
  });

  final String title;
  final String? subtitle;
  final String amount;
  final IconData? icon;
  final Color? amountColor;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: p.textMuted),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount,
            style: DesignType.numeric(fontSize: 13, letterSpacing: 0)
                .copyWith(color: amountColor ?? p.text),
          ),
        ],
      ),
    );
  }
}
