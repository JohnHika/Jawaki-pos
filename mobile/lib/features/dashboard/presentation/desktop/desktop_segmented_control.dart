import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';

/// One choice in a [SegmentedRangeControl].
class SegmentedOption<T> {
  const SegmentedOption(this.value, this.label, {this.tooltip});

  final T value;
  final String label;
  final String? tooltip;
}

/// A compact "Today / 7 days / 30 days" switch for page headers and toolbars.
///
/// The selected choice gets the accent tint and keeps its weight, so the
/// control never changes width when you click it. Every segment is reachable
/// with Tab and answers Enter / Space.
class SegmentedRangeControl<T> extends StatelessWidget {
  const SegmentedRangeControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<SegmentedOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        height: DesktopTokens.controlHeight,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: p.dark ? p.panelAlt : Colors.white,
          borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
          border: Border.all(color: p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              _Segment<T>(
                option: option,
                selected: option.value == selected,
                palette: p,
                onTap: () => onChanged(option.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final SegmentedOption<T> option;
  final bool selected;
  final DesktopPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget segment = Semantics(
      button: true,
      selected: selected,
      label: option.label,
      excludeSemantics: true,
      child: Material(
        color: selected ? p.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopTokens.controlRadius - 3),
        child: InkWell(
          onTap: onTap,
          hoverColor: p.hover,
          borderRadius: BorderRadius.circular(DesktopTokens.controlRadius - 3),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                option.label,
                maxLines: 1,
                style: GoogleFonts.plusJakartaSans(
                  color: selected ? p.text : p.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (option.tooltip != null) {
      segment = Tooltip(message: option.tooltip!, child: segment);
    }
    return segment;
  }
}
