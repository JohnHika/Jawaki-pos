import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_theme.dart';
import '../../../../core/theme/design_system.dart';
import '../../../notifications/presentation/widgets/notification_bell.dart';
import 'desktop_command_palette.dart';
import 'desktop_nav.dart';

/// Whether the shop's records are on this computer, shared, or unreachable.
enum DesktopConnection { online, offline, localOnly }

/// The desktop frame around every routed page: a permanent sidebar, a top bar
/// with search and status, and the page itself on a lighter sheet.
///
/// It replaces the phone's floating bottom bar and "More" sheet. Pages are
/// untouched: they render inside [child] with a desktop-tuned theme.
class DesktopShell extends StatefulWidget {
  const DesktopShell({
    super.key,
    required this.items,
    required this.settingsItem,
    required this.location,
    required this.onNavigate,
    required this.child,
    required this.companyName,
    required this.userName,
    required this.role,
    this.connection = DesktopConnection.online,
    this.statusWidgets = const [],
    this.extraCommands = const [],
    this.onLock,
    this.version,
  });

  /// Everything except Settings, in the order the shop wants them.
  final List<DesktopNavItem> items;
  final DesktopNavItem settingsItem;

  /// The router's current location, used to light the right sidebar item.
  final String location;
  final ValueChanged<String> onNavigate;
  final Widget child;

  final String companyName;
  final String userName;
  final String role;
  final DesktopConnection connection;

  /// Extra chips for the top bar (for example "Update ready").
  final List<Widget> statusWidgets;

  /// Actions added to the command palette beside the page list.
  final List<DesktopCommand> extraCommands;
  final VoidCallback? onLock;

  /// App version for the status bar ("1.0.181").
  final String? version;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  static const _collapsedKey = 'desktop_sidebar_collapsed';

