import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';

// Building blocks for the computer version of Settings: a setting row (title
// and helper on the left, the control on the right), a group of rows on one
// hairline panel, a switch, a segmented choice, and the small "Saved" note
// that confirms a change took effect.
//
// They take plain data and callbacks so a test can feed them directly.

/// Tells the Settings page that a change was just applied, so it can show
/// "Saved" for a moment. Toggles call [DesktopSavedController.of] and notify.
class DesktopSavedController extends ChangeNotifier {
  Timer? _timer;
  bool _visible = false;

  /// True for about two seconds after [saved].
  bool get visible => _visible;

  void saved() {
    _visible = true;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2200), () {
      _visible = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The controller of the nearest Settings page, or null outside one.
  static DesktopSavedController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DesktopSavedScope>()?.controller;

  /// Says "Saved" on the nearest Settings page, when there is one.
  static void notify(BuildContext context) => maybeOf(context)?.saved();
}

class DesktopSavedScope extends InheritedWidget {
  const DesktopSavedScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final DesktopSavedController controller;

  @override
  bool updateShouldNotify(DesktopSavedScope oldWidget) =>
      oldWidget.controller != controller;
}

/// The tick and "Saved" at the right of the pane title. Takes no room when
/// hidden, so the title row does not jump.
class DesktopSavedIndicator extends StatelessWidget {
  const DesktopSavedIndicator({super.key, required this.controller});

  final DesktopSavedController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AnimatedOpacity(
        opacity: controller.visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: Semantics(
          liveRegion: true,
          label: controller.visible ? 'Saved' : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: p.dark ? DesignColors.success : const Color(0xFF15803D),
              ),
              const SizedBox(width: 6),
              Text(
                'Saved',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One setting: an optional icon, the title and a line of helper text on the
/// left, and the control on the right. A row with [onTap] and no [trailing]
/// is a link and shows a chevron.
class DesktopSettingRow extends StatelessWidget {
  const DesktopSettingRow({
    super.key,
    required this.title,
    this.helper,
    this.icon,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
    this.helperMaxLines = 3,
  });

  final String title;
  final String? helper;
  final IconData? icon;

  /// The control (switch, segmented choice, button, value) at the right.
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;
  final int helperMaxLines;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final titleColor = destructive
        ? (p.dark ? DesignColors.error : const Color(0xFFB42318))
        : p.text;
    final isLink = onTap != null && trailing == null;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: p.textMuted),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  if (helper != null && helper!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      helper!,
                      maxLines: helperMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 16),
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 1,
                    child: trailing,
                  ),
                ),
              ),
            ] else if (isLink) ...[
              const SizedBox(width: 12),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.textFaint),
            ],
          ],
        ),
      ),
    );

    final row = Opacity(opacity: enabled ? 1 : 0.5, child: body);
    if (!isLink || !enabled) return row;
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          hoverColor: p.hover,
          child: row,
        ),
      ),
    );
  }
}

/// A titled group of rows on one hairline panel. The title sits above the
/// panel, like Windows Settings; rows are separated by hairlines.
class DesktopSettingGroup extends StatelessWidget {
  const DesktopSettingGroup({
    super.key,
    required this.children,
    this.title,
    this.note,
  });

  final String? title;

  /// A line of plain text under the panel (what the group does, a caveat).
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
              child: Text(
                title!,
                style: GoogleFonts.plusJakartaSans(
                  color: p.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          DesktopPanel(
            padding: EdgeInsets.zero,
            clip: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: p.border),
                  children[i],
                ],
              ],
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
              child: Text(
                note!,
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The label style of buttons inside settings rows: bundled font, one weight.
TextStyle desktopButtonText() => GoogleFonts.plusJakartaSans(
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );

/// A quiet outlined button: hairline border, text in the readable accent (the
/// deep orange on light, the bright orange on dark), or red when [destructive].
ButtonStyle desktopOutlinedStyle(
  BuildContext context, {
  bool destructive = false,
}) {
  final p = context.desktop;
  final color = destructive
      ? (p.dark ? DesignColors.error : const Color(0xFFB42318))
      : (p.dark ? DesignColors.accent : p.accent);
  return OutlinedButton.styleFrom(
    foregroundColor: color,
    side: BorderSide(
      color: destructive ? color.withValues(alpha: 0.5) : p.borderStrong,
    ),
    textStyle: desktopButtonText(),
  );
}

/// An on/off switch in the desktop palette: orange track, dark thumb on it.
class DesktopSwitch extends StatelessWidget {
  const DesktopSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Semantics(
      label: semanticLabel,
      toggled: value,
      child: SizedBox(
        height: 32,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Color(0xFF1C1917)
                : p.textMuted,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? DesignColors.accent
                : p.border,
          ),
          trackOutlineColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.transparent
                : p.borderStrong,
          ),
        ),
      ),
    );
  }
}

