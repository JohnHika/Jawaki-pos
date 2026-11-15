import 'package:flutter/material.dart';

import 'desktop_layout.dart';

/// The bordered, rounded surface a [DesktopDataTable] (or any list that fills
/// the leftover height) sits in. Unlike `DesktopPanel` it passes its height
/// constraint through, so an `Expanded` child works.
class DesktopTableFrame extends StatelessWidget {
  const DesktopTableFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.dark ? p.panelAlt : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: child,
    );
  }
}
