import 'package:flutter/material.dart';

/// Counterbase desktop palette — mirrors the mobile design system
/// (mobile/lib/core/theme/design_system.dart): near-black canvas, signal
/// orange as the single interactive accent, indigo as brand identifier.
abstract final class CbInk {
  // Dark canvas — true near-black, flat, no gradient wash.
  static const bg = Color(0xFF0B0A0F);
  static const surface = Color(0xFF15131C);
  static const surfaceElevated = Color(0xFF1F1C29);
  static const border = Color(0xFF2E2A3D);

  // Text
  static const text = Color(0xFFF5F3ED);
  static const textSecondary = Color(0xFFA8A3B8);
  static const textTertiary = Color(0xFF6E6A80);

  // Accent — signal orange, the app's one interactive color.
  static const accent = Color(0xFFFF7A33);
  static const accentLight = Color(0xFFFFA166);
  static const accentDark = Color(0xFFE0611E);
  static const accentSubtle = Color(0xFF2A1B10);

  // Brand identifier (logo mark, splash) — carries no interactive weight.
  static const brand = Color(0xFFFF7A33);
  static const indigo = Color(0xFF7C6CFF);

  // Status
  static const success = Color(0xFF3DDC84);
  static const error = Color(0xFFFF5C5C);
  static const warning = Color(0xFFFFC24B);
  static const info = Color(0xFF4FC3F7);
  static const successSubtle = Color(0xFF102A1B);
  static const errorSubtle = Color(0xFF2E1414);
  static const warningSubtle = Color(0xFF2E2410);
  static const infoSubtle = Color(0xFF102530);

  // Payment method colors — conventional, read instantly.
  static const mpesa = Color(0xFF3DDC84);
  static const cash = Color(0xFFC98A4B);
  static const credit = Color(0xFF7C6CFF);

  // Legacy aliases kept for widget code written against the navy draft.
  static const ground = bg;
  static const paper = surfaceElevated;
  static const navy = surfaceElevated;
  static const navy3 = border;
  static const ink = text;
  static const ink2 = textSecondary;
  static const muted = textTertiary;
  static const action = accent;
  static const actionHover = accentLight;
  static const onAction = Color(0xFF14100B);
  static const ok = success;
  static const warn = warning;
  static const bad = error;
  static const hairline = border;
}

abstract final class CbText {
  /// Display: Sora, geometric and confident — mobile's heading face.
  static const display = TextStyle(
    fontFamily: 'CbDisplay',
    fontWeight: FontWeight.w700,
    height: 1.18,
    letterSpacing: -0.3,
    color: CbInk.text,
  );

  /// Instrument label: mono, tracked, uppercase — mirrors mobile's
  /// uppercase card labels (MetricCard, SectionHeader pattern).
  static const tag = TextStyle(
    fontFamily: 'CbMono',
    fontSize: 11,
    height: 1.4,
    letterSpacing: 0.8,
    fontWeight: FontWeight.w600,
    color: CbInk.textTertiary,
  );

  /// Every monetary or counted figure uses mono with tabular figures.
  static const data = TextStyle(
    fontFamily: 'CbMono',
    fontSize: 13,
    height: 1.4,
    letterSpacing: -0.2,
    color: CbInk.text,
  );
}

/// Small instrument label: a tracking dot (like mobile StatusBadge's live
/// dot) or an accent dash, then tracked mono text.
class CbTag extends StatelessWidget {
  const CbTag(this.label, {super.key, this.color, this.dot = false});

  final String label;
  final Color? color;
  final bool dot;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (dot) ...[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color ?? CbInk.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (color ?? CbInk.accent).withValues(alpha: 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
      ] else ...[
        Container(width: 10, height: 2, color: color ?? CbInk.accent),
        const SizedBox(width: 8),
      ],
      Text(label.toUpperCase(), style: CbText.tag),
    ],
  );
}

/// The Counterbase mark, mirroring mobile's auth logo: a circle lifted on
/// the elevated surface with an accent ring (pin_login_screen pattern).
class CbLogoMark extends StatelessWidget {
  const CbLogoMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: CbInk.surfaceElevated,
      border: Border.all(
        color: CbInk.accent.withValues(alpha: 0.5),
        width: 2,
      ),
    ),
    child: Icon(Icons.bolt_rounded, color: CbInk.accent, size: size * 0.55),
  );
}

