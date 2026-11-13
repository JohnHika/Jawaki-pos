import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';

/// A title row, a hairline and a body that fills the rest of a side panel or a
/// fixed-height dialog. Unlike `DesktopSheetFrame` the body is not wrapped in a
/// scroll view, so forms that bring their own scrolling and pinned save bar
/// (the add product form, a category list) can sit inside it.
class DesktopPanelShell extends StatelessWidget {
  const DesktopPanelShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Defaults to closing the route this panel is shown in.
  final VoidCallback? onClose;

  /// A height that fits a dialog on a short laptop screen.
  static double dialogHeight(BuildContext context, {double preferred = 560}) {
    final available = MediaQuery.sizeOf(context).height - 96;
    return preferred < available ? preferred : available;
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.sora(
                        color: p.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: p.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close (Esc)',
                icon: const Icon(Icons.close_rounded, size: 19),
                onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        Expanded(child: child),
      ],
    );
  }
}
