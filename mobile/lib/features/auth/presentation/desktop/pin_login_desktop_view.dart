import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/theme/design_system.dart';
import '../widgets/sign_in_kit.dart';
import 'auth_desktop_kit.dart';

/// Someone who can sign in on this computer.
class PinDesktopPerson {
  const PinDesktopPerson({
    required this.id,
    required this.name,
    required this.role,
  });

  final String id;
  final String name;
  final String role;
}

/// PIN sign-in for a computer window. The keypad works with the mouse and
/// with the keyboard: digits, Backspace to delete, Delete to clear, Enter to
/// sign in.
class PinLoginDesktopView extends StatelessWidget {
  const PinLoginDesktopView({
    super.key,
    required this.companyName,
    required this.branchName,
    required this.people,
    required this.picking,
    required this.pinLength,
    required this.filled,
    required this.showError,
    required this.errorMessage,
    required this.loading,
    required this.keypadEnabled,
    required this.hint,
    required this.actionLabel,
    required this.canSubmit,
    required this.localWorkspace,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
    required this.onChoosePerson,
    this.selected,
    this.logoUrl,
    this.onBiometric,
    this.onUsePassword,
    this.appVersion,
  });

  final String companyName;
  final String branchName;
  final String? logoUrl;
  final List<PinDesktopPerson> people;

  /// True while the person has to choose their name before the keypad.
  final bool picking;
  final PinDesktopPerson? selected;

  /// Dots shown: the PIN's length, or 4 growing to 6 when it is not known.
  final int pinLength;
  final int filled;
  final bool showError;
  final String errorMessage;
  final bool loading;
  final bool keypadEnabled;
  final String hint;
  final String actionLabel;
  final bool canSubmit;

  /// The workspace lives on this computer, so it works offline.
  final bool localWorkspace;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;
  final ValueChanged<PinDesktopPerson?> onChoosePerson;
  final VoidCallback? onBiometric;

  /// Null on a workspace that has no password to fall back to.
  final VoidCallback? onUsePassword;
  final String? appVersion;

