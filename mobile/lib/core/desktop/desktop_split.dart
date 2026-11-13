import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'desktop_layout.dart';

/// A page with a main area and an optional inspector docked on the right.
///
/// Click a row and the inspector slides in beside the table; press Esc or the
/// close button and it slides away. On a narrow window the inspector floats
/// over the page instead of squeezing it.
class DesktopInspectorLayout extends StatelessWidget {
  const DesktopInspectorLayout({
    super.key,
    required this.main,
    this.inspector,
    this.onClose,
    this.inspectorWidth = 360,
    this.overlayBelow = 980,
  });

  final Widget main;

  /// null hides the inspector.
  final Widget? inspector;
  final VoidCallback? onClose;
  final double inspectorWidth;

  /// Below this width the inspector overlays the page.
  final double overlayBelow;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            inspector != null &&
            onClose != null) {
          onClose!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final overlay = constraints.maxWidth < overlayBelow;
          final open = inspector != null;

          if (overlay) {
            return Stack(
              children: [
                Positioned.fill(child: main),
                if (open) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: onClose,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: inspectorWidth.clamp(0, constraints.maxWidth - 48),
                    child: _InspectorFrame(palette: p, child: inspector!),
                  ),
                ],
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: main),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: open ? inspectorWidth : 0,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: inspectorWidth,
                    maxWidth: inspectorWidth,
                    child: open
                        ? _InspectorFrame(palette: p, child: inspector!)
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InspectorFrame extends StatelessWidget {
  const _InspectorFrame({required this.palette, required this.child});

  final DesktopPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: child,
    );
  }
}

/// Standard contents for an inspector: a title row with a close button, a
/// scrolling body and an optional pinned action bar.
class DesktopInspector extends StatelessWidget {
  const DesktopInspector({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.onClose,
    this.actions = const [],
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onClose;

  /// Icon buttons at the right of the title.
  final List<Widget> actions;

  /// Primary buttons pinned at the bottom.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.sora(
                        color: p.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
              ...actions,
              if (onClose != null)
                IconButton(
                  tooltip: 'Close (Esc)',
                  icon: const Icon(Icons.close_rounded, size: 19),
                  onPressed: onClose,
                ),
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
        if (footer != null) ...[
          Divider(height: 1, color: p.border),
          Padding(padding: const EdgeInsets.all(14), child: footer),
        ],
      ],
    );
  }
}

/// A left list and a right detail, side by side (customers, partners). The
/// list has a fixed width; the detail takes the rest.
class DesktopListDetail extends StatelessWidget {
  const DesktopListDetail({
    super.key,
    required this.list,
    required this.detail,
    this.listWidth = 340,
  });

  final Widget list;
  final Widget detail;
  final double listWidth;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Row(
      children: [
        SizedBox(width: listWidth, child: list),
        VerticalDivider(width: 1, color: p.border),
        Expanded(child: detail),
      ],
    );
  }
}
