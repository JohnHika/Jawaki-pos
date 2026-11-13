import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/theme/design_system.dart';

/// One figure in a [DesktopFiguresRow].
class DesktopFigure {
  const DesktopFigure({
    required this.label,
    required this.value,
    this.hint,
    this.valueColor,
  });

  final String label;

  /// Already formatted ("KES 12,400" or "-KES 800").
  final String value;
  final String? hint;

  /// Red for a negative figure. null is the ink colour.
  final Color? valueColor;
}

/// Key figures in one bordered strip, tabular numerals, separated by
/// hairlines. Every cell has a hint line (blank when there is none), so the
/// cells share one height without measuring them.
class DesktopFiguresRow extends StatelessWidget {
  const DesktopFiguresRow({
    super.key,
    required this.figures,
    this.dense = false,
  });

  final List<DesktopFigure> figures;

  /// Drops the hint line, for a short window.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < figures.length; i++)
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(left: BorderSide(color: p.border)),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(18, dense ? 9 : 12, 12, dense ? 9 : 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        figures[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          figures[i].value,
                          maxLines: 1,
                          style: DesignType.numeric(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: figures[i].valueColor ?? p.text,
                          ),
                        ),
                      ),
                      if (!dense) ...[
                        const SizedBox(height: 2),
                        Text(
                          figures[i].hint ?? ' ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textFaint,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Red for a negative amount, readable on the light page and the dark one.
Color negativeAmountColor(DesktopPalette p) =>
    p.dark ? DesignColors.error : const Color(0xFFB3261E);