  static final Map<LogicalKeyboardKey, String> _digitKeys = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (picking) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final digit = _digitKeys[key];
    if (digit != null) {
      if (keypadEnabled) onDigit(digit);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (keypadEnabled) onBackspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      if (keypadEnabled) onClear();
      return KeyEventResult.handled;
    }
    // Enter belongs to a focused button; only take it when nothing else is
    // focused so Tab then Enter still presses the link or button.
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        node.hasPrimaryFocus &&
        event is KeyDownEvent) {
      if (!loading) onSubmit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final back =
        selected != null ? () => onChoosePerson(null) : onUsePassword;
    return AuthDesktopShell(
      onEscape: back,
      formMaxWidth: picking ? AuthDesktop.formWidth : 320,
      brand: AuthBrandPanel(
        facts: localWorkspace
            ? const [
                'Works offline on this computer',
                'Your sales and stock stay on this computer',
              ]
            : const [],
        footer: appVersion,
      ),
      header: selected != null
          ? AuthBackLink(label: 'Not you?', onPressed: () => onChoosePerson(null))
          : null,
      child: Focus(
        autofocus: !picking,
        onKeyEvent: _onKey,
        child: picking ? _buildPicker(context) : _buildKeypad(context),
      ),
    );
  }

  Widget _buildPicker(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            BusinessMark(name: companyName, logoUrl: logoUrl, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    companyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    branchName.isNotEmpty
                        ? '$branchName · ${people.length} people on this computer'
                        : '${people.length} people on this computer',
                    style: TextStyle(color: p.textMuted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const AuthHeading(
          title: 'Who is at the till?',
          subtitle: 'Choose your name, then enter your PIN.',
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: p.panelAlt,
            borderRadius: BorderRadius.circular(DesktopTokens.controlRadius + 2),
            border: Border.all(color: p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < people.length; i++) ...[
                if (i > 0) Divider(height: 1, color: p.border),
                _PersonRow(
                  person: people[i],
                  autofocus: i == 0,
                  onTap: () => onChoosePerson(people[i]),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (onUsePassword != null)
          Center(
            child: AuthTextLink(
              label: 'Use password instead',
              onPressed: onUsePassword,
              hint: 'Esc',
            ),
          ),
        const Center(child: AuthLegalLine(action: 'signing in')),
      ],
    );
  }

  Widget _buildKeypad(BuildContext context) {
    final p = DesktopPalette.of(context);
    final person = selected;
    final errorInk = context.readable(DesignColors.error);
    final title = person?.name ?? companyName;
    final subtitle = person != null && person.role.isNotEmpty
        ? '${person.role} · enter your PIN'
        : hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: person != null
              ? _PersonAvatar(name: person.name, size: 52, selected: true)
              : BusinessMark(name: companyName, logoUrl: logoUrl, size: 52),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: DesignType.display.copyWith(
            color: p.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: p.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 20),
        PinDots(length: pinLength, filled: filled, error: showError),
        SizedBox(
          height: 38,
          child: Center(
            child: showError
                ? Semantics(
                    liveRegion: true,
                    child: Text(
                      errorMessage.isNotEmpty
                          ? errorMessage
                          : 'Invalid PIN. Try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: errorInk,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: _Keypad(
              enabled: keypadEnabled,
              onDigit: onDigit,
              onBackspace: onBackspace,
              onClear: onClear,
            ),
          ),
        ),
        const SizedBox(height: 14),
        AuthPrimaryButton(
          label: actionLabel,
          loading: loading,
          onPressed: canSubmit ? onSubmit : null,
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            if (onBiometric != null)
              AuthTextLink(
                label: 'Use biometric unlock',
                onPressed: loading ? null : onBiometric,
              ),
            if (onUsePassword != null)
              AuthTextLink(
                label: 'Use password instead',
                onPressed: onUsePassword,
                hint: person == null ? 'Esc' : null,
              ),
          ],
        ),
        const Center(child: AuthLegalLine(action: 'signing in')),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    Widget digit(String d) => _PinKey(
          semantics: 'PIN digit $d',
          onTap: enabled ? () => onDigit(d) : null,
          child: Text(d, style: DesignType.numeric(fontSize: 19, color: p.text)),
        );
    Widget row(List<Widget> keys) => Row(
          children: [
            for (var i = 0; i < keys.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: keys[i]),
            ],
          ],
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([digit('1'), digit('2'), digit('3')]),
        const SizedBox(height: 8),
        row([digit('4'), digit('5'), digit('6')]),
        const SizedBox(height: 8),
        row([digit('7'), digit('8'), digit('9')]),
        const SizedBox(height: 8),
        row([
          _PinKey(
            semantics: 'Clear PIN',
            quiet: true,
            onTap: enabled ? onClear : null,
            child: Text(
              'Clear',
              style: TextStyle(
                color: p.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          digit('0'),
          _PinKey(
            semantics: 'Delete digit',
            quiet: true,
            onTap: enabled ? onBackspace : null,
            child: Icon(Icons.backspace_outlined, color: p.textMuted, size: 20),
          ),
        ]),
      ],
    );
  }
}

/// A keypad key for the mouse. It is not a Tab stop: at a keyboard the digits
/// are typed, and Tab goes on to Sign in.
class _PinKey extends StatelessWidget {
  const _PinKey({
    required this.semantics,
    required this.onTap,
    required this.child,
    this.quiet = false,
  });

  final String semantics;
  final VoidCallback? onTap;
  final Widget child;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final radius = BorderRadius.circular(DesktopTokens.controlRadius);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: quiet ? Colors.transparent : p.panelAlt,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: quiet ? Colors.transparent : p.borderStrong),
        ),
        child: InkWell(
          onTap: onTap,
          canRequestFocus: false,
          borderRadius: radius,
          mouseCursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: SizedBox(height: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
    required this.name,
    this.size = 36,
    this.selected = false,
  });

  final String name;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? DesignColors.accent : p.border,
      ),
      child: Text(
        initialsFor(name),
        style: DesignType.display.copyWith(
          color: selected ? SignInPalette.onAccent : p.text,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.onTap,
    this.autofocus = false,
  });

  final PinDesktopPerson person;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Semantics(
      button: true,
      label: '${person.name}, ${person.role}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        autofocus: autofocus,
        mouseCursor: SystemMouseCursors.click,
        focusColor: p.selected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _PersonAvatar(name: person.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (person.role.isNotEmpty)
                      Text(
                        person.role,
                        style: TextStyle(color: p.textMuted, fontSize: 12.5),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
