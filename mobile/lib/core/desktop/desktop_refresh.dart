import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop_layout.dart';

/// Pull to refresh that also works with a mouse.
///
/// On a phone, or a Windows window narrower than
/// [DesktopLayout.shellMinWidth], this is exactly a [RefreshIndicator]: same
/// arguments, same widget, same behaviour.
///
/// In the desktop shell nobody can drag a list down with a mouse, so the page
/// also gets a slim strip above it with a Refresh button (it shows progress
/// while [onRefresh] runs), and F5 or Ctrl+R refresh it whenever focus is
/// somewhere inside the page. The pull gesture stays for touch screens.
class DesktopRefresh extends StatefulWidget {
  const DesktopRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color,
    this.backgroundColor,
    this.displacement = 40.0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final Color? color;
  final Color? backgroundColor;
  final double displacement;

  @override
  State<DesktopRefresh> createState() => _DesktopRefreshState();
}

class _DesktopRefreshState extends State<DesktopRefresh> {
  bool _busy = false;

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final indicator = RefreshIndicator(
      onRefresh: widget.onRefresh,
      color: widget.color,
      backgroundColor: widget.backgroundColor,
      displacement: widget.displacement,
      child: widget.child,
    );
    if (!DesktopLayout.wantsShell(context)) return indicator;

    final p = DesktopPalette.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): _refresh,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _refresh,
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        debugLabel: 'DesktopRefresh',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  DesktopTokens.gutter, 4, DesktopTokens.gutter, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: p.textMuted,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Refresh (F5)',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    constraints:
                        const BoxConstraints.tightFor(width: 32, height: 32),
                    padding: EdgeInsets.zero,
                    onPressed: _busy ? null : _refresh,
                    icon: Icon(Icons.refresh_rounded, color: p.textMuted),
                  ),
                ],
              ),
            ),
            Expanded(child: indicator),
          ],
        ),
      ),
    );
  }
}
