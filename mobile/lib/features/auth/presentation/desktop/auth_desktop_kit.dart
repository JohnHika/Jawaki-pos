import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_theme.dart';
import '../../../../core/theme/design_system.dart';
import '../widgets/sign_in_kit.dart';

/// Sizes shared by the computer versions of the pre-login screens.
class AuthDesktop {
  const AuthDesktop._();

  /// Share of the window taken by the brand panel on the left.
  static const double brandFraction = 0.45;

  /// Sign-in forms.
  static const double formWidth = 400;

  /// Wizards (shop setup, activation).
  static const double wizardWidth = 480;

  /// The one sentence about what the app does, shown on every brand panel.
  static const String tagline = 'Run your counter, stock and daily sales.';
}

/// The split window for sign-in and set-up on a computer: a calm brand panel
/// on the left, the form in a centred column on the right.
///
/// These screens sit outside the desktop shell, so this widget applies the
/// desktop theme itself. [onEscape] is bound to the Escape key for the whole
/// page, [actions] stays pinned under a scrolling form (wizard buttons).
class AuthDesktopShell extends StatelessWidget {
  const AuthDesktopShell({
    super.key,
    required this.brand,
    required this.child,
    this.formMaxWidth = AuthDesktop.formWidth,
    this.header,
    this.actions,
    this.onEscape,
    this.scrollController,
  });

  final Widget brand;
  final Widget child;
  final double formMaxWidth;

  /// Quiet row above the form, such as the Back link.
  final Widget? header;

