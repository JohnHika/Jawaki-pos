import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import 'settings_desktop_widgets.dart';

/// The three headings of the Settings sub-navigation.
enum DesktopSettingsNavGroup {
  shop('Shop'),
  thisComputer('This computer'),
  account('Account');

  const DesktopSettingsNavGroup(this.label);
  final String label;
}

/// One setting that can be searched and drawn: its words for the search box
/// and a builder for the row itself.
class DesktopSettingItem {
  const DesktopSettingItem({
    required this.id,
    required this.title,
    required this.builder,
    this.helper,
    this.keywords = const [],
  });

  final String id;
  final String title;
  final String? helper;
  final List<String> keywords;
  final WidgetBuilder builder;

  bool matches(String paneLabel, List<String> terms) {
    final haystack =
        [title, helper ?? '', paneLabel, ...keywords].join(' ').toLowerCase();
    return terms.every(haystack.contains);
  }
}

/// Rows drawn together on one panel under an optional heading.
class DesktopSettingGroupData {
  const DesktopSettingGroupData({
    required this.items,
    this.title,
    this.note,
  });

  final String? title;
  final String? note;
  final List<DesktopSettingItem> items;
}

/// One page of the Settings sub-navigation.
///
/// A pane with [onOpen] is a link out to another page (Users and roles): it is
/// listed in the navigation with an arrow and never selected.
class DesktopSettingsPaneData {
  const DesktopSettingsPaneData({
    required this.id,
    required this.label,
    required this.icon,
    required this.group,
    this.groups = const [],
    this.heading,
    this.leading,
    this.onOpen,
  });

  final String id;
  final String label;
  final IconData icon;
  final DesktopSettingsNavGroup group;
  final List<DesktopSettingGroupData> groups;

  /// The title over the content; defaults to [label].
  final String? heading;

  /// Drawn above the first group (the profile card on the Business pane).
  final WidgetBuilder? leading;
  final VoidCallback? onOpen;

  bool get isLink => onOpen != null;
}

