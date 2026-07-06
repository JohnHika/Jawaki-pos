import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'app_theme_mode';
const _primaryColorKey = 'primary_color';
const _secondaryColorKey = 'secondary_color';

/// Default brand colors (same as DesignColors.brand + teal)
const _defaultPrimary = Color(0xFF1A73E8);
const _defaultSecondary = Color(0xFF009688);

/// Persisted theme mode provider.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.light) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeModeKey);
    state = _fromString(value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, _toString(mode));
  }

  static ThemeMode _fromString(String? v) => switch (v) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.light,
  };

  static String _toString(ThemeMode m) => switch (m) {
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
    _ => 'light',
  };
}

// ── Theme Colors ─────────────────────────────────────────────────────────────

/// Holds the user-selected primary + secondary brand colors.
class ThemeColors {
  final Color primary;
  final Color secondary;

  const ThemeColors({
    this.primary = _defaultPrimary,
    this.secondary = _defaultSecondary,
  });

  ThemeColors copyWith({Color? primary, Color? secondary}) => ThemeColors(
        primary: primary ?? this.primary,
        secondary: secondary ?? this.secondary,
      );
}

/// Persisted theme color provider.
final themeColorsProvider =
    StateNotifierProvider<ThemeColorNotifier, ThemeColors>((ref) {
  return ThemeColorNotifier();
});

class ThemeColorNotifier extends StateNotifier<ThemeColors> {
  ThemeColorNotifier() : super(const ThemeColors()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final primary = prefs.getInt(_primaryColorKey);
    final secondary = prefs.getInt(_secondaryColorKey);
    state = ThemeColors(
      primary: primary != null ? Color(primary) : _defaultPrimary,
      secondary: secondary != null ? Color(secondary) : _defaultSecondary,
    );
  }

  Future<void> setColors(Color primary, Color secondary) async {
    state = ThemeColors(primary: primary, secondary: secondary);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_primaryColorKey, primary.toARGB32());
    await prefs.setInt(_secondaryColorKey, secondary.toARGB32());
  }
}
