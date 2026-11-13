import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_system.dart';
import 'desktop_layout.dart';

/// Re-tunes the phone theme for a mouse, a keyboard and a big window.
///
/// Applied by the desktop shell around every routed page, so the pages
/// themselves stay one codebase: tighter controls, flat hairline cards, no
/// ripples, page headers that read like title bars, toasts that do not span
/// the whole window.
class DesktopTheme {
  const DesktopTheme._();

  /// [pageSurface] false keeps the base page colours, app bar and cards (used
  /// app-wide so dialogs and menus get desktop controls without re-colouring
  /// full-screen pages such as sign-in); the shell passes true for its pages.
  static ThemeData of(ThemeData base, {bool pageSurface = true}) {
    final p = base.brightness == Brightness.dark
        ? DesktopPalette.darkPalette
        : DesktopPalette.light;

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
    );
    ButtonStyle compact(ButtonStyle? style) => (style ?? const ButtonStyle())
        .copyWith(
      minimumSize: const WidgetStatePropertyAll(
        Size(64, DesktopTokens.controlHeight),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      shape: WidgetStatePropertyAll(controlShape),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return base.copyWith(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashFactory: NoSplash.splashFactory,
      hoverColor: p.hover,
      highlightColor: p.hover,
      focusColor: p.selected,
      scaffoldBackgroundColor:
          pageSurface ? p.panel : base.scaffoldBackgroundColor,
      canvasColor: p.panel,
      dividerColor: p.border,
      dividerTheme: DividerThemeData(color: p.border, space: 1, thickness: 1),
      appBarTheme: !pageSurface
          ? base.appBarTheme
          : base.appBarTheme.copyWith(
        backgroundColor: p.panel,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        centerTitle: false,
        titleSpacing: DesktopTokens.gutter - 8,
        titleTextStyle: GoogleFonts.sora(
          color: p.text,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        shape: Border(bottom: BorderSide(color: p.border)),
      ),
      cardTheme: !pageSurface
          ? base.cardTheme
          : base.cardTheme.copyWith(
        color: p.dark ? p.panelAlt : Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: compact(base.elevatedButtonTheme.style),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: compact(base.filledButtonTheme.style),
      ),
      // Outlined buttons are the quiet kind: neutral ink and a hairline, so the
      // one orange button on a page stays the primary action.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: compact(base.outlinedButtonTheme.style).copyWith(
          foregroundColor: WidgetStatePropertyAll(p.text),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                  ? p.textMuted
                  : p.borderStrong,
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: compact(base.textButtonTheme.style),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        dense: true,
        minVerticalPadding: 4,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(8),
        interactive: true,
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => (p.dark ? Colors.white : const Color(0xFF3A2A14))
              .withValues(
            alpha: states.contains(WidgetState.hovered) ? 0.38 : 0.2,
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        showDuration: const Duration(seconds: 4),
        preferBelow: true,
        textStyle: GoogleFonts.plusJakartaSans(
          color: p.dark ? DesignColors.darkSurface : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        decoration: BoxDecoration(
          color: p.dark ? p.text : const Color(0xFF211B12),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        width: 440,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        constraints: const BoxConstraints(maxWidth: 560),
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesktopTokens.panelRadius),
          side: BorderSide(color: p.borderStrong),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowHeight: 40,
        dataRowMinHeight: DesktopTokens.rowHeight,
        dataRowMaxHeight: DesktopTokens.rowHeight + 12,
        horizontalMargin: 16,
        columnSpacing: 24,
        dividerThickness: 1,
        headingTextStyle: GoogleFonts.plusJakartaSans(
          color: p.textMuted,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: GoogleFonts.plusJakartaSans(
          color: p.text,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        dataRowColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ? p.hover : Colors.transparent,
        ),
      ),
    );
  }
}
