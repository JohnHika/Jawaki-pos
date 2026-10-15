import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'app_theme_mode';
// Bumped when the default changes; a device that hasn't seen this marker yet
// is moved to the new default once, after which its own choice is respected.
const _themeDefaultMarker = 'app_theme_default_light_v1';

/// Persisted theme mode provider. Axon POS opens in light mode by default;
/// dark stays available from Settings.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.light) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_themeDefaultMarker) != true) {
      await prefs.setBool(_themeDefaultMarker, true);
      await prefs.setString(_themeModeKey, _toString(ThemeMode.light));
      state = ThemeMode.light;
      return;
    }
    state = _fromString(prefs.getString(_themeModeKey));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, _toString(mode));
  }

  static ThemeMode _fromString(String? v) => switch (v) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.light,
  };

  static String _toString(ThemeMode m) => switch (m) {
    ThemeMode.light => 'light',
    ThemeMode.system => 'system',
    ThemeMode.dark => 'dark',
  };
}
