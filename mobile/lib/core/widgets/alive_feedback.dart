import 'dart:async';

import 'package:flutter/material.dart';

import '../services/haptic_service.dart';
import '../theme/design_system.dart';
import 'motion.dart' show reducedMotion;

/// "This has been done": one place for the small acknowledgement every action
/// should give, so the app feels alive instead of silent.
///
/// ```dart
/// // After something worked: soft tap, check pops in, message, optional undo.
/// Alive.done(context, 'Price list copied');
/// Alive.done(context, 'Customer removed',
///     undoLabel: 'Undo', onUndo: () => restore());
///
/// // Wrap an action: runs it, then acknowledges (or explains the failure).
/// final ok = await Alive.run(
///   context,
///   () => saveThing(),
///   done: 'Saved',
///   failed: 'Could not save. Try again.',
/// );
///
/// // A button icon that turns into a check for a moment after the action.
/// AliveIcon(done: _copied, idle: Icon(Icons.copy_rounded))
/// ```
///
/// Rules: say what happened in plain words ("Saved", not "Success"), keep the
/// haptic soft, and offer Undo where a mistake is cheap to take back.
class Alive {
  const Alive._();

  /// Acknowledges a finished action: soft haptic, a pop-in check and [message].
  /// With [onUndo] the message carries an undo button.
  static void done(
    BuildContext context,
    String message, {
    IconData icon = Icons.check_circle_rounded,
    Color color = DesignColors.success,
    String? undoLabel,
    VoidCallback? onUndo,
    bool haptic = true,
  }) {
    if (haptic) unawaited(HapticService().success());
    showGlassSnackBar(
      context,
      message,
      icon: icon,
      color: color,
      actionLabel: onUndo == null ? null : (undoLabel ?? 'Undo'),
      onAction: onUndo,
    );
  }

  /// Explains a failure with a firmer haptic. Say what to do next.
  static void failed(BuildContext context, String message) {
    unawaited(HapticService().error());
    showGlassSnackBar(
      context,
      message,
      icon: Icons.error_outline_rounded,
      color: DesignColors.error,
    );
  }

  /// Runs [action]; on success acknowledges with [done], on a thrown error shows
  /// [failed]. Returns whether it worked. Nothing is shown if the screen was
  /// closed while the action ran.
  static Future<bool> run(
    BuildContext context,
    Future<void> Function() action, {
    required String done,
    String failed = 'That did not go through. Please try again.',
    String? undoLabel,
    VoidCallback? onUndo,
  }) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) Alive.failed(context, failed);
      return false;
    }
    if (context.mounted) {
      Alive.done(context, done, undoLabel: undoLabel, onUndo: onUndo);
    }
    return true;
  }
}

/// An icon that swaps to a green check with a spring while [done] is true.
/// Set [done] for a moment after the action (see [AliveIcon.flash]).
class AliveIcon extends StatelessWidget {
  const AliveIcon({
    super.key,
    required this.idle,
    required this.done,
    this.size = 20,
    this.doneColor = DesignColors.success,
  });

  final Widget idle;
  final bool done;
  final double size;
  final Color doneColor;

  /// Sets [flag] true now and false after [hold]; use with setState. Returns the
  /// timer so the screen can cancel it in dispose().
  static Timer flash(
    void Function(bool value) flag, {
    Duration hold = const Duration(milliseconds: 1400),
  }) {
    flag(true);
    return Timer(hold, () => flag(false));
  }

  @override
  Widget build(BuildContext context) {
    final still = reducedMotion(context);
    return AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 320),
      switchInCurve: Curves.elasticOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: done
          ? Icon(Icons.check_rounded,
              key: const ValueKey('alive-done'), size: size, color: doneColor)
          : KeyedSubtree(key: const ValueKey('alive-idle'), child: idle),
    );
  }
}
