import 'package:flutter/services.dart';

/// Haptic feedback service for tactile user feedback
class HapticService {
  static final HapticService _instance = HapticService._internal();
  factory HapticService() => _instance;
  HapticService._internal();

  bool _enabled = true;

  /// Enable or disable haptic feedback
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Light haptic feedback for button taps
  Future<void> light() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Medium haptic feedback for important actions
  Future<void> medium() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Heavy haptic feedback for critical actions
  Future<void> heavy() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Success feedback (checkmark)
  Future<void> success() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Error feedback (shake)
  Future<void> error() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Selection feedback (picker scrolling)
  Future<void> selection() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Vibration pattern for notifications
  Future<void> vibratePattern() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.vibrate();
    } catch (_) {}
  }
}
