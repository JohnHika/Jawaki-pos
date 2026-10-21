import 'package:flutter/material.dart';

/// Semantic tone used by pills, banners and stat tiles.
enum Tone { brand, success, warning, danger, info, neutral }

/// Design tokens for ACA. Same orange-on-ink family as Counterbase, tuned for
/// an operations console: dense, calm surfaces and unmistakable status colour.
@immutable
class AcaPalette extends ThemeExtension<AcaPalette> {
  const AcaPalette({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.brand,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.isDark,
  });

  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color brand;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final bool isDark;

  static const dark = AcaPalette(
    bg: Color(0xFF0B0A0F),
    surface: Color(0xFF14121A),
    surfaceHigh: Color(0xFF1C1A25),
    border: Color(0xFF2A2733),
    text: Color(0xFFF4F1EA),
    textMuted: Color(0xFFA9A396),
    textFaint: Color(0xFF6F6A5F),
    brand: Color(0xFFFF7A33),
    success: Color(0xFF3DDC84),
    warning: Color(0xFFFFC24B),
    danger: Color(0xFFFF5C5C),
    info: Color(0xFF4FC3F7),
    isDark: true,
  );

  static const light = AcaPalette(
    bg: Color(0xFFF7F3EC),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF1EBDF),
    border: Color(0xFFE4DBCB),
    text: Color(0xFF1A1610),
    textMuted: Color(0xFF6B6455),
    textFaint: Color(0xFF9A927F),
    brand: Color(0xFFE0611E),
    success: Color(0xFF1E9E5A),
    warning: Color(0xFFB57A00),
    danger: Color(0xFFD13B3B),
    info: Color(0xFF1B7FB0),
    isDark: false,
  );

  Color toneColor(Tone tone) {
    switch (tone) {
      case Tone.brand:
        return brand;
      case Tone.success:
        return success;
      case Tone.warning:
        return warning;
      case Tone.danger:
        return danger;
      case Tone.info:
        return info;
      case Tone.neutral:
        return textMuted;
    }
  }

  /// Soft tinted background for a tone (pill / banner fill).
  Color toneFill(Tone tone) => toneColor(tone).withValues(alpha: isDark ? 0.16 : 0.12);

  @override
  AcaPalette copyWith() => this;

  @override
  AcaPalette lerp(ThemeExtension<AcaPalette>? other, double t) => this;
}

extension AcaThemeContext on BuildContext {
  AcaPalette get aca => Theme.of(this).extension<AcaPalette>()!;
}

class AcaTheme {
  AcaTheme._();

  static ThemeData get darkTheme => _build(AcaPalette.dark, Brightness.dark);
  static ThemeData get lightTheme => _build(AcaPalette.light, Brightness.light);

  static ThemeData _build(AcaPalette p, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: p.brand,
      onPrimary: b == Brightness.dark ? const Color(0xFF1A0E05) : Colors.white,
      secondary: p.info,
      onSecondary: Colors.white,
      error: p.danger,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.text,
      surfaceContainerHighest: p.surfaceHigh,
      outline: p.border,
      outlineVariant: p.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      extensions: [p],
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    final text = base.textTheme.apply(bodyColor: p.text, displayColor: p.text).copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          bodySmall: base.textTheme.bodySmall?.copyWith(color: p.textMuted),
        );

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border(p.border),
        enabledBorder: border(p.border),
        focusedBorder: border(p.brand, 1.6),
        errorBorder: border(p.danger),
        focusedErrorBorder: border(p.danger, 1.6),
        labelStyle: TextStyle(color: p.textMuted),
        hintStyle: TextStyle(color: p.textFaint),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.brand,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.brand,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.brand.withValues(alpha: 0.18),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? p.text : p.textMuted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? p.brand : p.textMuted,
            )),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.brand.withValues(alpha: 0.18),
        side: BorderSide(color: p.border),
        labelStyle: TextStyle(color: p.text, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceHigh,
        contentTextStyle: TextStyle(color: p.text, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : p.textMuted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.brand : p.surfaceHigh),
      ),
      listTileTheme: ListTileThemeData(iconColor: p.textMuted, textColor: p.text),
    );
  }
}
