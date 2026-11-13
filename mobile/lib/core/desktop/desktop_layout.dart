import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/design_system.dart';

/// When the app is a computer program, not a phone program.
///
/// The phone keeps its bottom bar, sheets and one-column pages. A computer
/// window gets a permanent sidebar, a top bar, panels and tables. The switch is
/// the platform plus the window's width, never a device guess, so a Windows
/// window dragged narrow falls back to the phone layout instead of breaking.
class DesktopLayout {
  const DesktopLayout._();

  /// Tests set this to pretend to be (or not be) a computer.
  @visibleForTesting
  static bool? debugIsDesktopPlatform;

  static bool get isDesktopPlatform {
    final forced = debugIsDesktopPlatform;
    if (forced != null) return forced;
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  /// Narrower than this and the window shows the phone layout.
  static const double shellMinWidth = 900;

  /// Narrower than this and the sidebar folds into an icon rail. A 1366-wide
  /// laptop at 125% display scaling is about 1093 logical pixels, so it
  /// starts on the rail and the page keeps the room.
  static const double sidebarFullMinWidth = 1100;

  /// True when this window should show the desktop shell.
  static bool wantsShell(BuildContext context) =>
      isDesktopPlatform && MediaQuery.sizeOf(context).width >= shellMinWidth;
}

/// Sizes shared by every desktop surface. One place, so the sidebar, the top
/// bar and every page agree on the same grid.
class DesktopTokens {
  const DesktopTokens._();

  static const double sidebarWidth = 232;
  static const double railWidth = 56;
  static const double topBarHeight = 44;
  static const double statusBarHeight = 24;

  /// Space between the window edge / panel edge and page content.
  static const double gutter = 24;

  /// Pages that are read like documents (settings, forms, lists) stop growing
  /// here so a wide monitor does not stretch a line of text across the room.
  static const double contentMaxWidth = 1280;

  static const double controlHeight = 36;
  static const double rowHeight = 44;
  static const double compactRowHeight = 36;

  static const double controlRadius = 8;
  static const double panelRadius = 14;
}

/// The colours of the desktop frame: the sidebar and top bar sit on [frame];
/// pages sit on [panel], a lighter sheet with a hairline edge.
@immutable
class DesktopPalette {
  const DesktopPalette({
    required this.dark,
    required this.frame,
    required this.panel,
    required this.panelAlt,
    required this.border,
    required this.borderStrong,
    required this.hover,
    required this.selected,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
  });

  final bool dark;
  final Color frame;
  final Color panel;
  final Color panelAlt;
  final Color border;
  final Color borderStrong;
  final Color hover;
  final Color selected;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color accent;

  static const DesktopPalette light = DesktopPalette(
    dark: false,
    frame: Color(0xFFF2EBE0),
    panel: Color(0xFFFFFDFA),
    panelAlt: Color(0xFFF8F3EC),
    border: Color(0xFFE6DDCF),
    borderStrong: Color(0xFFD6CAB8),
    hover: Color(0x0F5A3E1E),
    selected: Color(0x1FFF7A33),
    text: DesignColors.textPrimary,
    textMuted: DesignColors.textSecondary,
    textFaint: DesignColors.textTertiary,
    // Orange text on the warm frame needs a deeper shade to stay readable.
    accent: Color(0xFFB04106),
  );

  static const DesktopPalette darkPalette = DesktopPalette(
    dark: true,
    frame: DesignColors.darkBg,
    panel: DesignColors.darkSurface,
    panelAlt: Color(0xFF1B1824),
    border: Color(0xFF26222F),
    borderStrong: DesignColors.darkBorder,
    hover: Color(0x14FFFFFF),
    selected: Color(0x29FF7A33),
    text: DesignColors.darkTextPrimary,
    textMuted: DesignColors.darkTextSecondary,
    textFaint: DesignColors.darkTextTertiary,
    accent: DesignColors.accent,
  );

  static DesktopPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkPalette : light;
}

/// One small readout in the status bar's right side: scanner ready, printer
/// offline, 2 sales waiting. Pages and services publish theirs here and the
/// shell shows them.
@immutable
class DesktopStatusEntry {
  const DesktopStatusEntry({
    required this.id,
    required this.label,
    required this.icon,
    this.color,
    this.tooltip,
  });

  /// Entries with the same id replace each other.
  final String id;
  final String label;
  final IconData icon;
  final Color? color;
  final String? tooltip;
}

/// The status bar's right-hand entries. Static on purpose: a barcode scanner
/// service or a printer check publishes here without knowing about the shell.
class DesktopStatusRegistry {
  const DesktopStatusRegistry._();

  static final ValueNotifier<List<DesktopStatusEntry>> entries =
      ValueNotifier(const []);

  static void set(DesktopStatusEntry entry) {
    final next = [
      for (final e in entries.value)
        if (e.id != entry.id) e,
      entry,
    ];
    entries.value = next;
  }

  static void remove(String id) {
    if (!entries.value.any((e) => e.id == id)) return;
    entries.value = [
      for (final e in entries.value)
        if (e.id != id) e,
    ];
  }
}

/// Present below the desktop shell. Pages ask it whether they are inside the
/// shell (so they can drop their own bottom bars, floating buttons and extra
/// headers) and how wide the sidebar currently is.
class DesktopScope extends InheritedWidget {
  const DesktopScope({
    super.key,
    required this.sidebarCollapsed,
    required super.child,
  });

  final bool sidebarCollapsed;

  static DesktopScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopScope>();

  @override
  bool updateShouldNotify(DesktopScope oldWidget) =>
      oldWidget.sidebarCollapsed != sidebarCollapsed;
}

extension DesktopContext on BuildContext {
  /// True when this page is drawn inside the desktop shell.
  bool get inDesktopShell => DesktopScope.maybeOf(this) != null;

  /// Desktop palette for this context's theme brightness.
  DesktopPalette get desktop => DesktopPalette.of(this);
}

/// Centres page content and stops it growing past [maxWidth], with the desktop
/// gutter on both sides. Pages that fill the window (the till, chat) skip it.
class DesktopContent extends StatelessWidget {
  const DesktopContent({
    super.key,
    required this.child,
    this.maxWidth = DesktopTokens.contentMaxWidth,
    this.padding = const EdgeInsets.symmetric(
      horizontal: DesktopTokens.gutter,
    ),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
