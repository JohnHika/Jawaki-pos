import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _textSizeKey = 'app_text_size';
const _spacingKey = 'app_spacing';

/// How large text is drawn across the whole app.
enum AppTextSize {
  small('Small', 0.92),
  normal('Default', 1.0),
  large('Large', 1.12);

  const AppTextSize(this.label, this.scale);
  final String label;
  final double scale;

  static AppTextSize parse(String? v) => AppTextSize.values.firstWhere(
        (e) => e.name == v,
        orElse: () => AppTextSize.normal,
      );
}

/// How tightly lists, buttons and fields are packed.
enum AppSpacing {
  compact('Compact', VisualDensity.compact),
  comfortable('Comfortable', VisualDensity.standard);

  const AppSpacing(this.label, this.density);
  final String label;
  final VisualDensity density;

  static AppSpacing parse(String? v) => AppSpacing.values.firstWhere(
        (e) => e.name == v,
        orElse: () => AppSpacing.comfortable,
      );
}

class AppearanceState {
  const AppearanceState({
    this.textSize = AppTextSize.normal,
    this.spacing = AppSpacing.comfortable,
  });

  final AppTextSize textSize;
  final AppSpacing spacing;

  AppearanceState copyWith({AppTextSize? textSize, AppSpacing? spacing}) =>
      AppearanceState(
        textSize: textSize ?? this.textSize,
        spacing: spacing ?? this.spacing,
      );
}

/// Persisted text size and spacing, applied the moment they are picked.
final appearanceProvider =
    StateNotifierProvider<AppearanceNotifier, AppearanceState>(
  (ref) => AppearanceNotifier(),
);

class AppearanceNotifier extends StateNotifier<AppearanceState> {
  AppearanceNotifier() : super(const AppearanceState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AppearanceState(
        textSize: AppTextSize.parse(prefs.getString(_textSizeKey)),
        spacing: AppSpacing.parse(prefs.getString(_spacingKey)),
      );
    } catch (_) {
      // Keep the defaults when storage is unavailable.
    }
  }

  Future<void> setTextSize(AppTextSize value) async {
    state = state.copyWith(textSize: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textSizeKey, value.name);
  }

  Future<void> setSpacing(AppSpacing value) async {
    state = state.copyWith(spacing: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_spacingKey, value.name);
  }
}