  /// null follows the window width; true/false is the person's own choice.
  bool? _userCollapsed;
  bool _paletteOpen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _loadCollapsed();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  Future<void> _loadCollapsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_collapsedKey);
      if (saved != null && mounted) setState(() => _userCollapsed = saved);
    } catch (_) {
      // Not remembering the sidebar is harmless.
    }
  }

  /// The sidebar follows the person's own choice once they have made one.
  /// Until then it folds into the rail on a narrow window and on Sell, where
  /// the product grid and ticket want every pixel.
  bool _collapsedFor(double width) =>
      _userCollapsed ??
      (width < DesktopLayout.sidebarFullMinWidth || _current?.path == '/');

  Future<void> _toggleSidebar(double width) async {
    final next = !_collapsedFor(width);
    setState(() => _userCollapsed = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_collapsedKey, next);
    } catch (_) {}
  }

  List<DesktopNavItem> get _all => [...widget.items, widget.settingsItem];

  DesktopNavItem? get _current {
    DesktopNavItem? best;
    for (final item in _all) {
      if (item.path.isEmpty || !item.matches(widget.location)) continue;
      if (best == null || item.path.length > best.path.length) best = item;
    }
    return best;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;

    if (keyboard.isControlPressed && key == LogicalKeyboardKey.keyK) {
      _openPalette();
      return true;
    }
    if (keyboard.isControlPressed && key == LogicalKeyboardKey.keyB) {
      _toggleSidebar(MediaQuery.sizeOf(context).width);
      return true;
    }
    if (keyboard.isAltPressed && !keyboard.isControlPressed) {
      final digits = <LogicalKeyboardKey>[
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ];
      final index = digits.indexOf(key);
      if (index >= 0 && index < widget.items.length) {
        widget.onNavigate(widget.items[index].path);
        return true;
      }
    }
    return false;
  }

  Future<void> _openPalette() async {
    if (_paletteOpen) return;
    // Another dialog or full-screen route is on top: leave it alone.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _paletteOpen = true;
    try {
      await showDesktopCommandPalette(context, commands: _commands());
    } finally {
      _paletteOpen = false;
    }
  }

  List<DesktopCommand> _commands() {
    final all = _all;
    return [
      for (var i = 0; i < all.length; i++)
        DesktopCommand(
          label: all[i].label,
          icon: all[i].icon,
          section: all[i].group.label,
          keywords: all[i].keywords,
          shortcut: i < widget.items.length && i < 9 ? 'Alt ${i + 1}' : null,
          run: () => widget.onNavigate(all[i].path),
        ),
      ...widget.extraCommands,
      DesktopCommand(
        label: 'Show or hide sidebar',
        icon: Icons.view_sidebar_outlined,
        section: 'Action',
        shortcut: 'Ctrl B',
        keywords: const ['menu', 'collapse', 'navigation'],
        run: () => _toggleSidebar(MediaQuery.sizeOf(context).width),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final collapsed = _collapsedFor(width);
    final current = _current;

    return Scaffold(
      backgroundColor: p.frame,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _Sidebar(
                  palette: p,
                  collapsed: collapsed,
                  items: widget.items,
                  settingsItem: widget.settingsItem,
                  current: current,
                  companyName: widget.companyName,
                  onNavigate: widget.onNavigate,
                ),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(
                        palette: p,
                        collapsed: collapsed,
                        onToggleSidebar: () => _toggleSidebar(width),
                        onSearch: _openPalette,
                        connection: widget.connection,
                        statusWidgets: widget.statusWidgets,
                        userName: widget.userName,
                        role: widget.role,
                        onSettings: () =>
                            widget.onNavigate(widget.settingsItem.path),
                        onLock: widget.onLock,
                        extraCommands: widget.extraCommands,
                      ),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(right: 10, bottom: 4),
                          decoration: BoxDecoration(
                            color: p.panel,
                            borderRadius: BorderRadius.circular(
                              DesktopTokens.panelRadius,
                            ),
                            border: Border.all(color: p.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Theme(
                            data: DesktopTheme.of(Theme.of(context)),
                            child: DesktopScope(
                              sidebarCollapsed: collapsed,
                              child: widget.child,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _StatusBar(
            palette: p,
            connection: widget.connection,
            userName: widget.userName,
            role: widget.role,
            version: widget.version,
          ),
        ],
      ),
    );
  }
}

// ─── Sidebar ─────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.palette,
    required this.collapsed,
    required this.items,
    required this.settingsItem,
    required this.current,
    required this.companyName,
    required this.onNavigate,
  });

  final DesktopPalette palette;
  final bool collapsed;
  final List<DesktopNavItem> items;
  final DesktopNavItem settingsItem;
  final DesktopNavItem? current;
  final String companyName;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final groups = <DesktopNavGroup, List<DesktopNavItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.group, () => []).add(item);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed ? DesktopTokens.railWidth : DesktopTokens.sidebarWidth,
      color: p.frame,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          maxWidth: DesktopTokens.sidebarWidth,
          child: SizedBox(
            width: collapsed
                ? DesktopTokens.railWidth
                : DesktopTokens.sidebarWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Brand(
                  palette: p,
                  collapsed: collapsed,
                  companyName: companyName,
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      collapsed ? 12 : 10,
                      4,
                      collapsed ? 12 : 10,
                      12,
                    ),
                    children: [
                      for (final group in DesktopNavGroup.values)
                        if (groups[group]?.isNotEmpty ?? false) ...[
                          _GroupLabel(
                            palette: p,
                            label: group.label,
                            collapsed: collapsed,
                          ),
                          for (final item in groups[group]!)
                            _NavTile(
                              palette: p,
                              item: item,
                              selected: identical(item, current),
                              collapsed: collapsed,
                              onTap: () => onNavigate(item.path),
                            ),
                        ],
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    collapsed ? 12 : 10,
                    0,
                    collapsed ? 12 : 10,
                    12,
                  ),
                  child: _NavTile(
                    palette: p,
                    item: settingsItem,
                    selected: identical(settingsItem, current),
                    collapsed: collapsed,
                    onTap: () => onNavigate(settingsItem.path),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({
    required this.palette,
    required this.collapsed,
    required this.companyName,
  });

  final DesktopPalette palette;
  final bool collapsed;
  final String companyName;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SizedBox(
      height: DesktopTokens.topBarHeight + 8,
      child: Padding(
        padding: EdgeInsets.only(left: collapsed ? 0 : 16, right: 12, top: 8),
        child: Row(
          mainAxisAlignment:
              collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/axon_app_icon_512.png',
                width: 30,
                height: 30,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => Container(
                  width: 30,
                  height: 30,
                  color: DesignColors.accent,
                ),
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.sora(
                        color: p.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      'Counterbase',
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({
    required this.palette,
    required this.label,
    required this.collapsed,
  });

  final DesktopPalette palette;
  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Divider(height: 1, color: palette.border),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: palette.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.palette,
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final DesktopPalette palette;
  final DesktopNavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final iconColor = selected
        ? (p.dark ? DesignColors.accent : p.accent)
        : p.textMuted;
    final tile = Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: selected ? p.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
            hoverColor: p.hover,
            child: SizedBox(
              height: 36,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
                child: Row(
                  mainAxisAlignment: collapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(
                      selected ? item.activeIcon : item.icon,
                      size: 19,
                      color: iconColor,
                    ),
                    if (!collapsed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: selected ? p.text : p.textMuted,
                            fontSize: 13.5,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return collapsed
        ? Tooltip(
            message: item.label,
            preferBelow: false,
            waitDuration: const Duration(milliseconds: 300),
            child: tile,
          )
        : tile;
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.palette,
    required this.collapsed,
    required this.onToggleSidebar,
    required this.onSearch,
    required this.connection,
    required this.statusWidgets,
    required this.userName,
    required this.role,
    required this.onSettings,
    required this.onLock,
    required this.extraCommands,
  });

  final DesktopPalette palette;
  final bool collapsed;
  final VoidCallback onToggleSidebar;
  final VoidCallback onSearch;
  final DesktopConnection connection;
  final List<Widget> statusWidgets;
  final String userName;
  final String role;
  final VoidCallback onSettings;
  final VoidCallback? onLock;
  final List<DesktopCommand> extraCommands;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SizedBox(
      height: DesktopTokens.topBarHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 14),
        child: Row(
          children: [
            IconButton(
              tooltip: collapsed ? 'Show sidebar (Ctrl B)' : 'Hide sidebar (Ctrl B)',
              icon: Icon(
                Icons.view_sidebar_outlined,
                size: 20,
                color: p.textMuted,
              ),
              onPressed: onToggleSidebar,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _SearchPill(palette: p, onTap: onSearch),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (connection == DesktopConnection.offline) ...[
              _ConnectionChip(palette: p, connection: connection),
            ],
            for (final w in statusWidgets) ...[const SizedBox(width: 8), w],
            const SizedBox(width: 4),
            const NotificationBell(),
            const SizedBox(width: 4),
            _UserMenu(
              palette: p,
              userName: userName,
              role: role,
              onSettings: onSettings,
              onLock: onLock,
              extraCommands: extraCommands,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.palette, required this.onTap});

  final DesktopPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Semantics(
      button: true,
      label: 'Search pages and actions',
      excludeSemantics: true,
      child: Material(
        color: p.panel,
        borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
          hoverColor: p.hover,
          child: Container(
            height: 34,
            padding: const EdgeInsets.only(left: 10, right: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
              border: Border.all(color: p.border),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 18, color: p.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Search pages and actions',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const DesktopKeyCap(label: 'Ctrl K'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.palette, required this.connection});

  final DesktopPalette palette;
  final DesktopConnection connection;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final (label, tip, color) = switch (connection) {
      DesktopConnection.online => (
          'Online',
          'Connected. Sales sync as they happen.',
          DesignColors.success,
        ),
      DesktopConnection.offline => (
          'Offline',
          'No internet. Sales are kept here and sync when you are back online.',
          DesignColors.warning,
        ),
      DesktopConnection.localOnly => (
          'This computer',
          'Records stay on this computer.',
          DesignColors.info,
        ),
    };
    return Tooltip(
      message: tip,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: p.dark ? 0.14 : 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserMenu extends StatelessWidget {
  const _UserMenu({
    required this.palette,
    required this.userName,
    required this.role,
    required this.onSettings,
    required this.onLock,
    required this.extraCommands,
  });

  final DesktopPalette palette;
  final String userName;
  final String role;
  final VoidCallback onSettings;
  final VoidCallback? onLock;
  final List<DesktopCommand> extraCommands;

  String get _initials {
    final parts =
        userName.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    if (parts.isEmpty) return 'U';
    final list = parts.toList();
    final first = list.first[0];
    final second = list.length > 1 ? list.last[0] : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return PopupMenuButton<Object>(
      tooltip: userName.isEmpty ? 'Account' : userName,
      offset: const Offset(0, 40),
      color: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: p.borderStrong),
      ),
      onSelected: (value) {
        if (value == 'settings') onSettings();
        if (value == 'lock') onLock?.call();
        if (value is DesktopCommand) value.run();
      },
      itemBuilder: (context) => [
        PopupMenuItem<Object>(
          enabled: false,
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                userName.isEmpty ? 'Signed in' : userName,
                style: GoogleFonts.plusJakartaSans(
                  color: p.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (role.isNotEmpty)
                Text(
                  role,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<Object>(
          value: 'settings',
          height: 40,
          child: Text('Settings'),
        ),
        for (final command in extraCommands)
          PopupMenuItem<Object>(
            value: command,
            height: 40,
            child: Text(command.label),
          ),
        if (onLock != null)
          const PopupMenuItem<Object>(
            value: 'lock',
            height: 40,
            child: Text('Lock Counterbase'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: CircleAvatar(
          radius: 15,
          backgroundColor: p.dark ? p.panelAlt : DesignColors.peach,
          child: Text(
            _initials,
            style: GoogleFonts.sora(
              color: p.dark ? DesignColors.accent : p.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Status bar ──────────────────────────────────────────────────────

/// A thin strip along the bottom of the window: where the shop's records are
/// kept, hardware readouts (scanner, printer) other parts of the app publish,
/// who is signed in and which version is running.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.palette,
    required this.connection,
    required this.userName,
    required this.role,
    required this.version,
  });

  final DesktopPalette palette;
  final DesktopConnection connection;
  final String userName;
  final String role;
  final String? version;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final (label, color) = switch (connection) {
      DesktopConnection.online => ('Online', DesignColors.success),
      DesktopConnection.offline => ('Offline', DesignColors.warning),
      DesktopConnection.localOnly => (
          'Records stay on this computer',
          DesignColors.info,
        ),
    };
    TextStyle style([Color? c]) => GoogleFonts.plusJakartaSans(
          color: c ?? p.textMuted,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        );

    final who = [
      if (userName.trim().isNotEmpty) userName.trim(),
      if (role.trim().isNotEmpty) role.trim(),
    ].join(' · ');

    return SizedBox(
      height: DesktopTokens.statusBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(label, style: style()),
            const Spacer(),
            ValueListenableBuilder<List<DesktopStatusEntry>>(
              valueListenable: DesktopStatusRegistry.entries,
              builder: (context, entries, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in entries)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Tooltip(
                        message: e.tooltip ?? e.label,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(e.icon, size: 13, color: e.color ?? p.textMuted),
                            const SizedBox(width: 5),
                            Text(e.label, style: style(e.color)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (who.isNotEmpty) ...[
              const SizedBox(width: 16),
              Text(who, style: style()),
            ],
            if (version != null && version!.isNotEmpty) ...[
              const SizedBox(width: 16),
              Text('v$version', style: style(p.textFaint)),
            ],
          ],
        ),
      ),
    );
  }
}