/// A small row of mutually exclusive options (Light / Dark / Use system
/// setting). For five choices or fewer.
class DesktopSegmented<T> extends StatelessWidget {
  const DesktopSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Container(
      height: DesktopTokens.controlHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
        border: Border.all(color: p.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0)
              VerticalDivider(width: 1, thickness: 1, color: p.borderStrong),
            _Segment(
              label: options[i].$2,
              selected: options[i].$1 == value,
              onTap: () => onChanged(options[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? p.selected : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: p.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                style: GoogleFonts.plusJakartaSans(
                  color: selected ? p.text : p.textMuted,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain value at the right of a row ("1.0.181", "Connected").
class DesktopSettingValue extends StatelessWidget {
  const DesktopSettingValue(this.text, {super.key, this.tabular = false});

  final String text;
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tabular
          ? DesignType.numeric(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: p.textMuted,
            )
          : GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
    );
  }
}

/// Who is signed in and which shop this is, as the first thing on the
/// Business pane. Replaces the phone's profile card.
class DesktopSettingsProfile extends StatelessWidget {
  const DesktopSettingsProfile({
    super.key,
    required this.name,
    required this.email,
    required this.roleLabel,
    required this.businessName,
    this.branchName = '',
    this.companyCode = '',
    this.isOnline = false,
    this.isLocalWorkspace = false,
    this.onCopyCode,
  });

  final String name;
  final String email;
  final String roleLabel;
  final String businessName;
  final String branchName;
  final String companyCode;
  final bool isOnline;
  final bool isLocalWorkspace;
  final VoidCallback? onCopyCode;

  String get _initial {
    final text = name.trim();
    return text.isEmpty ? '?' : text[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final statusText = isLocalWorkspace
        ? 'Local only'
        : isOnline
            ? 'Connected'
            : 'No network';
    final statusColor = isLocalWorkspace
        ? DesignColors.info
        : isOnline
            ? DesignColors.success
            : DesignColors.warning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: DesktopPanel(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 560;
            final person = Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: DesignColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initial,
                    style: GoogleFonts.sora(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          DesktopChipLabel(label: roleLabel),
                          DesktopChipLabel(
                            label: statusText,
                            dotColor: statusColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );

            final shop = Column(
              crossAxisAlignment:
                  stacked ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  businessName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: stacked ? TextAlign.start : TextAlign.end,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (branchName.isNotEmpty)
                  Text(
                    branchName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (companyCode.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Company code',
                        style: GoogleFonts.plusJakartaSans(
                          color: p.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        companyCode,
                        style: DesignType.numeric(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: p.text,
                        ),
                      ),
                      if (onCopyCode != null)
                        IconButton(
                          key: const ValueKey('desktop-settings-copy-code'),
                          tooltip: 'Copy company code',
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          constraints: const BoxConstraints(
                            minWidth: 30,
                            minHeight: 30,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: onCopyCode,
                          icon: Icon(Icons.copy_rounded, color: p.textMuted),
                        ),
                    ],
                  ),
                ],
              ],
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [person, const SizedBox(height: 14), shop],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: person),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: shop),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A small neutral label with an optional status dot.
class DesktopChipLabel extends StatelessWidget {
  const DesktopChipLabel({super.key, required this.label, this.dotColor});

  final String label;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: p.dark ? p.hover : p.frame,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            maxLines: 1,
            style: GoogleFonts.plusJakartaSans(
              color: p.text,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
