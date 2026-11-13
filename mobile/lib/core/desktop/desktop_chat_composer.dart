import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_system.dart';
import 'desktop_layout.dart';

/// The message box docked at the bottom of a desktop conversation (Axon AI,
/// trade partners).
///
/// Enter sends, Shift+Enter starts a new line, and the keys are said out loud
/// in the hint line under the box. The box grows to six lines and then scrolls.
/// It never sends an empty message and ignores Enter while [busy] is true.
class DesktopChatComposer extends StatelessWidget {
  const DesktopChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    this.focusNode,
    this.hint = 'Write a message',
    this.enabled = true,
    this.busy = false,
    this.leading = const [],
    this.trailing = const [],
    this.onChanged,
    this.onEscape,
    this.maxLength,
    this.footnote,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final FocusNode? focusNode;
  final String hint;

  /// False greys the field out (a send is in flight and typing would be lost).
  final bool enabled;

  /// A send is in flight: the button shows progress and Enter does nothing.
  final bool busy;

  /// Icon buttons before the field (attach, add a photo).
  final List<Widget> leading;

  /// Icon buttons between the field and the send button (voice).
  final List<Widget> trailing;
  final ValueChanged<String>? onChanged;

  /// Esc inside the box. Return value ignored; the box does not clear itself.
  final VoidCallback? onEscape;
  final int? maxLength;

  /// Replaces the default "Enter to send" hint line.
  final String? footnote;

  bool get _canSend => enabled && !busy && controller.text.trim().isNotEmpty;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      if (_canSend) onSend();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && onEscape != null) {
      onEscape!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final radius = BorderRadius.circular(12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: p.dark ? p.panelAlt : Colors.white,
            borderRadius: radius,
            border: Border.all(color: p.borderStrong),
          ),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ...leading,
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  onKeyEvent: _onKey,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 6,
                    maxLength: maxLength,
                    onChanged: onChanged,
                    cursorColor: p.accent,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        null,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: hint,
                      hintStyle: GoogleFonts.plusJakartaSans(
                        color: p.textFaint,
                        fontSize: 14,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                    ),
                  ),
                ),
              ),
              ...trailing,
              const SizedBox(width: 2),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => _SendButton(
                  palette: p,
                  busy: busy,
                  canSend: _canSend,
                  onSend: onSend,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            footnote ?? 'Enter to send, Shift+Enter for a new line',
            style: GoogleFonts.plusJakartaSans(
              color: p.textFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.palette,
    required this.busy,
    required this.canSend,
    required this.onSend,
  });

  final DesktopPalette palette;
  final bool busy;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Tooltip(
      message: 'Send (Enter)',
      child: Material(
        color: canSend ? DesignColors.accent : p.hover,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: canSend ? onSend : null,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: p.textMuted,
                      ),
                    )
                  : Icon(
                      Icons.arrow_upward_rounded,
                      size: 19,
                      color: canSend ? DesignColors.textPrimary : p.textFaint,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
