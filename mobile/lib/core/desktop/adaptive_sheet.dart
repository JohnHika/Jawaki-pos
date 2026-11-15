import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'adaptive_overlays.dart';
import 'desktop_layout.dart';

export 'adaptive_overlays.dart' show DesktopSheetStyle;

/// Drop-in replacement for `showModalBottomSheet`.
///
/// On a phone, or a Windows window narrower than [DesktopLayout.shellMinWidth],
/// every argument is passed straight through to `showModalBottomSheet`, so the
/// phone looks and behaves exactly as it did before.
///
/// In the desktop shell the same [builder] opens as a centred dialog
/// ([DesktopSheetStyle.dialog], [desktopWidth] wide, Esc and the scrim close
/// it, the keyboard pushes it up) or as a right-hand panel
/// ([DesktopSheetStyle.sidePanel], for tall forms). A sheet that asked for a
/// transparent background (it draws its own rounded card) gets a transparent
/// dialog so the card is not boxed twice.
///
/// Sheets that dispose their controllers with `disposeAfterModalCloses` keep
/// working: the dialog is a route too, so `ModalRoute.of(context)` is valid.
Future<T?> showAdaptiveModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
  DesktopSheetStyle desktopStyle = DesktopSheetStyle.dialog,
  double desktopWidth = 560,
}) {
  if (!DesktopLayout.wantsShell(context)) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      backgroundColor: backgroundColor,
      barrierLabel: barrierLabel,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      barrierColor: barrierColor,
      isScrollControlled: isScrollControlled,
      scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      routeSettings: routeSettings,
      transitionAnimationController: transitionAnimationController,
      anchorPoint: anchorPoint,
      sheetAnimationStyle: sheetAnimationStyle,
      requestFocus: requestFocus,
    );
  }

  final transparent = backgroundColor == Colors.transparent;
  if (desktopStyle == DesktopSheetStyle.sidePanel) {
    return showAdaptiveSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      desktopStyle: DesktopSheetStyle.sidePanel,
      desktopWidth: desktopWidth,
      builder: (panelContext) => _EscapeCloses(
        child: SafeArea(child: Builder(builder: builder)),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: isDismissible,
    routeSettings: routeSettings,
    builder: (dialogContext) => _EscapeCloses(
      child: Dialog(
        backgroundColor: transparent ? Colors.transparent : backgroundColor,
        elevation: transparent ? 0 : null,
        shadowColor: transparent ? Colors.transparent : null,
        surfaceTintColor: transparent ? Colors.transparent : null,
        clipBehavior: transparent ? Clip.none : Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: desktopWidth,
          child: Builder(builder: builder),
        ),
      ),
    ),
  );
}

/// Makes Esc close the dialog or panel it wraps, wherever focus is inside it.
class _EscapeCloses extends StatelessWidget {
  const _EscapeCloses({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: child,
    );
  }
}