  /// Buttons pinned to the bottom of the right pane.
  final Widget? actions;
  final VoidCallback? onEscape;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: DesktopTheme.of(Theme.of(context)),
      child: Builder(builder: (context) {
        final p = DesktopPalette.of(context);
        return CallbackShortcuts(
          bindings: {
            if (onEscape != null)
              const SingleActivator(LogicalKeyboardKey.escape): onEscape!,
          },
          child: FocusScope(
            autofocus: true,
            child: Scaffold(
              backgroundColor: p.panel,
              body: LayoutBuilder(builder: (context, c) {
                final brandWidth =
                    (c.maxWidth * AuthDesktop.brandFraction).floorToDouble();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: brandWidth,
                      child: ColoredBox(color: p.frame, child: brand),
                    ),
                    VerticalDivider(width: 1, thickness: 1, color: p.border),
                    Expanded(
                      child: ColoredBox(
                        color: p.panel,
                        child: _FormPane(
                          formMaxWidth: formMaxWidth,
                          header: header,
                          actions: actions,
                          scrollController: scrollController,
                          child: child,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        );
      }),
    );
  }
}

class _FormPane extends StatelessWidget {
  const _FormPane({
    required this.child,
    required this.formMaxWidth,
    this.header,
    this.actions,
    this.scrollController,
  });

  final Widget child;
  final double formMaxWidth;
  final Widget? header;
  final Widget? actions;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Align(alignment: Alignment.centerLeft, child: header),
          ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            const vertical = 16.0;
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: vertical,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (c.maxHeight - vertical * 2).clamp(0.0, 9999.0),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: formMaxWidth),
                    child: child,
                  ),
                ),
              ),
            );
          }),
        ),
        if (actions != null) ...[
          Divider(height: 1, color: p.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: formMaxWidth),
                child: actions,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The left panel: the app mark, one calm sentence, optional wizard steps and
/// plain facts. Flat warm ground, no illustration.
class AuthBrandPanel extends StatelessWidget {
  const AuthBrandPanel({
    super.key,
    this.statement = AuthDesktop.tagline,
    this.facts = const [],
    this.steps,
    this.currentStep = 0,
    this.allStepsDone = false,
    this.onStepTap,
    this.footer = 'Counterbase by Arche Axon',
  });

  final String statement;

  /// True things about this kind of workspace, such as "Works offline".
  final List<String> facts;

  /// Wizard step names. When given they are listed under the statement.
  final List<String>? steps;
  final int currentStep;
  final bool allStepsDone;
  final ValueChanged<int>? onStepTap;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return LayoutBuilder(builder: (context, c) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(48, 32, 40, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (c.maxHeight - 60).clamp(0.0, 9999.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _BrandMark(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          statement,
                          style: DesignType.display.copyWith(
                            color: p.text,
                            fontSize: 26,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      if (steps != null) ...[
                        const SizedBox(height: 28),
                        AuthStepList(
                          labels: steps!,
                          current: currentStep,
                          allDone: allStepsDone,
                          onTap: onStepTap,
                        ),
                      ],
                      if (facts.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        for (final fact in facts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(Icons.check_rounded,
                                      size: 16, color: p.textMuted),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    fact,
                                    style: TextStyle(
                                      color: p.textMuted,
                                      fontSize: 13.5,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 32,
                child: footer == null
                    ? null
                    : Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          footer!,
                          style: TextStyle(color: p.textFaint, fontSize: 12),
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AxonLogoTitle(logoSize: 36),
        const SizedBox(width: 12),
        Text(
          'Counterbase',
          style: DesignType.display.copyWith(
            color: p.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

/// Wizard progress as a list: done steps are ticked, the current one is
/// orange, later ones are outlined. Done steps can be clicked to go back.
class AuthStepList extends StatelessWidget {
  const AuthStepList({
    super.key,
    required this.labels,
    required this.current,
    this.allDone = false,
    this.onTap,
  });

  final List<String> labels;
  final int current;
  final bool allDone;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < labels.length; i++)
          _StepRow(
            index: i,
            label: labels[i],
            total: labels.length,
            done: allDone || i < current,
            current: !allDone && i == current,
            last: i == labels.length - 1,
            palette: p,
            onTap: (allDone || i < current) && onTap != null
                ? () => onTap!(i)
                : null,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.label,
    required this.total,
    required this.done,
    required this.current,
    required this.last,
    required this.palette,
    this.onTap,
  });

  final int index;
  final String label;
  final int total;
  final bool done;
  final bool current;
  final bool last;
  final DesktopPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final circle = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: current
            ? DesignColors.accent
            : done
                ? p.text
                : Colors.transparent,
        border: current || done
            ? null
            : Border.all(color: p.borderStrong, width: 1.5),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 15, color: p.frame)
          : Text(
              '${index + 1}',
              style: TextStyle(
                color: current ? SignInPalette.onAccent : p.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            circle,
            if (!last)
              Container(width: 1.5, height: 20, color: p.borderStrong),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              label,
              style: TextStyle(
                color: current || done ? p.text : p.textMuted,
                fontSize: 14.5,
                fontWeight: current ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
    return Semantics(
      label: 'Step ${index + 1} of $total, $label, '
          '${done ? 'done' : current ? 'current' : 'to do'}',
      excludeSemantics: true,
      button: onTap != null,
      child: onTap == null
          ? Padding(padding: const EdgeInsets.only(bottom: 4), child: row)
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              mouseCursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: row,
              ),
            ),
    );
  }
}

/// Heading and supporting line of a form column.
class AuthHeading extends StatelessWidget {
  const AuthHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: DesignType.display.copyWith(
              color: p.text,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(color: p.textMuted, fontSize: 13.5, height: 1.45),
          ),
        ],
      ],
    );
  }
}

/// A labelled text field with a clear focus ring. The label sits above the
/// field so a list of fields can be scanned top to bottom.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.focusNode,
    this.hint,
    this.helper,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.obscureText = false,
    this.suffix,
    this.inputFormatters,
    this.autofocus = false,
    this.autocorrect = false,
    this.enabled = true,
    this.labelTrailing,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController controller;
  final Key? fieldKey;
  final FocusNode? focusNode;
  final String? hint;
  final String? helper;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final bool autocorrect;
  final bool enabled;
  final Widget? labelTrailing;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final errorInk = context.readable(DesignColors.error);
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
          borderSide: BorderSide(color: color, width: width),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: p.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (labelTrailing != null) labelTrailing!,
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          enabled: enabled,
          obscureText: obscureText,
          autocorrect: autocorrect,
          enableSuggestions: !obscureText && autocorrect,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          cursorColor: p.accent,
          style: TextStyle(
            color: p.text,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: p.panelAlt,
            hintText: hint,
            hintStyle: TextStyle(color: p.textFaint, fontSize: 14),
            helperText: helper,
            helperMaxLines: 2,
            helperStyle: TextStyle(color: p.textFaint, fontSize: 12),
            errorMaxLines: 3,
            errorStyle: TextStyle(color: errorInk, fontSize: 12, height: 1.3),
            suffixIcon: suffix,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
            border: border(p.borderStrong),
            enabledBorder: border(p.borderStrong),
            disabledBorder: border(p.border),
            focusedBorder: border(p.accent, 2),
            errorBorder: border(errorInk),
            focusedErrorBorder: border(errorInk, 2),
          ),
        ),
      ],
    );
  }
}

