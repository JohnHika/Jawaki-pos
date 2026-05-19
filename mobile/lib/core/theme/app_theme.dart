import 'package:flutter/material.dart';
import 'design_system.dart';

/// Levisa Adventures POS — Premium Material Theme
class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: DesignColors.brand,
        onPrimary: DesignColors.textInverse,
        primaryContainer: DesignColors.brandSubtle,
        secondary: DesignColors.teal,
        onSecondary: DesignColors.textInverse,
        secondaryContainer: DesignColors.tealSubtle,
        tertiary: DesignColors.accent,
        surface: DesignColors.surface,
        onSurface: DesignColors.textPrimary,
        error: DesignColors.error,
        onError: DesignColors.textInverse,
        outline: DesignColors.surfaceBorder,
      ),
      scaffoldBackgroundColor: DesignColors.surfaceMuted,
      appBarTheme: AppBarTheme(
        backgroundColor: DesignColors.surfaceMuted,
        foregroundColor: DesignColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleSpacing: 0,
        titleTextStyle: const TextStyle(
          color: DesignColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        toolbarHeight: 60,
        shape: Border(
          bottom: BorderSide(color: DesignColors.surfaceBorder, width: 0.75),
        ),
      ),
      cardTheme: CardThemeData(
        color: DesignColors.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          side: BorderSide(color: DesignColors.surfaceBorder, width: 0.75),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DesignColors.brand,
          foregroundColor: DesignColors.textInverse,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DesignColors.brand,
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          ),
          side: BorderSide(
              color: DesignColors.brand.withValues(alpha: 0.65), width: 1.25),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DesignColors.brand,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DesignColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide: const BorderSide(color: DesignColors.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide: const BorderSide(color: DesignColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide: const BorderSide(color: DesignColors.brand, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide: const BorderSide(color: DesignColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide: const BorderSide(color: DesignColors.error, width: 2),
        ),
        prefixIconColor: DesignColors.textSecondary,
        suffixIconColor: DesignColors.textSecondary,
        labelStyle: const TextStyle(
          color: DesignColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: const TextStyle(
          color: DesignColors.textTertiary,
          fontSize: 14,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: DesignColors.brand,
        foregroundColor: DesignColors.textInverse,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: DesignColors.surface,
        selectedItemColor: DesignColors.brand,
        unselectedItemColor: DesignColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: DesignColors.surfaceSubtle,
        deleteIconColor: DesignColors.textSecondary,
        labelStyle: const TextStyle(
          color: DesignColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: DesignColors.surfaceBorder,
        thickness: 0.5,
        space: 1,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 57,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.25,
          height: 1.12,
        ),
        displayMedium: TextStyle(
          fontSize: 45,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.16,
        ),
        displaySmall: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.22,
        ),
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.25,
          color: DesignColors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          height: 1.3,
          color: DesignColors.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          height: 1.35,
          color: DesignColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          height: 1.3,
          color: DesignColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.4,
          color: DesignColors.textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.4,
          color: DesignColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.5,
          color: DesignColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.5,
          color: DesignColors.textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          height: 1.4,
          color: DesignColors.textTertiary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          height: 1.4,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          height: 1.3,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          height: 1.4,
        ),
      ),
      iconTheme: const IconThemeData(
        color: DesignColors.textPrimary,
        size: 24,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: DesignColors.textPrimary,
        ),
        subtitleTextStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: DesignColors.textSecondary,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: DesignColors.brandLight,
        onPrimary: DesignColors.textPrimary,
        secondary: DesignColors.tealLight,
        surface: DesignColors.darkSurface,
        onSurface: DesignColors.darkTextPrimary,
        error: DesignColors.error,
      ),
      scaffoldBackgroundColor: DesignColors.darkBg,
      appBarTheme: AppBarTheme(
        backgroundColor: DesignColors.darkSurface,
        foregroundColor: DesignColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: DesignColors.darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        shape: Border(
          bottom: BorderSide(color: DesignColors.darkBorder, width: 0.75),
        ),
      ),
      cardTheme: CardThemeData(
        color: DesignColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          side: BorderSide(color: DesignColors.darkBorder, width: 0.75),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: DesignColors.darkTextPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: DesignColors.darkTextPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: DesignColors.darkTextSecondary,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: DesignColors.darkSurface,
        selectedItemColor: DesignColors.brandLight,
        unselectedItemColor: DesignColors.darkTextTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: DesignColors.darkSurfaceElevated,
        labelStyle: const TextStyle(
          color: DesignColors.darkTextPrimary,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DesignColors.darkSurfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide: const BorderSide(color: DesignColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide: const BorderSide(color: DesignColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide:
              const BorderSide(color: DesignColors.brandLight, width: 2),
        ),
        prefixIconColor: DesignColors.darkTextTertiary,
        labelStyle: const TextStyle(color: DesignColors.darkTextSecondary),
        hintStyle: const TextStyle(color: DesignColors.darkTextTertiary),
      ),
    );
  }
}
