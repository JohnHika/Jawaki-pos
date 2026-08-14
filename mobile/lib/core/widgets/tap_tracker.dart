import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

/// Wraps the app in a global tap listener so every pointer-down is logged
/// with its screen coordinates, the widget under it, and the current route.
/// Logs go through debugPrint (visible in `adb logcat`) tagged `TAP_TRACK`
/// so they can be grepped/correlated against Flutter error logs, which use
/// the existing FLUTTER ERROR / PLATFORM ERROR banners in main.dart.
///
/// Debug/profile only — compiled out of release builds so it never adds
/// overhead or noise for real users.
class TapTracker extends StatelessWidget {
  const TapTracker({super.key, required this.child, required this.router});

  final Widget child;
  final GoRouter router;

  static String? _describeHit(BuildContext context, Offset position) {
    final hitResult = BoxHitTestResult();
    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return null;
    renderBox.hitTest(hitResult, position: renderBox.globalToLocal(position));
    for (final entry in hitResult.path) {
      final target = entry.target;
      if (target is RenderObject) {
        final element = target.debugCreator;
        if (element is DebugCreator) {
          return element.element.widget.runtimeType.toString();
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) return child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final route = router.routerDelegate.currentConfiguration.uri.toString();
        final widgetName = _describeHit(context, event.position) ?? 'unknown';
        debugPrint(
          'TAP_TRACK x=${event.position.dx.toStringAsFixed(1)} '
          'y=${event.position.dy.toStringAsFixed(1)} '
          'route=$route widget=$widgetName',
        );
      },
      child: child,
    );
  }
}
