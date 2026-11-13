import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/adaptive_overlays.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/theme/design_system.dart';

/// Opens [builder] as the phone's bottom sheet exactly as `showModalBottomSheet`
/// would, and as a centred dialog (or side panel) on a computer.
///
/// The phone branch passes every argument straight through, so the phone looks
/// and behaves as it did before.
Future<T?> showSettingsSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = false,
  bool isScrollControlled = false,
  ShapeBorder? shape,
  Color? backgroundColor,
  DesktopSheetStyle desktopStyle = DesktopSheetStyle.dialog,
  double desktopWidth = 560,
}) {
  if (!DesktopLayout.wantsShell(context)) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      shape: shape,
      backgroundColor: backgroundColor,
      builder: builder,
    );
  }
  return showAdaptiveSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    desktopStyle: desktopStyle,
    desktopWidth: desktopWidth,
    builder: builder,
  );
}

/// The title block of a settings sheet. On the phone it is the familiar
/// [SettingsSheetScaffold] with its drag handle; on a computer it is a plain
/// title row with a close button, because a dialog is not dragged.
class SettingsSheetBody extends StatelessWidget {
  const SettingsSheetBody({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (!DesktopLayout.wantsShell(context)) {
      final custom = padding;
      return custom == null
          ? SettingsSheetScaffold(
              title: title,
              subtitle: subtitle,
              child: child,
            )
          : SettingsSheetScaffold(
              title: title,
              subtitle: subtitle,
              padding: custom,
              child: child,
            );
    }
    final p = DesktopPalette.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.sora(
                        color: p.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// The grab bar at the top of a phone bottom sheet. Nothing on a computer.
class SettingsSheetHandle extends StatelessWidget {
  const SettingsSheetHandle({
    super.key,
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (DesktopLayout.wantsShell(context)) return const SizedBox.shrink();
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