/// Password field with a keyboard-reachable show/hide button and a Caps Lock
/// hint beside the label.
class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.obscure,
    required this.onToggle,
    this.label = 'Password',
    this.hint,
    this.fieldKey,
    this.validator,
    this.onSubmitted,
    this.textInputAction,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscure;
  final VoidCallback onToggle;
  final String label;
  final String? hint;
  final Key? fieldKey;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool autofocus;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  final ValueNotifier<bool> _capsOn = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_sync);
    HardwareKeyboard.instance.addHandler(_onKey);
    _sync();
  }

  @override
  void didUpdateWidget(AuthPasswordField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_sync);
      widget.focusNode.addListener(_sync);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_sync);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _capsOn.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _sync();
    return false;
  }

  void _sync() {
    _capsOn.value = widget.focusNode.hasFocus &&
        HardwareKeyboard.instance.lockModesEnabled
            .contains(KeyboardLockMode.capsLock);
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final warn = context.readable(DesignColors.warning);
    return AuthField(
      label: widget.label,
      fieldKey: widget.fieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      hint: widget.hint,
      obscureText: widget.obscure,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      onSubmitted: widget.onSubmitted,
      labelTrailing: ValueListenableBuilder<bool>(
        valueListenable: _capsOn,
        builder: (context, on, _) => on
            ? Semantics(
                liveRegion: true,
                label: 'Caps Lock is on',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard_capslock_rounded,
                        size: 15, color: warn),
                    const SizedBox(width: 4),
                    Text(
                      'Caps Lock is on',
                      style: TextStyle(
                        color: warn,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
      suffix: IconButton(
        tooltip: widget.obscure ? 'Show password' : 'Hide password',
        onPressed: widget.onToggle,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: Icon(
          widget.obscure
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          size: 18,
          color: p.textMuted,
        ),
      ),
    );
  }
}

/// Filled orange action with dark ink. One per screen.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final enabled = onPressed != null && !loading;
    final style = FilledButton.styleFrom(
      backgroundColor: DesignColors.accent,
      foregroundColor: SignInPalette.onAccent,
      disabledBackgroundColor: loading ? DesignColors.accent : p.border,
      disabledForegroundColor: loading ? SignInPalette.onAccent : p.textFaint,
      minimumSize: const Size(64, 40),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
      ),
      textStyle: DesignType.body.copyWith(
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
      ),
    ).copyWith(
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(color: p.text, width: 2)
            : null,
      ),
    );
    final content = loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: SignInPalette.onAccent,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        autofocus: autofocus,
        focusNode: focusNode,
        style: style,
        child: content,
      ),
    );
  }
}

