import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import 'desktop_sub_page.dart';

/// One help topic: a title and its steps, as plain values.
class DesktopGuideTopic {
  const DesktopGuideTopic({
    required this.icon,
    required this.title,
    required this.steps,
  });

  final IconData icon;
  final String title;
  final List<String> steps;
}

/// The user guide on a computer: topics down the left, the chosen topic's
/// steps on the right. Up and Down move between topics.
class DesktopUserGuideView extends StatefulWidget {
  const DesktopUserGuideView({super.key, required this.topics, this.onBack});

  final List<DesktopGuideTopic> topics;
  final VoidCallback? onBack;

  @override
  State<DesktopUserGuideView> createState() => _DesktopUserGuideViewState();
}

class _DesktopUserGuideViewState extends State<DesktopUserGuideView> {
  int _index = 0;
  final _focus = FocusNode(debugLabel: 'guide-topics');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final next = (_index + delta).clamp(0, widget.topics.length - 1);
    if (next != _index) setState(() => _index = next);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final topics = widget.topics;
    return DesktopSubPage(
      title: 'User guide',
      subtitle: 'Short how-tos for the places you use most',
      maxWidth: 980,
      onBack: widget.onBack,
      child: topics.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: DesktopListDetail(
                    listWidth: 260,
                    list: Focus(
                      focusNode: _focus,
                      autofocus: true,
                      onKeyEvent: _onKey,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (var i = 0; i < topics.length; i++)
                            _TopicTile(
                              topic: topics[i],
                              selected: i == _index,
                              onTap: () {
                                _focus.requestFocus();
                                setState(() => _index = i);
                              },
                            ),
                        ],
                      ),
                    ),
                    detail: _TopicDetail(topic: topics[_index]),
                  ),
                ),
              ),
            ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.topic,
    required this.selected,
    required this.onTap,
  });

  final DesktopGuideTopic topic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Material(
      color: selected
          ? p.accent.withValues(alpha: p.dark ? 0.16 : 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(topic.icon,
                  size: 19, color: selected ? p.accent : p.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicDetail extends StatelessWidget {
  const _TopicDetail({required this.topic});
  final DesktopGuideTopic topic;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return SizedBox.expand(
        child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            topic.title,
            style: GoogleFonts.sora(
              color: p.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < topic.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.jetBrainsMono(
                        color: p.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      topic.steps[i],
                      style: GoogleFonts.plusJakartaSans(
                        color: p.text,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ));
  }
}