/// Identity chip from mobile's PIN screen: a quiet pill with icon + label.
class CbIdentityChip extends StatelessWidget {
  const CbIdentityChip(this.icon, this.label, {super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: CbInk.text.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: CbInk.text.withValues(alpha: 0.16)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: CbInk.text.withValues(alpha: 0.72), size: 15),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: CbInk.text.withValues(alpha: 0.82),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Product category colors, aligned to mobile conventions (warm, meaning-
/// carrying hues on the near-black canvas).
Color productCategoryColor(String category) {
  const colors = [
    Color(0xFFC98A4B), // cash brown
    Color(0xFF4FC3F7), // info blue
    Color(0xFFFFC24B), // warning amber
    Color(0xFF3DDC84), // success green
    Color(0xFF7C6CFF), // credit indigo
    Color(0xFFFF7A33), // accent orange
  ];
  return colors[category.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
      colors.length];
}

ThemeData buildCounterbaseTheme() {
  const scheme = ColorScheme.dark(
    primary: CbInk.accent,
    onPrimary: Colors.white,
    secondary: CbInk.brand,
    onSecondary: Colors.white,
    tertiary: CbInk.info,
    error: CbInk.error,
    onError: Colors.white,
    surface: CbInk.surface,
    onSurface: CbInk.text,
    surfaceContainerHighest: CbInk.surfaceElevated,
    outline: CbInk.border,
    outlineVariant: CbInk.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'CbSans',
    scaffoldBackgroundColor: CbInk.bg,
    splashFactory: InkRipple.splashFactory,
  );

  final display = CbText.display;
  final mono = CbText.data;

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displayLarge: display.copyWith(fontSize: 32, fontWeight: FontWeight.w800),
      displayMedium: display.copyWith(fontSize: 28, fontWeight: FontWeight.w700),
      displaySmall: display.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
      headlineMedium: display.copyWith(fontSize: 21, fontWeight: FontWeight.w700),
      headlineSmall: display.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
      titleLarge: display.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      titleMedium: const TextStyle(
        fontFamily: 'CbSans',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: CbInk.text,
        height: 1.35,
      ),
      titleSmall: const TextStyle(
        fontFamily: 'CbSans',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: CbInk.text,
        height: 1.35,
      ),
      bodyLarge: const TextStyle(
        fontFamily: 'CbSans',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: CbInk.textSecondary,
        height: 1.55,
      ),
      bodyMedium: const TextStyle(
        fontFamily: 'CbSans',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: CbInk.textSecondary,
        height: 1.55,
      ),
      bodySmall: const TextStyle(
        fontFamily: 'CbSans',
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: CbInk.textTertiary,
        height: 1.5,
      ),
      labelLarge: const TextStyle(
        fontFamily: 'CbSans',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: CbInk.text,
        letterSpacing: 0.1,
      ),
      labelMedium: mono.copyWith(fontSize: 12.5, color: CbInk.text),
      labelSmall: mono.copyWith(fontSize: 11, color: CbInk.textTertiary),
    ),
    cardTheme: CardThemeData(
      color: CbInk.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: CbInk.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: CbInk.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: CbInk.border),
      ),
      titleTextStyle: display.copyWith(fontSize: 19),
      contentTextStyle: const TextStyle(
        fontFamily: 'CbSans',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: CbInk.textSecondary,
        height: 1.55,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CbInk.surfaceElevated,
      hintStyle: const TextStyle(color: CbInk.textTertiary),
      labelStyle: const TextStyle(color: CbInk.textTertiary),
      floatingLabelStyle: const TextStyle(color: CbInk.accent),
      prefixIconColor: CbInk.textTertiary,
      suffixIconColor: CbInk.textTertiary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CbInk.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CbInk.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CbInk.accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CbInk.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CbInk.error, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CbInk.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: CbInk.surfaceElevated,
        disabledForegroundColor: CbInk.textTertiary,
        overlayColor: Colors.black.withValues(alpha: 0.18),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'CbSans',
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CbInk.accent,
        disabledForegroundColor: CbInk.textTertiary,
        overlayColor: CbInk.accent.withValues(alpha: 0.1),
        side: const BorderSide(color: CbInk.border),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'CbSans',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: CbInk.accent,
        disabledForegroundColor: CbInk.textTertiary,
        overlayColor: CbInk.accent.withValues(alpha: 0.1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: 'CbSans',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: CbInk.textSecondary,
        disabledForegroundColor: CbInk.textTertiary,
        highlightColor: CbInk.accent.withValues(alpha: 0.1),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.transparent,
      selectedColor: CbInk.accent,
      labelStyle: const TextStyle(
        fontFamily: 'CbSans',
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(fontFamily: 'CbSans', fontSize: 13),
      side: const BorderSide(color: CbInk.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: mono.copyWith(
        fontSize: 11,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        color: CbInk.textTertiary,
      ),
      headingRowColor: const WidgetStatePropertyAll(CbInk.surfaceElevated),
      dataTextStyle: const TextStyle(
        fontFamily: 'CbSans',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: CbInk.textSecondary,
      ),
      dividerThickness: 1,
    ),
    dividerTheme: const DividerThemeData(
      color: CbInk.border,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: CbInk.accent,
      linearTrackColor: CbInk.surfaceElevated,
      circularTrackColor: CbInk.surfaceElevated,
      borderRadius: BorderRadius.all(Radius.circular(2)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: CbInk.surfaceElevated,
      contentTextStyle: const TextStyle(
        fontFamily: 'CbSans',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: CbInk.text,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: CbInk.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: CbInk.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CbInk.border),
      ),
      textStyle: mono.copyWith(fontSize: 11, color: CbInk.textSecondary),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: CbInk.accent.withValues(alpha: 0.35),
      selectionHandleColor: CbInk.accent,
      cursorColor: CbInk.accent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: const WidgetStatePropertyAll(CbInk.border),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(8),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(CbInk.surfaceElevated),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: const WidgetStatePropertyAll(BorderSide(color: CbInk.border)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return CbInk.accent;
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return CbInk.textSecondary;
        }),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'CbSans',
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
            ? CbInk.accent
            : CbInk.surfaceElevated,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: CbInk.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: CbInk.border),
      ),
    ),
  );
}