/// Outlined alternative action.
class AuthSecondaryButton extends StatelessWidget {
  const AuthSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final style = OutlinedButton.styleFrom(
      foregroundColor: p.text,
      minimumSize: const Size(64, 40),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      side: BorderSide(color: p.borderStrong),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
      ),
      textStyle: DesignType.body.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ).copyWith(
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(color: p.accent, width: 2)
            : BorderSide(color: p.borderStrong),
      ),
    );
    return OutlinedButton(
      onPressed: onPressed,
      autofocus: autofocus,
      style: style,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

/// A quiet text button: muted until hovered or focused.
class AuthTextLink extends StatelessWidget {
  const AuthTextLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.hint,
    this.strong = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Keyboard shortcut shown after the label, such as "Esc".
  final String? hint;

  /// Uses the full text colour instead of the muted one.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final base = strong ? p.text : p.textMuted;
    final style = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ).copyWith(
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return p.textFaint;
        return states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? p.text
            : base;
      }),
      textStyle: WidgetStateProperty.resolveWith(
        (states) => DesignType.body.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          decoration: states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? TextDecoration.underline
              : TextDecoration.none,
        ),
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(color: p.accent, width: 2)
            : null,
      ),
    );
    return TextButton(
      onPressed: onPressed,
      style: style,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16),
            const SizedBox(width: 6),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
          if (hint != null) ...[
            const SizedBox(width: 8),
            AuthKeyCap(label: hint!),
          ],
        ],
      ),
    );
  }
}

/// A small keyboard key label.
class AuthKeyCap extends StatelessWidget {
  const AuthKeyCap({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: p.panelAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: p.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: p.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}

/// "Back" in the corner of the form pane, with the Esc key it answers to.
class AuthBackLink extends StatelessWidget {
  const AuthBackLink({super.key, required this.onPressed, this.label = 'Back'});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => AuthTextLink(
        label: label,
        icon: Icons.arrow_back_rounded,
        hint: 'Esc',
        onPressed: onPressed,
      );
}

/// A checkbox with its label; clicking the label toggles it.
class AuthCheckRow extends StatelessWidget {
  const AuthCheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      canRequestFocus: false,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: DesignColors.accent,
              checkColor: SignInPalette.onAccent,
              side: BorderSide(color: p.borderStrong, width: 1.5),
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? DesignColors.accent.withValues(alpha: 0.28)
                    : states.contains(WidgetState.hovered)
                        ? p.hover
                        : null,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: p.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A message above the action it concerns: what happened, in plain words.
class AuthNotice extends StatelessWidget {
  const AuthNotice({
    super.key,
    required this.message,
    this.warning = false,
    this.onDismiss,
  });

  final String message;
  final bool warning;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final tone = warning ? DesignColors.warning : DesignColors.error;
    final ink = context.readable(tone);
    return Semantics(
      liveRegion: true,
      label: warning ? message : 'Error: $message',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: p.dark ? 0.10 : 0.08),
          borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
          border: Border.all(color: tone.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                warning
                    ? Icons.info_outline_rounded
                    : Icons.error_outline_rounded,
                size: 18,
                color: ink,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1, right: 4),
                child: Text(
                  message,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 16, color: p.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// "By signing in you accept the Terms of Service and Privacy Notice."
class AuthLegalLine extends StatelessWidget {
  const AuthLegalLine({super.key, this.action = 'continuing'});

  final String action;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final text = TextStyle(color: p.textFaint, fontSize: 12, height: 1.4);
    Widget link(String label, String path) => TextButton(
          onPressed: () => context.push(path),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 24),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: p.textMuted,
            textStyle: DesignType.body.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? BorderSide(color: p.accent, width: 2)
                  : null,
            ),
          ),
          child: Text(label),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('By $action you accept the', style: text),
        link('Terms of Service', '/legal/terms'),
        Text('and', style: text),
        link('Privacy Notice', '/legal/privacy'),
      ],
    );
  }
}
