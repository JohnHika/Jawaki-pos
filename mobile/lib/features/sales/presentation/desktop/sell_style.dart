import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../home/presentation/desktop/desktop_command_palette.dart'
    show DesktopKeyCap;

/// Colours and type for the desktop till, taken from the desktop palette so
/// both themes follow the shell. Orange is only ever a fill (Pay), a selection
/// tint or a focus ring; text on the fill is dark ink.
class SellStyle {
  SellStyle(this.p);

  factory SellStyle.of(BuildContext context) =>
      SellStyle(DesktopPalette.of(context));

  final DesktopPalette p;

  bool get dark => p.dark;
  Color get surface => dark ? p.panelAlt : Colors.white;

  /// The ticket sits on a slightly different surface so it reads as the
  /// receipt side of the till without needing a card around it.
  Color get ticket => dark ? p.panel : p.panelAlt;
  Color get accentFill => DesignColors.accent;
  Color get accentFillHover => const Color(0xFFFF8B4D);
  Color get ink => const Color(0xFF1C1917);
  Color get success => dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
  Color get warning => dark ? const Color(0xFFF5C451) : const Color(0xFF92400E);
  Color get danger => dark ? const Color(0xFFF97066) : const Color(0xFFB42318);
  Color get info => dark ? const Color(0xFF7CB0FF) : const Color(0xFF1D4ED8);
  Color tint(Color c) => c.withValues(alpha: dark ? 0.16 : 0.11);

  TextStyle body({
    double size = 13,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? height,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color ?? p.text,
        height: height ?? 1.3,
      );

  TextStyle heading({
    double size = 15,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) =>
      GoogleFonts.sora(
        fontSize: size,
        fontWeight: weight,
        color: color ?? p.text,
        letterSpacing: -0.2,
      );

  TextStyle number({
    double size = 13,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) =>
      DesignType.numeric(
        fontSize: size,
        fontWeight: weight,
        color: color ?? p.text,
      );
}

/// "KES 1,180" or "1,180", with cents only when there are some.
String sellMoney(num value, {bool symbol = true}) => formatMoney(
      value,
      symbol: symbol ? 'KES ' : '',
      decimals: value.toDouble() % 1 != 0,
    );

/// "2", "0.5": a quantity without trailing zeros.
String sellQty(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');

/// Builds [builder] with whether the pointer is over it.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: widget.builder(context, _hovered),
      );
}

/// A small key label ("F9") shown beside an action.
class SellKey extends StatelessWidget {
  const SellKey(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => DesktopKeyCap(label: label);
}

/// The one filled orange button on a screen. Dark ink on orange.
class SellPrimaryButton extends StatelessWidget {
  const SellPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.keyHint,
    this.loading = false,
    this.height = 56,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? keyHint;
  final bool loading;
  final double height;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    final enabled = onPressed != null && !loading;
    return HoverBuilder(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered) => Material(
        color: !enabled
            ? (s.dark ? const Color(0xFF3A2F28) : const Color(0xFFEADFD3))
            : (hovered ? s.accentFillHover : s.accentFill),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.transparent,
          child: SizedBox(
            height: height,
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: s.ink,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            Icon(
                              icon,
                              size: 20,
                              color: enabled ? s.ink : s.p.textFaint,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.sora(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: enabled ? s.ink : s.p.textFaint,
                              ),
                            ),
                          ),
                          if (keyHint != null && enabled) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: s.ink.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                keyHint!,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: s.ink.withValues(alpha: 0.8),
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
  }
}

/// A quiet text-and-icon button used for secondary actions in the till.
class SellQuietButton extends StatelessWidget {
  const SellQuietButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.keyHint,
    this.color,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? keyHint;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    final fg = onPressed == null ? s.p.textFaint : (color ?? s.p.textMuted);
    final button = HoverBuilder(
      cursor: onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      builder: (context, hovered) => Material(
        color: hovered && onPressed != null ? s.p.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: s.body(size: 12.5, weight: FontWeight.w600, color: fg),
                ),
                if (keyHint != null) ...[
                  const SizedBox(width: 6),
                  SellKey(keyHint!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// A message strip shown inside the till: never a toast that disappears
/// before it is read.
enum SellNoticeKind { info, warning, error }

class SellNotice {
  const SellNotice(
    this.message, {
    this.kind = SellNoticeKind.info,
    this.actions = const [],
    this.id,
  });

  final String message;
  final SellNoticeKind kind;
  final List<SellNoticeAction> actions;

  /// Lets the page tell whether the notice on screen is still the same one.
  final Object? id;
}

class SellNoticeAction {
  const SellNoticeAction(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;
}

class SellNoticeBanner extends StatelessWidget {
  const SellNoticeBanner({super.key, required this.notice, this.onClose});

  final SellNotice notice;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final s = SellStyle.of(context);
    final color = switch (notice.kind) {
      SellNoticeKind.info => s.info,
      SellNoticeKind.warning => s.warning,
      SellNoticeKind.error => s.danger,
    };
    final icon = switch (notice.kind) {
      SellNoticeKind.info => Icons.info_outline_rounded,
      SellNoticeKind.warning => Icons.warning_amber_rounded,
      SellNoticeKind.error => Icons.error_outline_rounded,
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: s.tint(color),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice.message,
              style: s.body(size: 12.5, weight: FontWeight.w600),
            ),
          ),
          for (final action in notice.actions)
            SellQuietButton(
              label: action.label,
              onPressed: action.onPressed,
              color: s.p.text,
            ),
          if (onClose != null)
            IconButton(
              tooltip: 'Dismiss (Esc)',
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: Icon(Icons.close_rounded, color: s.p.textMuted),
            ),
        ],
      ),
    );
  }
}