/// Settings on a computer: a header, a 224px navigation on the left and one
/// pane of grouped setting rows (at most 760px wide) on the right. Changes
/// apply as they are made and the pane title says "Saved".
class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage({
    super.key,
    required this.panes,
    this.initialPaneId,
    this.title = 'Settings',
    this.subtitle = 'Manage your shop, this computer and your account',
  });

  final List<DesktopSettingsPaneData> panes;
  final String? initialPaneId;
  final String title;
  final String? subtitle;

  static const double navWidth = 224;
  static const double contentMaxWidth = 760;

  @override
  State<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends State<DesktopSettingsPage> {
  final _saved = DesktopSavedController();
  final _search = TextEditingController();
  final _contentScroll = ScrollController();
  final _navFocus = FocusNode(debugLabel: 'SettingsNav', skipTraversal: true);
  String? _selectedId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedId = _firstSelectable(widget.initialPaneId);
  }

  @override
  void dispose() {
    _saved.dispose();
    _search.dispose();
    _contentScroll.dispose();
    _navFocus.dispose();
    super.dispose();
  }

  String? _firstSelectable(String? wanted) {
    final selectable = widget.panes.where((p) => !p.isLink).toList();
    if (selectable.isEmpty) return null;
    if (wanted != null && selectable.any((p) => p.id == wanted)) return wanted;
    return selectable.first.id;
  }

  DesktopSettingsPaneData? get _selected {
    for (final pane in widget.panes) {
      if (pane.id == _selectedId) return pane;
    }
    final fallback = _firstSelectable(null);
    for (final pane in widget.panes) {
      if (pane.id == fallback) return pane;
    }
    return null;
  }

  void _select(DesktopSettingsPaneData pane) {
    _navFocus.requestFocus();
    if (pane.isLink) {
      pane.onOpen!();
      return;
    }
    setState(() {
      _selectedId = pane.id;
      _query = '';
      _search.clear();
    });
    if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
  }

  /// Arrow keys in the navigation move the selection, as in a list box.
  KeyEventResult _onNavKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final step = key == LogicalKeyboardKey.arrowDown
        ? 1
        : key == LogicalKeyboardKey.arrowUp
            ? -1
            : 0;
    if (step == 0) return KeyEventResult.ignored;
    final selectable = widget.panes.where((p) => !p.isLink).toList();
    final index = selectable.indexWhere((p) => p.id == _selectedId);
    final next = (index + step).clamp(0, selectable.length - 1);
    if (next != index) _select(selectable[next]);
    return KeyEventResult.handled;
  }

  bool _shortWindow(BuildContext context) =>
      MediaQuery.sizeOf(context).height < 640;

  List<String> get _terms => _query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final selected = _selected;
    final searching = _terms.isNotEmpty;

    return DesktopSavedScope(
      controller: _saved,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // On a short window (a laptop at 125%) the subtitle goes, so the
          // list of settings keeps the room.
          Builder(
            builder: (context) => DesktopPageHeader(
              title: widget.title,
              subtitle: _shortWindow(context) ? null : widget.subtitle,
              padding: const EdgeInsets.fromLTRB(
                DesktopTokens.gutter,
                14,
                DesktopTokens.gutter,
                10,
              ),
            ),
          ),
          Divider(height: 1, color: p.border),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: DesktopSettingsPage.navWidth,
                  child: _SubNav(
                    panes: widget.panes,
                    selectedId: searching ? null : selected?.id,
                    controller: _search,
                    onSearch: (v) => setState(() => _query = v),
                    onSelect: _select,
                    onKey: _onNavKey,
                    focusNode: _navFocus,
                  ),
                ),
                VerticalDivider(width: 1, color: p.border),
                Expanded(
                  child: Scrollbar(
                    controller: _contentScroll,
                    child: SingleChildScrollView(
                      controller: _contentScroll,
                      padding: const EdgeInsets.only(top: 20, bottom: 40),
                      child: DesktopContent(
                        maxWidth: DesktopSettingsPage.contentMaxWidth +
                            DesktopTokens.gutter * 2,
                        child: searching
                            ? _SearchResults(
                                panes: widget.panes,
                                terms: _terms,
                                saved: _saved,
                              )
                            : selected == null
                                ? const SizedBox.shrink()
                                : _PaneView(pane: selected, saved: _saved),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubNav extends StatelessWidget {
  const _SubNav({
    required this.panes,
    required this.selectedId,
    required this.controller,
    required this.onSearch,
    required this.onSelect,
    required this.onKey,
    required this.focusNode,
  });

  final FocusNode focusNode;
  final List<DesktopSettingsPaneData> panes;
  final String? selectedId;
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final ValueChanged<DesktopSettingsPaneData> onSelect;
  final KeyEventResult Function(KeyEvent event) onKey;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
      children: [
        DesktopSearchField(
          key: const ValueKey('desktop-settings-search'),
          controller: controller,
          hint: 'Find a setting',
          onChanged: onSearch,
        ),
        // Arrow keys move the selection while a tile has focus. The search box
        // sits outside so it keeps its own caret keys.
        Focus(
          focusNode: focusNode,
          onKeyEvent: (_, event) => onKey(event),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final group in DesktopSettingsNavGroup.values)
                if (panes.any((pane) => pane.group == group)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
                    child: Text(
                      group.label,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final pane in panes.where((pane) => pane.group == group))
                    _NavTile(
                      pane: pane,
                      selected: pane.id == selectedId,
                      onTap: () => onSelect(pane),
                    ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.pane,
    required this.selected,
    required this.onTap,
  });

  final DesktopSettingsPaneData pane;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final iconColor =
        selected ? (p.dark ? DesignColors.accent : p.accent) : p.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: pane.label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: selected ? p.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
          child: InkWell(
            key: ValueKey('desktop-settings-nav-${pane.id}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
            hoverColor: p.hover,
            child: SizedBox(
              height: 36,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(pane.icon, size: 19, color: iconColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        pane.label,
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
                    if (pane.isLink)
                      Icon(
                        Icons.north_east_rounded,
                        size: 15,
                        color: p.textFaint,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneTitle extends StatelessWidget {
  const _PaneTitle({required this.title, required this.saved});

  final String title;
  final DesktopSavedController saved;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.sora(
                color: p.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          DesktopSavedIndicator(controller: saved),
        ],
      ),
    );
  }
}

class _PaneView extends StatelessWidget {
  const _PaneView({required this.pane, required this.saved});

  final DesktopSettingsPaneData pane;
  final DesktopSavedController saved;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey('desktop-settings-pane-${pane.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaneTitle(title: pane.heading ?? pane.label, saved: saved),
        if (pane.leading != null) pane.leading!(context),
        for (final group in pane.groups)
          DesktopSettingGroup(
            title: group.title,
            note: group.note,
            children: [for (final item in group.items) item.builder(context)],
          ),
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.panes,
    required this.terms,
    required this.saved,
  });

  final List<DesktopSettingsPaneData> panes;
  final List<String> terms;
  final DesktopSavedController saved;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final groups = <Widget>[];
    for (final pane in panes) {
      if (pane.isLink) continue;
      final hits = <DesktopSettingItem>[
        for (final group in pane.groups)
          for (final item in group.items)
            if (item.matches(pane.label, terms)) item,
      ];
      if (hits.isEmpty) continue;
      groups.add(
        DesktopSettingGroup(
          title: pane.label,
          children: [for (final item in hits) item.builder(context)],
        ),
      );
    }
    return Column(
      key: const ValueKey('desktop-settings-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaneTitle(title: 'Search results', saved: saved),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.search_off_rounded, size: 36, color: p.textFaint),
                const SizedBox(height: 10),
                Text(
                  'No settings found',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try a different word, like "printer" or "PIN".',
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        else
          ...groups,
      ],
    );
  }
}
