import 'package:flutter/material.dart';

import 'desktop_layout.dart';

/// How a sheet appears on a computer. A phone always gets a bottom sheet.
enum DesktopSheetStyle {
  /// A centred dialog. Short forms, pickers, confirmations.
  dialog,

  /// A panel that slides in from the right edge and keeps the page visible
  /// behind it. Details, editors, anything the person compares with the page.
  sidePanel,
}

/// Opens [builder] the way the platform expects: a bottom sheet on a phone, a
/// centred dialog or right-hand panel in the desktop shell.
///
/// The builder's content is shown as is, so it should not draw its own drag
/// handle or rounded top. Use [DesktopSheetFrame] for a titled frame.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DesktopSheetStyle desktopStyle = DesktopSheetStyle.dialog,
  double desktopWidth = 520,
  bool useRootNavigator = true,
  bool isDismissible = true,
  Color? phoneBackgroundColor,
}) {
  if (!DesktopLayout.wantsShell(context)) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      backgroundColor: phoneBackgroundColor,
      builder: builder,
    );
  }
  switch (desktopStyle) {
    case DesktopSheetStyle.dialog:
      return showDialog<T>(
        context: context,
        useRootNavigator: useRootNavigator,
        barrierDismissible: isDismissible,
        builder: (dialogContext) => Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: desktopWidth),
            child: builder(dialogContext),
          ),
        ),
      );
    case DesktopSheetStyle.sidePanel:
      return showGeneralDialog<T>(
        context: context,
        useRootNavigator: useRootNavigator,
        barrierDismissible: isDismissible,
        barrierLabel: 'Close panel',
        barrierColor: Colors.black.withValues(alpha: 0.32),
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (panelContext, _, __) {
          final p = DesktopPalette.of(panelContext);
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: p.panel,
              elevation: 0,
              shape: Border(left: BorderSide(color: p.borderStrong)),
              child: SizedBox(
                width: desktopWidth,
                height: double.infinity,
                child: builder(panelContext),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          )),
          child: child,
        ),
      );
  }
}

/// Like [showAdaptiveSheet], but resolves only after the exit animation has
/// finished, not when the sheet is popped.
///
/// A sheet's builder keeps rebuilding while it closes, so a screen that
/// disposes the sheet's text controllers right after `await` crashes with
/// "used after being disposed". Awaiting the route's `completed` future closes
/// that window. The phone gets the same bottom sheet as before.
Future<T?> showAdaptiveSheetUntilClosed<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DesktopSheetStyle desktopStyle = DesktopSheetStyle.dialog,
  double desktopWidth = 520,
  bool showDragHandle = true,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final TransitionRoute<T> route;
  if (!DesktopLayout.wantsShell(context)) {
    final localizations = MaterialLocalizations.of(context);
    route = ModalBottomSheetRoute<T>(
      builder: builder,
      capturedThemes: themes,
      isScrollControlled: true,
      showDragHandle: showDragHandle,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint:
          localizations.scrimOnTapHint(localizations.bottomSheetLabel),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    );
  } else if (desktopStyle == DesktopSheetStyle.dialog) {
    route = DialogRoute<T>(
      context: context,
      themes: themes,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: desktopWidth),
          child: builder(dialogContext),
        ),
      ),
    );
  } else {
    route = RawDialogRoute<T>(
      barrierDismissible: true,
      barrierLabel: 'Close panel',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (panelContext, _, __) {
        final p = DesktopPalette.of(panelContext);
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: p.panel,
            elevation: 0,
            shape: Border(left: BorderSide(color: p.borderStrong)),
            child: SizedBox(
              width: desktopWidth,
              height: double.infinity,
              child: builder(panelContext),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        )),
        child: child,
      ),
    );
  }
  final result = await navigator.push<T>(route);
  await route.completed;
  return result;
}

/// A titled frame for dialog and side-panel content: title, close button,
/// scrollable body, optional footer actions. Matches the page header.
class DesktopSheetFrame extends StatelessWidget {
  const DesktopSheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(24, 8, 24, 24),
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Buttons along the bottom edge, right-aligned.
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: p.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: p.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        Flexible(
          child: SingleChildScrollView(
            padding: padding,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: child,
            ),
          ),
        ),
        if (actions.isNotEmpty) ...[
          Divider(height: 1, color: p.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actions[i],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
