import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';

/// Something the command palette can run: open a page, start a task.
@immutable
class DesktopCommand {
  const DesktopCommand({
    required this.label,
    required this.icon,
    required this.run,
    this.section = '',
    this.keywords = const [],
    this.shortcut,
  });

  final String label;
  final IconData icon;
  final VoidCallback run;

  /// Shown on the right ("Stock", "Action").
  final String section;
  final List<String> keywords;

  /// Shown as a key hint when the command has one ("Ctrl B").
  final String? shortcut;

  /// 0 = no match, higher = better.
  int score(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 1;
    final name = label.toLowerCase();
    if (name == q) return 100;
    if (name.startsWith(q)) return 80;
    if (name.split(' ').any((w) => w.startsWith(q))) return 60;
    if (name.contains(q)) return 40;
    if (keywords.any((k) => k.toLowerCase().startsWith(q))) return 30;
    if (keywords.any((k) => k.toLowerCase().contains(q))) return 15;
    if (section.toLowerCase().contains(q)) return 5;
    return 0;
  }
}

/// Ctrl+K: type a few letters, press Enter, be there. Replaces the phone's
/// "More" sheet as the way to reach any place in the app.
Future<void> showDesktopCommandPalette(
  BuildContext context, {
  required List<DesktopCommand> commands,
}) async {
  final picked = await showDialog<DesktopCommand>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.36),
    builder: (_) => _CommandPalette(commands: commands),
  );
  // Run after the dialog is gone so a command that opens another dialog or
  // changes the route does not race the pop animation.
  picked?.run();
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.commands});

  final List<DesktopCommand> commands;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _selected = 0;

  List<DesktopCommand> get _results {
    final scored = <(DesktopCommand, int)>[
      for (final c in widget.commands) (c, c.score(_field.text)),
    ].where((e) => e.$2 > 0).toList();
    if (_field.text.trim().isNotEmpty) {
      scored.sort((a, b) => b.$2.compareTo(a.$2));
    }
    return [for (final e in scored) e.$1];
  }

  @override
  void initState() {
    super.initState();
    _field.addListener(() => setState(() => _selected = 0));
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta) % count);
    final target = _selected * _rowHeight;
    if (_scroll.hasClients) {
      final viewport = _scroll.position.viewportDimension;
      if (target < _scroll.offset) {
        _scroll.jumpTo(target);
      } else if (target + _rowHeight > _scroll.offset + viewport) {
        _scroll.jumpTo(target + _rowHeight - viewport);
      }
    }
  }

  static const double _rowHeight = 44;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final results = _results;
    if (_selected >= results.length) _selected = 0;

    KeyEventResult onKey(FocusNode node, KeyEvent event) {
      if (event is KeyUpEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _move(1, results.length);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _move(results.length - 1, results.length);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (results.isNotEmpty) Navigator.of(context).pop(results[_selected]);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return Align(
      alignment: const Alignment(0, -0.55),
      child: Material(
        color: p.panel,
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesktopTokens.panelRadius),
          side: BorderSide(color: p.borderStrong),
        ),
        child: SizedBox(
          width: 580,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(
                onKeyEvent: onKey,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 20, color: p.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _field,
                          focusNode: _focus,
                          autofocus: true,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          cursorColor: p.accent,
                          decoration: InputDecoration(
                            hintText: 'Search pages and actions',
                            hintStyle: GoogleFonts.plusJakartaSans(
                              color: p.textFaint,
                              fontSize: 15,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      _KeyCap(label: 'Esc', palette: p),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: p.border),
              if (results.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    'Nothing matches “${_field.text.trim()}”.',
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 13.5,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _rowHeight * 8),
                  child: ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.zero,
                    itemExtent: _rowHeight,
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final command = results[i];
                      final selected = i == _selected;
                      return MouseRegion(
                        onHover: (_) {
                          if (_selected != i) setState(() => _selected = i);
                        },
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(command),
                          child: Container(
                            color: selected ? p.selected : Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Icon(
                                  command.icon,
                                  size: 19,
                                  color: selected ? p.accent : p.textMuted,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    command.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: p.text,
                                      fontSize: 14,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (command.shortcut != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: _KeyCap(
                                      label: command.shortcut!,
                                      palette: p,
                                    ),
                                  ),
                                if (command.section.isNotEmpty)
                                  Text(
                                    command.section,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: p.textFaint,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              Divider(height: 1, color: p.border),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Row(
                  children: [
                    _Hint(keys: '↑ ↓', text: 'to move', palette: p),
                    const SizedBox(width: 16),
                    _Hint(keys: 'Enter', text: 'to open', palette: p),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.keys, required this.text, required this.palette});

  final String keys;
  final String text;
  final DesktopPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _KeyCap(label: keys, palette: palette),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            color: palette.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// A small key label like Ctrl or Esc.
class DesktopKeyCap extends StatelessWidget {
  const DesktopKeyCap({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) =>
      _KeyCap(label: label, palette: DesktopPalette.of(context));
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label, required this.palette});

  final String label;
  final DesktopPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.panelAlt,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}
