import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';

/// The computer frame for a settings sub-page: a page header with a back
/// arrow in place of the phone app bar, a hairline, and a centred body that
/// never stretches across the window.
///
/// [onBack] defaults to popping the route, or going to Settings when the page
/// was opened directly.
class DesktopSubPage extends StatelessWidget {
  const DesktopSubPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.maxWidth = 760,
    this.onBack,
    this.scroll = false,
    this.backTo = '/settings',
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final double maxWidth;
  final VoidCallback? onBack;
  final String backTo;

  /// Wrap [child] in a scroll view with page padding. Leave false when [child]
  /// already scrolls (a ListView).
  final bool scroll;

  void _back(BuildContext context) {
    if (onBack != null) {
      onBack!();
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      Navigator.maybeOf(context)?.maybePop();
    } else if (router.canPop()) {
      router.pop();
    } else {
      router.go(backTo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: title,
          subtitle: subtitle,
          actions: actions,
          padding: const EdgeInsets.fromLTRB(16, 16, 24, 12),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            onPressed: () => _back(context),
          ),
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: DesktopContent(
            maxWidth: maxWidth,
            child: scroll
                ? SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: child,
                  )
                : child,
          ),
        ),
      ],
    );
  }
}
